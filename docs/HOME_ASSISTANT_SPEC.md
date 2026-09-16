# Hearth + Home Assistant — implementation handoff

**Written:** 16 September 2026

**Audience:** Claude Code implementing Hearth

**Status:** Proposed feature specification. No Home Assistant functionality is implemented by this document. Brendan's instruction to execute this handoff authorizes the scope below; until then, this is a proposal.

**Authority:** Read `CLAUDE.md` and `docs/HEARTH_SPEC.md` first. When execution is authorized, amend the relevant sections of `HEARTH_SPEC.md` to adopt this feature and reference this document for detail. Keep `HEARTH_SPEC.md` as the product source of truth. Do not quietly lift other deferred features.

## 1. Outcome

Brendan and his partner can use Hearth's House section to see selected door sensors and other household readings, control plugs and bulbs, and view supported cameras connected to Home Assistant on their Raspberry Pi. Home Assistant continues to own pairing, manufacturer accounts, device communication, and automations. Hearth provides a native household interface.

The connection is:

```text
Hearth on iPhone / Mac / Windows
    ↕ authenticated Home Assistant API
Home Assistant on the Raspberry Pi
    ↕ existing integrations
Sensors · plugs · bulbs · cameras
```

Adding a device to Home Assistant makes it discoverable in Hearth's device picker. It does not automatically add it to the dashboard, enable a disabled entity, or grant Hearth a new capability. Devices remain usable in Home Assistant and their manufacturer apps.

## 2. Product decisions for this build

These are proposed defaults, adopted when Brendan asks Claude to execute this handoff. Do not turn routine implementation choices into a new product questionnaire.

| Topic | Decision |
|---|---|
| Platforms | iOS, macOS, Windows; iPhone is the primary design surface. |
| Connection | Native client connects directly to Home Assistant. No Supabase proxy or custom Pi add-on. |
| Authentication | First release uses a Home Assistant long-lived access token entered into a secure setup field. OAuth browser sign-in is a later improvement, not a prerequisite. |
| Household | Each person connects using their own Home Assistant user; each Hearth installation is set up separately. One Home Assistant connection per active Hearth user/household context on that installation. |
| Dashboard preferences | Device-local and scoped to Hearth user + household + connection. Selection and favorites do not sync in this release. |
| Remote access | Support an explicitly configured HTTPS Home Assistant Cloud URL, or a reachable address over an already-configured VPN. Do not create a subscription or change router/VPN settings. |
| Nest | Preserve the existing direct Google Nest integration, routes, and thermostat behavior. Do not migrate it through Home Assistant in this build. |
| Cameras | A required second milestone. Native live view must be proven; a browser link alone does not satisfy the camera milestone. |
| Automations | Continue running in Home Assistant, including when Hearth is closed. No automation editor or scheduler in Hearth. |

Both people see real device changes through Home Assistant, even though their dashboard choices are local. Explain the separate setup clearly: joining a Hearth household does not automatically grant access to Home Assistant. A future shared layout can be added without sharing credentials.

## 3. Scope and capability mapping

Implement generic entity categories rather than a separate adapter per brand. One physical device may expose multiple entities; group related entities using Home Assistant registry relationships when available. Do not infer identity from similar names.

| Category | Required behavior | Limits |
|---|---|---|
| Door/window/contact sensors | Open/closed, unavailable/unknown, last change, associated battery when available. | Read-only; never imply a sensor can open or lock a door. |
| Motion/occupancy/leak sensors | Appropriate text and icon for the reported device class. | Read-only; unknown is never rendered as safe/inactive. |
| Numeric sensors | Selected temperature, humidity, battery, power, and energy readings with reported units. | Missing is not zero. No invented consumption or history. |
| Smart plugs and switches | Explicit on/off controls and confirmed state. Associated power/energy if exposed. | Only selected, ordinary household switches; no arbitrary service-call UI. |
| Lights | On/off; brightness and white temperature/color controls only where supported. | Respect `supported_color_modes`, ranges, and current API conventions. No color control on an on/off-only bulb. |
| Camera/doorbell events | Most recent motion or doorbell event and its timestamp where exposed. | Foreground status, not background push notifications or a recording archive. |
| Cameras | On-demand snapshot where available, native live video where supported, clear unavailable/error states. | One active live stream; no recording or continuous camera wall. |

Treat Ring floodlights as lights and Ring motion/doorbell events as event entities. Do not expose a camera's motion-detection configuration switch as if it were a smart plug. Disabled/hidden/configuration/diagnostic entities are excluded by default; read-only diagnostics such as battery may be associated with a chosen device. Inspect available registry metadata rather than guessing domain semantics from a name.

