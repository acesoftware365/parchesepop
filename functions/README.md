# Online V3 Cloud Functions

This folder is intentionally independent from `onlineV2`. It contains the
server-authoritative Quick Pop foundation and does not change the active
Flutter transport, Firebase Rules, or production Firebase project.

The first implementation unit is the deterministic Quick Pop resolver. It
gives every eligible 2-4 player cohort exactly one derived room ID, so retries
cannot create duplicate rooms. The next unit is the Admin SDK transaction
adapter, followed by the canonical match command processor.

Use Node.js 20. The runtime choice follows Firebase's currently supported
Node.js 20 and 22 environments.
