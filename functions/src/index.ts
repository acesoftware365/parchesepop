import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getFunctions } from "firebase-admin/functions";
import { onValueWritten } from "firebase-functions/v2/database";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onTaskDispatched } from "firebase-functions/v2/tasks";

import {
  createTicket,
  resolveQuickPop,
  type QuickPopRoomPlan,
  type QuickPopTicket,
} from "./quick_pop_resolver.js";
import { createQuickPopMatch } from "./match_state.js";
import { startTraditionalQuickPop, type TraditionalQuickPopState } from "./traditional_quick_pop_engine.js";
import { applyV3TraditionalQuickPopCommand } from "./v3_command_service.js";
import { playCpuTurn } from "./cpu_quick_pop.js";
import {
  createQuickTableRoom,
  joinQuickTableRoom,
  type QuickTableRoom,
  type QuickTableVisibility,
} from "./quick_table_resolver.js";

const v3DatabaseUrl = "https://parchese-pop-default-rtdb.firebaseio.com";
const firebaseApp = initializeApp({ databaseURL: v3DatabaseUrl });
const realtimeDatabase = getDatabase(firebaseApp);
// One player may start Quick Pop: after ten seconds the server fills vacant
// seats with CPU. Four humans skip that wait and launch immediately.
const quickPopLobbyWindowMs = 10_000;
// Keep a short grace period after the visible countdown so a callable retry
// can resolve the ticket before the resolver regards it as expired.
const quickPopTicketGraceMs = 5_000;
const quickPopAfkTakeoverDelaySeconds = 5;
const quickPopSharedLoadingDelaySeconds = 3;

// Pin every V3 server operation to the same RTDB instance used by the Flutter
// clients. This avoids relying on an implicit default-instance lookup.
function v3Database() {
  return realtimeDatabase;
}

// These defaults intentionally protect the first beta from surprise scaling.
// They are source-controlled and are not deployed by this change.
setGlobalOptions({
  region: "us-east1",
  minInstances: 0,
  maxInstances: 3,
  concurrency: 20,
});

type JoinQuickPopInput = {
  attemptId?: unknown;
  queueKey?: unknown;
  displayName?: unknown;
  mode?: unknown;
  minPlayers?: unknown;
  maxPlayers?: unknown;
};

type LeaveQuickPopInput = { queueKey?: unknown; roomId?: unknown };

type QueueDocument = {
  tickets?: Record<string, QuickPopTicket>;
  resolutions?: Record<string, QuickPopRoomPlan>;
};

/**
 * V3 matchmaking entry point.
 *
 * It is deliberately separate from onlineV2. One transaction owns the queue
 * resolution and ticket assignment, so concurrent callers cannot create two
 * human rooms for the same ticket cohort. The room ID is deterministic and
 * may safely be retried after a network timeout.
 */
