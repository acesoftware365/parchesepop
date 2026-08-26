import assert from "node:assert/strict";
import test from "node:test";

import { createQuickPopMatch } from "./match_state.js";
import { startTraditionalQuickPop } from "./traditional_quick_pop_engine.js";
import { applyV3TraditionalQuickPopCommand } from "./v3_command_service.js";

function state() {
  return startTraditionalQuickPop(createQuickPopMatch({
    roomId: "qp3_commands",
    queueKey: "traditional",
    mode: "traditional",
    humanUids: ["human-a", "human-b"],
    createdAt: 1_735_000_000_000,
    protocol: "quickPopV3",
  }));
}

function roll(actorUid = "human-a", key = "command_20260824_roll"): Parameters<typeof applyV3TraditionalQuickPopCommand>[1] {
  return { actorUid, idempotencyKey: key, expectedRevision: 0, kind: "roll", submittedAt: 1_735_000_000_000 };
}

test("server accepts one turn command and records its idempotency key", () => {
  const result = applyV3TraditionalQuickPopCommand(state(), roll());

  assert.equal(result.code, "accepted");
  assert.equal(result.state.revision, 1);
  assert.equal(Object.keys(result.state.processedCommands ?? {}).length, 1);
});

test("server returns the prior result for a repeated command", () => {
  const first = applyV3TraditionalQuickPopCommand(state(), roll());
  const second = applyV3TraditionalQuickPopCommand(first.state, roll());

  assert.equal(second.code, "duplicate");
  assert.equal(second.revision, 1);
});

test("server rejects a command from a player whose turn has not started", () => {
  const result = applyV3TraditionalQuickPopCommand(state(), roll("human-b"));

  assert.equal(result.code, "not_your_turn");
});
