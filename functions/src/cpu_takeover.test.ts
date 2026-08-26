import assert from "node:assert/strict";
import test from "node:test";

import { cpuTakeoverTaskId, decideCpuTakeover, type CpuTakeoverRequest } from "./cpu_takeover.js";

const request: CpuTakeoverRequest = {
  roomId: "qp3_room",
  uid: "human-a",
  turnRevision: 12,
  presenceEpoch: 4,
  dueAt: 1_735_000_030_000,
};

test("takes over only for the original disconnected turn", () => {
  assert.equal(
    decideCpuTakeover({
      now: request.dueAt,
      currentTurnUid: "human-a",
      currentRevision: 12,
      presence: { uid: "human-a", connected: false, changedAt: request.dueAt - 2_000, epoch: 4 },
      request,
    }),
    "takeover",
  );
});

test("cancels an old task after reconnection or a new turn", () => {
  assert.equal(
    decideCpuTakeover({
      now: request.dueAt,
      currentTurnUid: "human-a",
      currentRevision: 12,
      presence: { uid: "human-a", connected: true, changedAt: request.dueAt - 1_000, epoch: 5 },
      request,
    }),
    "cancel",
  );
  assert.equal(
    decideCpuTakeover({
      now: request.dueAt,
      currentTurnUid: "human-b",
      currentRevision: 13,
      presence: { uid: "human-a", connected: false, changedAt: request.dueAt - 2_000, epoch: 4 },
      request,
    }),
    "cancel",
  );
});

test("gives each disconnect epoch a unique task id", () => {
  assert.equal(cpuTakeoverTaskId(request), "cpu-qp3_room-human-a-12-4");
  assert.notEqual(cpuTakeoverTaskId({ ...request, presenceEpoch: 5 }), cpuTakeoverTaskId(request));
});