export const joinQuickPopV3 = onCall(
  // App Check is initialized by the Flutter client where the platform
  // provides a provider. It must not be enforced until a provider has also
  // been registered for Windows; enforcing it sooner would make one of the
  // supported game platforms unable to play. Firebase Auth and the V3 Rules
  // still require a signed-in player and prohibit every direct state write.
  { enforceAppCheck: false, timeoutSeconds: 15 },
  async (request) => {
    if (request.auth === null || request.auth === undefined) {
      throw new HttpsError("unauthenticated", "Sign in before joining Quick Pop.");
    }

    const uid = request.auth.uid;
    const input = validateJoinInput(request.data);
    const database = v3Database();
    const now = Date.now();
    const ticketPath = `onlineV3/quickPop/queues/${input.queueKey}/tickets/${uid}`;
    const ticketRef = database.ref(ticketPath);
    const ticketResult = await ticketRef.transaction((raw) => {
      const existing = raw as QuickPopTicket | null;
      // A ticket is reusable only by retries from this exact search screen.
      // A new tap on Play Online carries a new attemptId and must never reopen
      // an old assignment, even if that old room is technically still inGame.
      if (existing?.state === "assigned" && existing.attemptId === input.attemptId) {
        return existing;
      }
      if (
        existing?.state === "waiting" &&
        existing.attemptId === input.attemptId &&
        existing.expiresAt > now
      ) {
        return {
          ...existing,
          displayName: input.displayName,
          launchAt: existing.launchAt ?? existing.joinedAt + quickPopLobbyWindowMs,
        };
      }
      return createTicket({
        uid,
        attemptId: input.attemptId,
        displayName: input.displayName,
        queueKey: input.queueKey,
        mode: input.mode,
        minPlayers: input.minPlayers,
        maxPlayers: input.maxPlayers,
        joinedAt: now,
        launchAt: now + quickPopLobbyWindowMs,
        expiresAt: now + quickPopLobbyWindowMs + quickPopTicketGraceMs,
      });
    });

    const ticket = ticketResult.snapshot.val() as QuickPopTicket | null;
    if (ticket === null) {
      throw new HttpsError("aborted", "Quick Pop ticket was not created.");
    }

    const resolution = await resolveQueue(input.queueKey, now);
    if (resolution !== null) await provisionMatch(resolution);
    const settledTicket = (await ticketRef.get()).val() as QuickPopTicket | null;
    const assignedRoomId = settledTicket?.roomId ?? resolution?.roomId ?? null;
    const launchAt =
      settledTicket?.launchAt ??
      ticket.launchAt ??
      ticket.joinedAt + quickPopLobbyWindowMs;
    const queueAfterJoin = ((await database.ref(`onlineV3/quickPop/queues/${input.queueKey}`).get()).val() ?? {}) as QueueDocument;
    const lobbyPlayerCount = Math.min(
      input.maxPlayers,
      Object.values(queueAfterJoin.tickets ?? {}).filter(
        (candidate) =>
          candidate.state === "waiting" &&
          candidate.expiresAt > now &&
          candidate.mode === input.mode &&
          candidate.minPlayers === input.minPlayers &&
          candidate.maxPlayers === input.maxPlayers,
      ).length,
    );
    logger.info("quick_pop_v3_join", {
      uid,
      queueKey: input.queueKey,
      ticketId: settledTicket?.ticketId ?? ticket.ticketId,
      roomId: assignedRoomId,
    });

    return {
      protocol: "quickPopV3",
      ticketId: settledTicket?.ticketId ?? ticket.ticketId,
      state: assignedRoomId === null ? "waiting" : "assigned",
      roomId: assignedRoomId,
      launchAt,
      expiresAt: settledTicket?.expiresAt ?? ticket.expiresAt,
      lobbyPlayerCount:
        assignedRoomId === null ? Math.max(1, lobbyPlayerCount) : null,
      maxPlayers: input.maxPlayers,
    };
  },
);

/** Releases a player's assignment after they deliberately exit a V3 match. */
export const leaveQuickPopV3 = onCall(
  { enforceAppCheck: false, timeoutSeconds: 15 },
  async (request) => {
    if (request.auth === null || request.auth === undefined) {
      throw new HttpsError("unauthenticated", "Sign in before leaving Quick Pop.");
    }
    const input = validateLeaveQuickPopInput(request.data);
    const ticketRef = v3Database().ref(
      `onlineV3/quickPop/queues/${input.queueKey}/tickets/${request.auth.uid}`,
    );
    await ticketRef.transaction((raw) => {
      const ticket = raw as QuickPopTicket | null;
      if (ticket === null || ticket.roomId !== input.roomId) return;
      return {
        ...ticket,
        state: "cancelled" as const,
        expiresAt: Date.now(),
        roomId: undefined,
      };
    });
    return { protocol: "quickPopV3", released: true };
  },
);

