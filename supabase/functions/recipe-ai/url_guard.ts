/// Fetching a URL somebody pasted, without fetching whatever it points at
/// (spec §8.1, R14).
///
/// The Edge Function runs inside Supabase's network with the secret key and a
/// route to the project's own Postgres. `fetch(userUrl)` therefore is not a
/// request for a recipe page — it is an offer to make a request *from there*,
/// to anywhere, on behalf of whoever pasted the link. `http://169.254.169.254/`
/// is the cloud metadata service. `http://127.0.0.1:54321/` is PostgREST.
/// Neither is a recipe, and the old code would have read both back as one.
///
/// Its own file, and pure where it can be: the interesting half is a decision
/// about an address, and a decision about an address can be tested exhaustively
/// without a network, a server, or a single real request. The half that must
/// touch the network takes its transport as an argument for the same reason —
/// testing this against real internal addresses would mean probing them.

/// What a page may come back as.
///
/// A recipe is words. A tarball, an image and a PDF are not, and reading one
/// as text is a way to spend the model's budget on nothing.
const ALLOWED_TYPES = [
  'text/html',
  'application/xhtml+xml',
  'text/plain',
];

/// How many times a site may hand us on before we stop.
///
/// Redirects are ordinary — a shortened link, a trailing slash, http to https
/// — so refusing them outright would refuse half the real web. Five is more
/// than any recipe site needs and few enough that a loop ends quickly.
export const MAX_HOPS = 5;

/// The most of a page we will read, streaming.
///
/// Enforced against the bytes as they arrive rather than against
/// `content-length`, which is a claim the server makes about itself and is
/// absent entirely from a chunked response.
export const MAX_BYTES = 2 * 1024 * 1024;

/// Why a URL was refused, in words a person can act on.
export class UrlRefused extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UrlRefused';
  }
}

/// Whether this is an address the function must never connect to.
///
/// Written against the parsed octets rather than against the text, because
/// the text has more spellings than anybody can list: `127.0.0.1`,
/// `127.1`, `0x7f.1`, `2130706433` and `[::ffff:127.0.0.1]` are one address
/// with five names, and a blocklist of strings catches the first and none of
/// the rest.
export function isBlockedAddress(address: string): boolean {
  const v4 = parseIpv4(address);
  if (v4) return isBlockedIpv4(v4);

  const v6 = parseIpv6(address);
  if (v6) {
    // An IPv4 address wearing an IPv6 hat — ::ffff:127.0.0.1 and friends.
    // Judged as what it actually reaches.
    const mapped = mappedIpv4(v6);
    if (mapped) return isBlockedIpv4(mapped);
    return isBlockedIpv6(v6);
  }

  // Not an address at all. Names are resolved and their answers judged; see
  // `assertHostAllowed`.
  return false;
}

function isBlockedIpv4(octets: number[]): boolean {
  const [a, b] = octets;
  return (
    a === 0 || // 0.0.0.0/8 — "this network"
    a === 10 || // private
    a === 127 || // loopback
    (a === 100 && b >= 64 && b <= 127) || // 100.64.0.0/10, carrier NAT
    (a === 169 && b === 254) || // link-local, and the metadata service in it
    (a === 172 && b >= 16 && b <= 31) || // private
    (a === 192 && b === 0) || // 192.0.0.0/24 protocol assignments
    (a === 192 && b === 168) || // private
    (a === 198 && (b === 18 || b === 19)) || // benchmarking
    a >= 224 // multicast and reserved, up to and including 255.255.255.255
  );
}

function isBlockedIpv6(groups: number[]): boolean {
  const [first] = groups;
  const isLoopback = groups.slice(0, 7).every((g) => g === 0) &&
    groups[7] === 1;
  const isUnspecified = groups.every((g) => g === 0);
  return (
    isLoopback ||
    isUnspecified ||
    (first & 0xfe00) === 0xfc00 || // fc00::/7 unique-local
    (first & 0xffc0) === 0xfe80 || // fe80::/10 link-local
    (first & 0xff00) === 0xff00 // ff00::/8 multicast
  );
}

/// The IPv4 address inside an IPv4-mapped, IPv4-compatible, or NAT64 address.
function mappedIpv4(groups: number[]): number[] | null {
  // 64:ff9b::/96, the well-known NAT64 prefix (RFC 6052). On a network that
  // runs NAT64 this is simply another way to spell an IPv4 address, and
  // `64:ff9b::7f00:1` is another way to spell the loopback — the same "one
  // address, several names" argument as `::ffff:` above, one prefix along.
  if (
    groups[0] === 0x0064 && groups[1] === 0xff9b &&
    groups[2] === 0 && groups[3] === 0 && groups[4] === 0 && groups[5] === 0
  ) {
    return [groups[6] >> 8, groups[6] & 0xff, groups[7] >> 8, groups[7] & 0xff];
  }

  const leadingZero = groups.slice(0, 5).every((g) => g === 0);
  if (!leadingZero) return null;
  if (groups[5] !== 0xffff && groups[5] !== 0) return null;
  // ::/128 and ::1 are not IPv4 and are judged as IPv6.
  if (groups[5] === 0 && groups[6] === 0 && groups[7] <= 1) return null;
  return [
    groups[6] >> 8,
    groups[6] & 0xff,
    groups[7] >> 8,
    groups[7] & 0xff,
  ];
}

