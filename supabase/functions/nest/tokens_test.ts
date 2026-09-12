import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import {
  consentUrl,
  exchange,
  GrantRevoked,
  isFresh,
  refresh,
  SCOPE,
  SKEW_MS,
  TokenRefused,
} from './tokens.ts';

/// Where Google is told to send the browser back to.
///
/// A function of Hearth's own, on a Supabase domain no app claims. Google's
/// guide prescribes `https://www.google.com`, which is unusable on a phone:
/// it is a universal link claimed by the Google app, so iOS hands the redirect
/// there and the code never reaches anybody.
const CALLBACK = 'https://project.supabase.co/functions/v1/nest-callback';

const now = new Date('2026-09-13T12:00:00Z');

/// A fetch that answers once, with whatever is handed to it.
function answering(
  status: number,
  body: string,
): { fetcher: typeof fetch; calls: Request[] } {
  const calls: Request[] = [];
  const fetcher = ((input: string | URL | Request, init?: RequestInit) => {
    calls.push(new Request(input as string, init));
    return Promise.resolve(
      new Response(body, {
        status,
        headers: { 'content-type': 'application/json' },
      }),
    );
  }) as unknown as typeof fetch;
  return { fetcher, calls };
}

Deno.test('the consent URL carries everything the flow needs', () => {
  const url = new URL(consentUrl('proj-uuid', 'client-abc', CALLBACK, 'n0nce'));

  assertEquals(url.origin, 'https://nestservices.google.com');
  assertEquals(url.pathname, '/partnerconnections/proj-uuid/auth');
  assertEquals(url.searchParams.get('client_id'), 'client-abc');
  assertEquals(url.searchParams.get('scope'), SCOPE);
  assertEquals(url.searchParams.get('response_type'), 'code');
  assertEquals(url.searchParams.get('redirect_uri'), CALLBACK);
  // The nonce the callback will check. It is the only thing that endpoint
  // trusts, because Google redirects a browser to it and browsers carry no
  // token.
  assertEquals(url.searchParams.get('state'), 'n0nce');
  // Both of these, or the second link back returns no refresh token and the
  // thermostat stops answering an hour later.
  assertEquals(url.searchParams.get('access_type'), 'offline');
  assertEquals(url.searchParams.get('prompt'), 'consent');
});

Deno.test('and it is not the address bar the code used to land in', () => {
  // Regression: Google's own guide prescribes `https://www.google.com`, which
  // on iOS is a universal link claimed by the Google app — the redirect went
  // to that app, which had nothing to do with it, and the flow dead-ended
  // with the code never visible to anybody.
  const url = new URL(consentUrl('p', 'c', CALLBACK, 'n'));
  assertEquals(
    url.searchParams.get('redirect_uri')!.includes('google.com'),
    false,
  );
});

Deno.test('a refresh returns a token that expires when Google said', async () => {
  const { fetcher, calls } = answering(
    200,
    JSON.stringify({ access_token: 'at-1', expires_in: 3600 }),
  );

  const token = await refresh(fetcher, {
    refreshToken: 'rt-1',
    clientId: 'c',
    clientSecret: 's',
    now,
  });

  assertEquals(token.accessToken, 'at-1');
  assertEquals(token.expiresAt.toISOString(), '2026-09-13T13:00:00.000Z');
  assertEquals(calls.length, 1);
});

Deno.test('invalid_grant is its own failure, and never a retry', async () => {
  // The whole reason this file exists. Retrying a revoked refresh token is a
  // reuse storm, which is one of the ways a project earns a harder
  // revocation — so it has to be distinguishable at the type level.
  const { fetcher } = answering(
    400,
    JSON.stringify({ error: 'invalid_grant', error_description: 'expired' }),
  );

  await assertRejects(
    () =>
      refresh(fetcher, {
        refreshToken: 'rt-dead',
        clientId: 'c',
        clientSecret: 's',
        now,
      }),
    GrantRevoked,
  );
});

Deno.test('while any other refusal is retryable weather', async () => {
  const { fetcher } = answering(429, JSON.stringify({ error: 'rate_limited' }));

  const error = await assertRejects(
    () =>
      refresh(fetcher, {
        refreshToken: 'rt-1',
        clientId: 'c',
        clientSecret: 's',
        now,
      }),
    TokenRefused,
  );
  assertEquals((error as TokenRefused).status, 429);
});

Deno.test('a body that is not JSON at all fails with a sentence', async () => {
  // A gateway in front of Google answers with HTML, and `response.json()` on
  // that throws something that says nothing about what went wrong.
  const { fetcher } = answering(502, '<html>Bad Gateway</html>');

  await assertRejects(
    () =>
      refresh(fetcher, {
        refreshToken: 'rt-1',
        clientId: 'c',
        clientSecret: 's',
        now,
      }),
    TokenRefused,
  );
});

Deno.test('a 200 with no usable token is still a failure', async () => {
  const { fetcher } = answering(200, JSON.stringify({ scope: 'something' }));

  await assertRejects(
    () =>
      refresh(fetcher, {
        refreshToken: 'rt-1',
        clientId: 'c',
        clientSecret: 's',
        now,
      }),
    TokenRefused,
  );
});

Deno.test('an exchange without a refresh token is refused', async () => {
  // Storing the access token alone gives an hour of working thermostat and
  // then a dead link, which is worse than failing at link time.
  const { fetcher } = answering(
    200,
    JSON.stringify({ access_token: 'at-1', expires_in: 3600 }),
  );

  await assertRejects(
    () =>
      exchange(fetcher, {
        code: '4/0Ab',
        clientId: 'c',
        clientSecret: 's',
        redirectUri: CALLBACK,
        now,
      }),
    TokenRefused,
  );
});

Deno.test('and an exchange that works carries both tokens', async () => {
  const { fetcher, calls } = answering(
    200,
    JSON.stringify({
      access_token: 'at-1',
      refresh_token: 'rt-1',
      expires_in: 3599,
    }),
  );

  const token = await exchange(fetcher, {
    code: '4/0Ab',
    clientId: 'c',
    clientSecret: 's',
    redirectUri: CALLBACK,
    now,
  });

  assertEquals(token.refreshToken, 'rt-1');
  assertEquals(token.accessToken, 'at-1');
  // The redirect the consent URL carried, byte for byte, or Google answers
  // `redirect_uri_mismatch`.
  const sent = new URLSearchParams(await calls[0].text());
  assertEquals(sent.get('redirect_uri'), CALLBACK);
  assertEquals(sent.get('grant_type'), 'authorization_code');
});

Deno.test('a cached token is used until it is nearly out', () => {
  const soon = new Date(now.getTime() + SKEW_MS - 1000).toISOString();
  const later = new Date(now.getTime() + SKEW_MS + 1000).toISOString();

  // Inside the skew it counts as expired: a token that is valid when the
  // request is made and expired when it arrives produces a 401 that looks
  // exactly like a revoked grant.
  assertEquals(isFresh(soon, now), false);
  assertEquals(isFresh(later, now), true);
  assertEquals(isFresh(null, now), false);
  assertEquals(isFresh('not a date', now), false);
});
