// Who is calling, proved by the database rather than by the gateway.
//
// `verify_jwt` is on, and it is not enough. Supabase's gateway accepts an
// API-key-only request with the project's public key and no user token.
// That key ships inside the app bundle, so reaching the handler is
// not yet a request from a Hearth household member. Everything past this
// point spends money against this project's quota, so the question has to be
// settled first.
//
// It is settled the way every RLS policy in this project settles it: by asking
// Postgres, with the caller's own token, for `current_household_id`. A
// resolved household id is the only accepted proof. Nothing here decodes a
// JWT, because a decoder is a second, weaker copy of the rule — the database
// already holds the real one.

const RPC = 'current_household_id';

/// Short on purpose. This sits in front of every mode, so a slow ledger must
/// fail the request rather than hold a connection open behind it.
const TIMEOUT_MS = 5000;

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// Null when the caller is a verified member of a household; otherwise the
/// response to send back instead of doing any work.
///
/// Deliberately `Response | null` rather than a thrown error or a household
/// id: the caller's one correct use is `if (refusal) return refusal;`, and
/// nothing downstream is tempted to carry an id it does not need.
export async function requireHousehold(
  request: Request,
): Promise<Response | null> {
  const authorization = request.headers.get('authorization') ?? '';
  // Syntax only. Whether this token means anything is the database's
  // question, and asking it costs a round trip — so a header that could not
  // be a bearer token at all is refused here, without one.
  if (!looksLikeBearer(authorization)) {
    return json({ error: 'Sign in first.' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !secret) {
    // Configuration reported as configuration. Never as a refusal the user
    // could act on, and never with the value of anything.
    return json({
      error:
        'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set on this project',
    }, 500);
  }

  let response: Response;
  try {
    response = await fetch(`${url}/rest/v1/rpc/${RPC}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // PostgREST requires an apikey; the identity that matters is the
        // caller's own header below, which decides `auth.uid()` inside the
        // function. It is forwarded exactly as it arrived.
        apikey: secret,
        authorization,
      },
      body: '{}',
      // A redirect off this host would send the caller's token somewhere
      // this project did not choose.
      redirect: 'error',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    // A timeout or a refused connection. Nothing about the caller is known,
    // so nothing is spent — and the detail stays here.
    return unavailable();
  }

  if (response.status === 401) {
    return json({ error: 'Sign in again and retry.' }, 401);
  }
  if (response.status === 403) {
    return json({ error: 'That account cannot use this.' }, 403);
  }
  if (!response.ok) return unavailable();

  let value: unknown;
  try {
    value = await response.json();
  } catch {
    return unavailable();
  }

  if (value === null) return notInHousehold();
  if (typeof value !== 'string') return unavailable();

  const household = value.trim();
  // A signed-in person who belongs to no household: a real answer, and a
  // refusal rather than a fault.
  if (household.length === 0) return notInHousehold();
  // Anything else is the ledger answering something this function does not
  // understand. Treated as unavailable, because guessing at it would be the
  // one failure that looks like success.
  if (!UUID.test(household)) return unavailable();

  return null;
}

/// A bearer token, as far as syntax can tell.
///
/// Exactly two whitespace-separated parts, the first being `bearer` in any
/// case. A blank header, a bare scheme, another scheme entirely, or a token
/// with a space in it is not one.
function looksLikeBearer(header: string): boolean {
  const parts = header.trim().split(/\s+/);
  return parts.length === 2 && /^bearer$/i.test(parts[0]) &&
    parts[1].length > 0;
}

function notInHousehold(): Response {
  return json({ error: 'That account is not in a household yet.' }, 403);
}

/// The ledger could not be asked, so the caller is unproven.
///
/// 503 rather than a 401: nothing suggests the caller is wrong, and telling
/// somebody to sign in again when the database is unwell sends them round a
/// loop that cannot end. The body says nothing about what actually happened —
/// upstream text can carry ids, and a response is not a log.
function unavailable(): Response {
  return json({
    error: 'Hearth could not check your account just now. Try again shortly.',
  }, 503);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