/** The only V3 endpoint that may advance a Quick Pop board. */
export const submitQuickPopCommandV3 = onCall(
  { enforceAppCheck: false, timeoutSeconds: 15 },
  async (request) => {
    if (request.auth === null || request.auth === undefined) {
      throw new HttpsError("unauthenticated", "Sign in before sending a Quick Pop command.");
    }
    const uid = request.auth.uid;
    const input = validateCommandInput(request.data);
    const ref = v3Database().ref(`onlineV3/matches/${input.roomId}`);
    // The RTDB transaction callback runs once against its local cache before
    // the server sync arrives. Seed it so an existing room is never mistaken
    // for a missing one on a fresh function instance.
    const loadedState = (await ref.get()).val() as TraditionalQuickPopState | null;
    let response: { code: string; revision: number } | null = null;

    const transaction = await ref.transaction((raw) => {
      // Admin RTDB invokes a transaction once with an empty local cache on a
      // cold function. The server snapshot above is the safe initial value;
      // any retry receives the authoritative `raw` value instead.
      const state = (raw ?? loadedState) as TraditionalQuickPopState | null;
      if (state === null || state.protocol !== "onlineV3" || state.matchFormat !== "quickPop") {
        logger.warn("quick_pop_v3_command_room_mismatch", {
          roomId: input.roomId,
          exists: state !== null,
          protocol: state?.protocol ?? null,
          matchFormat: state?.matchFormat ?? null,
        });
        throw new HttpsError("not-found", "Quick Pop V3 room was not found.");
      }
      if (state.seats?.[uid]?.control !== "human") {
        throw new HttpsError("permission-denied", "You are not a human player in this room.");
      }
      if (typeof state.startAt === "number" && Date.now() < state.startAt) {
        response = { code: "not-ready", revision: state.revision };
        return;
      }
      const result = applyV3TraditionalQuickPopCommand(state, {
        actorUid: uid,
        idempotencyKey: input.idempotencyKey,
        expectedRevision: input.expectedRevision,
        kind: input.kind,
        payload: input.payload,
        submittedAt: Date.now(),
      });
      response = { code: result.code, revision: result.revision };
      return result.code === "accepted" ? result.state : undefined;
    });

    if (!transaction.committed && response === null) {
      throw new HttpsError("aborted", "Quick Pop command could not be processed.");
    }
    await queueNextCpuIfNeeded(transaction.snapshot.val() as TraditionalQuickPopState | null);
    const completedResponse = response!;
    logger.info("quick_pop_v3_command", { uid, roomId: input.roomId, ...completedResponse });
    return completedResponse;
  },
);

/** Creates a Quick Table lobby. The creator is an organizer, never the game authority. */
export const createQuickTableV3 = onCall(
  { enforceAppCheck: false, timeoutSeconds: 15 },
  async (request) => {
    if (request.auth === null || request.auth === undefined) {
      throw new HttpsError("unauthenticated", "Sign in before creating a Quick Table.");
    }
    const input = validateCreateQuickTableInput(request.data);
    const room = createQuickTableRoom({
      uid: request.auth.uid,
      visibility: input.visibility,
      mode: input.mode,
      now: Date.now(),
    });
    const database = v3Database();
    if (room.accessCode !== undefined) {
      const codeRef = database.ref(`onlineV3/quickTable/codes/${room.accessCode}`);
      const claim = await codeRef.transaction((raw) => raw ?? { roomId: room.roomId });
      if (!claim.committed) {
        throw new HttpsError("aborted", "Please retry creating the table.");
      }
    }
    await database.ref(`onlineV3/quickTable/rooms/${room.roomId}`).transaction((raw) => raw ?? room);
    if (room.visibility === "public") {
      await database.ref(`onlineV3/quickTable/publicRooms/${room.roomId}`).set(publicQuickTableSummary(room));
    }
    return quickTableResponse(room);
  },
);

/** Joins by opaque room id or access code; neither path exposes an RTDB index. */
export const joinQuickTableV3 = onCall(
  { enforceAppCheck: false, timeoutSeconds: 15 },
  async (request) => {
    if (request.auth === null || request.auth === undefined) {
      throw new HttpsError("unauthenticated", "Sign in before joining a Quick Table.");
    }
    const input = validateJoinQuickTableInput(request.data);
    const database = v3Database();
    const roomId = input.roomId ?? await quickTableRoomIdForCode(database, input.accessCode!);
    const ref = database.ref(`onlineV3/quickTable/rooms/${roomId}`);
    let failure: "not-found" | "full" | "closed" | null = null;
    const result = await ref.transaction((raw) => {
      const room = raw as QuickTableRoom | null;
      if (room === null) {
        failure = "not-found";
        return;
      }
      if (room.status === "closed") {
        failure = "closed";
        return;
      }
      const next = joinQuickTableRoom(room, request.auth!.uid, Date.now());
      if (next === null) {
        failure = "full";
        return;
      }
      return next;
    });
    if (!result.committed && failure !== null) {
      throw new HttpsError(failure === "not-found" ? "not-found" : "failed-precondition", `Quick Table is ${failure}.`);
    }
    const room = result.snapshot.val() as QuickTableRoom | null;
    if (room === null) throw new HttpsError("aborted", "Quick Table could not be joined.");
    if (room.visibility === "public") {
      await database.ref(`onlineV3/quickTable/publicRooms/${room.roomId}`).set(publicQuickTableSummary(room));
    }
    return quickTableResponse(room);
  },
);

type DisconnectTask = {
  roomId: string;
  uid: string;
  epoch: string;
};

