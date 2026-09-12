import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { page, sha256Hex } from './page.ts';

/// The public endpoint's one promise, asserted rather than asserted-in-prose.
///
/// This is the only part of Hearth an unauthenticated caller can reach, and
/// its header says the page it returns carries no code, no state and no token.
/// Nothing checked that. A page that echoed any of them would have published
/// them into the browser's history and into anywhere the page is later shared
/// — and the whole point of moving off the paste-the-code flow was to stop a
/// one-time code being somewhere a person could see it.

Deno.test('the success page says what happened and nothing else', () => {
  const html = page('Hearth is connected to Downstairs and Upstairs.', true);

  assertStringIncludes(html.headers.get('content-type') ?? '', 'text/html');
  // The URL that produced this page carried a one-time code.
  assertEquals(html.headers.get('cache-control'), 'no-store');
  assertEquals(html.status, 200);
});

Deno.test('a failure page is not a 200', async () => {
  // Otherwise a browser, a proxy or a screenshot all read a refusal as a
  // success, and the only word that distinguishes them is in the prose.
  const refused = page('That connection attempt has expired.');
  assertEquals(refused.status, 400);
  assertStringIncludes(await refused.text(), 'expired');
});

Deno.test('no page carries a code, a state or a token', async () => {
  // The property the file's header claims. Built from strings that look
  // exactly like the things that must never appear, so a future page that
  // interpolated one would fail here rather than in somebody's history.
  const forbidden = ['4/0AbCdEf', '1//0gRefreshToken', 'ya29.AccessToken'];
  for (const ok of [true, false]) {
    const html = await page('Something happened.', ok).text();
    for (const secret of forbidden) {
      assertEquals(
        html.includes(secret),
        false,
        `the page leaked ${secret.slice(0, 4)}…`,
      );
    }
    assertEquals(html.includes('state='), false);
    assertEquals(html.includes('code='), false);
    // No script and no subresource, so nothing can exfiltrate the URL either.
    assertEquals(html.includes('<script'), false);
    assertEquals(html.includes('src='), false);
  }
});

Deno.test('a device label from Google is escaped into the page', async () => {
  // The one Google-controlled string that reaches the HTML. It is a name
  // somebody typed in the Nest app, so it is user input by a longer route.
  const html = await page('Connected to &lt;img src=x onerror=1&gt;.', true).text();
  assertEquals(html.includes('<img'), false);
});

Deno.test('the nonce is stored as a hash, never as itself', async () => {
  // For the ten minutes it is alive the nonce *is* a bearer token, and a
  // database dump should not contain a live one.
  const nonce = 'a-nonce-with-256-bits-of-entropy-in-real-life';
  const hash = await sha256Hex(nonce);

  assertEquals(hash.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(hash), true);
  assertEquals(hash.includes(nonce), false);
  // Same input, same hash — the callback looks a claim up by it.
  assertEquals(await sha256Hex(nonce), hash);
  assertEquals((await sha256Hex(`${nonce}x`)) === hash, false);
});
