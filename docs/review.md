# Flutter SDK review

**Reviewed:** 17 November 2026. **Verdict: changes required before production release.** (F01–F05 since fixed: see Resolution.)
The Android example builds successfully against the native SDK, and the wrapper largely
keeps delivery, sessions and push in native code as intended. Five findings remain:
a tracking withdrawal can disappear on client replacement, consent-blocked events reach
the Dart hook, old engines can clear newer engines' callbacks, the iOS token bridge has
a retain cycle, and late routing requests can still invoke application navigation.

## Resolution (17 November 2026)

All five findings are fixed in the working tree; `flutter test` (33 tests) and `flutter analyze`
pass, the Android example builds, and the iOS plugin typechecks against the native Kirora module.

| Finding | Fix | Covered by |
| --- | --- | --- |
| F01 | A tracking choice still waiting for setup is sent to the native SDK at once when the instance is replaced or destroyed, ahead of the next setup or the destroy, so native consent storage records it (per workspace, as before). No Dart-side storage. | `a tracking choice still waiting reaches the native SDK before a replacement or destroy` |
| F02 | Native `configure` answers whether tracking is allowed. Dart gates `track`/`trackScreenView` on the app's latest choice, else that answer, before copying or calling `beforeSend`; until setup answers, the copy is taken at the call and the hook waits (calls stay in order). Unavailable platforms return before capture. Production and `KiroraMock` now agree. | `beforeSend never sees an event tracking does not allow` group |
| F03 | Each plugin records the engine that configured Kirora last (`owner`). Only it clears the process-wide callbacks (`wrapperDetached`, nil handlers) or, on iOS, holds the tap listener; an older engine ends only its own client. | Source; two-engine device run still to do |
| F04 | `TokenRequestsBox.requests` is weak, breaking `requests → closure → box → requests`. The native client's `fetchUserToken` closure keeps the active requests alive while that client lives. | Typecheck; heap check on device still to do |
| F05 | Native sends `{url, deadline}` (now + 1.5 s); Dart answers `false` without calling `handleDeepLink` once the deadline has passed. | `a tapped link is offered to handleDeepLink over the channel` |

The Android SDK saved a tracking choice off the main thread, so a client created straight after
could read the earlier value. kirora-android now hands a choice still being written to the next
client of the same workspace (`ConsentStorageTest.aReplacementClientTakesAChoiceStillBeingWritten`),
and the example builds against it. The package is now MIT licensed, like the native SDKs.
Publication and device verification remain as listed below.

## Scope and verification approach

Reviewed `kirora/kirora-flutter`: public Dart API, capture/redaction, method-channel
backend, both native plugins, manifests, native dependency declarations, example,
package metadata, mock and existing test sources. The authority is the shared
[SDK interface](../../../omnichannel/docs/sdk-interface.md), including its wrapper
exceptions, consent rules, engine teardown and current mobile context contract.

The checkout has no commits and consists of untracked files. A SHA-256 file snapshot
was captured before verification. Commands ran in an isolated copy at
`/private/tmp/kirora-flutter-review-20261117`, excluding Firebase configuration, local
settings and generated build caches. Only this report and the root README are changed
by this review. **The existing test suite was neither run nor modified.**

Runtime probes were separate temporary programs: the actual Dart SDK code ran in a
headless Flutter engine with a recording binary messenger; a Swift lifetime probe used
the actual native `KiroraWrapper.TokenRequests` class and the plugin's ownership pattern.
They do not establish physical-device push behavior. Findings distinguish those results
from source analysis. P1 blocks release; P2 is a material contract or lifecycle defect.
Recommendations below are proposed follow-up work, not implementation changes delivered
with this documentation review.

## Findings

### F01 — P1: a tracking withdrawal can disappear when the client is replaced

