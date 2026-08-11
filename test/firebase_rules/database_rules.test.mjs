import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  get,
  limitToFirst,
  orderByChild,
  query,
  ref,
  set,
  startAt,
  update,
} from 'firebase/database';

const projectId = 'parchese-pop';
const emulatorAddress =
  process.env.FIREBASE_DATABASE_EMULATOR_HOST ?? '127.0.0.1:9000';
const separator = emulatorAddress.lastIndexOf(':');
const host = emulatorAddress.slice(0, separator);
const port = Number(emulatorAddress.slice(separator + 1));
const rules = await readFile(new URL('../../database.rules.json', import.meta.url), 'utf8');

const environment = await initializeTestEnvironment({
  projectId,
  database: { host, port, rules },
});

const dbFor = (uid) => environment.authenticatedContext(uid).database();
const pathRef = (uid, path) => ref(dbFor(uid), path);
const activeQueueQuery = (uid, path, ownJoinedAt) =>
  query(
    pathRef(uid, path),
    orderByChild('activeUntil'),
    startAt(ownJoinedAt),
    limitToFirst(64),
  );
const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

async function seed(path, value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), path), value);
  });
}

const member = (uid, displayName, seat, joinedAt, ready = false) => ({
  uid,
  displayName,
  seat,
  ready,
  joinedAt,
});

const presence = (uid, changedAt) => ({
  uid,
  state: 'connected',
  changedAt,
  connectionId: `connection_${uid}`,
});

function waitingRoom(now, { withGuest = false } = {}) {
  return {
    id: 'room-1',
    code: 'ABC234',
    hostUid: 'host',
    visibility: 'private',
    status: 'waiting',
    mode: 'classic',
    matchFormat: 'quickTable',
    members: {
      host: member('host', 'Host', 'red', now),
      ...(withGuest
        ? { guest: member('guest', 'Guest', 'green', now + 1) }
        : {}),
    },
    presence: {
      host: presence('host', now),
      ...(withGuest ? { guest: presence('guest', now + 1) } : {}),
    },
    revision: withGuest ? 1 : 0,
    createdAt: now,
    updatedAt: withGuest ? now + 1 : now,
  };
}

function matchDocument(now) {
  return {
    schemaVersion: 1,
    authorityModel: 'activeHostV1',
    roomId: 'room-1',
    matchId: 'match-1',
    hostUid: 'host',
    hostLocalColor: 'red',
    authorityRevision: 0,
    stateRevision: 0,
    checkpoint: { phase: 'playing' },
    authorityCheckpoint: { revision: 0 },
    createdAt: now,
    updatedAt: now,
  };
}

const queueTicket = (uid, ticketId, queueKey, joinedAt) => ({
  ticketId,
  uid,
  displayName: uid === 'leader' ? 'Leader' : 'Follower',
  queueKey,
  joinedAt,
  deadlineAt: joinedAt + 5000,
  activeUntil: joinedAt + 5000,
  state: 'waiting',
});

