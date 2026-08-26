import { processCommand, type CommandResult, type PlayerCommand } from "./command_gate.js";
import {
  applyTraditionalQuickPopAction,
  type TraditionalQuickPopAction,
  type TraditionalQuickPopState,
} from "./traditional_quick_pop_engine.js";

export function applyV3TraditionalQuickPopCommand(
  state: TraditionalQuickPopState,
  command: PlayerCommand,
): CommandResult<TraditionalQuickPopState> {
  return processCommand(state, command, (current, envelope) => {
    const action = commandFromEnvelope(envelope);
    return action === null ? null : applyTraditionalQuickPopAction(current, action);
  });
}

function commandFromEnvelope(command: PlayerCommand): TraditionalQuickPopAction | null {
  if (command.kind === "roll") return { kind: "roll" };
  const payload = command.payload ?? {};
  const tokenId = payload.tokenId;
  if (tokenId !== 0 && tokenId !== 1) return null;
  if (command.kind === "moveAll") return { kind: "moveAll", tokenId };
  if (command.kind === "move" && typeof payload.die === "number") {
    return { kind: "move", tokenId, die: payload.die };
  }
  return null;
}
