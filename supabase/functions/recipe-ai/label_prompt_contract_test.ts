import assert from 'node:assert/strict';

// What the route actually sends a model for a label reading (spec 5.6).
//
// This exists because of a live failure that was NOT a legibility problem: on
// a downsampled photo pair the model read "2/3 cup (85g)" correctly, said so
// in its own uncertainty note, and then deliberately withheld the gram entry
// because its macros matched the cup entry's. The fix is a clarification of
// the extraction contract, and the only thing a test on this side of the wire
// can prove is that the clarification is genuinely in the request: the system
// prompt and tool schema that leave this function are the contract, and a
// clause that gets refactored out of them would otherwise fail silently.
//
// It CANNOT prove the model obeys any of it. No assertion here is evidence
// that the live photo pair now returns both entries; only the real retest is.
// Assertions are deliberately clause-shaped rather than whole paragraphs, so
// rewording the prose does not break them but deleting a rule does.

const HOUSEHOLD = '3f6b1c2e-9a4d-4b8e-8c0a-1d2e3f4a5b6c';
const AUTH = 'Bearer fixture.caller.token';
const MODEL_URL = 'https://api.anthropic.com/v1/messages';

Deno.test('label requests carry the serving-measure extraction contract', async (t) => {
  const originalServe = Deno.serve;
  const originalGet = Deno.env.get;
  const originalFetch = globalThis.fetch;
  let handler: ((request: Request) => Promise<Response>) | undefined;
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  const image = 'data:image/png;base64,iVBORw0KGgo=';

  // The panel and front from the live failure, as the model would have
  // returned them had it applied the contract. Fixture output only: it says
  // nothing about what a real model does with a real photograph.
  const macros = {
    kcal: 35,
    protein_g: 1,
    carb_g: 8,
    fat_g: 0,
    fiber_g: 1,
    sodium_mg: 0,
    cholesterol_mg: 0,
  };
  const modelInput: Record<string, unknown> = {
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
  };

  const json = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), {
      status,
      headers: { 'content-type': 'application/json' },
    });

  Deno.serve = ((fn: unknown) => {
    assert.equal(typeof fn, 'function');
    handler = fn as typeof handler;
    return {} as Deno.HttpServer;
  }) as typeof Deno.serve;

  Deno.env.get = (name: string) =>
    ({
      ANTHROPIC_API_KEY: 'EXAMPLE_ONLY_NOT_A_REAL_KEY',
      SUPABASE_URL: 'https://hearth-fixture.invalid',
      SUPABASE_SERVICE_ROLE_KEY: 'EXAMPLE_ONLY_NOT_A_REAL_SECRET',
    } as Record<string, string>)[name];

  globalThis.fetch = (input, init) => {
    const url = String(input);
    const body = JSON.parse(String(init?.body ?? '{}')) as Record<
      string,
      unknown
    >;
    calls.push({ url, body });
    if (url.endsWith('/rpc/current_household_id')) {
      return Promise.resolve(json(HOUSEHOLD));
    }
    if (url.endsWith('/rpc/reserve_ai_spend')) {
      return Promise.resolve(
        json([{
          reservation_id: 'fixture-reservation',
          spent_usd: 0,
          reserved_usd: 0,
          allowed: true,
        }]),
      );
    }
    if (url.endsWith('/rpc/settle_ai_spend')) {
      return Promise.resolve(json([{ cost_usd: 0.001 }]));
    }
    if (url.endsWith('/rpc/release_ai_spend')) return Promise.resolve(json(null));
    if (url === MODEL_URL) {
      return Promise.resolve(
        json({
          content: [{ type: 'tool_use', input: modelInput }],
          usage: { input_tokens: 100, output_tokens: 50 },
          stop_reason: 'tool_use',
        }),
      );
    }
    throw new Error(`Unexpected external call: ${url}`);
  };

  const modelCalls = () => calls.filter((c) => c.url === MODEL_URL);

  try {
    // A distinct specifier, because another test file in the same run may
    // already have imported the route: a cached module would not re-register
    // its handler against this file's stub, and every assertion below would
    // then be testing nothing.
    await import('./index.ts?label-prompt-contract');
    assert.ok(handler, 'the route registered no handler');

    const response = await handler(
      new Request('https://hearth-fixture.invalid/functions/v1/recipe-ai', {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: AUTH },
        body: JSON.stringify({
          mode: 'label',
          images: [image, image],
          image_roles: ['nutrition', 'package'],
        }),
      }),
    );
    const shaped = await response.json();

    assert.equal(response.status, 200);
    assert.equal(modelCalls().length, 1);
    const sent = modelCalls()[0].body;
    const system = String(sent.system ?? '');
    const tool = (sent.tools as Record<string, unknown>[])[0];
    const schema = tool.input_schema as Record<string, unknown>;
    const properties = schema.properties as Record<string, unknown>;
    const servings = properties.servings as Record<string, unknown>;
    const servingsText = String(servings.description ?? '');

    await t.step('the request still obeys the route boundaries it always did', () => {
      // Who is calling, before anything is read, spent or sent.
      assert.ok(calls[0]?.url.endsWith('/rpc/current_household_id'));
      // Reserved before the model, settled after it.
      assert.ok(calls[1]?.url.endsWith('/rpc/reserve_ai_spend'));
      assert.equal(calls[1].body.p_mode, 'label');
      assert.ok(
        calls.findIndex((c) => c.url === MODEL_URL) >
          calls.findIndex((c) => c.url.endsWith('/rpc/reserve_ai_spend')),
      );
      assert.ok(calls.at(-1)?.url.endsWith('/rpc/settle_ai_spend'));
      // One paid call for both photographs, with a bounded output.
      assert.equal(typeof sent.max_tokens, 'number');
      assert.ok((sent.max_tokens as number) > 0);
      assert.equal(tool.name, 'nutrition_label');
      assert.deepEqual(sent.tool_choice, {
        type: 'tool',
        name: 'nutrition_label',
      });
      // Both images went in one message, and neither role string reached the
      // model as free text.
      const message = (sent.messages as Record<string, unknown>[])[0];
      const content = message.content as Record<string, unknown>[];
      assert.equal(content.filter((c) => c.type === 'image').length, 2);
    });

    await t.step('the serving line must come back as every printed measure', () => {
      // The volume-and-gram case itself, named in the prompt rather than left
      // to be inferred from the ounce rule.
      assert.match(system, /2\/3 cup \(85g\)/);
      assert.match(system, /cup\s*\n?AND the gram figure/i);
      assert.match(servingsText, /2\/3 cup \(85g\)/);
    });

    await t.step('identical macros are never grounds for dropping a measure', () => {
      // The exact reasoning the live failure used: same numbers, so one entry
      // was withheld as a duplicate.
      assert.match(
        system,
        /(never|do not)[\s\S]{0,160}(deduplicat|merge|collaps|drop)/i,
      );
      assert.match(system, /identical macros[\s\S]{0,200}(expected|correct)/i);
      assert.match(
        servingsText,
        /(never|not)[\s\S]{0,160}(duplicate|drop)/i,
      );
    });

    await t.step('a package ounce figure never suppresses serving grams', () => {
      // The ounce preference stays, but only for an ounce printed on the
      // serving line itself.
      assert.match(system, /ounce figure is\s*\n?printed for that same serving/i);
      assert.match(
        system,
        /net (weight|contents)[\s\S]{0,200}never suppresses[\s\S]{0,60}gram/i,
      );
      assert.match(
        servingsText,
        /net (weight|contents)[\s\S]{0,200}never suppresses[\s\S]{0,60}gram/i,
      );
    });

    await t.step('"at most the servings the label states" is not a collapse rule', () => {
      assert.match(system, /Return at most the servings the label states/);
      assert.match(system, /100 g row/);
      assert.match(
        system,
        /(does not mean|not mean)[\s\S]{0,160}collaps/i,
      );
    });

    await t.step('the worked example states the whole shape at once', () => {
      assert.match(system, /"unit":"cup"/);
      assert.match(system, /"unit":"g"/);
      assert.match(system, /0\.667/);
      assert.match(system, /"amount":85/);
      assert.match(system, /"package_amount":10/);
      assert.match(system, /"package_unit":"oz"/);
      assert.match(system, /"servings_per_container":3\.5/);
      assert.match(system, /"servings_approximate":true/);
      // Identical macros across the two entries is the point of the example,
      // so both rows must carry the calorie figure.
      assert.equal((system.match(/"kcal":35/g) ?? []).length, 2);
    });

    await t.step('the worked example is labelled an illustration, not defaults', () => {
      // An example of the right shape, carrying real-looking numbers, is a
      // template somebody will fill in: a 35 that belonged to the soup would
      // read perfectly on a review screen beside a different packet.
      assert.match(system, /(not|never)[\s\S]{0,120}defaults?/i);
      assert.match(
        system,
        /(transcribed?|return)[\s\S]{0,160}(from the photographs|from the photos|in front of you)/i,
      );
    });

    await t.step('"about" is read literally, and unreadable is flagged not guessed', () => {
      assert.match(system, /about 3\.5/i);
      assert.match(system, /servings_approximate/);
      assert.match(system, /do not round it to a whole count/i);
      assert.match(
        system,
        /uncertain[\s\S]{0,160}(rather than|instead of)[\s\S]{0,80}exact/i,
      );
    });

    await t.step('the blurred-digit paragraph is unchanged', () => {
      // Reverted once already after review N2, because majors default to 0 and
      // omitting them turns an unreadable digit into a confident zero.
      assert.ok(
        system.includes(
          'If a digit is blurred, a line is cut off, or a figure could be read two\nways,\ntranscribe your best reading AND list it in uncertain.',
        ) ||
          (system.includes('transcribe your best reading AND list it in uncertain') &&
            system.includes('A flagged guess is\nuseful; a confident wrong number is not.')),
      );
    });

    await t.step('no schema or default changed alongside the prose', () => {
      // Nothing required, so a front-only photo set is still a valid reading.
      assert.equal(schema.required, undefined);
      const items = servings.items as Record<string, unknown>;
      const itemProps = items.properties as Record<string, unknown>;
      const unit = itemProps.unit as { enum: string[] };
      assert.ok(unit.enum.includes('cup'));
      assert.ok(unit.enum.includes('g'));
      assert.ok(unit.enum.includes('scoop'));
      assert.deepEqual(items.required, ['amount', 'unit', 'kcal']);
      assert.ok('servings_approximate' in properties);
      assert.ok('package_basis' in properties);
    });

    await t.step('the route still shapes both printed measures through', () => {
      // Route behaviour on fixture output, not evidence about the model.
      assert.equal(shaped.servings.length, 2);
      assert.equal(shaped.servings[0].unit, 'cup');
      assert.equal(shaped.servings[0].amount, 0.667);
      assert.equal(shaped.servings[1].unit, 'g');
      assert.equal(shaped.servings[1].amount, 85);
      for (const row of shaped.servings) {
        assert.equal(row.kcal, 35);
        assert.equal(row.fiber_g, 1);
        assert.equal(row.sodium_mg, 0);
        assert.equal(row.cholesterol_mg, 0);
      }
      assert.equal(shaped.servings_per_container, 3.5);
      assert.equal(shaped.servings_approximate, true);
      assert.equal(shaped.package_amount, 10);
      assert.equal(shaped.package_unit, 'oz');
      assert.equal(shaped.field_sources.servings, 'nutrition');
    });
  } finally {
    Deno.serve = originalServe;
    Deno.env.get = originalGet;
    globalThis.fetch = originalFetch;
  }
});
