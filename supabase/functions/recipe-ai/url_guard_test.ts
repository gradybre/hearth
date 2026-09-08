import { assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1';

import {
  assertHostAllowed,
  assertReadableType,
  assertUrlShape,
  fetchGuarded,
  isBlockedAddress,
  MAX_HOPS,
  readCapped,
  UrlRefused,
} from './url_guard.ts';

/// Fetching a pasted link without fetching whatever it points at (R14).
///
/// Every test here runs without a network. That is deliberate and it is the
/// handoff's own instruction: the way to find out whether this function will
/// connect to the metadata service is *not* to point it at the metadata
/// service. The addresses are judged as data, and the one function that must
/// touch the network takes its transport as an argument.

const publicOnly = (host: string) =>
  Promise.resolve(host === 'evil.example' ? ['127.0.0.1'] : ['93.184.216.34']);

Deno.test('an address inside the network is refused', async (t) => {
  const blocked: Record<string, string> = {
    'loopback': '127.0.0.1',
    'loopback, not .1': '127.99.42.7',
    'the metadata service': '169.254.169.254',
    'link-local generally': '169.254.0.1',
    'private 10': '10.0.0.1',
    'private 172.16': '172.16.5.4',
    'private 172.31': '172.31.255.254',
    'private 192.168': '192.168.1.1',
    'this network': '0.0.0.0',
    'carrier NAT': '100.64.0.1',
    'protocol assignments': '192.0.0.8',
    'benchmarking': '198.18.0.1',
    'multicast': '224.0.0.1',
    'broadcast': '255.255.255.255',
    'IPv6 loopback': '::1',
    'IPv6 unspecified': '::',
    'IPv6 unique-local': 'fd00::1',
    'IPv6 link-local': 'fe80::1',
    'IPv6 link-local with a zone': 'fe80::1%eth0',
    'IPv6 multicast': 'ff02::1',
    // The spellings a list of strings would miss.
    'loopback in an IPv6 hat': '::ffff:127.0.0.1',
    'metadata in an IPv6 hat': '::ffff:169.254.169.254',
    'private in an IPv6 hat': '::ffff:10.0.0.1',
  };
  for (const [name, address] of Object.entries(blocked)) {
    await t.step(name, () => {
      assertEquals(isBlockedAddress(address), true, `${address} was allowed`);
    });
  }
});

Deno.test('and an ordinary public address is not', async (t) => {
  const allowed = ['93.184.216.34', '1.1.1.1', '172.32.0.1', '192.169.0.1', '2606:2800:220:1:248:1893:25c8:1946'];
  for (const address of allowed) {
    await t.step(address, () => {
      assertEquals(isBlockedAddress(address), false, `${address} was refused`);
    });
  }
});

Deno.test('172.15 and 172.32 are public — the private range is 16 to 31', () => {
  // An off-by-one here refuses real sites or admits real internal ones, and
  // both failures are quiet.
  assertEquals(isBlockedAddress('172.15.255.255'), false);
  assertEquals(isBlockedAddress('172.16.0.0'), true);
  assertEquals(isBlockedAddress('172.31.255.255'), true);
  assertEquals(isBlockedAddress('172.32.0.0'), false);
});

Deno.test('the shape of the link is checked before anything else', async (t) => {
  await t.step('a file scheme is refused', () => {
    assertThrows(() => assertUrlShape('file:///etc/passwd'), UrlRefused);
  });
  await t.step('and so is anything else exotic', () => {
    assertThrows(() => assertUrlShape('gopher://example.com/'), UrlRefused);
    assertThrows(() => assertUrlShape('data:text/html,hi'), UrlRefused);
  });
  await t.step('credentials in the link are refused', () => {
    // They would be sent to whatever the link turns out to reach.
    assertThrows(
      () => assertUrlShape('https://user:secret@example.com/recipe'),
      UrlRefused,
    );
    assertThrows(
      () => assertUrlShape('https://user@example.com/recipe'),
      UrlRefused,
    );
  });
  await t.step('and a plain recipe link is not', () => {
    assertEquals(
      assertUrlShape('https://example.com/recipes/chilli').hostname,
      'example.com',
    );
  });
});

Deno.test('a name is judged by what it resolves to', async (t) => {
  await t.step('a public name is allowed', async () => {
    await assertHostAllowed(new URL('https://example.com/'), publicOnly);
  });

  await t.step('a public name pointing inward is not', async () => {
    // The whole point of resolving. "localtest.me" and friends are ordinary
    // public names whose records answer 127.0.0.1, and nothing about the URL
    // itself gives that away.
    await assertRejects(
      () => assertHostAllowed(new URL('https://evil.example/'), publicOnly),
      UrlRefused,
    );
  });

  await t.step('a name answering with two addresses is judged by the worst', async () => {
    await assertRejects(
      () =>
        assertHostAllowed(
          new URL('https://mixed.example/'),
          () => Promise.resolve(['93.184.216.34', '10.1.2.3']),
        ),
      UrlRefused,
    );
  });

  await t.step('a name that resolves to nothing is refused, not fetched', async () => {
    await assertRejects(
      () =>
        assertHostAllowed(new URL('https://void.example/'), () => Promise.resolve([])),
      UrlRefused,
    );
  });

  await t.step('a lookup that fails is refused rather than retried unchecked', async () => {
    await assertRejects(
      () =>
        assertHostAllowed(
          new URL('https://broken.example/'),
          () => Promise.reject(new Error('SERVFAIL')),
        ),
      UrlRefused,
    );
  });

  await t.step('and "localhost" never reaches a resolver that might allow it', async () => {
    await assertRejects(
      () =>
        assertHostAllowed(
          new URL('http://127.0.0.1:54321/rest/v1/foods'),
          () => Promise.reject(new Error('should not be asked')),
        ),
      UrlRefused,
    );
  });
});

Deno.test('what comes back is bounded', async (t) => {
  await t.step('a body larger than the cap is cut, not buffered whole', async () => {
    // 300 chunks of 1 KB, capped at 1 KB. The old code read all 300 into
    // memory and then took the first slice of it.
    let produced = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        produced++;
        if (produced > 300) return controller.close();
        controller.enqueue(new Uint8Array(1024).fill(65));
      },
    });
    const text = await readCapped(new Response(body), 1024);

    assertEquals(text.length, 1024);
    // Stopped reading rather than read-then-trimmed: a handful of chunks may
    // be in flight, but nothing like all three hundred.
    assertEquals(produced < 10, true, `read ${produced} chunks past the cap`);
  });

  await t.step('a body under the cap arrives whole', async () => {
    assertEquals(await readCapped(new Response('hello'), 1024), 'hello');
  });

  await t.step('an empty body is empty, not an error', async () => {
    assertEquals(await readCapped(new Response(null), 1024), '');
  });
});

