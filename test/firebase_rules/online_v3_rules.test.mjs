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
const emulatorAddress = process.env.FIREBASE_DATABASE_EMULATOR_HOST ?? '127.0.0.1:9000';
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

async function seed(path, value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await set(ref(context.database(), path), value);
  });
}

test('Online V3 rules make the server the sole board authority', async (t) => {
  const roomId = 'qp3_0123456789abcdef01234567';
  const matchPath = `onlineV3/matches/${roomId}`;

  await t.test('only participants can read their canonical match and no client can write it', async () => {
    await environment.clearDatabase();
    await seed(matchPath, {
      participantUids: { player: true },
      roomId,
      revision: 3,
    });

    const snapshot = await assertSucceeds(get(pathRef('player', matchPath)));
    assert.equal(snapshot.val().revision, 3);
    await assertFails(get(pathRef('outsider', matchPath)));
    await assertFails(set(pathRef('player', matchPath), { forged: true }));
  });

  await t.test('a player may signal only their own strictly shaped presence', async () => {
    await environment.clearDatabase();
    await seed(matchPath, { participantUids: { player: true } });
    const ownPresence = `onlineV3/presence/${roomId}/player`;

    await assertSucceeds(set(pathRef('player', ownPresence), {
      state: 'connected',
      epoch: 'presence_0123456789abcdef',
      changedAt: Date.now(),
    }));
    await assertFails(set(pathRef('outsider', ownPresence), {
      state: 'connected',
      epoch: 'presence_0123456789abcdef',
      changedAt: Date.now(),
    }));
    await assertFails(set(pathRef('player', ownPresence), {
      state: 'connected',
      epoch: 'short',
      changedAt: Date.now(),
    }));
  });

  await t.test('a ticket is readable only by its owner and is never client-writable', async () => {
    await environment.clearDatabase();
    const ticketPath = 'onlineV3/quickPop/queues/traditional/tickets/player';
    await seed(ticketPath, { ticketId: 'ticket-1', state: 'waiting' });

    await assertSucceeds(get(pathRef('player', ticketPath)));
    await assertFails(get(pathRef('outsider', ticketPath)));
    await assertFails(set(pathRef('player', ticketPath), { state: 'assigned' }));
  });

  await t.test('Quick Table rooms are readable only after server-side admission', async () => {
    await environment.clearDatabase();
    const tablePath = 'onlineV3/quickTable/rooms/qt3_0123456789abcdef01234567';
    await seed(tablePath, { participantUids: { player: true }, revision: 1 });

    await assertSucceeds(get(pathRef('player', tablePath)));
    await assertFails(get(pathRef('outsider', tablePath)));
    await assertFails(set(pathRef('player', tablePath), { participantUids: { player: true }, revision: 2 }));
  });
});

test.after(async () => {
  await environment.cleanup();
});
