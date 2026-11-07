# LOGOUT production implementation plan

Planning baseline: November 7, 2026, Asia/Seoul. Status: production scope and engineering plan; native implementation has not begun beyond project setup.

LOGOUT is a Korean-first iPhone running app with optional Apple Watch measurements and a conversational AI coach. It combines dependable outdoor recording, thoughtful coach personas, structured workouts and adaptive multiweek plans. Tracking must remain useful when the network, AI, a permission or an accessory is unavailable. A successful build is not evidence of reliable outdoor operation.

This is the master release plan. [APPLE-WATCH-PLAN.md](APPLE-WATCH-PLAN.md) specifies the companion's screens and behavior. The current iPhone prototype, `logout-mockup/DESIGN.md`, `RUNNING-METRICS.md` and verified browser flows remain the UI reference. Earlier prototype references to Live Activities and the static Watch-gallery Smart Stack concept are superseded by the exclusions below.

## 1. Confirmed product decisions

| Area | Release decision |
| --- | --- |
| Devices | Native iPhone app and optional dependent Watch companion; no iPad or desktop UI |
| Supported baseline | iOS 26.0 and watchOS 26.0; validate the actual supported device matrix before release |
| Run initiation | Always start on iPhone; choose Watch-assisted or phone-only before recording |
| Coached runs | Require iPhone and headphones; optimize for AirPods Pro while supporting verified alternatives |
| Free tier | Real tracking, local history, run summaries and basic workout controls |
| Paid tier | Digital AI coaching and personalized training plans through a StoreKit subscription |
| Voice proposition | Aim for unlimited voice at a sustainable higher price, with no default monthly allowance or hidden monthly cap |
| Audience | Adults aged 18 and older |
| Availability | Tracking distributed worldwide where permitted; AI only where OpenAI supports service and distribution is permitted |
| Languages | Korean initially; Korean/English choice in onboarding and Settings, synchronized to Watch |
| Appearance | Existing instrument-like LOGOUT design, graphite daytime and true black at night; Watch always black |
| Data location | History, detailed measurements, routes, feedback and plans stay on the user's devices; no cloud history sync |
| Backend scope | Accounts, purchase entitlements, AI connection/control and minimal operational usage records |
| Excluded surfaces | No Live Activity, ActivityKit extension, Watch Smart Stack card or related update pipeline |
| Other exclusions | Independent Watch runs, Watch-first start, automatic pause, medical diagnosis and social feeds |

Free tracking remains available without an account or subscription. AI requires a backend identity and explicit data-sharing consent. Downloaded plans remain readable and an already-started workout remains recordable after entitlement changes; new paid coaching or plan generation requires a valid entitlement. The precise subscription price, provider deployment and legal launch configuration are release decisions, not prerequisites for local recording implementation.

## 2. Current evidence and source of truth

The web prototype has verified onboarding, four-tab navigation, simulated runs, saved local demo history, goal-oriented coaches, Activity filters and a history-aware plan builder. It has no real GPS, microphone, HealthKit, Watch transport, OpenAI or payment processing. Demo data and generated routes must never enter production history or HealthKit.

The native project is `LOGOUT.xcodeproj`, with iPhone bundle `studio-glhf.logout.LOGOUT` and dependent Watch bundle `studio-glhf.logout.LOGOUT.watchkitapp`. Both apps currently display Xcode starter content. The recorded Watch simulator build verifies target setup only. Existing iPhone app settings target 26.0 while project/test settings include 26.5; align these intentionally before claiming 26.0 test coverage. Preserve unrelated project edits and user-specific workspace settings.

The existing Watch design package provides static screen images and flow boards, not implemented SwiftUI or verified Figma behavior. Its excluded Smart Stack image is not a release requirement. Use the updated Watch plan for functional truth when an older image conflicts.

Official Apple and OpenAI documentation was reviewed for this plan. API availability establishes a feasible integration direction, not latency, battery, accuracy or uninterrupted background guarantees. Each physical-device gate below must produce dated evidence, with OS, hardware, configuration and observed failures.

## 3. iPhone journeys and visual continuity

