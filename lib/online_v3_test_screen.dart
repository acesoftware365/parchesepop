import 'dart:async';

import 'package:flutter/material.dart';

import 'online_v3_models.dart';
import 'online_v3_quick_pop.dart';

/// Deliberately small beta-only surface for exercising the real V3 protocol
/// before it is connected to the production Quick Pop presentation.
class OnlineV3QuickPopTestScreen extends StatefulWidget {
  const OnlineV3QuickPopTestScreen({super.key, required this.playerName});

  final String playerName;

  @override
  State<OnlineV3QuickPopTestScreen> createState() =>
      _OnlineV3QuickPopTestScreenState();
}

class _OnlineV3QuickPopTestScreenState
    extends State<OnlineV3QuickPopTestScreen> {
  OnlineV3QuickPopClient? _client;
  OnlineV3QuickPopTicket? _ticket;
  OnlineV3MatchState? _match;
  StreamSubscription<OnlineV3MatchState?>? _matchSubscription;
  Timer? _retryTimer;
  String _status = 'Conectando al servidor…';
  String? _error;
  bool _submitting = false;
  bool _joining = false;
  late final String _queueAttemptId =
      'attempt_${DateTime.now().microsecondsSinceEpoch}';

  static const _queueKey = 'traditional_v3_beta';

  @override
  void initState() {
    super.initState();
    unawaited(_connectAndJoin());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_matchSubscription?.cancel());
    final client = _client;
    final roomId = _ticket?.roomId;
    if (client != null && roomId != null) unawaited(client.endPresence(roomId));
    super.dispose();
  }

  Future<void> _connectAndJoin() async {
    try {
      final client = await OnlineV3QuickPopClient.connect();
      if (!mounted) return;
      setState(() => _client = client);
      await _joinOnce();
      _retryTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_joinOnce()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _joinOnce() async {
    final client = _client;
    if (client == null || _matchSubscription != null || _joining) return;
    _joining = true;
    try {
      // Keep an assigned ticket while retrying presence. This is important
      // when a transient RTDB/rules error happens after matchmaking: the
      // player must rejoin the already-created server room, not wait forever.
      final ticket = _ticket?.roomId == null
          ? await client.join(
              attemptId: _queueAttemptId,
              queueKey: _queueKey,
              playerName: widget.playerName,
            )
          : _ticket!;
      if (!mounted) return;
      if (ticket.roomId == null) {
        setState(() {
          _ticket = ticket;
          _status = 'Buscando jugadores V3…';
        });
        return;
      }
      await client.beginPresence(ticket.roomId!);
      await _matchSubscription?.cancel();
      _matchSubscription = client
          .watchMatch(ticket.roomId!)
          .listen(
            (match) {
              if (!mounted) return;
              setState(() {
                _ticket = ticket;
                _match = match;
                _status = match == null
                    ? 'Sincronizando partida…'
                    : 'Partida V3 conectada';
              });
            },
            onError: (Object error) {
              if (mounted) setState(() => _error = '$error');
            },
          );
      if (mounted) {
        _retryTimer?.cancel();
        setState(() {
          _ticket = ticket;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _joining = false;
    }
  }

  Future<void> _command(
    OnlineV3QuickPopCommandKind kind, {
    Map<String, Object?> payload = const {},
  }) async {
    final client = _client;
    final match = _match;
    final roomId = _ticket?.roomId;
    if (client == null || match == null || roomId == null || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await client.sendCommand(
        roomId: roomId,
        expectedRevision: match.revision,
        kind: kind,
        payload: payload,
      );
      if (mounted && !result.accepted) {
        setState(() => _error = 'Comando rechazado: ${result.code}');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    final client = _client;
    final humanTurn =
        match != null && client != null && match.isHumanTurn(client.uid);
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Pop V3 · Beta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SelectableText('Jugador: ${widget.playerName}'),
          SelectableText('Ticket: ${_ticket?.ticketId ?? '—'}'),
          SelectableText('Sala: ${_ticket?.roomId ?? 'esperando'}'),
          if (match != null) ...[
            const Divider(height: 30),
            SelectableText('Revisión: ${match.revision} · turno ${match.turn}'),
            SelectableText('Turno: ${match.currentTurnUid} · ${match.phase}'),
            SelectableText('Dados: ${match.dice.join(', ')}'),
            SelectableText('Disponibles: ${match.remainingDice.join(', ')}'),
            SelectableText('Rojo: ${match.pieces['red']}'),
            SelectableText('Verde: ${match.pieces['green']}'),
            SelectableText('Amarillo: ${match.pieces['yellow']}'),
            SelectableText('Azul: ${match.pieces['blue']}'),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: humanTurn && !match.hasRolled && !_submitting
                  ? () => _command(OnlineV3QuickPopCommandKind.roll)
                  : null,
              icon: const Icon(Icons.casino_rounded),
              label: const Text('LANZAR DADOS'),
            ),
            if (humanTurn && match.hasRolled) ...[
              const SizedBox(height: 12),
              for (final tokenId in [0, 1])
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final die in match.remainingDice.toSet())
                      OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => _command(
                                OnlineV3QuickPopCommandKind.move,
                                payload: {'tokenId': tokenId, 'die': die},
                              ),
                        child: Text('Ficha ${tokenId + 1} · $die'),
                      ),
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => _command(
                              OnlineV3QuickPopCommandKind.moveAll,
                              payload: {'tokenId': tokenId},
                            ),
                      child: Text('Ficha ${tokenId + 1} · ambos'),
                    ),
                  ],
                ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
