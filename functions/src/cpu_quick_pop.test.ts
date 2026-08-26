import assert from "node:assert/strict";
import test from "node:test";

import { playCpuTurn } from "./cpu_quick_pop.js";
import { createQuickPopMatch } from "./match_state.js";
import { startTraditionalQuickPop } from "./traditional_quick_pop_engine.js";

test("temporary CPU advances only the disconnected player's turn", () => {
  const state = startTraditionalQuickPop(createQuickPopMatch({
    roomId: "qp3_cpu",
    queueKey: "traditional",
    mode: "traditional",
    humanUids: ["human-a", "human-b"],
    createdAt: 1,
    protocol: "quickPopV3",
  }));
  state.seats["human-a"].control = "cpuTemporary";

  const advanced = playCpuTurn(state, "human-a");

  assert.notEqual(advanced, null);
  assert.equal(advanced?.currentTurnUid, "human-b");
  assert.ok((advanced?.revision ?? 0) > state.revision);
  assert.equal(playCpuTurn(state, "human-b"), null);
});