Deferred: HA thermostat controls, locks, garage doors, covers, alarms, sirens, arbitrary buttons, configuration switches, scenes/scripts, automation editing, background push alerts, event-history persistence, recording playback/download, two-way camera audio, multiple HA servers, shared dashboard sync, and OAuth setup. Unsupported domains appear as unsupported in discovery when relevant, with no controls. Do not add generic “run anything” controls to bypass this boundary.

## 4. User experience

### 4.1 Navigation and setup

Add **Devices** and, when implemented, **Cameras** to the existing House destinations. Retain Thermostat and existing saved launch destinations. Use the registry in `lib/app/shell/` rather than creating a second navigation system. A new installation sees a useful connection explanation and **Connect Home Assistant**.

Setup sequence:

1. Enter the server address. Show a local-address example and explain an optional remote address. Never prefill a real household URL in source code.
2. Explain how to create a separate token in the user's own Home Assistant profile, named for this Hearth installation. Prefer a non-administrator HA account where its available permissions suffice. The user pastes the token into Hearth, never into chat, a repo file, or a command shown in documentation.
3. Test connectivity and authentication without operating devices. Distinguish address/DNS, local-network permission, VPN unreachable, TLS failure, server unavailable, authentication failure, and unsupported server/API behavior.
4. Discover supported entities. Let the user select devices/entities and review the selection before saving. Nothing is selected automatically merely because it appeared.
5. Open the dashboard and show current confirmed state.

Token input is obscured, with deliberate reveal and paste actions, no automatic clipboard reading, and no token echo in errors. Losing secure-storage access must fail clearly; never silently save credentials to ordinary preferences. Validate the connection before replacing a working one; cancellation keeps the existing connection.

Settings offers connection status, edit/test addresses, replace token, manage selected devices, and **Disconnect this device**. Distinguish local removal from revoking the token in Home Assistant. Locally deleting a long-lived token does not revoke it: explain where to revoke it, and never claim otherwise. Disconnecting must still clear local access when the Pi is unreachable.

### 4.2 Devices dashboard

- Favorites first, then rooms using Home Assistant area assignments; unassigned devices have a clear group. Entity area overrides device area where provided. If registry access is unavailable, use entity names and an unassigned group instead of failing the entire dashboard.
- Search by display name/room; device selection and favorites are reversible local choices. Names and rooms remain owned by Home Assistant; no renaming there from Hearth.
- Compact cards with label, state text, icon, and relevant controls. Put raw entity IDs and technical details in an optional details view, not primary UI.
- An opened door says **Open**. A lost connection says **Unavailable** or **Last known: closed**, never an unqualified **Closed**.
- Show **Sending…**, then observed state. A rejected action or an unconfirmed result has a useful retry/status message.
- Keep unknown, unavailable, unselected, removed, unauthorized, and unsupported distinct. A removed selected entity stays as a missing selection until the user removes/replaces it; no reassignment to a similarly named entity.
- Warm Hearth theme, dark mode, Dynamic Type, keyboard access, screen-reader labels, minimum platform-appropriate touch targets, and reduced motion. Status must never depend only on color.

### 4.3 Cameras

Camera cards do not autoplay. Show a labeled placeholder or snapshot with capture/fetch time; fetching an old image now must not claim it was captured now. Opening a camera explicitly starts one live stream. Closing it, switching accounts, disconnecting, leaving the camera view, or backgrounding Hearth stops playback and releases resources. Camera/microphone capture permissions are not needed for viewing; do not request them.

Provide loading, live, reconnect, unsupported format, unavailable, and permission-denied states. A still image must not carry a Live badge. Display event times as “Last doorbell ring” or “Last motion,” not a permanent “Ringing” state.

## 5. Connection, security, and storage

### 5.1 Direct connection and endpoints

Use authenticated REST/WebSocket APIs through adapters. Supabase continues serving Hearth's existing application data; it is not the transport for HA commands, tokens, snapshots, or video. This permits local device control when the internet is down, provided the device integration itself is local and the existing Hearth session can open the app offline.

Support a primary endpoint and an optional explicitly configured alternate endpoint for the **same** HA instance. Prefer the chosen local endpoint with a bounded connection attempt before trying the configured remote endpoint. Manual endpoint selection remains available. Never scan the LAN or discover new credential destinations automatically.

