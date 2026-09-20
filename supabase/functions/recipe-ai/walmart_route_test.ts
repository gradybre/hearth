import assert from 'node:assert/strict';

// Exercises the actual route without opening a socket, reading credentials,
// contacting a model, or writing household data. The caller is a signed-in
// member of a household here — who that is, and whether they may spend at
// all, is covered by auth_route_test.ts.
const HOUSEHOLD = '3f6b1c2e-9a4d-4b8e-8c0a-1d2e3f4a5b6c';
const AUTH = 'Bearer fixture.caller.token';

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
    if (url.endsWith('/rpc/current_household_id')) return Promise.resolve(json(HOUSEHOLD));
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
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: AUTH },
      body: JSON.stringify(body),
    }));
    return { response, body: await response.json() };
  };
  const modelCalls = () => calls.filter(c => c.url === 'https://api.anthropic.com/v1/messages');
  // Who is calling is settled first; the reservation is the call after it.
  const authFirst = () => assert.ok(calls[0]?.url.endsWith('/rpc/current_household_id'));
  try {
    await import('./index.ts');
    await t.step('standalone mode reserves, calls once with bounded output, then settles', async () => {
      reset();
      const result = await request({ mode: 'walmart', images: [image] });
      assert.equal(result.response.status, 200);
      assert.equal(result.body.walmart_link.url, 'https://www.walmart.com/ip/10450479');
      assert.equal(modelCalls().length, 1);
      assert.equal(modelCalls()[0].body.max_tokens, 1000);
      authFirst();
      assert.ok(calls[1].url.endsWith('/rpc/reserve_ai_spend'));
      assert.equal(calls[1].body.p_mode, 'walmart');
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
      authFirst();
    });
    await t.step('budget denial and unreadable ledger never call model', async () => {
      for (const mode of ['deny', 'fail'] as const) {
        reset(); reserve = mode;
        const result = await request({ mode: 'walmart', images: [image] });
        assert.equal(result.response.status, mode === 'deny' ? 429 : 503);
        assert.equal(modelCalls().length, 0);
        authFirst();
        assert.ok(calls[1]?.url.endsWith('/rpc/reserve_ai_spend'));
      }
    });
    await t.step('wrong image counts and types release reservation without model call', async () => {
      for (const images of [[], [image, image], [42], { bad: image }]) {
        reset();
        const result = await request({ mode: 'walmart', images });
        assert.equal(result.response.status, 400);
        assert.equal(modelCalls().length, 0);
        authFirst();
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

    // The request-intent gate, exercised through the route rather than against
    // the pure helper: the helper's own tests prove the rule, and these prove
    // it is actually wired in and that the package facts beside it survive.
    await t.step('a package-only request refuses volunteered nutrition end to end', async () => {
      reset();
      modelInput = {
        name: 'Tomato Basil Soup',
        brand: 'Hearthside',
        // No panel was photographed, so this row came from somewhere else —
        // a thumbnail, a sidebar, or the model's own memory. It claims a
        // panel as its source, which is exactly the claim the server refuses.
        servings: [{
          amount: 100, unit: 'g', kcal: 60,
          protein_g: 2, carb_g: 9, fat_g: 2,
          fiber_g: 1, sodium_mg: 480, cholesterol_mg: 0,
        }],
        package_amount: 10,
        package_unit: 'oz',
        field_sources: { servings: 'nutrition', package_amount: 'package' },
        walmart_candidates: [{ ...candidate, source: 'package' }],
      };
      const result = await request({
        mode: 'label', images: [image], image_roles: ['package'],
      });

      assert.equal(result.response.status, 200);
      assert.deepEqual(result.body.servings, []);
      // The model said it read a panel. The server knows which photographs it
      // was sent, and overrides the claim rather than arguing with it.
      assert.equal(result.body.field_sources.servings, 'package');
      assert.equal(result.body.field_sources.package_amount, 'package');
      assert.equal(result.body.uncertain.length, 1);
      assert.equal(result.body.uncertain[0].field, 'servings');
      assert.ok(result.body.uncertain[0].note.includes('was dropped'));
      // Everything the front of the packet actually showed is still here:
      // dropping the nutrition is not dropping the reading.
      assert.equal(result.body.name, 'Tomato Basil Soup');
      assert.equal(result.body.brand, 'Hearthside');
      assert.equal(result.body.package_amount, 10);
      assert.equal(result.body.package_unit, 'oz');
      assert.equal(result.body.servings_per_container, null);
      assert.equal(result.body.servings_approximate, false);
      assert.equal(result.body.package_basis, 'unknown');
      assert.equal(result.body.walmart_link.url, 'https://www.walmart.com/ip/10450479');
      assert.equal(modelCalls().length, 1);
      authFirst();
      assert.ok(calls[1].url.endsWith('/rpc/reserve_ai_spend'));
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/settle_ai_spend'));
    });

    await t.step('a package-only request with nothing to drop adds no note', async () => {
      reset();
      modelInput = {
        name: 'Tomato Basil Soup',
        servings: [],
        package_amount: 10,
        package_unit: 'oz',
        package_basis: 'as_packaged',
        uncertain: [{ field: 'package_amount', note: 'The net weight was at an angle.' }],
        walmart_candidates: [{ ...candidate, source: 'package' }],
      };
      const result = await request({
        mode: 'label', images: [image], image_roles: ['package'],
      });

      assert.equal(result.response.status, 200);
      assert.deepEqual(result.body.servings, []);
      // A warning about a drop that did not happen would send somebody back to
      // check a photograph they never took.
      assert.deepEqual(result.body.uncertain, [
        { field: 'package_amount', note: 'The net weight was at an angle.' },
      ]);
      assert.equal(result.body.field_sources.servings, 'package');
      assert.equal(result.body.package_amount, 10);
      assert.equal(result.body.package_unit, 'oz');
      assert.equal(result.body.package_basis, 'as_packaged');
      assert.equal(result.body.name, 'Tomato Basil Soup');
      assert.equal(modelCalls().length, 1);
    });

    await t.step('a nutrition and package pair returns both readings in one call', async () => {
      reset();
      // The cup and the gram figure are both printed on this panel, and
      // together they are the only statement of how dense the food is.
      const macros = {
        kcal: 35, protein_g: 1, carb_g: 8, fat_g: 0,
        fiber_g: 1, sodium_mg: 0, cholesterol_mg: 0,
      };
      modelInput = {
        name: 'Tomato Basil Soup',
        brand: 'Hearthside',
        servings: [
          { amount: 0.667, unit: 'cup', ...macros },
          { amount: 85, unit: 'g', ...macros },
        ],
        package_amount: 10,
        package_unit: 'oz',
        servings_per_container: 3.5,
        servings_approximate: true,
        package_basis: 'as_packaged',
        field_sources: { servings: 'nutrition', package_amount: 'package' },
        walmart_candidates: [{ ...candidate, source: 'package' }],
      };
      const result = await request({
        mode: 'label',
        images: [image, image],
        image_roles: ['nutrition', 'package'],
      });

      assert.equal(result.response.status, 200);
      assert.equal(result.body.servings.length, 2);
      assert.equal(result.body.servings[0].unit, 'cup');
      assert.equal(result.body.servings[0].amount, 0.667);
      assert.equal(result.body.servings[1].unit, 'g');
      assert.equal(result.body.servings[1].amount, 85);
      for (const row of result.body.servings) {
        assert.equal(row.kcal, 35);
        assert.equal(row.protein_g, 1);
        assert.equal(row.carb_g, 8);
        assert.equal(row.fat_g, 0);
        // A printed zero is a fact the panel stated. It stays a zero, and is
        // not flattened into the null that means "the label did not say".
        assert.equal(row.fiber_g, 1);
        assert.equal(row.sodium_mg, 0);
        assert.equal(row.cholesterol_mg, 0);
      }
      // A panel was photographed, so the model's own provenance stands.
      assert.equal(result.body.field_sources.servings, 'nutrition');
      assert.equal(result.body.field_sources.package_amount, 'package');
      assert.equal(result.body.servings_per_container, 3.5);
      assert.equal(result.body.servings_approximate, true);
      assert.equal(result.body.package_amount, 10);
      assert.equal(result.body.package_unit, 'oz');
      assert.equal(result.body.package_basis, 'as_packaged');
      assert.deepEqual(result.body.uncertain, []);
      assert.equal(result.body.walmart_link.url, 'https://www.walmart.com/ip/10450479');
      // Both photographs, one reading, one paid call.
      assert.equal(modelCalls().length, 1);
      authFirst();
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/settle_ai_spend'));
    });

    await t.step('a roleless request keeps its rows and still drops malformed ones', async () => {
      reset();
      modelInput = {
        name: 'Tomato Basil Soup',
        servings: [
          {
            amount: 1, unit: 'cup', kcal: 90,
            protein_g: 3, carb_g: 14, fat_g: 2,
          },
          // A unit Hearth has no meaning for, and an amount that cannot be a
          // portion. Both are dropped by the shaper before the gate ever sees
          // them, rather than reinterpreted into something plausible.
          { amount: 1, unit: 'sprinkle', kcal: 10 },
          { amount: -2, unit: 'g', kcal: 5 },
        ],
      };
      // An older client that knows nothing about roles. It read panels
      // perfectly well before the gate existed and must keep doing so.
      const result = await request({ mode: 'label', images: [image] });

      assert.equal(result.response.status, 200);
      assert.equal(result.body.servings.length, 1);
      assert.equal(result.body.servings[0].unit, 'cup');
      assert.equal(result.body.servings[0].kcal, 90);
      // Nothing the panel did not print: the omitted minor fields stay null.
      assert.equal(result.body.servings[0].fiber_g, null);
      assert.equal(result.body.servings[0].sodium_mg, null);
      // The model said nothing about where it read this, so neither does the
      // server — 'unknown' rather than a guess in either direction.
      assert.equal(result.body.field_sources.servings, 'unknown');
      assert.deepEqual(result.body.uncertain, []);
      assert.equal(result.body.package_amount, null);
      assert.equal(result.body.package_unit, null);
      assert.ok('walmart_link' in result.body);
      assert.equal(modelCalls().length, 1);
    });
  } finally {
    Deno.serve = originalServe;
    Deno.env.get = originalGet;
    globalThis.fetch = originalFetch;
  }
});
