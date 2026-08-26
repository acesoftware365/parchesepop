import assert from "node:assert/strict";
import test from "node:test";

import { createQuickPopMatch } from "./match_state.js";
import { applyTraditionalQuickPopAction, startTraditionalQuickPop } from "./traditional_quick_pop_engine.js";

function game() {
  return startTraditionalQuickPop(createQuickPopMatch({
    roomId: "qp3_engine",
    queueKey: "traditional",
    mode: "traditional",
    humanUids: ["human-a", "human-b"],
    createdAt: 1_735_000_000_000,
    protocol: "quickPopV3",
  }));
}

test("any die releases a Quick Pop piece from base", () => {
  const rolled = applyTraditionalQuickPopAction(game(), { kind: "roll", dice: [1, 6] })!;
  const moved = applyTraditionalQuickPopAction(rolled, { kind: "move", tokenId: 0, die: 1 })!;

  assert.equal(moved.pieces.red[0], 0);
  assert.deepEqual(moved.remainingDice, [6]);
});

test("a barrier blocks movement through its loop square", () => {
  const state = game();
  state.pieces.green = [0, 0];
  state.pieces.red = [16, -1];
  const rolled = applyTraditionalQuickPopAction(state, { kind: "roll", dice: [2, 6] })!;

  assert.equal(applyTraditionalQuickPopAction(rolled, { kind: "move", tokenId: 0, die: 2 }), null);
});

test("a capture returns an opponent to base and awards +20", () => {
  const state = game();
  state.pieces.red = [1, -1];
  // Green reaches global square 4 after (4 - 17) modulo 68 = 55 steps.
  state.pieces.green = [55, -1];
  const rolled = applyTraditionalQuickPopAction(state, { kind: "roll", dice: [3, 6] })!;
  const moved = applyTraditionalQuickPopAction(rolled, { kind: "move", tokenId: 0, die: 3 })!;

  assert.equal(moved.pieces.green[0], -1);
  assert.deepEqual(moved.remainingDice, [6, 20]);
});

test("finishing both Quick Pop pieces closes the match", () => {
  const state = game();
  state.pieces.red = [71, 70];
  const rolled = applyTraditionalQuickPopAction(state, { kind: "roll", dice: [1, 6] })!;
  const moved = applyTraditionalQuickPopAction(rolled, { kind: "move", tokenId: 1, die: 1 })!;

  assert.equal(moved.status, "closed");
  assert.equal(moved.winnerUid, "human-a");
});
