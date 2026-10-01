# Accounts, navigation, data ownership and House

Prepared against the merged Groups 1–10 baseline. These are proposal details,
not current approval or delivery status. The sole decision record is
[UX_PHASE_2_APPROVALS.md](../UX_PHASE_2_APPROVALS.md). Its recorded answers take
precedence over any preparation-time status in the source notes below.
Group 11 was approved on 2026-10-01 after these packets were prepared.


Read-only preparation against the source at `f478498` (the merged Groups 9–10).
These are unasked proposals, not permission to implement. Final group numbers
belong to the coordinator. Every card needs Approve / Modify / Skip buttons.
UX-083 is complete in Group 4. UX-084 was presented as Group 13, and UX-087 as
Group 12; do not offer those scopes a second time.

## Email next steps (`email-next-step`, UX-075)

**Card:** After creating an account, show the masked email, a paced Resend
confirmation button and Use a different email. Password recovery ends with a
clear success state and Continue to the intended screen, retaining the recovery
gate until the password is set. Small change, no AI. No social login or extra
onboarding wizard. Can run independently of food screens.

**Evidence / ownership:** `sign_in_screen.dart` currently has check-email copy;
`new_password_screen.dart` already has a gated success/Continue flow. Extend
`AuthGateway` through its implementations for confirmation resend; coordinator
owns provider/harness changes. Do not describe password recovery as missing.

## Personal food shortcuts (`food-shortcuts`, UX-078, UX-079)

**Card:** Put Your food preferences in recipe generation and the Food menu, with
a link explaining preferences versus nutrition targets. Add Shopping to Opens
on. After voluntarily visiting the same supported destination on three distinct
days, offer one dismissible Open here next time prompt with Undo; never switch
automatically. All opening choices are for this device. Small-to-medium change,
no AI, no required profile setup. Queue shared generation/settings changes.

**Evidence / ownership:** `recipe_chat_screen.dart` reads the private profile but
only describes it; `settings_screen.dart:232` links the profile under Account;
`launch_target.dart` supports Home, Today and furnished sections, not Shopping.
Own launch target and contextual UI; coordinator owns preferences/providers.
This is not a new macro-goal calculator or a settings search engine. A future
global unit preference belongs in food/display settings, not account security.

## Useful Home and honest future rooms (`home-summary`, UX-076, UX-077)

**Card:** Give Home at most three actionable rows: the agreed household dinner,
remaining shopping items with freshness, and an optional private food-today
summary. Keep Food and House prominent and put unfinished Fitness/Health in a
compact Coming later area. The personal summary can be hidden and never shows
the partner's diary. Medium change, no AI. Dinner waits for the separately
approved shared-dinner model. This explicitly changes the current no-live-Home
rule; a typed section-summary interface keeps modules separate.

**Evidence / ownership:** `home_screen.dart` renders static cards from
`builtSections`; `sections.dart` registers Fitness/Health as built despite
unfurnished destinations. Spec §6.2 prohibits live Home data and §11 supports
walkable future rooms. Reconcile both on approval. No paid sketches are part
of this packet (UX-038 is a separate recipe-image policy decision).

## Resolve overlapping household edits (`shared-edit-choice`, UX-080)

**Card:** Preserve a draft when the same shared recipe or shopping quantity
changes elsewhere. Explain who changed it and show the relevant before/after
values, with Keep theirs / Use mine. Ordinary unrelated updates stay quiet.
Medium-to-large change, no AI. This explicitly replaces silent handling of
overlapping edits; it does not introduce general recipe version history.

**Evidence / ownership:** `sync_engine.dart` has whole-record timestamp and
unsent-local protection; `sync_scope.dart` does not carry a user-facing conflict
inbox. Spec §4/§7.1 choose silent updates. Depends on named household membership
and reliable update versions; sync/schema/repositories are coordinator-owned.
Do not replace newer data merely because a stale dialog was confirmed.

## Ready for poor signal (`offline-ready`, UX-081)

**Card:** Add Keep this week on this phone to Plan/Shopping. Show which linked
recipes, list data and photos are available, which downloads remain and which
actions need a connection. Prefer automatic existing text caching; the action
finishes/verifies the chosen week's essentials without creating another library.
Medium change, no AI. Queue shared Plan/Shopping entry points.