Normalize URL schemes, ports, and paths using URI APIs. Reject user-info, query/fragment credentials, unsupported schemes, and malformed addresses. Remote endpoints require HTTPS with normal certificate validation. Allow plain HTTP only as an explicit local-network setup choice with a concise explanation that it is unencrypted, plus narrow native platform allowances. No blanket TLS bypass or unrestricted app transport exception. Do not classify an arbitrary public host as local based solely on a textual name; account for address resolution and platform behavior.

Each configured origin is a user-authorized credential destination. Explain that the alternate must reach the same installation. A matching location name does not prove server identity. Endpoint changes require validation and explicit save; do not forward authorization headers through cross-origin redirects. Distinguish public internet failure from HA unavailability and Ring cloud failure.

### 5.2 Credential boundaries

Create a dedicated HA credential store using the existing secure-storage approach, separately keyed from the Supabase session. Bind credentials and connection configuration to Hearth user ID, household ID, and a local connection ID. Do not use a globally shared `home_assistant_token` preference.

These are user-supplied runtime credentials, not a bundled API key. Never put them in Dart defines, `config/local.json`, fixtures, source, SQLite, Supabase, exports, analytics, crash reports, or logs. Existing rules against bundled/server secrets continue to apply. Device selection is a presentation filter, **not** a security boundary: Home Assistant enforces the token owner's actual permissions. Do not promise per-entity token scopes that HA does not provide.

Explicit Hearth sign-out, account replacement, household change, disconnect, and invalidated HA authorization tear down sessions and clear the old context's HA credentials and sensitive caches. Ignore callbacks and responses from prior contexts using a connection/session generation guard. Do not interpret a transient Hearth internet outage as sign-out; preserve existing offline-session semantics.

Use Home Assistant profile controls for remote token revocation, including lost-phone guidance. Local household removal cannot revoke an independent Home Assistant account's access; document that distinction. Separate tokens per installation let the owner revoke one without breaking every phone.

### 5.3 Local metadata and state

Use a versioned, scoped record through the existing preference abstraction for non-secret selected entity references, favorites, and display order. Keep endpoints with the connection's secure configuration. Do not store raw HA responses: they can contain access tokens and signed media URLs. Do not create server tables for this release.

Keep live entity states and camera images in memory. Persist only dashboard metadata, not household activity history. After a cold offline launch, selected cards can say “Connect to update”; do not fabricate last-known readings. Clear in-memory state on context changes. Explicitly document export exclusions for credentials, endpoints, HA-owned states/media, and any device-local layout metadata excluded by the existing export contract.

If implementation requires a new Drift schema, follow the existing version bump, schema snapshots, historical migration tests, and generated migration workflow. If a later approved scope introduces Supabase tables, apply household/user ownership deliberately, default-deny RLS, soft deletion for synced records, and the full deployed migration checks. Do not add a migration just to satisfy a guessed design.

## 6. Architecture and state correctness

Suggested boundaries, following existing repository conventions rather than mandating exact filenames:

- Pure Dart models under `lib/domain/house/`: entity identity, category/capabilities, typed state, availability, timestamps, commands, and normalized events. No Flutter imports or raw network payloads in this layer.
- HA transport/auth/credential/camera adapters under `lib/data/`; an injectable gateway exposed through a repository. Features never access sockets, secure storage, or HTTP directly.
- A repository/session controller owns discovery, current state, pending commands, connection generation, reconnection, and lifecycle. Riverpod exposes projections to `lib/features/house/`.
- A separate media adapter encapsulates camera negotiation/player differences. Camera dependencies must not become a requirement for food or thermostat startup.

Use documented API operations for authentication, state retrieval, service discovery/calls, and subscriptions. Registry and camera operations may require consulting the current official frontend/core source: record the exact API contracts and tested HA version in setup documentation. Do not invent an endpoint or assert that an internal operation is stable. If metadata requires administrator rights, degrade grouping gracefully without demanding administrator credentials for basic control.

### 6.1 Read and subscribe

Bootstrap a complete state snapshot and a subscription without losing events between them. Buffer subscription events during snapshot retrieval and merge using a defined ordering policy; test this race and reconnect behavior. Reconcile a fresh snapshot after reconnection instead of trusting an old socket's state. Resolve pending requests by ID and handle server errors, malformed messages, missing attributes, removal, and reconnects without crashing the whole screen.

Keep one active HA state connection for the visible House experience. Stop or suspend it when backgrounded; refresh on return. Use bounded retry with jitter and a manual retry, not an unbounded rapid loop. Invalid credentials halt retry and prompt reconnection. A permissions denial on one entity must not invalidate every entity or trigger repeated authentication attempts.

