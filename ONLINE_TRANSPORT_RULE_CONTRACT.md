# Online transport rule contract

The Flutter transport deliberately avoids guest transactions at
`onlineV2/rooms/{roomId}` and avoids transactions over another player's Quick
Pop ticket. Those operations would be rejected by narrow production rules and
would let a modified client assign seats or choose an opponent.

## Room admission

1. A guest writes only
   `onlineV2/joinRequests/{roomId}/{guestUid}`.
2. The host reads pending requests and admits them in one transaction at
   `onlineV2/rooms/{roomId}`. That transaction assigns the first free clockwise
   seat, so two guests cannot claim the same seat.
3. The host removes admitted requests and refreshes the public-room summary.
4. Each participant writes only its own `members/{uid}` ready state and
   `presence/{uid}` state. A non-host leaves by deleting those two owned paths.
5. Once a room reaches `inGame`, the host can publish only the validated match
   document. The host cannot delete the room root, another member, presence,
   command, chat message, lobby snapshot, or match document.

The deployed rules must add `joinRequests` with these constraints:

- authenticated users may create/update/delete only their own request;
- the room host may read and delete requests for its room;
- a request must contain the authenticated UID, referenced room ID and code,
  display name of at most 24 characters, and a numeric request timestamp;
- only the room host may transact the room root or update the public index.

## Durable account cleanup index

Every authenticated installation owns
`onlineV2/accountResources/{uid}`. Room creation, join requests, presence
locators, hosted-room locators, and Quick Pop tickets are written atomically
with their index entry through a multi-location update. Account deletion reads
this index, so it remains complete after an app restart and never depends only
on in-memory subscriptions.

The index is private to its UID, uses an exact schema, and includes a sticky
`requiresBackendCleanup` flag. A legacy identity without a complete index is
not deleted by the client; it must be migrated or removed with verified Admin
SDK tooling. The client preserves resolved tickets, active shared matches, and
immutable chat that contain other players' state.

## Quick Pop claims

1. Each user writes and transacts only
   `onlineV2/quickQueues/{queueKey}/{uid}`.
2. Every client sorts the same queue by server join time and ticket ID. Two
   adjacent compatible tickets derive the same SHA-256 claim and room IDs.
3. The deterministic first ticket is the claim leader. Only that UID may create
   `quickClaims/{queueKey}/{claimId}` or its final `resolution`.
4. Each participant writes only
   `quickClaims/{queueKey}/{claimId}/acceptances/{uid}`. Both acceptances must
   name each other's immutable ticket before the leader publishes a human
   result.
5. Each participant then updates only its own queue ticket. If no compatible
   ticket exists at the server deadline, that ticket changes to CPU fallback at
   exactly `joinedAt + 5000 ms`.

The deployed rules must add `quickClaims` with these constraints:

- reads require authentication;
- only the declared deterministic leader may create immutable claim metadata;
- an acceptance is writable only by its own UID and must reference that UID's
  current queue ticket;
- only the stored leader may create a resolution, and a resolution is
  immutable;
- clients never receive permission to write an opponent's queue ticket.

The claim handshake is matchmaking transport, not game authority. Dice, moves,
captures and final match state currently use the documented `activeHostV1`
authority model. Guests submit only validated command envelopes; the room host
applies them and publishes the durable checkpoint. This is appropriate for the
current casual release, but a ranked or competitive release still requires a
trusted backend with fenced authority.

## Quick Messages

Online rooms store only the 12 reviewed `SafeChatPhraseId` identifiers at
`onlineV2/rooms/{roomId}/chat/{messageId}`. A write is accepted only while the
room is `inGame`, from an authenticated member, and when `senderUid` equals the
authenticated UID. Messages are immutable, use an exact schema and carry a
server-adjacent timestamp. Arbitrary text, spoofed senders, CPU-authored records,
non-members and extra fields are rejected.

## Local verification

`database.rules.json` implements this contract for the current `activeHostV1`
authority model and was deployed to the `parchese-pop` Firebase project on
2026-08-09. Run the complete Realtime Database emulator contract with:

```sh
npm run test:database-rules
```

The test covers private durable account indexes, atomic room/index creation,
guest request ownership, host admission, immutable seats and
commands, Ready updates, presence, opening-roll requests, deterministic Quick
Pop claim acceptances and leader resolution, the five-second CPU boundary,
host-only match publication, profile sync, room-code activation, public-room
indexing, lobby snapshots, participant leave, safe pregame close, protected
in-game shared state, and both standard and Quick Pop room creation. It also
covers Quick Message membership, sender identity, the closed phrase catalog,
timestamp bounds, immutability and exact schema.

Run the multi-client wire smoke test with:

```sh
npm run test:firebase-smoke
```

That test uses separate authenticated clients against the official Realtime
Database Emulator for two-player Quick Pop, the five-second CPU fallback and a
four-player Quick Table opening roll. It clears the emulator after every case
and never writes test data to production.

Realtime Database rules cannot make the room host a trusted competitive
authority while the host must transact the room aggregate. The rules protect
guest-owned writes and immutable envelopes, but production anti-cheat still
requires moving match authority to a trusted backend as stated above.
