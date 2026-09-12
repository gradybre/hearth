// The page the browser is left looking at, and the hash the nonce is kept as.
//
// Its own module so both can be tested. `index.ts` calls `Deno.serve` at
// module scope, so importing it from a test starts a server and the run fails
// before a single assertion — which is how this file, the only publicly
// reachable one in the project, came to have no tests at all.

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
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

export function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
