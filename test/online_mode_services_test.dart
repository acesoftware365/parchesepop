import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:parchesepop/online_mode_services.dart';
import 'package:parchesepop/online_room_ui.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

import 'support/in_memory_online_realtime_store.dart';

void main() {
  test('Quick Pop facade owns only Quick Pop queue keys', () async {
    final store = InMemoryOnlineRealtimeStore(initialNowMs: 1000);
    final transport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(uid: 'pop-user', displayName: 'Pop'),
    );
    final service = OnlineQuickPopService(transport);

    final ticket = await service.enqueue(mode: GameMode.traditional);

    expect(ticket.queueKey, 'traditional_quickPop_v2');
    expect(
      await store.read(
        '$onlineTransportRoot/quickQueues/traditional_quickPop_v2/pop-user',
      ),
      isNotNull,
    );
    expect(
      () => service.cancel(
        QuickPopQueueTicket(
          ticketId: 'table-ticket',
          uid: 'pop-user',
          displayName: 'Pop',
          queueKey: 'classic_quickTable',
          joinedAtMs: 1000,
          deadlineAtMs: 16000,
        ),
      ),
      throwsA(isA<OnlineModeProtocolException>()),
    );
  });

  test(
    'Quick Pop v2 matches two clients without reading the legacy queue',
    () async {
      final store = InMemoryOnlineRealtimeStore(initialNowMs: 10_000);
      // A still-active ticket from the previous shared namespace must not be
      // able to become a leader or change the cohort for this search.
      await store.set(
        '$onlineTransportRoot/quickQueues/traditional_quickPop/legacy-user',
        <String, Object?>{
          'ticketId': 'legacy-ticket',
          'uid': 'legacy-user',
          'displayName': 'LEGACY',
          'queueKey': 'traditional_quickPop',
          'joinedAt': 10_000,
          'deadlineAt': 25_000,
          'activeUntil': 25_000,
          'state': 'waiting',
        },
      );
      final first = OnlineQuickPopService(
        OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: 'first-v2',
            displayName: 'FIRST',
          ),
        ),
      );
      final second = OnlineQuickPopService(
        OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: 'second-v2',
            displayName: 'SECOND',
          ),
        ),
      );

      final firstTicket = await first.enqueue(mode: GameMode.traditional);
      final secondTicket = await second.enqueue(mode: GameMode.traditional);

      QuickPopResolution? firstResolution;
      QuickPopResolution? secondResolution;
      for (var round = 0; round < 4; round++) {
        firstResolution ??= await first.resolve(firstTicket);
        secondResolution ??= await second.resolve(secondTicket);
      }
      // Two humans remain in the shared group until the 30-second window
      // closes; then the group is committed without adding a CPU player.
      store.setNowMs(firstTicket.deadlineAtMs);
      firstResolution = await first.resolve(firstTicket);
      secondResolution = await second.resolve(secondTicket);

      expect(firstTicket.queueKey, 'traditional_quickPop_v2');
      expect(secondTicket.queueKey, 'traditional_quickPop_v2');
      expect(firstResolution?.kind, QuickPopResolutionKind.human);
      expect(secondResolution?.kind, QuickPopResolutionKind.human);
      expect(firstResolution?.participantUids.toSet(), {
        'first-v2',
        'second-v2',
      });
      expect(secondResolution?.roomId, firstResolution?.roomId);
    },
  );

  test(
    'Quick Table facade rejects a Quick Pop room before listeners attach',
    () {
      final transport = OnlineTransportClient(
        store: InMemoryOnlineRealtimeStore(),
        identity: OnlineTransportIdentity(
          uid: 'table-user',
          displayName: 'Table',
        ),
      );
      final service = OnlineQuickTableService(transport);

      expect(
        () => service.assertRoom(_room(matchFormat: 'quickPop')),
        throwsA(isA<OnlineModeProtocolException>()),
      );
      expect(
        () => service.assertRoom(_room(matchFormat: 'quickTable')),
        returnsNormally,
      );
    },
  );
}

OnlineRoomRecord _room({required String matchFormat}) => OnlineRoomRecord(
  id: 'room-1',
  code: RoomCode.parse('ABC234'),
  hostUid: 'host',
  visibility: RoomVisibility.private,
  status: RoomStatus.waiting,
  mode: OnlineRoomGameMode.classic.name,
  matchFormat: matchFormat,
  members: const <String, OnlineRoomMemberRecord>{},
  presence: const <String, OnlinePresenceRecord>{},
  revision: 0,
  createdAtMs: 0,
  updatedAtMs: 0,
);
