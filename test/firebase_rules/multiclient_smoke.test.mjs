import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, onValue, ref, set, update } from 'firebase/database';

const projectId = 'parchese-pop';
const emulatorAddress =
  process.env.FIREBASE_DATABASE_EMULATOR_HOST ?? '127.0.0.1:9000';
const separator = emulatorAddress.lastIndexOf(':');
const host = emulatorAddress.slice(0, separator);
const port = Number(emulatorAddress.slice(separator + 1));
const rules = await readFile(
  new URL('../../database.rules.json', import.meta.url),
  'utf8',
);

const environment = await initializeTestEnvironment({
  projectId,
  database: { host, port, rules },
});

const dbFor = (uid) => environment.authenticatedContext(uid).database();
const pathRef = (uid, path) => ref(dbFor(uid), path);

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function waitForValue(reference, predicate, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    let unsubscribe = () => {};
    const timer = setTimeout(() => {
      unsubscribe();
      reject(new Error(`Realtime observation timed out after ${timeoutMs}ms.`));
    }, timeoutMs);
    unsubscribe = onValue(
      reference,
      (snapshot) => {
        const value = snapshot.val();
        if (!predicate(value)) return;
        clearTimeout(timer);
        unsubscribe();
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        unsubscribe();
        reject(error);
      },
    );
  });
}

const queueTicket = (uid, displayName, queueKey, joinedAt) => ({
  ticketId: `ticket_${uid}`,
  uid,
  displayName,
  queueKey,
  joinedAt,
  deadlineAt: joinedAt + 5000,
  state: 'waiting',
});

const member = (uid, displayName, seat, joinedAt, ready = false) => ({
  uid,
  displayName,
  seat,
  ready,
  joinedAt,
});

const presence = (uid, changedAt, state = 'connected') => ({
  uid,
  state,
  changedAt,
  connectionId: `smoke_connection_${uid}`,
});

async function clearAndVerifyIsolation() {
  await environment.clearDatabase();
  await environment.withSecurityRulesDisabled(async (context) => {
    const snapshot = await get(ref(context.database(), 'onlineV2'));
    assert.equal(snapshot.exists(), false, 'emulator test data must be empty');
  });
}