**Evidence / ownership:** local text caching exists; `photo_sync.dart` downloads
photos in bounded batches. Readiness must distinguish missing images from failed
downloads and never promise cloud completeness. Own a readiness projection and
sheet; coordinator integrates stores/providers and reuse of photo download work.

## Named sync recovery (`sync-recovery`, UX-082)

**Card:** Replace unexplained stuck counts with a list such as Milk quantity
saved on this phone or Lasagne photo waiting to upload. Offer Retry, Open item,
and Export affected data when available. Group repeated network failures and
move version/schema numbers under Support details. Medium change, no AI. Keep
unsent work; retry never duplicates the action. Can build the screen alongside
food UI, with sync/export integration sequenced.

**Evidence / ownership:** `settings_screen.dart` already has last-full-sync,
pending/stuck counts and retry; `pending_write_store.dart` retains failures.
This extends those features rather than rebuilding sync. Names must be resolved
only in the current account/household. Coordinator owns the queue/provider APIs.

## Verify and restore a Hearth backup (`archive-restore`, UX-085)

**Card:** Add Verify backup with no writes, then Import Hearth archive with a
preview of dates, counts, missing files, duplicates and unsupported fields.
Offer an additive reviewed merge or a new solo household; never silently replace
the current shared library. Preserve frozen history. Large change, no AI, after
the archive and ownership foundations. This brings previously deferred restore
into scope if approved; an actual restore still requires its in-app confirmation.

**Evidence / ownership:** `data_export.dart` has versioned JSON/manifest but no
restore UI. Depends on archive Group 13 and a safe household separation/new-space
path for its new-solo option. Separate parsing/preview can run first; schema,
sync, export and ownership integration are serialized. Verify a representative
six-month round trip, including deleted-source references and future fields.

## Bring repeat foods from the old tracker (`tracker-transition`, UX-086)

**Card:** Offer two honest ways to switch: seed the ten foods/meals you repeat,
or inspect an actual CSV/JSON you choose. A file import previews column mapping,
units, dates and sample rows, clearly flagging missing facts and preserving the
original evidence. No file means a forward-only two-week trial, not invented
backfill. Medium change, no AI for structured files. File-specific support is
bounded by the real supplied format; no MacrosFirst API/export is assumed.

**Evidence / ownership:** existing food/recipe creation and Hearth JSON export
do not ingest a previous tracker. No source file was supplied. Own a transition
screen plus reviewed importer adapter; coordinate with onboarding, food capture
and personal-log storage. Screenshot extraction would be a separate AI decision.

## Consistent amounts and uncertainty (`nutrition-readability`, UX-088)

**Card:** Keep Hearth's cream/cocoa/terracotta identity while making primary
amounts and units easy to scan. Standardize short Estimated / Partial / Unknown
labels across food, recipe and plan summaries, with icons/text in both themes.
Missing nutrition must not look like a confident zero. Small-to-medium change,
no AI. Roll out by screen after its current owner finishes; don't globally
shrink text or treat dark-mode color alone as meaning.

**Evidence / ownership:** shared theme styles and partial coverage semantics
already exist in `macro_rings.dart`/`minor_nutrient_bars.dart`. New logged details
are implemented by Group 9. Scope owns presentation consistency; the separate
nutrient-contributor packet owns the drill-down, not these cross-screen badges.

## Complete accessible actions and recovery (`accessible-actions`, UX-089)

**Card:** Finish full keyboard/screen-reader journeys for shopping, scanning and
logging: named actions without mandatory swipes, predictable Tab/Enter/Escape,
focus returned after sheets and one concise result announcement. Respect longer
assistive action timing. Add a recent-changes recovery list for supported
shopping and personal-log actions so a missed snackbar is not the only chance.
Medium-to-large change, no AI. Undo uses the same newer-change safeguards as
Group 11 and never rewrites someone else's later edit.

**Scope / evidence:** `undo_snackbar.dart` currently uses six seconds; semantics
primitives already exist. Recommend the latest 20 eligible local changes for
24 hours per account, with readable expired/unavailable explanations. This is
not shared recipe version history. Persistence/recovery is a scoped extension,
and real native keyboard/VoiceOver acceptance must be reported separately from
automated semantics. Shared widgets/data APIs serialize screen integration.

