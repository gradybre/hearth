// Where Google sends the browser back to (spec §11).
//
// Its own function because `verify_jwt` is per-function, not per-route: Google
// redirects a browser here with no token, so this one has to accept an
// unauthenticated GET — and putting it alongside `nest` would have turned
// every authenticated action there into one that verifies a JWT by hand.
//
// The first design skipped this entirely and asked the user to copy the
// `?code=` out of the address bar, which Google's own guide suggests. It does
// not work on a phone: `google.com` is a universal link claimed by the Google
// app, so iOS hands the redirect to that app and the flow dead-ends with the
// code never visible. A Supabase domain is claimed by nothing.
//
// The whole surface is one GET that trusts exactly one input — a nonce this
// project minted itself, hashed at rest, single-use, ten minutes to live. It
// reads no body, sets no cookie, and its HTML contains no code, no state and
// no token: a page that echoed any of those would have published them into the
// browser's history and anywhere the page is later shared.

import { exchange, GrantRevoked, TokenRefused } from '../nest/tokens.ts';
import { thermostatsIn } from '../nest/sdm.ts';

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'GET') return page('That link does not work here.');

  const env = readEnv();
  if ('error' in env) return page(env.error);

  const url = new URL(request.url);
  const state = url.searchParams.get('state') ?? '';
  const code = url.searchParams.get('code') ?? '';
  const refused = url.searchParams.get('error') ?? '';

  if (!state) return page('That link is missing something Hearth needs.');

  // Claimed before anything else is done with it, including when the user
  // pressed Cancel: a nonce left unclaimed after a refusal is a nonce that can
  // be replayed.
  const claim = await claimNonce(env, state);
  if (!claim) {
    // Expired, already used, or never existed. Deliberately one sentence for
    // all three: the difference is only ever useful to somebody guessing.
    return page(
      'That connection attempt has expired or was already finished. '
        + 'Start again from Hearth.',
    );
  }

  if (refused) {
    return page('Hearth was not given access. Nothing has changed.');
  }
  if (!code) return page('Google did not send a code back.');

  try {
    const token = await exchange(fetch, {
      code,
      clientId: env.clientId,
      clientSecret: env.clientSecret,
      redirectUri: env.callbackUrl,
      now: new Date(),
    });

    // Google requires one devices.list to complete authorization; without it
    // the project never appears in the Partner Connections Manager.
    const listed = await sdmDevices(env, token.accessToken);
    const thermostats = thermostatsIn(listed);
    if (thermostats.length === 0) {
      // The commonest real failure by a distance: the device picker was left
      // unticked. Saying so beats saving a link with nothing behind it.
      return page(
        'No thermostat was shared with Hearth. Start again from Hearth and '
          + 'tick the thermostat in Google’s device list.',
      );
    }

    const chosen = thermostats[0];
    await rpc(env, 'nest_link_save', {
      p_household: claim.household_id,
      p_project_id: env.projectId,
      p_refresh_token: token.refreshToken,
      p_linked_by: claim.started_by,
      p_device_name: chosen.name,
      p_device_label: chosen.label,
    });
    // All of them, not just the first. A house with Downstairs and Upstairs
    // had one of them silently not exist.
    await rpc(env, 'nest_link_save_devices', {
      p_household: claim.household_id,
      p_devices: thermostats,
    });
    await rpc(env, 'nest_link_save_access_token', {
      p_household: claim.household_id,
      p_access_token: token.accessToken,
      p_expires_at: token.expiresAt.toISOString(),
    });

    return page(
      `Hearth is connected to ${
        escapeHtml(thermostats.map((t) => t.label).join(' and '))
      }. You can close this tab and go back to Hearth.`,
      true,
    );
  } catch (error) {
    if (error instanceof GrantRevoked) {
      return page('Google would not accept that. Start again from Hearth.');
    }
    if (error instanceof TokenRefused) {
      return page(escapeHtml(error.message));
    }
    // Never the underlying message: it can carry a device id or a fragment of
    // a token, and this page ends up in somebody's browser history.
    return page('Something went wrong finishing the connection.');
  }
});

async function claimNonce(
  env: Env,
  nonce: string,
): Promise<{ household_id: string; started_by: string } | null> {
  const hash = await sha256Hex(nonce);
  const rows = await rpc(env, 'nest_claim_link', { p_token_hash: hash });
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const row = rows[0];
  return typeof row === 'object' && row !== null
    ? row as { household_id: string; started_by: string }
    : null;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function sdmDevices(env: Env, token: string): Promise<unknown> {
  const response = await fetch(
    `https://smartdevicemanagement.googleapis.com/v1/enterprises/`
      + `${env.projectId}/devices`,
    {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(15000),
    },
  );
  if (!response.ok) {
    throw new TokenRefused(
      response.status,
      'Google would not list the devices on that account.',
    );
  }
  return await response.json();
}

async function rpc(
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
  if (!response.ok) throw new Error(`${name} failed (${response.status})`);
  const text = await response.text();
  if (!text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

interface Env {
  projectId: string;
  clientId: string;
  clientSecret: string;
  callbackUrl: string;
  url: string;
  secret: string;
}

function readEnv(): Env | { error: string } {
  const names = [
    'SDM_PROJECT_ID',
    'GOOGLE_OAUTH_CLIENT_ID',
    'GOOGLE_OAUTH_CLIENT_SECRET',
    'NEST_CALLBACK_URL',
    'SUPABASE_URL',
    'SUPABASE_SERVICE_ROLE_KEY',
  ];
  const values = names.map((name) => Deno.env.get(name));
  const missing = names.filter((_, i) => !values[i]);
  if (missing.length > 0) {
    return { error: `${missing.join(', ')} is not set on this project.` };
  }
  const [projectId, clientId, clientSecret, callbackUrl, url, secret] =
    values as string[];
  return { projectId, clientId, clientSecret, callbackUrl, url, secret };
}

/// A self-contained page: no scripts, no external assets, nothing to load.
///
/// It does not call `window.close()` — browsers refuse for a tab they did not
/// open, so it would simply look broken — and it does not redirect anywhere.
/// `no-store`, because the URL that produced it carried a one-time code.
export function page(message: string, ok = false): Response {
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearth</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; display: grid; place-items: center; min-height: 100vh;
         font: 17px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         background: #F5F0E6; color: #3B2F2A; padding: 24px; }
  main { max-width: 28rem; text-align: center; }
  h1 { font-size: 1.25rem; margin: 0 0 .5rem; }
  p { margin: 0; color: #6B5B53; }
  @media (prefers-color-scheme: dark) {
    body { background: #241F1C; color: #EFE7DC; }
    p { color: #B6A89E; }
  }
</style>
</head><body><main>
<h1>${ok ? 'Connected' : 'Not connected'}</h1>
<p>${message}</p>
</main></body></html>`;

  return new Response(html, {
    status: ok ? 200 : 400,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
