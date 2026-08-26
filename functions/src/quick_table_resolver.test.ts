import assert from "node:assert/strict";
import test from "node:test";

import { createQuickTableRoom, joinQuickTableRoom } from "./quick_table_resolver.js";

test("Quick Table creation records an organizer but no host authority", () => {
  const room = createQuickTableRoom({
    uid: "player-a",
    visibility: "code",
    mode: "traditional",
    now: 100,
    roomNonce: "fixed",
    code: "ABC234",
  });

  assert.equal(room.accessCode, "ABC234");
  assert.equal(room.members["player-a"].color, "red");
  assert.equal("hostUid" in room, false);
  assert.equal(room.createdByUid, "player-a");
});

test("Quick Table assigns unique seats, is idempotent, and cannot exceed four", () => {
  let room = createQuickTableRoom({ uid: "a", visibility: "public", mode: "traditional", now: 1, roomNonce: "one" });
  for (const uid of ["b", "c", "d"]) room = joinQuickTableRoom(room, uid, 2)!;

  assert.equal(joinQuickTableRoom(room, "b", 3), room);
  assert.equal(joinQuickTableRoom(room, "e", 3), null);
  assert.deepEqual(Object.values(room.members).map((member) => member.color).sort(), ["blue", "green", "red", "yellow"]);
});
