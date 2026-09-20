import assert from 'node:assert/strict';

// Exercises the actual route without opening a socket, reading credentials,
// contacting a model, or writing household data. Gateway JWT enforcement is
// provided by Supabase and is not claimed by this in-process test.
Deno.test('Walmart route preserves one-call extraction and budget boundaries', async (t) => {
  const originalServe = Deno.serve;
  const originalGet = Deno.env.get;
  const originalFetch = globalThis.fetch;
  let handler: ((request: Request) => Promise<Response>) | undefined;
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  let reserve: 'allow' | 'deny' | 'fail' = 'allow';
  let modelFailure = false;
  let truncated = false;
  let modelInput: Record<string, unknown> = {};
  const image = 'data:image/png;base64,iVBORw0KGgo=';
  const candidate = { url: 'walmart.com/ip/10450479', source: 'screenshot', uncertain: false };
  const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
    status, headers: { 'content-type': 'application/json' },
  });
  const reset = () => {
    calls.length = 0;
    reserve = 'allow'; modelFailure = false; truncated = false;
    modelInput = { walmart_candidates: [candidate], walmart_unreadable: false };
  };
  Deno.serve = ((fn: unknown) => {
    assert.equal(typeof fn, 'function');
    handler = fn as typeof handler;
    return {} as Deno.HttpServer;
  }) as typeof Deno.serve;
  Deno.env.get = (name: string) => ({
    ANTHROPIC_API_KEY: 'EXAMPLE_ONLY_NOT_A_REAL_KEY',
    SUPABASE_URL: 'https://hearth-fixture.invalid',
    SUPABASE_SERVICE_ROLE_KEY: 'EXAMPLE_ONLY_NOT_A_REAL_SECRET',
  } as Record<string, string>)[name];
  globalThis.fetch = (input, init) => {
    const url = String(input);
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>;
    calls.push({ url, body });
    if (url.endsWith('/rpc/reserve_ai_spend')) {
      if (reserve === 'fail') return Promise.resolve(json({}, 503));
      return Promise.resolve(json([{
        reservation_id: reserve === 'allow' ? 'fixture-reservation' : null,
        spent_usd: reserve === 'deny' ? 1000 : 0, reserved_usd: 0,
        allowed: reserve === 'allow',
      }]));
    }
    if (url.endsWith('/rpc/settle_ai_spend')) return Promise.resolve(json([{ cost_usd: 0.001 }]));
    if (url.endsWith('/rpc/release_ai_spend')) return Promise.resolve(json(null));
    if (url === 'https://api.anthropic.com/v1/messages') {
      if (modelFailure) return Promise.resolve(json({ error: 'fixture failure' }, 503));
      return Promise.resolve(json({
        content: [{ type: 'tool_use', input: modelInput }],
        usage: { input_tokens: 100, output_tokens: 50 },
        stop_reason: truncated ? 'max_tokens' : 'tool_use',
      }));
    }
    throw new Error(`Unexpected external call: ${url}`);
  };
  const request = async (body: Record<string, unknown>) => {
    assert.ok(handler);
    const response = await handler(new Request('https://hearth-fixture.invalid/functions/v1/recipe-ai', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
    }));
    return { response, body: await response.json() };
  };
  const modelCalls = () => calls.filter(c => c.url === 'https://api.anthropic.com/v1/messages');
  try {
    await import('./index.ts');
    await t.step('standalone mode reserves, calls once with bounded output, then settles', async () => {
      reset();
      const result = await request({ mode: 'walmart', images: [image] });
      assert.equal(result.response.status, 200);
      assert.equal(result.body.walmart_link.url, 'https://www.walmart.com/ip/10450479');
      assert.equal(modelCalls().length, 1);
      assert.equal(modelCalls()[0].body.max_tokens, 1000);
      assert.ok(calls[0].url.endsWith('/rpc/reserve_ai_spend'));
      assert.equal(calls[0].body.p_mode, 'walmart');
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/settle_ai_spend'));
    });
    await t.step('combined label keeps nutrition and adds link in one model call', async () => {
      reset();
      modelInput = {
        servings: [{ amount: 1, unit: 'cup', kcal: 120, protein_g: 4, carb_g: 22, fat_g: 2 }],
        walmart_candidates: [{ ...candidate, source: 'nutrition' }],
      };
      const result = await request({ mode: 'label', images: [image], image_roles: ['nutrition'] });
      assert.equal(result.response.status, 200);
      assert.equal(result.body.servings[0].kcal, 120);
      assert.equal(result.body.walmart_link.source, 'nutrition');
      assert.equal(modelCalls().length, 1);
    });
    await t.step('budget denial and unreadable ledger never call model', async () => {
      for (const mode of ['deny', 'fail'] as const) {
        reset(); reserve = mode;
        const result = await request({ mode: 'walmart', images: [image] });
        assert.equal(result.response.status, mode === 'deny' ? 429 : 503);
        assert.equal(modelCalls().length, 0);
        assert.ok(calls[0]?.url.endsWith('/rpc/reserve_ai_spend'));
      }
    });
    await t.step('wrong image counts and types release reservation without model call', async () => {
      for (const images of [[], [image, image], [42], { bad: image }]) {
        reset();
        const result = await request({ mode: 'walmart', images });
        assert.equal(result.response.status, 400);
        assert.equal(modelCalls().length, 0);
        assert.ok(calls.at(-1)?.url.endsWith('/rpc/release_ai_spend'));
      }
    });
    await t.step('exactly 5 MiB decoded is accepted despite base64 expansion', async () => {
      reset();
      const encoded = 'A'.repeat(Math.ceil(5 * 1024 * 1024 / 3) * 4 - 1) + '=';
      const result = await request({mode: 'walmart', images: ['data:image/png;base64,' + encoded]});
      assert.equal(result.response.status, 200);
      assert.equal(modelCalls().length, 1);
    });
    await t.step('oversized screenshot is refused before model', async () => {
      reset();
      const result = await request({ mode: 'walmart', images: ['data:image/png;base64,' + 'A'.repeat(7 * 1024 * 1024)] });
      assert.equal(result.response.status, 400);
      assert.equal(modelCalls().length, 0);
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/release_ai_spend'));
    });
    await t.step('provider failure returns error and releases reservation', async () => {
      reset(); modelFailure = true;
      const result = await request({ mode: 'walmart', images: [image] });
      assert.equal(result.response.status, 502);
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/release_ai_spend'));
    });
    await t.step('truncated, ambiguous and cropped responses cannot fill a link', async () => {
      for (const kind of ['truncated', 'ambiguous', 'cropped']) {
        reset();
        if (kind === 'truncated') truncated = true;
        if (kind === 'ambiguous') modelInput.walmart_candidates = [candidate, { ...candidate, url: 'walmart.com/ip/98765432' }];
        if (kind === 'cropped') modelInput.walmart_unreadable = true;
        const result = await request({ mode: 'walmart', images: [image] });
        assert.equal(result.response.status, 200);
        assert.equal(result.body.walmart_link.url, null);
      }
    });
  } finally {
    Deno.serve = originalServe;
    Deno.env.get = originalGet;
    globalThis.fetch = originalFetch;
  }
});
