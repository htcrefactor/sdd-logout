# LOGOUT Apple Watch app and UI plan

Planning baseline: November 7, 2026, Asia/Seoul.

The [production implementation plan](PRODUCTION-PLAN.md) is the master plan for release scope, architecture, security, payments and acceptance gates. This document specifies the dependent Watch app, its screens and its workout responsibilities. Production readiness requires verified real-device behavior; a successful simulator build is not evidence of reliable outdoor recording.

LOGOUT Watch is an optional workout companion. The runner starts every run on iPhone, then uses the Watch to read measurements and pause, resume or finish the workout. Training plans, workout selection, coach selection, language preferences, account management and detailed history remain on iPhone. This preserves the existing product requirement that coached runs require an iPhone and headphones.

The user selected **start on iPhone only** for the first release. Watch-first starts and independent Watch runs are outside this release. The Watch UI inherits Korean by default and the runner's English selection from iPhone. The release includes real GPS, HealthKit read/write and AI coaching on iPhone. The Watch captures measurements and controls the run; it does not host the AI voice conversation. Live Activities and a Watch Smart Stack card are excluded from v1.

## Product decisions

| Decision | First release |
| --- | --- |
| Start location | iPhone only; Watch has no Start button |
| Watch availability | Optional; choose Watch-assisted or phone-only recording before starting |
| Watch responsibilities | Local workout measurements, workout timing, stage transitions, haptics, pause/resume/finish and a short summary |
| Phone responsibilities | Setup, plans, coach preference, network, AI voice, phone GPS, main history and production account/payment flows |
| Workout controls | Manual pause/resume; finish requires confirmation; no automatic pause in the first release |
| Goal completion | Announce completion visually and with an optional haptic; recording continues until the runner finishes |
| Appearance | Pure-black Watch backgrounds at all times, including daytime |
| Watch navigation | Digital Crown vertical pages and a visible Controls button |
| Ultra support | Larger readable content; core functions also work on smaller compatible Watches |
| Action Button | Later enhancement after a hardware feasibility test; no core flow depends on it |
| Plan and coach management | iPhone only; the Watch receives the selected workout and concise coach identity |
| Summary and history | Last-run summary on Watch; full charts, routes, form analysis and training progress on iPhone |

## Screen and flow specification

### Before a run

The Watch opens to a calm waiting screen with the LOGOUT mark and **iPhone에서 시작하세요 / Start on iPhone**. It shows whether a phone connection is available. There is no workout catalog, coach carousel, account form or separate language menu.

First-time Watch setup explains the purpose of Health access and presents the system authorization flow on the appropriate device. The phone preflight distinguishes Watch not installed, not reachable, preparing, ready and setup needed. The runner can retry or explicitly continue with phone-only recording. A timeout never silently starts two owners. Missing heart-rate readings do not by themselves prove permission denial.

After the runner starts on iPhone:

1. Phone creates a run identifier and sends the workout prescription, including the entire interval sequence, to Watch.
2. Watch displays **달리기 준비 중 / Preparing your run**, prepares its workout and acknowledges the matching prescription revision as Ready. Ready does not mean recording.
3. Phone sends a stable commit ID. Watch persists the run/owner/commit state and acknowledges Running with its authoritative start time before either device claims recording. Duplicate commits do not create another session. A launch callback alone does not count as successful recording.
4. Watch opens Overview for free runs or Workout for structured runs. After an uncertain commit, phone-only fallback remains blocked until reconciliation or an acknowledged abort resolves the pending Watch start.

### During a run

| View | Information hierarchy | Interaction |
| --- | --- | --- |
| Overview | Distance is the largest number. Running time, current pace and heart rate are secondary. Keep a visible state label and measurement units. | Controls button; Crown to other pages |
| Workout | Current phase, remaining time or distance, repetition number when relevant, next phase. For intervals, remaining time is the largest number. | Controls button; Crown to Overview or More |
| More | Average pace, cadence, running power and elevation gain. Unavailable measurements show a dash with a clear state. | Crown scrolling; expand detail only where it remains readable |
| Controls | Large Pause or Resume action, separate Finish run action, return to metrics. | One tap to pause/resume; Finish opens confirmation |
| Paused | Persistent Paused label, frozen running time and prominent Resume. Clearly distinguish running time from total elapsed time. | Resume or Finish |

