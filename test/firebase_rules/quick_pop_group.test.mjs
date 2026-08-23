import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, ref, set } from 'firebase/database';

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
const now = Date.now();
const queueKey = 'traditional_quickPop';
const groupId = 'group_test_4';
const groupPath = `onlineV2/quickPopGroups/${queueKey}/${groupId}`;

test.after(async () => {
  await environment.cleanup();
});

const ticket = (uid, offset) => ({
  ticketId: `ticket_${uid}`,
  uid,
  displayName: uid.toUpperCase(),
  queueKey,
  joinedAt: now + offset,
  deadlineAt: now + offset + 30000,
  activeUntil: now + offset + 30000,
  state: 'waiting',
});

test('Quick Pop group rules admit up to four human tickets', async () => {
  await environment.clearDatabase();
  const uids = ['a', 'b', 'c', 'd'];
  const tickets = Object.fromEntries(uids.map((uid, index) => [uid, ticket(uid, index)]));
  await Promise.all(
    uids.map((uid) =>
      assertSucceeds(
        set(pathRef(uid, `onlineV2/quickQueues/${queueKey}/${uid}`), tickets[uid]),
      ),
    ),
  );

  const members = Object.fromEntries(
    uids.map((uid) => [uid, {
      uid,
      ticketId: tickets[uid].ticketId,
      displayName: tickets[uid].displayName,
      joinedAt: tickets[uid].joinedAt,
      deadlineAt: tickets[uid].deadlineAt,
    }]),
  );
  await assertSucceeds(
    set(pathRef('a', groupPath), {
      groupId,
      queueKey,
      leaderUid: 'a',
      createdAt: now,
      members: { a: members.a },
    }),
  );
  await Promise.all(
    uids.slice(1).map((uid) =>
      assertSucceeds(set(pathRef(uid, `${groupPath}/members/${uid}`), members[uid])),
    ),
  );
  await assertSucceeds(
    set(pathRef('a', `${groupPath}/resolution`), {
      kind: 'human',
      roomId: 'quick_group_room',
      resolvedAt: now + 100,
      memberUids: uids,
    }),
  );
  for (const uid of uids) {
    const snapshot = await assertSucceeds(get(pathRef(uid, groupPath)));
    assert.equal(snapshot.val().resolution.memberUids.length, 4);
  }
  await assertFails(get(pathRef('outsider', groupPath)));
});

test('Quick Pop group members can publish launch lifecycle markers', async () => {
  await environment.clearDatabase();
  const uids = ['a', 'b'];
  const tickets = Object.fromEntries(
    uids.map((uid, index) => [uid, ticket(uid, index)]),
  );
  const members = Object.fromEntries(
    uids.map((uid) => [uid, {
      uid,
      ticketId: tickets[uid].ticketId,
      displayName: tickets[uid].displayName,
      joinedAt: tickets[uid].joinedAt,
      deadlineAt: tickets[uid].deadlineAt,
    }]),
  );

  await environment.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), groupPath), {
      groupId,
      queueKey,
      leaderUid: 'a',
      createdAt: now,
      members,
      resolution: {
        kind: 'human',
        roomId: 'quick_group_room',
        resolvedAt: now + 100,
        memberUids: uids,
      },
    });
    await set(
      ref(context.database(), 'onlineV2/rooms/quick_group_room/status'),
      'starting',
    );
  });

  for (const uid of uids) {
    await assertSucceeds(
      set(pathRef(uid, `${groupPath}/launchReady/${uid}`), {
        uid,
        ticketId: tickets[uid].ticketId,
        readyAt: now + 200,
      }),
    );
  }
  await assertFails(
    set(pathRef('outsider', `${groupPath}/launchReady/outsider`), {
      uid: 'outsider',
      ticketId: 'ticket_outsider',
      readyAt: now + 200,
    }),
  );

  await environment.withSecurityRulesDisabled(async (context) => {
    await set(
      ref(context.database(), 'onlineV2/rooms/quick_group_room/status'),
      'inGame',
    );
  });
  for (const uid of uids) {
    await assertSucceeds(
      set(pathRef(uid, `${groupPath}/launchSettled/${uid}`), {
        uid,
        ticketId: tickets[uid].ticketId,
        settledAt: now + 300,
      }),
    );
  }
  await assertSucceeds(
    set(pathRef('a', `${groupPath}/launchAborted/a`), {
      uid: 'a',
      ticketId: tickets.a.ticketId,
      abortedAt: now + 400,
    }),
  );
});