## Quiet, useful reminders (`food-reminders`, UX-090)

**Card:** Add separate opt-ins for a weekly planning time, a personal logging
reminder and additions received while actively shopping. Keep every category
off by default, offer quiet hours and batch partner additions for roughly a
minute. Suppress duplicates while viewing the list. Dinner's ready is an
explicit send action, never an automatic timer message. Medium-to-large change,
no AI; background partner delivery needs the notification infrastructure and
shared shopping/dinner foundations before it can be claimed.

**Evidence / ownership:** native kitchen notifications cover timers only;
spec §7.3 allows optional reminders. Coordinate with active shopping/freshness
and shared dinner. Implement local scheduled reminders and event delivery behind
adapters; preserve timer delivery. Approval of software does not send a real
Dinner's ready notification during development.

## Food actions outside the app (`food-widgets`, UX-091)

**Card:** Start on iPhone with Tonight and Shopping widgets plus shortcuts for
Add shopping item and Open today's log. Show stale data honestly; personal
calorie totals stay off the lock screen by default. An optional Log recent food
shortcut still confirms its amount. Medium-to-large native change, no AI.
Queue Tonight behind shared dinner. This does not enable deferred voice cooking
or a Claude voice assistant; phone reliability comes before watch controls.

**Evidence / ownership:** native share intake and timer notifications already
exist; no implemented WidgetKit/AppIntent features were found. Own native
extensions, safe shared snapshots and explicit app routes, with coordinator
handling shared persistence/build configuration. Native device validation is
required before claiming widget/background reliability.

## Optional personal-screen lock (`personal-lock`, UX-092)

**Card:** Add opt-in device biometrics/passcode for personal nutrition/settings,
with an alternative whole-app lock. Let the user deliberately keep Shopping or
Cook convenient, obscure private app-switcher previews and protect private
widget drill-ins. Medium change, no AI. This lifts previously deferred app-lock
scope if approved; it is a local privacy boundary, not a claim of database
encryption or replacement for household access rules.

**Evidence / ownership:** secure auth storage is implemented, no lock UI/native
lock adapter is present. Own lock state/adapters; coordinate router/native/widget
entry points and recovery so offline access cannot strand the user.

## Leave a household with clear ownership (`household-exit`, UX-093)

**Card:** Show the two named members and a reviewed Leave this household flow.
Explain retained private logs, the shared-food/recipe copies that follow the
person and integrations needing relinking. Offer export first, require explicit
confirmation, revoke stale invites and show a receipt. Large change, no AI.
This brings the previously deferred unlink flow into scope; deleting an account
remains a separate decision. Queue after invitation/identity and archive work.

**Evidence / ownership:** Settings can join/sign out but cannot unlink;
`household_join` migrations merge shared data; §5.1 intends retained copies.
Server ownership transition/RLS, sync, local reset and export are coordinator
integration. The app must not silently discard either person's unsent work or
expose the other person's diary during transition.

## A complete first Home Assistant view (`ha-useful-view`, UX-094, UX-095)

**Card:** Finish setup with rooms and device selection, then a favorites view
for supported temperature/battery/leak/contact readings and lights/switches.
Suggest a few useful devices without forcing them. Show last-known/unavailable
state and command confirmation. Include Change server, Reconnect and Forget
this phone; explain that HA credentials are device-local while Nest is shared.
Large change, no AI. Preserve later camera/broader-device scope separately; no
raw token sync. This can run independently of food work when a lane is free.

**Evidence / ownership:** `ha_connect_route.dart` explicitly ends at connection;
domain selection, area, sensor and command foundations already exist. Setup
already masks credentials and has token instructions; extend rather than replace.
Own House HA UI/repository/domain; coordinator owns shared registration/provider
integration. No live physical device commands during implementation tests.

## Readable thermostat controls (`nest-readability`, UX-096)

