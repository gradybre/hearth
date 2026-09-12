// The household's Google Nest, behind the server (spec §11, CLAUDE.md §8.1).
//
// This function exists because the OAuth token exchange needs a client secret,
// and a secret in the client is a secret anyone can pull out of the app bundle.
// The household's refresh token — a live bearer credential for the heating —
// never leaves the server at all: it lives in `private.nest_link`, which
// PostgREST does not expose, reachable only through the `nest_link_*` functions
// with the secret key.
//
// verify_jwt is on (the default), so every action here is a signed-in member of
// some household, and which household is asked of `current_household_id` with
// the caller's own JWT rather than read from the request body.

import {
  commandBody,
  SDM,
  type Snapshot,
  snapshotOf,
  thermostatsIn,
} from './sdm.ts';
import {
  consentUrl,
  exchange,
  type FreshToken,
  GrantRevoked,
  isFresh,
  REDIRECT_URI,
  refresh,
  TokenRefused,
} from './tokens.ts';

/// Google's device-level ceiling is 100 requests an hour. Stopping at 90 keeps
/// room for the commands somebody is in the middle of making, and means Hearth
/// never earns a real 429 — a sustained one is how a link starts failing in
/// ways that look like an app bug.
const CALLS_PER_HOUR = 90;


Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') return json({ error: 'POST only' }, 405);

  const env = readEnv();
  if ('error' in env) return json({ error: env.error }, 500);

  const auth = request.headers.get('authorization') ?? '';
  if (!auth) return json({ error: 'Sign in first.' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json() as Record<string, unknown>;
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const action = typeof body.action === 'string' ? body.action : '';

  // The household is asked of the database with the caller's own token, never
  // taken from the body. `current_household_id` is `security definer` and is
  // already what every RLS policy in this project is built on, so there is no
  // JWT parsing anywhere in this function.
  const household = await currentHousehold(env, auth);
  if (!household) {
    return json({ error: 'That account is not in a household yet.' }, 403);
  }

  try {
    switch (action) {
      case 'consent-url':
        return json({ url: consentUrl(env.projectId, env.clientId) });
      case 'link':
        return await link(env, household, auth, body);
      case 'status':
        return await status(env, household, auth);
      case 'command':
        return await command(env, household, body);
      case 'unlink':
        return await unlink(env, household);
      default:
        return json({ error: 'unknown action' }, 400);
    }
  } catch (error) {
    if (error instanceof GrantRevoked) {
      // Not a server fault, and never worth retrying. 409 is what the client
      // reads as "offer Reconnect" rather than "try again".
      await rpc(env, 'nest_link_clear', {
        p_household: household,
        p_reason: 'invalid_grant',
      });
      return json({
        error:
          'Google stopped accepting Hearth’s connection. It needs linking '
          + 'again.',
        needs_relink: true,
      }, 409);
    }
    if (error instanceof TokenRefused) {
      await note(env, household, false, error.message);
      return json({ error: error.message }, 502);
    }
    const message = error instanceof Error
      ? error.message
      : 'Something went wrong reaching the thermostat.';
    await note(env, household, false, message);
    return json({ error: message }, 502);
  }
});

// ── Actions ─────────────────────────────────────────────────────────────────

async function link(
  env: Env,
  household: string,
  auth: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const raw = typeof body.code === 'string' ? body.code.trim() : '';
  if (!raw) return json({ error: 'Paste the code from the address bar.' }, 400);

  // The code arrives percent-encoded in the browser's address bar — `4%2F0A…`
  // — and pasting it verbatim is the obvious thing to do. Decoding here means
  // either form works, which is worth more than being strict about a string
  // somebody copied off a screen.
  const code = raw.includes('%') ? safeDecode(raw) : raw;

  const token = await exchange(fetch, {
    code,
    clientId: env.clientId,
    clientSecret: env.clientSecret,
    redirectUri: REDIRECT_URI,
    now: new Date(),
  });

  // Google requires one devices.list to complete authorization; without it the
  // project never appears in the Partner Connections Manager.
  const listed = await sdm(env, token.accessToken, `/devices`);
  const thermostats = thermostatsIn(listed);
  if (thermostats.length === 0) {
    // The commonest real failure: the device picker was left unticked. Saying
    // so beats saving a link with nothing behind it and an empty screen.
    return json({
      error: 'No thermostat was shared with Hearth. Link again and tick the '
        + 'thermostat in Google’s device list.',
    }, 400);
  }

  // Whose Google account this is, asked of the database with the caller's own
  // JWT. `linked_by` is who has to reconnect when the link dies, so a wrong
  // value here is a wrong name on the one screen that has to name somebody.
  const linkedBy = await currentUser(env, auth);
  if (!linkedBy) return json({ error: 'Sign in again and retry.' }, 401);

  const chosen = thermostats[0];
  const saved = await rpcOne(env, 'nest_link_save', {
    p_household: household,
    p_project_id: env.projectId,
    p_refresh_token: token.refreshToken,
    p_linked_by: linkedBy,
    p_device_name: chosen.name,
    p_device_label: chosen.label,
  });
  if (!saved) return json({ error: 'Could not save the link.' }, 500);

  await rpc(env, 'nest_link_save_access_token', {
    p_household: household,
    p_access_token: token.accessToken,
    p_expires_at: token.expiresAt.toISOString(),
  });

  return json({ linked: true, deviceLabel: chosen.label });
}