1. Onboarding introduces LOGOUT, confirms adult eligibility, sets Korean/English, running goals and preferred coaching experience. Explain local history and optional AI processing clearly. Request system permissions when the related capability is first used, rather than blocking the entire app behind a permission checklist.
2. Home offers the next useful run, accumulated genuine history, a short coach description and that coach's session count, running minutes, distance and distinct running days. No previously removed promotional footer returns. Coach totals belong to the coach recorded with each run and never change retroactively when the default coach changes.
3. Run selection offers free, easy, distance and interval sessions, plus prescribed plan sessions. Configure duration/distance/stages, inspect the current coach, then complete preflight. The previously removed encouragement banner stays absent.
4. Preflight shows actual permission, GPS, headphone, Watch and AI availability independently. Choose recording owner before start. A headphone or AI problem allows an explicit uncoached run; missing Health access does not fabricate a denial state or prevent local GPS recording.
5. Active run is full screen without the bottom tab bar. Show actual state, distance, running time, current pace and available heart rate first. Further metrics, workout stage, voice controls and connection status are accessible without crowding the main numbers. Pause/resume is prominent; Finish requires confirmation.
6. Summary distinguishes running time from elapsed time, measured totals from estimates, and local save from Health save or Watch synchronization. Record optional perceived effort, pain/discomfort feedback and coach usefulness. Saving cannot depend on AI producing a summary.
7. Activity retains week/month/year filters, period comparison, distance charts, run cards, weighted average pace and detail drill-down into route, splits, heart rate and available form data. Charts expose measurement gaps instead of joining them into invented traces.
8. Plan has two states: without an active plan, a three-step builder uses history, goals and schedule preferences; with a plan, show progress, the next workout and weekly schedule. Home mirrors this state. The timeline fills its padded card width. Replacing a plan requires confirmation and preserves run history.
9. Settings contains default coach selection, language, units, appearance, connected devices, privacy controls, subscription management and account deletion. Coach selection has no bottom tab. The four tabs remain Home, Run, Plan and Activity.

Keep the original LOGOUT palette and iconography: black `#000000`, near-white numerals, cyan/turquoise measurements, lime progress and orange primary actions. Automatic appearance uses the existing 19:00–07:00 device-local schedule, with explicit Light/Dark overrides. This is an app preference, not an undocumented claim that it follows system appearance. Review the chosen mode at run start; do not flash a bright transition during an active night run.

Create original rounded 3D portraits for Mina, Jae, Noa and Sol with the approachable quality requested from Memoji-inspired imagery. They are original LOGOUT characters, not copied Apple Memoji assets, emoji or Apple branding. Keep portraits secondary to readable stats and review both languages at native sizes. Follow native safe areas, Dynamic Type, VoiceOver, Reduce Motion and color-independent state labels. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## 4. Coach personas, bilingual voice and training

| Coach | Runner objective | Guidance style |
| --- | --- | --- |
| Mina | Enjoy comfortable running with less pressure | Calm, brief, body-aware encouragement |
| Jae | Pursue performance within an agreed workout | Direct, demanding, specific targets; seek agreement before increasing intensity |
| Noa | Understand training and measurements | Explain the purpose of a stage and distinguish evidence from interpretation |
| Sol | Build a regular running habit | Celebrate consistency and manageable next steps without shame |

Personality changes phrasing, frequency and emphasis, not measurement truth or safety rules. Every coach respects pain, distress, fatigue and a request to slow down or stop. No diagnosis, invented readiness score, guaranteed performance outcome or instruction to ignore symptoms. Coaching requests outside app control remain conversational suggestions. Snapshot the selected coach into the run at start; changing the default affects subsequent runs and never rewrites coach history.

Use the selected app language as the default spoken language. Handle Korean, English and ordinary code-switching naturally; a spoken language request can apply to the conversation without silently rewriting the saved UI preference. Localize units and pace pronunciation, avoid reading raw identifiers, keep routine prompts short, and disclose that the voice is AI-generated. Evaluate Korean honorifics, numbers, breathy speech and outdoor noise explicitly.

Headphone conversation supports runner-initiated speech, interruption, stats questions, encouragement and requested workout adjustment. Controls include microphone mute, coach quiet mode, stop AI and a foreground talk control. Muting capture and suppressing coach speech are distinct. An explicit pause/end request promptly suppresses coaching even while the Watch acknowledgement is pending.

The local workout engine owns stage timing and completion; the model cannot silently mutate it. A proposed change is validated against current state, shown or read back when material, confirmed where required, and applied as a versioned prescription. Routine stats queries are read-only. Offline planned stages and local cues continue without AI.

The plan builder initially summarizes the last 28 days of genuine eligible runs, recent frequency, duration, distance, consistency, perceived effort and missing-data coverage. Preserve the prototype's insufficient-history explanation and manual experience/comfortable-duration fallback; review its three-runs/seven-days heuristic before production rather than treating it as validated training science. Imported Health workouts count only after provenance and duplicate checks, and never acquire a fictional LOGOUT coach.

Training rules are a reviewed, versioned system: goal, available days, baseline, recovery spacing and completed-workout feedback determine a candidate schedule. Include easy, recovery, distance, speed, fartlek and interval styles where appropriate. A qualified running coach must review load limits, progression, recovery, novice restrictions and discomfort responses before launch. AI may explain or propose within that envelope; it does not invent unrestricted prescriptions. Changes require runner acceptance and retain a reason/revision history locally.