Deno.test('only something a recipe could be written in is read', async (t) => {
  await t.step('html is fine', () => {
    assertReadableType(
      new Response('', { headers: { 'content-type': 'text/html; charset=utf-8' } }),
    );
  });
  await t.step('a missing type is allowed, being ordinary on small sites', () => {
    assertReadableType(new Response(''));
  });
  await t.step('a PDF is not', () => {
    assertThrows(
      () =>
        assertReadableType(
          new Response('', { headers: { 'content-type': 'application/pdf' } }),
        ),
      UrlRefused,
    );
  });
  await t.step('and neither is a tarball', () => {
    assertThrows(
      () =>
        assertReadableType(
          new Response('', { headers: { 'content-type': 'application/gzip' } }),
        ),
      UrlRefused,
    );
  });
});

Deno.test('every redirect is checked, not just the first URL', async (t) => {
  const asked: string[] = [];
  const modes: (string | undefined)[] = [];
  const redirecting = (map: Record<string, string>): typeof fetch =>
    ((input: string | URL | Request, init?: RequestInit) => {
      const url = `${input}`;
      asked.push(url);
      modes.push(init?.redirect);
      const to = map[url];
      if (to) {
        return Promise.resolve(
          new Response(null, { status: 302, headers: { location: to } }),
        );
      }
      return Promise.resolve(
        new Response('<h1>Chilli</h1>', {
          headers: { 'content-type': 'text/html' },
        }),
      );
    }) as typeof fetch;

  await t.step('a public page redirecting inward is refused at the hop', async () => {
    asked.length = 0;
    await assertRejects(
      () =>
        fetchGuarded('https://example.com/r', {
          fetch: redirecting({
            'https://example.com/r': 'http://169.254.169.254/latest/meta-data/',
          }),
          resolve: publicOnly,
        }),
      UrlRefused,
    );
    // It asked the first page and stopped. The old code followed this hop
    // inside `fetch` and never saw where it went.
    assertEquals(asked, ['https://example.com/r']);
  });

  await t.step('a redirect loop ends rather than spinning', async () => {
    asked.length = 0;
    await assertRejects(
      () =>
        fetchGuarded('https://example.com/a', {
          fetch: redirecting({
            'https://example.com/a': 'https://example.com/b',
            'https://example.com/b': 'https://example.com/a',
          }),
          resolve: publicOnly,
        }),
      UrlRefused,
    );
    assertEquals(asked.length, MAX_HOPS + 1);
  });

  await t.step('an ordinary redirect is followed', async () => {
    asked.length = 0;
    const text = await fetchGuarded('https://example.com/old', {
      fetch: redirecting({ 'https://example.com/old': 'https://example.com/new' }),
      resolve: publicOnly,
    });
    assertEquals(text, '<h1>Chilli</h1>');
    assertEquals(asked, ['https://example.com/old', 'https://example.com/new']);
  });

  await t.step('a relative redirect resolves against the hop it came from', async () => {
    asked.length = 0;
    const text = await fetchGuarded('https://example.com/recipes/old', {
      fetch: redirecting({ 'https://example.com/recipes/old': '../new' }),
      resolve: publicOnly,
    });
    assertEquals(text, '<h1>Chilli</h1>');
    assertEquals(asked[1], 'https://example.com/new');
  });

  await t.step('and the runtime is told not to follow them itself', async () => {
    // Without this the hop checks above are dead code and the tests over them
    // prove nothing: `redirect: 'follow'` means a real fetch resolves the
    // whole chain internally and hands back the final page, so a 302 to
    // 169.254.169.254 is followed before this function ever sees it. A fake
    // transport cannot show that — it returns whatever it is told to — so
    // the instruction itself is what gets asserted.
    asked.length = 0;
    modes.length = 0;
    await fetchGuarded('https://example.com/old', {
      fetch: redirecting({ 'https://example.com/old': 'https://example.com/new' }),
      resolve: publicOnly,
    });
    assertEquals(modes, ['manual', 'manual']);
  });

  await t.step('a redirect to nowhere says so', async () => {
    await assertRejects(
      () =>
        fetchGuarded('https://example.com/r', {
          fetch: (() =>
            Promise.resolve(new Response(null, { status: 302 }))) as typeof fetch,
          resolve: publicOnly,
        }),
      UrlRefused,
    );
  });

  await t.step('a scheme change on a redirect is checked too', async () => {
    await assertRejects(
      () =>
        fetchGuarded('https://example.com/r', {
          fetch: redirecting({ 'https://example.com/r': 'file:///etc/passwd' }),
          resolve: publicOnly,
        }),
      UrlRefused,
    );
  });
});

Deno.test('nothing is fetched when the address is refused', async () => {
  // The order that matters: a refusal must cost no request at all, or the
  // refusal is only a refusal to *read* the answer.
  let called = false;
  await assertRejects(
    () =>
      fetchGuarded('http://169.254.169.254/latest/meta-data/', {
        fetch: (() => {
          called = true;
          return Promise.resolve(new Response(''));
        }) as typeof fetch,
        resolve: publicOnly,
      }),
    UrlRefused,
  );
  assertEquals(called, false, 'it connected before deciding not to');
});

Deno.test('a page that fails says what happened without inventing a page', async () => {
  await assertRejects(
    () =>
      fetchGuarded('https://example.com/gone', {
        fetch: (() =>
          Promise.resolve(new Response('nope', { status: 404 }))) as typeof fetch,
        resolve: publicOnly,
      }),
    UrlRefused,
    '404',
  );
});