**Card:** At large text, lead with a compact room / current temperature / state
summary, then the setpoint and full-size plus/minus controls. Keep the generous
display at ordinary text sizes. Add a Fahrenheit/Celsius display choice while
preserving actual device command units and pending confirmation. Small-to-medium
change, no AI. Queue behind other thermostat screen work.

**Evidence / ownership:** `_Ambient` uses a 56-point Fahrenheit reading;
`_Target` already has large controls. This changes density and display units,
not the HVAC safety model or automatic physical settings.

## Finish the Nest connection handoff (`nest-return`, UX-097)

**Card:** After Google authorization, show an Open Hearth button plus fallback
instructions and return to the thermostat. Name the household member who linked
it and the last successful device read; distinguish expired permission from an
unavailable thermostat. Reconnection says who can do it, and disconnect keeps
its household-wide consequence explicit. Small-to-medium change, no AI; existing
Nest API limits remain separate. Sequence with thermostat readability.

**Evidence / ownership:** callback `page.ts` has no app return button; the app
currently says someone else in the house. OAuth success alone is not a successful
device read. Own callback/route and thermostat connection presentation; identity
and backend link fields are coordinator integration. The development task does
not itself reconnect or disconnect the user's real devices.

## Future-only decisions

These cards must say **Approve for later / Modify / Skip**. They record roadmap
direction after Food usefulness, not permission to start them during this pass.

### Household availability (`future-availability`, FUT-001)

Home / Out / Late / Guests blocks beside the shared dinner plan, with optional
time and a later opt-in read-only busy/free calendar connection. Do not import
private event titles by default. Medium, no AI; depends on shared dinner. A full
calendar replacement and two-way calendar editing remain outside this packet.

### Kitchen-linked chores (`future-chores`, FUT-002)

Shared tasks with optional owner, recurrence, due window, Done and Snooze.
Default owner Either of us; link defrost/prep to meals and allow travel pauses.
No points or partner rankings. Medium, no AI; connects to availability/reminders.

### Household supply lists (`future-supplies`, FUT-003)

Named Groceries, Home supplies and Errands lists; deliberately combine selected
lists for a trip. Ordinary supplies need only name/quantity/store, with Buy again
for repeats. Keep recipe/nutrition links only on food. Medium, no AI; depends on
the shopping-trip/list foundation, not fake zero-calorie food records.

### Home maintenance (`future-maintenance`, FUT-004)

Asset cards for filters/batteries with model, consumable size, manual, last
service and next reminder. Completing a task can offer to add a replacement to
supplies. Device readings may suggest tasks only after opt-in. Medium, no AI;
depends on chores/supplies/documents. Unknown readings never mean an asset is safe.

### Bills and grocery spending (`future-bills`, FUT-005)

A modest manual shared ledger for recurring bills and confirmed grocery receipts:
amount/currency, due/paid date, payer and household/personal scope. Show upcoming
obligations and monthly totals. Large, no AI in this version; no bank connection
or inferred purchase from a Walmart link. Receipt extraction is a later decision.

### Household document drawer (`future-documents`, FUT-006)

Keep original manuals, warranties and receipts linked to assets/purchases/events,
with explicit shared/private scope, optional renewal date, search where text is
available and ordinary-file export. Large, no AI by default. Private health or
financial files never become household-shared automatically.

### Hosting occasions (`future-hosting`, FUT-007)

An occasion has date, guest count/restrictions, dishes and a prep checklist.
Review scaled shopping additions and reuse an occasion next year; guest needs
do not overwrite either person's profile. Medium, no AI by default. An optional
future Suggest menu action would use an explicit budgeted recipe-generation
request; no autonomous shopping or invitation sending. Depends on dinner,
availability, scaling and chores.

## Coverage

UX-075 email-next-step; 076/077 home-summary; 078/079 food-shortcuts;
080 shared-edit-choice; 081 offline-ready; 082 sync-recovery;
083 completed Group 4; 084 presented Group 13; 085 archive-restore;
086 tracker-transition; 087 presented Group 12; 088 nutrition-readability;
089 accessible-actions; 090 food-reminders; 091 food-widgets; 092 personal-lock;
093 household-exit; 094/095 ha-useful-view; 096 nest-readability; 097 nest-return.
FUT-001–FUT-007 all mapped above. All unpresented packets remain unapproved.
