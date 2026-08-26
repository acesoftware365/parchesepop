import assert from "node:assert/strict";
import test from "node:test";

import { createQuickPopMatch } from "./match_state.js";

test("creates a hostless two-human Quick Pop state with server-controlled CPU seats", () => {
  const match = createQuickPopMatch({
    roomId: "qp3_room",
    queueKey: "traditional",
    mode: "traditional",
    humanUids: ["human-b", "human-a"],
    humanDisplayNames: { "human-a": "Ana", "human-b": "Beto" },
    createdAt: 1_735_000_000_000,
    protocol: "quickPopV3",
  });

  assert.equal(match.currentTurnUid, "human-a");
  assert.equal(match.seats["human-a"].color, "red");
  assert.equal(match.seats["human-b"].color, "green");
  assert.equal(match.seats["human-a"].displayName, "Ana");
  assert.equal(match.seats["human-b"].displayName, "Beto");
  assert.equal(Object.keys(match.seats).length, 4);
  assert.equal(match.seats.cpu_v3_qp3_room_yellow.control, "cpu");
  assert.deepEqual(match.pieces.blue, [-1, -1]);
  assert.equal("hostUid" in match, false);
});
