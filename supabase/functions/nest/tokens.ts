// Google's OAuth token endpoint, and the one failure that is not a failure.
//
// An access token lasts an hour; a refresh token lasts until Google decides
// otherwise. `invalid_grant` is Google saying the refresh token is gone —
// revoked in account settings, expired because the consent screen is still in
// Testing (seven days), or unused for six months. It is not a server fault and
// it will never succeed on a retry: retrying it is a refresh-token reuse storm,
// which is one of the ways a project earns a harder revocation.
//
// So it is separated from every other failure at the type level, and the caller
// answers it with a 409 and a sentence about reconnecting rather than a 500 and
// a spinner.

export const TOKEN_URL = 'https://oauth2.googleapis.com/token';

export const SCOPE = 'https://www.googleapis.com/auth/sdm.service';

/// Where to send somebody to grant access.
///
/// Built here rather than in `index.ts` so it can be tested: `index.ts` calls
/// `Deno.serve` at module scope, so importing it from a test starts a server.
///
/// [redirectUri] is passed rather than fixed. Google's own guide prescribes
/// `https://www.google.com`, and on a phone that is unusable — it is a
/// universal link claimed by the Google app, so iOS hands the redirect there
/// and the flow dead-ends with the code never visible to anybody. Hearth
/// redirects to a function of its own instead, on a domain no app claims.
///
/// [state] is the single-use nonce the callback will check. It is the only
/// thing that endpoint trusts, because Google redirects a browser to it and
/// browsers carry no token.
export function consentUrl(
  projectId: string,
  clientId: string,
  redirectUri: string,
  state: string,
): string {
  const query = new URLSearchParams({
    redirect_uri: redirectUri,
    access_type: 'offline',
    // Without this, a second link returns no refresh token at all and the
    // thermostat stops answering an hour later.
    prompt: 'consent',
    client_id: clientId,
    response_type: 'code',
    scope: SCOPE,
    state,
  });
  return `https://nestservices.google.com/partnerconnections/${projectId}`
    + `/auth?${query.toString()}`;
}

/// A refresh that worked.
export interface FreshToken {
  accessToken: string;
  /// When it stops being usable, already adjusted for skew — see [SKEW].
  expiresAt: Date;
}

/// The authorisation is gone. Nothing but consenting again will fix it.
export class GrantRevoked extends Error {
  constructor(readonly detail: string) {
    super(`invalid_grant: ${detail}`);
  }
}

/// Google said no for some other reason, and asking again might work.
export class TokenRefused extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

/// Treat a token as expired this long before it really is.
///
/// A token that is valid when the request is made and expired when it arrives
/// produces a 401 that looks exactly like a revoked grant, which is the one
/// thing this file exists to tell apart.
export const SKEW_MS = 5 * 60 * 1000;

/// Whether a cached token is still worth using.
export function isFresh(expiresAt: string | null, now: Date): boolean {
  if (!expiresAt) return false;
  const at = Date.parse(expiresAt);
  return Number.isFinite(at) && at - now.getTime() > SKEW_MS;
}

/// Exchanges a refresh token for an access token.
export async function refresh(
  fetcher: typeof fetch,
  options: {
    refreshToken: string;
    clientId: string;
    clientSecret: string;
    now: Date;
  },
): Promise<FreshToken> {
  return await post(fetcher, options.now, {
    grant_type: 'refresh_token',
    refresh_token: options.refreshToken,
    client_id: options.clientId,
    client_secret: options.clientSecret,
  });
}

/// Exchanges the code the consent flow handed back.
///
/// [redirectUri] has to match the one the consent URL carried, byte for byte —
/// `redirect_uri_mismatch` is the commonest failure in this whole flow, and it
/// is why one constant is used to build both.
export async function exchange(
  fetcher: typeof fetch,
  options: {
    code: string;
    clientId: string;
    clientSecret: string;
    redirectUri: string;
    now: Date;
  },
): Promise<FreshToken & { refreshToken: string }> {
  const body = {
    grant_type: 'authorization_code',
    code: options.code,
    client_id: options.clientId,
    client_secret: options.clientSecret,
    redirect_uri: options.redirectUri,
  };
  const { token, raw } = await postRaw(fetcher, options.now, body);
  const refreshToken = typeof raw.refresh_token === 'string'
    ? raw.refresh_token
    : '';
  if (!refreshToken) {
    // `access_type=offline` and `prompt=consent` are both on the consent URL,
    // so this means the user has already granted access and Google reissued
    // without a refresh token. Storing the access token alone would give an
    // hour of working thermostat and then a dead link, which is worse than
    // failing here.
    throw new TokenRefused(
      400,
      'Google did not return a refresh token. Remove Hearth from your '
        + 'Google account’s connected apps and link again.',
    );
  }
  return { ...token, refreshToken };
}

async function post(
  fetcher: typeof fetch,
  now: Date,
  body: Record<string, string>,
): Promise<FreshToken> {
  return (await postRaw(fetcher, now, body)).token;
}

async function postRaw(
  fetcher: typeof fetch,
  now: Date,
  body: Record<string, string>,
): Promise<{ token: FreshToken; raw: Record<string, unknown> }> {
  const response = await fetcher(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(body).toString(),
    signal: AbortSignal.timeout(10000),
  });

  // Read as text first: Google answers an error with JSON, but a gateway in
  // front of it answers with HTML, and `response.json()` on that throws
  // something that says nothing about what went wrong.
  const text = await response.text();
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }
  const raw = typeof parsed === 'object' && parsed !== null
    ? parsed as Record<string, unknown>
    : {};

  if (!response.ok) {
    const error = typeof raw.error === 'string' ? raw.error : '';
    if (error === 'invalid_grant') {
      throw new GrantRevoked(
        typeof raw.error_description === 'string' ? raw.error_description : '',
      );
    }
    throw new TokenRefused(
      response.status,
      error ? `Google refused: ${error}` : 'Google refused the request.',
    );
  }

  const accessToken = typeof raw.access_token === 'string'
    ? raw.access_token
    : '';
  const expiresIn = typeof raw.expires_in === 'number' ? raw.expires_in : 0;
  if (!accessToken || expiresIn <= 0) {
    throw new TokenRefused(502, 'Google sent a token Hearth cannot read.');
  }

  return {
    token: {
      accessToken,
      expiresAt: new Date(now.getTime() + expiresIn * 1000),
    },
    raw,
  };
}
