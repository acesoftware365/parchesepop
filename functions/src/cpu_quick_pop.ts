import { applyTraditionalQuickPopAction, type TraditionalQuickPopState } from "./traditional_quick_pop_engine.js";

const MAX_CPU_ACTIONS_PER_TAKEOVER = 24;

/**
 * Completes one disconnected player's safe turn inside the backend.
 *
 * The function is deterministic in its choice of move; only dice remain
 * server-random. It never writes a client command or takes ownership from a
 * player whose turn has already advanced.
 */
export function playCpuTurn(
  state: TraditionalQuickPopState,
  uid: string,
): TraditionalQuickPopState | null {
  if (state.status !== "inGame" || state.currentTurnUid !== uid || state.seats[uid]?.control === "human") {
    return null;
  }
  let next = structuredClone(state);
  let changed = false;

  for (let actionCount = 0; actionCount < MAX_CPU_ACTIONS_PER_TAKEOVER; actionCount += 1) {
    if (next.status !== "inGame" || next.currentTurnUid !== uid || next.seats[uid]?.control === "human") break;
    const advanced = next.phase === "awaitingRoll"
      ? applyTraditionalQuickPopAction(next, { kind: "roll" })
      : chooseMove(next);
    if (advanced === null) break;
    next = advanced;
    changed = true;
  }

  return changed ? next : null;
}

function chooseMove(state: TraditionalQuickPopState): TraditionalQuickPopState | null {
  for (const tokenId of [0, 1] as const) {
    const allDice = applyTraditionalQuickPopAction(state, { kind: "moveAll", tokenId });
    if (allDice !== null) return allDice;
    for (const die of [...state.remainingDice].sort((left, right) => right - left)) {
      const moved = applyTraditionalQuickPopAction(state, { kind: "move", tokenId, die });
      if (moved !== null) return moved;
    }
  }
  return null;
}
