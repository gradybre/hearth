import assert from 'node:assert/strict';

// Proves the route establishes *who is calling* before it does anything a
// caller could spend or steer: no socket is opened, no credential is read,
// no model is contacted and no household data is written. A resolved
// household id is the only accepted proof of identity — there is no JWT
// decoding here and there must be none in the route.
//
// Imported with a query so this file instantiates the module independently of
// the walmart route test, which stubs the same globals.

const HOUSEHOLD = '3f6b1c2e-9a4d-4b8e-8c0a-1d2e3f4a5b6c';
const AUTH = 'Bearer fixture.caller.token';
const SERVICE_SECRET = 'EXAMPLE_ONLY_NOT_A_REAL_SECRET';
const IMAGE = 'data:image/png;base64,iVBORw0KGgo=';
const UPSTREAM_MARKER = 'UPSTREAM-DETAIL-SHOULD-NOT-LEAK';

const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });

Deno.test('Recipe route proves the caller before it spends', async (t) => {
  const originalServe = Deno.serve;
  const originalGet = Deno.env.get;
  const originalFetch = globalThis.fetch;
  let handler: ((request: Request) => Promise<Response>) | undefined;

  const calls: { url: string; init: RequestInit }[] = [];
  const fullEnv: Record<string, string> = {
    ANTHROPIC_API_KEY: 'EXAMPLE_ONLY_NOT_A_REAL_KEY',
    SUPABASE_URL: 'https://hearth-fixture.invalid',
    SUPABASE_SERVICE_ROLE_KEY: SERVICE_SECRET,
  };
  let env: Record<string, string> = { ...fullEnv };
  let household: () => Promise<Response> = () =>
    Promise.resolve(json(HOUSEHOLD));

  const reset = () => {
    calls.length = 0;
    env = { ...fullEnv };
    household = () => Promise.resolve(json(HOUSEHOLD));
  };

  Deno.serve = ((fn: unknown) => {
    assert.equal(typeof fn, 'function');
    handler = fn as typeof handler;
    return {} as Deno.HttpServer;
  }) as typeof Deno.serve;

  Deno.env.get = (name: string) => env[name];

  globalThis.fetch = ((input: unknown, init: RequestInit = {}) => {
    const url = String(input);
    calls.push({ url, init });
    if (url.endsWith('/rpc/current_household_id')) return household();
    if (url.endsWith('/rpc/reserve_ai_spend')) {
      return Promise.resolve(json([{
        reservation_id: 'fixture-reservation',
        spent_usd: 0,
        reserved_usd: 0,
        allowed: true,
      }]));
    }
    if (url.endsWith('/rpc/settle_ai_spend')) {
      return Promise.resolve(json([{ cost_usd: 0.001 }]));
    }
    if (url.endsWith('/rpc/release_ai_spend')) {
      return Promise.resolve(json(null));
    }
    if (url === 'https://api.anthropic.com/v1/messages') {
      return Promise.resolve(json({
        content: [{
          type: 'tool_use',
          input: {
            walmart_candidates: [{
              url: 'walmart.com/ip/10450479',
              source: 'screenshot',
              uncertain: false,
            }],
            walmart_unreadable: false,
            servings: [],
            title: 'Fixture',
            sections: [],
          },
        }],
        usage: { input_tokens: 100, output_tokens: 50 },
        stop_reason: 'tool_use',
      }));
    }
    throw new Error(`Unexpected external call: ${url}`);
  }) as unknown as typeof fetch;

  const request = async (
    body: unknown,
    authorization: string | null = AUTH,
  ) => {
    assert.ok(handler);
    const headers: Record<string, string> = {
      'content-type': 'application/json',
    };
    if (authorization !== null) headers.authorization = authorization;
    const response = await handler(
      new Request('https://hearth-fixture.invalid/functions/v1/recipe-ai', {
        method: 'POST',
        headers,
        body: typeof body === 'string' ? body : JSON.stringify(body),
      }),
    );
    const text = await response.text();
    return {
      response,
      raw: text,
      body: text ? JSON.parse(text) as Record<string, unknown> : {},
    };
  };

  const url = (suffix: string) => (call: { url: string }) =>
    call.url.endsWith(suffix);
  const reserved = () => calls.filter(url('/rpc/reserve_ai_spend'));
  const modelCalls = () =>
    calls.filter((c) => c.url === 'https://api.anthropic.com/v1/messages');
  const leaks = (raw: string) =>
    raw.includes(SERVICE_SECRET) || raw.includes(UPSTREAM_MARKER) ||
    raw.includes('EXAMPLE_ONLY_NOT_A_REAL_KEY');

  try {
    await import('./index.ts?auth-route');

    await t.step('a request with no usable bearer never reaches the network', async () => {
      const headers = [
        null,
        '',
        '   ',
        'Bearer',
        'Bearer ',
        'Bearer    ',
        'Basic Zml4dHVyZQ==',
        'fixture.caller.token',
        'Bearer one two',
      ];
      for (const authorization of headers) {
        reset();
        const result = await request(
          { mode: 'walmart', images: [IMAGE] },
          authorization,
        );
        assert.equal(result.response.status, 401);
        assert.equal(calls.length, 0);
        assert.equal(typeof result.body.error, 'string');
        assert.ok(!leaks(result.raw));
      }
    });

    await t.step('the household is resolved with the caller\'s own token, first', async () => {
      reset();
      const result = await request({ mode: 'label', images: [IMAGE] });
      assert.equal(result.response.status, 200);

      const proof = calls[0];
      assert.ok(url('/rpc/current_household_id')(proof));
      assert.equal(proof.init.method, 'POST');
      assert.equal(String(proof.init.body ?? ''), '{}');
      assert.equal(proof.init.redirect, 'error');
      assert.ok(proof.init.signal);
      const headers = proof.init.headers as Record<string, string>;
      // The caller's own header, unaltered: the database decides who this is.
      assert.equal(headers.authorization, AUTH);
      // The secret is the apikey only because PostgREST requires one.
      assert.equal(headers.apikey, SERVICE_SECRET);

      assert.ok(url('/rpc/reserve_ai_spend')(calls[1]));
      assert.ok(calls.indexOf(reserved()[0]) > 0);
    });

    await t.step('auth is settled before the body is even parsed', async () => {
      reset();
      const anonymous = await request('{ not json', null);
      assert.equal(anonymous.response.status, 401);
      assert.equal(calls.length, 0);

      reset();
      const signedIn = await request('{ not json');
      assert.equal(signedIn.response.status, 400);
      assert.ok(url('/rpc/current_household_id')(calls[0]));
      assert.equal(reserved().length, 0);
      assert.equal(modelCalls().length, 0);
    });

    await t.step('a caller the database will not vouch for is denied before spending', async () => {
      const cases: {
        name: string;
        authorization: string;
        reply: () => Promise<Response>;
        status?: number;
      }[] = [
        {
          // A publishable/anon key used as a bearer: signed by nobody.
          name: 'publishable key as bearer',
          authorization: 'Bearer fixture.publishable.apikey',
          reply: () => Promise.resolve(json({ message: 'invalid claim' }, 401)),
          status: 401,
        },
        {
          name: 'revoked session',
          authorization: 'Bearer fixture.revoked.token',
          reply: () => Promise.resolve(json({ message: 'expired' }, 401)),
          status: 401,
        },
        {
          name: 'forbidden by the database',
          authorization: AUTH,
          reply: () => Promise.resolve(json({ message: 'denied' }, 403)),
          status: 403,
        },
        {
          // A service-role string carries no auth.uid(), so there is no
          // household behind it. Denied, whichever refusal is chosen.
          name: 'service role as bearer',
          authorization: 'Bearer fixture.service.role.string',
          reply: () => Promise.resolve(json(null)),
        },
        {
          name: 'signed in but in no household',
          authorization: AUTH,
          reply: () => Promise.resolve(json('')),
        },
      ];

      for (const mode of ['walmart', 'label', 'generate']) {
        for (const kind of cases) {
          reset();
          household = kind.reply;
          const result = await request({
            mode,
            images: [IMAGE],
            messages: [{ role: 'user', text: 'something' }],
          }, kind.authorization);

          if (kind.status) {
            assert.equal(result.response.status, kind.status, kind.name);
          } else {
            assert.ok(
              result.response.status === 401 || result.response.status === 403,
              `${kind.name} in ${mode} must be denied, not ${result.response.status}`,
            );
          }
          assert.equal(reserved().length, 0, kind.name);
          assert.equal(modelCalls().length, 0, kind.name);
          assert.ok(url('/rpc/current_household_id')(calls[0]));
          assert.ok(!leaks(result.raw));
        }
      }
    });

    await t.step('an unreachable ledger refuses rather than spends', async () => {
      const replies: { name: string; reply: () => Promise<Response> }[] = [
        {
          name: 'timed out',
          reply: () =>
            Promise.reject(
              new DOMException('signal timed out', 'TimeoutError'),
            ),
        },
        {
          name: 'unavailable',
          reply: () =>
            Promise.resolve(json({ message: UPSTREAM_MARKER }, 503)),
        },
        {
          name: 'malformed body',
          reply: () =>
            Promise.resolve(
              new Response(`not json ${UPSTREAM_MARKER}`, {
                status: 200,
                headers: { 'content-type': 'application/json' },
              }),
            ),
        },
        {
          name: 'answered with the wrong shape',
          reply: () => Promise.resolve(json({ household: HOUSEHOLD })),
        },
      ];

      for (const kind of replies) {
        reset();
        household = kind.reply;
        const result = await request({ mode: 'label', images: [IMAGE] });
        assert.equal(result.response.status, 503, kind.name);
        assert.equal(reserved().length, 0, kind.name);
        assert.equal(modelCalls().length, 0, kind.name);
        assert.equal(typeof result.body.error, 'string');
        assert.ok(!leaks(result.raw), kind.name);
      }
    });

    await t.step('missing server configuration reads as configuration', async () => {
      for (const name of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']) {
        reset();
        delete env[name];
        const result = await request({ mode: 'label', images: [IMAGE] });
        assert.equal(result.response.status, 500, name);
        assert.equal(calls.length, 0, name);
        assert.equal(typeof result.body.error, 'string');
        assert.ok(!leaks(result.raw), name);
      }
    });

    await t.step('a resolved household falls through to the usual handling', async () => {
      reset();
      const refused = await request({ mode: 'label', images: [] });
      assert.equal(refused.response.status, 400);
      assert.ok(url('/rpc/current_household_id')(calls[0]));
      assert.equal(modelCalls().length, 0);

      reset();
      const accepted = await request({
        mode: 'label',
        images: [IMAGE],
        image_roles: ['nutrition'],
      });
      assert.equal(accepted.response.status, 200);
      assert.equal(modelCalls().length, 1);
      assert.ok(url('/rpc/current_household_id')(calls[0]));
      assert.ok(url('/rpc/reserve_ai_spend')(calls[1]));
    });
  } finally {
    Deno.serve = originalServe;
    Deno.env.get = originalGet;
    globalThis.fetch = originalFetch;
  }
});