Give each plan and session a stable ID. Store completed, partial, skipped and rescheduled distinctly; an ended run is not automatically a completed prescription. Completing a session and advancing a plan happen once after durable run reconciliation. Existing plans do not regenerate unexpectedly after every run. Deletion and replacement recompute progress without duplicating old completions.

## 5. Native code and persistence architecture

Use the existing Xcode project with two SwiftUI targets. Extract a shared Swift package for run IDs, measurement types, prescriptions, state transitions, timing, commands, validation and serialization. Keep views separate from services and domain rules. Do not share phone-only audio/network implementation with Watch merely to reduce file count.

| Component | Responsibility |
| --- | --- |
| Shared domain | Typed measurements, source/freshness, workout stages, state machine, idempotent events and plan rules |
| iPhone services | GPS/motion, phone-only HealthKit, Watch mirror, local history, audio routing, AI transport and StoreKit |
| Watch services | Primary workout/builder, live sensors, local stage timing, haptics, durable journal and transport |
| SwiftUI presentation | Bilingual screens and accessibility driven by actual service state |
| Local repository | Transactional run journal, route chunks, history, plan revisions, feedback and pending operations |
| Backend | Authentication, verified billing, connection admission, AI tools, abuse protection and operations |

Use a Core Data store backed by local SQLite, accessed through serialized repository services, with explicit schema migrations and a transactional append-only active-run journal. Keep UI state outside persistence transactions and validate crash-safe checkpointing. This is the selected native storage baseline; do not introduce a second SwiftData history store. Persist identifiers, owner, state revision, timing anchors, accepted events, measurement batches and pending save/sync steps before acknowledging them. Large route/sample chunks use bounded storage rather than one growing in-memory array.

Store health/route files under appropriate iOS data protection and exclude app-owned health records from iCloud backup/sync. Select protection classes that permit legitimate locked recording after first unlock, and verify first-unlock/reboot behavior. Keep refresh tokens in Keychain with an intentional accessibility class. Document local data loss on device loss/uninstall; account login does not restore local history. Apple's own Health storage/sync is a separate user-controlled service, not LOGOUT cloud backup.

Timing is owner-authoritative. Use monotonic duration within the current boot for running and paused intervals, with persisted owner start/pause/resume events and checkpoints. Recover through the HealthKit session and journal, rather than subtracting wall-clock timestamps or counting timer callbacks. Account for clock changes, reboot, device skew and future sample timestamps before determining freshness; uncertain timing is displayed as uncertain.

State transitions include Preparing, Running, Paused, Ending, LocallySaved and recovery states. Health workout save, route save and phone/Watch delivery are independent operation records. App relaunch replays durable events and reconciles external outcomes; it never blindly repeats an ambiguous Health write. Exactly-once language means one logical run with deduplicated effects under tested retry/recovery paths, not a distributed atomic guarantee. If a Health save outcome cannot be verified, including because read access is unavailable, preserve the local summary and an unresolved Health state instead of risking a duplicate write. Database migration, low storage and corrupted-record handling are release requirements.

## 6. Workout ownership, GPS and HealthKit

| Mode | Primary recording owner | Supporting behavior |
| --- | --- | --- |
| Phone-only | iPhone workout session and builder | Core Location GPS and available motion data; no invented Watch physiology |
| Watch-assisted | Watch workout session and live builder | iPhone mirrored session, phone GPS buffer, main UI and AI audio/network |