type CpuTurnTask = { roomId: string };
type StartMatchTask = { roomId: string; startAt: number };

type V3Presence = {
  state?: unknown;
  epoch?: unknown;
};

/**
 * Presence is the only V3 path a client may write. On disconnect, queue a
 * bounded server task; on return, restore the person after any CPU turn has
 * completed. The canonical board is never written by this trigger.
 */
export const observeV3Presence = onValueWritten(
  {
    // The default RTDB URL uses the legacy firebaseio.com domain, which is the
    // us-central1 instance. Database event functions must live with the DB.
    // The callable and task worker remain in us-east1 for the beta API.
    ref: "/onlineV3/presence/{roomId}/{uid}",
    instance: "parchese-pop-default-rtdb",
    region: "us-central1",
  },
  async (event) => {
    const roomId = event.params.roomId;
    const uid = event.params.uid;
    const presence = (event.data.after.val() ?? {}) as V3Presence;
    if (presence.state === "disconnected" && typeof presence.epoch === "string") {
      await getFunctions().taskQueue("locations/us-east1/functions/resolveV3Disconnect").enqueue(
        { roomId, uid, epoch: presence.epoch } satisfies DisconnectTask,
        { scheduleDelaySeconds: quickPopAfkTakeoverDelaySeconds },
      );
      return;
    }
    if (presence.state === "connected") await restoreReturnedPlayer(roomId, uid);
  },
);

/** Cloud Tasks worker for delayed CPU takeover, configured for a small beta. */
export const resolveV3Disconnect = onTaskDispatched<DisconnectTask>(
  {
    region: "us-east1",
    timeoutSeconds: 30,
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 10 },
    rateLimits: { maxConcurrentDispatches: 4 },
  },
  async (request) => {
    const { roomId, uid, epoch } = request.data;
    if (!isV3RoomId(roomId) || typeof uid !== "string" || typeof epoch !== "string") return;
    const presence = (await v3Database().ref(`onlineV3/presence/${roomId}/${uid}`).get()).val() as V3Presence | null;
    if (presence?.state !== "disconnected" || presence.epoch !== epoch) return;

    const ref = v3Database().ref(`onlineV3/matches/${roomId}`);
    const loadedState = (await ref.get()).val() as TraditionalQuickPopState | null;
    const result = await ref.transaction((raw) => {
      const state = (raw ?? loadedState) as TraditionalQuickPopState | null;
      if (state === null || state.status !== "inGame" || state.seats[uid]?.control !== "human") return;
      const cpuState = structuredClone(state);
      cpuState.seats[uid] = { ...cpuState.seats[uid], control: "cpuTemporary" };
      cpuState.revision += 1;
      cpuState.updatedAt = Date.now();
      return state.currentTurnUid === uid
        ? playCpuTurn(cpuState, uid) ?? cpuState
        : cpuState;
    });
    await queueNextCpuIfNeeded(result.snapshot.val() as TraditionalQuickPopState | null);
    logger.info("quick_pop_v3_cpu_takeover", { roomId, uid, epoch });
  },
);

/** Drives empty-seat bots and temporary disconnected-player CPU turns. */
export const driveV3Cpu = onTaskDispatched<CpuTurnTask>(
  {
    region: "us-east1",
    timeoutSeconds: 30,
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 5 },
    rateLimits: { maxConcurrentDispatches: 4 },
  },
  async (request) => {
    const { roomId } = request.data;
    if (!isV3RoomId(roomId)) return;
    const ref = v3Database().ref(`onlineV3/matches/${roomId}`);
    const loadedState = (await ref.get()).val() as TraditionalQuickPopState | null;
    const result = await ref.transaction((raw) => {
      const state = (raw ?? loadedState) as TraditionalQuickPopState | null;
      if (state === null || state.status !== "inGame" || state.seats[state.currentTurnUid]?.control === "human") return;
      return playCpuTurn(state, state.currentTurnUid);
    });
    await queueNextCpuIfNeeded(result.snapshot.val() as TraditionalQuickPopState | null);
  },
);

/** Opens the canonical board after the shared loading screen deadline. */
export const startV3QuickPopMatch = onTaskDispatched<StartMatchTask>(
  {
    region: "us-east1",
    timeoutSeconds: 30,
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 5 },
    rateLimits: { maxConcurrentDispatches: 4 },
  },
  async (request) => {
    const { roomId, startAt } = request.data;
    if (!isV3RoomId(roomId) || !Number.isFinite(startAt)) return;
    await activateV3QuickPopMatch(roomId);
  },
);

