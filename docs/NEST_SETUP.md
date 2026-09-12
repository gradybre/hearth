# Connecting Hearth to a Google Nest

The one-time sequence through Google's two consoles, written down because it
will need repeating in a year when something breaks and none of it is
guessable.

Everything below is done as **the Google account that owns the Nest**. A
thermostat merely shared with a second account usually cannot grant access.

## 1. Google Cloud

1. Create or pick a project.
2. **APIs & Services → Library → Smart Device Management API → Enable**
   (<https://console.cloud.google.com/apis/library/smartdevicemanagement.googleapis.com>).
3. **Google Auth Platform → Data Access → Add or remove scopes**, then the
   *Manually add scopes* box at the bottom:
   `https://www.googleapis.com/auth/sdm.service` → Add to table → Update →
   Save. It is a **restricted** scope; that is expected.
4. **Google Auth Platform → Audience**. A personal Gmail account must be
   **External**; press *Make external* if it offers to.
5. **Publish app**, so publishing status reads **In production**.
   See the warning below — this step is not optional for long.
6. **Credentials → Create credentials → OAuth client ID → Web application**.
   Authorised redirect URI, exactly, with no trailing slash:
   `https://www.google.com`. Leave JavaScript origins empty.
   Keep the **Client ID** and **Client Secret**.

## 2. Device Access Console

<https://console.nest.google.com/device-access>

7. Accept the terms and pay the one-time **US$5** registration. It is per
   Google account, not per project.
8. **Create project**, pasting the OAuth **Client ID** from step 6.
9. Leave **Events** off. Hearth polls; events would need a Pub/Sub topic
   nothing here uses.
10. The **Project ID** is the UUID at the top of the project page. It is *not*
    the Google Cloud project id, which is a slug like `my-first-project-474218`
    — confusing the two is the commonest failure in this setup.

## 3. Hearth

Set three Edge Function secrets. Never in the repo, never in `config/`, never
in a chat message (CLAUDE.md, Secrets hygiene):

```bash
supabase secrets set --env-file ./nest.env && rm ./nest.env
```

with `nest.env` holding:

```
SDM_PROJECT_ID=…
GOOGLE_OAUTH_CLIENT_ID=…
GOOGLE_OAUTH_CLIENT_SECRET=…
```

Then `supabase functions deploy nest`.

## 4. Linking, in the app

House → Thermostat → **Connect Google Nest**. Google opens in a browser.

**Tick the thermostat in Google's device picker.** Skipping this is the
commonest real-world failure: the link "succeeds" and there is nothing to
control. Hearth refuses such a link and says so, rather than saving it.

Google then lands on `https://www.google.com/?code=…`. Copy the `code` value
out of the address bar and paste it into Hearth. Percent-encoded (`4%2F0A…`)
is fine; it is decoded server-side.

---

## The seven-day trap

**While the OAuth consent screen is in "Testing", Google revokes the refresh
token every seven days.** Everything works for a week and then stops, and the
failure looks like an app bug rather than a console setting.

Step 5 above is the fix. It has to be done *and* the thermostat re-linked
afterwards, because the existing token was issued under Testing and publishing
does not rescue it.

While it stays in Testing, the account must also be listed under **Test users**
on the Audience page, or consent fails outright with `access_denied`.

Two related expiries, for completeness:

- A refresh token unused for **six months** is revoked. Ordinary use prevents
  it; a six-month gap means linking again.
- An unverified app using a restricted scope shows Google's "hasn't verified
  this app" interstitial on the consent page. Expected, and one extra click.

All three surface in Hearth the same way: a **409** from the Edge Function,
which the screen shows as *"Google stopped accepting Hearth's connection"* with
a Reconnect button rather than a spinner or a generic error.
