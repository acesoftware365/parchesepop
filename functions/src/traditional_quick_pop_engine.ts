import { randomInt } from "node:crypto";

import type { CommandGateState } from "./command_gate.js";
import { BOARD_COLORS, type BoardColor, type V3MatchState } from "./match_state.js";

const COMMON_PATH_LENGTH = 64;
const FINISH_PROGRESS = 71;
const START_OFFSET: Record<BoardColor, number> = { red: 0, green: 17, yellow: 34, blue: 51 };
const HOME_ENTRY_OFFSET: Record<BoardColor, number> = { red: 63, green: 12, yellow: 29, blue: 46 };
const SAFE_LOOP_INDICES = new Set([0, 7, 12, 17, 24, 29, 34, 41, 46, 51, 58, 63]);

export type TraditionalQuickPopAction =
  | { kind: "roll"; dice?: readonly [number, number] }
  | { kind: "move"; tokenId: 0 | 1; die: number }
  | { kind: "moveAll"; tokenId: 0 | 1 };

export interface TraditionalQuickPopState extends V3MatchState, CommandGateState {
  status: "inGame" | "closed";
  mode: "traditional";
  turn: number;
  remainingDice: number[];
  hasRolled: boolean;
  consecutiveDoubles: number;
  winnerUid?: string;
}

export function startTraditionalQuickPop(match: V3MatchState): TraditionalQuickPopState {
  if (match.mode !== "traditional") throw new Error("Quick Pop V3 currently supports traditional mode only.");
  return {
    ...clone(match),
    mode: "traditional",
    status: "inGame",
    turn: 1,
    remainingDice: [],
    hasRolled: false,
    consecutiveDoubles: 0,
    participantUids: Object.fromEntries(
      Object.values(match.seats)
        .filter((seat) => seat.control === "human")
        .map((seat) => [seat.uid, true] as const),
    ),
    processedCommands: {},
  };
}

/** Applies one already-authorized server command. It never trusts client dice. */
export function applyTraditionalQuickPopAction(
  state: TraditionalQuickPopState,
  action: TraditionalQuickPopAction,
): TraditionalQuickPopState | null {
  if (state.status !== "inGame") return null;
  const next = clone(state);
  if (action.kind === "roll") return roll(next, action.dice);
  if (!next.hasRolled) return null;
  const current = currentSeat(next);
  const tokenId = action.tokenId;
  if (!Number.isInteger(tokenId) || tokenId < 0 || tokenId > 1) return null;

  const consumed = action.kind === "move" ? [action.die] : combinedDice(next);
  if (consumed === null || consumed.some((die) => !next.remainingDice.includes(die))) return null;
  const amount = consumed.reduce((sum, die) => sum + die, 0);
  const progress = next.pieces[current.color][tokenId];
  if (!canMove(next, current.color, tokenId, amount, action.kind === "moveAll")) return null;

  for (const die of consumed) next.remainingDice.splice(next.remainingDice.indexOf(die), 1);
  const enteredFromNest = progress < 0;
  next.pieces[current.color][tokenId] = enteredFromNest ? 0 : progress + amount;
  const captured = captureAtLanding(next, current.color, tokenId, progress, enteredFromNest, amount, action.kind === "moveAll");
  if (captured) next.remainingDice.push(20);
  if (next.pieces[current.color][tokenId] >= FINISH_PROGRESS) {
    next.pieces[current.color][tokenId] = FINISH_PROGRESS;
    next.remainingDice.push(10);
  }
  if (next.pieces[current.color].every((piece) => piece >= FINISH_PROGRESS)) {
    next.status = "closed";
    next.phase = "finished";
    next.hasRolled = false;
    next.remainingDice = [];
    next.winnerUid = current.uid;
  } else if (next.remainingDice.length === 0 || !hasAnyMove(next)) {
    endTurn(next);
  }
  next.revision += 1;
  next.updatedAt = Date.now();
  return next;
}

function roll(state: TraditionalQuickPopState, suppliedDice?: readonly [number, number]): TraditionalQuickPopState | null {
  if (state.hasRolled || state.phase !== "awaitingRoll") return null;
  // Supplied dice exist only for deterministic server tests. Production calls
  // omit them, so dice are generated inside the trusted backend process.
  const dice = suppliedDice ?? [randomInt(1, 7), randomInt(1, 7)] as const;
  if (!isDie(dice[0]) || !isDie(dice[1])) return null;
  state.dice = [...dice];
  state.hasRolled = true;
  state.phase = "awaitingMove";
  state.consecutiveDoubles = dice[0] === dice[1] ? state.consecutiveDoubles + 1 : 0;
  if (state.consecutiveDoubles >= 3) {
    const seat = currentSeat(state);
    const penalized = state.pieces[seat.color]
      .map((progress, tokenId) => ({ progress, tokenId }))
      .filter((piece) => piece.progress >= 0 && piece.progress < COMMON_PATH_LENGTH)
      .sort((left, right) => right.progress - left.progress)[0];
    if (penalized !== undefined) state.pieces[seat.color][penalized.tokenId] = -1;
    state.consecutiveDoubles = 0;
    state.dice = [dice[0], 0];
    endTurn(state);
  } else {
    state.remainingDice = [...dice];
    if (!hasAnyMove(state)) endTurn(state);
  }
  state.revision += 1;
  state.updatedAt = Date.now();
  return state;
}

