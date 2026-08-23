# Online connection safety

This project now has a small circuit breaker around the authenticated
Realtime Database adapter. Its purpose is to make Quick Pop and Quick Table
recoverable without changing local board rules or allowing a reconnecting
Firebase socket to freeze a match.

## Safety contract

- Recovery is enabled by default and is limited to paths whose first segment
  is `onlineV2`.
- Queue reads, authenticated REST calls, native reads/writes, and transactions
  have finite budgets. A timeout fails the current operation instead of
  blocking the 15/30-second matchmaking deadline forever.
- Idempotent `set`, `update`, `read`, and queue-query operations may use the
  authenticated REST session as a bounded fallback. REST uses the current
  Firebase ID token and therefore still goes through the deployed rules.
- A REST transaction that times out is not replayed through the native SDK.
  Its result is ambiguous; replaying the updater could create a second room or
  consume a ticket twice. The protocol must retry its next poll instead.
- Paths outside `onlineV2` keep their normal Firebase behavior. Settings,
  local game state, ads, and the board never enter this recovery path.

## Change procedure

Before editing online code, run the focused safety gate from the project root:

The same gate is available as `tool/verify_online_connection_safety.sh` and can
be run from any directory. It never deploys Firebase rules, creates an APK, or
sends a build. Add `RUN_PRODUCTION_SMOKE=1` only when Firebase smoke identities
are intentionally available.

```text
flutter analyze --no-pub
flutter test --no-pub --reporter compact \
  test/online_connection_safety_test.dart \
  test/quick_pop_group_test.dart \
  test/online_transport_test.dart \
  test/quick_pop_online_diagnostics_test.dart
git diff --check
```

Only after that gate passes should a simulator or production smoke test be
started. Do not deploy `database.rules.json` from a dirty worktree. Keep the
diagnostic rollback build explicit with
`--dart-define=PARCHESE_POP_SAFE_ONLINE=false`; it is for comparison only,
not a production setting.

## What to capture when a connection fails

Copy the complete **PARCHIS POP ONLINE DEBUG** panel, including the first
failed step, elapsed time, Firebase path, UID, queue key, ticket ID, room ID,
group ID, and error code. A screenshot without those fields cannot distinguish
an auth failure, a denied rules write, a stale ticket, or a client that merely
missed a bounded poll.