The workout page adapts to the selected activity without creating another training-plan system:

| Workout | Workout page |
| --- | --- |
| Free run | Overview is the initial view; no fabricated goal or progress ring |
| Easy or recovery | Remaining planned time, prescribed effort description and next phase |
| Distance goal | Remaining distance and progress toward the chosen distance |
| Intervals, fartlek or speed | Current phase, remaining duration, repetition count and next phase |
| Multiweek plan session | The selected day's prescribed stages, using the same workout page |

Once the runner chooses a page, retain it. A phase change updates content and gives a brief haptic or status message without unexpectedly navigating to another page. The Watch executes the downloaded stage sequence locally. A pause freezes stage timing as well as running time. No medical or physiological inference is needed to advance a timed stage.

Keep stride length, ground contact time, vertical oscillation, detailed splits and charts in the iPhone run summary for the first release. They remain part of the full measurement model when supported and available; they do not crowd the default Watch screen.

### Finishing and saving

Finish opens **달리기를 마칠까요? / Finish this run?**, with distance, running time, **종료하고 저장 / Finish & save**, and **돌아가기 / Go back**. Returning leaves the prior running or paused state unchanged. There is no discard action on Watch in this release.

After confirmation, stop collection through the owning session and durably retain the run before attempting final HealthKit and phone synchronization. The summary shows distance, running time, average pace and available average heart rate. Track three independent outcomes:

1. **워치에 저장됨 / Saved on Watch** means the LOGOUT record is durable on Watch. It does not claim a HealthKit save or delivery to iPhone.
2. **건강 앱에 저장됨 / Saved to Health** appears only after successful HealthKit completion. Show **건강 앱 저장 대기 중 / Waiting to save to Health** or an actionable failure state when needed. Route saving has its own pending state because it follows workout saving.
3. **iPhone 동기화 대기 중 / Waiting to sync with iPhone** remains until iPhone acknowledges durable receipt of the same run. Phone receipt does not establish that HealthKit has finished syncing across devices.

A failed Health save or phone sync retains a recoverable local record and offers an appropriate Retry. Reconcile an ambiguous prior save before attempting another write. The runner can dismiss the summary without erasing its pending record. If local persistence itself fails, explicitly show that the run is not yet safely saved and preserve the in-memory record while recovery is attempted.

Full history, feedback, plan adaptation and coach-specific totals are updated on iPhone once the same run is reconciled. Completing a prescribed workout counts once, even if completion is received through multiple delivery paths.

## Visual design and accessibility

Use the existing LOGOUT palette: black `#000000`, near-white primary text, cyan for distance and pace, turquoise for supporting status, lime for progress, orange for principal controls and a restrained warning color. Color always accompanies text or an icon. Finishing is visually distinct from Resume.

Use native SwiftUI typography and monospaced digits. Avoid decorative watch-case artwork, perimeter ticks, tiny complications, large glowing fills and dense dashboards. Keep at most four main measurements on a normal-size page; at larger text sizes reflow into fewer measurements rather than shrink text. An Ultra uses its extra room for larger numbers and controls. These choices follow Apple's guidance to adapt layouts across Watch sizes and prioritize Crown-driven vertical navigation. [Watch layout and navigation](https://developer.apple.com/documentation/watchos-apps/creating-an-intuitive-and-effective-ui-in-watchos-10), [multiple Watch sizes](https://developer.apple.com/documentation/watchos-apps/supporting-multiple-watch-sizes).

Use full-width native controls with generous targets, visible labels and safe-area spacing. Pause must not require a hidden gesture. End must never be adjacent to Resume in a row of tiny buttons. Respect Dynamic Type, VoiceOver, Reduce Motion and increased contrast. VoiceOver announces the measurement name, full unit and availability state; it does not announce every sensor tick. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

Always On preserves the layout while dimming secondary information and replacing bright fills with quieter outlines. Respect system privacy redaction and the user's Always On setting. Never promise per-second wrist-down rendering; the system reduces update frequency. Watches without Always On resume the same view when raised. [Apple Always On behavior](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state/).

