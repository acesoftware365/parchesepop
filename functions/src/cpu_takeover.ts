export interface PresenceSnapshot {
  uid: string;
  connected: boolean;
  changedAt: number;
  epoch: number;
}

export interface CpuTakeoverRequest {
  roomId: string;
  uid: string;
  turnRevision: number;
  presenceEpoch: number;
  dueAt: number;
}

export type CpuTakeoverDecision = "wait" | "cancel" | "takeover";

/**
 * A scheduled CPU task is safe to retry. It may take a seat only when it
 * still refers to the active turn and the same disconnect epoch.
 */
export function decideCpuTakeover(input: {
  now: number;
  currentTurnUid: string;
  currentRevision: number;
  presence: PresenceSnapshot | undefined;
  request: CpuTakeoverRequest;
}): CpuTakeoverDecision {
  const { now, currentTurnUid, currentRevision, presence, request } = input;
  if (now < request.dueAt) return "wait";
  if (currentTurnUid !== request.uid || currentRevision !== request.turnRevision) return "cancel";
  if (presence === undefined || presence.connected || presence.epoch !== request.presenceEpoch) return "cancel";
  return "takeover";
}

export function cpuTakeoverTaskId(request: CpuTakeoverRequest): string {
  return `cpu-${request.roomId}-${request.uid}-${request.turnRevision}-${request.presenceEpoch}`;
}