test('Firebase multi-client online smoke', async (t) => {
  await t.test('Quick Pop matches two realtime clients before five seconds', async () => {
    await environment.clearDatabase();
    const startedAt = Date.now();
    const queueKey = 'traditional_quickPop';
    const firstUid = 'smoke_a';
    const secondUid = 'smoke_b';
    const claimId = 'smoke_claim_human';
    const roomId = 'smoke_quick_human_room';
    const first = queueTicket(firstUid, 'Ana', queueKey, startedAt);
    const second = queueTicket(secondUid, 'Beto', queueKey, startedAt + 1);

    const resolutionPath =
      `onlineV2/quickClaims/${queueKey}/${claimId}/resolution`;
    const secondObservedResolution = waitForValue(
      pathRef(secondUid, resolutionPath),
      (value) => value?.kind === 'human',
    );

    await Promise.all([
      assertSucceeds(
        set(pathRef(firstUid, `onlineV2/quickQueues/${queueKey}/${firstUid}`), first),
      ),
      assertSucceeds(
        set(pathRef(secondUid, `onlineV2/quickQueues/${queueKey}/${secondUid}`), second),
      ),
    ]);
    await Promise.all([
      assertSucceeds(
        update(pathRef(firstUid, `onlineV2/quickQueues/${queueKey}/${firstUid}`), {
          claimId,
        }),
      ),
      assertSucceeds(
        update(pathRef(secondUid, `onlineV2/quickQueues/${queueKey}/${secondUid}`), {
          claimId,
        }),
      ),
    ]);

    await assertSucceeds(
      set(pathRef(firstUid, `onlineV2/quickClaims/${queueKey}/${claimId}`), {
        claimId,
        queueKey,
        leaderUid: firstUid,
        firstUid,
        firstTicketId: first.ticketId,
        secondUid,
        secondTicketId: second.ticketId,
        createdAt: Date.now(),
      }),
    );
    await Promise.all([
      assertSucceeds(
        set(
          pathRef(
            firstUid,
            `onlineV2/quickClaims/${queueKey}/${claimId}/acceptances/${firstUid}`,
          ),
          {
            uid: firstUid,
            ticketId: first.ticketId,
            opponentUid: secondUid,
            opponentTicketId: second.ticketId,
            acceptedAt: Date.now(),
          },
        ),
      ),
      assertSucceeds(
        set(
          pathRef(
            secondUid,
            `onlineV2/quickClaims/${queueKey}/${claimId}/acceptances/${secondUid}`,
          ),
          {
            uid: secondUid,
            ticketId: second.ticketId,
            opponentUid: firstUid,
            opponentTicketId: first.ticketId,
            acceptedAt: Date.now(),
          },
        ),
      ),
    ]);

    const resolution = {
      kind: 'human',
      roomId,
      resolvedAt: Date.now(),
      firstUid,
      secondUid,
    };
    // The follower may be the last acceptance to arrive, so it must be able
    // to publish the deterministic resolution without waiting for another
    // leader polling cycle.
    await assertSucceeds(set(pathRef(secondUid, resolutionPath), resolution));
    assert.deepEqual(await secondObservedResolution, resolution);
    await Promise.all([
      assertSucceeds(
        update(pathRef(firstUid, `onlineV2/quickQueues/${queueKey}/${firstUid}`), {
          state: 'matched',
          roomId,
          opponentUid: secondUid,
        }),
      ),
      assertSucceeds(
        update(pathRef(secondUid, `onlineV2/quickQueues/${queueKey}/${secondUid}`), {
          state: 'matched',
          roomId,
          opponentUid: firstUid,
        }),
      ),
    ]);

    const room = {
      id: roomId,
      code: 'QCK234',
      hostUid: firstUid,
      visibility: 'private',
      status: 'inGame',
      mode: 'traditional',
      matchFormat: 'quickPop',
      members: {
        [firstUid]: member(firstUid, 'Ana', 'red', startedAt, true),
        [secondUid]: member(secondUid, 'Beto', 'green', startedAt + 1, true),
        cpu_yellow: member('cpu_yellow', 'CPU Rayo', 'yellow', startedAt + 2, true),
        cpu_blue: member('cpu_blue', 'CPU Pop', 'blue', startedAt + 3, true),
      },
      presence: {
        [firstUid]: presence(firstUid, startedAt),
        [secondUid]: presence(secondUid, startedAt + 1),
        cpu_yellow: presence('cpu_yellow', startedAt + 2),
        cpu_blue: presence('cpu_blue', startedAt + 3),
      },
      revision: 0,
      createdAt: startedAt,
      updatedAt: Date.now(),
    };
    await assertSucceeds(
      set(pathRef(firstUid, `onlineV2/rooms/${roomId}`), room),
    );
    const secondRoom = await assertSucceeds(
      get(pathRef(secondUid, `onlineV2/rooms/${roomId}`)),
    );
    assert.equal(secondRoom.val().members[secondUid].seat, 'green');
    assert.ok(
      Date.now() - startedAt < 5000,
      'human Quick Pop must resolve before its five-second deadline',
    );
    await clearAndVerifyIsolation();
  });

  await t.test('Quick Pop solo falls back to CPU only after five seconds', async () => {
    await environment.clearDatabase();
    const uid = 'smoke_solo';
    const queueKey = 'traditional_quickPop';
    const joinedAt = Date.now();
    const ticket = queueTicket(uid, 'Solo', queueKey, joinedAt);
    const ticketPath = `onlineV2/quickQueues/${queueKey}/${uid}`;
    await assertSucceeds(set(pathRef(uid, ticketPath), ticket));

    await assertFails(
      update(pathRef(uid, ticketPath), {
        state: 'cpuFallback',
        roomId: 'smoke_cpu_room',
      }),
    );

    const observedFallback = waitForValue(
      pathRef(uid, ticketPath),
      (value) => value?.state === 'cpuFallback',
      7000,
    );
    await delay(Math.max(0, ticket.deadlineAt - Date.now() + 100));
    await assertSucceeds(
      update(pathRef(uid, ticketPath), {
        state: 'cpuFallback',
        roomId: 'smoke_cpu_room',
      }),
    );
    const fallback = await observedFallback;
    assert.equal(fallback.roomId, 'smoke_cpu_room');
    assert.ok(Date.now() - joinedAt >= 5000);
    await clearAndVerifyIsolation();
  });

  await t.test('Quick Table connects four clients, readies, rolls, orders, and closes', async () => {
    await environment.clearDatabase();
    const now = Date.now();
    const roomId = 'smoke-table';
    const code = 'SMK234';
    const uids = ['table_host', 'table_green', 'table_yellow', 'table_blue'];
    const seats = ['red', 'green', 'yellow', 'blue'];
    const names = ['Host', 'Green', 'Yellow', 'Blue'];
    const roomPath = `onlineV2/rooms/${roomId}`;

    const initialRoom = {
      id: roomId,
      code,
      hostUid: uids[0],
      visibility: 'private',
      status: 'waiting',
      mode: 'chaos',
      matchFormat: 'quickTable',
      members: {
        [uids[0]]: member(uids[0], names[0], seats[0], now),
      },
      presence: {
        [uids[0]]: presence(uids[0], now),
      },
      revision: 0,
      createdAt: now,
      updatedAt: now,
    };
    await assertSucceeds(set(pathRef(uids[0], roomPath), initialRoom));

    for (let index = 1; index < uids.length; index += 1) {
      await assertSucceeds(
        set(pathRef(uids[index], `onlineV2/joinRequests/${roomId}/${uids[index]}`), {
          roomId,
          roomCode: code,
          uid: uids[index],
          displayName: names[index],
          requestedAt: now + index,
        }),
      );
    }

    const admittedRoom = structuredClone(initialRoom);
    for (let index = 1; index < uids.length; index += 1) {
      admittedRoom.members[uids[index]] = member(
        uids[index],
        names[index],
        seats[index],
        now + index,
      );
    }
    admittedRoom.revision = 3;
    admittedRoom.updatedAt = now + 3;
    await assertSucceeds(set(pathRef(uids[0], roomPath), admittedRoom));

    for (let index = 1; index < uids.length; index += 1) {
      await assertSucceeds(
        set(
          pathRef(uids[index], `${roomPath}/presence/${uids[index]}`),
          presence(uids[index], now + index),
        ),
      );
      await assertSucceeds(
        set(pathRef(uids[0], `onlineV2/joinRequests/${roomId}/${uids[index]}`), null),
      );
    }
    await Promise.all(
      uids.map((uid) =>
        assertSucceeds(update(pathRef(uid, `${roomPath}/members/${uid}`), { ready: true })),
      ),
    );
    const readyRoom = await assertSucceeds(get(pathRef(uids[0], roomPath)));
    assert.equal(
      Object.values(readyRoom.val().members).every((value) => value.ready),
      true,
    );

    const participants = uids.map((uid, index) => ({
      participantId: uid,
      displayName: names[index],
      seat: seats[index],
      ready: true,
      presence: 'connected',
    }));
    const opening = {
      round: 1,
      seatByParticipantId: Object.fromEntries(
        uids.map((uid, index) => [uid, seats[index]]),
      ),
      eligibleParticipantIds: uids,
      currentRolls: {},
      history: [],
      clockwiseParticipantIds: [],
    };
    const lobbyPath = `${roomPath}/lobbyState`;
    await assertSucceeds(
      set(pathRef(uids[0], lobbyPath), {
        schemaVersion: 1,
        roomId,
        roomCode: code,
        hostParticipantId: uids[0],
        visibility: 'private',
        status: 'openingRoll',
        revision: 4,
        participants,
        openingRoll: opening,
      }),
    );
    await assertSucceeds(
      update(pathRef(uids[0], roomPath), {
        status: 'openingRoll',
        revision: 4,
        updatedAt: Date.now(),
      }),
    );

    const startingSnapshots = uids.map((uid) =>
      waitForValue(pathRef(uid, lobbyPath), (value) => value?.status === 'starting'),
    );
    for (const uid of uids) {
      await assertSucceeds(
        set(pathRef(uid, `${roomPath}/openingRollRequests/${uid}`), {
          uid,
          round: 1,
          requestedAt: Date.now(),
        }),
      );
    }
    const requests = await assertSucceeds(
      get(pathRef(uids[0], `${roomPath}/openingRollRequests`)),
    );
    assert.equal(Object.keys(requests.val()).length, 4);

    const rolls = {
      [uids[0]]: 2,
      [uids[1]]: 6,
      [uids[2]]: 4,
      [uids[3]]: 1,
    };
    const clockwiseParticipantIds = [uids[1], uids[2], uids[3], uids[0]];
    const completedOpening = {
      ...opening,
      currentRolls: rolls,
      history: [
        {
          round: 1,
          eligibleParticipantIds: uids,
          rolls,
        },
      ],
      winnerParticipantId: uids[1],
      clockwiseParticipantIds,
    };
    await assertSucceeds(
      set(pathRef(uids[0], lobbyPath), {
        schemaVersion: 1,
        roomId,
        roomCode: code,
        hostParticipantId: uids[0],
        visibility: 'private',
        status: 'starting',
        revision: 5,
        participants,
        openingRoll: completedOpening,
      }),
    );
    await assertSucceeds(
      update(pathRef(uids[0], roomPath), {
        status: 'starting',
        revision: 5,
        updatedAt: Date.now(),
      }),
    );
    for (const snapshot of await Promise.all(startingSnapshots)) {
      assert.deepEqual(
        snapshot.openingRoll.clockwiseParticipantIds,
        clockwiseParticipantIds,
      );
    }

    for (const uid of uids) {
      await assertSucceeds(
        set(pathRef(uids[0], `${roomPath}/openingRollRequests/${uid}`), null),
      );
    }
    await assertSucceeds(
      set(pathRef(uids[0], lobbyPath), {
        schemaVersion: 1,
        roomId,
        roomCode: code,
        hostParticipantId: uids[0],
        visibility: 'private',
        status: 'closed',
        revision: 6,
        participants,
        openingRoll: completedOpening,
      }),
    );
    await assertSucceeds(
      update(pathRef(uids[0], roomPath), {
        status: 'closed',
        revision: 6,
        updatedAt: Date.now(),
      }),
    );
    await assertFails(set(pathRef(uids[0], roomPath), null));
    const closedRoom = await assertSucceeds(
      get(pathRef(uids[1], roomPath)),
    );
    assert.equal(closedRoom.val().status, 'closed');
    assert.equal(Object.keys(closedRoom.val().members).length, 4);
    await clearAndVerifyIsolation();
  });
});

test.after(async () => {
  await environment.cleanup();
});
