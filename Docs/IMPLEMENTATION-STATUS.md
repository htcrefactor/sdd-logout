# Native implementation status

Updated November 7, 2026, Asia/Seoul.

LOGOUT now has a first native production implementation increment for iPhone and its dependent Apple Watch companion. It replaces the Xcode starter screens with real recording services, durable local storage and bilingual SwiftUI flows. This is an engineering foundation for the [production plan](PRODUCTION-PLAN.md), not a finished product or an App Store release candidate. A successful build and simulator interaction do not establish reliable outdoor operation.

The web prototype and Watch design boards remain visual and journey references. Features described in the master plan are release requirements unless this document explicitly records them as implemented and verified. This increment contains no simulated production measurements, active AI coaching, purchasable subscription or generated training plan.

## Implemented in this increment

### iPhone

- Korean-first onboarding with English selection, adult eligibility, runner goal and coach preference. Settings contains default coach selection, language and appearance preferences. Original coach portraits are included as app resources.
- Home, Run, Plan and Activity navigation. Home derives totals and coach-specific sessions, time, distance and running days from genuine local history. The Plan screen explains that personalized plans are not yet available.
- Free runs, configurable easy runs and distance goals, plus a structured interval prescription. Preflight distinguishes phone-only and Watch-assisted recording and exposes location and Health access.
- A full-screen active run with measured distance, running time, pace, available heart rate, cadence and power, stage progress, pause/resume and confirmed finish. Missing or stale readings remain unavailable. Watch-assisted phone displays use the last received owner totals and identify delayed updates.
- Native Core Location recording with accuracy and timestamp filtering, pause/gap handling and background location configuration. Phone-only distance has one GPS-derived source. HealthKit workout and route writing are separate from local saving; local tracking can proceed without Health workout write access.
- Local history with week/month/year selection, distance charts, weighted average pace, distinct running days and per-run details. Routes load on demand. Detail screens label retained heart-rate, cadence and power values as the last received samples, not whole-run averages. Local record deletion uses a durable tombstone to reject a delayed replay of that run.
- True-black active-run presentation and the existing LOGOUT instrument palette. Appearance preferences are part of the native UI; full visual and accessibility parity with the reference remains subject to review.

### Apple Watch

- A dependent app with no independent Start action. Waiting, permission setup, preparing, Overview, Workout, More, Controls, paused, saving, interrupted and last-run summary states are implemented. The Watch is always dark with a black background.
- The iPhone supplies the prescription and language. Preparation and an explicit committed start are separate operations. The Watch persists its accepted state before acknowledging recording; a launch callback or reachable connection is insufficient to claim that a run started.
- A Watch-owned HealthKit workout, live builder and mirrored session. Real available measurements feed the UI. The Watch records its actual GPS route in this increment and does not add phone distance to its cumulative total.
- Local monotonic running time, downloaded workout stages and stage/goal haptics. Pause freezes running and stage time. Reaching a goal does not automatically end recording. Pages retain the runner's selection during a stage change.
- Pause/resume and a finish confirmation work through the recording owner. Controls, journal revisions, stable command identifiers and expiry validation prevent an accepted retry from applying the same transition twice.
- Local save, Health workout save, Health route save and acknowledged iPhone delivery have separate statuses. Completed records are retained in a protected outbox until the phone acknowledges durable receipt. Missing connectivity does not turn a queued run into a claimed successful sync.
- Recovery adopts a matching active HealthKit session or retains an interrupted record. It does not estimate a lost duration from wall-clock subtraction or blindly repeat an uncertain Health save. A recovered live session keeps its in-memory clock and GPS active while persistence errors are reported and retried.

### Shared foundation

- The `LOGOUTCore` Swift package supplies run ownership, state transitions, prescriptions, fresh/stale metric handling, wire validation, GPS filtering and monotonic clocks.
- A Core Data SQLite repository serializes writes. Snapshots, journal events and new route batches can commit atomically. Route chunks remain separate from lightweight history rows. Duplicate events, stale snapshots, terminal-state reopening and delayed replay after local deletion are rejected.
- App-owned health and route storage is excluded from backup and uses protection that permits legitimate recording after the device's first unlock. This configuration still needs locked-device and reboot testing.
- HealthKit mirroring carries live snapshots, with immediate WatchConnectivity messaging for control and status exchange. Application context stages a preparation and synchronizes language; it cannot independently authorize a start. Completed-file transfer provides a separate eventual-delivery path.
- Both native targets include relevant capability configuration, localized permission-purpose strings and initial privacy manifests. These are implementation inputs to release review, not completed privacy or App Review certification.