/**
 * RTDB is the reliable clock for this short shared loading phase. Waiting in
 * the trigger keeps the start server-owned even if every player has merely
 * joined and no device remains responsible for starting the match.
 */
export const observeV3MatchStart = onValueWritten(
  {
    ref: "/onlineV3/matches/{roomId}/status",
    instance: "parchese-pop-default-rtdb",
    region: "us-central1",
  },
  async (event) => {
    if (event.data.before.val() === "starting" || event.data.after.val() !== "starting") return;
    const roomId = event.params.roomId;
    if (!isV3RoomId(roomId)) return;
    const state = (await v3Database().ref(`onlineV3/matches/${roomId}`).get()).val() as
      | ReturnType<typeof createQuickPopMatch>
      | TraditionalQuickPopState
      | null;
    if (state?.status !== "starting") return;
    const delay = Math.max(0, state.startAt - Date.now());
    if (delay > 0) await new Promise<void>((resolve) => setTimeout(resolve, delay));
    await activateV3QuickPopMatch(roomId);
  },
);

async function activateV3QuickPopMatch(roomId: string): Promise<void> {
  const ref = v3Database().ref(`onlineV3/matches/${roomId}`);
  const result = await ref.transaction((raw) => {
    const state = raw as ReturnType<typeof createQuickPopMatch> | TraditionalQuickPopState | null;
    if (state === null || state.status !== "starting") return;
    return startTraditionalQuickPop(state);
  });
  await queueNextCpuIfNeeded(result.snapshot.val() as TraditionalQuickPopState | null);
  logger.info("quick_pop_v3_started", { roomId, committed: result.committed });
}

async function resolveQueue(queueKey: string, now: number): Promise<QuickPopRoomPlan | null> {
  const queueRef = v3Database().ref(`onlineV3/quickPop/queues/${queueKey}`);
  const lockRef = queueRef.child("_resolverLock");
  const owner = `resolver_${now}_${Math.random().toString(36).slice(2)}`;
  const lock = await lockRef.transaction((current) => {
    const prior = current as { owner?: string; expiresAt?: number } | null;
    if (prior?.expiresAt !== undefined && prior.expiresAt > now) return;
    return { owner, expiresAt: now + 5_000 };
  });
  if (!lock.committed || lock.snapshot.child("owner").val() !== owner) return null;

  try {
    const queue = ((await queueRef.get()).val() ?? {}) as QueueDocument;
    const tickets = Object.values(queue.tickets ?? {});
    const resolution = resolveQuickPop(tickets, now);
    const oldestWaitingTicket = tickets
      .filter((ticket) => ticket.state === "waiting" && ticket.expiresAt > now)
      .sort((left, right) => left.joinedAt - right.joinedAt || left.ticketId.localeCompare(right.ticketId))[0];
    const deadlineReached =
      oldestWaitingTicket !== undefined &&
      now >= (oldestWaitingTicket.launchAt ?? oldestWaitingTicket.joinedAt + quickPopLobbyWindowMs);
    // Launch early only for a full four-human room. At the ten-second
    // deadline the resolver may also return a solo room, completed by CPU.
    const roomIsFull = resolution?.room.humanUids.length === 4;
    const selectedResolution = roomIsFull || deadlineReached
      ? resolution ?? resolveQuickPop(tickets, now, { minHumanPlayers: 1 })
      : null;
    if (selectedResolution === null) return null;
    const existing = queue.resolutions?.[selectedResolution.room.roomId];
    if (existing !== undefined) return existing;

    const ticketsById = new Map(
      Object.values(queue.tickets ?? {}).map((ticket) => [ticket.ticketId, ticket]),
    );
    const cohort = selectedResolution.assignedTicketIds
      .map((ticketId) => ticketsById.get(ticketId))
      .filter((ticket): ticket is QuickPopTicket => ticket !== undefined);
    const lobbyLaunchAt = Math.min(
      ...cohort.map((ticket) => ticket.launchAt ?? ticket.joinedAt + quickPopLobbyWindowMs),
    );
    if (!roomIsFull && now < lobbyLaunchAt) return null;

    const updates: Record<string, unknown> = {
      [`resolutions/${selectedResolution.room.roomId}`]: selectedResolution.room,
    };
    for (const ticketId of selectedResolution.assignedTicketIds) {
      const entry = Object.entries(queue.tickets ?? {}).find(([, ticket]) => ticket.ticketId === ticketId);
      if (entry === undefined) return null;
      const [uid, ticket] = entry;
      updates[`tickets/${uid}`] = { ...ticket, state: "assigned", roomId: selectedResolution.room.roomId };
    }
    await queueRef.update(updates);
    return selectedResolution.room;
  } finally {
    await lockRef.remove();
  }
}

