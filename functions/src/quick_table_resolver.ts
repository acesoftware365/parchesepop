import { createHash, randomBytes, randomUUID } from "node:crypto";

export const QUICK_TABLE_PROTOCOL = "quickTableV3" as const;
export const QUICK_TABLE_COLORS = ["red", "green", "yellow", "blue"] as const;
export type QuickTableColor = (typeof QUICK_TABLE_COLORS)[number];
export type QuickTableVisibility = "public" | "private" | "code";

export interface QuickTableMember {
  uid: string;
  color: QuickTableColor;
  joinedAt: number;
}

export interface QuickTableRoom {
  protocol: typeof QUICK_TABLE_PROTOCOL;
  roomId: string;
  visibility: QuickTableVisibility;
  accessCode?: string;
  createdByUid: string;
  mode: "traditional" | "chaos";
  status: "waiting" | "inGame" | "closed";
  revision: number;
  members: Record<string, QuickTableMember>;
  participantUids: Record<string, true>;
  createdAt: number;
  updatedAt: number;
}

export function createQuickTableRoom(input: {
  uid: string;
  visibility: QuickTableVisibility;
  mode: "traditional" | "chaos";
  now: number;
  roomNonce?: string;
  code?: string;
}): QuickTableRoom {
  const roomNonce = input.roomNonce ?? randomUUID();
  const roomId = `qt3_${createHash("sha256").update(`${input.uid}:${input.now}:${roomNonce}`).digest("hex").slice(0, 24)}`;
  const accessCode = input.visibility === "code" ? input.code ?? newAccessCode() : undefined;
  return {
    protocol: QUICK_TABLE_PROTOCOL,
    roomId,
    visibility: input.visibility,
    ...(accessCode === undefined ? {} : { accessCode }),
    createdByUid: input.uid,
    mode: input.mode,
    status: "waiting",
    revision: 0,
    members: {
      [input.uid]: { uid: input.uid, color: "red", joinedAt: input.now },
    },
    participantUids: { [input.uid]: true },
    createdAt: input.now,
    updatedAt: input.now,
  };
}

export function joinQuickTableRoom(
  room: QuickTableRoom,
  uid: string,
  now: number,
): QuickTableRoom | null {
  if (room.protocol !== QUICK_TABLE_PROTOCOL || room.status !== "waiting") return null;
  if (room.members[uid] !== undefined) return room;
  const color = QUICK_TABLE_COLORS[Object.keys(room.members).length];
  if (color === undefined) return null;
  return {
    ...room,
    revision: room.revision + 1,
    members: { ...room.members, [uid]: { uid, color, joinedAt: now } },
    participantUids: { ...room.participantUids, [uid]: true },
    updatedAt: now,
  };
}

function newAccessCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = randomBytes(6);
  return Array.from(bytes, (value) => alphabet[value % alphabet.length]).join("");
}
