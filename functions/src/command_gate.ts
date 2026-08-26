export type CommandKind = "roll" | "move" | "moveAll" | "powerUp";

export interface PlayerCommand {
  actorUid: string;
  idempotencyKey: string;
  expectedRevision: number;
  kind: CommandKind;
  submittedAt: number;
  payload?: Record<string, unknown>;
}

export interface CommandResult<State> {
  code: "accepted" | "duplicate" | "stale_revision" | "not_your_turn" | "invalid";
  revision: number;
  state: State;
}

export interface CommandReceipt {
  code: "accepted";
  revision: number;
  processedAt: number;
}

export interface CommandGateState {
  revision: number;
  currentTurnUid: string;
  // Maps are the canonical persisted shape: they make per-player RTDB Rules
  // checks constant-time. Arrays remain accepted while beta rooms created by
  // an older deployment naturally age out.
  participantUids: string[] | Record<string, true>;
  // RTDB does not persist an empty object, so a newly created match can read
  // this as absent on its first command.
  processedCommands?: Record<string, CommandReceipt>;
}

/**
 * Applies the protocol-level rules around a game-engine transition. The engine
 * callback is intentionally separate: it will later be the port of the
 * existing validated Parchis engine. This gate is already authoritative for
 * idempotency, membership, turn ownership and optimistic concurrency.
 */
export function processCommand<State extends CommandGateState>(
  state: State,
  command: PlayerCommand,
  transition: (current: State, command: PlayerCommand) => State | null,
): CommandResult<State> {
  const commandKey = `${command.actorUid}:${command.idempotencyKey}`;
  const processedCommands = state.processedCommands ?? {};
  const previouslyProcessed = processedCommands[commandKey];
  if (previouslyProcessed !== undefined) {
    return { code: "duplicate", revision: previouslyProcessed.revision, state };
  }
  if (!isValidCommand(command) || !isParticipant(state.participantUids, command.actorUid)) {
    return reject(state, "invalid");
  }
  if (command.expectedRevision !== state.revision) {
    return reject(state, "stale_revision");
  }
  if (command.actorUid !== state.currentTurnUid) {
    return reject(state, "not_your_turn");
  }

  const next = transition(state, command);
  if (next === null) return reject(state, "invalid");
  const accepted: CommandResult<State> = {
    code: "accepted",
    revision: next.revision,
    state: next,
  };
  next.processedCommands = {
    ...processedCommands,
    [commandKey]: {
      code: "accepted",
      revision: next.revision,
      processedAt: command.submittedAt,
    },
  };
  return accepted;
}

function isParticipant(
  participants: CommandGateState["participantUids"],
  uid: string,
): boolean {
  return Array.isArray(participants)
    ? participants.includes(uid)
    : participants[uid] === true;
}

function reject<State extends CommandGateState>(
  state: State,
  code: Exclude<CommandResult<State>["code"], "accepted" | "duplicate">,
): CommandResult<State> {
  return { code, revision: state.revision, state };
}

function isValidCommand(command: PlayerCommand): boolean {
  return (
    typeof command.actorUid === "string" &&
    command.actorUid.length > 0 &&
    /^[A-Za-z0-9_-]{8,96}$/.test(command.idempotencyKey) &&
    Number.isSafeInteger(command.expectedRevision) &&
    command.expectedRevision >= 0 &&
    Number.isFinite(command.submittedAt)
  );
}