/// Dotted-quad only, deliberately — and safe to be, for a reason worth
/// writing down because it is not obvious and it is load-bearing.
///
/// The legacy spellings — `127.1`, `0x7f000001`, `2130706433`, `017700000001`
/// — never reach here as themselves. The WHATWG URL parser canonicalises the
/// host, so `new URL('http://0x7f000001/').hostname` is already the string
/// `127.0.0.1` before this function is called. Writing a second
/// `inet_aton` here would be a second implementation that eventually
/// disagrees with the first, which is precisely the class of bug this file
/// exists to close. There are tests over the real path for exactly this.
///
/// The contract, therefore: [isBlockedAddress] expects a host as a `URL`
/// gives it, not as a person typed it.
function parseIpv4(text: string): number[] | null {
  const parts = text.split('.');
  if (parts.length !== 4) return null;
  const octets: number[] = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    const value = Number(part);
    if (value > 255) return null;
    octets.push(value);
  }
  return octets;
}

function parseIpv6(text: string): number[] | null {
  let body = text;
  if (body.startsWith('[') && body.endsWith(']')) body = body.slice(1, -1);
  if (!body.includes(':')) return null;
  // A zone id (fe80::1%eth0) names an interface on this machine, which is
  // reason enough on its own; it is dropped so the address still parses.
  const percent = body.indexOf('%');
  if (percent >= 0) body = body.slice(0, percent);

  // A trailing dotted quad — ::ffff:127.0.0.1 — becomes two groups.
  const lastColon = body.lastIndexOf(':');
  const tail = body.slice(lastColon + 1);
  const quad = parseIpv4(tail);
  if (quad) {
    body = body.slice(0, lastColon + 1) +
      ((quad[0] << 8) | quad[1]).toString(16) + ':' +
      ((quad[2] << 8) | quad[3]).toString(16);
  }

  const halves = body.split('::');
  if (halves.length > 2) return null;

  const read = (part: string): number[] | null => {
    if (part === '') return [];
    const groups: number[] = [];
    for (const group of part.split(':')) {
      if (!/^[0-9a-fA-F]{1,4}$/.test(group)) return null;
      groups.push(parseInt(group, 16));
    }
    return groups;
  };

  const head = read(halves[0]);
  const rest = halves.length === 2 ? read(halves[1]) : null;
  if (head === null) return null;
  if (halves.length === 1) return head.length === 8 ? head : null;
  if (rest === null) return null;
  const gap = 8 - head.length - rest.length;
  if (gap < 1) return null;
  return [...head, ...new Array(gap).fill(0), ...rest];
}

/// Resolves a name and returns its addresses, or the literal itself.
export type Resolve = (host: string) => Promise<string[]>;

/// Checks the URL itself, before anything is resolved or connected.
///
/// Throws [UrlRefused] with a sentence worth showing somebody.
export function assertUrlShape(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new UrlRefused('That is not a link. Paste the page address, or the recipe text.');
  }

  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    throw new UrlRefused('Only http and https links can be read. Paste the recipe text instead.');
  }

  // A username or password in the URL is sent to whatever the URL turns out
  // to point at. Nothing legitimate needs it, and a recipe page never does.
  if (url.username !== '' || url.password !== '') {
    throw new UrlRefused('That link carries a username or password, so it will not be opened.');
  }

  return url;
}

/// Checks where a hostname actually goes.
///
/// A literal address is judged directly. A name is resolved and **every**
/// answer is judged, because a name that answers with two addresses is only
/// as safe as its worst one.
///
/// This is not a complete defence against DNS rebinding, and saying so is
/// better than implying otherwise: the name is resolved here and resolved
/// again by `fetch`, and a record with a one-second lifetime can differ
/// between the two. Closing that needs the connection itself pinned to a
/// checked address, which Deno's `fetch` does not expose. What this does
/// close is the whole of the direct case — a pasted internal address, and a
/// public name that simply points inward — which is every version of this
/// anybody has actually pasted.
export async function assertHostAllowed(
  url: URL,
  resolve: Resolve,
): Promise<void> {
  const host = url.hostname;

  if (isBlockedAddress(host)) {
    throw new UrlRefused(`${host} is not a public address, so it will not be opened.`);
  }

  // A literal that parsed and was allowed needs no resolving.
  if (parseIpv4(host) || parseIpv6(host)) return;

  let addresses: string[];
  try {
    addresses = await resolve(host);
  } catch {
    throw new UrlRefused(`${host} could not be looked up. Check the link, or paste the recipe text.`);
  }

  if (addresses.length === 0) {
    throw new UrlRefused(`${host} does not resolve to anything.`);
  }
  for (const address of addresses) {
    if (isBlockedAddress(address)) {
      throw new UrlRefused(`${host} points inside the network, so it will not be opened.`);
    }
  }
}

