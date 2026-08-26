import type { QuickPopRoomPlan } from "./quick_pop_resolver.js";

export const QUICK_POP_RULES_VERSION = 2;
export const BOARD_COLORS = ["red", "green", "yellow", "blue"] as const;
export type BoardColor = (typeof BOARD_COLORS)[number];
export type SeatControl = "human" | "cpu" | "cpuTemporary";

export interface V3Seat {
  uid: string;
  color: BoardColor;
  control: SeatControl;
  displayName: string;
}

export interface V3MatchState {
  protocol: "onlineV3";
  roomId: string;
  matchFormat: "quickPop";
  mode: "traditional" | "chaos";
  rulesVersion: number;
  status: "starting" | "inGame" | "closed";
  revision: number;
  currentTurnUid: string;
  phase: "awaitingRoll" | "awaitingMove" | "finished";
  dice: number[];
  seats: Record<string, V3Seat>;
  pieces: Record<BoardColor, number[]>;
  /** Shared server timestamp at which every client may reveal the board. */
  startAt: number;
  createdAt: number;
  updatedAt: number;
}

/**
 * Creates the only canonical starting state for a resolved Quick Pop room.
 * The resolver controls every seat; the client does not supply a host, color,
 * CPU identity, current turn, die result, or board position.
 */
export function createQuickPopMatch(room: QuickPopRoomPlan): V3MatchState {
  const humanUids = [...room.humanUids].sort();
  const seats: Record<string, V3Seat> = {};
  for (let index = 0; index < BOARD_COLORS.length; index += 1) {
    const color = BOARD_COLORS[index];
    const uid = humanUids[index] ?? `cpu_v3_${room.roomId}_${color}`;
    const isHuman = humanUids[index] !== undefined;
    seats[uid] = {
      uid,
      color,
      control: isHuman ? "human" : "cpu",
      displayName: isHuman
        ? room.humanDisplayNames?.[uid] ?? "Jugador"
        : "CPU",
    };
  }

  return {
    protocol: "onlineV3",
    roomId: room.roomId,
    matchFormat: "quickPop",
    mode: room.mode,
    rulesVersion: QUICK_POP_RULES_VERSION,
    status: "starting",
    revision: 0,
    currentTurnUid: humanUids[0] ?? `cpu_v3_${room.roomId}_red`,
    phase: "awaitingRoll",
    dice: [],
    seats,
    pieces: { red: [-1, -1], green: [-1, -1], yellow: [-1, -1], blue: [-1, -1] },
    startAt: room.createdAt + 3_000,
    createdAt: room.createdAt,
    updatedAt: room.createdAt,
  };
}
