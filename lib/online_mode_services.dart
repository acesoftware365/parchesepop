import 'game_engine.dart';
import 'online_lobby.dart';
import 'online_quick_pop.dart';
import 'online_room_ui.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

/// The two online experiences intentionally share authentication, Firebase
/// storage and the live game synchronizer, but they do not share matchmaking
/// commands. Keeping the protocol boundary in one place prevents a Quick Pop
/// ticket from being sent to the Quick Table room flow (or the reverse).
enum OnlineModeProtocol { quickPop, quickTable }

final class OnlineModeProtocolException implements Exception {
  const OnlineModeProtocolException(this.protocol, this.message);

  final OnlineModeProtocol protocol;
  final String message;

  @override
  String toString() =>
      'OnlineModeProtocolException(${protocol.name}): $message';
}

/// Matchmaking facade for Quick Pop. The UI only receives this facade, so the
/// Quick Pop queue/group/settlement protocol cannot accidentally use a room
/// lobby operation intended for Quick Table.
final class OnlineQuickPopService {
  const OnlineQuickPopService(this.transport);

  static const MatchFormat matchFormat = MatchFormat.quickPop;
  // Keep the queue namespace separate from tickets created by the previous
  // Quick Pop group protocol. Those records can remain in Firebase for their
  // short 30-second lifetime after an emulator is closed, and must never be
  // allowed to become the leader of a new search.
  static const String queueGeneration = 'v2';
  // Keep this literal so it remains usable from const contexts and so the
  // namespace is unambiguous in diagnostics/rule paths.
  static const String queueMatchFormat = 'quickPop_v2';

  final OnlineTransportClient transport;

  Future<QuickPopQueueTicket> enqueue({
    required GameMode mode,
    Duration searchWindow = quickPopSearchWindow,
  }) => transport.enqueueQuickPop(
    mode: mode.name,
    matchFormat: queueMatchFormat,
    searchWindow: searchWindow,
  );

  Future<QuickPopResolution?> resolve(
    QuickPopQueueTicket ticket, {
    bool waitForGroupWindow = true,
  }) {
    _assertTicket(ticket);
    return transport.resolveQuickPop(
      ticket,
      waitForGroupWindow: waitForGroupWindow,
    );
  }

  Future<OnlineQuickPopPreparedMatch> prepare({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    GameMode mode = GameMode.traditional,
    Duration hostTimeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 150),
  }) {
    _assertTicket(ticket);
    _assertResolution(resolution);
    return OnlineQuickPopBootstrap.prepare(
      transport: transport,
      ticket: ticket,
      resolution: resolution,
      mode: mode,
      hostTimeout: hostTimeout,
      pollInterval: pollInterval,
    );
  }

  Future<bool> synchronize({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) {
    _assertTicket(ticket);
    _assertResolution(resolution);
    return transport.synchronizeQuickPopLaunch(
      ticket: ticket,
      resolution: resolution,
    );
  }

  Future<QuickPopLaunchSettlement> settle({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
    Duration peerWait = quickPopSettlementPeerWait,
    Duration operationTimeout = quickPopSettlementOperationTimeout,
  }) {
    _assertTicket(ticket);
    _assertResolution(resolution);
    return transport.settleQuickPopLaunch(
      ticket: ticket,
      resolution: resolution,
      peerWait: peerWait,
      operationTimeout: operationTimeout,
    );
  }

  Future<void> cancel(QuickPopQueueTicket ticket) {
    _assertTicket(ticket);
    return transport.cancelQuickPop(ticket);
  }

  Future<void> abandon({
    required QuickPopQueueTicket ticket,
    required QuickPopResolution resolution,
  }) {
    _assertTicket(ticket);
    _assertResolution(resolution);
    return transport.abandonQuickPopLaunch(
      ticket: ticket,
      resolution: resolution,
    );
  }

  void _assertTicket(QuickPopQueueTicket ticket) {
    if (!ticket.queueKey.endsWith('_$queueMatchFormat')) {
      throw const OnlineModeProtocolException(
        OnlineModeProtocol.quickPop,
        'The ticket belongs to a different online protocol.',
      );
    }
  }

  void _assertResolution(QuickPopResolution resolution) {
    if (resolution.kind != QuickPopResolutionKind.human ||
        resolution.queueKey != null &&
            !resolution.queueKey!.endsWith('_$queueMatchFormat')) {
      throw const OnlineModeProtocolException(
        OnlineModeProtocol.quickPop,
        'The resolution is not a verified Quick Pop result.',
      );
    }
  }
}

/// Room facade for Quick Table. Room discovery and admission remain in the
/// existing realtime controller, but every room it creates or attaches is
/// checked at this boundary before lobby listeners are started.
final class OnlineQuickTableService {
  const OnlineQuickTableService(this.transport);

  static const String matchFormat = 'quickTable';

  final OnlineTransportClient transport;

  Future<OnlineRoomRecord> createRoom({
    required OnlineRoomGameMode mode,
    required RoomVisibility visibility,
    String? roomName,
  }) async {
    final room = await transport.createRoom(
      visibility: visibility,
      mode: mode.name,
      matchFormat: matchFormat,
      roomName: roomName,
    );
    assertRoom(room);
    return room;
  }

  void assertRoom(OnlineRoomRecord room) {
    if (room.matchFormat != matchFormat) {
      throw const OnlineModeProtocolException(
        OnlineModeProtocol.quickTable,
        'The room belongs to a different online protocol.',
      );
    }
  }

  Future<OnlineRoomRecord?> readRoom(String roomId) async {
    final room = await transport.readRoom(roomId);
    if (room != null) assertRoom(room);
    return room;
  }
}
