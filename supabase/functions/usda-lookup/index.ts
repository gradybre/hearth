// USDA FoodData Central, behind the server (spec §5.5, CLAUDE.md §8.1).
//
// This function exists for exactly one reason: FDC requires an API key, and a
// key in the client is a key anyone can pull out of the app bundle. Open Food
// Facts needs no key and is called directly; USDA cannot be, so the app asks
// this function and the function asks USDA.
//
// A second benefit worth having: USDA's response shape is awkward and changes.
// Parsing it here means a fix is a redeploy rather than an App Store release.
// That parsing lives in `narrow.ts`, because this file calls `Deno.serve` and
// importing it to test the narrowing would start a server.
//
// verify_jwt is on (the default), so only a signed-in Hearth user can spend
// this project's USDA quota.

import { type Match, toMatch } from './narrow.ts';

const FDC = 'https://api.nal.usda.gov/fdc/v1';

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  const key = Deno.env.get('USDA_FDC_API_KEY');
  if (!key) {
    // Configuration, not a lookup failure — say so plainly rather than
    // returning an empty result the client would read as "no such food".
    return json({ error: 'USDA_FDC_API_KEY is not set on this project' }, 500);
  }

  let body: { barcode?: string; query?: string; limit?: number };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const barcode = (body.barcode ?? '').trim();
  const query = (body.query ?? '').trim();
  const limit = Math.min(Math.max(body.limit ?? 20, 1), 50);

  if (!barcode && !query) {
    return json({ error: 'give a barcode or a query' }, 400);
  }

  try {
    const matches = barcode
      ? await byBarcode(barcode, key)
      : await search(query, limit, key);
    return json({ matches });
  } catch (error) {
    // Upstream being unreachable is not this function's failure, and the
    // client treats a 502 as "this source had nothing" and moves on.
    return json({ error: `${error}`, matches: [] }, 502);
  }
});

/// FDC has no barcode endpoint. Searching the branded dataset for the number
/// and then insisting on an exact GTIN match is the documented way, and the
/// insistence matters: search alone happily returns near-misses, and a
/// near-miss here is the wrong food's macros in someone's day.
async function byBarcode(barcode: string, key: string): Promise<Match[]> {
  const found = await search(barcode, 25, key, 'Branded');
  const exact = found.filter((m) => m.barcode === barcode);
  return exact.length > 0 ? [exact[0]] : [];
}

async function search(
  query: string,
  limit: number,
  key: string,
  dataType?: string,
): Promise<Match[]> {
  const url = new URL(`${FDC}/foods/search`);
  url.searchParams.set('api_key', key);
  url.searchParams.set('query', query);
  url.searchParams.set('pageSize', `${limit}`);
  if (dataType) url.searchParams.set('dataType', dataType);

  const response = await fetch(url, {
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`FDC returned ${response.status}`);

  const payload = await response.json();
  const foods: unknown[] = Array.isArray(payload?.foods) ? payload.foods : [];

  return foods
    .map(toMatch)
    .filter((m): m is Match => m !== null);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