## Verification evidence

| Check | Status | What it establishes |
| --- | --- | --- |
| Shared core automated tests | Passed: 22 tests | Command retry/expiry behavior, state transitions, monotonic timing, stage boundaries, metric freshness, GPS filtering, durable journal/route transactions, reopening storage and deletion tombstones |
| iPhone shared-service SDK type-check | Passed against the installed iPhone Simulator 26.5 SDK | The adapter code uses available SDK APIs and passes compilation checks |
| Watch shared-service and app SDK type-check | Passed against the installed Watch Simulator 26.5 SDK, deployment target 26.0 | The Watch UI, coordinator, transport and services type-check together |
| Full Xcode app build including Watch companion | Passed | Native app targets and resources integrate in the Xcode build; this is not a distribution archive |
| Native iPhone unit tests on iPhone 16e, iOS 26.2 simulator | Passed: 7 tests | Duration/pace formatting, missing values, rounding and distance precision; `/tmp/logout-unit-formatter-tests.xcresult` |
| Native UI test suite | Passed: 1 end-to-end test | Korean default, adult-choice gating, English selection, onboarding persistence, four tabs, empty Activity, settings and location-gated preflight; `/tmp/logout-ui-serial.xcresult` |
| Computer-driven UI inspection on paired iPhone 17 Pro and Apple Watch Ultra 3, 26.5 simulators | Passed for the inspected flows below | Native phone recording flow and both initial layouts inspected; Watch-owned workout/control/sync behavior remains unverified |
| Physical iPhone, Watch and AirPods validation | Not yet verified | Simulator success cannot establish sensors, background reliability, audio behavior, radio delivery, thermal state or battery use |

The source deployment baseline is iOS 26.0 and watchOS 26.0. SDK compilation against 26.5 and simulator tests on 26.2 or 26.5 must not be described as verified runtime coverage on 26.0. Keep dated test results with exact devices, OS versions, build identifiers and observed failures when replacing the pending entries above.

### November 7 simulator inspection

Used the existing `iPhone 17 Pro w/ Ultra 3` paired with `Apple Watch Ultra 3 (49mm)`, both running 26.5. The first parallel UI-test attempt stalled in Xcode's simulator/debugger setup and was stopped. A serial rerun completed successfully in 63 seconds with zero test failures. Final app builds completed successfully; the only remaining build notices concerned unused App Intents metadata extraction.

Computer inspection verified Korean onboarding, original coach portraits, the Home and workout-selection screens, location and motion permission flows, and a phone-only uncoached run. Pause froze the running time at 00:10; resume continued it; confirmed finish saved a 00:20 local record. The summary correctly showed missing physiology as unavailable and Health workout/route as not saved. The local record remained after app termination, replacement with the updated build and relaunch. The simulator supplied a stationary location, so 0.00 km is not evidence of outdoor GPS accuracy. No run was written to Health during this check.

Two visible issues were fixed and inspected again: the nighttime preflight sheet now uses a black background, and the Watch waiting header is more compact so Health setup is visible without scrolling. The Watch waiting screen showed the connected iPhone status. Full Watch setup, Watch-owned start, controls, save and synchronization have not been exercised end to end. Watch content did not expose usable accessibility elements through Computer in this environment; coordinate interaction was inconclusive. Those flows remain explicit test gates.

Both final app bundles contain their privacy manifests. The backend key exists only in the ignored local backend configuration with owner-only file permissions. No OpenAI request was made by this increment and no permanent credential is included in either app bundle.

## Required recording and recovery gates

Before treating recording as production-ready, exercise phone-only and Watch-owned runs on physical hardware with the debugger detached. The minimum gate covers:

