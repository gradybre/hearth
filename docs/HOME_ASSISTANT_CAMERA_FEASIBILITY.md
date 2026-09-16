# Home Assistant cameras — native live view feasibility

**Written:** 16 September 2026
**Status:** Research only. No code, no dependency, no spec amendment. This document
answers one question and stops: *can Hearth show native live camera video on iOS,
macOS and Windows, and over what transport?*
**Method:** Public documentation, the Home Assistant Core source on GitHub, pub.dev,
package issue trackers, and the local toolchain. **Brendan's Home Assistant instance,
Raspberry Pi and Ring devices were not contacted and no credentials were sought.**

---

## 0. The short answer

**Yes — on all three platforms, by exactly one transport: WebRTC, signalled over the
Home Assistant WebSocket, played by `flutter_webrtc`.**

No platform has to be dropped. But the route is narrower than it looks, for a reason
that only shows up in the Ring source:

> **Ring's `live_view` camera is WebRTC-only. It does not offer HLS at all.**
> HA skips every WebRTC provider and never registers an HLS stream for a camera that
> implements a native WebRTC offer handler, and Ring does. So the HLS path — the one
> `video_player` and `media_kit` could consume — is not merely the slower option for
> Brendan's cameras. For Ring live view **it does not exist**.

That collapses the decision. WebRTC is not one candidate among several; for the camera
hardware the spec names, it is the only candidate. Everything else in this document is
either evidence for that, or contingency for non-Ring cameras added later.

A second finding that is a product question, not an engineering one:

> **Ring still images appear to require a Ring Protect subscription**, because HA derives
> the `live_view` snapshot by running ffmpeg over the last *recording*. See §3.3. If
> Brendan has no subscription, the "snapshot on the camera card" half of spec §4.3 may
> have nothing to show, even though live view itself works. Unverified — settled by §6.

---

## 1. What transports Home Assistant actually offers

Evidence is the HA Core source at `dev` (read 16 Sep 2026), because the prose docs do
not describe the transport negotiation and the negotiation is the whole question.
Version context: `homeassistant/const.py` on `master` reads `2026.9.2`; on `dev` it
reads `2026.10.0.dev0`. **Brendan's installed version is unknown — see §6.**

