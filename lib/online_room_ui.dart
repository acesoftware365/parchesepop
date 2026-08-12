import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareResultStatus;

import 'app_language.dart';
import 'game_analytics.dart';
import 'online_invite.dart';
import 'online_lobby.dart';
import 'online_transport.dart';

enum OnlineRoomGameMode { classic, chaos }

/// A local room operation was explicitly cancelled before it could become
/// visible to the player.
final class OnlineRoomOperationCancelledException implements Exception {
  const OnlineRoomOperationCancelledException();
}

class PublicRoomSummary {
  const PublicRoomSummary({
    required this.roomId,
    required this.roomCode,
    required this.hostDisplayName,
    required this.mode,
    required this.occupiedSeats,
    this.roomName,
  }) : assert(occupiedSeats >= 1 && occupiedSeats <= 4);

  final String roomId;
  final RoomCode roomCode;
  final String hostDisplayName;
  final OnlineRoomGameMode mode;
  final int occupiedSeats;
  final String? roomName;
}

/// Backend-agnostic boundary used by the mobile room UI.
///
/// A production implementation must authenticate every action and publish
/// server snapshots through [Listenable]. The UI never generates dice values,
/// assigns seats, or grants host permissions by itself.
abstract interface class OnlineRoomController implements Listenable {
  String get localParticipantId;
  OnlineLobby? get lobby;
  OnlineRoomGameMode? get roomMode;
  List<PublicRoomSummary> get publicRooms;
  bool get loadingPublicRooms;
  String? get publicRoomsError;

  Future<void> refreshPublicRooms();

  Future<void> createRoom({
    required OnlineRoomGameMode mode,
    required RoomVisibility visibility,
    String? roomName,
  });

  /// Reports a public room for moderation. The backend should rate-limit and
  /// deduplicate reports; the UI never exposes reporter identity to other
  /// players.
  Future<void> reportPublicRoom({
    required String roomId,
    required String reason,
  });

  Future<void> cancelPendingCreate();
  Future<void> joinRoomByCode(RoomCode roomCode);
  Future<void> joinPublicRoom(String roomId);
  Future<void> cancelPendingJoin();
  Future<void> setReady(bool ready);
  Future<void> changeVisibility(RoomVisibility visibility);
  Future<void> kick(String participantId);
  Future<void> leaveRoom();
  Future<void> closeRoom();

  /// Releases local presence and realtime listeners after either the room
  /// record or lobby aggregate reports a terminal closed state.
  ///
  /// Implementations must coalesce concurrent calls. This is deliberately
  /// separate from [closeRoom]: acknowledging a remote close must never issue
  /// another host-close mutation.
  Future<void> dismissClosedRoom();
  Future<void> startOpeningRoll();
  Future<void> rollOpeningDie();
  Future<void> markGameStarted();
}

class QuickTableHubScreen extends StatelessWidget {
  const QuickTableHubScreen({
    super.key,
    required this.controller,
    this.onPlayLocal,
    this.shareService,
    this.analytics = const NoopGameAnalytics(),
    this.launchSource = MatchLaunchSource.home,
    this.createTimeout = const Duration(seconds: 15),
  }) : assert(createTimeout > Duration.zero);

  final OnlineRoomController controller;

