# LOGOUT

The `htcrefactor/sdd-logout` project.

Korean-first running app for iPhone with an optional Apple Watch companion. Native SwiftUI, Core Location, HealthKit and a shared recording core.

This repository is under active implementation. The current increment records phone-only runs, supplies Watch-owned workout services and controls, and stores history locally. AI coaching, backend accounts, StoreKit subscriptions and adaptive training plans are not enabled yet. See [implementation evidence and remaining work](Docs/IMPLEMENTATION-STATUS.md) before testing or releasing.

## Open and build

Open `LOGOUT.xcodeproj` in Xcode. Select the `LOGOUT` scheme for iPhone, or `LOGOUTWatch Watch App` for its dependent companion. The project targets iOS 26.0 and watchOS 26.0 and was built with Xcode 26.6. It uses the local `Packages/LOGOUTCore` package; there are no external package dependencies.

Simulator compilation does not need a development signing identity:

```sh
xcodebuild -project LOGOUT.xcodeproj -scheme LOGOUT \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/logout-build CODE_SIGNING_ALLOWED=NO build
```

Use a real signing team with the necessary HealthKit capabilities for physical devices. Start all runs on iPhone. Watch mode requires the companion app and its permissions. Phone-only GPS recording works without Health write permission. Do not describe simulator measurements as real sensor validation.

## Checks

```sh
swift test --package-path Packages/LOGOUTCore
```

The Xcode project also contains native formatter tests and a UI flow test. Run simulator UI tests serially (`-parallel-testing-enabled NO`) to keep Xcode from substituting extra cloned devices during visual checks. Debug-only UI-test arguments use a separate preferences suite and an in-memory recording store.

## Plans and secrets

- [Production plan](Docs/PRODUCTION-PLAN.md)
- [Apple Watch plan](Docs/APPLE-WATCH-PLAN.md)
- [Verified implementation status](Docs/IMPLEMENTATION-STATUS.md)

Permanent OpenAI credentials belong only on the backend. `Backend/.env.local` is ignored and must never be copied into either app, source control, test attachments or logs. The local development credential is not a deployed backend. No microphone, AI, purchasing, Live Activity or Smart Stack integration is active in this increment.
