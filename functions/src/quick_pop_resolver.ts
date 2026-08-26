import { createHash, randomUUID } from "node:crypto";

export const QUICK_POP_PROTOCOL = "quickPopV3";

export type QuickPopTicketState = "waiting" | "assigned" | "cancelled";

export interface QuickPopTicket {
  uid: string;
  /** Stable only for one explicit tap on Play Online. */
  attemptId: string;
  displayName: string;
  ticketId: string;
  queueKey: string;
  mode: "traditional" | "chaos";
  minPlayers: number;
  maxPlayers: number;
  joinedAt: number;
  /** The first cohort's fixed lobby deadline. */
  launchAt: number;
  expiresAt: number;
  state: QuickPopTicketState;
  roomId?: string;
}

export interface QuickPopRoomPlan {
  roomId: string;
  queueKey: string;
  mode: QuickPopTicket["mode"];
  humanUids: string[];
  humanDisplayNames?: Record<string, string>;
  createdAt: number;
  protocol: typeof QUICK_POP_PROTOCOL;
}

export interface QuickPopResolution {
  room: QuickPopRoomPlan;
  assignedTicketIds: string[];
}

/**
 * Pure, deterministic resolver. The database adapter must persist its result
 * with one RTDB transaction over the queue tickets before creating the match.
 * Re-running it against the same inputs therefore produces the same room id.
 */
export function resolveQuickPop(
  tickets: readonly QuickPopTicket[],
  now: number,
  { minHumanPlayers = 2 }: { minHumanPlayers?: number } = {},
): QuickPopResolution | null {
  const compatible = tickets
    .filter((ticket) =>
      ticket.state === "waiting" &&
      ticket.expiresAt > now &&
      ticket.minPlayers >= 2 &&
      ticket.maxPlayers >= ticket.minPlayers &&
      ticket.maxPlayers <= 4,
    )
    .sort(compareTickets);

  for (const anchor of compatible) {
    const cohort = compatible
      .filter((candidate) => isCompatible(anchor, candidate))
      .slice(0, anchor.maxPlayers);
    // At the lobby deadline Quick Pop may launch a one-human room and fill
    // every remaining color with server-controlled CPU seats.
    if (cohort.length < Math.max(1, minHumanPlayers)) continue;

    const humanUids = cohort.map((ticket) => ticket.uid).sort();
    const humanDisplayNames = Object.fromEntries(
      cohort.map((ticket) => [ticket.uid, ticket.displayName] as const),
    );
    const assignedTicketIds = cohort.map((ticket) => ticket.ticketId).sort();
    return {
      room: {
        roomId: deterministicRoomId(anchor.queueKey, assignedTicketIds),
        queueKey: anchor.queueKey,
        mode: anchor.mode,
        humanUids,
        humanDisplayNames,
        createdAt: now,
        protocol: QUICK_POP_PROTOCOL,
      },
      assignedTicketIds,
    };
  }
  return null;
}

export function createTicket(
  input: Omit<QuickPopTicket, "ticketId" | "state">,
): QuickPopTicket {
  return { ...input, ticketId: randomUUID(), state: "waiting" };
}

export function deterministicRoomId(queueKey: string, ticketIds: string[]): string {
  const stableTickets = [...ticketIds].sort().join("|");
  const digest = createHash("sha256")
    .update(`${QUICK_POP_PROTOCOL}|${queueKey}|${stableTickets}`)
    .digest("hex")
    .slice(0, 24);
  return `qp3_${digest}`;
}

function compareTickets(left: QuickPopTicket, right: QuickPopTicket): number {
  return left.joinedAt - right.joinedAt || left.ticketId.localeCompare(right.ticketId);
}

function isCompatible(anchor: QuickPopTicket, candidate: QuickPopTicket): boolean {
  return (
    anchor.queueKey === candidate.queueKey &&
    anchor.mode === candidate.mode &&
    anchor.minPlayers === candidate.minPlayers &&
    anchor.maxPlayers === candidate.maxPlayers
  );
}