  /// Kept nullable for invite/error-flow compatibility. Local play now has
  /// its own home card (PASS & PLAY), so the online room hub never renders a
  /// duplicate local-match action.
  final VoidCallback? onPlayLocal;
  final RoomInviteShareService? shareService;
  final GameAnalytics analytics;
  final MatchLaunchSource launchSource;
  final Duration createTimeout;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RoomColors.cloud,
    appBar: AppBar(
      backgroundColor: _RoomColors.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const PopText(
        'MESA RÁPIDA',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 680;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 10 : 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PopText(
                  'JUEGA CON AMIGOS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _RoomColors.navy,
                    fontSize: compact ? 20 : 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const PopText(
                  'Crea una sala, entra con código o busca una mesa pública.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: compact ? 10 : 18),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _HubAction(
                          key: const ValueKey('quick-table-create-room'),
                          color: _RoomColors.blue,
                          icon: Icons.add_home_work_rounded,
                          title: 'CREAR SALA',
                          subtitle: 'Pública o privada · 2–4 jugadores',
                          onTap: () => _open(
                            context,
                            CreateRoomScreen(
                              controller: controller,
                              shareService: shareService,
                              analytics: analytics,
                              launchSource: launchSource,
                              createTimeout: createTimeout,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _HubAction(
                          key: const ValueKey('quick-table-join-code'),
                          color: _RoomColors.purple,
                          icon: Icons.password_rounded,
                          title: 'ENTRAR CON CÓDIGO',
                          subtitle: 'Usa el código de seis caracteres',
                          onTap: () => _open(
                            context,
                            JoinRoomCodeScreen(
                              controller: controller,
                              shareService: shareService,
                              analytics: analytics,
                              launchSource: launchSource,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _HubAction(
                          key: const ValueKey('quick-table-public-rooms'),
                          color: _RoomColors.green,
                          icon: Icons.public_rounded,
                          title: 'SALAS PÚBLICAS',
                          subtitle: 'Encuentra una mesa disponible',
                          onTap: () => _open(
                            context,
                            PublicRoomsScreen(
                              controller: controller,
                              shareService: shareService,
                              analytics: analytics,
                              launchSource: launchSource,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({
    super.key,
    required this.controller,
    this.shareService,
    this.analytics = const NoopGameAnalytics(),
    this.launchSource = MatchLaunchSource.home,
    this.createTimeout = const Duration(seconds: 15),
  }) : assert(createTimeout > Duration.zero);

  final OnlineRoomController controller;
  final RoomInviteShareService? shareService;
  final GameAnalytics analytics;
  final MatchLaunchSource launchSource;
  final Duration createTimeout;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final roomNameController = TextEditingController();
  OnlineRoomGameMode mode = OnlineRoomGameMode.classic;
  RoomVisibility visibility = RoomVisibility.private;
  bool submitting = false;
  bool createTerminalLogged = false;
  bool cancellationInProgress = false;
  DateTime? attemptStartedAt;

  int get attemptElapsedMilliseconds {
    final startedAt = attemptStartedAt;
    if (startedAt == null) return 0;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  OnlineRoomAccess get analyticsRoomAccess =>
      visibility == RoomVisibility.public
      ? OnlineRoomAccess.public
      : OnlineRoomAccess.private;

  @override
  void dispose() {
    roomNameController.dispose();
    if (submitting && !createTerminalLogged) {
      createTerminalLogged = true;
      unawaited(_cancelPendingRoomCreate(widget.controller));
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.createCancelled,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            roomAccess: analyticsRoomAccess,
          ),
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !submitting || createTerminalLogged,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && submitting) unawaited(_cancelCreateAndLeave());
    },
    child: Scaffold(
      backgroundColor: _RoomColors.cloud,
      appBar: AppBar(
        backgroundColor: _RoomColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const PopText('CREAR SALA'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel(
                icon: Icons.sports_esports_rounded,
                label: 'MODO DE JUEGO',
              ),
              const SizedBox(height: 10),
              SegmentedButton<OnlineRoomGameMode>(
                key: const ValueKey('create-room-mode'),
                segments: const [
                  ButtonSegment(
                    value: OnlineRoomGameMode.classic,
                    icon: Icon(Icons.emoji_events_rounded),
                    label: PopText('CLÁSICO'),
                  ),
                  ButtonSegment(
                    value: OnlineRoomGameMode.chaos,
                    icon: Icon(Icons.bolt_rounded),
                    label: PopText('CAOS'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: submitting
                    ? null
                    : (selection) => setState(() => mode = selection.single),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(vertical: 2),
                ),
              ),
              const SizedBox(height: 18),
              const _SectionLabel(
                icon: Icons.edit_rounded,
                label: 'NOMBRE DE LA SALA',
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('create-room-name-field'),
                controller: roomNameController,
                enabled: !submitting,
                maxLength: 28,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ej. Noche de amigos',
                  helperText: 'Opcional · visible en salas públicas',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel(
                icon: Icons.visibility_rounded,
                label: 'QUIÉN PUEDE ENTRAR',
              ),
              const SizedBox(height: 10),
              SegmentedButton<RoomVisibility>(
                key: const ValueKey('create-room-visibility'),
                segments: const [
                  ButtonSegment(
                    value: RoomVisibility.private,
                    icon: Icon(Icons.lock_rounded),
                    label: PopText('PRIVADA'),
                  ),
                  ButtonSegment(
                    value: RoomVisibility.public,
                    icon: Icon(Icons.public_rounded),
                    label: PopText('PÚBLICA'),
                  ),
                ],
                selected: {visibility},
                onSelectionChanged: submitting
                    ? null
                    : (selection) =>
                          setState(() => visibility = selection.single),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(vertical: 2),
                ),
              ),
              const SizedBox(height: 16),
              _InfoPanel(
                icon: visibility == RoomVisibility.private
                    ? Icons.key_rounded
                    : Icons.travel_explore_rounded,
                text: visibility == RoomVisibility.private
                    ? 'Solo entran quienes tengan tu código o invitación.'
                    : 'Tu sala aparecerá en la lista pública hasta llenarse.',
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('create-room-submit'),
                onPressed: submitting ? null : _createRoom,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded),
                label: PopText(submitting ? 'CREANDO…' : 'CREAR SALA'),
                style: _RoomStyles.primaryButton(_RoomColors.blue),
              ),
              if (submitting) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('create-room-cancel'),
                  onPressed: cancellationInProgress
                      ? null
                      : _cancelCreateAndLeave,
                  icon: const Icon(Icons.close_rounded),
                  label: const PopText('CANCELAR'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _createRoom() async {
    attemptStartedAt = DateTime.now();
    createTerminalLogged = false;
    cancellationInProgress = false;
    final roomAccess = analyticsRoomAccess;
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.createStarted,
          launchSource: widget.launchSource,
          roomAccess: roomAccess,
        ),
      ),
    );
    setState(() => submitting = true);
    try {
      await widget.controller
          .createRoom(
            mode: mode,
            visibility: visibility,
            roomName: _cleanRoomName(roomNameController.text),
          )
          .timeout(
            widget.createTimeout,
            onTimeout: () async {
              await _cancelPendingRoomCreate(widget.controller);
              throw TimeoutException('Room creation timed out.');
            },
          );
      if (createTerminalLogged) return;
      if (!mounted) return;
      if (widget.controller.lobby == null) {
        throw StateError('El servidor no devolvió la sala creada.');
      }
      createTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.roomCreated,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            roomAccess: roomAccess,
          ),
        ),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoomLobbyScreen(
            controller: widget.controller,
            shareService: widget.shareService,
            analytics: widget.analytics,
            launchSource: widget.launchSource,
          ),
        ),
      );
    } catch (error) {
      if (createTerminalLogged || !mounted) return;
      createTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.createFailed,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            failureReason: onlineRoomAnalyticsFailureReason(error),
            roomAccess: roomAccess,
          ),
        ),
      );
      if (mounted) _showRoomError(context, error);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _cancelCreateAndLeave() async {
    if (!submitting || createTerminalLogged || cancellationInProgress) return;
    setState(() {
      cancellationInProgress = true;
      createTerminalLogged = true;
    });
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.createCancelled,
          launchSource: widget.launchSource,
          elapsedMilliseconds: attemptElapsedMilliseconds,
          roomAccess: analyticsRoomAccess,
        ),
      ),
    );
    try {
      await widget.controller.cancelPendingCreate();
    } catch (_) {
      // The local attempt is already terminal; cleanup remains best effort.
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }
}

class JoinRoomCodeScreen extends StatefulWidget {
  const JoinRoomCodeScreen({
    super.key,
    required this.controller,
    this.shareService,
    this.analytics = const NoopGameAnalytics(),
    this.launchSource = MatchLaunchSource.home,
  });

  final OnlineRoomController controller;
  final RoomInviteShareService? shareService;
  final GameAnalytics analytics;
  final MatchLaunchSource launchSource;

  @override
  State<JoinRoomCodeScreen> createState() => _JoinRoomCodeScreenState();
}

class _JoinRoomCodeScreenState extends State<JoinRoomCodeScreen> {
  final textController = TextEditingController();
  bool submitting = false;
  DateTime? attemptStartedAt;
  bool joinTerminalLogged = false;

  bool get valid => RoomCode.isValid(textController.text);

  int get attemptElapsedMilliseconds {
    final startedAt = attemptStartedAt;
    if (startedAt == null) return 0;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  @override
  void dispose() {
    if (submitting && !joinTerminalLogged) {
      joinTerminalLogged = true;
      unawaited(_cancelPendingRoomJoin(widget.controller));
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.joinCancelled,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            joinMethod: OnlineJoinMethod.roomCode,
          ),
        ),
      );
    }
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RoomColors.cloud,
    appBar: AppBar(
      backgroundColor: _RoomColors.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const PopText('ENTRAR CON CÓDIGO'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.password_rounded,
              color: _RoomColors.purple,
              size: 58,
            ),
            const SizedBox(height: 12),
            const PopText(
              'ESCRIBE EL CÓDIGO DE LA SALA',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _RoomColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const PopText(
              'Lo encontrarás en la invitación de tu amigo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('join-room-code-field'),
              controller: textController,
              enabled: !submitting,
              autofocus: true,
              maxLength: RoomCode.length,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [const RoomCodeInputFormatter()],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (valid && !submitting) _joinRoom();
              },
              style: const TextStyle(
                color: _RoomColors.navy,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 7,
              ),
              decoration: InputDecoration(
                hintText: 'ABC234',
                counterText: '${textController.text.length}/6',
                errorText:
                    textController.text.length == RoomCode.length && !valid
                    ? appTranslate(
                        context,
                        'Usa letras y números sin I, O, 0 ni 1.',
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('join-room-code-submit'),
              onPressed: valid && !submitting ? _joinRoom : null,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: PopText(submitting ? 'ENTRANDO…' : 'ENTRAR A LA SALA'),
              style: _RoomStyles.primaryButton(_RoomColors.purple),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _joinRoom() async {
    attemptStartedAt = DateTime.now();
    joinTerminalLogged = false;
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.joinStarted,
          launchSource: widget.launchSource,
          joinMethod: OnlineJoinMethod.roomCode,
        ),
      ),
    );
    setState(() => submitting = true);
    try {
      await widget.controller.joinRoomByCode(
        RoomCode.parse(textController.text),
      );
      if (!mounted) return;
      if (widget.controller.lobby == null) {
        throw StateError('La sala no está disponible.');
      }
      joinTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.roomJoined,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            joinMethod: OnlineJoinMethod.roomCode,
          ),
        ),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoomLobbyScreen(
            controller: widget.controller,
            shareService: widget.shareService,
            analytics: widget.analytics,
            launchSource: widget.launchSource,
          ),
        ),
      );
    } catch (error) {
      if (!mounted || joinTerminalLogged) return;
      final failureReason = onlineRoomAnalyticsFailureReason(error);
      joinTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: failureReason == OnlineFlowFailureReason.cancelled
                ? OnlineFlowStage.joinCancelled
                : OnlineFlowStage.joinFailed,
            launchSource: widget.launchSource,
            elapsedMilliseconds: attemptElapsedMilliseconds,
            joinMethod: OnlineJoinMethod.roomCode,
            failureReason: failureReason == OnlineFlowFailureReason.cancelled
                ? null
                : failureReason,
          ),
        ),
      );
      if (mounted) _showRoomError(context, error);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

class RoomCodeInputFormatter extends TextInputFormatter {
  const RoomCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text.toUpperCase().replaceAll(
      RegExp('[^A-Z0-9]'),
      '',
    );
    final truncated = normalized.length <= RoomCode.length
        ? normalized
        : normalized.substring(0, RoomCode.length);
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

class PublicRoomsScreen extends StatefulWidget {
  const PublicRoomsScreen({
    super.key,
    required this.controller,
    this.shareService,
    this.analytics = const NoopGameAnalytics(),
    this.launchSource = MatchLaunchSource.home,
  });

  final OnlineRoomController controller;
  final RoomInviteShareService? shareService;
  final GameAnalytics analytics;
  final MatchLaunchSource launchSource;

  @override
  State<PublicRoomsScreen> createState() => _PublicRoomsScreenState();
}

class _PublicRoomsScreenState extends State<PublicRoomsScreen> {
  String? joiningRoomId;
  DateTime? searchStartedAt;
  DateTime? joinStartedAt;
  bool joinedRoom = false;
  bool searchCancellationLogged = false;
  bool searchFailureLogged = false;
  bool joinTerminalLogged = false;
  bool refreshInProgress = false;

  int _elapsedMillisecondsSince(DateTime? startedAt) {
    if (startedAt == null) return 0;
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerUpdate);
    unawaited(_refreshRooms());
  }

  @override
  void didUpdateWidget(covariant PublicRoomsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerUpdate);
    widget.controller.addListener(_handleControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    if (joiningRoomId != null && !joinedRoom && !joinTerminalLogged) {
      joinTerminalLogged = true;
      unawaited(_cancelPendingRoomJoin(widget.controller));
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.joinCancelled,
            launchSource: widget.launchSource,
            elapsedMilliseconds: _elapsedMillisecondsSince(joinStartedAt),
            joinMethod: OnlineJoinMethod.publicDirectory,
          ),
        ),
      );
    } else if (!joinedRoom &&
        !searchCancellationLogged &&
        !searchFailureLogged &&
        searchStartedAt != null) {
      searchCancellationLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.searchCancelled,
            launchSource: widget.launchSource,
            elapsedMilliseconds: _elapsedMillisecondsSince(searchStartedAt),
          ),
        ),
      );
    }
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!refreshInProgress &&
        widget.controller.publicRoomsError != null &&
        !searchFailureLogged) {
      _logSearchFailure(OnlineFlowFailureReason.network);
    }
  }

  Future<void> _refreshRooms() async {
    refreshInProgress = true;
    searchStartedAt = DateTime.now();
    searchFailureLogged = false;
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.searchStarted,
          launchSource: widget.launchSource,
        ),
      ),
    );
    try {
      await widget.controller.refreshPublicRooms();
      refreshInProgress = false;
      _handleControllerUpdate();
    } catch (error) {
      refreshInProgress = false;
      _logSearchFailure(onlineRoomAnalyticsFailureReason(error));
      if (mounted) _showRoomError(context, error);
    }
  }

  void _logSearchFailure(OnlineFlowFailureReason reason) {
    if (searchFailureLogged) return;
    searchFailureLogged = true;
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.searchFailed,
          launchSource: widget.launchSource,
          elapsedMilliseconds: _elapsedMillisecondsSince(searchStartedAt),
          failureReason: reason,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _RoomColors.cloud,
    appBar: AppBar(
      backgroundColor: _RoomColors.navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const PopText('SALAS PÚBLICAS'),
      actions: [
        IconButton(
          key: const ValueKey('public-rooms-refresh'),
          tooltip: appTranslate(context, 'Actualizar'),
          onPressed: widget.controller.loadingPublicRooms
              ? null
              : _refreshRooms,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          if (widget.controller.loadingPublicRooms &&
              widget.controller.publicRooms.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final error = widget.controller.publicRoomsError;
          if (error != null && widget.controller.publicRooms.isEmpty) {
            return _PublicRoomsEmpty(
              icon: Icons.cloud_off_rounded,
              title: 'NO PUDIMOS CARGAR LAS SALAS',
              message:
                  'No pudimos conectar con el servidor. Revisa tu internet e inténtalo otra vez.',
              onRetry: _refreshRooms,
            );
          }
          if (widget.controller.publicRooms.isEmpty) {
            return _PublicRoomsEmpty(
              icon: Icons.weekend_rounded,
              title: 'NO HAY SALAS ABIERTAS',
              message: 'Crea una sala pública o vuelve a intentarlo.',
              onRetry: _refreshRooms,
            );
          }
          return RefreshIndicator(
            onRefresh: _refreshRooms,
            child: ListView.separated(
              key: const ValueKey('public-rooms-list'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              itemCount: widget.controller.publicRooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final room = widget.controller.publicRooms[index];
                return _PublicRoomCard(
                  room: room,
                  joining: joiningRoomId == room.roomId,
                  onJoin: joiningRoomId == null ? () => _join(room) : null,
                  onReport: () => _report(room),
                );
              },
            ),
          );
        },
      ),
    ),
  );

  Future<void> _join(PublicRoomSummary room) async {
    joinStartedAt = DateTime.now();
    joinTerminalLogged = false;
    unawaited(
      widget.analytics.logEvent(
        OnlineFlowEvent(
          experience: OnlineExperience.quickTable,
          stage: OnlineFlowStage.joinStarted,
          launchSource: widget.launchSource,
          joinMethod: OnlineJoinMethod.publicDirectory,
        ),
      ),
    );
    setState(() => joiningRoomId = room.roomId);
    try {
      await widget.controller.joinPublicRoom(room.roomId);
      if (!mounted) return;
      if (widget.controller.lobby == null) {
        throw StateError('La sala ya no está disponible.');
      }
      joinedRoom = true;
      joinTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: OnlineFlowStage.roomJoined,
            launchSource: widget.launchSource,
            elapsedMilliseconds: _elapsedMillisecondsSince(joinStartedAt),
            joinMethod: OnlineJoinMethod.publicDirectory,
          ),
        ),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RoomLobbyScreen(
            controller: widget.controller,
            shareService: widget.shareService,
            analytics: widget.analytics,
            launchSource: widget.launchSource,
          ),
        ),
      );
    } catch (error) {
      if (!mounted || joinTerminalLogged) return;
      final failureReason = onlineRoomAnalyticsFailureReason(error);
      joinTerminalLogged = true;
      unawaited(
        widget.analytics.logEvent(
          OnlineFlowEvent(
            experience: OnlineExperience.quickTable,
            stage: failureReason == OnlineFlowFailureReason.cancelled
                ? OnlineFlowStage.joinCancelled
                : OnlineFlowStage.joinFailed,
            launchSource: widget.launchSource,
            elapsedMilliseconds: _elapsedMillisecondsSince(joinStartedAt),
            joinMethod: OnlineJoinMethod.publicDirectory,
            failureReason: failureReason == OnlineFlowFailureReason.cancelled
                ? null
                : failureReason,
          ),
        ),
      );
      if (mounted) _showRoomError(context, error);
    } finally {
      if (mounted) setState(() => joiningRoomId = null);
    }
  }

  Future<void> _report(PublicRoomSummary room) async {
    final reason = await _askReportReason(context);
    if (reason == null || !mounted) return;
    try {
      await widget.controller.reportPublicRoom(
        roomId: room.roomId,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: PopText(
              'Reporte enviado. Gracias por ayudar a mantener la comunidad segura.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showRoomError(context, error);
    }
  }
}

class RoomLobbyScreen extends StatefulWidget {
  const RoomLobbyScreen({
    super.key,
    required this.controller,
    this.shareService,
    this.analytics = const NoopGameAnalytics(),
    this.launchSource = MatchLaunchSource.home,
  });

  final OnlineRoomController controller;
  final RoomInviteShareService? shareService;
  final GameAnalytics analytics;
  final MatchLaunchSource launchSource;

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  String? action;
  bool allowPop = false;
  bool handledClosedRoom = false;
  bool handledUnavailableRoom = false;
  bool hadLobby = false;
  bool intentionalLeaveInProgress = false;

  bool get busy => action != null;

  @override
  void initState() {
    super.initState();
    hadLobby = widget.controller.lobby != null;
    widget.controller.addListener(_handleControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleControllerUpdate();
    });
  }

  @override
  void didUpdateWidget(covariant RoomLobbyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerUpdate);
    widget.controller.addListener(_handleControllerUpdate);
    handledClosedRoom = false;
    handledUnavailableRoom = false;
    hadLobby = widget.controller.lobby != null;
    intentionalLeaveInProgress = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleControllerUpdate();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerUpdate);
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    final lobby = widget.controller.lobby;
    if (lobby != null) {
      hadLobby = true;
      if (handledClosedRoom || lobby.status != RoomStatus.closed) return;
      handledClosedRoom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_exitClosedRoom());
      });
      return;
    }
    if (!hadLobby ||
        handledClosedRoom ||
        intentionalLeaveInProgress ||
        handledUnavailableRoom) {
      return;
    }
    handledUnavailableRoom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_exitUnavailableRoom());
    });
  }

  Future<void> _exitClosedRoom() async {
    try {
      await widget.controller.dismissClosedRoom();
    } catch (_) {
      // The room is already terminal. Navigation and clear feedback are more
      // useful than trapping the player in a dead lobby after cleanup fails.
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!allowPop) {
      setState(() => allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await Navigator.of(context).maybePop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey('room-closed-feedback'),
          content: PopText('Sala cerrada'),
        ),
      );
  }

  Future<void> _exitUnavailableRoom() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!allowPop) {
      setState(() => allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await Navigator.of(context).maybePop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: ValueKey('room-unavailable-feedback'),
          content: PopText('Ya no estás en la sala.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop || allowPop || busy) return;
      final lobby = widget.controller.lobby;
      if (lobby == null) {
        if (!handledUnavailableRoom) {
          handledUnavailableRoom = true;
          unawaited(_exitUnavailableRoom());
        }
        return;
      }
      final isHost =
          lobby.hostParticipantId == widget.controller.localParticipantId;
      unawaited(isHost ? _confirmClose() : _confirmLeave());
    },
    child: Scaffold(
      backgroundColor: _RoomColors.cloud,
      appBar: AppBar(
        backgroundColor: _RoomColors.navy,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const PopText('SALA ONLINE'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final lobby = widget.controller.lobby;
            if (lobby == null) {
              return const Center(
                child: PopText('La sala ya no está disponible.'),
              );
            }
            final local = lobby.participantById(
              widget.controller.localParticipantId,
            );
            final isHost = local.participantId == lobby.hostParticipantId;
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                return Padding(
                  padding: EdgeInsets.fromLTRB(10, compact ? 7 : 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LobbyHeader(
                        lobby: lobby,
                        mode: widget.controller.roomMode,
                        isHost: isHost,
                        busy: busy,
                        onShare: _shareInvite,
                        onCopy: () => _copyCode(lobby.roomCode),
                        onExit: isHost ? _confirmClose : _confirmLeave,
                        exitClosesRoom: isHost,
                      ),
                      SizedBox(height: compact ? 6 : 9),
                      _VisibilityControl(
                        visibility: lobby.visibility,
                        hostEnabled:
                            isHost &&
                            !busy &&
                            lobby.status == RoomStatus.waiting,
                        onChanged: (value) => _run(
                          'visibility',
                          () => widget.controller.changeVisibility(value),
                        ),
                      ),
                      SizedBox(height: compact ? 6 : 9),
                      Expanded(
                        flex: lobby.status == RoomStatus.waiting ? 5 : 4,
                        child: _SeatGrid(
                          lobby: lobby,
                          localParticipantId:
                              widget.controller.localParticipantId,
                          canKick:
                              isHost &&
                              !busy &&
                              lobby.status == RoomStatus.waiting,
                          onKick: _confirmKick,
                        ),
                      ),
                      if (lobby.status != RoomStatus.waiting) ...[
                        SizedBox(height: compact ? 6 : 8),
                        Expanded(
                          flex: 3,
                          child: _OpeningRollPanel(
                            lobby: lobby,
                            localParticipantId:
                                widget.controller.localParticipantId,
                            isHost: isHost,
                            busy: busy,
                            onRoll: () =>
                                _run('roll', widget.controller.rollOpeningDie),
                            onStartGame: () => _run(
                              'game-start',
                              widget.controller.markGameStarted,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 6 : 9),
                      if (lobby.status == RoomStatus.waiting)
                        _WaitingRoomActions(
                          lobby: lobby,
                          local: local,
                          isHost: isHost,
                          busy: busy,
                          onReady: () => _run(
                            'ready',
                            () => widget.controller.setReady(!local.ready),
                          ),
                          onStart: () => _run(
                            'opening-roll',
                            widget.controller.startOpeningRoll,
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );

  Future<void> _run(String operation, Future<void> Function() callback) async {
    if (busy) return;
    setState(() => action = operation);
    try {
      await callback();
    } catch (error) {
      if (mounted) _showRoomError(context, error);
    } finally {
      if (mounted) setState(() => action = null);
    }
  }

  Future<void> _copyCode(RoomCode code) async {
    await Clipboard.setData(ClipboardData(text: code.value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: PopText('Código copiado.')));
    }
  }

  Future<void> _shareInvite(BuildContext buttonContext) async {
    final lobby = widget.controller.lobby;
    if (lobby == null || busy) return;
    final service = widget.shareService ?? RoomInviteShareService();
    final renderBox = buttonContext.findRenderObject();
    Rect? origin;
    if (renderBox is RenderBox && renderBox.hasSize) {
      origin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    }
    await _run('share', () async {
      try {
        final result = await service.share(
          RoomInvite(lobby.roomCode),
          sharePositionOrigin: origin,
        );
        final stage = result.status == ShareResultStatus.dismissed
            ? OnlineFlowStage.inviteShareCancelled
            : OnlineFlowStage.inviteShared;
        unawaited(
          widget.analytics.logEvent(
            OnlineFlowEvent(
              experience: OnlineExperience.quickTable,
              stage: stage,
              launchSource: widget.launchSource,
            ),
          ),
        );
      } catch (error) {
        unawaited(
          widget.analytics.logEvent(
            OnlineFlowEvent(
              experience: OnlineExperience.quickTable,
              stage: OnlineFlowStage.inviteShareFailed,
              launchSource: widget.launchSource,
              failureReason: onlineRoomAnalyticsFailureReason(error),
            ),
          ),
        );
        rethrow;
      }
    });
  }

  Future<void> _confirmKick(LobbyParticipant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const PopText('¿EXPULSAR JUGADOR?'),
        content: PopText('${participant.displayName} saldrá de la sala.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const PopText('CANCELAR'),
          ),
          FilledButton(
            key: const ValueKey('confirm-kick-player'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const PopText('EXPULSAR'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        'kick',
        () => widget.controller.kick(participant.participantId),
      );
    }
  }

  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const PopText('¿CERRAR SALA?'),
        content: const PopText('Todos los jugadores volverán al inicio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const PopText('CANCELAR'),
          ),
          FilledButton(
            key: const ValueKey('confirm-close-room'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const PopText('CERRAR'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run('close', widget.controller.closeRoom);
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const PopText('¿SALIR DE LA SALA?'),
        content: const PopText('Podrás volver a entrar mientras siga abierta.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const PopText('CANCELAR'),
          ),
          FilledButton(
            key: const ValueKey('confirm-leave-room'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const PopText('SALIR'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    intentionalLeaveInProgress = true;
    await _run('leave', widget.controller.leaveRoom);
    if (mounted && widget.controller.lobby == null) {
      if (!allowPop) {
        setState(() => allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await Navigator.of(context).maybePop();
    } else {
      intentionalLeaveInProgress = false;
    }
  }
}

class _HubAction extends StatelessWidget {
  const _HubAction({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    title,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  PopText(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _RoomColors.blue),
      const SizedBox(width: 8),
      PopText(
        label,
        style: const TextStyle(
          color: _RoomColors.navy,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Row(
      children: [
        Icon(icon, color: _RoomColors.blue),
        const SizedBox(width: 10),
        Expanded(
          child: PopText(
            text,
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PublicRoomsEmpty extends StatelessWidget {
  const _PublicRoomsEmpty({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 62, color: _RoomColors.blue),
        const SizedBox(height: 14),
        PopText(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _RoomColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        PopText(message, textAlign: TextAlign.center),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const PopText('ACTUALIZAR'),
        ),
      ],
    ),
  );
}

class _PublicRoomCard extends StatelessWidget {
  const _PublicRoomCard({
    required this.room,
    required this.joining,
    required this.onJoin,
    required this.onReport,
  });

  final PublicRoomSummary room;
  final bool joining;
  final VoidCallback? onJoin;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD8E2F2)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: room.mode == OnlineRoomGameMode.chaos
              ? _RoomColors.purple
              : _RoomColors.blue,
          child: Icon(
            room.mode == OnlineRoomGameMode.chaos
                ? Icons.bolt_rounded
                : Icons.emoji_events_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PopText(
                room.roomName?.isNotEmpty == true
                    ? room.roomName!
                    : room.hostDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _RoomColors.navy,
                  fontWeight: FontWeight.w900,
                ),
              ),
              PopText(
                '${room.mode == OnlineRoomGameMode.chaos ? 'CAOS' : 'CLÁSICO'}'
                ' · ${room.occupiedSeats}/4 · ${room.roomCode.value}'
                '${room.roomName?.isNotEmpty == true ? ' · ${room.hostDisplayName}' : ''}',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
        Column(
          children: [
            FilledButton(
              key: ValueKey('join-public-room-${room.roomId}'),
              onPressed: onJoin,
              child: joining
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const PopText('ENTRAR'),
            ),
            IconButton(
              key: ValueKey('report-public-room-${room.roomId}'),
              tooltip: appTranslate(context, 'Reportar sala'),
              onPressed: joining ? null : onReport,
              icon: const Icon(Icons.flag_outlined, color: _RoomColors.red),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    ),
  );
}

Future<String?> _askReportReason(BuildContext context) async {
  const reasons = <String>[
    'Nombre o contenido ofensivo',
    'Trampa o comportamiento abusivo',
    'Sala sospechosa o spam',
  ];
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const PopText('REPORTAR SALA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PopText(
            'Elige el motivo. Revisaremos los reportes antes de tomar medidas.',
          ),
          const SizedBox(height: 12),
          for (final reason in reasons)
            ListTile(
              dense: true,
              leading: const Icon(Icons.flag_outlined, color: _RoomColors.red),
              title: PopText(reason),
              onTap: () => Navigator.of(dialogContext).pop(reason),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const PopText('CANCELAR'),
        ),
      ],
    ),
  );
}

String? _cleanRoomName(String raw) {
  final clean = raw.trim();
  return clean.isEmpty ? null : clean;
}

class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader({
    required this.lobby,
    required this.mode,
    required this.isHost,
    required this.busy,
    required this.onShare,
    required this.onCopy,
    required this.onExit,
    required this.exitClosesRoom,
  });

  final OnlineLobby lobby;
  final OnlineRoomGameMode? mode;
  final bool isHost;
  final bool busy;
  final ValueChanged<BuildContext> onShare;
  final VoidCallback onCopy;
  final VoidCallback onExit;
  final bool exitClosesRoom;

  @override
  Widget build(BuildContext context) {
    final modeLabel = mode == OnlineRoomGameMode.chaos
        ? '⚡ CAOS'
        : '🏆 CLÁSICO';
    final title = lobby.roomName?.isNotEmpty == true
        ? lobby.roomName!
        : modeLabel;
    final subtitle = lobby.roomName?.isNotEmpty == true
        ? '$modeLabel · ${lobby.occupiedSeatCount}/4 jugadores'
        : '${lobby.occupiedSeatCount}/4 jugadores';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _RoomColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PopText(
                      'CÓDIGO',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    PopText(
                      lobby.roomCode.value,
                      style: const TextStyle(
                        color: _RoomColors.navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _LobbyHeaderIconButton(
                key: const ValueKey('lobby-copy-code'),
                tooltip: appTranslate(context, 'Copiar código'),
                onPressed: busy ? null : onCopy,
                icon: Icons.copy_rounded,
              ),
              Builder(
                builder: (buttonContext) => _LobbyHeaderIconButton(
                  key: const ValueKey('lobby-share-invite'),
                  tooltip: appTranslate(context, 'Compartir invitación'),
                  onPressed: busy ? null : () => onShare(buttonContext),
                  icon: Icons.ios_share_rounded,
                ),
              ),
              _LobbyHeaderIconButton(
                key: ValueKey(
                  exitClosesRoom ? 'lobby-close-room' : 'lobby-leave-room',
                ),
                tooltip: appTranslate(
                  context,
                  exitClosesRoom ? 'Cerrar sala' : 'Salir de la sala',
                ),
                onPressed: busy ? null : onExit,
                icon: exitClosesRoom
                    ? Icons.close_rounded
                    : Icons.logout_rounded,
                color: _RoomColors.red,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PopText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                PopText(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyHeaderIconButton extends StatelessWidget {
  const _LobbyHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.color = Colors.white,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 36, height: 40),
    visualDensity: VisualDensity.compact,
    color: color,
    icon: Icon(icon, size: 24),
  );
}

class _VisibilityControl extends StatelessWidget {
  const _VisibilityControl({
    required this.visibility,
    required this.hostEnabled,
    required this.onChanged,
  });

  final RoomVisibility visibility;
  final bool hostEnabled;
  final ValueChanged<RoomVisibility> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const PopText(
        'ACCESO',
        style: TextStyle(
          color: _RoomColors.navy,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: SegmentedButton<RoomVisibility>(
          key: const ValueKey('lobby-visibility'),
          segments: const [
            ButtonSegment(
              value: RoomVisibility.private,
              icon: Icon(Icons.lock_rounded, size: 16),
              label: PopText('PRIVADA'),
            ),
            ButtonSegment(
              value: RoomVisibility.public,
              icon: Icon(Icons.public_rounded, size: 16),
              label: PopText('PÚBLICA'),
            ),
          ],
          selected: {visibility},
          onSelectionChanged: hostEnabled
              ? (selection) => onChanged(selection.single)
              : null,
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity(vertical: -2)),
        ),
      ),
    ],
  );
}

class _SeatGrid extends StatelessWidget {
  const _SeatGrid({
    required this.lobby,
    required this.localParticipantId,
    required this.canKick,
    required this.onKick,
  });

  final OnlineLobby lobby;
  final String localParticipantId;
  final bool canKick;
  final ValueChanged<LobbyParticipant> onKick;

  @override
  Widget build(BuildContext context) {
    Widget seat(LobbySeatColor color) => Expanded(
      child: _SeatCard(
        color: color,
        participant: lobby.participantForSeat(color),
        localParticipantId: localParticipantId,
        canKick: canKick,
        hostParticipantId: lobby.hostParticipantId,
        onKick: onKick,
      ),
    );
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              seat(LobbySeatColor.blue),
              const SizedBox(width: 8),
              seat(LobbySeatColor.yellow),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              seat(LobbySeatColor.red),
              const SizedBox(width: 8),
              seat(LobbySeatColor.green),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({
    required this.color,
    required this.participant,
    required this.localParticipantId,
    required this.canKick,
    required this.hostParticipantId,
    required this.onKick,
  });

  final LobbySeatColor color;
  final LobbyParticipant? participant;
  final String localParticipantId;
  final bool canKick;
  final String hostParticipantId;
  final ValueChanged<LobbyParticipant> onKick;

  @override
  Widget build(BuildContext context) {
    final player = participant;
    final seatColor = _RoomColors.forSeat(color);
    return Container(
      key: ValueKey('lobby-seat-${color.name}'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: seatColor, width: 2),
      ),
      child: player == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_add_alt_1_rounded,
                  color: seatColor,
                  size: 29,
                ),
                const SizedBox(height: 4),
                const PopText(
                  'ESPERANDO…',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: seatColor,
                        child: PopText(
                          player.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      PopText(
                        player.participantId == localParticipantId
                            ? '${player.displayName} · TÚ'
                            : player.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _RoomColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: player.connected
                                  ? _RoomColors.green
                                  : const Color(0xFF98A2B3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          PopText(
                            player.ready ? 'LISTO' : 'NO LISTO',
                            style: TextStyle(
                              color: player.ready
                                  ? _RoomColors.green
                                  : const Color(0xFF667085),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (player.participantId == hostParticipantId)
                  const Positioned(
                    left: 0,
                    top: 0,
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      size: 18,
                      color: _RoomColors.yellow,
                    ),
                  ),
                if (canKick && player.participantId != hostParticipantId)
                  Positioned(
                    right: -5,
                    top: -7,
                    child: IconButton(
                      key: ValueKey('kick-${player.participantId}'),
                      tooltip: appTranslate(
                        context,
                        'Expulsar ${player.displayName}',
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onKick(player),
                      icon: const Icon(
                        Icons.person_remove_rounded,
                        size: 19,
                        color: _RoomColors.red,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WaitingRoomActions extends StatelessWidget {
  const _WaitingRoomActions({
    required this.lobby,
    required this.local,
    required this.isHost,
    required this.busy,
    required this.onReady,
    required this.onStart,
  });

  final OnlineLobby lobby;
  final LobbyParticipant local;
  final bool isHost;
  final bool busy;
  final VoidCallback onReady;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          key: const ValueKey('lobby-ready'),
          onPressed: busy || !local.connected ? null : onReady,
          icon: Icon(
            local.ready ? Icons.check_circle_rounded : Icons.circle_outlined,
          ),
          label: PopText(local.ready ? 'LISTO' : 'MARCAR LISTO'),
          style: _RoomStyles.secondaryButton,
        ),
      ),
      if (isHost) ...[
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            key: const ValueKey('lobby-start-opening-roll'),
            onPressed: !busy && lobby.canStart ? onStart : null,
            icon: const Icon(Icons.casino_rounded),
            label: const PopText('INICIAR TIRADA'),
            style: _RoomStyles.primaryButton(_RoomColors.blue),
          ),
        ),
      ],
    ],
  );
}

class _OpeningRollPanel extends StatelessWidget {
  const _OpeningRollPanel({
    required this.lobby,
    required this.localParticipantId,
    required this.isHost,
    required this.busy,
    required this.onRoll,
    required this.onStartGame,
  });

  final OnlineLobby lobby;
  final String localParticipantId;
  final bool isHost;
  final bool busy;
  final VoidCallback onRoll;
  final VoidCallback onStartGame;

  @override
  Widget build(BuildContext context) {
    final opening = lobby.openingRoll;
    if (lobby.status == RoomStatus.inGame) {
      return const _InfoPanel(
        icon: Icons.sports_esports_rounded,
        text: 'La partida está comenzando…',
      );
    }
    if (opening == null) {
      return const _InfoPanel(
        icon: Icons.error_outline_rounded,
        text: 'Esperando la tirada inicial.',
      );
    }
    final localEligible = opening.eligibleParticipantIds.contains(
      localParticipantId,
    );
    final localRolled = opening.currentRolls.containsKey(localParticipantId);
    final canRoll =
        lobby.status == RoomStatus.openingRoll &&
        localEligible &&
        !localRolled &&
        !busy;
    final winner = opening.winnerParticipantId == null
        ? null
        : lobby.participantById(opening.winnerParticipantId!);

    return Container(
      key: const ValueKey('opening-roll-panel'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _RoomColors.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PopText(
            opening.round > 1
                ? 'DESEMPATE · RONDA ${opening.round}'
                : 'TIRADA PARA COMENZAR',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final participant in lobby.participants)
                _OpeningDieResult(
                  participant: participant,
                  value: _latestOpeningRoll(opening, participant.participantId),
                  eligible: opening.eligibleParticipantIds.contains(
                    participant.participantId,
                  ),
                ),
            ],
          ),
          if (lobby.status == RoomStatus.starting)
            if (isHost)
              FilledButton.icon(
                key: const ValueKey('lobby-start-game'),
                onPressed: busy ? null : onStartGame,
                icon: const Icon(Icons.play_arrow_rounded),
                label: PopText('COMENZAR · ${winner?.displayName ?? ''}'),
                style: _RoomStyles.primaryButton(_RoomColors.green),
              )
            else
              PopText(
                '${winner?.displayName ?? 'El ganador'} comienza. '
                'Esperando al anfitrión…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              )
          else
            FilledButton.icon(
              key: const ValueKey('lobby-roll-opening-die'),
              onPressed: canRoll ? onRoll : null,
              icon: const Icon(Icons.casino_rounded),
              label: PopText(
                opening.round > 1 ? 'TIRAR DESEMPATE' : 'TIRAR DADO',
              ),
            ),
        ],
      ),
    );
  }
}

class _OpeningDieResult extends StatelessWidget {
  const _OpeningDieResult({
    required this.participant,
    required this.value,
    required this.eligible,
  });

  final LobbyParticipant participant;
  final int? value;
  final bool eligible;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: eligible ? 1 : .48,
    child: Column(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: value == null
                ? Colors.white.withValues(alpha: .15)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _RoomColors.forSeat(participant.seat),
              width: 2,
            ),
          ),
          child: PopText(
            value?.toString() ?? '—',
            style: TextStyle(
              color: value == null ? Colors.white : _RoomColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 62,
          child: PopText(
            participant.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 9),
          ),
        ),
      ],
    ),
  );
}

int? _latestOpeningRoll(OpeningRollState opening, String participantId) {
  final current = opening.currentRolls[participantId];
  if (current != null) return current;
  for (final round in opening.history.reversed) {
    final previous = round.rolls[participantId];
    if (previous != null) return previous;
  }
  return null;
}

Future<void> _cancelPendingRoomJoin(OnlineRoomController controller) async {
  try {
    await controller.cancelPendingJoin();
  } catch (_) {
    // The local attempt token is invalidated synchronously. Remote cleanup is
    // best effort and must never make route disposal fail.
  }
}

Future<void> _cancelPendingRoomCreate(OnlineRoomController controller) async {
  try {
    await controller.cancelPendingCreate();
  } catch (_) {
    // The attempt token is invalidated synchronously by production. Cleanup is
    // best effort when a controller is concurrently being disposed.
  }
}

OnlineFlowFailureReason onlineRoomAnalyticsFailureReason(Object error) {
  if (error is TimeoutException) return OnlineFlowFailureReason.timeout;
  if (error is OnlineRoomOperationCancelledException) {
    return OnlineFlowFailureReason.cancelled;
  }
  if (error is FirebaseException) {
    final code = error.code.toLowerCase().replaceAll('_', '-');
    return switch (code) {
      'network-request-failed' ||
      'network-error' ||
      'disconnected' ||
      'unavailable' => OnlineFlowFailureReason.network,
      'permission-denied' => OnlineFlowFailureReason.permission,
      'operation-not-allowed' ||
      'app-not-authorized' ||
      'invalid-api-key' => OnlineFlowFailureReason.configuration,
      _ => OnlineFlowFailureReason.unknown,
    };
  }
  if (error is OnlineTransportException) {
    return switch (error.code) {
      OnlineTransportErrorCode.joinTimedOut => OnlineFlowFailureReason.timeout,
      OnlineTransportErrorCode.joinCancelled =>
        OnlineFlowFailureReason.cancelled,
      OnlineTransportErrorCode.roomFull => OnlineFlowFailureReason.roomFull,
      OnlineTransportErrorCode.roomNotFound ||
      OnlineTransportErrorCode.roomClosed => OnlineFlowFailureReason.roomClosed,
      OnlineTransportErrorCode.invalidIdentity ||
      OnlineTransportErrorCode.invalidPathSegment ||
      OnlineTransportErrorCode.invalidQueueTicket =>
        OnlineFlowFailureReason.invalidInput,
      OnlineTransportErrorCode.roomCodeUnavailable ||
      OnlineTransportErrorCode.duplicateSeat ||
      OnlineTransportErrorCode.unknownParticipant ||
      OnlineTransportErrorCode.notHost ||
      OnlineTransportErrorCode.invalidRoomStatus =>
        OnlineFlowFailureReason.unavailable,
    };
  }
  if (error is LobbyException) {
    return switch (error.code) {
      LobbyErrorCode.invalidRoomCode ||
      LobbyErrorCode.invalidParticipant => OnlineFlowFailureReason.invalidInput,
      LobbyErrorCode.roomFull => OnlineFlowFailureReason.roomFull,
      LobbyErrorCode.roomNotJoinable => OnlineFlowFailureReason.roomClosed,
      _ => OnlineFlowFailureReason.unavailable,
    };
  }
  if (error is RoomInviteFormatException) {
    return OnlineFlowFailureReason.invalidInput;
  }
  return OnlineFlowFailureReason.unknown;
}

String onlineRoomErrorMessage(Object error) => switch (error) {
  TimeoutException() =>
    'La operación tardó demasiado. Revisa tu conexión e inténtalo otra vez.',
  OnlineRoomOperationCancelledException() => 'La operación fue cancelada.',
  LobbyException(:final code) => switch (code) {
    LobbyErrorCode.invalidRoomCode => 'El código de sala no es válido.',
    LobbyErrorCode.invalidParticipant ||
    LobbyErrorCode.unknownParticipant => 'Ya no formas parte de esta sala.',
    LobbyErrorCode.duplicateParticipant => 'Ya estás dentro de esta sala.',
    LobbyErrorCode.roomFull => 'La sala ya está llena.',
    LobbyErrorCode.roomNotJoinable => 'La sala ya no acepta jugadores.',
    LobbyErrorCode.seatOccupied => 'Ese asiento ya está ocupado.',
    LobbyErrorCode.notHost || LobbyErrorCode.hostCannotBeKicked =>
      'Solo el anfitrión puede hacer esa acción.',
    LobbyErrorCode.invalidStatus =>
      'La sala cambió de estado. Inténtalo otra vez.',
    LobbyErrorCode.notEnoughPlayers => 'Faltan jugadores para comenzar.',
    LobbyErrorCode.participantsNotReady =>
      'Todos los jugadores deben marcarse como listos.',
    LobbyErrorCode.participantsDisconnected =>
      'Espera a que todos los jugadores se conecten.',
    LobbyErrorCode.openingRollUnavailable =>
      'La tirada inicial todavía no está disponible.',
    LobbyErrorCode.participantNotEligible =>
      'No te corresponde tirar en esta ronda.',
    LobbyErrorCode.participantAlreadyRolled =>
      'Ya tiraste el dado en esta ronda.',
  },
  OnlineTransportException(:final code) => switch (code) {
    OnlineTransportErrorCode.roomCodeUnavailable =>
      'No pudimos reservar un código de sala. Inténtalo otra vez.',
    OnlineTransportErrorCode.roomNotFound ||
    OnlineTransportErrorCode.roomClosed => 'La sala ya no está disponible.',
    OnlineTransportErrorCode.roomFull => 'La sala ya está llena.',
    OnlineTransportErrorCode.duplicateSeat => 'Ese asiento ya está ocupado.',
    OnlineTransportErrorCode.unknownParticipant =>
      'Ya no formas parte de esta sala.',
    OnlineTransportErrorCode.notHost =>
      'Solo el anfitrión puede hacer esa acción.',
    OnlineTransportErrorCode.invalidRoomStatus =>
      'La sala cambió de estado. Inténtalo otra vez.',
    OnlineTransportErrorCode.joinTimedOut =>
      'El anfitrión no respondió a tiempo. Inténtalo otra vez.',
    OnlineTransportErrorCode.joinCancelled =>
      'La solicitud para entrar fue cancelada.',
    OnlineTransportErrorCode.invalidIdentity ||
    OnlineTransportErrorCode.invalidPathSegment ||
    OnlineTransportErrorCode.invalidQueueTicket =>
      'No pudimos completar la acción online. Inténtalo otra vez.',
  },
  RoomInviteFormatException() => 'La invitación de sala no es válida.',
  _ =>
    'No pudimos completar la acción online. Revisa tu conexión e inténtalo otra vez.',
};

void _showRoomError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: PopText(onlineRoomErrorMessage(error))));
}

abstract final class _RoomColors {
  static const navy = Color(0xFF12234A);
  static const cloud = Color(0xFFF1F6FF);
  static const blue = Color(0xFF2E7BEA);
  static const purple = Color(0xFF7257E9);
  static const green = Color(0xFF31BE7B);
  static const red = Color(0xFFF45163);
  static const yellow = Color(0xFFFFC73D);

  static Color forSeat(LobbySeatColor color) => switch (color) {
    LobbySeatColor.red => red,
    LobbySeatColor.green => green,
    LobbySeatColor.yellow => yellow,
    LobbySeatColor.blue => blue,
  };
}

abstract final class _RoomStyles {
  static ButtonStyle primaryButton(Color color) => FilledButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(54),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );

  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(54),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
    textStyle: const TextStyle(fontWeight: FontWeight.w900),
  );
}