Starting on iPhone does not make it the owner of a Watch-assisted Health workout. Use prepare → ready → commit → owner-running acknowledgement, with one persisted run ID, owner epoch, prescription revision and commit ID. Persist accepted state before acknowledging it. Ready means prepared, not recording. Repeated commits are idempotent. After an uncertain commit, block phone-only fallback until the owner state is reconciled or an abort is acknowledged; a timeout alone cannot authorize a second primary. iPhone-only workout sessions are supported with the selected iOS 26 baseline. [Apple iPhone workout support](https://developer.apple.com/videos/play/wwdc2025/322/), [multidevice workouts](https://developer.apple.com/videos/play/wwdc2023/10023/).

The owning device executes the full downloaded stage sequence, owns run/pause timing and finalizes one HealthKit workout. The other device never saves a second copy simply because synchronization is delayed. Mirror state changes and send explicit metric payloads; use WatchConnectivity for preferences, prescription delivery and eventual completion recovery, not as a guaranteed live stream. [WatchConnectivity transfer modes](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).

Phone GPS runs during an outdoor workout for the main route and recovery buffer. Watch uses workout/location services where appropriate for its own measurement stream and route recovery. Do not claim a particular physical GPS receiver when the system chooses internally. Phone-only distance uses validated phone locations. Watch-assisted distance uses the accepted Watch workout stream; never add the two cumulative totals.

Filter stale/invalid/inaccurate locations, impossible jumps and poor acquisition without inventing replacement coordinates. Compute pace over a bounded quality-aware window; expose acquiring/unreliable states. Compute ascent from filtered elevation changes, not final minus initial altitude. Persist raw accepted-source segments and quality metadata so a reconciliation is explainable.

During a Watch-link gap, phone progress may be explicitly provisional. Reconnection reconciles against canonical owner data without adding the same segment twice or repeating kilometer/goal events. Do not silently migrate Health ownership after a Watch shutdown. Preserve the phone buffer as a recoverable LOGOUT run and resolve the owner's final status before any replacement-save policy.

Route storage follows the same single-writer rule: one canonical LOGOUT route with source-tagged segments. Watch writes the Health route for Watch-owned runs; iPhone writes it for phone-owned runs, after the workout exists. Transfer finalized phone route chunks to Watch with durable checkpoints and acknowledgements. A viable phone-to-Watch transfer and route-finalization path is a release gate. During development or a temporary delivery failure, retain the phone route locally and mark Health route pending rather than writing a second workout. A Watch-collected route can fill a genuine gap only through explicit segment reconciliation, never overlay duplication. [Workout route creation](https://developer.apple.com/documentation/healthkit/creating-a-workout-route), [route synchronization](https://developer.apple.com/documentation/healthkit/reading-route-data).

Request independent Health read/write scopes and localized purpose strings for enabled features. Read workouts/routes and relevant measurements only with permission; import is optional and local. Write only actual LOGOUT-owned workouts, routes and supported collected/system-calculated samples. Let the workout builder collect samples instead of duplicating them separately. Imported workouts are never rewritten.

HealthKit intentionally does not reveal denied read access as a simple permission result; empty results mean unavailable, not proven denial. Denied writes leave local tracking usable with an honest Health-save state. Reconcile Health deletions and imported changes by source/UUID and avoid double-counting a LOGOUT run later observed in Health. [HealthKit privacy and authorization](https://developer.apple.com/documentation/healthkit/protecting-user-privacy).

## 7. Measurement contract and coaching triggers

Every measurement includes value, unit, observed timestamp, receipt timestamp, source/device, run ID, quality and availability. Events have unique IDs, sequence numbers and schema versions. Source identity and sample freshness are distinct from connection status. Never convert missing values to zero, interpolate physiological gaps as fact or backfill older runs with examples.

| Data | During run | History and handling |
| --- | --- | --- |
| Distance, running/elapsed time, pace | Primary | Totals, route and splits; period pace = total running seconds / total distance |
| Heart rate | Primary when sufficiently fresh | Time-aware average/max/chart, coverage and gaps |
| Cadence | Optional detail | Store available live samples; Core Motion cadence is steps/second, convert to steps/minute |
| Running power | Optional detail | Conditional estimated Watch metric; availability/coverage retained |
| Elevation gain | Optional detail | Filtered accumulated ascent and route profile |
| Active energy | Optional detail | System estimate with partial-coverage handling |
| Stride length, ground contact, vertical oscillation | Secondary detail | Form analysis when genuinely available; absent on unsupported conditions/hardware |
| Heart-rate zones | Only with a valid configuration | No guessed thresholds; use explicitly configured app zones; do not assume access to Apple’s configured zones |
| VO2 max or recovery | No live dashboard claim | Optional dated historical samples; not a continuous run sensor |

Availability varies by hardware, permissions and conditions; requesting a type is not a guarantee of samples. Keep sleep, HRV, blood oxygen and wrist temperature outside live-running UI. [Apple running measurements](https://support.apple.com/guide/watch/workout-views-and-running-metrics-apd1f24d4d35/watchos), [cadence units](https://developer.apple.com/documentation/coremotion/cmpedometerdata/currentcadence).

Initial engineering freshness policy: instantaneous heart rate and pace older than 15 seconds become stale for timely coaching; tune against real delivery cadence before release. Keep cumulative distance with its last-update timestamp. Late batches remain historical data and do not trigger old encouragement or safety statements. Summaries use duration/coverage-aware aggregates, not averages of inconsistent partial totals.

Run local deterministic triggers for phase changes, accepted milestones, requested stats and agreed target deviation. Require sufficient duration/quality, cooldowns and hysteresis to avoid noisy prompting. Suppress unnecessary speech during runner speech, calls, mute/quiet mode and recovery from a link gap. Prompts contain an allowlisted fresh snapshot, its age, relevant stage and runner request, not the entire Health database.

## 8. Locked-phone operation and failure recovery

Use legitimate phone location/audio background modes and Watch workout processing. Do not use silent audio or excluded system surfaces as keepalive tricks. Apple documents that a suspended iPhone may receive cached Watch batches several minutes apart; mirroring alone cannot guarantee live heart-rate coaching. Verify actual behavior while locked with GPS/audio active and debugger detached. [Remote workout delivery](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:didReceiveDataFromRemoteWorkoutSession:)), [workout execution](https://developer.apple.com/documentation/healthkit/running-workout-sessions).

| Failure | Required behavior |
| --- | --- |
| Internet loss or unsupported AI region | Tracking, local timing and available measurements continue; show AI unavailable and reconnect deliberately |
| Watch link loss | Watch retains primary recording/controls; phone marks Watch values stale and retains GPS buffer |
| Watch reconnect | Accept new mirrored-session object, request snapshot, deduplicate events and reject expired controls |
| Phone pause/end has no acknowledgement | Show Pending/Unconfirmed and direct to Watch controls; never claim the owner stopped |
| Phone/Watch process termination | Recover supported active session, replay journal and reconcile; expose recovery failure and gaps |
| User force-quits or device reboots | Do not promise automatic uninterrupted recording; preserve completed checkpoints and surface interruption on recovery |
| Other Watch workout starts | Stop claiming LOGOUT is recording, retain partial data and reconcile the ended state |
| Health write or route save fails | Keep local result, separate pending states and retry only after checking ambiguous prior completion |
| Low storage or local save failure | Explicit unsaved warning; preserve in-memory data where possible and offer recoverable retry |
| Headphone disconnect or incoming call | Stop capture/playback as appropriate, keep tracking, restore audio only through a tested route/state transition |
| AI timeout, quota or service outage | Fall back to local stage/status cues; never stop or lose the workout |

Control commands include run ID, command ID, expected revision and expiry. Reject old resume/end commands after reconnect. Watch remains usable locally during phone/network loss. A disconnected mirror is replaced on reconnection, not treated as a second run. [Mirror reconnection](https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:didDisconnectFromRemoteDeviceWithError:)).

## 9. Audio and OpenAI architecture

Use native iPhone audio routing and a maintained, pinned native WebRTC dependency, reviewed for licensing and privacy manifests. The app submits an SDP offer to its authenticated backend; the backend initializes the allowed session with its permanent OpenAI credential and returns the SDP answer. Audio then uses the documented WebRTC connection; the backend joins a sideband channel for context/tools and operational control. No permanent OpenAI key ships in either app. [OpenAI WebRTC setup](https://developers.openai.com/api/docs/guides/voice-webrtc), [server controls](https://developers.openai.com/api/docs/guides/voice-server-controls).

Treat sideband control as useful coordination, not an immutable security boundary. Documented client events allow `session.update`; a hostile client may alter permitted session settings. Model selection is immutable after creation, but client honesty cannot enforce business limits. Backend-issued identity, authorized run/session binding, verified entitlements, tool authorization, one active AI session per account, short-lived admission, event validation and server hangup remain necessary. [Realtime client events](https://developers.openai.com/api/reference/resources/realtime/client-events), [call termination](https://developers.openai.com/api/reference/resources/realtime/subresources/calls/methods/hangup).

All consequential tools execute through trusted app/backend validation. A tool call cannot directly write HealthKit, bill the user, override safety rules or accept arbitrary account/run IDs. Validate schema and ownership, use fresh local state for stats and require confirmation for material prescription changes. Prompt instructions are not access control. Do not expose arbitrary network or database tools to the coach.

Realtime sessions have a documented 60-minute limit. Renew before expiry using a compact consented context snapshot, retaining run ID, persona, language, stage and recent conversational intent. Recording remains independent. Test multiple renewals over four hours, announce a brief reconnect only when it affects the runner, and never promise seamless speech across every rotation. Do not assume a different voice product shares identical limits. [Realtime sessions](https://developers.openai.com/api/docs/guides/realtime-conversations).

Evaluate `gpt-realtime-2.1`, `gpt-realtime-2.1-mini` and `gpt-live-1` on Korean/English intelligibility, interruptions, outdoor false activation, tool accuracy, latency, battery and actual run cost. OpenAI's current audio guide recommends Live for new conversational apps; choosing Realtime here is a product/transport/cost decision to validate, not a claim that it is OpenAI's universal recommendation. Pin a documented model snapshot if one exists at implementation time; otherwise record the evaluated alias, prompt/configuration version and evaluation date, with regression checks and controlled rollback. Never invent a snapshot identifier. [Audio guide](https://developers.openai.com/api/docs/guides/audio), [Realtime 2.1](https://developers.openai.com/api/docs/models/gpt-realtime-2.1), [Realtime 2.1 mini](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini).

Current published audio token prices are $32 input/$64 output per million for the full Realtime option and $10/$20 for mini; text/context charges and caching also matter. `gpt-live-1` lists $0.05 per connected minute, or $3 per connected hour before backend expense. These are planning inputs, not a promised per-run cost or final retail price. Recheck before launch. [API pricing](https://developers.openai.com/api/docs/pricing), [Live model pricing](https://developers.openai.com/api/docs/models/gpt-live-1).

Configure `AVAudioSession` for duplex conversation only while AI listening is enabled. Bluetooth HFP microphone use may change playback quality and routing; AirPods Pro optimization is not a promise of high-fidelity simultaneous microphone/music operation. Test communication mode, mix/duck choices, route changes, calls, Siri, alarms, headphone removal and switching among supported hardware. The app does not control every music app or headphone gesture. Apple’s high-quality Bluetooth recording option can add latency, requires default mode and is not recommended for realtime communication, so it is not the conversation baseline. [High-quality recording limitations](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/bluetoothhighqualityrecording). [Apple audio session](https://developer.apple.com/documentation/avfaudio/avaudiosession), [Bluetooth HFP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp).

Tune VAD and interruption behavior for breathing, wind and footfall, with false-activation monitoring and explicit mute/talk controls. Avoid custom wake-word promises in v1. Do not send hours of empty silence under an untested assumption that VAD guarantees no charge. Locally generated essential stage cues remain available after AI failure, and their interruption/music behavior must be tested too.

## 10. Backend, accounts, privacy and security

Provisional deployment: a small container-based TypeScript service, managed PostgreSQL for account/entitlement/usage state, managed secrets, HTTPS ingress and durable job queue. AWS ECS/Fargate, RDS PostgreSQL, Secrets Manager and a managed queue are a practical reference architecture; selecting an equivalent provider is acceptable. Region, budget, operations ownership and contracts remain launch configuration. Do not buy infrastructure or assume a provisioned account in this planning increment.

Use separate development/staging/production environments and OpenAI projects. Sign in with Apple is the initial cloud identity; verify tokens server-side with nonce/audience/issuer checks, issue short-lived access tokens and rotate/revoke refresh sessions. Free local mode has no compulsory signup. Add app-attestation/device signals as abuse signals, not the only authentication or an untested lockout for legitimate devices.

Check AI availability before a purchase offer and before each session, including when a subscriber travels. Storefront alone is insufficient; use a reviewed coarse availability policy without sending raw GPS, and never route requests to bypass OpenAI country restrictions. Age eligibility is a product gate distinct from the App Store content-rating questionnaire.

Apply account/session authorization to every API, parameterized persistence, request-size limits, bounded tool execution, safe retries, idempotency keys and rate limits for abusive automation. Reject overlapping paid voice sessions and unsupported models. Protect credentials in a secret manager with rotation and least privilege. Do not log authorization headers, audio, prompts, routes, health values or transcript fragments in traces/crash reports.

Local-only history does not mean AI receives no context. With separate informed consent, send minimal fresh metrics and a temporary history aggregate needed for coaching or plan generation. Do not upload raw routes or full Health history by default. Return generated plans/feedback to device storage; the backend is not a second history database. A device reinstall restores account/subscription access, not LOGOUT history or coach/plan progress. Allow a deliberate user-controlled local export of records; warn that a route export reveals location and do not auto-upload it. Imported Health workouts can rebuild only the data actually available there.

Settings must let users independently manage location, Health read/write, AI health-context sharing, microphone, diagnostics, account deletion and local history deletion. Obtain consent for OpenAI audio processing separately from optional measurement/history context. Revoking context consent stops new context transmission immediately; stopping AI stops microphone transmission and closes its session. Free tracking remains independent. Explain OS-level permission changes and avoid misrepresenting unknown Health-read status. AI consent names OpenAI, purpose, data categories and retention limits; declining leaves free tracking available. [Apple data-sharing rules](https://developer.apple.com/app-store/review/guidelines/#privacy), [supported API countries](https://developers.openai.com/api/docs/supported-countries).

Store no app audio or transcripts by default. Keep raw conversation only in memory for the active session and minimal handoff context; disable content tracing and use `store:false` for plan-generation Responses requests; explicit future retention would require a separate product decision and consent. OpenAI API data is not used for model training by default, but default abuse-monitoring logs may retain content for up to 30 days. Do not promise zero retention without approved and compatible controls. Review the chosen API's actual retention eligibility and processor terms before production. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

Proposed backend retention: redacted operational diagnostics 14 days, non-content usage totals 90 days for cost/support, and account/entitlement records while needed for service. Billing records follow documented legal retention obligations. Confirm these durations against actual provider configuration before publishing policy. Account deletion removes active personal records promptly through a retryable job; disclose a measured completion deadline and maximum backup expiry, provisionally 35 days. Never promise instantaneous deletion from immutable backups or vendor abuse logs.

HealthKit data sharing requires express permission and a health/fitness-service purpose; blanket AI consent does not permit unrestricted third-party reuse. No health/location advertising, sale or model-training reuse. Review the processor relationship and sensitive-data obligations for launch regions. Do not store personal health information in CloudKit/iCloud; Apple's Health sync is separate. [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [health-data rules](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).

Account deletion is available in Settings, revokes Sign in with Apple tokens and clears corresponding Watch caches when connected. Explain that Apple subscriptions require separate cancellation and provide management while still allowing immediate account deletion. Local LOGOUT deletion and deletion of LOGOUT-owned Health records are separate explicit choices; never delete other apps' Health data. [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

## 11. Subscriptions, unlimited voice and cost gate

Digital coaching and plans use StoreKit 2 auto-renewable subscriptions. Apple Pay is not the v1 checkout: it serves different eligible purchase types, while regional external digital-payment programs add requirements outside this global default. Revisit only if physical/in-person offerings or a deliberate storefront-specific strategy is introduced. [Apple purchase rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase), [South Korea external purchase program](https://developer.apple.com/support/storekit-external-entitlement-kr/).

Implement verified purchase results, `Transaction.updates` from launch, `currentEntitlements`, account binding with `appAccountToken`, Restore Purchases and subscription management. Provision idempotently before finishing the transaction. Backend verifies signed transaction/renewal information and uses App Store Server Notifications V2 plus API reconciliation after outages. Handle cancellation, pending approval, grace, billing retry, expiry, refunds and revocation distinctly. [StoreKit transactions](https://developer.apple.com/documentation/storekit/transaction), [server-notification recovery](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications).

Enable an explicitly chosen Billing Grace Period and reflect Apple's actual status. Offline cached access is bounded by known verified entitlement and does not prove a fresh renewal; reconnect through the backend before admitting paid cloud service. Preserve recording/history and an active workout through billing problems. Never open a paywall over running controls. [Billing grace configuration](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions).

Unlimited means no routine monthly minute allowance. A 60-minute technical reconnection is not a usage cap. Anti-abuse controls prevent automated farming, credential sharing and concurrent sessions; describe material restrictions transparently. Do not market unlimited and then silently stop heavy legitimate runners at a hidden threshold. If economics fail, revisit model, price or the published offer before launch instead of inventing a secret cap.

Measure connected minutes, billable input/output usage, latency, context growth, session rotations and backend cost without retaining speech/health content. Profile quiet runs, conversational runs, frequent encouragement and long-run outliers. Model subscription economics after store fees, taxes, payment failures, refunds, vendor cost and support, including the 95th/99th-percentile legitimate runner. Exact price is chosen from these measurements. Vendor/global emergency spend protection may temporarily disable AI with clear status and support, but must never stop recording or masquerade as normal unlimited service.

## 12. Staged production implementation

| Stage | Working increment | Evidence required before expansion |
| --- | --- | --- |
| 0. Project alignment | Preserve existing targets; align baselines/tests, shared package, configuration, CI and source control | Both targets build; unit tests execute on intended minimums; no production credentials in source |
| 1. Recording core | Typed owner-aware state machine, durable journal, permissions, real phone GPS and Health save | Deterministic recovery/idempotency tests; real phone locked run; truthful local/Health save states |
| 2. Watch reliability | Phone launch handshake, Watch-owned workout, mirroring, local stages, controls, route/data reconciliation | Real phone/Watch disconnect/reconnect, owner failure, duplicate-save prevention and sample-age evidence |
| 3. Production UI | Implement current iPhone flows and specified Watch screens over real services | Korean/English, dark mode, accessibility, missing-data and no-network journeys pass; no demo data in release |
| 4. Secure voice | Account/consent service, headphone routing, WebRTC, sideband tools, interruption and renewal | Locked AirPods tests, Korean/English evaluations, 60-minute rotation and failure isolation pass |
| 5. Plans and billing | Reviewed training engine, contextual generation, StoreKit/server reconciliation and subscription UI | Plan safety/revision tests; sandbox purchase/refund/grace/recovery; unlimited cost model approved |
| 6. TestFlight | Signed builds, migrations, operational monitoring, privacy controls and release materials | Extended hardware matrix, recovery/deletion drills, support readiness and no critical open defects |
| 7. App Store | Final policy/price/configuration review, phased release and monitored rollout | Release checklist complete; rollback/AI kill switch rehearsed; evidence supports every marketed capability |

Each increment is working production code, with fixtures only in tests/previews and a change log of verified behavior versus assumptions. Do not implement the entire UI first and postpone workout reliability. Do not label an increment production-ready merely because the simulator launches. Maintain version control in `htcrefactor/sdd-logout`; resolve existing GitHub authentication/write access before remote publication without discarding local commits or unrelated changes.

## 13. Test matrix and acceptance gates

Use physical iPhone, a smaller supported Watch, an Ultra and AirPods Pro on minimum/current OS combinations. Add supported non-AirPods headphones and phone-only runs. Test outdoors with debugger detached, screen locked, wrist down and normal network transitions. Run 30-, 60- and 120-minute sessions plus a four-hour endurance session with multiple voice renewals. Record battery, thermal state, GPS quality, sample ages, audio interruptions, lost/late events and save outcomes; set marketed battery/latency claims only after measurement.

Inject airplane-mode/network loss, Bluetooth loss, Watch shutdown, calls/Siri, headphone removal, low battery, low storage, permission changes, process termination, force-quit, server outage, token expiry and duplicate/out-of-order messages. Distinguish system limitations from recoverable app failures. Exercise rain/wet-hand controls and VoiceOver/larger text on both devices.

- The selected owner persists and acknowledges its committed Running state before either device claims recording. Readiness alone does not satisfy this gate. A timed-out Watch start cannot later create a parallel phone workout.
- Pause freezes running and stage time; elapsed time remains truthful. Repeated controls and reconnects cannot replay expired commands or change a different run.
- Network/AI failure never interrupts accepted tracking or erases a recoverable journal. Forced termination gaps are visible, with no invented route or measurements.
- One finished run yields one local history record, one plan outcome, correctly attributed coach totals and at most one finalized Health workout; route saving has its own state.
- GPS source reconciliation does not double distance or milestones. Missing/stale readings remain unavailable, and measured coverage appears in summaries/charts.
- The phone visibly distinguishes lost internet, lost Watch, unavailable sensor and stale sample. No timely physiological claim uses data older than the approved freshness policy.
- Voice can be interrupted and muted reliably on validated hardware; no unintended speaker playback/capture follows headphone loss. Calls recover without stopping tracking.
- Four-hour sessions survive planned transport renewals with documented conversation gaps and bounded memory; no session limit silently ends the workout.
- Korean/English flows, numbers, units, persona behavior and safety cases pass evaluations. Jae never pressures a runner through pain or contradicts an explicit stop request.
- Plan proposals remain within reviewed rules, explain their basis, handle insufficient history and apply only accepted revisions; shortened sessions stay partial.
- StoreKit purchase, restore, pending approval, renewal, cancellation, grace, refund, revocation and backend outage resolve correctly without duplicate grants or hidden usage caps.
- Permission refusal, account deletion, local deletion, Health-delete choice and offline Watch deletion queue work without accidental deletion of unrelated data.
- Release build contains no simulated production data, API secrets, audio/transcript logging, health-content analytics or excluded Live Activity/Smart Stack functionality.

Automate state-machine, journal replay, deduplication, clock/pause, GPS acceptance, metric coverage, plan-rule and purchase-reconciliation tests. Use service contract tests for backend authorization and malicious tool arguments. Add UI tests for core journeys and accessibility, plus migration/restore fixtures. Manual hardware tests remain mandatory for background execution, audio routes, sensors and battery.

## 14. Operations and App Store readiness

CI builds both targets, runs meaningful tests, validates localization/resources/privacy manifests and scans secrets/dependencies. Use stable toolchain versions and separate test credentials. A release candidate requires reviewed schema migrations, a signed archive including the dependent Watch app, correct entitlements/purpose strings and version alignment. Remote configuration can select an already-tested model or disable AI admission; it cannot disable recording or inject arbitrary executable logic.

Monitor crash-free sessions, recording/save failures, duplicate reconciliation, Watch lag, AI connection/renewal failures, authentication abuse, purchase-webhook backlog and cost anomalies using content-free diagnostics. Establish alerts and a named incident owner before TestFlight. Feature rollout is staged; rehearse backend rollback, credential rotation, queued-job recovery and purchase reconciliation. Mobile rollback uses a corrective release, so persisted schemas require compatibility planning.

Back up only necessary backend account/billing/operational records with encryption, tested restore and documented expiry; there is no server backup of route/history data. Test restoration into an isolated environment and replay notifications safely. Keep deleted-user tombstones/retention exceptions narrowly scoped and documented. Publish support contact, service status and a clear AI-unavailable explanation.

Release prerequisites: Apple Developer Program enrollment and signing, seller identity review, App Store Connect agreements/tax/banking, subscription products/prices/localizations, privacy policy and terms, adult age/audience configuration, Korean/English screenshots and Watch screenshots, permission/AI disclosures, account deletion, export/compliance answers and privacy labels matching actual vendors. Review current submission requirements at release, including any minimum SDK change. [Developer program](https://developer.apple.com/help/account/basics/about-your-developer-account), [privacy details](https://developer.apple.com/app-store/app-privacy-details/), [privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

Provide App Review a working account/demo route through paid features, reachable backend and clear instructions for phone-only and Watch-assisted testing. Explain background location/audio, Health writes, headphone requirements and the absence of independent Watch starts. Use original visuals and claims supported by device evidence. No submission while unresolved issues can lose workouts, duplicate Health records, misstate recording/saving, expose private data or generate unsafe coaching.

The next implementation increment is Stage 0 followed by the durable phone recording core. Provider deployment, final unlimited subscription pricing, processor/legal configuration and final hardware acceptance remain explicit launch gates, not assumptions disguised as completed work.