Separate HA `last_changed`, `last_updated`, and Hearth's last successful synchronization time. An unchanged sensor can be healthy for days. Do not decide it is stale solely because its value has not changed. A broken connection makes the snapshot unverified even if individual entity timestamps look recent.

### 6.2 Commands

Dispatch explicit actions such as switch/light on or off with a specific selected entity target. Do not use an empty target, area-wide fallback, or HA state-writing endpoints to operate hardware. Changing `/api/states` is not a substitute for calling the device service.

Validate the command against current capabilities and permissions. Coalesce slider updates with a short debounce and serialize changes per entity. Render pending intent separately from observed state so late events cannot overwrite a newer pending intention.

Service success means HA accepted/executed the request; it does not by itself prove the physical state. Reconcile with a state event or a bounded state refresh; after a reasonable confirmation deadline, show “Could not confirm” rather than silently claiming success. A command already matching the observed state should not wait for a change event that may never come.

Never persist device commands in Hearth's food sync outbox. No automatic replay after restart, reconnect, endpoint switch, or an ambiguous timeout. If delivery is uncertain, show the latest state and let the user deliberately retry. This applies even to apparently idempotent commands: a delayed replay could undo another person's action.

## 7. Camera and Ring implementation requirements

The current official Ring integration documents live-view and last-recording camera entities, motion/doorbell events, cloud communication, a subscription requirement for last-recording video, and no two-way live-view audio. Verify these against the installed HA version and actual Ring models; do not repeat old advice that Ring universally lacks HA live view. [Official Ring integration](https://www.home-assistant.io/integrations/ring/)

Before building the camera UI, prove an authenticated camera session end to end on each target platform using the installed HA camera capabilities. Evaluate the actual WebRTC/HLS or other supported transport and existing Flutter dependencies. Do not assume a generic video widget can consume any HA camera, that a battery camera is always streaming, or that a Pi should transcode every feed.

Use the HA-mediated camera API and its supported signaling/media flow. Support an authenticated still image where available, then user-initiated live playback. Keep bearer tokens out of ordinary media URLs; where HA requires signed URLs, treat them as short-lived credentials held only in memory. Handle authenticated HLS child resources and WebRTC signaling correctly. Do not forward a general HA bearer token to a Ring/CDN host. Follow legitimate HA-provided media flows with bounded, validated URL handling; never load arbitrary entity attributes as embedded web content.

One active stream at a time; cancel superseded startup requests and release decoders/sockets on teardown. Handle an expired media session with bounded renegotiation, not an infinite reload loop. Live video must be tested remotely as well as locally: working API access does not guarantee media connectivity.

An **Open in Home Assistant** action is a useful fallback using the configured trusted origin, without tokens embedded in the link. It requires the browser's own authentication. This fallback must not be reported as completed native live view.

Camera implementation is a named milestone. If a transport/platform/model cannot be supported, record the precise gap and evidence and ask Brendan about a scope change; continue independent device work. Do not silently drop cameras, promise unsupported talkback, buy a subscription, or install a community Ring integration to conceal a gap.

## 8. Delivery sequence

### A. Confirm contracts and adopt the spec

Read current house rules, spec, navigation, adapters, auth cleanup, preferences, and dependency versions. Record a short implementation plan, update `HEARTH_SPEC.md` for the authorized scope, and choose a tested HA version. Use fakes immediately; lack of live credentials must not block pure models, transport contracts, or UI. Request real connection details only when needed for live verification, and provide an in-app path for token entry.

Prove camera transport feasibility early to reveal platform blockers before promising completion. Do not operate Brendan's live devices during discovery or automated tests without an explicit live-test instruction.

### B. Connection and read-only devices

Secure setup, connection lifecycle, local/remote endpoint handling, discovery, selection review, room grouping, read-only sensors, stale/unknown states, disconnect, and account isolation. Include adapter and widget tests alongside implementation.

### C. Plugs and lights

Capability-driven controls, exact targeting, command confirmation, slider handling, second-client updates, and failure recovery. Preserve Nest and food behavior. Deliver the usable device milestone before camera polish if it helps review, but continue through D.

### D. Cameras and Ring events

Selected camera cards, snapshots where supported, native live playback, event display, teardown, remote media verification, and clear capability limits. Test real Ring live view; mocked media is not sufficient proof.

### E. Finish and hand off

Update setup documentation (`docs/HOME_ASSISTANT_SETUP.md`), product spec, export exclusions, dependency rationale, and test evidence. Follow the repository ship/review/CI process. Distinguish automated completion from Brendan's pending physical-device acceptance. Do not declare the full feature finished when D or required platform verification is still blocked.

## 9. Acceptance and test matrix

Author meaningful automated tests with each milestone. Every discovered bug gets a failing regression test before its fix. Use explicitly fake credentials; never capture real payloads containing credentials or private footage as fixtures.

| Area | Required evidence |
|---|---|
| Setup | Correct connection; bad address/token; valid API but denied entity; cancelled replacement preserves old config; secure-storage failure; local-network permission denied; missing VPN; invalid certificate. |
| Credential isolation | No credential/raw-media leakage in logs, SQLite, export, or Supabase; no cross-origin auth redirect; account A → B → A and household changes; stale callback ignored; sign-out/disconnect cleanup; independent token revocation. |
| Discovery | Multiple entities per device; entity/device area inheritance; registry access denied; unsupported/disabled/configuration entities; selected entity removed/renamed; duplicate friendly names; malformed metadata. Never retarget by label. |
| Live state | Snapshot/subscription race; reconnect; Pi restart; foreground/background; two clients observing changes; unknown versus unavailable; unchanged healthy sensor; old socket response after a new session. |
| Controls | Only chosen entity changes; no all-device service call; on/off-only and dimmable/color bulbs; unit/range handling; rapid slider movement; already-matching state; service refusal; accepted-but-unconfirmed command; ambiguous timeout; no replay on reconnect. |
| Offline | Food still works offline; local devices work without internet when possible; cloud-dependent Ring can fail independently; cold offline launch shows no invented readings; stale controls cannot enqueue operations. |
| Media | Authenticated snapshot; native live startup on each platform; expired media authorization; LAN and remote playback; unsupported format; absent snapshot; still versus live labeling; switching cameras; no background stream/resource leak; no token-bearing link/log. |
| UX | Light/dark theme, large text, VoiceOver/semantics, keyboard interaction, reduced motion, missing device, no selections, reconnect and permission errors, preserved Nest and saved launch destinations. |

Run `dart format`, `flutter analyze`, relevant tests, and the full required repository checks, reading process exit codes. Build native targets where runners are available. Record the HA version, device model, integration, transport, and platform for live evidence; unsupported or unavailable test hardware is **pending**, never passed.

Manual acceptance with Brendan and partner, once explicitly authorized:

1. Connect each phone independently and select a door sensor, plug, bulb, and available Ring camera.
2. Open/close the door and verify accurate state; switch the chosen plug; set bulb brightness and supported color. Observe changes made from Home Assistant and the partner's phone.
3. Switch the phone to cellular with configured remote access; repeat a control and live camera view. Confirm VPN-required behavior where applicable.
4. Stop/restart the Pi or interrupt connectivity; verify honest unavailable state, recovery, and no delayed command replay.
5. View Ring live video and a doorbell/motion event; verify media stops after leaving/backgrounding. Document model/integration limits.
6. Disconnect/sign out and verify no HA data or controls remain accessible in that Hearth context. Check existing food and Nest flows still work.

The final implementation report must list completed milestones, automated results, actual platform/live-device results, unverified cases, and remaining blockers. A green mock suite does not establish real Ring playback or remote connectivity.

## 10. Official references

Checked while drafting on 16 September 2026; recheck before implementation because installed HA versions and integrations vary.

- [Authentication and token handling](https://developers.home-assistant.io/docs/auth_api/)
- [WebSocket API](https://developers.home-assistant.io/docs/api/websocket/)
- [REST API](https://developers.home-assistant.io/docs/api/rest/)
- [Remote access](https://www.home-assistant.io/docs/configuration/remote/)
- [Binary sensors](https://www.home-assistant.io/integrations/binary_sensor/)
- [Switches](https://www.home-assistant.io/integrations/switch/)
- [Lights](https://www.home-assistant.io/integrations/light/)
- [Cameras](https://www.home-assistant.io/integrations/camera/)
- [Ring](https://www.home-assistant.io/integrations/ring/)

Relevant existing code: `lib/data/adapters/thermostat.dart`, `lib/data/adapters/edge_function_thermostat.dart`, `lib/features/house/thermostat_screen.dart`, `lib/data/auth/secure_session_storage.dart`, `lib/data/auth/account_cache.dart`, `lib/data/local/preference_store.dart`, and `lib/app/shell/`.