/// A response body, read as text and stopped at [MAX_BYTES].
///
/// Streamed rather than buffered. `await response.text()` reads the whole
/// body into memory and *then* takes the first two megabytes of it, so a
/// server answering with two gigabytes is two gigabytes in the function's
/// memory before the limit is consulted at all. Content-length would not help:
/// it is the server's claim about itself, and a chunked response has none.
export async function readCapped(
  response: Response,
  maxBytes = MAX_BYTES,
): Promise<string> {
  const body = response.body;
  if (!body) return '';

  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (total < maxBytes) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      const room = maxBytes - total;
      chunks.push(value.length > room ? value.subarray(0, room) : value);
      total += Math.min(value.length, room);
    }
  } finally {
    // Cancelled rather than left open: we have what we are going to read, and
    // the rest of a two-gigabyte body is not worth the socket.
    await reader.cancel().catch(() => {});
  }

  const joined = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    joined.set(chunk, at);
    at += chunk.length;
  }
  return new TextDecoder('utf-8', { fatal: false }).decode(joined);
}

/// Whether the response is the sort of thing a recipe is written in.
export function assertReadableType(response: Response): void {
  const header = response.headers.get('content-type') ?? '';
  const type = header.split(';')[0].trim().toLowerCase();
  // Absent is allowed: plenty of small sites send nothing, and the byte cap
  // and the tag stripper already bound what an unexpected body can do.
  if (type === '') return;
  if (!ALLOWED_TYPES.includes(type)) {
    throw new UrlRefused(`That link is ${type}, not a web page. Paste the recipe text instead.`);
  }
}

export interface GuardedFetch {
  fetch: typeof fetch;
  resolve: Resolve;
}

/// Fetches [raw], checking every address it is sent to along the way.
///
/// Redirects are followed by hand. `redirect: 'follow'` hands the whole check
/// back to the server being checked: a public page answering `302` to
/// `http://127.0.0.1:54321/` was fetched by the old code with no second
/// thought, because only the first URL had ever been looked at. Every hop is
/// now shape-checked and address-checked exactly as the first one was.
export async function fetchGuarded(
  raw: string,
  { fetch: doFetch, resolve }: GuardedFetch,
  { timeoutMs = 10_000, maxBytes = MAX_BYTES }: {
    timeoutMs?: number;
    maxBytes?: number;
  } = {},
): Promise<string> {
  let url = assertUrlShape(raw);

  // One budget for the whole chain rather than one per hop. Six hops of ten
  // seconds each is a minute a hostile site can hold the function for, and it
  // gets that by doing nothing more clever than redirecting slowly.
  const deadline = Date.now() + timeoutMs;

  for (let hop = 0; hop <= MAX_HOPS; hop++) {
    await assertHostAllowed(url, resolve);

    const left = deadline - Date.now();
    if (left <= 0) throw new UrlRefused('That link took too long to answer.');

    const response = await doFetch(url, {
      headers: { 'user-agent': 'Hearth/1.0 (household recipe app)' },
      // Manual, so the next hop comes back here to be checked rather than
      // being followed by the runtime on our behalf.
      redirect: 'manual',
      signal: AbortSignal.timeout(left),
    });

    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');
      // Read to completion or cancelled, either way not left dangling.
      await response.body?.cancel().catch(() => {});
      if (!location) {
        throw new UrlRefused('That page redirected to nowhere.');
      }
      if (hop === MAX_HOPS) {
        throw new UrlRefused('That link redirects too many times.');
      }
      // Relative locations are ordinary, so it is resolved against the hop it
      // came from — and then checked from scratch, shape and all.
      url = assertUrlShape(new URL(location, url).toString());
      continue;
    }

    if (!response.ok) {
      await response.body?.cancel().catch(() => {});
      throw new UrlRefused(`That page returned ${response.status}.`);
    }

    try {
      assertReadableType(response);
    } catch (refusal) {
      // The socket is ours to close whether we read the body or not. Every
      // other exit from this loop cancels; this one did not, so a site
      // answering with a PDF left a connection open behind the refusal.
      await response.body?.cancel().catch(() => {});
      throw refusal;
    }
    return await readCapped(response, maxBytes);
  }

  // Unreachable: the hop counter throws first. Here so the function has one
  // exit rather than an implicit undefined.
  throw new UrlRefused('That link redirects too many times.');
}