async function status(
  env: Env,
  household: string,
  auth: string,
): Promise<Response> {
  const row = await readLink(env, household);
  if (!row || !row.refresh_token) return json({ linked: false });

  const device = await read(env, household, row);
  // Whether *you* linked it, rather than the raw uuid of whoever did. A uuid
  // on screen says nothing, and resolving it to a name would be another query
  // for a sentence that only needs to distinguish two people.
  const me = await currentUser(env, auth);
  return json({
    linked: true,
    linkedAt: row.linked_at,
    linkedByYou: me !== null && me === row.linked_by,
    device,
  });
}

async function command(
  env: Env,
  household: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const row = await readLink(env, household);
  if (!row || !row.refresh_token) return json({ linked: false });
  if (!row.device_name) {
    return json({ error: 'Hearth has not found the thermostat yet.' }, 409);
  }

  const wire = commandBody(body.command);
  if (!wire) return json({ error: 'That is not a command Hearth sends.' }, 400);

  const token = await accessToken(env, household, row);
  if (!(await takeCall(env, household))) return rateLimited();

  await sdm(
    env,
    token,
    `/${row.device_name.replace(/^enterprises\/[^/]+\//, '')}:executeCommand`,
    { method: 'POST', body: JSON.stringify(wire) },
    row.device_name,
  );
  await note(env, household, true, null);

  // Deliberately no re-read. A command plus a read is two calls against a
  // five-a-minute device ceiling, so one drag of a setpoint would exhaust it.
  // The client folds what it asked for into what it already has, and the next
  // poll — at most a minute away — is what confirms it.
  return json({ applied: true });
}

async function unlink(env: Env, household: string): Promise<Response> {
  const row = await readLink(env, household);
  if (row?.refresh_token) {
    // Best effort, and deliberately not fatal: the credential must stop
    // working here whether or not Google is reachable this second.
    try {
      await fetch(
        `https://oauth2.googleapis.com/revoke?token=${
          encodeURIComponent(row.refresh_token)
        }`,
        { method: 'POST', signal: AbortSignal.timeout(5000) },
      );
    } catch {
      // Nothing to do about it, and nothing worth telling the user.
    }
  }
  await rpc(env, 'nest_link_clear', {
    p_household: household,
    p_reason: 'unlinked',
  });
  return json({ linked: false });
}

// ── Reading the device ──────────────────────────────────────────────────────

/// The thermostat as it is now.
///
/// Throws rather than returning null when it cannot be read. Answering
/// `{linked: true, device: null}` would be the server saying "you have a
/// thermostat and here is nothing", which the app can only read as having no
/// thermostat — so spending the hour's budget would put a Connect button in
/// front of somebody whose link is perfectly good, and pressing it would start
/// a fresh consent flow for no reason.
async function read(
  env: Env,
  household: string,
  row: LinkRow,
): Promise<Snapshot> {
  const token = await accessToken(env, household, row);

  let deviceName = row.device_name;
  if (!deviceName) {
    if (!(await takeCall(env, household))) throw overBudget();
    const thermostats = thermostatsIn(await sdm(env, token, '/devices'));
    if (thermostats.length === 0) {
      throw new TokenRefused(
        404,
        'No thermostat is shared with Hearth any more. Link again and tick '
          + 'it in Google\u2019s device list.',
      );
    }
    deviceName = thermostats[0].name;
    await rpc(env, 'nest_link_pin_device', {
      p_household: household,
      p_device_name: deviceName,
      p_device_label: thermostats[0].label,
    });
  }

  if (!(await takeCall(env, household))) throw overBudget();
  const path = `/${deviceName.replace(/^enterprises\/[^/]+\//, '')}`;
  const device = await sdm(env, token, path, {}, deviceName);
  const snapshot = snapshotOf(device);
  if (!snapshot) {
    throw new TokenRefused(
      502,
      'The thermostat answered with something Hearth cannot read.',
    );
  }
  await note(env, household, true, null);
  return snapshot;
}

/// The hour's requests are spent.
///
/// A `TokenRefused` rather than a bare error so the caller answers it as
/// weather — the link is fine and asking again later works.
function overBudget(): TokenRefused {
  return new TokenRefused(
    429,
    'Hearth has asked the thermostat as often as Google allows this hour. '
      + 'Try again shortly.',
  );
}

async function accessToken(
  env: Env,
  household: string,
  row: LinkRow,
): Promise<string> {
  const now = new Date();
  if (row.access_token && isFresh(row.access_token_expires_at, now)) {
    return row.access_token;
  }
  if (!row.refresh_token) {
    throw new GrantRevoked('no refresh token on this household');
  }

  const token: FreshToken = await refresh(fetch, {
    refreshToken: row.refresh_token,
    clientId: env.clientId,
    clientSecret: env.clientSecret,
    now,
  });
  await rpc(env, 'nest_link_save_access_token', {
    p_household: household,
    p_access_token: token.accessToken,
    p_expires_at: token.expiresAt.toISOString(),
  });
  return token.accessToken;
}

