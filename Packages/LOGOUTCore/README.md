# LOGOUTCore

Shared value models, recording state, clock, GPS filtering and durable local storage for the iPhone and Watch targets. Swift 6, iOS 26, watchOS 26 and macOS 14 for package tests. No network calls, API credentials, artificial workout measurements or third-party dependencies.

## Integration contract

- Select one immutable `RecordingOwner` before starting. Build a `RunRecord`, persist preparation, and call `begin(at:)` only after the owner has actually started recording. Persist the resulting state before reporting a committed start.
- Apply pause/resume/finish through `RunRecord.apply`. The caller passes the current expected revision, command identifier and deadline. Duplicate applied identifiers acknowledge without reapplying. Persist before an acknowledgement; keep any hardware operation coordinated with this journal in the application service.
- `DeviceMessage.validate` rejects schema, run, owner, expiry and revision mismatches. Do not interpret transport delivery as durable acknowledgement. To acknowledge a previously applied command, check its persisted identifier before strict revision validation.
- `RunClock` measures active time from injected monotonic uptime. Call checkpoint on the application service's cadence and at transitions. UI refreshes do not count elapsed seconds. The clock is deliberately not Codable: after process restart, rebuild from the persisted duration and reconcile with the owning HealthKit session. Never replay a persisted uptime against a new boot or silently fill the missing time with wall-clock elapsed time.
- `TimedMetric.isFresh` checks observation time, arrival time and future timestamps. Missing or stale data stays absent/stale in the interface. Application services choose a freshness budget appropriate to each metric and preserve source provenance.

## Persistence

`RunRepository` is an actor backed by Core Data SQLite. Every `save` atomically commits a lightweight snapshot, an append-only journal entry and newly supplied route chunks. Reusing an event identifier for the same run returns `false`; it does not append another event. Lower revisions, decreasing elapsed/distance values, same-revision phase changes, reopening ended runs and erasing a successful Health save are rejected. A failed write rolls back; the caller must expose failure and must not acknowledge success.

`records()` and `unfinished()` return lightweight records without route points. `load(id:)` hydrates one route. `save` accepts a cumulative route, while `appendRoute` accepts an ordered batch with an idempotency identifier. Batched appends decode at most the last existing chunk to verify continuity. Prefer bounded batches during an active run and load full routes only for detail/export. Save route points from one owner; never add Watch and phone distance together.

For an atomic bounded checkpoint, call `save(record, routeBatch: points, eventID: batchID, eventKind: "checkpoint")` with `record.route` empty. It commits the snapshot and incremental batch together. Keep the batch until success and retry with the same event identifier; `false` means that event is already committed. Preserve new arrivals separately while a write is in flight. Do not mix an incremental batch and a cumulative route in the same write.

`replay(id:)` reconstructs the last journaled state plus committed route chunks. Deletion removes the record, detailed journal and route, retaining only a run-ID tombstone to reject delayed companion replay. Application deletion must still coordinate the other device and any separately requested HealthKit deletion.

The recording directory is excluded from backup. iOS/watchOS use `completeUntilFirstUserAuthentication` protection so a run can checkpoint after the screen locks. Access before the first unlock after reboot is not promised. Device-level file protection behavior still requires hardware testing.

The programmatic model has explicit version `LOGOUTCore.v1`. Tests verify reopening this initial SQLite schema. Before changing its structure, retain the prior model and ship a tested migration; enabling automatic lightweight migration alone does not prove a future migration works.

## GPS and recovery boundaries

`GPSAccumulator` rejects stale/future fixes, invalid coordinates, poor accuracy, duplicate/out-of-order timestamps and implausible speed. Pauses and long observation gaps break continuity, with no invented straight-line distance. It derives rolling pace only after a minimum observation interval. It does not replace device accuracy and battery testing: stationary drift, urban canyons, tunnels and distance error must be measured outdoors before release. Persisted routes do not yet encode explicit segment boundaries; route renderers must also break on time gaps and known pause events rather than draw invented connections.

Core Data commit is the local durability boundary, not proof that HealthKit saved, that a Watch received the state or that a remote service completed an operation. Health write uncertainty and workout identifiers remain explicit fields; application recovery must reconcile these before retrying a potentially completed save.

## Verification

Run `swift test --scratch-path .build` from this directory. Tests exercise idempotent commands, stale messages, monotonic timing, reboot protection, interval stages, metric freshness, GPS rejection, SQLite reopen, atomic rollback, route batches, journal replay, immutable terminal state and deletion tombstones. Hardware background execution, HealthKit permissions, workout ownership, Watch transport and power consumption are outside package-test coverage.