1. Locked phone, backgrounded app and wrist-down Watch during a complete outdoor run. Measure actual sample age and delivery gaps; do not promise timely heart-rate-driven coaching from mirroring alone.
2. Watch unavailable at preflight, permission denial, expired preparations, uncertain commit, duplicate commands, simultaneous controls, disconnection and reconnection. Confirm one logical run and one Health workout writer without silent ownership fallback.
3. Process termination, system workout interruption, battery exhaustion and device reboot. Confirm truthful recovery, paused-time handling and retained local data. Test first-unlock restrictions and device-clock changes explicitly.
4. Low storage, failed local commits, corrupted storage and interrupted route writes. Confirm that the live workout is retained where possible, save failures remain visible and retries cannot manufacture a successful save or lose an accepted route batch.
5. Health read/write permission changes, workout save failure, ambiguous save outcomes, route finalization, duplicate delivery and delayed phone receipts. Verify actual Health workout identifiers and that no second save occurs merely because an acknowledgement was lost.
6. GPS quality and gaps, reduced accuracy, sensor availability and stale samples. Compare recorded distance and timing with a controlled reference; inspect routes for false connecting segments and duplicated source distance.
7. A smaller supported Watch as well as Ultra, Korean and English, larger text, VoiceOver, scrolling, one-handed controls and finish confirmation. Review the actual native layouts, not only static design boards.
8. Two-hour normal and four-hour endurance runs, recording battery drain, thermal state, GPS continuity, sample-age distribution and save/sync outcomes. Audio and AI add another performance gate when implemented.

## Remaining production work

| Area | Work still required |
| --- | --- |
| Accounts and backend | Deploy authenticated services, account lifecycle and deletion, server-side secrets, entitlement verification, operational controls and privacy-preserving observability. Provisioning a developer OpenAI key does not implement these services or activate in-app AI. |
| AI coaching | Implement secure session admission and the verified voice transport; bilingual personas; microphone and headphone controls; interruptions and barge-in; safe measurement tools; consent; supported-market restrictions; loss-of-network behavior; outdoor and breathing-noise evaluation; responsible coaching evaluations. Permanent API credentials must remain outside app bundles. |
| Audio and AirPods | Validate actual AirPods microphone routing, recording while locked, music coexistence, calls, route changes, interruption recovery and battery use. No headphone or microphone reliability claim has been verified by this increment. |
| Subscription | Implement StoreKit products, purchase/restore/manage flows, server verification and notifications, entitlement reconciliation and regional availability. Decide sustainable pricing only after real voice-cost testing. Unlimited voice remains a product goal under evaluation. |
| Training plans | Implement the history-aware builder, insufficient-history fallback, reviewed training rules, multiweek schedule, workout feedback and accepted adaptation. Preserve completed/partial/skipped/rescheduled distinctions and deduplicate plan progress. The native Plan tab currently has no operational builder or active-plan engine. |
| Measurements and analysis | Persist appropriately bounded measurement series and coverage; compute valid whole-run averages, splits, heart-rate zones, elevation and supported running-form metrics; add gap-aware charts and provenance-aware Health import. A last sample must never be relabeled as an average. |
| Phone/Watch route selection | Finish the production canonical-route policy, source-segment provenance, provisional phone backup behavior, source handoff and reconciliation. Current Watch-owned runs use Watch GPS routes. A phone location manager being available is not proof that canonical phone-route transfer/fallback has been implemented. |
| Privacy and deletion | Finish granular consent, export, retention choices, cross-device deletion acknowledgement and pending-outbox cleanup. Local deletion currently protects the local repository from replay; it does not establish deletion from the Watch, Apple Health, a future backend or OpenAI. Health deletion and account deletion need explicit, separately tested behavior. |
| Persistence operations | Add reviewed schema migration fixtures, corruption handling, storage-pressure policy, retention/compaction for journals and transfer files, and verified recovery after upgrades. An initial SQLite reopen test does not validate future schema migration. |
| Product parity | Complete the remaining plan, feedback, account, subscription and privacy journeys; finish appearance/accessibility review and relevant units preferences; validate goal-oriented coach presentation without implying unavailable AI behavior. |
| Release operations | Establish CI, regression and security checks, model/configuration controls, signed device builds, TestFlight distribution, support and incident procedures, privacy/legal documentation, App Store privacy declarations, age/market settings, review instructions and original store assets. Validate the supported hardware/OS matrix and resolve all workout-loss, duplicate-write, false-state and privacy defects before submission. |

Live Activities, Watch Smart Stack, Watch-first starts, independent Watch runs and automatic pause remain excluded from the agreed release scope. Their absence is intentional and does not block the recording reliability work above.

The next engineering milestone is to complete the pending simulator evidence and the physical recording/recovery gate, fix any failures, and then connect the secure backend and paid AI experience in independently validated increments. The full product vision remains the master plan's release scope.
