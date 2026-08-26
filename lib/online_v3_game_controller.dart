import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_engine.dart';
import 'online_v3_game_adapter.dart';
import 'online_v3_models.dart';
import 'online_v3_quick_pop.dart';

/// Bridges the server-owned V3 match into the existing game board.
///
/// The board is a replica only: this controller never rolls dice or advances
/// a token locally.  It sends a command to Cloud Functions and applies the
/// next canonical RTDB revision when it arrives.
final class OnlineV3QuickPopGameController extends ChangeNotifier {
  OnlineV3QuickPopGameController._({
    required this.client,
    required this.roomId,
    required this.playerName,
  });

  final OnlineV3QuickPopClient client;
  final String roomId;
  final String playerName;
  StreamSubscription<OnlineV3MatchState?>? _subscription;
  final Completer<void> _initialState = Completer<void>();

  OnlineV3MatchState? _state;
  GameEngine? _engine;
  Object? _lastError;
  bool _submitting = false;
  bool _disposed = false;

  OnlineV3MatchState? get state => _state;
  GameEngine get engine {
    final value = _engine;
    if (value == null) throw StateError('V3 match has not supplied a board.');
    return value;
  }

  int get revision => _state?.revision ?? -1;
  bool get submitting => _submitting;
  Object? get lastError => _lastError;
  bool get isLocalHumanTurn => _state?.isHumanTurn(client.uid) ?? false;

  static Future<OnlineV3QuickPopGameController> open({
    required OnlineV3QuickPopClient client,
    required String roomId,
    required String playerName,
  }) async {
    final controller = OnlineV3QuickPopGameController._(
      client: client,
      roomId: roomId,
      playerName: playerName,
    );
    await controller.start();
    return controller;
  }

  Future<void> start() async {
    if (_disposed) throw StateError('V3 controller is disposed.');
    await client.beginPresence(roomId);
    _subscription ??= client
        .watchMatch(roomId)
        .listen(
          _applyState,
          onError: (Object error, StackTrace stackTrace) {
            _lastError = error;
            if (!_initialState.isCompleted) {
              _initialState.completeError(error, stackTrace);
            }
            notifyListeners();
          },
        );
    await _initialState.future.timeout(const Duration(seconds: 15));
  }

  /// Reasserts presence after Home/background. The RTDB stream remains the
  /// source of truth, so no local turn is resumed or fabricated here.
  Future<void> resume() async {
    if (_disposed) return;
    await client.beginPresence(roomId);
  }

  Future<void> pause() async {
    if (_disposed) return;
    await client.markAfk(roomId);
  }

  Future<void> leaveMatch() async {
    if (_disposed) return;
    try {
      await client.leaveQuickPop(roomId);
    } finally {
      await client.endPresence(roomId);
    }
  }

  Future<void> roll() => _send(OnlineV3QuickPopCommandKind.roll);

  Future<void> move({required int tokenId, required int die}) => _send(
    OnlineV3QuickPopCommandKind.move,
    payload: <String, Object?>{'tokenId': tokenId, 'die': die},
  );

  Future<void> moveAll({required int tokenId}) => _send(
    OnlineV3QuickPopCommandKind.moveAll,
    payload: <String, Object?>{'tokenId': tokenId},
  );

  Future<void> _send(
    OnlineV3QuickPopCommandKind kind, {
    Map<String, Object?> payload = const {},
  }) async {
    final state = _state;
    if (_disposed || state == null || _submitting) return;
    if (!state.isHumanTurn(client.uid)) {
      throw const OnlineV3Exception('No es tu turno en esta partida.');
    }
    _submitting = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await client.sendCommand(
        roomId: roomId,
        expectedRevision: state.revision,
        kind: kind,
        payload: payload,
      );
      if (!result.accepted) {
        throw OnlineV3Exception(
          'El servidor rechazó la acción: ${result.code}.',
        );
      }
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _applyState(OnlineV3MatchState? state) {
    if (_disposed || state == null) return;
    try {
      final board = _engine;
      if (board == null) {
        _engine = OnlineV3GameAdapter.createBoard(
          state: state,
          localUid: client.uid,
          displayNames: <String, String>{client.uid: playerName},
        );
      } else {
        board.applyRemoteCheckpoint(
          OnlineV3GameAdapter.checkpointFor(
            state: state,
            localUid: client.uid,
            displayNames: <String, String>{client.uid: playerName},
          ),
        );
      }
      _state = state;
      _lastError = null;
      if (!_initialState.isCompleted) {
        _initialState.complete();
      }
    } catch (error, stackTrace) {
      _lastError = error;
      if (!_initialState.isCompleted) {
        _initialState.completeError(error, stackTrace);
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(client.endPresence(roomId));
    _engine?.dispose();
    super.dispose();
  }
}