Use optional, brief system haptics for acknowledged start/pause/resume/end, important phase transitions and goal completion. Avoid a vibration on every measurement or repeated connection flapping. Every haptic has a visible equivalent. AI audio and microphone capture remain on iPhone and its connected headphones; Watch haptics do not depend on an AI response or network connection. [Apple haptics guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics).

## Bilingual labels and exceptional states

Phone preferences synchronize before each run and remain cached on Watch. Mid-run language changes apply when received without interrupting recording. Native system permission dialogs follow the operating system's language, which the app cannot override. Units follow the phone preference, with kilometers as the initial default.

| State | Korean | English | Behavior |
| --- | --- | --- | --- |
| Waiting | iPhone에서 시작하세요 | Start on iPhone | No Watch Start action |
| Preparing | 달리기 준비 중 | Preparing your run | No running timer before acknowledgement |
| Running | 달리는 중 | Running | Visible recording state |
| Controls | 제어 | Controls | Opens Pause/Resume and Finish |
| Paused | 일시 정지됨 | Paused | Freeze running and stage time |
| Resume | 다시 시작 | Resume | Continue the existing run |
| Sensor waiting | 측정 대기 중 | Waiting for a reading | Dash, never a generated measurement |
| Sensor unavailable | 측정할 수 없음 | Unavailable | Keep the rest of the workout usable |
| Stale value | 마지막 측정 18초 전 | Last reading 18s ago | Current instantaneous value becomes a dash |
| Phone link lost | iPhone 연결 끊김 | iPhone disconnected | Show connection status separately from sensor status |
| Watch still recording | 워치에서 기록 중 | Recording on Watch | Only shown while the local workout is actually active |
| Reconnected | iPhone 다시 연결됨 | iPhone reconnected | Reconcile the existing run |
| Save pending | 기록 저장 중 | Saving run | Do not claim successful save yet |
| Local save complete | 워치에 저장됨 | Saved on Watch | LOGOUT record is durable locally; Health and phone states remain separate |
| Health save pending | 건강 앱 저장 대기 중 | Waiting to save to Health | Retain the record for reconciliation and retry |
| Health save complete | 건강 앱에 저장됨 | Saved to Health | HealthKit completion confirmed; route may still be pending |
| Phone sync pending | iPhone 동기화 대기 중 | Waiting to sync with iPhone | Local save and remote sync are separate |
| Save failure | 저장을 다시 시도해 주세요 | Try saving again | Retain local recovery data |
| Full history | 자세한 기록은 iPhone에서 | See details on iPhone | No full history browser on Watch |

Freshness belongs to each measurement, not just the connection. As an initial engineering policy, instantaneous heart rate and pace older than 15 seconds are stale; tune this using real sample cadence before release. Retain cumulative distance with its last-update state instead of resetting it to zero. The phone never uses stale physiological measurements for timely AI guidance.

## Native architecture

Keep the existing iOS 26 baseline and a dependent SwiftUI watchOS 26 companion. On November 7, 2026, Xcode created the `LOGOUTWatch Watch App` target and its unit-test and UI-test targets inside the existing LOGOUT project. The Watch app and both Watch test targets use watchOS 26.0. The display name is LOGOUT, the bundle ID is `studio-glhf.logout.LOGOUT.watchkitapp`, and the companion is `studio-glhf.logout.LOGOUT`. Independent installation remains disabled. The starter app built successfully for the Apple Watch Series 11 (46mm) simulator destination. This verifies project setup only. Both native apps still have starter content; their production screens, shared run models, workout services, HealthKit/GPS integration and AI connection are not implemented. Check the installed SDK and supported hardware matrix before release, and align the existing iPhone test deployment settings intentionally.

The initiating device and the recording owner are different concepts. Starting on iPhone does not mean the iPhone must own a Watch-assisted HealthKit workout.

| Run type | Recording owner | Other device |
| --- | --- | --- |
| Watch-assisted | Watch primary session and live workout builder; saves the HealthKit workout | iPhone mirrored session, main UI, phone GPS, network and coaching |
| Phone-only | iPhone primary session and builder using available phone measurements | Watch does not start a second session or join automatically mid-run |

