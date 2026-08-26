import assert from "node:assert/strict";
import test from "node:test";

import { processCommand, type CommandGateState, type PlayerCommand } from "./command_gate.js";

function state(): CommandGateState {
  return {
    revision: 7,
    currentTurnUid: "player-a",
    participantUids: ["player-a", "player-b"],
    processedCommands: {},
  };
}

function command(overrides: Partial<PlayerCommand> = {}): PlayerCommand {
  return {
    actorUid: "player-a",
    idempotencyKey: "command_20260824_0001",
    expectedRevision: 7,
    kind: "roll",
    submittedAt: 1_735_000_000_000,
    ...overrides,
  };
}

function accept(current: CommandGateState): CommandGateState {
  return { ...current, revision: current.revision + 1, currentTurnUid: "player-b" };
}

test("accepts exactly one valid command", () => {
  const result = processCommand(state(), command(), accept);

  assert.equal(result.code, "accepted");
  assert.equal(result.revision, 8);
  assert.equal(result.state.currentTurnUid, "player-b");
});

test("returns a stable result for a double tap", () => {
  const first = processCommand(state(), command(), accept);
  const second = processCommand(first.state, command(), accept);

  assert.equal(second.code, "duplicate");
  assert.equal(second.revision, 8);
  assert.equal(second.state.revision, 8);
});

test("initializes an omitted RTDB command receipt map", () => {
  const persistedNewMatch = {
    ...state(),
    participantUids: { "player-a": true, "player-b": true },
    processedCommands: undefined,
  } satisfies CommandGateState;

  const result = processCommand(persistedNewMatch, command(), accept);

  assert.equal(result.code, "accepted");
  assert.ok(result.state.processedCommands?.["player-a:command_20260824_0001"]);
});

test("rejects stale revisions and commands from a different player", () => {
  assert.equal(processCommand(state(), command({ expectedRevision: 6 }), accept).code, "stale_revision");
  assert.equal(processCommand(state(), command({ actorUid: "player-b" }), accept).code, "not_your_turn");
});