async function provisionMatch(room: QuickPopRoomPlan): Promise<void> {
  const matchRef = v3Database().ref(`onlineV3/matches/${room.roomId}`);
  // The authoritative game becomes active immediately, but [startAt] remains
  // a server timestamp three seconds ahead. Every client stays on the shared
  // loading screen until that moment, while the command endpoint rejects
  // premature input above.
  const result = await matchRef.transaction(
    (raw) => raw ?? startTraditionalQuickPop(createQuickPopMatch(room)),
  );
  await queueNextCpuIfNeeded(result.snapshot.val() as TraditionalQuickPopState | null);
}

async function queueNextCpuIfNeeded(state: TraditionalQuickPopState | null): Promise<void> {
  if (state === null || state.status !== "inGame" || state.seats[state.currentTurnUid]?.control === "human") return;
  await getFunctions().taskQueue("locations/us-east1/functions/driveV3Cpu").enqueue(
    { roomId: state.roomId } satisfies CpuTurnTask,
  );
}

function validateJoinInput(value: unknown): Required<JoinQuickPopInput> & {
  attemptId: string;
  queueKey: string;
  displayName: string;
  mode: "traditional";
  minPlayers: 2 | 3 | 4;
  maxPlayers: 2 | 3 | 4;
} {
  const input = (value ?? {}) as JoinQuickPopInput;
  if (typeof input.attemptId !== "string" || !/^[A-Za-z0-9_-]{8,96}$/.test(input.attemptId)) {
    throw new HttpsError("invalid-argument", "attemptId is invalid.");
  }
  if (typeof input.queueKey !== "string" || !/^[a-z0-9_-]{1,40}$/i.test(input.queueKey)) {
    throw new HttpsError("invalid-argument", "queueKey is invalid.");
  }
  if (typeof input.displayName !== "string") {
    throw new HttpsError("invalid-argument", "displayName is invalid.");
  }
  const displayName = input.displayName.trim();
  if (displayName.length < 1 || displayName.length > 24 || /[\u0000-\u001F\u007F]/.test(displayName)) {
    throw new HttpsError("invalid-argument", "displayName is invalid.");
  }
  if (input.mode !== "traditional") {
    throw new HttpsError("failed-precondition", "Quick Pop V3 is currently enabled only for traditional mode.");
  }
  if (!isSeatCount(input.minPlayers) || !isSeatCount(input.maxPlayers) || input.minPlayers > input.maxPlayers) {
    throw new HttpsError("invalid-argument", "Quick Pop requires between two and four players.");
  }
  return {
    attemptId: input.attemptId,
    queueKey: input.queueKey,
    displayName,
    mode: input.mode,
    minPlayers: input.minPlayers,
    maxPlayers: input.maxPlayers,
  };
}

function validateLeaveQuickPopInput(value: unknown): {
  queueKey: string;
  roomId: string;
} {
  const input = (value ?? {}) as LeaveQuickPopInput;
  if (input.queueKey !== "traditional_v3_beta") {
    throw new HttpsError("invalid-argument", "queueKey is invalid.");
  }
  if (typeof input.roomId !== "string" || !isV3RoomId(input.roomId)) {
    throw new HttpsError("invalid-argument", "roomId is invalid.");
  }
  return { queueKey: input.queueKey, roomId: input.roomId };
}

function validateCreateQuickTableInput(value: unknown): {
  visibility: QuickTableVisibility;
  mode: "traditional" | "chaos";
} {
  const input = (value ?? {}) as Record<string, unknown>;
  if (input.visibility !== "public" && input.visibility !== "private" && input.visibility !== "code") {
    throw new HttpsError("invalid-argument", "Quick Table visibility is invalid.");
  }
  if (input.mode !== "traditional" && input.mode !== "chaos") {
    throw new HttpsError("invalid-argument", "Quick Table mode is invalid.");
  }
  return { visibility: input.visibility, mode: input.mode };
}