/// Claims one request against the hour's budget, or false if it is spent.
async function takeCall(env: Env, household: string): Promise<boolean> {
  const taken = await rpcOne(env, 'nest_link_take_call', {
    p_household: household,
    p_limit: CALLS_PER_HOUR,
  });
  return typeof taken === 'number';
}

async function sdm(
  env: Env,
  token: string,
  path: string,
  init: RequestInit = {},
  deviceName?: string,
): Promise<unknown> {
  const response = await fetch(
    `${SDM}/enterprises/${env.projectId}${
      path.startsWith('/devices') ? path : `/devices${path}`
    }`,
    {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      signal: AbortSignal.timeout(15000),
    },
  );

  if (response.status === 401) {
    // A fresh access token that is refused means the grant behind it is gone.
    throw new GrantRevoked('the access token was rejected');
  }
  if (response.status === 404 && deviceName) {
    throw new TokenRefused(
      404,
      'That thermostat is no longer shared with Hearth. Link again.',
    );
  }
  if (response.status === 429) {
    throw new TokenRefused(
      429,
      'Google is rate-limiting Hearth. Try again in a minute.',
    );
  }
  if (!response.ok) {
    // The body is not logged and not forwarded: it can carry device ids, and
    // function logs are not a secret store.
    throw new TokenRefused(
      response.status,
      'The thermostat did not answer. Try again in a moment.',
    );
  }
  return await response.json();
}

// ── The database ────────────────────────────────────────────────────────────

interface LinkRow {
  household_id: string;
  refresh_token: string | null;
  access_token: string | null;
  access_token_expires_at: string | null;
  device_name: string | null;
  device_label: string | null;
  linked_by: string;
  linked_at: string;
}

async function readLink(env: Env, household: string): Promise<LinkRow | null> {
  const row = await rpcOne(env, 'nest_link_read', { p_household: household });
  return row && typeof row === 'object' ? row as unknown as LinkRow : null;
}

async function note(
  env: Env,
  household: string,
  ok: boolean,
  error: string | null,
): Promise<void> {
  try {
    await rpc(env, 'nest_link_note_result', {
      p_household: household,
      p_ok: ok,
      p_error: error,
    });
  } catch {
    // Bookkeeping. Never the reason a request fails.
  }
}

async function currentHousehold(env: Env, auth: string): Promise<string | null> {
  // The caller's own JWT, so `auth.uid()` inside the function is the person
  // who made the request — the apikey header is the secret key only because
  // PostgREST requires one.
  const response = await fetch(`${env.url}/rest/v1/rpc/current_household_id`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.secret,
      authorization: auth,
    },
    body: '{}',
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return null;
  const value = await response.json();
  return typeof value === 'string' && value.length > 0 ? value : null;
}

/// The caller's own id, asked of the database with the caller's own JWT.
///
/// The sibling of [currentHousehold], and for the same reason: there is no
/// JWT-parsing code anywhere in this project, and adding some here to save one
/// round trip would be the first.
async function currentUser(env: Env, auth: string): Promise<string | null> {
  const response = await fetch(`${env.url}/rest/v1/rpc/current_app_user`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.secret,
      authorization: auth,
    },
    body: '{}',
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return null;
  const value = await response.json();
  return typeof value === 'string' && value.length > 0 ? value : null;
}

async function rpc(
  env: Env,
  name: string,
  args: Record<string, unknown>,
): Promise<void> {
  await rpcOne(env, name, args);
}

/// The secret key, not the caller's JWT: `private.nest_link` has no policies
/// at all and its functions have execute revoked from every client role.
async function rpcOne(
  env: Env,
  name: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  const response = await fetch(`${env.url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: env.secret,
      authorization: `Bearer ${env.secret}`,
    },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) {
    throw new Error(`${name} failed (${response.status})`);
  }
  const text = await response.text();
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// ── Plumbing ────────────────────────────────────────────────────────────────

interface Env {
  projectId: string;
  clientId: string;
  clientSecret: string;
  url: string;
  secret: string;
}

function readEnv(): Env | { error: string } {
  const names = [
    'SDM_PROJECT_ID',
    'GOOGLE_OAUTH_CLIENT_ID',
    'GOOGLE_OAUTH_CLIENT_SECRET',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY',
  ];
  const values = names.map((name) => Deno.env.get(name));
  const missing = names.filter((_, i) => !values[i]);
  if (missing.length > 0) {
    // Configuration reported as configuration, never as an empty result.
    return { error: `${missing.join(', ')} is not set on this project` };
  }
  const [projectId, clientId, clientSecret, url, secret] = values as string[];
  return { projectId, clientId, clientSecret, url, secret };
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function rateLimited(): Response {
  return json({
    error: 'Hearth has asked the thermostat as often as Google allows this '
      + 'hour. Try again shortly.',
  }, 429);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