Use `HKHealthStore.startWatchApp` for the phone-initiated Watch launch, a versioned prescription transfer, and an application-level ready/start handshake. Prepare the Watch session before requesting mirroring. Register the iPhone mirroring handler at app launch. The Watch owns timing and haptics during an active Watch workout. Apple's mirroring APIs synchronize workout state; the app must explicitly send its metric payloads. [Multidevice workout guidance](https://developer.apple.com/videos/play/wwdc2023/10023/), [Apple's prepare-before-mirroring guidance](https://developer.apple.com/forums/thread/804276).

Use `sendToRemoteWorkoutSession` for workout payloads. Each payload includes schema version, run ID, prescription revision, event or sample ID, sequence number, observation time, source and availability. Process delayed batches in order, preserve history and expose only the newest sufficiently fresh measurement as current. Bound message rate and size; send aggregate updates and phase events rather than every raw sample.

Use WatchConnectivity for preference snapshots, prescription delivery and eventual completion reconciliation. A preference transfer is not evidence that an active workout is recording, and background queued delivery is not a live-data guarantee. Persist critical workout state on each device, not only in view memory. [WatchConnectivity delivery modes](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).

Phone-only sessions and builders are supported on iOS 26. They do not manufacture Watch-only measurements. [iPhone workout support](https://developer.apple.com/videos/play/wwdc2025/322/).

### Background delivery and recovery

Apple documents that a suspended iPhone may receive cached Watch messages with several minutes between deliveries. Mirroring alone therefore cannot guarantee immediate heart-rate-based coaching while locked. Valid phone GPS/audio background execution must be tested separately. Until data is fresh, the phone can use its own available measurements and runner feedback while suppressing stale Watch-based triggers. [Remote workout data delivery](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:didReceiveDataFromRemoteWorkoutSession:)).

| Failure | Required response |
| --- | --- |
| Internet lost | Watch workout, phone GPS and local stage timing continue. AI availability is separate from tracking. |
| Phone and Watch disconnect | Watch continues its local workout and controls. Phone marks Watch values stale/unavailable and keeps its own GPS buffer. No second primary session is created. |
| Reconnection | Replace the invalid mirrored-session object, request a complete snapshot and reconcile by run/event IDs. Do not replay expired controls. |
| Phone control is unacknowledged | Show Pending or Unconfirmed, stop coaching promptly for a pause/end request, and direct the runner to Watch controls. Never claim that Watch stopped without confirmation. |
| Watch finishes while disconnected | Persist the local record, attempt its HealthKit save independently, retain completion for later delivery and show phone-sync pending. |
| Process termination | Recover an active session where supported, reattach data source/delegates and reconstruct stage timing from durable events. A failed recovery is explicitly shown. |
| Watch shuts down | Retain the phone GPS/time buffer under the same LOGOUT run ID. Show Watch recording unavailable. Do not silently migrate the HealthKit owner or create a duplicate workout. |
| Owner cannot finalize HealthKit | Preserve the LOGOUT summary and mark Health save pending or partial. Reconcile recovered owner data before attempting a replacement save. |
| Another workout app starts | Stop claiming LOGOUT is recording, stop local phase haptics, preserve the partial run and synchronize its ended state to iPhone. Never automatically restart or create another owner. |

A disconnected iPhone mirror becomes invalid. If the primary workout remains active, the system attempts to reconnect and supplies a new mirror through the start handler. The application must treat this as the same run. [Apple reconnection behavior](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:didDisconnectFromRemoteDeviceWithError:)).

