import { reserveUsd, costOf } from './budget.ts';
import { strict as assert } from 'node:assert/strict';
import {
  WALMART_FIELDS,
  WALMART_PROMPT,
  WALMART_TOOL,
  walmartContent,
  allowedWalmartSources,
} from './walmart_mode.ts';

Deno.test('walmartContent throws on zero images', () => {
  assert.throws(
    () => walmartContent([], (imgs) => imgs.map((i) => ({ img: i }))),
    /^Error: bad request:/,
  );
});

Deno.test('walmartContent throws on multiple images', () => {
  assert.throws(
    () => walmartContent(['a', 'b'], (imgs) => imgs.map((i) => ({ img: i }))),
    /^Error: bad request:/,
  );
});

Deno.test('walmartContent throws on non-string image', () => {
  assert.throws(
    () => walmartContent([123], (imgs) => imgs.map((i) => ({ img: i }))),
    /^Error: bad request:/,
  );
});

Deno.test('walmartContent throws on object instead of array', () => {
  assert.throws(
    () => walmartContent({ 0: 'a' }, (imgs) => imgs.map((i) => ({ img: i }))),
    /^Error: bad request:/,
  );
});

Deno.test('walmartContent throws on empty string image', () => {
  assert.throws(
    () => walmartContent([''], (imgs) => imgs.map((i) => ({ img: i }))),
    /^Error: bad request:/,
  );
});

Deno.test('walmartContent invokes callback exactly once with the single image array', () => {
  let calls = 0;
  let received: string[] | null = null;
  const result = walmartContent(['data:image/png;base64,AAA'], (imgs) => {
    calls += 1;
    received = imgs;
    return [{ type: 'image', source: imgs[0] }];
  });
  assert.equal(calls, 1);
  assert.deepEqual(received, ['data:image/png;base64,AAA']);
  assert.equal(Array.isArray(result), true);
  assert.equal(result.length, 2);
  assert.deepEqual(result[0], { type: 'image', source: 'data:image/png;base64,AAA' });
  const textBlock = result[1] as { type: string; text: string };
  assert.equal(textBlock.type, 'text');
  assert.equal(typeof textBlock.text, 'string');
  assert.match(textBlock.text, /screenshot/);
});

Deno.test('walmartContent preserves errors thrown by imageBlocks callback (cap errors)', () => {
  const capError = new Error('image exceeds size cap');
  assert.throws(
    () =>
      walmartContent(['data:image/png;base64,AAA'], () => {
        throw capError;
      }),
    (err: unknown) => err === capError,
  );
});

Deno.test('allowedWalmartSources returns [] for non-array roles', () => {
  assert.deepEqual(allowedWalmartSources('nutrition', 1), []);
  assert.deepEqual(allowedWalmartSources(null, 1), []);
  assert.deepEqual(allowedWalmartSources(undefined, 1), []);
});

Deno.test('allowedWalmartSources returns [] for invalid role values', () => {
  assert.deepEqual(allowedWalmartSources(['screenshot'], 1), []);
  assert.deepEqual(allowedWalmartSources(['barcode'], 1), []);
  assert.deepEqual(allowedWalmartSources([1], 1), []);
});

Deno.test('allowedWalmartSources returns [] when length mismatches count', () => {
  assert.deepEqual(allowedWalmartSources(['nutrition'], 2), []);
  assert.deepEqual(allowedWalmartSources(['nutrition', 'package'], 1), []);
});

Deno.test('allowedWalmartSources returns [] for duplicate roles', () => {
  assert.deepEqual(allowedWalmartSources(['nutrition', 'nutrition'], 2), []);
  assert.deepEqual(allowedWalmartSources(['package', 'package'], 2), []);
});

Deno.test('allowedWalmartSources returns [] for invalid count', () => {
  assert.deepEqual(allowedWalmartSources(['nutrition'], 3), []);
  assert.deepEqual(allowedWalmartSources(['nutrition'], 0), []);
});

Deno.test('allowedWalmartSources returns roles for valid single role', () => {
  assert.deepEqual(allowedWalmartSources(['nutrition'], 1), ['nutrition']);
  assert.deepEqual(allowedWalmartSources(['package'], 1), ['package']);
});

Deno.test('allowedWalmartSources returns roles for valid distinct pair', () => {
  assert.deepEqual(allowedWalmartSources(['nutrition', 'package'], 2), [
    'nutrition',
    'package',
  ]);
  assert.deepEqual(allowedWalmartSources(['package', 'nutrition'], 2), [
    'package',
    'nutrition',
  ]);
});

Deno.test('WALMART_TOOL wraps WALMART_FIELDS with correct required keys', () => {
  assert.equal(WALMART_TOOL.name, 'walmart_link');
  assert.equal(WALMART_TOOL.input_schema.type, 'object');
  assert.equal(WALMART_TOOL.input_schema.properties, WALMART_FIELDS);
  assert.deepEqual(
    [...WALMART_TOOL.input_schema.required].sort(),
    ['walmart_candidates', 'walmart_unreadable'].sort(),
  );
});

Deno.test('WALMART_FIELDS schema shape matches spec', () => {
  assert.equal(WALMART_FIELDS.walmart_candidates.type, 'array');
  assert.equal(WALMART_FIELDS.walmart_candidates.maxItems, 10);
  assert.deepEqual(WALMART_FIELDS.walmart_candidates.items.required, ['url']);
  assert.equal(WALMART_FIELDS.walmart_candidates.items.properties.url.type, 'string');
  assert.equal(WALMART_FIELDS.walmart_candidates.items.properties.url.maxLength, 2048);
  assert.deepEqual(WALMART_FIELDS.walmart_candidates.items.properties.source.enum, [
    'nutrition',
    'package',
    'screenshot',
  ]);
  assert.equal(WALMART_FIELDS.walmart_candidates.items.properties.uncertain.type, 'boolean');
  assert.equal(WALMART_FIELDS.walmart_unreadable.type, 'boolean');
});

Deno.test('combined prompt + schema stay concise (<=12000 characters)', () => {
  const combinedLength = WALMART_PROMPT.length + JSON.stringify(WALMART_FIELDS).length;
  assert.ok(
    combinedLength <= 12000,
    `combined length ${combinedLength} exceeds 12000 character budget`,
  );
});

Deno.test('label reservation covers the added link prompt and tool overhead', () => {
  assert.ok(reserveUsd('label') + 1e-9 >= reserveUsd('pack') + costOf({input_tokens: 4000, output_tokens: 3096}));
});