| Transport | Status | How the client gets it | Evidence |
|---|---|---|---|
| **WebRTC** (native or via go2rtc) | **Current.** The preferred path since HA 2024.11 | WebSocket `camera/webrtc/offer`, `camera/webrtc/candidate`, `camera/webrtc/get_client_config` | `homeassistant/components/camera/webrtc.py` lines 252–357 (command registrations); [go2rtc integration](https://www.home-assistant.io/integrations/go2rtc/) "Introduced in Home Assistant 2024.11" |
| **HLS / LL-HLS** via the `stream` integration | **Current**, but only for cameras that expose an ffmpeg-compatible `stream_source()` | WebSocket `camera/stream` → `{"url": "/api/hls/<token>/master_playlist.m3u8"}` | `camera/__init__.py` 953–980; `stream/__init__.py` `endpoint_url()` 352–359; `stream/hls.py` line 42 `"/api/hls/{}/master_playlist.m3u8"` |
| **MJPEG** via the camera proxy | **Current but legacy-flavoured** — a fallback, high bandwidth, no audio | `GET /api/camera_proxy_stream/<entity_id>` | `camera/__init__.py` line 909 `class CameraMjpegStream`, `url = "/api/camera_proxy_stream/{entity_id}"` |
| **Still image** via the camera proxy | **Current.** Not live view; satisfies the snapshot half of spec §4.3 only | `GET /api/camera_proxy/<entity_id>` | `camera/__init__.py` line 885 `class CameraImageView` |

### 1.1 The negotiation rule that decides everything

`camera/capabilities` (a WebSocket command, `camera/__init__.py` 935–951) returns the
set of stream types the frontend may use. It is computed at lines 809–820:

```python
frontend_stream_types = set()
if CameraEntityFeature.STREAM in self.supported_features:
    if self._supports_native_async_webrtc:
        # The camera has a native WebRTC implementation
        frontend_stream_types.add(StreamType.WEB_RTC)
    else:
        frontend_stream_types.add(StreamType.HLS)
        if self._webrtc_provider:
            frontend_stream_types.add(StreamType.WEB_RTC)
```

`_supports_native_async_webrtc` is simply "did this integration override
`async_handle_async_webrtc_offer`" (line 470–473). So:

- **Native-WebRTC camera** (Ring): capabilities = `{web_rtc}`. **No HLS, ever.** The
  `else` branch that adds HLS is not reached, and line 729 additionally skips provider
  registration entirely — go2rtc is not consulted for such a camera.
- **Ordinary RTSP camera**: capabilities = `{hls}`, plus `{web_rtc}` if go2rtc is
  running. Both paths available.

This matches the developer docs' own wording: implementing the WebRTC methods
"signals to the frontend that the camera exclusively supports WebRTC, preventing
fallback to HLS" ([camera entity docs](https://developers.home-assistant.io/docs/core/entity/camera/)).

**Design consequence for Hearth:** the media adapter must call `camera/capabilities`
per entity and branch, not assume a house-wide transport. A camera wall with a Ring
doorbell and a generic RTSP camera needs both code paths.

### 1.2 Signalling shapes (verified against source, not invented)

Client → `camera/webrtc/offer` with `{entity_id, offer}`. HA replies with a normal
result, then pushes `event` messages on the same subscription id. Message `type` is
derived from the class name lowercased after the `WebRTC` prefix
(`webrtc.py` 40–53), giving:

| `type` | Payload | Class |
|---|---|---|
| `session` | `session_id` | `WebRTCSession` (sent first, always) |
| `answer` | `answer` (SDP string) | `WebRTCAnswer` |
| `candidate` | `candidate` (dict) | `WebRTCCandidate` |
| `error` | `code`, `message` | `WebRTCError` |

Client → `camera/webrtc/candidate` with `{entity_id, session_id, candidate}` for
trickle ICE. `camera/webrtc/get_client_config` returns `{"configuration": {...}}`
(ICE servers) and optionally `"dataChannel"` (`webrtc.py` 95–112). Closing the
subscription tears down the session — `connection.subscriptions[msg["id"]] =
partial(camera.close_webrtc_session, session_id)` (line 276).

That maps cleanly onto spec §7's "one active stream, release on teardown": closing the
WebSocket subscription *is* the teardown signal.

### 1.3 Credential handling, which the spec cares about

- **HLS** returns a **signed path** — `/api/hls/<hex token>/master_playlist.m3u8`, token
  from `secrets.token_hex()` (`stream/__init__.py` 356–357). No bearer header is
  needed on the media URL or its child segments. That is good for players that cannot
  set headers, and it is exactly the "short-lived credential held only in memory" the
  spec §7 describes. It must not be logged or persisted.
- **Still images / MJPEG** at `/api/camera_proxy*` require either the bearer token or
  the per-entity `access_token` that HA embeds in `entity_picture`
  (`ENTITY_IMAGE_URL = "/api/camera_proxy/{0}?token={1}"`, line 125). **Prefer the
  bearer header over the `?token=` query form** — spec §5 forbids credentials in query
  strings, and the house privacy rules say the same.
- **WebRTC** carries no token on the media path at all. Signalling rides the already
  authenticated WebSocket; media flows peer-to-peer. This is the cleanest of the three
  against spec §7's "keep bearer tokens out of ordinary media URLs" and "do not forward
  a general HA bearer token to a Ring/CDN host."

---

## 2. Flutter packages, per transport, per platform

Hearth's targets and their current floors, from this repo: iOS 15.0
(`ios/Runner.xcodeproj/project.pbxproj`, `IPHONEOS_DEPLOYMENT_TARGET = 15.0`),
macOS 12.0 (`macos/.../project.pbxproj`, `MACOSX_DEPLOYMENT_TARGET = 12.0`), and a
`windows/` runner directory is present.

### 2.1 The matrix

Legend: **works** = the package vendor states current support for that platform and
transport; **does not work** = the vendor states it is unsupported; **unverifiable
from here** = plausible but not provable without running it on hardware.

| Transport → | **WebRTC** (`flutter_webrtc`) | **HLS** (`video_player`) | **HLS** (`media_kit`) | **HLS** (`fvp` + `video_player`) | **MJPEG** (plain HTTP) | **Still image** (`Image.memory`) |
|---|---|---|---|---|---|---|
| **iOS 15+** | **works** — badge + README matrix lists iOS ✔️ for Audio/Video; v1.6.2+hotfix.3 | **works** — pub.dev states iOS 13.0+ | **works** — README matrix iOS 9+ | **works** — pub.dev lists iOS | **works** — no plugin needed, see §2.6 | **works** — Flutter core |
| **macOS 12+** | **works** — badge + matrix lists macOS ✔️ | **works** — pub.dev states macOS 10.15+ | **works** — matrix macOS 10.9+ | **works** — pub.dev lists macOS | **works** | **works** |
| **Windows** | **works** — badge + matrix lists Windows ✔️; libwebrtc 150.7871.01 shipped Sep 2026. Caveats in §2.3 | **does not work** — pub.dev badges are Android, iOS, macOS, Web. **No Windows.** | **works** — matrix "Windows 7+". Caveats in §2.4 | **works** — pub.dev lists "Windows (x64, arm64, including Windows 7)" | **works** | **works** |

**The Windows column is the finding.** `video_player` genuinely has no Windows
implementation — confirmed on [pub.dev/packages/video_player](https://pub.dev/packages/video_player)
(v2.14.0, published ~35 days before 16 Sep 2026), whose platform table lists Android
SDK 24+, iOS 13.0+, macOS 10.15+, Web, and nothing else. This is not a stale rumour;
it is the current published support table. **But Windows is not a blocker**, because
both `flutter_webrtc` and `media_kit` do support it, and `fvp` retrofits a Windows
backend onto `video_player` itself.

### 2.2 Nothing is already in the tree

```
$ grep -nE "video_player|media_kit|webrtc|ffmpeg|vlc|flick|chewie|fvp|libmpv" \
    pubspec.lock pubspec.yaml
NO MATCHES
```

`pubspec.lock` holds 202 packages; none is a video or WebRTC dependency, direct or
transitive. Every candidate is a genuinely new dependency with a native build on three
platforms. One thing *is* already there: `web_socket_channel` (transitive, via
`supabase_flutter`), which is enough to speak the HA WebSocket without a new dependency
for signalling.

### 2.3 `flutter_webrtc` — the recommended package, with its warts shown

- Latest **1.6.2+hotfix.3**, published ~28 hours before this was written. Actively
  maintained: releases in Mar, Jun and Sep 2026; libwebrtc bumped to 150.7871.01 for
  Darwin/Android/Windows/Linux in 1.6.1 (Sep 2026).
- Platform badges: Android, iOS, Linux, macOS, Windows. README matrix marks
  Audio/Video ✔️ on all five.
- **Open Windows issues**, from the tracker — listed because "actively maintained" and
  "bug-free" are different claims:
  - #2146 (13 Aug 2026) — bundled `libwebrtc.dll` (m144.7559.09) crashes with an access
    violation **when audio capture starts**
  - #2141 (9 Aug 2026) — audio device enumeration returns empty until capture starts
  - #2137 (4 Aug 2026) — `getDisplayMedia()` returns a dead track on capturer failure
  - #2176 (11 Sep 2026) — `captureFrame` leaks an RGBA buffer per call and busy-spins
  - #2116 (21 Jul 2026) — **H.264 video permanently stops decoding a few seconds into
    playback**
  - #2097 (18 Jun 2026) — AEC leak when switching audio devices

  **Most of these are in capture paths Hearth never enters.** Hearth is receive-only:
  no microphone, no camera, no screen capture, no `captureFrame`. #2146, #2141, #2137,
  #2176 and #2097 all sit in code Hearth would not call. Note the release-notes line
  that 1.6.2+hotfix.1 "includes a Windows/Linux crash fix", and that the libwebrtc in
  1.6.1+ is 150.x while #2146 is filed against 144.x — the specific crash may already
  be fixed. Not verified.

  **#2116 is the one that matters and is not dismissible.** "H.264 video permanently
  stops decoding a few seconds into playback" is precisely Hearth's use case, and Ring
  streams H.264. Whether it reproduces on the current libwebrtc, on Windows only, and
  against a Ring stream is **unverifiable from here** — it needs a Windows machine and
  a real camera. **This is the single largest technical risk in the recommendation**
  and should be the first thing the Windows spike tries to reproduce.

- **Apple permission trap, and why it is real.** The README instructs adding
  `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` to `Info.plist`, and the
  macOS entitlements `com.apple.security.device.camera`,
  `com.apple.security.device.audio-input` and `com.apple.security.network.client`.
  Spec §4.3 says the opposite: "Camera/microphone capture permissions are not needed for
  viewing; do not request them."

  These are reconcilable in principle — the strings are needed when capture APIs are
  *called*, and a receive-only `RTCPeerConnection` with a `recvonly` transceiver should
  not call them. But `flutter_webrtc` links `AVCaptureDevice` regardless of what Hearth
  calls, and App Store static analysis has historically flagged linked-but-unused
  capture APIs. **Unverifiable from here.** What would settle it: a TestFlight/App Store
  Connect submission of a build with the plugin and no usage-description strings, or a
  local `strings`/`otool` pass over the built framework plus an archive validation.
  Resolve it before promising the milestone, and if strings turn out to be mandatory,
  that is a user-visible deviation from spec §4.3 and Brendan's call, not a quiet fix.

- Alternative if `flutter_webrtc` proves unworkable: **`medea_flutter_webrtc`** 0.19.0
  (published ~5 months ago, verified publisher instrumentisto.com), supporting macOS
  10.15+, Windows 10+ (build 20348) and iOS 15+. Originally a `flutter_webrtc` fork,
  now a complete rewrite. Its floors happen to match Hearth's exactly. Less widely
  deployed; a genuine fallback, not a first choice.

### 2.4 `media_kit` — good coverage, worrying maintenance

- `media_kit` **1.2.6**, `media_kit_video` **2.0.1**, both published **~9 months ago**.
  Platform matrix claims Android 5+, iOS 9+, macOS 10.9+, Windows 7+, Linux, Web.
  HLS is in the supported-formats list. Requires companions `media_kit_video` and
  `media_kit_libs_video` — so it is three new dependencies, not one, plus bundled
  libmpv binaries.
- **[Issue #1337, "Limited Maintenance"](https://github.com/media-kit/media-kit/issues/1337)**,
  pinned by the maintainer on 25 Nov 2025: "We do not have any full-time engineers to
  work on new features, fix bugs, write unit-tests, cross-compile mpv, provide support
  etc." — they "generally fix issues and review pull-requests to critical issues."
  335 open issues.
- One open issue is directly on the path we would use: bundled libmpv (dated 2023-09-24)
  **"locks onto subtitle renditions in HLS masters — black screen"** on Windows. An
  HLS-master parsing bug on the exact platform where `media_kit` is the reason we
  chose it.
- Verdict: **viable, not preferred.** Keep it as the HLS fallback for non-Ring cameras.
  Do not build the Ring milestone on it — and note it could not serve the Ring
  milestone anyway (§1.1).

### 2.5 `fvp` — the quiet alternative worth knowing about

`fvp` 0.38.1 (published ~30 days before writing) registers itself as a `video_player`
platform implementation, covering "Windows (x64, arm64, including Windows 7), Linux,
macOS, iOS, Android". It is FFmpeg/libmdk-based with hardware decoding. **This is the
cheapest way to make `video_player` work on Windows**, and it keeps the familiar
`video_player` API across all three targets with one uniform widget. Costs ~10 MB per
CPU architecture. HLS is not called out by name in its README — **unverified**; a
15-minute spike against any public HLS URL would settle it.

If HLS ever becomes the main path (it will not, for Ring), `video_player` + `fvp` is a
better shape than `media_kit`: one API, three platforms, and the two Apple platforms
stay on AVPlayer rather than libmpv.

### 2.6 MJPEG needs no package at all

`/api/camera_proxy_stream/<entity_id>` is `multipart/x-mixed-replace`. A streaming
`http` response parsed into JPEG frames and pushed through `Image.memory` works on every
Flutter platform with no native code, because there is none. High bandwidth, no audio,
and honestly it is a still-image slideshow — but **it is a genuine all-platform floor**,
and unlike a browser link it is native pixels inside Hearth. If everything else fails on
one platform, this is the answer that is not "open a browser."

For Ring specifically it is likely useless: `RingCam.handle_async_mjpeg_stream` returns
`None` when `self._video_url is None`, and §3.3 explains when that is.

---

## 3. Ring, specifically

The spec asked for this to be re-verified rather than repeated from old advice. It was
verified against `homeassistant/components/ring/camera.py` on `dev`, read 16 Sep 2026,
and the [official Ring integration docs](https://www.home-assistant.io/integrations/ring/).

### 3.1 Ring *does* have live view, and it is WebRTC

The old advice is out of date. `RingCam` overrides
`async_handle_async_webrtc_offer` (line 204), `async_on_webrtc_candidate` (line 230)
and `close_webrtc_session` (line 248), delegating to `ring_doorbell`'s
`generate_async_webrtc_stream`. Two entities are defined (lines 55–72):

| Entity | `live_stream` | Exists when | Stream feature |
|---|---|---|---|
| `live_view` | `True` | always (`exists_fn=lambda _: True`) | `CameraEntityFeature.STREAM` set (line 121) |
| `last_recording` | `False` | **only `if camera.has_subscription`** | not set — no live stream |

`last_recording` is `entity_registry_enabled_default=False`, matching the docs'
"disabled by default".

### 3.2 Ring live view offers no HLS

`RingCam` never implements `stream_source()`. Combined with §1.1, its
`camera/capabilities` returns `{web_rtc}` and nothing else. **A `camera/stream` call
against a Ring `live_view` entity will fail** — `_async_stream_endpoint_url` raises
`"<entity> does not support play stream service"` (`camera/__init__.py` 1148–1151).
go2rtc does not help: line 729 skips provider registration for native-WebRTC cameras,
and go2rtc would need an RTSP source that Ring does not expose.

**This is the load-bearing fact of the whole document.** Any plan built on
"get the HLS URL and hand it to a video widget" does not work for Brendan's cameras.

### 3.3 Ring still images need a subscription — Brendan has one

`RingCam.async_camera_image` (line 155) works off `self._video_url`:

```python
if self._video_url is None:
    if not self._device.has_subscription:
        raise HomeAssistantError(translation_key="no_subscription")
    return None
```

and `_video_url` is only populated from recording history, which is itself gated:
`if history_data and self._device.has_subscription` (line 132). The image is then
produced by running ffmpeg over that recording URL.

So on a **`live_view`** entity with no Ring Protect plan, the snapshot raises
`no_subscription`. Spec §4.3 wants camera cards to "show a labeled placeholder or
snapshot with capture/fetch time" and not autoplay. **Without a subscription there may
be no snapshot to show, on a camera whose live view works fine.** The card design needs
a real, honest placeholder state for "live view available, no still image", not a
spinner that never resolves — and note the snapshot would be a frame from the *last
recording*, which spec §4.3 explicitly forbids presenting as captured now.

**Answered, 16 September 2026.** Brendan is on **Ring Multi**, which lists *180 days
of video event history for all cameras*, *Snapshot Capture*, and *Extended Live View*.
History is what populates `_video_url`, so `has_subscription` should read true and the
snapshot path should return an image rather than raising.

**What that settles, and what it does not.** It settles *availability*: the snapshot half
of §4.3 is not empty here, and the card does not need a "live view works, no still image"
state as its normal case — though it still needs one for the moment history is empty or
the plan lapses, because an entitlement is not a guarantee about any given camera at any
given moment.

It does **not** settle *freshness*, and that is the half that shapes the UI. The image is
produced by running ffmpeg over the **last recording's** URL — it is a frame of whatever
was last recorded, not a capture taken when the card was drawn. §4.3's rule stands
unchanged: show it with the event's own time, never with "now". A camera that has not
recorded since Tuesday shows Tuesday, and says so.

**Still unverified from here:** that Home Assistant's `has_subscription` flag reads true
for this particular plan tier on his instance. Ring's plan naming has changed over time,
and the flag comes from Ring's API rather than from the plan's marketing name. One
snapshot fetch against his own camera settles it; until then this is *expected to work*,
not *verified working*. See §6.

### 3.4 Other Ring facts, confirmed

- **No two-way audio.** The docs state plainly: "Two-way audio in camera live view is
  not currently supported." Matches the spec's deferral. Do not promise talkback.
- **Cloud-only, 60-second polling.** All Ring communication goes through the cloud;
  there is no local path. So Ring live view **fails when the internet is down even if
  the Pi is reachable** — exactly the independent failure mode spec §9's Offline row
  demands a test for.
- **Subscription is needed for `last_recording` video**, per docs and `exists_fn`.
- **Event entities** carry doorbell/motion; binary sensors are being phased out, with
  the docs recommending migration by 2025.4.0. Hearth should read the event entities.

---

## 4. Recommendation

**Transport: WebRTC over the Home Assistant WebSocket.
Package: `flutter_webrtc`.
One adapter, one code path, all three platforms.**

Reasoning, in order of weight:

1. **It is the only transport Ring live view offers** (§3.2). HLS is not a slower
   alternative here; it is absent. Choosing anything else means not shipping the camera
   the spec names.
2. **It is the only transport supported on all three targets by a single package.**
   `flutter_webrtc` covers iOS, macOS and Windows; `video_player` does not cover
   Windows; `media_kit` covers all three but is under declared limited maintenance.
3. **It is the best credential shape.** No token on the media URL, no bearer forwarded
   to a Ring or CDN host, signalling on the already-authenticated socket. §1.3, and
   spec §7's rules are satisfied by construction rather than by care.
4. **Lifecycle falls out for free.** Closing the WebSocket subscription is HA's own
   teardown signal (§1.2), which is what spec §4.3 and §7 require on close, background,
   camera switch, disconnect and account change.
5. **It is the transport HA itself has moved to** since 2024.11.

**Keep as a documented secondary path, not built now:** HLS via `camera/stream` for
non-Ring cameras that expose `stream_source()`, played by `video_player` on
iOS/macOS with **`fvp`** added for Windows. Prefer that over `media_kit` if the
secondary path is ever built (§2.5). Put both behind the single media adapter spec §6
already calls for, branching on `camera/capabilities` per entity.

**Do not build:** MJPEG, unless a platform turns out to be blocked. It is the floor,
not the plan — and it will not serve Ring anyway (§2.6).

### 4.1 What to spike first, in order

Cheapest disproof first. Each step can kill the plan before the next costs anything.

1. **Windows H.264 longevity** — `flutter_webrtc` issue #2116. Receive-only H.264 on
   Windows for ten minutes against any WebRTC source. If it dies after a few seconds,
   the recommendation changes and everything below is wasted. Highest risk, lowest cost.
2. **Apple usage-description strings** — build iOS and macOS with the plugin and *no*
   camera/mic strings, confirm a receive-only peer connection works and an archive
   validates (§2.3).
3. **Signalling against a fake** — implement `camera/capabilities`, `camera/webrtc/*`
   against a scripted fake HA socket. No hardware needed, and spec §8A says fakes must
   not wait on credentials.
4. **Real Ring, locally**, then **remotely** — spec §7 is explicit that working API
   access does not imply media connectivity.

### 4.2 Costs of the recommendation, stated plainly

- Three platforms gain a native dependency with bundled binaries. App size grows
  materially on all three (libwebrtc is not small); measure it rather than guess.
- **CI cannot verify any of it.** `.github/workflows/ci.yml` runs every job on
  `ubuntu-latest` — there is no macOS or Windows runner. A native plugin for three
  platforms Hearth ships and none CI builds is, in ORCHESTRATION.md §6's terms, not a
  gate. Either add build jobs for the targets, or treat "it compiles on iOS/macOS/
  Windows" as **unknown** on every commit.
- Spec §6 requires camera dependencies not become a startup requirement for food or
  thermostat. A plugin with native registration is loaded at app start regardless;
  keeping it out of the *critical path* is a code-structure obligation, and worth an
  architecture test.

---

## 5. Where the doc is honest about its own limits

- HA Core was read on `dev` (`2026.10.0.dev0`), not on Brendan's version. The camera
  WebRTC API has moved before and could move again.
- Package platform badges are **vendor claims**, not test results. Every "works" cell in
  §2.1 means "the vendor currently states this", not "this was run". Nothing in this
  document was executed on Windows; no Windows machine was available.
- Issue-tracker findings are titles and dates, not reproductions. #2116 in particular is
  reported, not confirmed, and not confirmed against the current libwebrtc.
- No version number, package capability or API shape here was written from memory. The
  API shapes in §1.2 are transcribed from source with file and line references; where
  something is inference rather than transcription it says so.

---

## 6. What cannot be settled without Brendan's hardware — **pending, never passed**

Per spec §9: unsupported or unavailable test hardware is *pending*. None of the
following is a pass, and none should be recorded as one.

| # | Unknown | Why it matters | What would settle it |
|---|---|---|---|
| 1 | **HA version installed on the Pi** | go2rtc needs ≥ 2024.11; the `camera/webrtc/*` commands and `camera/capabilities` shape are version-dependent | Settings → About, or `/api/config` on his instance |
| 2 | **Install method** (HA OS / Container / Core) | go2rtc ships automatically with `default_config` on **OS and Container**; Core is not stated to. Only affects non-Ring cameras — Ring skips providers either way (§1.1) | Settings → About |
| 3 | **Whether `stream` is enabled** | Determines whether the HLS secondary path exists for any non-Ring camera | Whether `default_config` is in his `configuration.yaml` |
| 4 | **Ring model(s)** | The docs cover doorbells and stick-up cameras. Battery cameras are not always streaming; other models may differ | Device list in HA |
| 5 | **Ring Protect subscription status** | Decides whether `last_recording` exists at all, and — per §3.3 — whether **`live_view` can produce a still image**. Directly changes the camera card design | Ring account, or whether a `last_recording` entity appears |
| 6 | **Any non-Ring cameras** | Decides whether the HLS secondary path needs building at all in this milestone | Entity list |
| 7 | **Remote path** (HA Cloud vs VPN) | WebRTC needs a working ICE path; `camera/webrtc/get_client_config` supplies ICE servers and HA Cloud provides TURN. A VPN-only setup with no TURN may fail off-LAN where it works on-LAN | His remote-access configuration |
| 8 | **Windows H.264 longevity** (#2116) | **The largest technical risk in this recommendation** (§2.3) | A Windows machine + ten minutes of receive-only H.264 |
| 9 | **Apple capture-API review outcome** | Could force usage-description strings that contradict spec §4.3 | An archive validation / TestFlight submission (§2.3) |

---

## 7. Is any platform blocked?

**No — no platform needs to be dropped, and no browser link is needed.** iOS, macOS and
Windows can all play WebRTC through `flutter_webrtc`, and Ring live view is reachable on
all three.

Three things nonetheless belong in front of Brendan rather than buried, because each is
a decision rather than an implementation detail:

1. **`video_player` is out for Windows.** Not a blocker — `flutter_webrtc` is the plan
   and `media_kit`/`fvp` exist as HLS fallbacks — but it does mean Windows never shares
   an HLS player with the Apple platforms for free.
2. **Ring live view is WebRTC-only.** Any camera plan assuming "fetch an HLS URL, hand
   it to a video widget" is wrong for the hardware in this house (§3.2).
3. **Ring still images may be unavailable without a Ring Protect plan** (§3.3), which
   changes what a camera card can show at rest. That is a product decision — spec §12's
   rule that open decisions are Brendan's applies.

None of these is "silently drop cameras" or "substitute a browser link", which spec §7
forbids. The **Open in Home Assistant** action remains a legitimate *additional*
fallback and must never be reported as native live view.

---

## 8. Sources

Home Assistant:
- [Camera integration](https://www.home-assistant.io/integrations/camera/)
- [Camera entity developer docs](https://developers.home-assistant.io/docs/core/entity/camera/)
- [Stream integration](https://www.home-assistant.io/integrations/stream/)
- [go2rtc integration](https://www.home-assistant.io/integrations/go2rtc/)
- [Ring integration](https://www.home-assistant.io/integrations/ring/)
- [WebSocket API](https://developers.home-assistant.io/docs/api/websocket/) — note: does **not** document the camera commands; source was used instead
- [2024.11 release blog](https://www.home-assistant.io/blog/2024/11/06/release-202411/) — go2rtc built in

HA Core source, `dev` branch, read 16 Sep 2026:
`homeassistant/components/camera/__init__.py`,
`homeassistant/components/camera/webrtc.py`,
`homeassistant/components/stream/__init__.py`,
`homeassistant/components/stream/hls.py`,
`homeassistant/components/ring/camera.py`,
`homeassistant/const.py`

Flutter packages:
- [video_player](https://pub.dev/packages/video_player) 2.14.0
- [media_kit](https://pub.dev/packages/media_kit) 1.2.6 · [media_kit_video](https://pub.dev/packages/media_kit_video) 2.0.1 · [Limited Maintenance #1337](https://github.com/media-kit/media-kit/issues/1337)
- [flutter_webrtc](https://pub.dev/packages/flutter_webrtc) 1.6.2+hotfix.3 · [issues](https://github.com/flutter-webrtc/flutter-webrtc/issues)
- [medea_flutter_webrtc](https://pub.dev/packages/medea_flutter_webrtc) 0.19.0
- [fvp](https://pub.dev/packages/fvp) 0.38.1

Local toolchain: Flutter 3.47.1 / Dart 3.13.1; `pubspec.lock` (202 packages, no video
or WebRTC dependency); iOS 15.0 and macOS 12.0 deployment targets;
`.github/workflows/ci.yml` (all jobs `ubuntu-latest`).