Apple permits one active workout session on Watch. Starting another workout can end the existing session with `errorAnotherWorkoutSessionStarted`; treat that as a recording interruption, not a network failure. [Apple workout session behavior](https://developer.apple.com/documentation/healthkit/hkworkoutsession).

Control requests carry a unique ID, expected state revision and short expiry. Local Watch controls affect its primary workout immediately. Old resume/end requests must not execute against a different run after reconnection. Durable state records distinguish Running, Paused and Ending. Local persistence, Health workout save, Health route save and phone synchronization each have independent pending, successful and failed states. Timing uses the owner's monotonic duration within a boot and persisted start/pause/resume events; recover through the Health session and journal instead of counting timer callbacks or subtracting wall-clock timestamps. Clock skew or uncertain observation time prevents timely coaching claims.

### Distance and route policy

For a Watch-assisted run, the accepted workout distance comes from the Watch-owned workout stream. The iPhone records GPS for route processing and backup. For phone-only runs, the accepted stream comes from validated phone locations. Attribute the source to the measured stream; do not claim a specific physical GPS receiver when the system has selected it internally.

Never add phone and Watch cumulative distances. During a Watch-link gap, the phone may show clearly labelled provisional phone-derived progress. Reconnection replaces that provisional view with reconciled canonical data; it does not add both increments. Provisional crossings do not trigger duplicate kilometer milestones or plan completion. Keep raw source segments so reconciliation is auditable.

If the Watch owner is permanently unavailable, the retained phone route supports a recoverable LOGOUT run summary. Automatic HealthKit ownership migration remains deferred until an exactly-once recovery path is demonstrated. Routes can finish synchronizing after a workout, so history supports a route-syncing state. [Apple route handling](https://developer.apple.com/documentation/healthkit/reading-route-data).

## Privacy and excluded surfaces

Live Activities and a Watch Smart Stack card are excluded from v1. Do not add an ActivityKit extension, Smart Stack presentation or update pipeline for this release. The active Watch app provides local measurements and controls. Background workout recording and phone location handling must pass their own device tests without either excluded surface.

Keep the Watch free of permanent OpenAI credentials, independent AI requests and voice recordings. Store only the current prescription, necessary preferences, active-run journal and pending synchronization data under system data protection. Keep pending data until the phone acknowledges durable receipt, then remove raw temporary transport data. Keep a compact last-run summary until replaced; full history lives on iPhone. An account or run deletion on phone queues deletion of the corresponding Watch cache for the next connection, with pending status if offline. HealthKit deletion remains a distinct, explicit user choice.

Request only the location and Health data needed for enabled functionality, using localized purpose strings and independent read/write authorization handling. Empty HealthKit reads do not prove denial. Write only LOGOUT-owned workouts, routes and supported measured or system-calculated samples; do not invent missing heart rate, energy, cadence or other HealthKit values, and do not rewrite imported workouts. Use the owning workout builder's collection instead of separately duplicating its samples. A denied Health write leaves the local run usable and clearly marked as not saved to Health. No health values belong in analytics, crash breadcrumbs or public screenshots by default. Audio and transcript consent, retention and deletion follow the production plan's iPhone/backend policy. [Health authorization behavior](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus), [workout and route saving](https://developer.apple.com/documentation/healthkit/creating-a-workout-route).

## Xcode setup and release work

1. Completed: added the watchOS **App** template using **Watch App for Existing iOS App**, bound to LOGOUT, with the same development team and generated companion relationship. Xcode named the target `LOGOUTWatch Watch App`. It remains dependent on the iPhone app. [Apple Watch project setup](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project).
2. Add shared Swift code for run identifiers, measurements, prescription stages, timing, commands and reconciliation. Keep this separate from SwiftUI screen state.
3. Add HealthKit configuration and localized read/write purpose strings to the targets that use it. Add Watch workout-processing background support; Apple's workout guide also requires Audio background mode for workout haptics/audio. Use phone location/audio background capabilities only for implemented, legitimate uses. [Workout setup requirements](https://developer.apple.com/documentation/healthkit/running-workout-sessions).
4. Add Korean and English string catalogs, Watch app assets and UI previews for supported sizes. Keep the Watch screen black; use appropriate app-icon contrast against the system's black launcher background.
5. Verify the final signed archive includes the dependent companion with matching versions, bundle relationships and correct entitlements. No Live Activity or Smart Stack extension is part of v1. Keep permanent OpenAI credentials and production payment secrets out of both app bundles.
6. Use Apple Developer Program distribution signing for TestFlight/App Store release. Prepare Korean and English listing content, Watch screenshots, privacy policy and Health/location disclosures that match actual collection. Validate with the current App Store requirements before submission.

The existing iPhone configuration changes were preserved during Watch target creation. The generated Watch content is still the Xcode starter screen. The separate UI design package contains 30 screen images and five representative flow boards; these are static design artifacts rather than implemented native screens.

## Staged delivery and acceptance

| Stage | Deliverable | Exit criteria |
| --- | --- | --- |
| 1. Shared recording foundation | Typed run/measurement/prescription models, an owner-aware state machine, durable run journal, acknowledged commands and explicit save states. Use deterministic fixtures only in previews and automated tests. | Tests cover owner selection, uncertain startup, repeated commands, delayed samples, pause timing and replay without duplicate completion. Production paths cannot expose simulated measurements. |
| 2. Physical-device reliability gate | Real phone GPS, phone-only HealthKit sessions, phone-initiated Watch sessions, mirroring, local stages/haptics and one workout/route save path. Minimal native screens expose actual state for testing. | Physical iPhone and Watch demonstrate locked-phone recording, sample-age reporting, startup handshake, disconnection/reconnection, crash recovery and Health read/write failure handling. Document measured limits before promising timely AI guidance. |
| 3. Production screens and reconciliation | Implement the specified bilingual Watch UI and matching iPhone flows over real services, source reconciliation, local summaries, independent Health/phone save status and accessible controls. | All applicable functional criteria below pass; completed runs reconcile once into history, plan progress and coach totals. No UI requires a live network for recording. |
| 4. iPhone AI integration | Feed only sufficiently fresh, consented measurements to the secure iPhone/backend coaching path. Watch remains a measurement/control companion. | AirPods, locked-phone delivery, interruptions and network-loss tests pass. Missing/stale readings cannot produce factual coaching claims, and AI failure never stops recording. |
| 5. Release validation | Battery profiling, extended outdoor runs, accessibility, privacy/deletion, signed TestFlight builds, regression testing and store materials. | No unresolved data loss, duplicate workout, false recording/saving state or stale-data coaching issue. The master production plan's security, account and payment gates also pass. |

Functional acceptance:

- Start only on iPhone; Watch persists and acknowledges the matching committed Running state before recording is shown. Readiness alone is insufficient. Phone-only fallback is explicit and cannot race a late Watch startup. Exactly once refers to a deduplicated logical run, not an atomic distributed guarantee.
- The runner can read state, distance and workout phase while moving, and pause with Controls then Pause without taking out the phone. Finish always requires confirmation.
- Running time and stage timing freeze together on pause. Repeated pause/resume from both devices does not produce drift or contradictory states.
- A timed phase changes on Watch while the phone is locked or temporarily disconnected. Goal completion does not silently end recording.
- Missing and stale measurements never become zero or fabricated values. Data age and connection state are independently testable.
- Completing one run yields one LOGOUT history entry, one plan completion and at most one finalized HealthKit workout. Replayed messages and repeated Save do not duplicate them.
- During temporary link loss, Watch controls and local recording continue; reconnect restores one session. Stale commands are ignored and provisional distance is reconciled without double counting.
- Local persistence failure, Health workout/route save failure, phone sync failure, Watch shutdown and process termination have separately testable, truthful states. Recoverable data is retained, and an ambiguous save is reconciled before retrying.
- Starting another workout app ends LOGOUT's recording state and phase haptics, preserves the partial run and reconciles the ending with iPhone without automatic restart.
- Korean and English labels fit the smallest supported Watch and Ultra at supported text sizes. VoiceOver identifies controls, units and state; color is not the sole status indicator.
- Always On and wrist-up transitions retain the correct screen and state. Local workout operation and locked-phone GPS pass without a Live Activity or Smart Stack card.

Hardware matrix: a smaller compatible Watch and an Ultra, the oldest supported OS combination and the current release, a physical iPhone, and AirPods Pro. Include outdoor GPS, wrist down, phone locked, debugger detached, music on/off, calls/audio interruptions, wet-hand interaction, low battery, permission changes, connection loss and network loss. Run a two-hour normal session and a four-hour endurance test; record sample-age distributions, lost/late events, battery drain, thermal state and save/sync outcomes. Set release battery claims only from those measurements.

Immediate next implementation increment: establish the shared recording state, durable journal and permission model, then connect a minimal real GPS/HealthKit flow on the existing native targets. Exercise phone-only and Watch-owned runs on physical devices before expanding the full screens or enabling measurement-triggered AI coaching. The existing web prototype and Watch design boards guide UI implementation; they are not proof of native capability or production reliability.