function canMove(
  state: TraditionalQuickPopState,
  color: BoardColor,
  tokenId: number,
  amount: number,
  usingAllDice: boolean,
): boolean {
  const progress = state.pieces[color][tokenId];
  if (amount <= 0 || progress >= FINISH_PROGRESS) return false;
  if (progress < 0) return !usingAllDice && !startBlocked(state, color);
  const homeEntryCapture = !usingAllDice && amount === 5 && progress === COMMON_PATH_LENGTH - 2 && capturableOpponentAt(state, color, HOME_ENTRY_OFFSET[color], true) !== null;
  const destination = progress + amount;
  if (destination > FINISH_PROGRESS) return false;
  for (let step = progress + 1; step <= destination; step += 1) {
    if (step < COMMON_PATH_LENGTH) {
      const index = loopIndex(color, step);
      if (isBarrier(state, index)) return false;
      if (index === HOME_ENTRY_OFFSET[color] && opponentsAt(state, color, index).length > 0 && !homeEntryCapture) return false;
      if (step === destination && (commonOccupancy(state, index) >= 2 || safeOccupiedByOpponent(state, color, index))) return false;
    } else if (step < FINISH_PROGRESS && laneOccupancy(state, color, step) >= 2) {
      return false;
    }
  }
  return true;
}

function captureAtLanding(
  state: TraditionalQuickPopState,
  color: BoardColor,
  tokenId: number,
  previousProgress: number,
  enteredFromNest: boolean,
  amount: number,
  usingAllDice: boolean,
): boolean {
  const progress = state.pieces[color][tokenId];
  if (progress >= COMMON_PATH_LENGTH) return false;
  const homeEntryCapture = !usingAllDice && amount === 5 && previousProgress === COMMON_PATH_LENGTH - 2;
  const index = homeEntryCapture ? HOME_ENTRY_OFFSET[color] : loopIndex(color, progress);
  const target = capturableOpponentAt(state, color, index, homeEntryCapture || (enteredFromNest && index === START_OFFSET[color]));
  if (target === null) return false;
  state.pieces[target.color][target.tokenId] = -1;
  return true;
}

function hasAnyMove(state: TraditionalQuickPopState): boolean {
  const seat = currentSeat(state);
  return state.pieces[seat.color].some((_, tokenId) =>
    state.remainingDice.some((die) => canMove(state, seat.color, tokenId, die, false)) ||
    (combinedDice(state) !== null && canMove(state, seat.color, tokenId, combinedDice(state)!.reduce((sum, die) => sum + die, 0), true)),
  );
}

function combinedDice(state: TraditionalQuickPopState): number[] | null {
  if (state.dice.length !== 2 || state.dice.some((die) => !isDie(die)) || state.remainingDice.length !== 2) return null;
  const remaining = [...state.remainingDice];
  for (const die of state.dice) {
    const index = remaining.indexOf(die);
    if (index < 0) return null;
    remaining.splice(index, 1);
  }
  return remaining.length === 0 ? [...state.dice] : null;
}

function endTurn(state: TraditionalQuickPopState): void {
  const doubles = state.dice[0] === state.dice[1];
  state.remainingDice = [];
  state.hasRolled = false;
  state.phase = "awaitingRoll";
  if (!doubles) {
    const current = currentSeat(state);
    const nextColor = BOARD_COLORS[(BOARD_COLORS.indexOf(current.color) + 1) % BOARD_COLORS.length];
    state.currentTurnUid = Object.values(state.seats).find((seat) => seat.color === nextColor)!.uid;
  }
  state.turn += 1;
}

function currentSeat(state: TraditionalQuickPopState) {
  const seat = state.seats[state.currentTurnUid];
  if (seat === undefined) throw new Error("Current turn does not belong to a V3 seat.");
  return seat;
}

function loopIndex(color: BoardColor, progress: number): number {
  return (START_OFFSET[color] + progress) % 68;
}

function opponentsAt(state: TraditionalQuickPopState, owner: BoardColor, index: number) {
  return BOARD_COLORS.flatMap((color) =>
    color === owner
      ? []
      : state.pieces[color]
          .map((progress, tokenId) => ({ color, tokenId, progress }))
          .filter((piece) => piece.progress >= 0 && piece.progress < COMMON_PATH_LENGTH && loopIndex(color, piece.progress) === index),
  );
}

function capturableOpponentAt(state: TraditionalQuickPopState, owner: BoardColor, index: number, forcedSafeCapture: boolean) {
  if (SAFE_LOOP_INDICES.has(index) && !forcedSafeCapture) return null;
  const targets = opponentsAt(state, owner, index);
  return targets.length === 1 ? targets[0] : null;
}

function commonOccupancy(state: TraditionalQuickPopState, index: number): number {
  return BOARD_COLORS.reduce((count, color) => count + state.pieces[color].filter((progress) => progress >= 0 && progress < COMMON_PATH_LENGTH && loopIndex(color, progress) === index).length, 0);
}

function laneOccupancy(state: TraditionalQuickPopState, color: BoardColor, progress: number): number {
  return state.pieces[color].filter((value) => value === progress).length;
}

function isBarrier(state: TraditionalQuickPopState, index: number): boolean {
  return BOARD_COLORS.some((color) => state.pieces[color].filter((progress) => progress >= 0 && progress < COMMON_PATH_LENGTH && loopIndex(color, progress) === index).length >= 2);
}

function safeOccupiedByOpponent(state: TraditionalQuickPopState, owner: BoardColor, index: number): boolean {
  return SAFE_LOOP_INDICES.has(index) && opponentsAt(state, owner, index).length > 0;
}

function startBlocked(state: TraditionalQuickPopState, color: BoardColor): boolean {
  const start = START_OFFSET[color];
  return isBarrier(state, start) || commonOccupancy(state, start) >= 2;
}

function isDie(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 6;
}

function clone<T>(value: T): T {
  return structuredClone(value);
}