test('Realtime Database rules enforce the online security contract', async (t) => {
  await t.test('guest request is allowed, room-root write is denied, and host admission is allowed', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now);
    await seed('onlineV2/rooms/room-1', room);

    const request = {
      roomId: 'room-1',
      roomCode: 'ABC234',
      uid: 'guest',
      displayName: 'Guest',
      attemptId: 'join_attempt_guest',
      requestedAt: now + 1,
    };
    const fence = {
      uid: 'guest',
      attemptId: request.attemptId,
      requestedAt: request.requestedAt,
    };
    await assertSucceeds(
      set(pathRef('guest', 'onlineV2/rooms/room-1/joinFences/guest'), fence),
    );
    await assertSucceeds(
      set(pathRef('guest', 'onlineV2/joinRequests/room-1/guest'), request),
    );

    await assertFails(
      set(pathRef('guest', 'onlineV2/rooms/room-1'), {
        ...room,
        visibility: 'public',
      }),
    );

    const admitted = waitingRoom(now, { withGuest: true });
    admitted.joinFences = { guest: fence };
    // Admission adds membership only. The admitted device establishes its own
    // presence after observing the room snapshot.
    delete admitted.presence.guest;
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1'), admitted),
    );
    const snapshot = await assertSucceeds(
      get(pathRef('guest', 'onlineV2/rooms/room-1/members/guest')),
    );
    assert.equal(snapshot.val().seat, 'green');
  });

  await t.test('join fences reject stale or cross-account admission attempts', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    await seed('onlineV2/rooms/room-1', waitingRoom(now));
    const fencePath = 'onlineV2/rooms/room-1/joinFences/guest';
    const requestPath = 'onlineV2/joinRequests/room-1/guest';
    const fence = {
      uid: 'guest',
      attemptId: 'join_attempt_exact',
      requestedAt: now + 1,
    };
    const request = {
      roomId: 'room-1',
      roomCode: 'ABC234',
      uid: 'guest',
      displayName: 'Guest',
      attemptId: fence.attemptId,
      requestedAt: fence.requestedAt,
    };

    await assertFails(
      set(pathRef('outsider', fencePath), {
        ...fence,
        uid: 'guest',
      }),
    );
    await assertSucceeds(set(pathRef('guest', fencePath), fence));
    await assertFails(
      set(pathRef('guest', requestPath), {
        ...request,
        attemptId: 'join_attempt_mismatch',
      }),
    );
    await assertSucceeds(set(pathRef('guest', requestPath), request));

    await assertSucceeds(set(pathRef('guest', fencePath), null));
    const staleAdmission = waitingRoom(now, { withGuest: true });
    delete staleAdmission.presence.guest;
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1'), staleAdmission),
    );
  });

  await t.test('only a pristine host-owned Quick Table room can be rolled back', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const roomPath = 'onlineV2/rooms/room-1';

    const pristine = waitingRoom(now);
    pristine.creationState = 'initializing';
    await seed(roomPath, pristine);
    await assertFails(set(pathRef('guest', roomPath), null));
    await assertSucceeds(set(pathRef('host', roomPath), null));

    const shared = waitingRoom(now, { withGuest: true });
    shared.creationState = 'initializing';
    await seed(roomPath, shared);
    await assertFails(set(pathRef('host', roomPath), null));

    const inGame = waitingRoom(now);
    inGame.status = 'inGame';
    await seed(roomPath, inGame);
    await assertFails(set(pathRef('host', roomPath), null));

    const quickPopStarting = waitingRoom(now);
    quickPopStarting.status = 'starting';
    quickPopStarting.matchFormat = 'quickPop';
    quickPopStarting.quickPopLaunch = {
      queueKey: 'traditional_quickPop',
      claimId: 'claim_rollback',
      firstUid: 'host',
      firstTicketId: 'ticket_host',
      secondUid: 'guest',
      secondTicketId: 'ticket_guest',
      sharedDeadlineAt: now + 5000,
    };
    await seed(roomPath, quickPopStarting);
    await assertFails(set(pathRef('host', roomPath), null));
  });

  await t.test('a member may change only their Ready flag, never their seat', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    await seed('onlineV2/rooms/room-1', waitingRoom(now, { withGuest: true }));

    await assertSucceeds(
      update(pathRef('guest', 'onlineV2/rooms/room-1/members/guest'), {
        ready: true,
      }),
    );
    await assertFails(
      update(pathRef('guest', 'onlineV2/rooms/room-1/members/guest'), {
        seat: 'blue',
      }),
    );
  });

  await t.test('a player may delete only their own profile and unresolved queue ticket', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const profilePath = 'onlineV2/profiles/player';
    const queueKey = 'traditional_quickPop';
    const ticketPath = `onlineV2/quickQueues/${queueKey}/player`;

    await assertSucceeds(
      set(pathRef('player', profilePath), {
        uid: 'player',
        displayName: 'Player',
        createdAt: now,
        updatedAt: now,
      }),
    );
    await assertSucceeds(get(pathRef('player', profilePath)));
    await assertFails(get(pathRef('other', profilePath)));
    await assertSucceeds(
      set(
        pathRef('player', ticketPath),
        {
          ...queueTicket('player', 'ticket_player', queueKey, now),
          displayName: 'Player',
        },
      ),
    );

    await assertFails(set(pathRef('other', profilePath), null));
    await assertFails(set(pathRef('other', ticketPath), null));
    await assertSucceeds(
      update(pathRef('player', ticketPath), {
        state: 'cancelled',
        activeUntil: 0,
      }),
    );
    await assertSucceeds(set(pathRef('player', ticketPath), null));
    await assertSucceeds(set(pathRef('player', profilePath), null));
  });

  await t.test('Quick Pop queue enumeration ends when a search is no longer active', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const queueKey = 'traditional_quickPop';
    const queuePath = `onlineV2/quickQueues/${queueKey}`;

    await assertSucceeds(
      set(
        pathRef('active', `${queuePath}/active`),
        {
          ...queueTicket('active', 'ticket_active', queueKey, now),
          displayName: 'Active',
        },
      ),
    );
    await assertSucceeds(
      set(
        pathRef('peer', `${queuePath}/peer`),
        {
          ...queueTicket('peer', 'ticket_peer', queueKey, now + 1),
          displayName: 'Peer',
        },
      ),
    );
    await seed(`${queuePath}/historical`, {
      ...queueTicket(
        'historical',
        'ticket_historical',
        queueKey,
        now - 1,
      ),
      displayName: 'Historical',
      state: 'cancelled',
      activeUntil: 0,
    });
    await assertFails(get(pathRef('active', queuePath)));
    const activeQueue = await assertSucceeds(
      get(activeQueueQuery('active', queuePath, now)),
    );
    assert.equal(activeQueue.hasChild('peer'), true);
    assert.equal(activeQueue.hasChild('historical'), false);
    await assertFails(
      get(activeQueueQuery('active', queuePath, now - 10000)),
    );
    await assertFails(
      get(
        query(
          pathRef('active', queuePath),
          orderByChild('activeUntil'),
          startAt(now),
          limitToFirst(63),
        ),
      ),
    );
    await assertFails(
      get(
        query(
          pathRef('active', queuePath),
          orderByChild('deadlineAt'),
          startAt(now),
          limitToFirst(64),
        ),
      ),
    );

    await assertFails(
      update(pathRef('active', `${queuePath}/active`), {
        state: 'cancelled',
      }),
    );
    await assertSucceeds(
      update(pathRef('active', `${queuePath}/active`), {
        state: 'cancelled',
        activeUntil: 0,
      }),
    );
    await assertSucceeds(get(pathRef('active', `${queuePath}/active`)));
    await assertFails(get(activeQueueQuery('active', queuePath, now)));
    await assertFails(get(pathRef('active', `${queuePath}/peer`)));

    await seed(`${queuePath}/expired`, {
      ...queueTicket('expired', 'ticket_expired_private', queueKey, now - 6000),
      displayName: 'Expired',
    });
    await assertSucceeds(get(pathRef('expired', `${queuePath}/expired`)));
    await assertFails(
      get(activeQueueQuery('expired', queuePath, now - 6000)),
    );
    await assertFails(get(pathRef('expired', `${queuePath}/peer`)));
  });

  await t.test('durable account resources are private, exact, and cleanup-safe', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const resourcePath = 'onlineV2/accountResources/player';
    const resources = {
      schemaVersion: 1,
      updatedAt: now,
      requiresBackendCleanup: false,
      rooms: {
        'room-1': { roomId: 'room-1', role: 'member', indexedAt: now },
      },
      presence: {
        'room-1': { roomId: 'room-1', indexedAt: now },
      },
      hostedRooms: {
        'room-2': { roomId: 'room-2', indexedAt: now },
      },
      joinRequests: {
        'room-3': {
          roomId: 'room-3',
          roomCode: 'ABC234',
          uid: 'player',
          displayName: 'Player',
          attemptId: 'join_attempt_player',
          requestedAt: now,
        },
      },
      quickQueues: {
        traditional_quickPop: {
          queueKey: 'traditional_quickPop',
          ticketId: 'ticket_player',
          indexedAt: now,
        },
      },
    };

    await assertSucceeds(set(pathRef('player', resourcePath), resources));
    await assertSucceeds(get(pathRef('player', resourcePath)));
    await assertFails(get(pathRef('other', resourcePath)));
    await assertFails(set(pathRef('other', resourcePath), null));
    await assertFails(
      set(pathRef('player', `${resourcePath}/rooms/room-1`), {
        roomId: 'different-room',
        role: 'member',
        indexedAt: now,
      }),
    );
    await assertFails(
      update(pathRef('player', resourcePath), { unexpected: true }),
    );

    await assertSucceeds(
      update(pathRef('player', resourcePath), {
        requiresBackendCleanup: true,
        updatedAt: now + 1,
      }),
    );
    await assertFails(
      update(pathRef('player', resourcePath), {
        requiresBackendCleanup: false,
        updatedAt: now + 2,
      }),
    );
    await assertSucceeds(set(pathRef('player', resourcePath), null));
  });

  await t.test('room creation and account indexing commit atomically', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const roomId = 'room-player';
    const room = {
      id: roomId,
      code: 'ABC234',
      hostUid: 'player',
      visibility: 'private',
      status: 'waiting',
      mode: 'classic',
      matchFormat: 'quickTable',
      members: {
        player: member('player', 'Player', 'red', now),
      },
      presence: {
        player: presence('player', now),
      },
      revision: 0,
      createdAt: now,
      updatedAt: now,
    };

    await assertSucceeds(
      update(pathRef('player', 'onlineV2'), {
        [`profiles/player`]: {
          uid: 'player',
          displayName: 'Player',
          createdAt: now,
          updatedAt: now,
        },
        [`rooms/${roomId}`]: room,
        'accountResources/player/schemaVersion': 1,
        'accountResources/player/updatedAt': now,
        'accountResources/player/requiresBackendCleanup': false,
        [`accountResources/player/rooms/${roomId}`]: {
          roomId,
          role: 'host',
          indexedAt: now,
        },
        [`accountResources/player/presence/${roomId}`]: {
          roomId,
          indexedAt: now,
        },
        [`accountResources/player/hostedRooms/${roomId}`]: {
          roomId,
          indexedAt: now,
        },
      }),
    );
    await assertFails(
      update(pathRef('other', 'onlineV2'), {
        'profiles/player': null,
        'accountResources/player': null,
      }),
    );
    await assertSucceeds(
      update(pathRef('player', 'onlineV2'), {
        'profiles/player': null,
        'accountResources/player': null,
      }),
    );
  });

  await t.test('both Quick Pop players accept, either participant resolves', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const queueKey = 'classic_quickPop';
    const claimId = 'claim_contract_test';
    const first = queueTicket('leader', 'ticket_leader', queueKey, now - 100);
    const second = queueTicket('follower', 'ticket_follower', queueKey, now - 50);

    await assertSucceeds(
      set(pathRef('leader', `onlineV2/quickQueues/${queueKey}/leader`), first),
    );
    await assertSucceeds(
      set(pathRef('follower', `onlineV2/quickQueues/${queueKey}/follower`), second),
    );
    await assertSucceeds(
      update(pathRef('leader', `onlineV2/quickQueues/${queueKey}/leader`), {
        claimId,
      }),
    );
    await assertSucceeds(
      update(pathRef('follower', `onlineV2/quickQueues/${queueKey}/follower`), {
        claimId,
      }),
    );

    const claimPath = `onlineV2/quickClaims/${queueKey}/${claimId}`;
    const leaderPendingClaim = await assertSucceeds(
      get(pathRef('leader', claimPath)),
    );
    assert.equal(leaderPendingClaim.exists(), false);
    await assertFails(get(pathRef('observer', `onlineV2/quickQueues/${queueKey}`)));
    await assertSucceeds(
      set(
        pathRef('observer', `onlineV2/quickQueues/${queueKey}/observer`),
        queueTicket('observer', 'ticket_observer', queueKey, now),
      ),
    );
    const visibleQueue = await assertSucceeds(
      get(
        activeQueueQuery(
          'observer',
          `onlineV2/quickQueues/${queueKey}`,
          now,
        ),
      ),
    );
    assert.equal(visibleQueue.val().leader.displayName, 'Leader');

    const claim = {
      claimId,
      queueKey,
      leaderUid: 'leader',
      firstUid: 'leader',
      firstTicketId: 'ticket_leader',
      secondUid: 'follower',
      secondTicketId: 'ticket_follower',
      createdAt: now,
    };
    await assertSucceeds(
      set(pathRef('leader', claimPath), claim),
    );
    await assertSucceeds(get(pathRef('leader', claimPath)));
    await assertSucceeds(get(pathRef('follower', claimPath)));
    await assertFails(get(pathRef('observer', claimPath)));

    const leaderAcceptance = {
      uid: 'leader',
      ticketId: 'ticket_leader',
      opponentUid: 'follower',
      opponentTicketId: 'ticket_follower',
      acceptedAt: now + 1,
    };
    const followerAcceptance = {
      uid: 'follower',
      ticketId: 'ticket_follower',
      opponentUid: 'leader',
      opponentTicketId: 'ticket_leader',
      acceptedAt: now + 2,
    };
    await assertSucceeds(
      set(
        pathRef(
          'leader',
          `onlineV2/quickClaims/${queueKey}/${claimId}/acceptances/leader`,
        ),
        leaderAcceptance,
      ),
    );
    await assertSucceeds(
      set(
        pathRef(
          'follower',
          `onlineV2/quickClaims/${queueKey}/${claimId}/acceptances/follower`,
        ),
        followerAcceptance,
      ),
    );

    // Claim metadata is immutable after creation. Transport retries abort the
    // root transaction and validate this existing snapshot locally.
    const claimSnapshot = await get(
      pathRef('leader', `onlineV2/quickClaims/${queueKey}/${claimId}`),
    );
    await assertFails(
      set(
        pathRef('leader', `onlineV2/quickClaims/${queueKey}/${claimId}`),
        claimSnapshot.val(),
      ),
    );

    const resolution = {
      kind: 'human',
      roomId: 'quick_shared_room',
      resolvedAt: now + 3,
      firstUid: 'leader',
      secondUid: 'follower',
    };
    const resolutionPath =
      `onlineV2/quickClaims/${queueKey}/${claimId}/resolution`;
    await assertSucceeds(set(pathRef('follower', resolutionPath), resolution));
    await assertFails(set(pathRef('leader', resolutionPath), resolution));
    await assertSucceeds(
      update(pathRef('leader', `onlineV2/quickQueues/${queueKey}/leader`), {
        state: 'matched',
        activeUntil: 0,
        roomId: 'quick_shared_room',
        opponentUid: 'follower',
      }),
    );
    await assertSucceeds(
      update(pathRef('follower', `onlineV2/quickQueues/${queueKey}/follower`), {
        state: 'matched',
        activeUntil: 0,
        roomId: 'quick_shared_room',
        opponentUid: 'leader',
      }),
    );
    await assertFails(
      get(
        activeQueueQuery(
          'leader',
          `onlineV2/quickQueues/${queueKey}`,
          first.joinedAt,
        ),
      ),
    );
    await assertSucceeds(
      get(pathRef('leader', `onlineV2/quickQueues/${queueKey}/follower`)),
    );
    await assertSucceeds(
      update(pathRef('observer', `onlineV2/quickQueues/${queueKey}/observer`), {
        state: 'cancelled',
        activeUntil: 0,
      }),
    );
    await assertFails(
      get(pathRef('observer', `onlineV2/quickQueues/${queueKey}/leader`)),
    );
  });

  await t.test('CPU fallback is denied before the five-second deadline', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const queueKey = 'chaos_quickPop';
    await assertSucceeds(
      set(
        pathRef('solo', `onlineV2/quickQueues/${queueKey}/solo`),
        {
          ...queueTicket('solo', 'ticket_solo', queueKey, now),
          displayName: 'Solo',
        },
      ),
    );

    await assertFails(
      update(pathRef('solo', `onlineV2/quickQueues/${queueKey}/solo`), {
        state: 'cpuFallback',
        activeUntil: 0,
        roomId: 'quick_cpu_room',
      }),
    );

    const expired = {
      ...queueTicket('expired', 'ticket_expired', queueKey, now - 5100),
      displayName: 'Expired',
    };
    await assertSucceeds(
      set(pathRef('expired', `onlineV2/quickQueues/${queueKey}/expired`), expired),
    );
    await assertSucceeds(
      update(pathRef('expired', `onlineV2/quickQueues/${queueKey}/expired`), {
        state: 'cpuFallback',
        activeUntil: 0,
        roomId: 'quick_cpu_expired',
      }),
    );

    await assertSucceeds(
      set(pathRef('short', `onlineV2/quickQueues/${queueKey}/short`), {
        ...queueTicket('short', 'ticket_short', queueKey, now),
        deadlineAt: now + 1200,
        activeUntil: now + 1200,
      }),
    );
    await assertFails(
      set(pathRef('too-long', `onlineV2/quickQueues/${queueKey}/too-long`), {
        ...queueTicket('too-long', 'ticket_too_long', queueKey, now),
        deadlineAt: now + 5001,
        activeUntil: now + 5001,
      }),
    );
    const missingActiveUntil = queueTicket(
      'missing-index',
      'ticket_missing_index',
      queueKey,
      now,
    );
    delete missingActiveUntil.activeUntil;
    await assertFails(
      set(
        pathRef(
          'missing-index',
          `onlineV2/quickQueues/${queueKey}/missing-index`,
        ),
        missingActiveUntil,
      ),
    );
    await assertFails(
      set(
        pathRef('wrong-index', `onlineV2/quickQueues/${queueKey}/wrong-index`),
        {
          ...queueTicket(
            'wrong-index',
            'ticket_wrong_index',
            queueKey,
            now,
          ),
          activeUntil: 0,
        },
      ),
    );
  });

  await t.test('a committed human resolution atomically blocks CPU fallback', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const queueKey = 'classic_quickPop';
    const claimId = 'claim_human_wins_cpu_race';
    const leaderTicket = {
      ...queueTicket('leader', 'ticket_human_leader', queueKey, now - 6000),
      claimId,
    };
    const followerTicket = {
      ...queueTicket('follower', 'ticket_human_follower', queueKey, now - 5900),
      claimId,
    };
    const claim = {
      claimId,
      queueKey,
      leaderUid: 'leader',
      firstUid: 'leader',
      firstTicketId: leaderTicket.ticketId,
      secondUid: 'follower',
      secondTicketId: followerTicket.ticketId,
      createdAt: now - 5800,
      acceptances: {
        leader: {
          uid: 'leader',
          ticketId: leaderTicket.ticketId,
          opponentUid: 'follower',
          opponentTicketId: followerTicket.ticketId,
          acceptedAt: now - 100,
        },
        follower: {
          uid: 'follower',
          ticketId: followerTicket.ticketId,
          opponentUid: 'leader',
          opponentTicketId: leaderTicket.ticketId,
          acceptedAt: now - 90,
        },
      },
      resolution: {
        kind: 'human',
        roomId: 'quick_human_room',
        resolvedAt: now - 80,
        firstUid: 'leader',
        secondUid: 'follower',
      },
    };
    await seed(`onlineV2/quickQueues/${queueKey}/leader`, leaderTicket);
    await seed(`onlineV2/quickQueues/${queueKey}/follower`, followerTicket);
    await seed(`onlineV2/quickClaims/${queueKey}/${claimId}`, claim);

    await assertFails(
      update(pathRef('leader', `onlineV2/quickQueues/${queueKey}/leader`), {
        state: 'cpuFallback',
        activeUntil: 0,
        roomId: 'quick_cpu_must_not_win',
      }),
    );
    await assertSucceeds(
      update(pathRef('leader', `onlineV2/quickQueues/${queueKey}/leader`), {
        state: 'matched',
        activeUntil: 0,
        roomId: 'quick_human_room',
        opponentUid: 'follower',
      }),
    );
  });

  await t.test('host creation paths accept standard and two-human Quick Pop rooms', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1'), waitingRoom(now)),
    );

    const queueKey = 'traditional_quickPop';
    const claimId = 'quick-launch-claim';
    const roomId = 'quick-room';
    const leaderTicket = {
      ...queueTicket('leader', 'ticket-leader', queueKey, now),
      state: 'matched',
      activeUntil: 0,
      claimId,
      roomId,
      opponentUid: 'follower',
    };
    const followerTicket = {
      ...queueTicket('follower', 'ticket-follower', queueKey, now),
      state: 'matched',
      activeUntil: 0,
      claimId,
      roomId,
      opponentUid: 'leader',
    };
    await seed(`onlineV2/quickQueues/${queueKey}/leader`, leaderTicket);
    await seed(`onlineV2/quickQueues/${queueKey}/follower`, followerTicket);
    await seed(`onlineV2/quickClaims/${queueKey}/${claimId}`, {
      claimId,
      queueKey,
      leaderUid: 'leader',
      firstUid: 'leader',
      firstTicketId: leaderTicket.ticketId,
      secondUid: 'follower',
      secondTicketId: followerTicket.ticketId,
      createdAt: now,
      resolution: {
        kind: 'human',
        roomId,
        resolvedAt: now,
        firstUid: 'leader',
        secondUid: 'follower',
      },
    });

    const quickRoom = {
      id: 'quick-room',
      code: 'QCK234',
      hostUid: 'leader',
      visibility: 'private',
      status: 'starting',
      mode: 'traditional',
      matchFormat: 'quickPop',
      members: {
        leader: member('leader', 'Leader', 'red', now, true),
        follower: member('follower', 'Follower', 'green', now, true),
        cpu_yellow: member('cpu_yellow', 'CPU Rayo', 'yellow', now, true),
        cpu_blue: member('cpu_blue', 'CPU Pop', 'blue', now, true),
      },
      presence: {
        leader: presence('leader', now),
        follower: presence('follower', now),
        cpu_yellow: presence('cpu_yellow', now),
        cpu_blue: presence('cpu_blue', now),
      },
      revision: 0,
      createdAt: now,
      updatedAt: now,
      quickPopLaunch: {
        queueKey,
        claimId,
        firstUid: 'leader',
        firstTicketId: leaderTicket.ticketId,
        secondUid: 'follower',
        secondTicketId: followerTicket.ticketId,
        sharedDeadlineAt: leaderTicket.deadlineAt,
      },
    };
    await assertSucceeds(
      set(pathRef('leader', 'onlineV2/rooms/quick-room'), quickRoom),
    );
  });

  await t.test('Quick Pop launch barrier serializes ready, play, and fallback', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const queueKey = 'traditional_quickPop';
    const claimId = 'barrier-claim';
    const roomId = 'barrier-room';
    const leaderTicket = {
      ...queueTicket('leader', 'barrier-leader', queueKey, now),
      deadlineAt: now + 1200,
      state: 'matched',
      activeUntil: 0,
      claimId,
      roomId,
      opponentUid: 'follower',
    };
    const followerTicket = {
      ...queueTicket('follower', 'barrier-follower', queueKey, now),
      deadlineAt: now + 1200,
      state: 'matched',
      activeUntil: 0,
      claimId,
      roomId,
      opponentUid: 'leader',
    };
    const claim = {
      claimId,
      queueKey,
      leaderUid: 'leader',
      firstUid: 'leader',
      firstTicketId: leaderTicket.ticketId,
      secondUid: 'follower',
      secondTicketId: followerTicket.ticketId,
      createdAt: now,
      resolution: {
        kind: 'human',
        roomId,
        resolvedAt: now,
        firstUid: 'leader',
        secondUid: 'follower',
      },
    };
    const room = {
      id: roomId,
      code: 'BAR234',
      hostUid: 'leader',
      visibility: 'private',
      status: 'starting',
      mode: 'traditional',
      matchFormat: 'quickPop',
      members: {
        leader: member('leader', 'Leader', 'red', now, true),
        follower: member('follower', 'Follower', 'green', now, true),
        cpu_yellow: member('cpu_yellow', 'CPU Rayo', 'yellow', now, true),
        cpu_blue: member('cpu_blue', 'CPU Pop', 'blue', now, true),
      },
      presence: {
        leader: presence('leader', now),
        follower: presence('follower', now),
        cpu_yellow: presence('cpu_yellow', now),
        cpu_blue: presence('cpu_blue', now),
      },
      revision: 0,
      createdAt: now,
      updatedAt: now,
      quickPopLaunch: {
        queueKey,
        claimId,
        firstUid: 'leader',
        firstTicketId: leaderTicket.ticketId,
        secondUid: 'follower',
        secondTicketId: followerTicket.ticketId,
        sharedDeadlineAt: leaderTicket.deadlineAt,
      },
      match: {
        ...matchDocument(now),
        roomId,
        matchId: roomId,
        hostUid: 'leader',
      },
    };
    const seedCandidate = async () => {
      await seed(`onlineV2/quickQueues/${queueKey}/leader`, leaderTicket);
      await seed(`onlineV2/quickQueues/${queueKey}/follower`, followerTicket);
      await seed(`onlineV2/quickClaims/${queueKey}/${claimId}`, claim);
      await seed(`onlineV2/rooms/${roomId}`, room);
    };
    await seedCandidate();

    const statusPath = `onlineV2/rooms/${roomId}/status`;
    await assertFails(set(pathRef('leader', statusPath), 'inGame'));
    await assertSucceeds(
      set(
        pathRef(
          'leader',
          `onlineV2/quickClaims/${queueKey}/${claimId}/launchReady/leader`,
        ),
        { uid: 'leader', ticketId: leaderTicket.ticketId, readyAt: Date.now() },
      ),
    );
    await assertFails(set(pathRef('leader', statusPath), 'inGame'));
    await assertSucceeds(
      set(
        pathRef(
          'follower',
          `onlineV2/quickClaims/${queueKey}/${claimId}/launchReady/follower`,
        ),
        {
          uid: 'follower',
          ticketId: followerTicket.ticketId,
          readyAt: Date.now(),
        },
      ),
    );
    await assertFails(set(pathRef('follower', statusPath), 'inGame'));
    await assertSucceeds(set(pathRef('leader', statusPath), 'inGame'));
    await assertFails(set(pathRef('outsider', statusPath), 'closed'));
    await assertSucceeds(set(pathRef('follower', statusPath), 'closed'));
    await assertFails(
      set(
        pathRef(
          'leader',
          `onlineV2/quickClaims/${queueKey}/${claimId}/launchSettled/leader`,
        ),
        {
          uid: 'leader',
          ticketId: leaderTicket.ticketId,
          settledAt: Date.now(),
        },
      ),
    );

    await environment.clearDatabase();
    await seedCandidate();
    await Promise.all([
      assertSucceeds(
        set(
          pathRef(
            'leader',
            `onlineV2/quickClaims/${queueKey}/${claimId}/launchReady/leader`,
          ),
          {
            uid: 'leader',
            ticketId: leaderTicket.ticketId,
            readyAt: now + 100,
          },
        ),
      ),
      assertSucceeds(
        set(
          pathRef(
            'follower',
            `onlineV2/quickClaims/${queueKey}/${claimId}/launchReady/follower`,
          ),
          {
            uid: 'follower',
            ticketId: followerTicket.ticketId,
            readyAt: now + 100,
          },
        ),
      ),
    ]);
    await assertSucceeds(set(pathRef('leader', statusPath), 'inGame'));
    await delay(Math.max(0, leaderTicket.deadlineAt - Date.now() + 25));
    await Promise.all([
      assertSucceeds(
        set(
          pathRef(
            'leader',
            `onlineV2/quickClaims/${queueKey}/${claimId}/launchSettled/leader`,
          ),
          {
            uid: 'leader',
            ticketId: leaderTicket.ticketId,
            settledAt: Date.now(),
          },
        ),
      ),
      assertSucceeds(
        set(
          pathRef(
            'follower',
            `onlineV2/quickClaims/${queueKey}/${claimId}/launchSettled/follower`,
          ),
          {
            uid: 'follower',
            ticketId: followerTicket.ticketId,
            settledAt: Date.now(),
          },
        ),
      ),
    ]);
    await assertFails(set(pathRef('follower', statusPath), 'closed'));
    await assertFails(
      set(
        pathRef(
          'follower',
          `onlineV2/quickClaims/${queueKey}/${claimId}/launchAborted/follower`,
        ),
        {
          uid: 'follower',
          ticketId: followerTicket.ticketId,
          abortedAt: Date.now(),
        },
      ),
    );

    // A write-once abort tombstone prevents delayed host room creation and
    // readiness after the local client has already left.
    await environment.clearDatabase();
    await seed(`onlineV2/quickQueues/${queueKey}/leader`, leaderTicket);
    await seed(`onlineV2/quickQueues/${queueKey}/follower`, followerTicket);
    await seed(`onlineV2/quickClaims/${queueKey}/${claimId}`, claim);
    const abortPath =
      `onlineV2/quickClaims/${queueKey}/${claimId}/launchAborted/follower`;
    await assertFails(
      set(pathRef('outsider', abortPath), {
        uid: 'follower',
        ticketId: followerTicket.ticketId,
        abortedAt: Date.now(),
      }),
    );
    await assertFails(
      set(pathRef('follower', abortPath), {
        uid: 'follower',
        ticketId: 'wrong-ticket',
        abortedAt: Date.now(),
      }),
    );
    await assertSucceeds(
      set(pathRef('follower', abortPath), {
        uid: 'follower',
        ticketId: followerTicket.ticketId,
        abortedAt: Date.now(),
      }),
    );
    await assertFails(set(pathRef('leader', `onlineV2/rooms/${roomId}`), room));
  });

  await t.test('known room codes and exact join paths work without exposing indexes or active rooms', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    await seed('onlineV2/roomCodes/ABC234', {
      roomId: 'room-1',
      hostUid: 'host',
      reservationId: 'reserve-1',
      state: 'active',
      reservedAt: now,
      expiresAt: 0,
    });

    const knownCode = await assertSucceeds(
      get(pathRef('outsider', 'onlineV2/roomCodes/ABC234')),
    );
    assert.equal(knownCode.val().roomId, 'room-1');
    await assertFails(get(pathRef('outsider', 'onlineV2/roomCodes')));

    const missingRoom = await assertSucceeds(
      get(pathRef('outsider', 'onlineV2/rooms/missing-room')),
    );
    assert.equal(missingRoom.exists(), false);
    await assertFails(get(pathRef('outsider', 'onlineV2/rooms')));

    const activeRoom = waitingRoom(now, { withGuest: true });
    await seed('onlineV2/rooms/room-1', activeRoom);
    const discoverableRoom = await assertSucceeds(
      get(pathRef('outsider', 'onlineV2/rooms/room-1')),
    );
    assert.equal(discoverableRoom.val().status, 'waiting');

    activeRoom.status = 'inGame';
    await seed('onlineV2/rooms/room-1', activeRoom);
    await assertFails(get(pathRef('outsider', 'onlineV2/rooms/room-1')));
    const memberRoom = await assertSucceeds(
      get(pathRef('guest', 'onlineV2/rooms/room-1')),
    );
    assert.equal(memberRoom.val().status, 'inGame');
  });

  await t.test('profile, code, public index, lobby snapshot, and leave paths stay functional', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const profilePath = 'onlineV2/profiles/host';
    await assertSucceeds(
      set(pathRef('host', profilePath), {
        uid: 'host',
        displayName: 'Host',
        createdAt: now,
        updatedAt: now,
      }),
    );
    await assertSucceeds(
      update(pathRef('host', profilePath), {
        displayName: 'Host Pop',
        updatedAt: now + 1,
      }),
    );

    const codePath = 'onlineV2/roomCodes/ABC234';
    await assertSucceeds(
      set(pathRef('host', codePath), {
        roomId: 'room-1',
        hostUid: 'host',
        reservationId: 'reserve-1',
        state: 'reserved',
        reservedAt: now,
        expiresAt: now + 30000,
      }),
    );
    await assertSucceeds(
      update(pathRef('host', codePath), { state: 'active', expiresAt: 0 }),
    );

    const room = waitingRoom(now);
    room.visibility = 'public';
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1'), room),
    );
    await seed(
      'onlineV2/rooms/room-1/members/guest',
      member('guest', 'Guest', 'green', now + 1),
    );
    await seed(
      'onlineV2/rooms/room-1/presence/guest',
      presence('guest', now + 1),
    );
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/publicRooms/room-1'), {
        roomId: 'room-1',
        code: 'ABC234',
        hostUid: 'host',
        hostDisplayName: 'Host Pop',
        mode: 'classic',
        matchFormat: 'quickTable',
        occupiedSeats: 2,
        updatedAt: now + 2,
      }),
    );
    await assertSucceeds(get(pathRef('guest', 'onlineV2/publicRooms')));

    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1/lobbyState'), {
        schemaVersion: 1,
        roomId: 'room-1',
        roomCode: 'ABC234',
        hostParticipantId: 'host',
        visibility: 'public',
        status: 'waiting',
        revision: 1,
        participants: [
          { participantId: 'host' },
          { participantId: 'guest' },
        ],
      }),
    );

    await assertSucceeds(
      set(pathRef('guest', 'onlineV2/rooms/room-1/presence/guest'), null),
    );
    await assertSucceeds(
      set(pathRef('guest', 'onlineV2/rooms/room-1/members/guest'), null),
    );
  });

  await t.test('commands are owned and immutable; only the host publishes match state', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now, { withGuest: true });
    room.status = 'inGame';
    room.matchFormat = 'quickTable';
    room.members.cpu_green = member('cpu_green', 'CPU', 'yellow', now + 2, true);
    await seed('onlineV2/rooms/room-1', room);
    await seed('onlineV2/rooms/room-1/match', matchDocument(now));

    const commandPath = 'onlineV2/rooms/room-1/commands/guest/action-1';
    const command = {
      kind: 'roll',
      matchId: 'match-1',
      participantId: 'guest',
      submittedById: 'guest',
      actionId: 'action-1',
      expectedRevision: 0,
      submittedAt: now + 1,
    };
    await assertSucceeds(set(pathRef('guest', commandPath), command));
    await assertFails(
      update(pathRef('guest', commandPath), { expectedRevision: 1 }),
    );

    await assertSucceeds(
      set(
        pathRef(
          'host',
          'onlineV2/rooms/room-1/commands/cpu_green/action-cpu',
        ),
        {
          kind: 'powerUp',
          matchId: 'match-1',
          participantId: 'cpu_green',
          submittedById: 'host',
          actionId: 'action-cpu',
          expectedRevision: 0,
          submittedAt: now + 2,
        },
      ),
    );
    await assertFails(
      set(
        pathRef(
          'guest',
          'onlineV2/rooms/room-1/commands/cpu_green/action-spoof',
        ),
        {
          kind: 'powerUp',
          matchId: 'match-1',
          participantId: 'cpu_green',
          submittedById: 'guest',
          actionId: 'action-spoof',
          expectedRevision: 0,
          submittedAt: now + 3,
        },
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/commands/guest/action-2'),
        {
          ...command,
          submittedById: 'host',
          actionId: 'action-2',
        },
      ),
    );

    await environment.withSecurityRulesDisabled(async (context) => {
      await set(ref(context.database(), 'onlineV2/rooms/room-1/match'), null);
    });
    await assertFails(
      set(pathRef('guest', 'onlineV2/rooms/room-1/match'), matchDocument(now)),
    );
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1/match'), matchDocument(now)),
    );
  });

  await t.test('an in-game host cannot delete the room or another player shared data', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now, { withGuest: true });
    room.status = 'inGame';
    room.matchFormat = 'quickTable';
    room.lobbyState = {
      schemaVersion: 1,
      roomId: 'room-1',
      roomCode: 'ABC234',
      hostParticipantId: 'host',
      visibility: 'private',
      status: 'inGame',
      revision: 3,
      participants: {
        0: { participantId: 'host' },
        1: { participantId: 'guest' },
      },
    };
    room.match = matchDocument(now);
    room.commands = {
      guest: {
        'guest-action': {
          kind: 'roll',
          matchId: 'match-1',
          participantId: 'guest',
          submittedById: 'guest',
          actionId: 'guest-action',
          expectedRevision: 0,
          submittedAt: now,
        },
      },
    };
    room.chat = {
      'guest-message': {
        messageId: 'guest-message',
        senderUid: 'guest',
        phraseId: 'hello',
        sentAt: now,
      },
    };
    await seed('onlineV2/rooms/room-1', room);

    await assertFails(set(pathRef('host', 'onlineV2/rooms/room-1'), null));
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1/members/guest'), null),
    );
    await assertFails(
      update(pathRef('host', 'onlineV2/rooms/room-1/members/guest'), {
        ready: false,
      }),
    );
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1/presence/guest'), null),
    );
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1/lobbyState'), null),
    );
    await assertFails(
      set(
        pathRef(
          'host',
          'onlineV2/rooms/room-1/commands/guest/guest-action',
        ),
        null,
      ),
    );
    await assertFails(
      set(
        pathRef('host', 'onlineV2/rooms/room-1/chat/guest-message'),
        null,
      ),
    );
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1/match'), null),
    );

    const withoutGuest = structuredClone(room);
    delete withoutGuest.members.guest;
    delete withoutGuest.presence.guest;
    withoutGuest.revision += 1;
    withoutGuest.updatedAt += 1;
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1'), withoutGuest),
    );

    const nextMatch = matchDocument(now);
    nextMatch.authorityRevision = 1;
    nextMatch.stateRevision = 1;
    nextMatch.checkpoint = { phase: 'playing', turn: 1 };
    nextMatch.authorityCheckpoint = { revision: 1 };
    nextMatch.updatedAt = now + 1;
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1/match'), nextMatch),
    );
  });

  await t.test('a waiting host closes safely but cannot erase the shared room root', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now, { withGuest: true });
    const closed = structuredClone(room);
    closed.status = 'closed';
    closed.revision += 1;
    closed.updatedAt += 1;

    await seed('onlineV2/rooms/room-1', room);
    await assertSucceeds(
      set(pathRef('host', 'onlineV2/rooms/room-1'), closed),
    );
    await assertFails(set(pathRef('host', 'onlineV2/rooms/room-1'), null));
    const snapshot = await assertSucceeds(
      get(pathRef('guest', 'onlineV2/rooms/room-1')),
    );
    assert.equal(snapshot.val().status, 'closed');
    assert.equal(snapshot.val().members.guest.uid, 'guest');
  });

  await t.test('Quick Messages are member-only, reviewed, timely, exact, and immutable', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now, { withGuest: true });
    room.status = 'inGame';
    await seed('onlineV2/rooms/room-1', room);

    const allowedPhrases = [
      'hello',
      'goodLuck',
      'goodGame',
      'greatMove',
      'wellPlayed',
      'wow',
      'yourTurn',
      'thanks',
      'almost',
      'oops',
      'rematch',
      'funGame',
    ];
    const message = (messageId, overrides = {}) => ({
      messageId,
      senderUid: 'guest',
      phraseId: 'hello',
      sentAt: Date.now(),
      ...overrides,
    });

    for (const [index, phraseId] of allowedPhrases.entries()) {
      const messageId = `allowed-${index}`;
      await assertSucceeds(
        set(
          pathRef('guest', `onlineV2/rooms/room-1/chat/${messageId}`),
          message(messageId, { phraseId }),
        ),
      );
    }

    await assertSucceeds(
      get(pathRef('guest', 'onlineV2/rooms/room-1/chat')),
    );
    await assertFails(
      get(pathRef('outsider', 'onlineV2/rooms/room-1/chat')),
    );
    await assertFails(
      get(
        ref(
          environment.unauthenticatedContext().database(),
          'onlineV2/rooms/room-1/chat',
        ),
      ),
    );

    await assertFails(
      set(
        pathRef('outsider', 'onlineV2/rooms/room-1/chat/outsider-message'),
        message('outsider-message', { senderUid: 'outsider' }),
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/spoofed-sender'),
        message('spoofed-sender', { senderUid: 'host' }),
      ),
    );
    await assertFails(
      set(
        pathRef('host', 'onlineV2/rooms/room-1/chat/host-spoofed-sender'),
        {
          ...message('host-spoofed-sender'),
          senderUid: 'guest',
        },
      ),
    );
    await assertFails(
      set(
        ref(
          environment.unauthenticatedContext().database(),
          'onlineV2/rooms/room-1/chat/anonymous-message',
        ),
        message('anonymous-message'),
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/unreviewed'),
        message('unreviewed', { phraseId: 'customText' }),
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/wrong-key'),
        message('different-message-id'),
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/extra-field'),
        message('extra-field', { text: 'unmoderated' }),
      ),
    );
    const missingField = message('missing-field');
    delete missingField.phraseId;
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/missing-field'),
        missingField,
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/too-old'),
        message('too-old', { sentAt: Date.now() - 11000 }),
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/chat/too-far-future'),
        message('too-far-future', { sentAt: Date.now() + 11000 }),
      ),
    );

    const immutablePath = 'onlineV2/rooms/room-1/chat/immutable';
    await assertSucceeds(
      set(pathRef('host', immutablePath), {
        messageId: 'immutable',
        senderUid: 'host',
        phraseId: 'hello',
        sentAt: Date.now(),
      }),
    );
    await assertFails(
      update(pathRef('host', immutablePath), { phraseId: 'wow' }),
    );
    await assertFails(set(pathRef('host', immutablePath), null));

    const waiting = waitingRoom(Date.now(), { withGuest: true });
    await seed('onlineV2/rooms/waiting-room', {
      ...waiting,
      id: 'waiting-room',
    });
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/waiting-room/chat/not-in-game'),
        message('not-in-game'),
      ),
    );
  });

  await t.test('presence and opening-roll requests follow their real wire shapes', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const room = waitingRoom(now, { withGuest: true });
    room.status = 'openingRoll';
    room.lobbyState = {
      schemaVersion: 1,
      roomId: 'room-1',
      roomCode: 'ABC234',
      hostParticipantId: 'host',
      visibility: 'private',
      status: 'openingRoll',
      revision: 2,
      participants: {
        0: { participantId: 'host' },
        1: { participantId: 'guest' },
      },
      openingRoll: {
        round: 1,
        currentRolls: {},
      },
    };
    await seed('onlineV2/rooms/room-1', room);

    await assertSucceeds(
      set(pathRef('guest', 'onlineV2/rooms/room-1/presence/guest'), {
        ...presence('guest', now + 1),
        state: 'disconnected',
      }),
    );
    await assertFails(
      set(pathRef('host', 'onlineV2/rooms/room-1/presence/guest'), {
        ...presence('guest', now + 2),
        state: 'connected',
      }),
    );
    await assertSucceeds(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/openingRollRequests/guest'),
        { uid: 'guest', round: 1, requestedAt: now + 2 },
      ),
    );
    await assertFails(
      set(
        pathRef('guest', 'onlineV2/rooms/room-1/openingRollRequests/guest'),
        { uid: 'guest', round: 2, requestedAt: now + 3 },
      ),
    );
  });
});

test.after(async () => {
  await environment.cleanup();
});