function validateJoinQuickTableInput(value: unknown): { roomId?: string; accessCode?: string } {
  const input = (value ?? {}) as Record<string, unknown>;
  const roomId = typeof input.roomId === "string" && /^qt3_[a-f0-9]{24}$/.test(input.roomId)
    ? input.roomId
    : undefined;
  const accessCode = typeof input.accessCode === "string" && /^[A-Z2-9]{6}$/.test(input.accessCode)
    ? input.accessCode
    : undefined;
  if (roomId === undefined && accessCode === undefined) {
    throw new HttpsError("invalid-argument", "Provide a valid Quick Table room id or code.");
  }
  return { roomId, accessCode };
}

async function quickTableRoomIdForCode(
  database: ReturnType<typeof getDatabase>,
  accessCode: string,
): Promise<string> {
  const raw = (await database.ref(`onlineV3/quickTable/codes/${accessCode}`).get()).val() as { roomId?: unknown } | null;
  if (typeof raw?.roomId !== "string" || !/^qt3_[a-f0-9]{24}$/.test(raw.roomId)) {
    throw new HttpsError("not-found", "Quick Table code was not found.");
  }
  return raw.roomId;
}

function publicQuickTableSummary(room: QuickTableRoom): Record<string, unknown> {
  return {
    roomId: room.roomId,
    mode: room.mode,
    status: room.status,
    memberCount: Object.keys(room.members).length,
    revision: room.revision,
    updatedAt: room.updatedAt,
  };
}

function quickTableResponse(room: QuickTableRoom): Record<string, unknown> {
  return {
    protocol: "quickTableV3",
    roomId: room.roomId,
    visibility: room.visibility,
    accessCode: room.accessCode ?? null,
    mode: room.mode,
    status: room.status,
    revision: room.revision,
    memberCount: Object.keys(room.members).length,
  };
}

function isSeatCount(value: unknown): value is 2 | 3 | 4 {
  return value === 2 || value === 3 || value === 4;
}

async function restoreReturnedPlayer(roomId: string, uid: string): Promise<void> {
  const ref = v3Database().ref(`onlineV3/matches/${roomId}`);
  const loadedState = (await ref.get()).val() as TraditionalQuickPopState | null;
  await ref.transaction((raw) => {
    const state = (raw ?? loadedState) as TraditionalQuickPopState | null;
    // A CPU finishes a complete turn atomically. If it is still the current
    // player, wait for the following connected event/normal flow instead of
    // letting a returning device interrupt a server move.
    if (state === null || state.seats[uid]?.control !== "cpuTemporary" || state.currentTurnUid === uid) return;
    const next = structuredClone(state);
    next.seats[uid] = { ...next.seats[uid], control: "human" };
    next.revision += 1;
    next.updatedAt = Date.now();
    return next;
  });
}

function isV3RoomId(value: string): boolean {
  return /^qp3_[a-f0-9]{24}$/.test(value);
}

function validateCommandInput(value: unknown): {
  roomId: string;
  idempotencyKey: string;
  expectedRevision: number;
  kind: "roll" | "move" | "moveAll";
  payload: Record<string, unknown>;
} {
  const input = (value ?? {}) as Record<string, unknown>;
  if (typeof input.roomId !== "string" || !/^qp3_[a-f0-9]{24}$/.test(input.roomId)) {
    throw new HttpsError("invalid-argument", "roomId is invalid.");
  }
  if (typeof input.idempotencyKey !== "string" || !/^[A-Za-z0-9_-]{8,96}$/.test(input.idempotencyKey)) {
    throw new HttpsError("invalid-argument", "idempotencyKey is invalid.");
  }
  if (!Number.isSafeInteger(input.expectedRevision) || (input.expectedRevision as number) < 0) {
    throw new HttpsError("invalid-argument", "expectedRevision is invalid.");
  }
  if (input.kind !== "roll" && input.kind !== "move" && input.kind !== "moveAll") {
    throw new HttpsError("invalid-argument", "command kind is invalid.");
  }
  if (input.payload !== undefined && (input.payload === null || typeof input.payload !== "object" || Array.isArray(input.payload))) {
    throw new HttpsError("invalid-argument", "payload is invalid.");
  }
  return {
    roomId: input.roomId,
    idempotencyKey: input.idempotencyKey,
    expectedRevision: input.expectedRevision as number,
    kind: input.kind,
    payload: (input.payload ?? {}) as Record<string, unknown>,
  };
}