**Reproduced with the production Dart API and a recording platform messenger.**
[NativeBackend._send](../lib/src/native_backend.dart), lines 166–172, waits for
`_configured`, then suppresses the call if `_stopped` became true.
`setTrackingConsent` goes through that asynchronous path despite returning `void`.
[Kirora's constructor](../lib/src/kirora.dart) synchronously stops the previous backend.

With the first client already configured:

```dart
first.setTrackingConsent(false);
final second = Kirora(KiroraOptions(clientKey: sameClientKey));
```

The withdrawal waits at the asynchronous boundary. Replacement marks the old backend
stopped before it resumes, so the native setter never runs. The headless probe observed
**zero forwarded `setTrackingConsent` calls**. A previously granted native choice can
therefore survive and allow collection by the replacement. No network disclosure was
observed in this probe; the demonstrated failure is that the refusal never reaches
native consent storage.

The existing test named “a call queued on an instance replaced before its setup answered
is never sent” even expects a queued withdrawal to vanish. That expectation verifies the
current behavior, not the spec's requirement that a fresh consent choice applies
immediately and a remembered refusal survives client changes.

**Required change:** preserve pending same-namespace consent choices across replacement,
or convey the choice before disposing of the old client. Do not apply one workspace's
choice to a different workspace/API configuration. Verify both completed and pending
configuration, explicit destroy/recreation, and refusal followed by replacement. Avoid
adding a second persistent consent implementation in Dart.

### F02 — P2: beforeSend sees events that consent should block

**Reproduced; the mock behaves differently from production.**
[NativeBackend.track/trackScreenView](../lib/src/native_backend.dart) checks `_stopped`
but otherwise calls `EventCapture` before native consent is consulted. With
`requireTrackingConsent: true`, no grant, and an explicit refusal, an app's `beforeSend`
still receives the event's properties. Native code can subsequently reject forwarding
for storage/delivery, but the callback has already run.

The actual Dart probe observed one hook invocation for a refused event; the same scenario
through [KiroraMock](../lib/testing.dart) observed zero. The mock gates capture on
`trackingConsent`, whereas production does not. The shared redaction contract explicitly
states that the hook is never called for activity blocked by consent. The wrapper
exception for native automatic events does not remove that consent requirement.

There is no claim that Kirora itself transmitted the refused event. The concern is
unconsented capture/hook invocation and misleading host-test behavior: applications can
observe, count or otherwise act on hook data even though tests suggest it never reaches
the callback. An unavailable backend also lacks an early capture guard, so a host hook
can run on a platform where the SDK otherwise advertises no-ops.

**Required change:** make the capture gate consistent with the current native consent
answer, explicit fresh choices and unsupported availability before copying or invoking
the hook. Preserve the synchronous hook API and native ownership of persisted consent.
Align the mock's documented behavior with production. Verify fresh opt-in mode, stored
refusal, withdrawal, regrant, unsupported platforms and screen views.

### F03 — P2: an older engine can clear a newer engine's process-wide callbacks

**Source analysis on Android and iOS; not a two-engine device reproduction.**
The [Android plugin](../android/src/main/kotlin/io/kirora/flutter/KiroraFlutterPlugin.kt),
lines 65–76, calls `Kirora.wrapperDetached()` whenever its own `configured` flag is true.
The [iOS plugin](../ios/Classes/KiroraFlutterPlugin.swift), around lines 31–39, makes
the same decision before calling `KiroraWrapper.wrapperDetached()`.

That flag means “this engine configured a client at some point,” not “this engine still
owns the current process-wide hooks.” Sequence: engine A configures; engine B configures
and installs its callbacks; A detaches. A still has `configured = true`, so it clears B's
routing/foreground callbacks and, on iOS, the global tap listener. B's Dart client remains
alive but its push integration has been disrupted. A stale explicit destroy can similarly
clear process-wide handlers.

Flutter supports engines with independent lifetimes in add-to-app hosts; this is not
merely a hypothetical impossible process state. See
[Flutter's multiple-engine guidance](https://docs.flutter.dev/add-to-app/multiple-flutters).
A background engine that never configured Kirora is correctly excluded already.

**Required change:** associate process-wide callback ownership with the currently
configured engine/generation and let only that owner clear global hooks. Still dispose
of an old engine's own client and subscriptions. If only one configuring engine is
supported, enforce and document that boundary rather than silently disrupting the newer
one. Verify A configure → B configure → A detach/destroy, plus normal single-engine reload.

### F04 — P2: the iOS token-request bridge creates a permanent retain cycle

**ARC ownership established by source and reproduced with the native request class.**
[iOS configure](../ios/Classes/KiroraFlutterPlugin.swift), around lines 152–164, creates
`TokenRequestsBox`, creates `KiroraWrapper.TokenRequests` with a closure that captures that
box, then assigns `box.requests = requests`. Both references are strong:

```text
requests → onRequest closure → box → requests
```

The closure also retains its channel. Replacing the plugin's `tokens` property or setting
it to nil does not break the cycle. Native `TokenRequests` intentionally retains its
`onRequest` closure, so its own timeout/cancellation handling does not release this
ownership graph once pending requests finish.

A standalone Swift program linked the existing native Kirora module, constructed the
same box/callback graph, released external owners, and observed a weak request reference
remain non-nil. This demonstrates the cycle; it is not an iOS heap profile or proof of
an exact retained engine size. Repeated configuration with a token provider can retain
one such graph per configuration.

**Required change:** break one edge, for example by making the box's request reference
weak while the plugin/native provider owns active requests, or capturing an appropriate
weak owner. Preserve request IDs and late-answer rejection. Verify deallocation after
reconfigure, explicit destroy and engine detachment, including a pending token request.
Do not weaken all callbacks indiscriminately and lose active token replies.

### F05 — P2: expired link requests can still execute the Dart router

**Native timeout path checked by source; late Dart dispatch simulated in the headless
probe.** The Dart method handler in
[NativeBackend](../lib/src/native_backend.dart), around lines 55–66, invokes
`handleDeepLink` whenever a URL is delivered. Requests carry no deadline or configuration
generation. Native SDKs wait 1.5 seconds and then use their fallback; Android's
`askDart` and the iOS `ask` helper do not prevent later invocation of application code.
The iOS helper's three-second continuation cleanup is separate from the native
1.5-second routing decision.

If Dart is busy and processes the request after native fallback already opened the URL,
its callback can also navigate inside the app. Ignoring the callback's eventual answer
does not undo the side effect. The headless probe confirmed that dispatching a request
identified by the harness as expired still invoked the router once. It did not stall a
real device or observe duplicate OS/app navigation.

**Required change:** carry and check request expiry/lifetime before calling the host
router; preserve the native fallback deadline. Keep routing callbacks fast and avoid
indefinite waits for navigation readiness. Verify delayed delivery, engine replacement,
normal handled/unhandled routes and cold start. Already executed app side effects cannot
be canceled retrospectively.

## Contract and release assessment

| Area | Assessment |
| --- | --- |
| Native delegation | Correct overall architecture: no independent Dart HTTP queue, authentication engine or retry scheduler. Native SDKs own delivery, identity, sessions and push. |
| State | Both native plugins call native `getState`; Android does not reconstruct its count from a Room-only flow. Native channel errors get a quiet Dart fallback. Do not import the earlier React Native state-count finding into this SDK. |
| Redaction | Copying, hook failure handling and re-entry protection exist. Hook runs before native storage on explicit app events; native automatic events are deliberately exempt in the wrapper spec. Context is empty and returned context is not forwarded. F02 remains a consent defect. |
| Errors | Identify and marketing consent surface typed native failures. Logout/flush/device toggles use quiet handling; completion is not proof of remote delivery. Missing native code has documented safe no-op behavior. |
| Launch and teardown | Android provider and iOS plugin registration install early push hooks. Both distinguish intentional destroy from engine detachment. Current-owner enforcement still needs F03. |
| Push | Appearance, channels, permission/device preference APIs and tap streams exist. Android-only receive stream and iOS service-extension delivery requirements need explicit documentation. |
| Dependencies | Android always includes core and FCM artifacts, even without Dart push options. iOS uses CocoaPods `Kirora ~> 0.1`; no plugin SwiftPM manifest is included. Optional dependency separation/SPM support are product choices, not this spec's release blockers. |
| Compatibility | Pubspec requires Dart `^3.13.1` and Flutter `>=3.22.0`; the Dart constraint is an additional effective minimum. Android plugin uses compileSdk 36/minSdk 24, AGP 9.1.1 and Java 17. Do not claim compatibility with every Flutter 3.22-era toolchain. |
| Distribution | `publish_to: none` intentionally prevents pub.dev publication. `LICENSE` is still a TODO placeholder. Record a deliberate license and tested native versions before publication; do not invent a grant in documentation. |
| Example/CI | Android host exists and builds. There is no checked-in iOS example host or CI workflow, so the previous README's direct iOS example-build instruction was incomplete. |

The old README also promised that identity always carries across replacement and that
A's pending events are sent before B's. Those are not portable wrapper guarantees.
Native ownership rules require A's records to remain A's; they do not promise an outgoing
flush on every direct switch. The rewritten guide asks apps to identify after native
startup/reconfiguration and separates logout completion from remote cleanup.

A malformed state-map probe also produced a Dart type error because field casts occur
after the quiet channel read. Current native bridges emit the declared types, so this
is a lower-confidence protocol robustness observation, not an additional demonstrated
normal-integration failure or justification for a new validation framework.

## Comparison with Customer.io and Iterable

**Support status matters.** Customer.io has an official Flutter SDK. The official
Iterable material inspected documents native and React Native SDKs; I could not verify
an equivalent official Flutter SDK. The `iterable_flutter` pub.dev package is marked
**discontinued** with an unverified uploader. The current `iterable_sdk` page is an
**unlisted empty release**, despite older cached documentation describing a wrapper.
These publisher pages are primary evidence about those packages, not proof of Iterable
vendor support. See [iterable_flutter](https://pub.dev/packages/iterable_flutter) and
[iterable_sdk](https://pub.dev/packages/iterable_sdk). Do not use their old feature lists
as the current official Iterable Flutter baseline.

| Area | Customer.io Flutter | Iterable benchmark | Kirora recommendation |
| --- | --- | --- | --- |
| Installation | Separates initialization, identify/track, push and in-app setup. [Quick start](https://docs.customer.io/integrations/sdk/flutter/quick-start-guide/) | Official native guides cover app/push setup and dependency installation. [Android](https://support.iterable.com/hc/en-us/articles/360035019712-Iterable-s-Android-SDK), [iOS](https://support.iterable.com/hc/en-us/articles/360035018152-Iterable-s-iOS-SDK) | Use a short Dart start plus explicit native steps; add a real iOS consuming host before release. |
| Version evidence | Upgrade guidance ties Flutter/Dart requirements to native SDK versions; release notes identify native updates. [Upgrade guide](https://docs.customer.io/integrations/sdk/flutter/whats-new/5.0.0-upgrade/), [changelog](https://docs.customer.io/integrations/sdk/flutter/whats-new/changelog/) | Vendor native SDKs have their own version/dependency requirements. [Android guide](https://support.iterable.com/hc/en-us/articles/360035019712-Iterable-s-Android-SDK) | Publish tested wrapper/native/toolchain combinations, rather than relying on a loose `0.1.0` label. |
| Authentication | Uses its own platform credentials and identify API. [Quick start](https://docs.customer.io/integrations/sdk/flutter/quick-start-guide/) | Official JWT guidance keeps secrets server-side and supports async auth callbacks in its React Native wrapper. [JWT guide](https://support.iterable.com/hc/en-us/articles/43901001355412-JWT-Authentication-with-Iterable-s-React-Native-SDK) | Retain Kirora's public key plus server-signed per-user JWT; fix callback ownership/lifetime rather than copying another vendor's claims. |
| Push lifecycle | Documents platform push setup and FCM integration. [Quick start](https://docs.customer.io/integrations/sdk/flutter/quick-start-guide/) | Vendor native SDKs document notification integration and link handling. [iOS guide](https://support.iterable.com/hc/en-us/articles/360035018152-Iterable-s-iOS-SDK) | Validate engine teardown, late links, permissions and cold starts with actual native hosts. |
| Product breadth | Provides push and in-app messaging, with native release maintenance. [Quick start](https://docs.customer.io/integrations/sdk/flutter/quick-start-guide/), [changelog](https://docs.customer.io/integrations/sdk/flutter/whats-new/changelog/) | Official native product includes in-app/inbox/embedded features. [Android guide](https://support.iterable.com/hc/en-us/articles/360035019712-Iterable-s-Android-SDK) | These additional surfaces are outside Kirora's current spec; do not add them to make a comparison table look complete. |

The useful blueprint is clear installation, maintained native dependencies, explicit
platform support and repeatable lifecycle verification. A discontinued community bridge
is not a suitable reliability target.

## Verification performed

| Check | Result and limits |
| --- | --- |
| Toolchain | Flutter 3.50.0 stable, Dart 3.14.0. Tool cache access required sandbox escalation. |
| Dependency resolution | `flutter pub get --offline` passed in the isolated copy, including example dependencies. |
| Static analysis | Default `flutter analyze --no-pub` reported one informational deprecated `flutter/material.dart` import in `example/lib/main.dart`; exit 1. No Dart error/warning diagnostics were reported. Native code is excluded by analyzer configuration. |
| SDK-only analysis | `flutter analyze --no-pub lib` passed with no issues. |
| README examples | Analyzed against the actual package using typed host authentication/router/widget placeholders. |
| Android host build | `flutter build apk --debug --no-pub` passed: `example/build/app/outputs/flutter-apk/app-debug.apk`. Used the installed Android SDK, Java 17 and local Maven Kirora artifacts. Toolchain future-support warnings remain; no test tasks or live FCM verification. |
| Dart runtime probes | Actual package code ran in the headless Flutter engine with a recording `BinaryMessenger`; refusal loss, hook/mock difference and simulated late routing were observed. Direct runtime execution exited 0. No `flutter_test` suite was executed. |
| Swift lifetime probe | Linked the native Kirora module and reproduced the plugin's request/box strong-reference graph. Weak request reference remained non-nil after external owners were released. No live Flutter iOS engine or heap profiler. |
| iOS syntax | Swift frontend parsing and podspec Ruby syntax passed. No complete iOS plugin semantic build, pod resolution, signing or simulator/device run; full Xcode is unavailable. |
| Existing tests | Relevant sources inspected, left unchanged and not run. Mock-channel tests do not validate engine/native integration. |

The initial Flutter launcher waited for debugger discovery after the short probe exited;
it was stopped, and the compiled probe was run directly in the headless engine to obtain
an unambiguous exit status. The first Android attempt lacked SDK environment discovery;
retrying with the installed SDK path produced the successful APK. These were environment
issues, not SDK findings. Generated changes stayed in the isolated copy.

No production API calls, private signing credentials or Firebase configuration were
used. Local build success does not verify pub.dev/Maven/CocoaPods publication, deployed
backend compatibility, APNs/FCM delivery, OS notification settings or OEM behavior.

## Recommended sequence

1. Preserve consent changes across client replacement and gate Dart capture/hooks (F01–F02).
2. Enforce native callback ownership across engines and break the iOS retain cycle (F03–F04).
3. Reject expired routing requests before calling application navigation (F05).
4. In a subsequent implementation task, add focused regressions and run the existing
   suite. Validate both real native hosts, two-engine teardown, background/terminated
   push delivery and the exact released native dependencies.
5. Resolve licensing/publication intent and record a supported toolchain/native version
   matrix before changing `publish_to` or announcing a public release.

This review delivers documentation only. The five findings remain open.
