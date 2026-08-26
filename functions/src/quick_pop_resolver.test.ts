import assert from "node:assert/strict";
import test from "node:test";

import { deterministicRoomId, resolveQuickPop, type QuickPopTicket } from "./quick_pop_resolver.js";

const now = 1_735_000_000_000;

function ticket(uid: string, ticketId: string, joinedAt: number): QuickPopTicket {
  return {
    uid,
    attemptId: `attempt-${ticketId}`,
    displayName: `Player ${uid}`,
    ticketId,
    queueKey: "traditional",
    mode: "traditional",
    minPlayers: 2,
    maxPlayers: 4,
    joinedAt,
    launchAt: now + 30_000,
    expiresAt: now + 30_000,
    state: "waiting",
  };
}

test("resolves two players to one deterministic V3 room", () => {
  const result = resolveQuickPop([ticket("b", "ticket-b", now + 1), ticket("a", "ticket-a", now)], now);

  if (result === null) throw new Error("Expected a two-player resolution.");
  assert.deepEqual(result.room.humanUids, ["a", "b"]);
  assert.equal(result.room.roomId, deterministicRoomId("traditional", ["ticket-a", "ticket-b"]));
});

test("takes at most four compatible players in a stable order", () => {
  const result = resolveQuickPop(
    ["a", "b", "c", "d", "e"].map((uid, index) => ticket(uid, `ticket-${uid}`, now + index)),
    now,
  );

  if (result === null) throw new Error("Expected a four-player resolution.");
  assert.deepEqual(result.room.humanUids, ["a", "b", "c", "d"]);
  assert.equal(result.assignedTicketIds.length, 4);
});

test("allows one human at the deadline so CPU can fill the room", () => {
  const result = resolveQuickPop([ticket("a", "ticket-a", now)], now, {
    minHumanPlayers: 1,
  });

  if (result === null) throw new Error("Expected a solo CPU-fill resolution.");
  assert.deepEqual(result.room.humanUids, ["a"]);
  assert.equal(result.assignedTicketIds.length, 1);
});

test("does not match expired or incompatible tickets", () => {
  const expired = { ...ticket("a", "expired", now), expiresAt: now };
  const chaos = { ...ticket("b", "chaos", now + 1), mode: "chaos" as const };

  assert.equal(resolveQuickPop([expired, chaos], now), null);
});
