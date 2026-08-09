import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_language.dart';
import 'app_availability.dart';
import 'cosmetic_visuals.dart';
import 'feature_rollout.dart';
import 'game_analytics.dart';
import 'game_audio.dart';
import 'game_engine.dart';
import 'game_feedback.dart';
import 'game_guide.dart';
import 'game_interaction_state.dart';
import 'mobile_ads.dart';
import 'online_match.dart';
import 'orientation_policy.dart';
import 'player_auth.dart';
import 'player_progression.dart';
import 'progress_hub.dart';
import 'safe_chat.dart';
import 'tutorial_controller.dart';
import 'tutorial_scenario.dart';
import 'wallet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await enableFlexibleOrientation();
  final analytics = await initializeGameAnalytics();
  final adsController = createAppAdsController();
  final availability = await AppAvailabilityService.load();
  runApp(
    ParchesePopApp(
      analytics: analytics,
      adsController: adsController,
      availability: availability,
    ),
  );
}

class PopColors {
  static const blue = Color(0xFF2474E5);
  static const red = Color(0xFFF04452);
  static const yellow = Color(0xFFFFC83D);
  static const green = Color(0xFF32B875);
  static const navy = Color(0xFF17284D);
  static const ink = Color(0xFF243047);
  static const cloud = Color(0xFFF4F7FC);
}

class _PlatformGameFeedbackOutput implements GameFeedbackOutput {
  const _PlatformGameFeedbackOutput();

  @override
  Future<void> playSound(GameEventType eventType) =>
      gameAudio.playEvent(eventType);

  @override
  Future<void> playHaptic(GameHapticCue cue) => switch (cue) {
    GameHapticCue.light => HapticFeedback.selectionClick(),
    GameHapticCue.calm => HapticFeedback.lightImpact(),
    GameHapticCue.strong => HapticFeedback.heavyImpact(),
    GameHapticCue.success => HapticFeedback.mediumImpact(),
    GameHapticCue.celebration => HapticFeedback.vibrate(),
  };
}

/// Version of the logical board topology stored in active-match checkpoints.
/// Increment this whenever saved progress or loop indices change meaning.
const int activeMatchBoardLayoutVersion = 4;

const String settingsRollGuideKey = 'settings_roll_guide';
const String settingsDiceHandKey = 'settings_dice_hand';
const AppFeatureRollout appFeatureRollout = AppFeatureRollout.safeDefaults;
// Retained only in debug/test builds for the existing ad diagnostics. Release
// builds use the single post-match "double reward" offer.
const bool shopRewardedCoinsEnabled = !kReleaseMode;

String _newAnalyticsReference(String prefix) {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final entropy = math.Random().nextInt(0x7FFFFFFF).toRadixString(36);
  return '${prefix}_${timestamp}_$entropy';
}

enum DiceHandPreference { left, right }

DiceHandPreference diceHandPreferenceFromStorage(String? value) =>
    value == DiceHandPreference.left.name
    ? DiceHandPreference.left
    : DiceHandPreference.right;

/// Uses the more legible board artwork only on compact iOS/Android screens.
///
/// The game topology is deliberately identical on every platform.  This flag
/// only changes paint sizes and hit targets, so a phone match remains fully
/// compatible with tablets and desktop builds.
bool _usesCompactPhoneBoard(BuildContext context) {
  if (kIsWeb) return false;
  final platform = defaultTargetPlatform;
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
    return false;
  }
  final size = MediaQuery.maybeSizeOf(context);
  return size != null && size.shortestSide < 600;
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen({required this.availability});

  final AppAvailability availability;

  Future<void> _openUpdate() async {
    final url = availability.updateUrl.trim();
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final canOpenStore = availability.updateUrl.trim().isNotEmpty;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PopColors.blue, Color(0xFF6C49D8), PopColors.navy],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 18,
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundColor: PopColors.yellow,
                        child: Icon(
                          Icons.system_update_rounded,
                          size: 48,
                          color: PopColors.navy,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'New version available',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: PopColors.navy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        availability.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.35,
                          color: PopColors.ink,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: canOpenStore ? _openUpdate : null,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download the new app'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Installed version ${availability.installedVersion}',
                        style: const TextStyle(color: Color(0xFF68738A)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _twentyStepGuideColors = <Color>[
  Color(0xFF7C4DFF),
  Color(0xFF00AFC4),
  Color(0xFFD946EF),
  Color(0xFFFF7043),
];

Color _twentyStepGuideColor(int tokenId) =>
    _twentyStepGuideColors[tokenId % _twentyStepGuideColors.length];

String _formatMatchDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

Color _eventPlayerColor(PlayerColor color) => switch (color) {
  PlayerColor.red => PopColors.red,
  PlayerColor.green => PopColors.green,
  PlayerColor.yellow => PopColors.yellow,
  PlayerColor.blue => PopColors.blue,
};

@visibleForTesting
bool resolveTrapDiagnosticsVisibility({
  required bool isDebugBuild,
  bool? requested,
}) => isDebugBuild && (requested ?? false);

Color _moveChoiceColor(List<int> rolledDice, int value) {
  final firstMatches = rolledDice.isNotEmpty && rolledDice.first == value;
  final secondMatches = rolledDice.length > 1 && rolledDice[1] == value;
  if (firstMatches && !secondMatches) return PopColors.blue;
  if (secondMatches && !firstMatches) return PopColors.red;
  if (!firstMatches && !secondMatches && value == 20) {
    return const Color(0xFFFF8A24);
  }
  if (!firstMatches && !secondMatches && value == 10) {
    return PopColors.green;
  }
  return const Color(0xFF7057FF);
}

class _AutoFitSingleLineText extends StatelessWidget {
  const _AutoFitSingleLineText(
    this.text, {
    super.key,
    this.style,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: PopText(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
        style: style,
      ),
    ),
  );
}

String _participantRoleLabel(
  OnlineParticipant participant, {
  bool uppercase = false,
}) {
  final label = switch (participant.kind) {
    ParticipantKind.local => 'Tú',
    ParticipantKind.remoteHuman => 'Rival online',
    ParticipantKind.virtual => 'CPU',
    ParticipantKind.humanTakenOver => 'CPU temporal',
  };
  return uppercase ? label.toUpperCase() : label;
}

bool _sessionHasRemoteHuman(OnlineMatchSession? session) =>
    session?.participants.any(
      (participant) => participant.kind == ParticipantKind.remoteHuman,
    ) ??
    false;

MatchPlayType _playTypeForSession(OnlineMatchSession? session) =>
    _sessionHasRemoteHuman(session) ? MatchPlayType.online : MatchPlayType.cpu;

String _cosmeticGlyph(String productId) {
  if (productId.startsWith('theme_')) return '🎨';
  if (productId.startsWith('dice_')) return '🎲';
  if (productId.startsWith('tokens_')) return '⭐';
  return '★';
}

@immutable
class MoveDestinationPreview {
  const MoveDestinationPreview({
    required this.token,
    required this.value,
    required this.cell,
    required this.color,
    required this.owner,
    required this.isExit,
    required this.isHomeEntryCapture,
    required this.isHomeLane,
    required this.isGoal,
    required this.overview,
    this.usesAllDice = false,
    this.loopIndex,
    this.captureCell,
    this.captureTarget,
  });

  final GameToken token;
  final int value;
  final Offset cell;
  final Color color;
  final PlayerColor owner;
  final bool isExit;
  final bool isHomeEntryCapture;
  final bool isHomeLane;
  final bool isGoal;
  final bool overview;
  final bool usesAllDice;
  final int? loopIndex;
  final Offset? captureCell;
  final GameToken? captureTarget;
}

List<MoveDestinationPreview> _moveDestinationPreviews(
  GameEngine engine,
  GameToken? token,
) {
  if (engine.effectResolving || engine.gameOver || !engine.hasRolled) {
    return const <MoveDestinationPreview>[];
  }
  final overview =
      token == null &&
      engine.currentPlayer.isHuman &&
      engine.remainingDice.contains(20);
  final candidates = token != null
      ? <GameToken>[token]
      : overview
      ? engine.currentPlayer.tokens
            .where((candidate) => engine.canMove(candidate, 20))
            .toList()
      : const <GameToken>[];
  final previews = <MoveDestinationPreview>[];
  for (final candidate in candidates) {
    final values = overview
        ? const <int>[20]
        : engine.legalDieValuesFor(candidate);
    for (final value in values) {
      final destinationProgress = engine.destinationProgressFor(
        candidate,
        value,
      );
      final cell = engine.destinationCellFor(candidate, value);
      if (destinationProgress == null || cell == null) continue;
      final isExit = candidate.inNest && value == 5;
      final isHomeEntryCapture = engine.isHomeEntryCaptureMove(
        candidate,
        value,
      );
      final isGoal = destinationProgress >= GameEngine.finishProgress;
      final isHomeLane =
          destinationProgress >= GameEngine.commonPathLength && !isGoal;
      final captureTarget = engine.captureTargetFor(candidate, value);
      previews.add(
        MoveDestinationPreview(
          token: candidate,
          value: value,
          cell: cell,
          color: value == 20
              ? _twentyStepGuideColor(candidate.id)
              : _moveChoiceColor(engine.dice, value),
          owner: candidate.owner,
          isExit: isExit,
          isHomeEntryCapture: isHomeEntryCapture,
          isHomeLane: isHomeLane,
          isGoal: isGoal,
          overview: overview,
          loopIndex: destinationProgress < GameEngine.commonPathLength
              ? engine.loopIndex(candidate.owner, destinationProgress)
              : null,
          captureCell: isHomeEntryCapture
              ? GameEngine.loop[GameEngine.homeEntryOffset[candidate.owner]!]
              : null,
          captureTarget: captureTarget,
        ),
      );
    }
    if (!overview) {
      final total = engine.allDiceTotalFor(candidate);
      final destinationProgress = engine.destinationProgressUsingAllDice(
        candidate,
      );
      final cell = engine.destinationCellUsingAllDice(candidate);
      if (total != null && destinationProgress != null && cell != null) {
        final isGoal = destinationProgress >= GameEngine.finishProgress;
        previews.add(
          MoveDestinationPreview(
            token: candidate,
            value: total,
            cell: cell,
            color: const Color(0xFF7057FF),
            owner: candidate.owner,
            isExit: false,
            isHomeEntryCapture: false,
            isHomeLane:
                destinationProgress >= GameEngine.commonPathLength && !isGoal,
            isGoal: isGoal,
            overview: false,
            usesAllDice: true,
            loopIndex: destinationProgress < GameEngine.commonPathLength
                ? engine.loopIndex(candidate.owner, destinationProgress)
                : null,
            captureTarget: engine.captureTargetUsingAllDice(candidate),
          ),
        );
      }
    }
  }
  return previews;
}

class _BoardGeometry {
  _BoardGeometry(double side, {this.compactPhone = false})
    : cell =
          side /
          (gridCells +
              (compactPhone ? compactFrameGutterCells : frameGutterCells) * 2),
      inset =
          (compactPhone ? compactFrameGutterCells : frameGutterCells) *
          side /
          (gridCells +
              (compactPhone ? compactFrameGutterCells : frameGutterCells) * 2);

  static const double gridCells = 20;
  static const double frameGutterCells = .26;
  // Keep just enough breathing room for the double frame on compact phones.
  // The minimap provides the close inspection that compact phones need while
  // the complete 68-space topology remains identical on every platform.
  static const double compactFrameGutterCells = .08;

  final bool compactPhone;
  final double cell;
  final double inset;

  Offset toPixel(Offset logical) =>
      Offset(inset + logical.dx * cell, inset + logical.dy * cell);

  Offset toLogical(Offset pixel) =>
      Offset((pixel.dx - inset) / cell, (pixel.dy - inset) / cell);
}

enum _MobileBoardCameraMode { fullBoard, manual }

// Preserve the same apparent cell size that the former 18×18 board reached at
// 1.8× zoom: the complete 20×20 board therefore uses a proportional 2× zoom.
const double _mobileBoardZoomScale = 2.0;

@visibleForTesting
Offset clampMobileBoardFocusForTesting(
  Offset focus, {
  double zoomScale = _mobileBoardZoomScale,
}) {
  final halfViewport = .5 / zoomScale;
  return Offset(
    focus.dx.clamp(halfViewport, 1 - halfViewport).toDouble(),
    focus.dy.clamp(halfViewport, 1 - halfViewport).toDouble(),
  );
}

@visibleForTesting
Rect mobileBoardViewportRectForTesting({
  required Size size,
  required Offset focus,
  bool fullBoard = false,
  double zoomScale = _mobileBoardZoomScale,
}) {
  if (fullBoard) return Offset.zero & size;
  final clamped = clampMobileBoardFocusForTesting(focus, zoomScale: zoomScale);
  final viewportSize = Size(size.width / zoomScale, size.height / zoomScale);
  return Rect.fromCenter(
    center: Offset(clamped.dx * size.width, clamped.dy * size.height),
    width: viewportSize.width,
    height: viewportSize.height,
  );
}

@visibleForTesting
Offset safeStarPaintNudgeForTesting(
  int loopIndex, {
  required bool compactPhone,
}) {
  if (!compactPhone) return Offset.zero;
  return switch (loopIndex) {
    // The compact-phone double frame is intentionally very close to the
    // route. Nudge only the four exterior safe stars inward so their points
    // stay fully visible without changing the logical cell or its hit area.
    // The lower star needs a little more clearance because its shadow falls
    // downward; the other three need only the frame's visual overlap removed.
    12 => const Offset(0, -.16),
    29 => const Offset(-.12, 0),
    46 => const Offset(0, .12),
    63 => const Offset(.12, 0),
    _ => Offset.zero,
  };
}

/// Returns the owner of the seventeen-space exterior sector surrounding each
/// colored base. Red owns the visible run 64–68 and 1–12 around its
/// lower-left base; the remaining equal sectors continue clockwise. This is
/// visual ownership only, so movement rules and logical positions do not
/// change with cosmetics.
@visibleForTesting
PlayerColor visualSectorOwnerForLoopIndex(int loopIndex) {
  final index = loopIndex % GameEngine.loop.length;
  final normalized = index < 0 ? index + GameEngine.loop.length : index;
  if (normalized <= 11 || normalized >= 63) return PlayerColor.red;
  if (normalized <= 28) return PlayerColor.green;
  if (normalized <= 45) return PlayerColor.yellow;
  return PlayerColor.blue;
}

Path? _transitionTrackPath(int index, double cell) {
  final points = switch (index) {
    3 => const [Offset(7, 11), Offset(8, 11), Offset(8, 12), Offset(7, 13)],
    4 => const [Offset(8, 12), Offset(9, 12), Offset(9, 13), Offset(7, 13)],
    20 => const [
      Offset(11, 12),
      Offset(12, 12),
      Offset(13, 13),
      Offset(11, 13),
    ],
    21 => const [
      Offset(12, 11),
      Offset(13, 11),
      Offset(13, 13),
      Offset(12, 12),
    ],
    37 => const [Offset(12, 8), Offset(13, 7), Offset(13, 9), Offset(12, 9)],
    38 => const [Offset(11, 7), Offset(13, 7), Offset(12, 8), Offset(11, 8)],
    54 => const [Offset(7, 7), Offset(9, 7), Offset(9, 8), Offset(8, 8)],
    55 => const [Offset(7, 7), Offset(8, 8), Offset(8, 9), Offset(7, 9)],
    _ => null,
  };
  if (points == null) return null;
  final path = Path()..moveTo(points.first.dx * cell, points.first.dy * cell);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx * cell, point.dy * cell);
  }
  return path..close();
}

Rect _boardTrackRect(Offset center, double cell) {
  final vertical =
      center.dx == 8 ||
      center.dx == 12 ||
      (center.dx == 10 && (center.dy == .5 || center.dy == 19.5));
  final width = vertical ? 2.0 : 1.0;
  final height = vertical ? 1.0 : 2.0;
  return Rect.fromCenter(
    center: center * cell,
    width: width * cell,
    height: height * cell,
  );
}

Rect _boardHomeRect(PlayerColor color, Offset center, double cell) {
  final vertical = color == PlayerColor.blue || color == PlayerColor.green;
  return Rect.fromCenter(
    center: center * cell,
    width: (vertical ? 2 : 1) * cell,
    height: (vertical ? 1 : 2) * cell,
  );
}

Path _boardGoalPath(PlayerColor owner, double cell) {
  final points = switch (owner) {
    PlayerColor.red => const [Offset(8, 8), Offset(10, 10), Offset(8, 12)],
    PlayerColor.green => const [Offset(8, 12), Offset(10, 10), Offset(12, 12)],
    PlayerColor.yellow => const [Offset(12, 12), Offset(10, 10), Offset(12, 8)],
    PlayerColor.blue => const [Offset(12, 8), Offset(10, 10), Offset(8, 8)],
  };
  final path = Path()..moveTo(points.first.dx * cell, points.first.dy * cell);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx * cell, point.dy * cell);
  }
  return path..close();
}

Path _moveDestinationPath(MoveDestinationPreview preview, double cell) {
  if (preview.isGoal) return _boardGoalPath(preview.owner, cell);
  if (preview.isHomeLane) {
    return Path()..addRect(_boardHomeRect(preview.owner, preview.cell, cell));
  }
  final index = preview.loopIndex!;
  return _transitionTrackPath(index, cell) ??
      (Path()..addRect(_boardTrackRect(GameEngine.loop[index], cell)));
}

Map<GameToken, Offset> _displayTokenCells(
  GameEngine engine, {
  bool compactPhone = false,
}) {
  const nestOrigins = {
    PlayerColor.blue: Offset(0, 0),
    PlayerColor.yellow: Offset(13, 0),
    PlayerColor.red: Offset(0, 13),
    PlayerColor.green: Offset(13, 13),
  };
  const nestSlots = [
    Offset(2.5, 2.5),
    Offset(4.5, 2.5),
    Offset(2.5, 4.5),
    Offset(4.5, 4.5),
  ];
  final result = <GameToken, Offset>{};
  final occupiedCells = <Offset, List<GameToken>>{};

  for (final player in engine.players) {
    final finishedTokens =
        player.tokens.where((token) => token.finished).toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
    final finishedSlotByToken = <GameToken, int>{
      for (var index = 0; index < finishedTokens.length; index++)
        finishedTokens[index]: index,
    };
    for (final token in player.tokens) {
      if (token.inNest) {
        result[token] = nestOrigins[token.owner]! + nestSlots[token.id];
      } else if (token.finished) {
        // Completed pieces leave the shared center clear. Keep them visibly
        // separated from pieces that have not started by filing them down the
        // screen-left edge of their own base, in finishing-token order.
        final slot = finishedSlotByToken[token]!;
        final columnStart = switch (token.owner) {
          PlayerColor.blue || PlayerColor.yellow => 1.60,
          PlayerColor.red || PlayerColor.green => 1.05,
        };
        result[token] =
            nestOrigins[token.owner]! + Offset(.72, columnStart + slot * 1.05);
      } else {
        final cell = engine.tokenCell(token)!;
        result[token] = cell;
        occupiedCells.putIfAbsent(cell, () => <GameToken>[]).add(token);
      }
    }
  }

  for (final entry in occupiedCells.entries) {
    if (entry.value.length != 2) continue;
    final tokens = entry.value
      ..sort(
        (a, b) =>
            (a.owner.index * 4 + a.id).compareTo(b.owner.index * 4 + b.id),
      );
    final sample = tokens.first;
    late final Offset axis;
    if (sample.progress < GameEngine.commonPathLength) {
      final index = engine.loopIndex(sample.owner, sample.progress);
      if (const {4, 20, 38, 54}.contains(index)) {
        axis = const Offset(1, 0);
      } else if (const {3, 21, 37, 55}.contains(index)) {
        axis = const Offset(0, 1);
      } else {
        final center = GameEngine.loop[index];
        final isWide =
            center.dx == 8 ||
            center.dx == 12 ||
            (center.dx == 10 && (center.dy == .5 || center.dy == 19.5));
        axis = isWide ? const Offset(1, 0) : const Offset(0, 1);
      }
    } else {
      final isWide =
          sample.owner == PlayerColor.blue || sample.owner == PlayerColor.green;
      axis = isWide ? const Offset(1, 0) : const Offset(0, 1);
    }
    final barrierOffset = compactPhone ? .50 : .47;
    result[tokens.first] = entry.key - axis * barrierOffset;
    result[tokens.last] = entry.key + axis * barrierOffset;
  }

  return result;
}

@visibleForTesting
Map<GameToken, Offset> displayTokenCellsForTesting(
  GameEngine engine, {
  bool compactPhone = false,
}) => _displayTokenCells(engine, compactPhone: compactPhone);

class PlayerProfile {
  const PlayerProfile({
    required this.name,
    required this.email,
    required this.flag,
    this.level = 1,
  });

  final String name;
  final String email;
  final String flag;
  final int level;

  bool get isGuest => email.isEmpty;

  static const guest = PlayerProfile(name: 'Invitado', email: '', flag: '🎮');
}

OnlineMatchSession? _restoreOnlineSession(Map<String, dynamic> checkpoint) {
  if (checkpoint['online'] != true) return null;
  final rawParticipants = checkpoint['onlineParticipants'] as List<dynamic>?;
  if (rawParticipants == null ||
      rawParticipants.length != PlayerColor.values.length) {
    return null;
  }
  try {
    return OnlineMatchSession(
      matchId:
          'restored-${checkpoint['savedAt'] ?? DateTime.now().millisecondsSinceEpoch}',
      seed: 0,
      mode: checkpoint['mode'] == GameMode.chaos.name
          ? GameMode.chaos
          : GameMode.traditional,
      participants: rawParticipants.whereType<Map>().map((entry) {
        final color = PlayerColor.values.firstWhere(
          (value) => value.name == entry['color'],
        );
        final kind = ParticipantKind.values.firstWhere(
          (value) => value.name == entry['kind'],
          orElse: () => color == PlayerColor.red
              ? ParticipantKind.local
              : ParticipantKind.virtual,
        );
        return OnlineParticipant(
          id: entry['id'] as String,
          displayName: entry['displayName'] as String,
          flag: entry['flag'] as String,
          avatarId: entry['avatarId'] as String,
          level: entry['level'] as int? ?? 1,
          color: color,
          kind: kind,
          loadout: CosmeticLoadout(
            themeId: entry['themeId'] as String?,
            diceId: entry['diceId'] as String?,
            tokensId: entry['tokensId'] as String?,
          ),
        );
      }),
    );
  } catch (_) {
    return null;
  }
}

class ParchesePopApp extends StatefulWidget {
  const ParchesePopApp({
    super.key,
    this.analytics = const NoopGameAnalytics(),
    this.adsController,
    this.audioController,
    this.availability = AppAvailability.available,
  });

  final GameAnalytics analytics;
  final AppAdsController? adsController;
  final GameAudioController? audioController;
  final AppAvailability availability;

  @override
  State<ParchesePopApp> createState() => _ParchesePopAppState();
}

class _ParchesePopAppState extends State<ParchesePopApp>
    with WidgetsBindingObserver {
  final WalletController wallet = WalletController();
  final PlayerProgressionController progression = PlayerProgressionController();
  final AppLanguageController language = AppLanguageController();
  late final AppAdsController adsController;
  LocalPlayerAuthGateway? authGateway;
  TutorialController? tutorial;
  PlayerProfile? profile;
  GameEngine? interruptedMatch;
  OnlineMatchSession? interruptedOnlineSession;
  String? interruptedAnalyticsMatchRef;
  DateTime? interruptedMatchSavedAt;
  bool interruptedFirstRollAnalyticsLogged = false;
  String? interruptedMatchOpponent;
  Duration interruptedMatchElapsed = Duration.zero;
  bool loading = true;
  bool restoringSavedMatch = false;

  GameAudioController get audioController =>
      widget.audioController ?? gameAudio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    adsController = widget.adsController ?? NoopAppAdsController();
    unawaited(adsController.initialize());
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeAudio());
    });
  }

  Future<void> _initializeAudio() async {
    await audioController.initialize();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (!mounted || lifecycleState == null) return;
    await audioController.handleAppLifecycleState(lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(audioController.handleAppLifecycleState(state));
    if (state == AppLifecycleState.resumed) {
      adsController.preloadRewarded();
    }
  }

  Future<void> _loadProfile() async {
    final store = await SharedPreferences.getInstance();
    final localAuth = await LocalPlayerAuthGateway.create();
    await Future.wait([
      wallet.initialize(),
      progression.initialize(),
      language.initialize(),
    ]);
    // Progression and wallet persist independently. Replaying deterministic
    // credits repairs the narrow crash window between awarding a mission and
    // storing its wallet balance; WalletController rejects every duplicate.
    if (wallet.creditLedgerNeedsReconciliation) {
      await wallet.reconcileKnownCredits(
        progression.transactions.map((transaction) => transaction.id),
      );
    }
    for (final transaction in progression.transactions) {
      await wallet.applyCredit(
        transactionId: transaction.id,
        amount: transaction.amount,
      );
    }
    tutorial = await TutorialController.create(
      analytics: widget.analytics,
      preferences: store,
      correlation: AnalyticsCorrelation(
        anonymousSessionId: _newAnalyticsReference('tutorial_session'),
      ),
    );
    authGateway = localAuth;
    final name = store.getString('profile_name');
    if (name != null && mounted) {
      profile = PlayerProfile(
        name: name,
        email: store.getString('profile_email') ?? '',
        flag: store.getString('profile_flag') ?? '🇩🇴',
        level: store.getInt('profile_level') ?? 1,
      );
    }
    // Checkpoints from the compact 60-space board use incompatible positions.
    // Migrate once to the restored complete board by safely discarding them.
    final savedBoardLayout =
        store.getInt('active_match_board_layout_version') ?? 1;
    if (savedBoardLayout != activeMatchBoardLayoutVersion) {
      await store.remove('active_match_checkpoint');
      await store.setInt(
        'active_match_board_layout_version',
        activeMatchBoardLayoutVersion,
      );
    }
    final savedMatch = store.getString('active_match_checkpoint');
    if (savedMatch != null) {
      try {
        final checkpoint = jsonDecode(savedMatch) as Map<String, dynamic>;
        interruptedMatch = GameEngine.fromCheckpoint(checkpoint);
        interruptedOnlineSession = _restoreOnlineSession(checkpoint);
        interruptedAnalyticsMatchRef =
            checkpoint['analyticsMatchRef'] as String? ??
            _newAnalyticsReference('restored_match');
        interruptedMatchSavedAt = DateTime.tryParse(
          checkpoint['savedAt'] as String? ?? '',
        );
        interruptedFirstRollAnalyticsLogged =
            checkpoint['analyticsFirstRollLogged'] as bool? ?? false;
        interruptedMatchOpponent = checkpoint['opponent'] as String?;
        interruptedMatchElapsed = Duration(
          seconds: checkpoint['elapsedSeconds'] as int? ?? 0,
        );
      } catch (_) {
        await store.remove('active_match_checkpoint');
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    wallet.dispose();
    progression.dispose();
    tutorial?.dispose();
    language.dispose();
    adsController.dispose();
    authGateway?.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(PlayerProfile value) async {
    if (mounted) setState(() => profile = value);
    final store = await SharedPreferences.getInstance();
    await store.setString('profile_name', value.name);
    await store.setString('profile_email', value.email);
    await store.setString('profile_flag', value.flag);
    await store.setInt('profile_level', value.level);
  }

  Future<void> _discardDeletedLocalData() async {
    interruptedMatch?.dispose();
    if (!mounted) return;
    setState(() {
      profile = null;
      interruptedMatch = null;
      interruptedOnlineSession = null;
      interruptedAnalyticsMatchRef = null;
      interruptedMatchSavedAt = null;
      interruptedFirstRollAnalyticsLogged = false;
      interruptedMatchOpponent = null;
      interruptedMatchElapsed = Duration.zero;
      restoringSavedMatch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MobileAdsScope(
      controller: adsController,
      child: AppLanguageScope(
        controller: language,
        child: AnimatedBuilder(
          animation: language,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Parchís Pop',
            locale: language.localeOverride,
            supportedLocales: const [Locale('es'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            localeResolutionCallback: (locale, supportedLocales) {
              final languageCode = locale?.languageCode;
              if (languageCode == 'en') return const Locale('en');
              if (languageCode == 'es') return const Locale('es');
              return const Locale('es');
            },
            builder: (context, child) => MobileAdShell(
              controller: adsController,
              child: child ?? const SizedBox.shrink(),
            ),
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: PopColors.blue,
                primary: PopColors.blue,
                secondary: PopColors.yellow,
                surface: Colors.white,
              ),
              scaffoldBackgroundColor: PopColors.cloud,
              textTheme: ThemeData.light().textTheme.apply(
                bodyColor: PopColors.ink,
                displayColor: PopColors.navy,
                fontFamily: 'Arial',
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            home: !widget.availability.isAvailable
                ? _UpdateRequiredScreen(availability: widget.availability)
                : loading
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : _buildHomeScreen(),
            routes: {
              '/home': (_) => loading
                  ? const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    )
                  : _buildHomeScreen(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHomeScreen() {
    return HomeScreen(
      profile: profile ?? PlayerProfile.guest,
      onProfileChanged: _saveProfile,
      wallet: wallet,
      progression: progression,
      tutorial: tutorial,
      authGateway: authGateway!,
      analytics: widget.analytics,
      onResumeMatch: interruptedMatch == null ? null : _resumeSavedMatch,
      onLocalDataDeleted: _discardDeletedLocalData,
    );
  }

  Future<void> _resumeSavedMatch(BuildContext context) async {
    if (restoringSavedMatch || interruptedMatch == null) return;
    restoringSavedMatch = true;
    if (!mounted || !context.mounted || interruptedMatch == null) {
      restoringSavedMatch = false;
      return;
    }

    final resumedEngine = interruptedMatch!;
    final resumedOnlineSession = interruptedOnlineSession;
    final matchRef =
        interruptedAnalyticsMatchRef ??
        _newAnalyticsReference('restored_match');
    final resumeSecondsAway = interruptedMatchSavedAt == null
        ? null
        : math.max(
            0,
            DateTime.now().difference(interruptedMatchSavedAt!).inSeconds,
          );
    final analyticsMatch = MatchAnalyticsContext(
      playType: _playTypeForSession(resumedOnlineSession),
      mode: resumedEngine.mode,
      matchFormat: resumedEngine.matchFormat,
      correlation: AnalyticsCorrelation(anonymousMatchId: matchRef),
    );
    try {
      // Preserve event order: an attempted resume must reach analytics before
      // the resumed GameScreen can report success.
      await widget.analytics.logEvent(
        MatchResumeEvent(
          match: analyticsMatch,
          stage: MatchResumeStage.attempted,
          secondsAway: resumeSecondsAway,
        ),
      );
      if (!mounted || !context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GameScreen(
            opponent: interruptedMatchOpponent ?? 'Partida guardada',
            gameEngine: resumedEngine,
            wallet: wallet,
            progression: appFeatureRollout.retentionRewards
                ? progression
                : null,
            tutorial: tutorial,
            localProfile: profile,
            onlineSession: resumedOnlineSession,
            analytics: widget.analytics,
            analyticsMatchRef: matchRef,
            analyticsFirstRollLogged: interruptedFirstRollAnalyticsLogged,
            isResumedMatch: true,
            resumeSecondsAway: resumeSecondsAway,
            initialElapsed: interruptedMatchElapsed,
          ),
        ),
      );

      // The game route may have discarded or replaced its checkpoint. Keep
      // the Home resume action in sync instead of offering stale progress.
      final store = await SharedPreferences.getInstance();
      final savedMatch = store.getString('active_match_checkpoint');
      if (savedMatch == null) {
        interruptedMatch = null;
        interruptedOnlineSession = null;
        interruptedAnalyticsMatchRef = null;
        interruptedMatchSavedAt = null;
        interruptedFirstRollAnalyticsLogged = false;
        interruptedMatchOpponent = null;
        interruptedMatchElapsed = Duration.zero;
      } else {
        try {
          final checkpoint = jsonDecode(savedMatch) as Map<String, dynamic>;
          interruptedAnalyticsMatchRef =
              checkpoint['analyticsMatchRef'] as String? ?? matchRef;
          interruptedMatchSavedAt = DateTime.tryParse(
            checkpoint['savedAt'] as String? ?? '',
          );
          interruptedFirstRollAnalyticsLogged =
              checkpoint['analyticsFirstRollLogged'] as bool? ?? false;
          interruptedMatchOpponent = checkpoint['opponent'] as String?;
          interruptedMatchElapsed = Duration(
            seconds: checkpoint['elapsedSeconds'] as int? ?? 0,
          );
        } catch (_) {
          await store.remove('active_match_checkpoint');
          interruptedMatch = null;
          interruptedOnlineSession = null;
        }
      }
      if (mounted) setState(() {});
    } finally {
      restoringSavedMatch = false;
    }
  }
}

class PopBackground extends StatelessWidget {
  const PopBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF3FF), Color(0xFFFFFAE8), Color(0xFFEAFBF4)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              top: -70,
              right: -60,
              child: _Bubble(PopColors.yellow, 190),
            ),
            const Positioned(
              bottom: -90,
              left: -70,
              child: _Bubble(PopColors.blue, 220),
            ),
            SafeArea(child: child),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.color, this.size);
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .16),
      shape: BoxShape.circle,
    ),
  );
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.onSaved,
    this.initial,
    this.authGateway,
  });
  final ValueChanged<PlayerProfile> onSaved;
  final PlayerProfile? initial;
  final PlayerAuthGateway? authGateway;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController name = TextEditingController(
    text: widget.initial?.name,
  );
  late final TextEditingController email = TextEditingController(
    text: widget.initial?.email,
  );
  final TextEditingController password = TextEditingController();
  final TextEditingController passwordConfirmation = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String flag = '🇩🇴';
  bool obscurePassword = true;
  bool submitting = false;
  static const flags = [
    '🇩🇴',
    '🇺🇸',
    '🇵🇷',
    '🇲🇽',
    '🇨🇴',
    '🇪🇸',
    '🇧🇷',
    '🇨🇦',
    '🇫🇷',
    '🇮🇹',
  ];
  static const blocked = ['puta', 'mierda', 'fuck', 'bitch'];

  @override
  void initState() {
    super.initState();
    flag = widget.initial?.flag ?? flag;
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    passwordConfirmation.dispose();
    super.dispose();
  }

  bool get needsAccountRegistration =>
      widget.authGateway != null &&
      (widget.initial == null || widget.authGateway?.currentAccount == null);

  String? _validateName(BuildContext context, String? value) {
    final clean = (value ?? '').trim();
    if (clean.length < 3 || clean.length > 12) {
      return appTranslate(context, 'Usa entre 3 y 12 caracteres.');
    }
    if (!RegExp(r"^[a-zA-ZÀ-ÿ0-9 _-]+$").hasMatch(clean)) {
      return appTranslate(context, 'Usa letras, números, espacios, _ o -.');
    }
    final lower = clean.toLowerCase();
    if (blocked.any(lower.contains)) {
      return appTranslate(context, 'Ese nombre no está permitido.');
    }
    return null;
  }

  String? _validatePassword(BuildContext context, String? value) {
    if (!needsAccountRegistration) return null;
    final issues = PlayerCredentialValidator.validatePassword(
      value ?? '',
      confirmation: passwordConfirmation.text,
    );
    if (issues.isEmpty) return null;
    if (issues.contains(CredentialIssue.passwordsDoNotMatch)) {
      return appTranslate(context, 'Las contraseñas no coinciden.');
    }
    return appTranslate(
      context,
      'Usa 8 caracteres con mayúscula, minúscula y número.',
    );
  }

  PlayerAuthPlatform get _authPlatform {
    if (kIsWeb) return PlayerAuthPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => PlayerAuthPlatform.ios,
      TargetPlatform.android => PlayerAuthPlatform.android,
      TargetPlatform.macOS => PlayerAuthPlatform.macos,
      TargetPlatform.windows => PlayerAuthPlatform.windows,
      TargetPlatform.linux => PlayerAuthPlatform.linux,
      TargetPlatform.fuchsia => PlayerAuthPlatform.unknown,
    };
  }

  void _showAuthError(Object error) {
    if (!mounted) return;
    final message = error is PlayerAuthException
        ? error.message
        : 'No se pudo completar el registro.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: PopText(message)));
  }

  Future<void> _saveWithEmail() async {
    if (submitting || !formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    try {
      if (needsAccountRegistration && widget.authGateway != null) {
        await widget.authGateway!.registerWithEmail(
          email: email.text,
          password: password.text,
        );
      }
      if (!mounted) return;
      widget.onSaved(
        PlayerProfile(
          name: name.text.trim(),
          email: email.text.trim().toLowerCase(),
          flag: flag,
          level: widget.initial?.level ?? 1,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      _showAuthError(error);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _continueWithProvider(PlayerAuthMethod method) async {
    if (submitting || widget.authGateway == null) return;
    final nameIssue = _validateName(context, name.text);
    if (nameIssue != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: PopText(nameIssue)));
      return;
    }
    setState(() => submitting = true);
    try {
      final account = method == PlayerAuthMethod.apple
          ? await widget.authGateway!.signInWithApple()
          : await widget.authGateway!.signInWithGoogle();
      if (!mounted) return;
      widget.onSaved(
        PlayerProfile(
          name: name.text.trim(),
          email: account.email,
          flag: flag,
          level: widget.initial?.level ?? 1,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      _showAuthError(error);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authMethods = PlayerAuthPolicy.methodsFor(_authPlatform);
    return Scaffold(
      backgroundColor: PopColors.navy,
      body: _HomeArcadeBackdrop(
        animation: const AlwaysStoppedAnimation<double>(1),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  elevation: 16,
                  shadowColor: const Color(0x6607132D),
                  color: Colors.white.withValues(alpha: .97),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: const BorderSide(color: Colors.white, width: 3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                key: const ValueKey('profile-edit-cancel'),
                                tooltip: appTranslate(context, 'Volver'),
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: PopText(
                                  'Parchís Pop',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: PopColors.navy,
                                  ),
                                ),
                              ),
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: PopColors.yellow,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: PopColors.navy,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          PopText(
                            widget.initial == null
                                ? 'Crea tu perfil de jugador'
                                : 'Edita tu perfil',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: name,
                            validator: (value) => _validateName(context, value),
                            maxLength: 12,
                            decoration: InputDecoration(
                              labelText: appTranslate(
                                context,
                                'Nombre de jugador',
                              ),
                              hintText: appTranslate(context, 'Ej. JuanPop'),
                              prefixIcon: const Icon(Icons.person_rounded),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              final clean = (value ?? '').trim();
                              if (clean.isEmpty) {
                                return appTranslate(
                                  context,
                                  'Escribe tu correo.',
                                );
                              }
                              if (!clean.contains('@') ||
                                  !clean.contains('.')) {
                                return appTranslate(
                                  context,
                                  'Escribe un correo válido.',
                                );
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              labelText: appTranslate(
                                context,
                                'Correo electrónico',
                              ),
                              prefixIcon: const Icon(Icons.email_rounded),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          if (needsAccountRegistration) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const ValueKey('profile-password'),
                              controller: password,
                              obscureText: obscurePassword,
                              validator: (value) =>
                                  _validatePassword(context, value),
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: appTranslate(context, 'Contraseña'),
                                helperText: appTranslate(
                                  context,
                                  '8+ caracteres, mayúscula, minúscula y número',
                                ),
                                prefixIcon: const Icon(Icons.lock_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const ValueKey(
                                'profile-password-confirmation',
                              ),
                              controller: passwordConfirmation,
                              obscureText: obscurePassword,
                              validator: (value) {
                                if ((value ?? '') != password.text) {
                                  return appTranslate(
                                    context,
                                    'Las contraseñas no coinciden.',
                                  );
                                }
                                return null;
                              },
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: appTranslate(
                                  context,
                                  'Confirmar contraseña',
                                ),
                                prefixIcon: const Icon(
                                  Icons.verified_user_rounded,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          const PopText(
                            'Elige tu bandera',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: flags
                                .map(
                                  (item) => ChoiceChip(
                                    label: PopText(
                                      item,
                                      style: const TextStyle(fontSize: 25),
                                    ),
                                    selected: flag == item,
                                    onSelected: (_) =>
                                        setState(() => flag = item),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            key: const ValueKey('profile-email-submit'),
                            onPressed: submitting ? null : _saveWithEmail,
                            icon: submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_rounded),
                            label: PopText(
                              widget.initial == null
                                  ? 'Crear cuenta con correo'
                                  : 'Guardar cambios',
                            ),
                          ),
                          if (needsAccountRegistration &&
                              (authMethods.contains(PlayerAuthMethod.google) ||
                                  authMethods.contains(
                                    PlayerAuthMethod.apple,
                                  ))) ...[
                            const SizedBox(height: 16),
                            const Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: PopText(
                                    'O CONTINÚA CON',
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (authMethods.contains(PlayerAuthMethod.google))
                              OutlinedButton.icon(
                                key: const ValueKey('profile-google-sign-in'),
                                onPressed: submitting
                                    ? null
                                    : () => _continueWithProvider(
                                        PlayerAuthMethod.google,
                                      ),
                                icon: const Icon(Icons.g_mobiledata_rounded),
                                label: const PopText(
                                  'Continuar con Google',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            if (authMethods.contains(
                              PlayerAuthMethod.apple,
                            )) ...[
                              const SizedBox(height: 9),
                              FilledButton.icon(
                                key: const ValueKey('profile-apple-sign-in'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: submitting
                                    ? null
                                    : () => _continueWithProvider(
                                        PlayerAuthMethod.apple,
                                      ),
                                icon: const Icon(Icons.apple_rounded),
                                label: const PopText(
                                  'Continuar con Apple',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 10),
                          const PopText(
                            'La cuenta es opcional, permanece en este dispositivo y la contraseña nunca se guarda como texto.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.profile,
    required this.onProfileChanged,
    required this.wallet,
    required this.authGateway,
    this.progression,
    this.tutorial,
    this.analytics = const NoopGameAnalytics(),
    this.onResumeMatch,
    this.onLocalDataDeleted,
  });
  final PlayerProfile profile;
  final ValueChanged<PlayerProfile> onProfileChanged;
  final WalletController wallet;
  final PlayerProgressionController? progression;
  final TutorialController? tutorial;
  final PlayerAuthGateway authGateway;
  final GameAnalytics analytics;
  final void Function(BuildContext context)? onResumeMatch;
  final Future<void> Function()? onLocalDataDeleted;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController entranceController;
  bool entranceStarted = false;

  @override
  void initState() {
    super.initState();
    entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (entranceStarted) return;
    entranceStarted = true;
    if (MediaQuery.of(context).disableAnimations) {
      entranceController.value = 1;
    } else {
      entranceController.forward();
    }
  }

  @override
  void dispose() {
    entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PopColors.navy,
      body: _HomeArcadeBackdrop(
        animation: CurvedAnimation(
          parent: entranceController,
          curve: Curves.easeOutCubic,
        ),
        child: SafeArea(
          child: PlayHome(
            profile: widget.profile,
            onProfileChanged: widget.onProfileChanged,
            wallet: widget.wallet,
            progression: widget.progression,
            tutorial: widget.tutorial,
            authGateway: widget.authGateway,
            analytics: widget.analytics,
            onResumeMatch: widget.onResumeMatch,
            onLocalDataDeleted: widget.onLocalDataDeleted,
          ),
        ),
      ),
    );
  }
}

class _HomeArcadeBackdrop extends StatelessWidget {
  const _HomeArcadeBackdrop({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF092B68), Color(0xFF245DBA), Color(0xFF5839A8)],
          stops: [0, .53, 1],
        ),
      ),
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = animation.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                key: const ValueKey('home-animated-decoration'),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _HomeArcadeBackdropPainter(progress),
                  ),
                ),
              ),
              Opacity(
                opacity: progress,
                child: Transform.translate(
                  offset: Offset(0, 18 * (1 - progress)),
                  child: child,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _HomeArcadeBackdropPainter extends CustomPainter {
  const _HomeArcadeBackdropPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutBack.transform(progress.clamp(0, 1));
    _paintGlow(
      canvas,
      Offset(size.width * .11, size.height * .10),
      size.shortestSide * .42,
      PopColors.blue,
    );
    _paintGlow(
      canvas,
      Offset(size.width * .88, size.height * .08),
      size.shortestSide * .34,
      PopColors.yellow,
    );
    _paintGlow(
      canvas,
      Offset(size.width * .84, size.height * .90),
      size.shortestSide * .46,
      PopColors.red,
    );
    _paintGlow(
      canvas,
      Offset(size.width * .12, size.height * .88),
      size.shortestSide * .40,
      PopColors.green,
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .055 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final spacing = math.max(34.0, size.shortestSide * .075);
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), grid);
    }
    for (double x = 0; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), grid);
    }

    final cellSize = math.min(42.0, size.shortestSide * .052);
    final roadY = size.height * .67;
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: .045 * progress)
      ..style = PaintingStyle.fill;
    final roadLine = Paint()
      ..color = Colors.white.withValues(alpha: .12 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (double x = -cellSize; x < size.width + cellSize; x += cellSize) {
      final cell = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, roadY, cellSize - 3, cellSize - 3),
        const Radius.circular(7),
      );
      canvas.drawRRect(cell, roadPaint);
      canvas.drawRRect(cell, roadLine);
    }

    _paintToken(
      canvas,
      Offset(-28 + eased * (size.width * .055 + 28), size.height * .24),
      math.min(30, size.shortestSide * .036),
      PopColors.red,
      -0.15,
    );
    _paintToken(
      canvas,
      Offset(
        size.width + 30 - eased * (size.width * .07 + 30),
        size.height * .42,
      ),
      math.min(34, size.shortestSide * .040),
      PopColors.yellow,
      0.12,
    );
    _paintToken(
      canvas,
      Offset(
        size.width * .17,
        size.height + 32 - eased * (size.height * .075 + 32),
      ),
      math.min(27, size.shortestSide * .033),
      PopColors.green,
      0,
    );
    final portrait = size.height > size.width * 1.15;
    _paintPowerCube(
      canvas,
      Offset(
        size.width * (portrait ? .98 : .88),
        -40 + eased * (size.height * (portrait ? .51 : .20) + 40),
      ),
      math.min(46, size.shortestSide * .06),
      progress,
    );

    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: .20 * progress);
    _paintStar(
      canvas,
      Offset(size.width * .08, size.height * .55),
      math.min(18, size.shortestSide * .025),
      starPaint,
    );
    _paintStar(
      canvas,
      Offset(size.width * .91, size.height * .72),
      math.min(13, size.shortestSide * .019),
      starPaint,
    );
    _paintStar(
      canvas,
      Offset(size.width * .72, size.height * .16),
      math.min(10, size.shortestSide * .016),
      starPaint,
    );
  }

  void _paintGlow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: .24 * progress),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _paintToken(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double rotation,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .25 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(const Offset(0, 7), radius, shadow);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withValues(alpha: .72 * progress),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .78,
      Paint()
        ..color = Colors.white.withValues(alpha: .10 * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, radius * .12),
    );
    _paintStar(
      canvas,
      Offset.zero,
      radius * .43,
      Paint()..color = Colors.white.withValues(alpha: .82 * progress),
    );
    canvas.restore();
  }

  void _paintPowerCube(Canvas canvas, Offset center, double size, double turn) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((1 - turn) * -.55 + .12);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size,
      height: size,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 7)),
        Radius.circular(size * .24),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .22 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size * .24)),
      Paint()..color = PopColors.yellow.withValues(alpha: .86 * progress),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size * .08),
        Radius.circular(size * .18),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: .85 * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, size * .06),
    );
    final label = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: PopColors.navy.withValues(alpha: progress),
          fontSize: size * .60,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, -label.size.center(Offset.zero));
    canvas.restore();
  }

  void _paintStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final angle = -math.pi / 2 + index * math.pi / 5;
      final pointRadius = index.isEven ? radius : radius * .45;
      final point = center + Offset.fromDirection(angle, pointRadius);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HomeArcadeBackdropPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class PageShell extends StatelessWidget {
  const PageShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: child,
      ),
    ),
  );
}

class _PopRouteScaffold extends StatelessWidget {
  const _PopRouteScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PopColors.cloud,
    body: PopBackground(child: child),
  );
}

class PlayHome extends StatelessWidget {
  const PlayHome({
    super.key,
    required this.profile,
    required this.onProfileChanged,
    required this.wallet,
    required this.authGateway,
    this.progression,
    this.tutorial,
    this.analytics = const NoopGameAnalytics(),
    this.onResumeMatch,
    this.onLocalDataDeleted,
  });
  final PlayerProfile profile;
  final ValueChanged<PlayerProfile> onProfileChanged;
  final WalletController wallet;
  final PlayerProgressionController? progression;
  final TutorialController? tutorial;
  final PlayerAuthGateway authGateway;
  final GameAnalytics analytics;
  final void Function(BuildContext context)? onResumeMatch;
  final Future<void> Function()? onLocalDataDeleted;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) {
      final compactLandscape =
          viewport.maxHeight < 520 && viewport.maxWidth > viewport.maxHeight;
      final narrow = viewport.maxWidth < 560;
      final densePortrait =
          narrow && !compactLandscape && viewport.maxHeight < 730;
      final padding = compactLandscape
          ? const EdgeInsets.fromLTRB(10, 6, 10, 3)
          : narrow
          ? const EdgeInsets.fromLTRB(14, 14, 14, 16)
          : const EdgeInsets.fromLTRB(24, 18, 24, 22);
      final availableHeight = math.max(
        0.0,
        viewport.maxHeight - padding.vertical,
      );

      return SingleChildScrollView(
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, contentBox) {
                final horizontalModes = contentBox.maxWidth >= 620;
                final quickPopCard = _ModeCard(
                  key: const ValueKey('home-mode-quick-pop'),
                  color: const Color(0xFF7257E9),
                  icon: Icons.speed_rounded,
                  title: 'QUICK POP',
                  subtitle: '2 fichas · partida rápida',
                  badge: 'ONLINE · PRÓXIMAMENTE',
                  featured: true,
                  dense: densePortrait,
                  expanded: horizontalModes && !compactLandscape,
                  onTap: () => _showQuickPopEntry(context),
                );
                final quickTableCard = _ModeCard(
                  key: const ValueKey('home-mode-quick-table'),
                  color: PopColors.blue,
                  icon: Icons.bolt_rounded,
                  title: 'MESA RÁPIDA',
                  subtitle: 'Partida local',
                  tile: narrow && !compactLandscape,
                  dense: densePortrait,
                  expanded: horizontalModes && !compactLandscape,
                  onTap: () => _startOnline(context),
                );
                final cpuCard = _ModeCard(
                  key: const ValueKey('home-mode-cpu'),
                  color: PopColors.red,
                  icon: Icons.smart_toy_rounded,
                  title: 'CONTRA CPU',
                  subtitle: 'Juega contra el CPU',
                  tile: narrow && !compactLandscape,
                  dense: densePortrait,
                  expanded: horizontalModes && !compactLandscape,
                  onTap: () => _showCpuDialog(context),
                );
                final modeCards = [quickPopCard, quickTableCard, cpuCard];
                return ConstrainedBox(
                  constraints: BoxConstraints(minHeight: availableHeight),
                  child: Column(
                    mainAxisAlignment: compactLandscape
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HomeTopBar(
                        profile: profile,
                        wallet: wallet,
                        compactLandscape: compactLandscape,
                        onProfileTap: () => _openProfile(context),
                        onSettings: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                              themeId: wallet.equippedProductId(
                                CosmeticCategory.theme,
                              ),
                              analytics: analytics,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compactLandscape
                              ? 5
                              : densePortrait
                              ? 10
                              : 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (onResumeMatch != null) ...[
                              _ResumeSavedMatchButton(
                                compact: compactLandscape,
                                onTap: () => onResumeMatch!(context),
                              ),
                              SizedBox(height: compactLandscape ? 5 : 10),
                            ],
                            if (appFeatureRollout.contextualTutorial &&
                                !compactLandscape &&
                                viewport.maxHeight >= 800 &&
                                (tutorial?.shouldOffer ?? false)) ...[
                              _TutorialStarterButton(
                                compact: compactLandscape,
                                onTap: () => _startTutorial(context),
                              ),
                              SizedBox(height: compactLandscape ? 5 : 10),
                            ],
                            _HomeSectionTitle(compact: compactLandscape),
                            SizedBox(height: compactLandscape ? 4 : 12),
                            if (horizontalModes)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (
                                    var index = 0;
                                    index < modeCards.length;
                                    index++
                                  ) ...[
                                    if (index > 0) const SizedBox(width: 12),
                                    Expanded(child: modeCards[index]),
                                  ],
                                ],
                              )
                            else if (narrow && !compactLandscape)
                              Column(
                                children: [
                                  quickPopCard,
                                  SizedBox(height: densePortrait ? 9 : 13),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: quickTableCard),
                                      SizedBox(width: densePortrait ? 9 : 12),
                                      Expanded(child: cpuCard),
                                    ],
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < modeCards.length;
                                    index++
                                  ) ...[
                                    if (index > 0)
                                      SizedBox(height: densePortrait ? 9 : 13),
                                    modeCards[index],
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          _HomeMenuDock(
                            compact: compactLandscape,
                            children: [
                              _RoundMenuButton(
                                color: PopColors.yellow,
                                icon: Icons.storefront_rounded,
                                label: 'Tienda',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ShopScreen(
                                      wallet: wallet,
                                      analytics: analytics,
                                    ),
                                  ),
                                ),
                              ),
                              _RoundMenuButton(
                                color: PopColors.green,
                                icon: profile.isGuest
                                    ? Icons.person_add_alt_1_rounded
                                    : Icons.person_rounded,
                                label: profile.isGuest
                                    ? 'Registrarme'
                                    : 'Mi perfil',
                                onTap: () => _openProfile(context),
                              ),
                              if (appFeatureRollout.retentionRewards)
                                if (progression case final controller?)
                                  _RoundMenuButton(
                                    key: const ValueKey('home-progress'),
                                    color: PopColors.blue,
                                    icon: Icons.emoji_events_rounded,
                                    label: 'Misiones',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProgressHubScreen(
                                          progression: controller,
                                          wallet: wallet,
                                        ),
                                      ),
                                    ),
                                  ),
                              _RoundMenuButton(
                                key: const ValueKey('home-how-to-play'),
                                color: const Color(0xFF8A61FF),
                                icon: Icons.help_rounded,
                                label: 'Cómo jugar',
                                onTap: () => _openLearning(
                                  context,
                                  offerTutorial:
                                      appFeatureRollout.contextualTutorial &&
                                      narrow &&
                                      !compactLandscape &&
                                      viewport.maxHeight < 800 &&
                                      (tutorial?.shouldOffer ?? false),
                                ),
                              ),
                              _RoundMenuButton(
                                key: const ValueKey('home-traps'),
                                color: PopColors.red,
                                icon: Icons.science_rounded,
                                label: 'Trampas',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TrapPowerLabScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: compactLandscape ? 2 : 13),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  Future<void> _openProfile(BuildContext context) async {
    if (profile.isGuest) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileSetupScreen(
            onSaved: onProfileChanged,
            authGateway: authGateway,
          ),
        ),
      );
      return;
    }

    final editRequested = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC071A3D),
      builder: (_) => _HomeProfileDialog(
        profile: profile,
        wallet: wallet,
        progression: progression,
        tutorial: tutorial,
        authGateway: authGateway,
        analytics: analytics,
        onLocalDataDeleted: onLocalDataDeleted,
        onProfileChanged: onProfileChanged,
      ),
    );
    if (!context.mounted || editRequested != true) return;
    await Navigator.push<void>(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProfileSetupScreen(
              initial: profile,
              onSaved: onProfileChanged,
              authGateway: authGateway,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: .98, end: 1.0).animate(animation),
                child: child,
              ),
            ),
      ),
    );
  }

  Future<void> _startOnline(BuildContext context) async {
    final mode = await showDialog<GameMode>(
      context: context,
      builder: (_) => const _OnlineModeDialog(),
    );
    if (!context.mounted || mode == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchmakingScreen(
          profile: profile,
          mode: mode,
          wallet: wallet,
          progression: appFeatureRollout.retentionRewards ? progression : null,
          tutorial: tutorial,
          analytics: analytics,
        ),
      ),
    );
  }

  Future<void> _showCpuDialog(BuildContext context) async {
    final setup = await showDialog<({GameMode mode, String level})>(
      context: context,
      builder: (_) => const _CpuSetupDialog(),
    );
    if (!context.mounted || setup == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          opponent: 'CPU • ${setup.level}',
          mode: setup.mode,
          wallet: wallet,
          progression: appFeatureRollout.retentionRewards ? progression : null,
          tutorial: tutorial,
          localProfile: profile,
          analytics: analytics,
        ),
      ),
    );
  }

  Future<void> _showQuickPopEntry(BuildContext context) async {
    final playLocal = await showDialog<bool>(
      context: context,
      builder: (_) => const _QuickPopEntryDialog(),
    );
    if (!context.mounted || playLocal != true) return;
    _startQuickPop(context);
  }

  void _startQuickPop(BuildContext context) {
    if (!appFeatureRollout.quickPopLocal) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          opponent: 'Quick Pop • CPU Normal',
          mode: GameMode.traditional,
          matchFormat: MatchFormat.quickPop,
          wallet: wallet,
          progression: appFeatureRollout.retentionRewards ? progression : null,
          tutorial: tutorial,
          localProfile: profile,
          analytics: analytics,
        ),
      ),
    );
  }

  Future<void> _openLearning(
    BuildContext context, {
    required bool offerTutorial,
  }) async {
    if (!offerTutorial) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const GameGuideScreen()),
      );
      return;
    }

    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          key: const ValueKey('learning-options-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PopText(
                '¿CÓMO QUIERES APRENDER?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PopColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const PopText(
                'Empieza una partida guiada o consulta todas las reglas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667085)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('learning-start-tutorial'),
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.school_rounded),
                label: const PopText('TUTORIAL JUGABLE'),
              ),
              const SizedBox(height: 9),
              OutlinedButton.icon(
                key: const ValueKey('learning-open-guide'),
                onPressed: () => Navigator.pop(sheetContext, false),
                icon: const Icon(Icons.menu_book_rounded),
                label: const PopText('GUÍA COMPLETA'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice) {
      await _startTutorial(context);
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const GameGuideScreen()),
      );
    }
  }

  Future<void> _startTutorial(BuildContext context) async {
    if (!appFeatureRollout.contextualTutorial) return;
    final controller = tutorial;
    if (controller == null) return;
    await controller.start();
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          opponent: 'Tutorial • CPU Fácil',
          mode: GameMode.traditional,
          wallet: wallet,
          tutorial: controller,
          guidedTutorial: true,
          localProfile: profile,
          analytics: analytics,
        ),
      ),
    );
  }
}

class _QuickPopEntryDialog extends StatelessWidget {
  const _QuickPopEntryDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('quick-pop-entry-dialog'),
    insetPadding: const EdgeInsets.all(18),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7257E9),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PopText(
                        'QUICK POP ONLINE',
                        style: TextStyle(
                          color: PopColors.navy,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      _ModeStatusBadge(label: 'ONLINE · PRÓXIMAMENTE'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 17),
            const PopText(
              'El modo online necesita conexión con un servidor seguro. '
              'Mientras lo terminamos, puedes probar Quick Pop contra el CPU.',
              style: TextStyle(
                color: Color(0xFF475467),
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('quick-pop-local-preview'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const PopText('PROBAR QUICK POP'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7257E9),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('quick-pop-entry-close'),
              onPressed: () => Navigator.pop(context, false),
              child: const PopText('AHORA NO'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OnlineModeDialog extends StatelessWidget {
  const _OnlineModeDialog();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .84;
    return Dialog(
      key: const ValueKey('online-mode-dialog'),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: PopColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.public_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopText(
                          'Elige cómo jugar',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: PopColors.navy,
                          ),
                        ),
                        PopText(
                          'Elige las reglas de la mesa local',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: appTranslate(context, 'Cerrar'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _GameModeChoices(
                key: const ValueKey('online-mode-step'),
                keyPrefix: 'online',
                onSelected: (mode) => Navigator.pop(context, mode),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CpuSetupDialog extends StatefulWidget {
  const _CpuSetupDialog();

  @override
  State<_CpuSetupDialog> createState() => _CpuSetupDialogState();
}

class _CpuSetupDialogState extends State<_CpuSetupDialog> {
  GameMode? selectedMode;

  @override
  Widget build(BuildContext context) {
    final choosingMode = selectedMode == null;
    final maxHeight = MediaQuery.sizeOf(context).height * .84;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (!choosingMode)
                    IconButton.filledTonal(
                      key: const ValueKey('cpu-setup-back'),
                      tooltip: appTranslate(context, 'Volver a modos'),
                      onPressed: () => setState(() => selectedMode = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: PopColors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopText(
                          choosingMode
                              ? 'Elige cómo jugar'
                              : 'Elige la dificultad',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: PopColors.navy,
                          ),
                        ),
                        PopText(
                          choosingMode
                              ? 'Paso 1 de 2 · modo de partida'
                              : 'Paso 2 de 2 · nivel del CPU',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: appTranslate(context, 'Cerrar'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: .96, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: choosingMode
                    ? _GameModeChoices(
                        key: const ValueKey('cpu-mode-step'),
                        keyPrefix: 'cpu',
                        onSelected: (mode) =>
                            setState(() => selectedMode = mode),
                      )
                    : _CpuDifficultyChoices(
                        key: const ValueKey('cpu-level-step'),
                        mode: selectedMode!,
                        onSelected: (level) => Navigator.pop(context, (
                          mode: selectedMode!,
                          level: level,
                        )),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameModeChoices extends StatelessWidget {
  const _GameModeChoices({
    super.key,
    required this.keyPrefix,
    required this.onSelected,
  });

  final String keyPrefix;
  final ValueChanged<GameMode> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final horizontal = box.maxWidth >= 500;
      final choices = [
        _CpuChoiceCard(
          key: ValueKey('$keyPrefix-mode-traditional'),
          color: PopColors.blue,
          icon: Icons.workspace_premium_rounded,
          title: 'Tradicional',
          description: 'Reglas clásicas, sin cubos, objetos ni trampas.',
          badge: 'CLÁSICO',
          onTap: () => onSelected(GameMode.traditional),
        ),
        _CpuChoiceCard(
          key: ValueKey('$keyPrefix-mode-chaos'),
          color: const Color(0xFF7B61FF),
          icon: Icons.bolt_rounded,
          title: 'Caos',
          description: 'Cubos sorpresa, poderes, trampas y efectos especiales.',
          badge: 'MÁS ACCIÓN',
          onTap: () => onSelected(GameMode.chaos),
        ),
      ];
      return horizontal
          ? Row(
              children: [
                Expanded(child: choices.first),
                const SizedBox(width: 12),
                Expanded(child: choices.last),
              ],
            )
          : Column(
              children: [
                choices.first,
                const SizedBox(height: 12),
                choices.last,
              ],
            );
    },
  );
}

class _CpuDifficultyChoices extends StatelessWidget {
  const _CpuDifficultyChoices({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  final GameMode mode;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final choices = [
      (
        level: 'Fácil',
        description: 'Para aprender y practicar',
        icon: Icons.sentiment_satisfied_alt_rounded,
        color: PopColors.green,
      ),
      (
        level: 'Normal',
        description: 'Una partida equilibrada',
        icon: Icons.psychology_alt_rounded,
        color: PopColors.blue,
      ),
      (
        level: 'Experto',
        description: 'El CPU calcula trampas y bloqueos',
        icon: Icons.local_fire_department_rounded,
        color: PopColors.red,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:
                (mode == GameMode.chaos
                        ? const Color(0xFF7B61FF)
                        : PopColors.blue)
                    .withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: PopText(
            mode == GameMode.chaos
                ? '⚡ Modo Caos seleccionado'
                : '🏆 Modo Tradicional seleccionado',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PopColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final choice in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CpuChoiceCard(
              key: ValueKey('cpu-level-${choice.level}'),
              color: choice.color,
              icon: choice.icon,
              title: choice.level,
              description: choice.description,
              badge: 'JUGAR',
              compact: true,
              onTap: () => onSelected(choice.level),
            ),
          ),
      ],
    );
  }
}

class _CpuChoiceCard extends StatelessWidget {
  const _CpuChoiceCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.onTap,
    this.compact = false,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String description;
  final String badge;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(22),
    elevation: 7,
    shadowColor: color.withValues(alpha: .3),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(compact ? 13 : 18),
        child: Row(
          children: [
            Container(
              width: compact ? 50 : 62,
              height: compact ? 50 : 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: compact ? 29 : 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 19 : 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  PopText(
                    description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PopText(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.profile,
    required this.wallet,
    required this.compactLandscape,
    required this.onProfileTap,
    required this.onSettings,
  });

  final PlayerProfile profile;
  final WalletController wallet;
  final bool compactLandscape;
  final VoidCallback onProfileTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final stackPlayer = box.maxWidth < 720 && !compactLandscape;
      final compactLogo = box.maxWidth < 500 || compactLandscape;
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CoinPill(wallet: wallet),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .82),
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4007142E),
                  blurRadius: 9,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: IconButton(
              tooltip: appTranslate(context, 'Ajustes'),
              onPressed: onSettings,
              icon: const Icon(Icons.settings_rounded, color: PopColors.navy),
            ),
          ),
        ],
      );
      final playerCard = _HomePlayerCard(
        profile: profile,
        wallet: wallet,
        compact: compactLandscape,
        onTap: onProfileTap,
      );

      if (stackPlayer) {
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _GameLogo(compact: compactLogo)),
                controls,
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(width: double.infinity, child: playerCard),
          ],
        );
      }
      return Row(
        children: [
          _GameLogo(compact: compactLogo),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compactLandscape ? 300 : 380,
                ),
                child: playerCard,
              ),
            ),
          ),
          const SizedBox(width: 16),
          controls,
        ],
      );
    },
  );
}

class _HomePlayerCard extends StatelessWidget {
  const _HomePlayerCard({
    required this.profile,
    required this.wallet,
    required this.compact,
    required this.onTap,
  });

  final PlayerProfile profile;
  final WalletController wallet;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: wallet,
    builder: (context, _) {
      final avatarId = wallet.equippedProductId(CosmeticCategory.avatar);
      return Semantics(
        button: true,
        label: profile.isGuest
            ? appTranslate(context, '¡Listo para jugar!')
            : '${profile.name} ${profile.flag}',
        child: Material(
          key: const ValueKey('home-game-hero'),
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Ink(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 13,
                vertical: compact ? 7 : 9,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .22),
                    Colors.white.withValues(alpha: .11),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .65),
                  width: 1.6,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3307132D),
                    blurRadius: 11,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 44 : 52,
                    height: compact ? 44 : 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [PopColors.yellow, Color(0xFFFFA928)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x50000000),
                          blurRadius: 7,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _AvatarArt(
                      key: ValueKey('home-avatar-${avatarId ?? 'default'}'),
                      avatarId: avatarId,
                      size: compact ? 39 : 47,
                      withFrame: false,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AutoFitSingleLineText(
                          profile.isGuest
                              ? '¡Listo para jugar!'
                              : '${profile.name} ${profile.flag}',
                          style: TextStyle(
                            fontSize: compact ? 16 : 19,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -.2,
                            shadows: const [
                              Shadow(
                                color: Color(0x55000000),
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: PopColors.yellow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: PopText(
                                profile.isGuest
                                    ? 'Invitado'
                                    : 'Nv. ${profile.level}',
                                style: const TextStyle(
                                  color: PopColors.navy,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            for (final color in const [
                              PopColors.red,
                              PopColors.yellow,
                              PopColors.green,
                              PopColors.blue,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ResumeSavedMatchButton extends StatelessWidget {
  const _ResumeSavedMatchButton({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Continuar partida guardada',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('resume-saved-match-button'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: compact ? 38 : 48,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A61FF), Color(0xFF5842D6)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white, width: 1.8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D5842D6),
                blurRadius: 9,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: compact ? 20 : 25,
              ),
              SizedBox(width: compact ? 6 : 9),
              Flexible(
                child: _AutoFitSingleLineText(
                  'CONTINUAR PARTIDA GUARDADA',
                  alignment: Alignment.center,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 10 : 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TutorialStarterButton extends StatelessWidget {
  const _TutorialStarterButton({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('start-contextual-tutorial'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        height: compact ? 42 : 54,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF32B875), Color(0xFF16855B)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 1.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4432B875),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: compact ? 21 : 26,
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    'TUTORIAL JUGABLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  PopText(
                    'Aprende dentro de tu primera partida',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFE7FFF4),
                      fontSize: 10,
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

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .72),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 17,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: PopColors.yellow,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4207132D),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stars_rounded,
                  color: PopColors.navy,
                  size: 18,
                ),
                const SizedBox(width: 7),
                PopText(
                  'ELIGE TU PARTIDA',
                  style: TextStyle(
                    fontSize: compact ? 11.5 : 13,
                    letterSpacing: compact ? .8 : 1.1,
                    fontWeight: FontWeight.w900,
                    color: PopColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .72),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      if (!compact) ...[
        const SizedBox(height: 7),
        const PopText(
          'Elige tu partida y lleva tus cuatro fichas al centro.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFE7EEFF),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ],
  );
}

class _HomeMenuDock extends StatelessWidget {
  const _HomeMenuDock({required this.children, required this.compact});

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('home-menu-dock'),
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 6 : 12,
      vertical: compact ? 4 : 10,
    ),
    decoration: BoxDecoration(
      color: const Color(0xFF071B40).withValues(alpha: .68),
      borderRadius: BorderRadius.circular(compact ? 20 : 26),
      border: Border.all(
        color: Colors.white.withValues(alpha: .28),
        width: 1.5,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x4007132D),
          blurRadius: 14,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceEvenly,
      runAlignment: WrapAlignment.center,
      spacing: compact ? 4 : 8,
      runSpacing: 8,
      children: children,
    ),
  );
}

class _GameLogo extends StatelessWidget {
  const _GameLogo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Transform.rotate(
        angle: -.07,
        child: Container(
          width: compact ? 44 : 56,
          height: compact ? 44 : 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFDD55), Color(0xFFFFA918)],
            ),
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x5007132D),
                blurRadius: 9,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.casino_rounded,
            color: PopColors.navy,
            size: compact ? 28 : 35,
          ),
        ),
      ),
      SizedBox(width: compact ? 8 : 11),
      Flexible(
        child: PopText(
          'PARCHÍS\nPOP!',
          style: TextStyle(
            fontSize: compact ? 19 : 25,
            height: .84,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: compact ? -1 : -1.3,
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                offset: Offset(0, 3),
                blurRadius: 5,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _RoundMenuButton extends StatefulWidget {
  const _RoundMenuButton({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_RoundMenuButton> createState() => _RoundMenuButtonState();
}

class _RoundMenuButtonState extends State<_RoundMenuButton> {
  bool pressed = false;
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 500 ||
        MediaQuery.sizeOf(context).height < 520;
    final foreground = widget.color == PopColors.yellow
        ? PopColors.navy
        : Colors.white;
    if (compact) {
      final compactWidth = ((MediaQuery.sizeOf(context).width - 54) / 3)
          .clamp(86.0, 112.0)
          .toDouble();
      return MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedScale(
          scale: pressed ? .96 : (hovered ? 1.025 : 1),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: SizedBox(
            width: compactWidth,
            height: 48,
            child: Material(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onHighlightChanged: (value) => setState(() => pressed = value),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(widget.color, Colors.white, .24)!,
                              widget.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(alpha: .28),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: foreground, size: 22),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _AutoFitSingleLineText(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Color(0x66000000),
                                offset: Offset(0, 2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: pressed ? .94 : (hovered ? 1.04 : 1),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: compact ? 64 : 86,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onHighlightChanged: (value) => setState(() => pressed = value),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(0, compact ? 3 : 5),
                          child: Container(
                            width: compact ? 44 : 56,
                            height: compact ? 44 : 56,
                            decoration: BoxDecoration(
                              color: Color.lerp(
                                widget.color,
                                PopColors.navy,
                                .42,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        Container(
                          width: compact ? 44 : 56,
                          height: compact ? 44 : 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(widget.color, Colors.white, .24)!,
                                widget.color,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: widget.color.withValues(alpha: .35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: foreground,
                            size: compact ? 24 : 31,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 3 : 8),
                    _AutoFitSingleLineText(
                      widget.label,
                      alignment: Alignment.center,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 9 : 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.featured = false,
    this.tile = false,
    this.expanded = false,
    this.dense = false,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final bool featured;
  final bool tile;
  final bool expanded;
  final bool dense;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool pressed = false;
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 520;
    final narrow = MediaQuery.sizeOf(context).width < 500 && !compact;
    final minHeight = compact
        ? 90.0
        : widget.tile
        ? (widget.dense ? 128.0 : 146.0)
        : widget.featured && widget.dense
        ? 116.0
        : widget.dense
        ? 110.0
        : narrow
        ? 132.0
        : widget.expanded
        ? 158.0
        : 118.0;
    final dark = Color.lerp(widget.color, PopColors.navy, .32)!;
    return Semantics(
      button: true,
      label:
          '${appTranslate(context, widget.title)}. '
          '${appTranslate(context, widget.subtitle)}'
          '${widget.badge == null ? '' : '. ${appTranslate(context, widget.badge!)}'}',
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 125),
          curve: Curves.easeOut,
          scale: pressed ? .975 : (hovered ? 1.012 : 1),
          child: Padding(
            padding: EdgeInsets.only(bottom: compact ? 5 : 7),
            child: Stack(
              children: [
                Positioned.fill(
                  top: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark,
                      borderRadius: BorderRadius.circular(29),
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(29),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    height: minHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(29),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(widget.color, Colors.white, .20)!,
                          widget.color,
                          dark,
                        ],
                        stops: const [0, .56, 1],
                      ),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: .38),
                          blurRadius: 17,
                          offset: const Offset(0, 9),
                        ),
                      ],
                    ),
                    child: InkWell(
                      onTap: widget.onTap,
                      onHighlightChanged: (value) =>
                          setState(() => pressed = value),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 2,
                            left: 28,
                            right: 28,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white.withValues(alpha: .48),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(
                              compact
                                  ? 9
                                  : widget.dense
                                  ? 12
                                  : narrow
                                  ? 15
                                  : 18,
                            ),
                            child: widget.tile
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _ModeArtwork(
                                            color: widget.color,
                                            icon: widget.icon,
                                            size: widget.dense ? 43 : 49,
                                          ),
                                          const Spacer(),
                                          _ModePlayPill(
                                            color: dark,
                                            iconOnly: true,
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      _ModeCardTitle(
                                        title: widget.title,
                                        fontSize: widget.dense ? 16 : 18,
                                      ),
                                      const SizedBox(height: 5),
                                      PopText(
                                        widget.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFFF4F7FF),
                                          fontSize: widget.dense ? 9.5 : 10.5,
                                          height: 1.15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      _ModeArtwork(
                                        color: widget.color,
                                        icon: widget.icon,
                                        size: compact
                                            ? 52
                                            : widget.dense
                                            ? 58
                                            : narrow
                                            ? 70
                                            : 78,
                                      ),
                                      SizedBox(
                                        width: compact || narrow || widget.dense
                                            ? 12
                                            : 17,
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (widget.badge case final badge?)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 3,
                                                ),
                                                child: _ModeStatusBadge(
                                                  label: badge,
                                                ),
                                              ),
                                            _ModeCardTitle(
                                              title: widget.title,
                                              fontSize:
                                                  compact ||
                                                      narrow ||
                                                      widget.dense
                                                  ? (compact ? 18 : 20)
                                                  : 24,
                                            ),
                                            const SizedBox(height: 5),
                                            PopText(
                                              widget.subtitle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: const Color(0xFFF4F7FF),
                                                fontSize: compact ? 10 : 11,
                                                height: 1.18,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      _ModePlayPill(
                                        color: dark,
                                        compact: compact,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCardTitle extends StatelessWidget {
  const _ModeCardTitle({required this.title, required this.fontSize});

  final String title;
  final double fontSize;

  @override
  Widget build(BuildContext context) => _AutoFitSingleLineText(
    title,
    style: TextStyle(
      fontSize: fontSize,
      height: .98,
      letterSpacing: -.45,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      shadows: const [
        Shadow(color: Color(0x55000000), offset: Offset(0, 2), blurRadius: 4),
      ],
    ),
  );
}

class _ModeStatusBadge extends StatelessWidget {
  const _ModeStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: PopColors.yellow,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: PopText(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: PopColors.navy,
        fontSize: 8.5,
        height: 1,
        letterSpacing: .25,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _ModePlayPill extends StatelessWidget {
  const _ModePlayPill({
    required this.color,
    this.compact = false,
    this.iconOnly = false,
  });

  final Color color;
  final bool compact;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: iconOnly ? 8 : (compact ? 7 : 11),
      vertical: compact ? 6 : 9,
    ),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 7,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!iconOnly) ...[
          PopText(
            'JUGAR',
            style: TextStyle(
              color: color,
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 2),
        ],
        Icon(
          Icons.arrow_forward_rounded,
          color: color,
          size: compact ? 15 : 17,
        ),
      ],
    ),
  );
}

class _ModeArtwork extends StatelessWidget {
  const _ModeArtwork({
    required this.color,
    required this.icon,
    required this.size,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final online = icon == Icons.public_rounded || icon == Icons.bolt_rounded;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: online ? -.07 : .07,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(size * .28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .95),
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 9,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: size * .53),
              ),
            ),
          ),
          for (final entry in [
            (
              alignment: online ? Alignment.topRight : Alignment.bottomLeft,
              tokenColor: PopColors.yellow,
            ),
            (
              alignment: online ? Alignment.bottomRight : Alignment.topRight,
              tokenColor: PopColors.green,
            ),
          ])
            Align(
              alignment: entry.alignment,
              child: Container(
                width: size * .25,
                height: size * .25,
                decoration: BoxDecoration(
                  color: entry.tokenColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x38000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: online
                    ? null
                    : Center(
                        child: Container(
                          width: size * .055,
                          height: size * .055,
                          decoration: const BoxDecoration(
                            color: PopColors.navy,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

String _formatCoins(int value) {
  final text = value.toString();
  final output = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) output.write(',');
    output.write(text[index]);
  }
  return output.toString();
}

Future<void> _showAddCoinsDialog(
  BuildContext context,
  WalletController wallet,
) async {
  const packs = [
    (amount: 500, label: 'Paquete pequeño', color: PopColors.blue),
    (amount: 1200, label: 'Paquete mediano', color: PopColors.green),
    (amount: 3000, label: 'Paquete grande', color: Color(0xFF7B61FF)),
    (amount: 10000, label: 'Caja de prueba', color: Color(0xFFFF8A24)),
  ];

  Future<void> addPack(BuildContext dialogContext, int amount) async {
    await wallet.addCoins(amount);
    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: PopText('Añadiste ${_formatCoins(amount)} monedas de prueba.'),
      ),
    );
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      key: const ValueKey('test-balance-dialog'),
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(dialogContext).height - 36,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: PopColors.yellow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.monetization_on_rounded,
                      color: PopColors.navy,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopText(
                          'Añadir monedas',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: PopColors.navy,
                          ),
                        ),
                        PopText(
                          'Saldo local para probar la tienda',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: appTranslate(context, 'Cerrar'),
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      PopColors.yellow.withValues(alpha: .30),
                      const Color(0xFFFFE7A0).withValues(alpha: .48),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: PopColors.yellow.withValues(alpha: .70),
                  ),
                ),
                child: Column(
                  children: [
                    PopText(
                      'SALDO ACTUAL · ${_formatCoins(wallet.balance)}',
                      style: const TextStyle(
                        color: PopColors.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const PopText(
                      'MODO DE PRUEBA · No se realiza ningún cobro. Las '
                      'compras reales se conectarán con App Store y Google Play.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PopColors.ink,
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final pack in packs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    color: pack.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      key: ValueKey('add-test-coins-${pack.amount}'),
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => addPack(dialogContext, pack.amount),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_circle_rounded,
                              color: pack.color,
                              size: 31,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PopText(
                                    pack.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  PopText(
                                    '+${_formatCoins(pack.amount)} monedas',
                                    style: TextStyle(
                                      color: pack.color,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: pack.color,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: pack.color.withValues(alpha: .30),
                                    blurRadius: 7,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const PopText(
                                'AÑADIR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.wallet});

  final WalletController wallet;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: wallet,
    builder: (context, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PopColors.yellow.withValues(alpha: .55)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F17284D),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded, color: Color(0xFFF4AE00)),
          const SizedBox(width: 5),
          PopText(
            _formatCoins(wallet.balance),
            key: const ValueKey('coin-balance'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );
}

class _ShopBalanceCard extends StatelessWidget {
  const _ShopBalanceCard({required this.wallet, required this.onAdd});

  final WalletController wallet;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('shop-balance-card'),
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD966), Color(0xFFFFB429)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3BB87400),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .88),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFF1B5), width: 2),
            ),
            child: const Icon(
              Icons.toll_rounded,
              color: Color(0xFFD58B00),
              size: 29,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PopText(
                  'SALDO PARA PROBAR',
                  maxLines: 1,
                  style: TextStyle(
                    color: PopColors.navy,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                _AutoFitSingleLineText(
                  '${_formatCoins(wallet.balance)} MONEDAS',
                  alignment: Alignment.centerLeft,
                  style: const TextStyle(
                    color: PopColors.navy,
                    fontSize: 19,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('shop-add-test-balance'),
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_rounded, size: 20),
            label: const PopText('+ MONEDAS'),
            style: FilledButton.styleFrom(
              backgroundColor: PopColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopRewardedCoinsCard extends StatelessWidget {
  const _ShopRewardedCoinsCard({
    required this.controller,
    required this.onWatch,
  });

  final AppAdsController controller;
  final Future<void> Function(AppAdsController controller) onWatch;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final ready = controller.rewardedReady;
      return Container(
        key: const ValueKey('shop-rewarded-coins-card'),
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7558F5), Color(0xFF3E7BEA)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3B314DCA),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .62),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.ondemand_video_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    'PREMIO',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                  SizedBox(height: 2),
                  PopText(
                    'Mira un anuncio y recibe 100 monedas.',
                    maxLines: 2,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('shop-rewarded-coins'),
              onPressed: ready ? () => onWatch(controller) : null,
              icon: Icon(
                ready ? Icons.play_arrow_rounded : Icons.hourglass_top_rounded,
                size: 20,
              ),
              label: PopText(
                ready ? 'VER ANUNCIO · +100' : 'PREPARANDO ANUNCIO',
                maxLines: 1,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: PopColors.yellow,
                foregroundColor: PopColors.navy,
                disabledBackgroundColor: Colors.white.withValues(alpha: .18),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({
    super.key,
    required this.profile,
    required this.mode,
    this.wallet,
    this.progression,
    this.tutorial,
    this.analytics = const NoopGameAnalytics(),
  });

  final PlayerProfile profile;
  final GameMode mode;
  final WalletController? wallet;
  final PlayerProgressionController? progression;
  final TutorialController? tutorial;
  final GameAnalytics analytics;

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  static const _setupTick = Duration(milliseconds: 250);
  static const firstVirtualJoinStep = 1;
  static const virtualSeatColors = [
    PlayerColor.green,
    PlayerColor.yellow,
    PlayerColor.blue,
  ];

  int setupStep = 0;
  Timer? timer;
  late final int seed;
  late final OnlineParticipant localPlayer;
  OnlineMatchSession? session;
  List<OnlineParticipant> opponents = const [];
  bool openingGame = false;

  @override
  void initState() {
    super.initState();
    seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    localPlayer = OnlineParticipant(
      id: 'local-${widget.profile.name.toLowerCase()}',
      displayName: widget.profile.name,
      flag: widget.profile.flag,
      avatarId:
          widget.wallet?.equippedProductId(CosmeticCategory.avatar) ??
          'avatar_default',
      level: widget.profile.level,
      color: PlayerColor.red,
      kind: ParticipantKind.local,
      loadout: CosmeticLoadout(
        themeId: widget.wallet?.equippedProductId(CosmeticCategory.theme),
        diceId: widget.wallet?.equippedProductId(CosmeticCategory.dice),
        tokensId: widget.wallet?.equippedProductId(CosmeticCategory.tokens),
      ),
    );
    timer = Timer.periodic(_setupTick, (_) => _advanceSearch());
  }

  void _prepareVirtualFallback() {
    if (session != null) return;
    final fallbackSession = VirtualProfileFactory(seed: seed).createSession(
      matchId: 'quick-$seed',
      mode: widget.mode,
      localPlayer: localPlayer,
    );
    session = fallbackSession;
    opponents = fallbackSession.participants
        .where((participant) => participant.kind != ParticipantKind.local)
        .toList(growable: false);
  }

  void _advanceSearch() {
    if (!mounted || openingGame) return;
    final nextStep = setupStep + 1;
    if (nextStep == firstVirtualJoinStep) {
      _prepareVirtualFallback();
    }
    final gameStartStep = firstVirtualJoinStep + virtualSeatColors.length;
    if (nextStep >= gameStartStep) {
      setupStep = nextStep;
      _openGame();
      return;
    }
    setState(() => setupStep = nextStep);
  }

  int get revealedOpponents {
    final joined = setupStep - firstVirtualJoinStep + 1;
    if (joined <= 0) return 0;
    if (joined >= opponents.length) return opponents.length;
    return joined;
  }

  String get searchStatus {
    if (setupStep < firstVirtualJoinStep) {
      return 'Preparando partida local';
    }
    return 'Añadiendo CPU · '
        '$revealedOpponents/${virtualSeatColors.length}';
  }

  void _openGame() {
    if (!mounted || openingGame) return;
    _prepareVirtualFallback();
    final readySession = session!;
    openingGame = true;
    timer?.cancel();
    final firstOpponent = opponents.first;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          opponent:
              '${firstOpponent.displayName} ${firstOpponent.flag} • Normal',
          mode: readySession.mode,
          wallet: widget.wallet,
          progression: widget.progression,
          tutorial: widget.tutorial,
          onlineSession: readySession,
          analytics: widget.analytics,
          matchmakingWaitSeconds: math.max(
            1,
            (setupStep * _setupTick.inMilliseconds / 1000).ceil(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PopBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 74,
                    height: 74,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                      color: PopColors.blue,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const PopText(
                    'Armando tu mesa…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: ValueKey('matchmaking-mode-${widget.mode.name}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (widget.mode == GameMode.chaos
                                  ? const Color(0xFF7B61FF)
                                  : PopColors.blue)
                              .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: PopText(
                      widget.mode == GameMode.chaos
                          ? '⚡ CAOS'
                          : '🏆 TRADICIONAL',
                      style: const TextStyle(
                        color: PopColors.navy,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  PopText(
                    searchStatus,
                    key: const ValueKey('matchmaking-status'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    key: const ValueKey('matchmaking-seats'),
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MatchmakingSeat(
                        participant: localPlayer,
                        color: PlayerColor.red,
                        revealed: true,
                      ),
                      for (
                        var index = 0;
                        index < virtualSeatColors.length;
                        index++
                      )
                        _MatchmakingSeat(
                          participant: index < opponents.length
                              ? opponents[index]
                              : null,
                          color: virtualSeatColors[index],
                          revealed: index < revealedOpponents,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .86),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          color: PopColors.blue,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: PopText(
                            'Esta versión prepara la partida en tu dispositivo '
                            'y completa los demás asientos con CPU.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const PopText('Cancelar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchmakingSeat extends StatelessWidget {
  const _MatchmakingSeat({
    required this.participant,
    required this.color,
    required this.revealed,
  });

  final OnlineParticipant? participant;
  final PlayerColor color;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final profile = participant;
    final local = profile?.kind == ParticipantKind.local;
    final badge = profile == null
        ? ''
        : _participantRoleLabel(profile, uppercase: true);
    return AnimatedContainer(
      key: ValueKey('matchmaking-seat-${color.name}'),
      duration: const Duration(milliseconds: 420),
      width: 132,
      height: 126,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: revealed
            ? Colors.white.withValues(alpha: .93)
            : PopColors.cloud.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: revealed ? _playerUiColor(color) : const Color(0xFFD7DCE5),
          width: revealed ? 2 : 1,
        ),
        boxShadow: revealed
            ? const [
                BoxShadow(
                  color: Color(0x2017284D),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: revealed && profile != null
            ? Column(
                key: ValueKey('profile-${profile.id}'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: _playerUiColor(
                      color,
                    ).withValues(alpha: .15),
                    child: _AvatarArt(
                      key: ValueKey('match-avatar-${profile.avatarId}'),
                      avatarId: profile.avatarId,
                      size: 42,
                      withFrame: false,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _AutoFitSingleLineText(
                    '${profile.displayName} ${profile.flag}',
                    alignment: Alignment.center,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: PopColors.navy,
                    ),
                  ),
                  PopText(
                    'Nv. ${profile.level}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  PopText(
                    badge,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 7,
                      color: local ? PopColors.green : PopColors.blue,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .35,
                    ),
                  ),
                ],
              )
            : const Column(
                key: ValueKey('searching-seat'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 27,
                    height: 27,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                  SizedBox(height: 10),
                  PopText(
                    'Preparando…',
                    style: TextStyle(
                      color: Color(0xFF98A2B3),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _CpuExitChoice { save, discard, cancel }

class _MatchExitDialogFrame extends StatelessWidget {
  const _MatchExitDialogFrame({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 17),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF254F9E), Color(0xFF162C5D)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: PopColors.yellow, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x9007132D),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: .6),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 13),
            PopText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: .35,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: .2)),
              ),
              child: PopText(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFF3F7FF),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.opponent,
    this.mode = GameMode.traditional,
    this.matchFormat = MatchFormat.classic,
    this.gameEngine,
    this.wallet,
    this.progression,
    this.tutorial,
    this.guidedTutorial = false,
    this.localProfile,
    this.onlineSession,
    this.analytics = const NoopGameAnalytics(),
    this.analyticsMatchRef,
    this.analyticsFirstRollLogged = false,
    this.isRematch = false,
    this.isResumedMatch = false,
    this.resumeSecondsAway,
    this.matchmakingWaitSeconds,
    this.showAllTestTraps,
    this.cpuThinkDelayProvider,
    this.initialElapsed = Duration.zero,
  });
  final String opponent;
  final GameMode mode;
  final MatchFormat matchFormat;
  final GameEngine? gameEngine;
  final WalletController? wallet;
  final PlayerProgressionController? progression;
  final TutorialController? tutorial;
  final bool guidedTutorial;
  final PlayerProfile? localProfile;
  final OnlineMatchSession? onlineSession;
  final GameAnalytics analytics;
  final String? analyticsMatchRef;
  final bool analyticsFirstRollLogged;
  final bool isRematch;
  final bool isResumedMatch;
  final int? resumeSecondsAway;
  final int? matchmakingWaitSeconds;
  final bool? showAllTestTraps;
  final Duration Function()? cpuThinkDelayProvider;
  final Duration initialElapsed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const _firstRollGuideDelay = Duration(milliseconds: 450);
  static const _idleRollGuideDelay = Duration(seconds: 4);

  late final GameEngine engine;
  late final bool ownsEngine;
  late final TutorialGameScenario? tutorialScenario;
  late final MatchAnalyticsContext analyticsMatch;
  late final String progressionEventRunRef;
  late final GameFeedbackController feedbackController;
  final math.Random cpuPacingRandom = math.Random();
  bool cpuThinking = false;
  GameToken? selectedToken;
  Timer? victoryTimer;
  Timer? finalReturnTimer;
  Timer? chatTimer;
  Timer? chatReactionTimer;
  Timer? eventChatTimer;
  Timer? matchClockTimer;
  Duration matchElapsed = Duration.zero;
  bool victoryQueued = false;
  bool showVictory = false;
  bool compactPhoneBoard = false;
  _MobileBoardCameraMode mobileBoardCameraMode =
      _MobileBoardCameraMode.fullBoard;
  Offset mobileBoardManualFocus = const Offset(.5, .5);
  bool endMatchRewardInProgress = false;
  bool endMatchRewardClaimed = false;
  bool postVictoryNavigationInProgress = false;
  bool rewardedPreloadRequested = false;
  bool tutorialCompletionVisible = false;
  final Object moveSelectionTapGroup = Object();
  SafeChatController? safeChat;
  SafeChatMessage? visibleChatMessage;
  OnlineParticipant? visibleChatSender;
  int lastAudioEventSequence = 0;
  int lastAnalyticsEventSequence = 0;
  bool firstRollAnalyticsLogged = false;
  bool matchCompletionAnalyticsLogged = false;
  bool matchAbandonAnalyticsLogged = false;
  bool rematchOfferAnalyticsLogged = false;
  bool rewardedOfferAnalyticsLogged = false;
  bool rewardedDecisionAnalyticsLogged = false;
  int rewardedOfferedCoins = 0;
  bool matchCompletionRewardSettled = false;
  bool matchPlacementRewardSettled = false;
  int matchRewardCoinsAwarded = 0;
  int matchBasePayout = 0;
  bool localCpuTakeoverActive = false;
  bool rollGuideEnabled = true;
  DiceHandPreference diceHandPreference = DiceHandPreference.right;
  bool rollGuideVisible = false;
  bool rollGuideAppActive = true;
  int rollGuidePulseSerial = 0;
  int completedGuidedRolls = 0;
  int? rollGuideArmedTurn;
  Timer? rollGuideDelayTimer;

  bool get _isLocallyControlledTurn =>
      engine.currentPlayer.isHuman && !localCpuTakeoverActive;

  bool get _isCpuControlledTurn =>
      !engine.currentPlayer.isHuman || localCpuTakeoverActive;

  bool get _usesGuidedTutorial =>
      widget.guidedTutorial ||
      (widget.tutorial != null && widget.opponent.startsWith('Tutorial'));

  TutorialStep? get _guidedTutorialStep =>
      widget.tutorial?.lifecycle == TutorialLifecycle.inProgress
      ? widget.tutorial?.currentStep
      : null;

  bool get _guidedTutorialActive =>
      tutorialScenario != null && _guidedTutorialStep != null;

  bool get _tutorialAllowsRoll =>
      !_guidedTutorialActive ||
      tutorialScenario!.allowsRoll(_guidedTutorialStep);

  List<int>? get _guidedVisibleRemainingDice {
    if (!_guidedTutorialActive || !engine.hasRolled) return null;
    final die = tutorialScenario!.expectedDie(_guidedTutorialStep);
    return die == null ? const <int>[] : <int>[die];
  }

  bool _tutorialAllowsToken(GameToken token) =>
      !_guidedTutorialActive ||
      tutorialScenario!.allowsToken(_guidedTutorialStep, token);

  bool _tutorialAllowsMove(
    GameToken token,
    int die, {
    bool usesAllDice = false,
  }) =>
      !_guidedTutorialActive ||
      tutorialScenario!.allowsMove(
        _guidedTutorialStep,
        token,
        die,
        usesAllDice: usesAllDice,
      );

  List<MoveDestinationPreview> _visibleMoveDestinationPreviews(
    GameToken? token,
  ) {
    final previews = _moveDestinationPreviews(engine, token);
    if (!_guidedTutorialActive) return previews;
    return previews
        .where(
          (preview) => _tutorialAllowsMove(
            preview.token,
            preview.value,
            usesAllDice: preview.usesAllDice,
          ),
        )
        .toList(growable: false);
  }

  GameToken? get _tokenChoiceGuideTarget {
    if (!rollGuideAppActive ||
        !_isLocallyControlledTurn ||
        !engine.hasRolled ||
        engine.gameOver ||
        engine.effectResolving ||
        mobileBoardCameraMode != _MobileBoardCameraMode.fullBoard ||
        selectedToken != null) {
      return null;
    }
    if (_guidedTutorialActive) {
      final target = tutorialScenario!.expectedToken(_guidedTutorialStep);
      if (target != null &&
          !target.finished &&
          (engine.legalDiceFor(target).isNotEmpty ||
              engine.canMoveUsingAllDice(target))) {
        return target;
      }
      return null;
    }
    if (!rollGuideEnabled) return null;
    final legalNestTokens = engine.currentPlayer.tokens
        .where(
          (token) => token.inNest && engine.legalDiceFor(token).contains(5),
        )
        .toList(growable: false);
    if (legalNestTokens.isEmpty) return null;

    final preferredIds = diceHandPreference == DiceHandPreference.right
        ? const [1, 0, 3, 2]
        : const [0, 1, 2, 3];
    for (final id in preferredIds) {
      for (final token in legalNestTokens) {
        if (token.id == id) return token;
      }
    }
    return legalNestTokens.first;
  }

  GameToken? get _tokenChoicePromptTarget {
    if (!_isLocallyControlledTurn ||
        !engine.hasRolled ||
        engine.gameOver ||
        engine.effectResolving ||
        selectedToken != null) {
      return null;
    }
    if (_guidedTutorialActive) {
      final target = tutorialScenario!.expectedToken(_guidedTutorialStep);
      if (target != null &&
          !target.finished &&
          (engine.legalDiceFor(target).isNotEmpty ||
              engine.canMoveUsingAllDice(target))) {
        return target;
      }
      return null;
    }
    final legalTokens = engine.currentPlayer.tokens
        .where(
          (token) =>
              !token.finished &&
              (engine.legalDiceFor(token).isNotEmpty ||
                  engine.canMoveUsingAllDice(token)),
        )
        .toList(growable: false);
    if (legalTokens.isEmpty) return null;

    final guidedNestToken = _tokenChoiceGuideTarget;
    if (guidedNestToken != null) return guidedNestToken;
    final preferredIds = diceHandPreference == DiceHandPreference.right
        ? const [1, 0, 3, 2]
        : const [0, 1, 2, 3];
    for (final id in preferredIds) {
      for (final token in legalTokens) {
        if (token.id == id) return token;
      }
    }
    return legalTokens.first;
  }

  bool get trapDiagnosticsEnabled => resolveTrapDiagnosticsVisibility(
    isDebugBuild: kDebugMode,
    requested: widget.showAllTestTraps,
  );

  @override
  void initState() {
    super.initState();
    matchElapsed = widget.initialElapsed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(WakelockPlus.enable());
    final level = widget.opponent.contains('Experto')
        ? 'Experto'
        : widget.opponent.contains('Fácil')
        ? 'Fácil'
        : 'Normal';
    final onlineSession = widget.onlineSession;
    final onlineCpuNames = onlineSession == null
        ? null
        : [
            onlineSession.participantForColor(PlayerColor.green).displayName,
            onlineSession.participantForColor(PlayerColor.yellow).displayName,
            onlineSession.participantForColor(PlayerColor.blue).displayName,
          ];
    tutorialScenario =
        _usesGuidedTutorial &&
            widget.gameEngine == null &&
            widget.tutorial?.currentStep != null
        ? TutorialGameScenario.create(
            step: widget.tutorial!.currentStep!,
            humanName: widget.localProfile?.name ?? 'Tú',
          )
        : null;
    ownsEngine = widget.gameEngine == null;
    engine =
        widget.gameEngine ??
        tutorialScenario?.engine ??
        GameEngine(
          cpuLevel: level,
          mode: onlineSession?.mode ?? widget.mode,
          matchFormat: widget.matchFormat,
          humanName:
              onlineSession?.participantForColor(PlayerColor.red).displayName ??
              'Tú',
          cpuNames: onlineCpuNames,
        );
    final playType = _playTypeForSession(onlineSession);
    final matchRef =
        widget.analyticsMatchRef ??
        _newAnalyticsReference(
          playType == MatchPlayType.cpu ? 'cpu_match' : 'online_match',
        );
    analyticsMatch = MatchAnalyticsContext(
      playType: playType,
      mode: engine.mode,
      matchFormat: engine.matchFormat,
      correlation: AnalyticsCorrelation(anonymousMatchId: matchRef),
    );
    // GameEngine starts a fresh local event sequence after checkpoint restore.
    // A run-scoped prefix keeps mission events unique across every resume.
    progressionEventRunRef = _newAnalyticsReference('progress');
    feedbackController = GameFeedbackController(
      output: const _PlatformGameFeedbackOutput(),
      safeLandingResolver: (event) {
        final progress = event.toProgress;
        if (progress == null ||
            progress < 0 ||
            progress >= GameEngine.commonPathLength) {
          return false;
        }
        return GameEngine.safeLoopIndices.contains(
          engine.loopIndex(event.playerColor, progress),
        );
      },
    );
    firstRollAnalyticsLogged = widget.analyticsFirstRollLogged;
    if (!_usesGuidedTutorial && widget.isResumedMatch) {
      unawaited(
        widget.analytics.logEvent(
          MatchResumeEvent(
            match: analyticsMatch,
            stage: MatchResumeStage.succeeded,
            secondsAway: widget.resumeSecondsAway,
          ),
        ),
      );
    } else if (!_usesGuidedTutorial) {
      unawaited(
        widget.analytics.logMatchStarted(
          MatchStartEvent(
            playType: playType,
            mode: engine.mode,
            matchFormat: engine.matchFormat,
            launchSource: widget.isRematch
                ? MatchLaunchSource.rematch
                : MatchLaunchSource.home,
            cpuDifficulty: playType == MatchPlayType.cpu
                ? switch (level) {
                    'Fácil' => CpuDifficulty.easy,
                    'Experto' => CpuDifficulty.expert,
                    _ => CpuDifficulty.normal,
                  }
                : null,
            matchmakingWaitSeconds: playType == MatchPlayType.online
                ? widget.matchmakingWaitSeconds
                : null,
            fallbackOpponentCount: playType == MatchPlayType.online
                ? onlineSession?.participants
                      .where(
                        (participant) =>
                            participant.kind == ParticipantKind.virtual,
                      )
                      .length
                : null,
            liveHumanOpponentCount: playType == MatchPlayType.online
                ? onlineSession?.participants
                      .where(
                        (participant) =>
                            participant.kind == ParticipantKind.remoteHuman,
                      )
                      .length
                : null,
            takenOverOpponentCount: playType == MatchPlayType.online
                ? onlineSession?.participants
                      .where(
                        (participant) =>
                            participant.kind == ParticipantKind.humanTakenOver,
                      )
                      .length
                : null,
            correlation: analyticsMatch.correlation,
          ),
        ),
      );
    }
    if (!_usesGuidedTutorial && widget.isRematch) {
      unawaited(
        widget.analytics.logEvent(
          RematchEvent(match: analyticsMatch, stage: RematchStage.started),
        ),
      );
    }
    engine.addListener(_onGameChanged);
    widget.wallet?.addListener(_onWalletChanged);
    lastAudioEventSequence = engine.eventHistory.isEmpty
        ? 0
        : engine.eventHistory.last.sequence;
    lastAnalyticsEventSequence = lastAudioEventSequence;
    matchClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || engine.gameOver) return;
      setState(() => matchElapsed += const Duration(seconds: 1));
    });
    if (onlineSession != null) {
      safeChat = SafeChatController();
    }
    if (engine.gameOver && engine.winner != null) {
      _queueVictoryCelebration();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (engine.gameOver) unawaited(_settleMatchRewards());
      unawaited(_saveMatchCheckpoint());
      // A restored checkpoint can open directly on a CPU turn without a fresh
      // engine notification. Kick the existing CPU driver once after mount.
      if (widget.isResumedMatch && !engine.gameOver && _isCpuControlledTurn) {
        _onGameChanged();
      }
    });
    unawaited(_loadRollGuidePreferences(rearm: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (rewardedPreloadRequested) return;
    rewardedPreloadRequested = true;
    MobileAdsScope.maybeOf(context)?.preloadRewarded();
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallet != widget.wallet) {
      oldWidget.wallet?.removeListener(_onWalletChanged);
      widget.wallet?.addListener(_onWalletChanged);
    }
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(WakelockPlus.disable());
    victoryTimer?.cancel();
    finalReturnTimer?.cancel();
    chatTimer?.cancel();
    chatReactionTimer?.cancel();
    eventChatTimer?.cancel();
    matchClockTimer?.cancel();
    _cancelRollGuide(notify: false);
    widget.wallet?.removeListener(_onWalletChanged);
    engine.removeListener(_onGameChanged);
    if (ownsEngine) engine.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isLeaving =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (isLeaving) {
      if (state == AppLifecycleState.detached) {
        if (engine.gameOver) {
          _logMatchCompleted(placement: engine.placementFor(PlayerColor.red));
          _logRewardedDeclinedIfIgnored();
        } else {
          _logMatchAbandoned(MatchAbandonReason.appClosed);
        }
      }
      rollGuideAppActive = false;
      _cancelRollGuide(resetWindow: true, notify: false);
      mobileBoardCameraMode = _MobileBoardCameraMode.fullBoard;
      unawaited(_saveMatchCheckpoint());
      if (_sessionHasRemoteHuman(widget.onlineSession) && !engine.gameOver) {
        localCpuTakeoverActive = true;
        _onGameChanged();
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      rollGuideAppActive = true;
      localCpuTakeoverActive = false;
      unawaited(_saveMatchCheckpoint());
      unawaited(_loadRollGuidePreferences(rearm: true));
      MobileAdsScope.maybeOf(context)?.preloadRewarded();
      if (mounted) setState(() {});
    }
  }

  bool get _canOfferRollGuide =>
      rollGuideEnabled &&
      rollGuideAppActive &&
      _tutorialAllowsRoll &&
      _isLocallyControlledTurn &&
      !engine.hasRolled &&
      !engine.gameOver &&
      !engine.effectResolving;

  Future<void> _loadRollGuidePreferences({bool rearm = false}) async {
    final store = await SharedPreferences.getInstance();
    final enabled = store.getBool(settingsRollGuideKey) ?? true;
    final hand = diceHandPreferenceFromStorage(
      store.getString(settingsDiceHandKey),
    );
    feedbackController
      ..soundEnabled = store.getBool('settings_sound') ?? true
      ..hapticsEnabled = store.getBool('settings_vibration') ?? true;
    if (!mounted) return;

    rollGuideDelayTimer?.cancel();
    rollGuideDelayTimer = null;
    if (rearm) rollGuideArmedTurn = null;
    setState(() {
      rollGuideEnabled = enabled;
      diceHandPreference = hand;
      if (!enabled || rearm) rollGuideVisible = false;
    });
    _syncRollGuide();
  }

  void _syncRollGuide() {
    if (!mounted) return;
    if (!_canOfferRollGuide) {
      _cancelRollGuide();
      return;
    }
    if (rollGuideVisible || rollGuideDelayTimer != null) return;
    if (rollGuideArmedTurn == engine.turnNumber) return;

    rollGuideArmedTurn = engine.turnNumber;
    final delay = completedGuidedRolls < 2
        ? _firstRollGuideDelay
        : _idleRollGuideDelay;
    rollGuideDelayTimer = Timer(delay, () {
      rollGuideDelayTimer = null;
      if (!mounted || !_canOfferRollGuide) return;
      setState(() {
        rollGuideVisible = true;
        rollGuidePulseSerial++;
      });
    });
  }

  void _cancelRollGuide({bool resetWindow = false, bool notify = true}) {
    rollGuideDelayTimer?.cancel();
    rollGuideDelayTimer = null;
    if (resetWindow) rollGuideArmedTurn = null;
    if (!rollGuideVisible) return;
    if (notify && mounted) {
      setState(() => rollGuideVisible = false);
    } else {
      rollGuideVisible = false;
    }
  }

  void _rollDiceFromHud() {
    if (!_tutorialAllowsRoll ||
        !_isLocallyControlledTurn ||
        engine.hasRolled ||
        engine.gameOver ||
        engine.effectResolving) {
      return;
    }
    _cancelRollGuide(notify: false);
    if (rollGuideEnabled) {
      completedGuidedRolls = math.min(completedGuidedRolls + 1, 2);
    }
    engine.roll();
    if (engine.matchFormat == MatchFormat.quickPop) {
      final command = engine.uniqueLegalMoveCommand;
      if (command != null) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        Future<void>.delayed(
          Duration(milliseconds: reduceMotion ? 80 : 620),
          () {
            if (!mounted || engine.gameOver || engine.effectResolving) return;
            engine.executeMoveCommand(command);
          },
        );
      }
    }
  }

  Future<void> _openGameSettings() async {
    _cancelRollGuide(resetWindow: true);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          themeId: 'theme_default',
          analytics: widget.analytics,
        ),
      ),
    );
    if (!mounted) return;
    await _loadRollGuidePreferences(rearm: true);
  }

  Future<void> _saveMatchCheckpoint() async {
    // Tutorial progress is enough to reconstruct this short lesson. Never let
    // it overwrite the player's real resumable match.
    if (_usesGuidedTutorial) return;
    final store = await SharedPreferences.getInstance();
    if (engine.gameOver) {
      await store.remove('active_match_checkpoint');
      return;
    }
    await store.setInt(
      'active_match_board_layout_version',
      activeMatchBoardLayoutVersion,
    );
    await store.setString(
      'active_match_checkpoint',
      jsonEncode({
        ...engine.checkpointRuleMetadata,
        'savedAt': DateTime.now().toIso8601String(),
        'analyticsMatchRef': analyticsMatch.correlation.anonymousMatchId,
        'analyticsFirstRollLogged': firstRollAnalyticsLogged,
        'online': widget.onlineSession != null,
        'mode': engine.mode.name,
        'cpuLevel': engine.cpuLevel,
        'opponent': widget.opponent,
        'elapsedSeconds': matchElapsed.inSeconds,
        'turn': engine.turnNumber,
        'currentPlayer': engine.currentPlayer.color.name,
        'dice': engine.dice,
        'remainingDice': engine.remainingDice,
        'hasRolled': engine.hasRolled,
        'chaosItemsPerSide': engine.chaosItemsPerSide,
        'items': engine.itemLoopIndices.toList(growable: false),
        'players': [
          for (final player in engine.players)
            {
              'color': player.color.name,
              'name': player.name,
              'tokens': [for (final token in player.tokens) token.progress],
              'inventory': player.inventory?.name,
              'shielded': player.shielded,
              'skippedTurns': player.skippedTurns,
            },
        ],
        'traps': [
          for (final trap in engine.traps)
            {
              'owner': trap.owner.name,
              'type': trap.type.name,
              'loopIndex': trap.loopIndex,
            },
        ],
        'onlineParticipants': [
          for (final participant
              in widget.onlineSession?.participants ??
                  const <OnlineParticipant>[])
            {
              'id': participant.id,
              'displayName': participant.displayName,
              'flag': participant.flag,
              'avatarId': participant.color == PlayerColor.red
                  ? widget.wallet?.equippedProductId(CosmeticCategory.avatar) ??
                        participant.avatarId
                  : participant.avatarId,
              'level': participant.level,
              'color': participant.color.name,
              'kind': participant.kind.name,
              'themeId': participant.color == PlayerColor.red
                  ? widget.wallet?.equippedProductId(CosmeticCategory.theme) ??
                        participant.loadout.themeId
                  : participant.loadout.themeId,
              'diceId': participant.color == PlayerColor.red
                  ? widget.wallet?.equippedProductId(CosmeticCategory.dice) ??
                        participant.loadout.diceId
                  : participant.loadout.diceId,
              'tokensId': participant.color == PlayerColor.red
                  ? widget.wallet?.equippedProductId(CosmeticCategory.tokens) ??
                        participant.loadout.tokensId
                  : participant.loadout.tokensId,
            },
        ],
      }),
    );
  }

  void _trackAnalyticsEvents() {
    for (final event in engine.eventHistory) {
      if (event.sequence <= lastAnalyticsEventSequence) continue;
      lastAnalyticsEventSequence = event.sequence;

      if (!_usesGuidedTutorial &&
          !firstRollAnalyticsLogged &&
          event.type == GameEventType.roll) {
        firstRollAnalyticsLogged = true;
        unawaited(
          widget.analytics.logEvent(
            MatchFirstRollEvent(
              match: analyticsMatch,
              secondsFromMatchStart: matchElapsed.inSeconds,
              turnNumber: math.max(1, event.turn),
            ),
          ),
        );
      }

      unawaited(_trackTutorialEvent(event));
      unawaited(_trackProgressionEvent(event));

      final localPlacement = engine.placementFor(PlayerColor.red);
      if (localPlacement != null) {
        _logMatchCompleted(placement: localPlacement);
      }
    }
  }

  void _logMatchCompleted({int? placement}) {
    if (_usesGuidedTutorial ||
        matchCompletionAnalyticsLogged ||
        matchAbandonAnalyticsLogged) {
      return;
    }
    matchCompletionAnalyticsLogged = true;
    unawaited(
      widget.analytics.logEvent(
        MatchCompletedEvent(
          match: analyticsMatch,
          reason: MatchCompletionReason.reachedHome,
          placement: placement,
          durationSeconds: matchElapsed.inSeconds,
          turnsPlayed: math.max(0, engine.turnNumber),
        ),
      ),
    );
  }

  Future<void> _trackTutorialEvent(GameEvent event) async {
    final controller = widget.tutorial;
    if (!_usesGuidedTutorial ||
        controller == null ||
        controller.lifecycle != TutorialLifecycle.inProgress ||
        event.playerColor != PlayerColor.red) {
      return;
    }
    final previousStep = controller.currentStep;
    switch (controller.currentStep) {
      case TutorialStep.firstRoll when event.type == GameEventType.roll:
        await controller.completeStep(TutorialStep.firstRoll);
      case TutorialStep.releaseToken when event.type == GameEventType.departure:
        await controller.completeStep(TutorialStep.releaseToken);
      case TutorialStep.chooseMove when event.type == GameEventType.move:
        await controller.completeStep(TutorialStep.chooseMove);
      case TutorialStep.safeSquare when event.type == GameEventType.move:
        final progress = event.toProgress;
        if (progress != null &&
            progress >= 0 &&
            progress < GameEngine.commonPathLength &&
            GameEngine.safeLoopIndices.contains(
              engine.loopIndex(event.playerColor, progress),
            )) {
          await controller.completeStep(TutorialStep.safeSquare);
        }
      case TutorialStep.capture when event.type == GameEventType.capture:
        await controller.completeStep(TutorialStep.capture);
      case TutorialStep.reachHome when event.type == GameEventType.goal:
        await controller.completeStep(TutorialStep.reachHome);
      default:
        break;
    }
    if (controller.currentStep != previousStep) {
      tutorialScenario?.prepareFor(controller.currentStep);
    }
    if (!mounted) return;
    setState(() {
      tutorialCompletionVisible =
          _usesGuidedTutorial &&
          controller.lifecycle == TutorialLifecycle.completed;
    });
  }

  Future<void> _trackProgressionEvent(GameEvent event) async {
    if (_usesGuidedTutorial) return;
    final controller = widget.progression;
    if (controller == null || event.playerColor != PlayerColor.red) return;
    final eventId = '${progressionEventRunRef}_${event.sequence}';
    final transactions = <ProgressionTransaction>[];
    final releasedQuickPopToken =
        engine.matchFormat == MatchFormat.quickPop &&
        event.type == GameEventType.move &&
        event.fromProgress == 0;
    if (event.type == GameEventType.departure || releasedQuickPopToken) {
      final update = await controller.recordTokenReleased(
        eventId: '${eventId}_release',
      );
      transactions.addAll(update.transactions);
    }
    if (event.type == GameEventType.move) {
      final from = event.fromProgress;
      final to = event.toProgress;
      if (from != null && to != null && to > from) {
        final update = await controller.recordCellsMoved(
          eventId: '${eventId}_move',
          cells: to - from,
        );
        transactions.addAll(update.transactions);
      }
    }
    await _creditProgression(transactions);
  }

  Future<void> _creditProgression(
    Iterable<ProgressionTransaction> transactions,
  ) async {
    final wallet = widget.wallet;
    if (wallet == null) return;
    for (final transaction in transactions) {
      final balanceBefore = wallet.balance;
      final result = await wallet.applyCredit(
        transactionId: transaction.id,
        amount: transaction.amount,
      );
      if (result != ApplyCreditResult.applied) continue;
      final source = switch (transaction.source) {
        ProgressionTransactionSource.matchCompletion =>
          CurrencySource.matchCompletion,
        ProgressionTransactionSource.placement => CurrencySource.placement,
        ProgressionTransactionSource.firstMatchOfDay =>
          CurrencySource.firstMatchOfDay,
        ProgressionTransactionSource.dailyMoveMission ||
        ProgressionTransactionSource.dailyReleaseMission ||
        ProgressionTransactionSource.weeklyMatchesMission =>
          CurrencySource.mission,
        ProgressionTransactionSource.rewardedDouble =>
          CurrencySource.rewardedAd,
      };
      unawaited(
        widget.analytics.logEvent(
          CurrencyEvent(
            flow: CurrencyFlow.earned,
            source: source,
            amount: transaction.amount,
            balanceBefore: balanceBefore,
            balanceAfter: wallet.balance,
            anonymousTransactionId: _newAnalyticsReference('transaction'),
            match: transaction.matchId == null ? null : analyticsMatch,
          ),
        ),
      );
      final progression = widget.progression;
      if (progression != null) {
        final mission = switch (transaction.source) {
          ProgressionTransactionSource.firstMatchOfDay => (
            MissionKind.finishOneMatch,
            progression.dailyMissions.matchCompleted ? 1 : 0,
            1,
          ),
          ProgressionTransactionSource.dailyMoveMission => (
            MissionKind.move20Cells,
            progression.dailyMissions.cellsMoved,
            progression.dailyMissions.moveTarget,
          ),
          ProgressionTransactionSource.dailyReleaseMission => (
            MissionKind.releaseToken,
            progression.dailyMissions.tokenReleased ? 1 : 0,
            1,
          ),
          ProgressionTransactionSource.weeklyMatchesMission => (
            MissionKind.finish7Matches,
            progression.weeklyMission.matchesCompleted,
            progression.weeklyMission.target,
          ),
          _ => null,
        };
        if (mission case final value?) {
          unawaited(
            widget.analytics.logEvent(
              MissionRewardEvent(
                mission: value.$1,
                rewardCoins: transaction.amount,
                progress: value.$2,
                target: value.$3,
                correlation: analyticsMatch.correlation,
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _settleMatchRewards() async {
    if (_usesGuidedTutorial) return;
    final progression = widget.progression;
    if (progression == null) return;
    final placement = engine.placementFor(PlayerColor.red);
    // The first finisher ends the active match even when the local player has
    // not reached home yet. Award participation at that point so losing never
    // means "no progress". If the player keeps watching, the placement reward
    // is added later when their position becomes authoritative.
    if (!engine.gameOver && placement == null) return;
    final matchId =
        analyticsMatch.correlation.anonymousMatchId ??
        'local_${engine.hashCode}';
    ProgressionUpdate update;
    if (!matchCompletionRewardSettled) {
      matchCompletionRewardSettled = true;
      if (placement != null) matchPlacementRewardSettled = true;
      update = await progression.recordMatchCompleted(
        matchId: matchId,
        placement: placement,
      );
    } else if (placement != null && !matchPlacementRewardSettled) {
      matchPlacementRewardSettled = true;
      update = await progression.recordPlacement(
        matchId: matchId,
        placement: placement,
      );
    } else {
      return;
    }
    await _creditProgression(update.transactions);
    matchBasePayout = progression.matchPayout(matchId);
    endMatchRewardClaimed = progression.rewardedDoubleClaimed(matchId);
    if (endMatchRewardClaimed) rewardedDecisionAnalyticsLogged = true;
    if (update.coinsAwarded > 0) {
      matchRewardCoinsAwarded += update.coinsAwarded;
    } else if (matchRewardCoinsAwarded == 0) {
      matchRewardCoinsAwarded = progression.matchCoinsAwarded(matchId);
    }
    _logRewardedOfferIfEligible();
    if (mounted) setState(() {});
  }

  void _logRewardedOfferIfEligible() {
    if (rewardedOfferAnalyticsLogged ||
        endMatchRewardClaimed ||
        widget.wallet == null) {
      return;
    }
    final ads = MobileAdsScope.maybeOf(context);
    final reward = widget.progression == null
        ? (engine.standingsComplete ? 100 : 0)
        : matchPlacementRewardSettled
        ? matchBasePayout
        : 0;
    if (reward <= 0 || ads == null || !ads.supported) return;
    rewardedOfferAnalyticsLogged = true;
    rewardedOfferedCoins = reward;
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: RewardedAdStage.offered,
          placement: RewardedAdPlacement.postMatchReward,
          rewardCoins: reward,
          match: analyticsMatch,
        ),
      ),
    );
  }

  void _logRewardedDeclinedIfIgnored() {
    if (!rewardedOfferAnalyticsLogged ||
        rewardedDecisionAnalyticsLogged ||
        rewardedOfferedCoins <= 0) {
      return;
    }
    rewardedDecisionAnalyticsLogged = true;
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: RewardedAdStage.declined,
          placement: RewardedAdPlacement.postMatchReward,
          rewardCoins: rewardedOfferedCoins,
          match: analyticsMatch,
        ),
      ),
    );
  }

  void _onGameChanged() {
    if (!mounted) return;
    _trackAnalyticsEvents();
    final feedbackEvents = engine.eventHistory
        .where((event) => event.sequence > lastAudioEventSequence)
        .toList(growable: false);
    if (feedbackEvents.isNotEmpty) {
      lastAudioEventSequence = feedbackEvents.last.sequence;
      unawaited(feedbackController.process(feedbackEvents));
      for (final event in feedbackEvents) {
        _reactToMatchEvent(event);
      }
    }
    if (selectedToken != null &&
        (engine.gameOver ||
            !_isLocallyControlledTurn ||
            !engine.hasRolled ||
            engine.effectResolving ||
            selectedToken!.owner != engine.currentPlayer.color ||
            (engine.legalDiceFor(selectedToken!).isEmpty &&
                !engine.canMoveUsingAllDice(selectedToken!)))) {
      selectedToken = null;
    }
    if (engine.gameOver && engine.winner != null) {
      _queueVictoryCelebration();
    }
    unawaited(_settleMatchRewards());
    _logRewardedOfferIfEligible();
    setState(() {});
    _syncRollGuide();
    if (!engine.gameOver && _isCpuControlledTurn && !cpuThinking) {
      _playCpuTurn();
    }
  }

  void _queueVictoryCelebration() {
    if (victoryQueued || engine.winner == null) return;
    victoryQueued = true;
    if (rewardedPreloadRequested) {
      MobileAdsScope.maybeOf(context)?.preloadRewarded();
    }
    victoryTimer?.cancel();
    final delay = engine.effectKind == PowerEffectKind.goal
        ? const Duration(milliseconds: 1650)
        : const Duration(milliseconds: 650);
    victoryTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => showVictory = true);
      if (!rematchOfferAnalyticsLogged) {
        rematchOfferAnalyticsLogged = true;
        unawaited(
          widget.analytics.logEvent(
            RematchEvent(match: analyticsMatch, stage: RematchStage.offered),
          ),
        );
      }
      _logRewardedOfferIfEligible();
    });
  }

  /// Optional coin bonus offered after the local placement is known.
  /// Navigation never opens an advertisement.
  Future<void> _watchEndMatchRewarded() async {
    if (endMatchRewardInProgress ||
        endMatchRewardClaimed ||
        postVictoryNavigationInProgress ||
        widget.wallet == null) {
      return;
    }
    final ads = MobileAdsScope.maybeOf(context);
    if (ads == null || !ads.supported) return;
    final rewardAmount = widget.progression == null ? 100 : matchBasePayout;
    if (rewardAmount <= 0 ||
        (widget.progression != null && !matchPlacementRewardSettled)) {
      return;
    }

    finalReturnTimer?.cancel();
    final legacyBalanceBefore = widget.wallet?.balance;
    setState(() => endMatchRewardInProgress = true);
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: RewardedAdStage.started,
          placement: RewardedAdPlacement.postMatchReward,
          rewardCoins: rewardAmount,
          match: analyticsMatch,
        ),
      ),
    );
    var adResult = RewardedAdResult.failed;
    try {
      adResult = await ads.showRewardedWithResult();
    } catch (_) {
      debugPrint('Optional post-match rewarded ad could not be completed.');
    }
    final earned = adResult.didEarnReward;
    rewardedDecisionAnalyticsLogged = true;
    var creditedAmount = 0;
    if (earned) {
      final progression = widget.progression;
      if (progression == null) {
        await widget.wallet?.addCoins(rewardAmount);
        creditedAmount = rewardAmount;
      } else {
        final matchId =
            analyticsMatch.correlation.anonymousMatchId ??
            'local_${engine.hashCode}';
        final result = await progression.claimRewardedDouble(matchId: matchId);
        final transaction = result.transaction;
        if (transaction != null) {
          await _creditProgression([transaction]);
          creditedAmount = transaction.amount;
        }
      }
    }
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: switch (adResult) {
            RewardedAdResult.earned => RewardedAdStage.completed,
            RewardedAdResult.dismissed => RewardedAdStage.declined,
            RewardedAdResult.unavailable => RewardedAdStage.unavailable,
            RewardedAdResult.failed => RewardedAdStage.failed,
          },
          placement: RewardedAdPlacement.postMatchReward,
          rewardCoins: rewardAmount,
          match: analyticsMatch,
        ),
      ),
    );
    if (earned && widget.progression == null) {
      unawaited(
        widget.analytics.logEvent(
          CurrencyEvent(
            flow: CurrencyFlow.earned,
            source: CurrencySource.rewardedAd,
            amount: rewardAmount,
            balanceBefore: legacyBalanceBefore,
            balanceAfter: widget.wallet?.balance,
            anonymousTransactionId: _newAnalyticsReference(
              'reward_transaction',
            ),
            match: analyticsMatch,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      endMatchRewardInProgress = false;
      if (earned) endMatchRewardClaimed = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: PopText(switch (adResult) {
          RewardedAdResult.earned =>
            creditedAmount > 0
                ? '¡Duplicaste tu premio: +$creditedAmount monedas!'
                : 'Este premio ya estaba duplicado.',
          RewardedAdResult.dismissed =>
            'No se completó el anuncio. Puedes intentarlo otra vez.',
          RewardedAdResult.unavailable =>
            'No hay un anuncio disponible ahora. Inténtalo más tarde.',
          RewardedAdResult.failed =>
            'No se pudo mostrar el anuncio. Tus monedas no cambiaron.',
        }),
      ),
    );
  }

  void _playAgain() {
    finalReturnTimer?.cancel();
    _logMatchCompleted(placement: engine.placementFor(PlayerColor.red));
    _logRewardedDeclinedIfIgnored();
    final playType = _playTypeForSession(widget.onlineSession);
    final nextMatchRef = _newAnalyticsReference(
      playType == MatchPlayType.cpu ? 'cpu_match' : 'online_match',
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(
          opponent: widget.opponent,
          mode: engine.mode,
          matchFormat: engine.matchFormat,
          wallet: widget.wallet,
          progression: widget.progression,
          tutorial: widget.tutorial,
          localProfile: widget.localProfile,
          onlineSession: widget.onlineSession,
          analytics: widget.analytics,
          analyticsMatchRef: nextMatchRef,
          isRematch: true,
          cpuThinkDelayProvider: widget.cpuThinkDelayProvider,
        ),
      ),
    );
  }

  Future<void> _runPostVictoryNavigation(
    Future<void> Function() navigate,
  ) async {
    if (postVictoryNavigationInProgress || endMatchRewardInProgress) return;
    finalReturnTimer?.cancel();
    setState(() => postVictoryNavigationInProgress = true);

    if (!mounted) return;
    await navigate();
    if (mounted) {
      setState(() => postVictoryNavigationInProgress = false);
    }
  }

  Future<void> _playAgainFromVictory() =>
      _runPostVictoryNavigation(() async => _playAgain());

  Future<void> _homeFromVictory() {
    unawaited(
      widget.analytics.logEvent(
        RematchEvent(match: analyticsMatch, stage: RematchStage.declined),
      ),
    );
    return _runPostVictoryNavigation(_returnToStart);
  }

  void _continueWatching() {
    if (!engine.continueAfterWinner()) return;
    victoryTimer?.cancel();
    finalReturnTimer?.cancel();
    setState(() {
      showVictory = false;
      victoryQueued = false;
    });
  }

  List<_FinalStandingEntry> _standingEntries(
    Map<PlayerColor, String?> avatarIds,
  ) {
    return [
      for (final standing in engine.standings)
        () {
          final player = engine.players.firstWhere(
            (candidate) => candidate.color == standing.competitor,
          );
          final participant = widget.onlineSession?.participantForColor(
            standing.competitor,
          );
          final localProfile = standing.competitor == PlayerColor.red
              ? widget.localProfile
              : null;
          return _FinalStandingEntry(
            placement: standing.placement,
            points: standing.points,
            player: player,
            displayName:
                participant?.displayName ?? localProfile?.name ?? player.name,
            flag: participant?.flag ?? localProfile?.flag,
            level: participant?.level ?? localProfile?.level,
            avatarId:
                avatarIds[standing.competitor] ??
                (player.isHuman ? 'avatar_default' : 'avatar_robot'),
            reachedGoal: player.tokens.every((token) => token.finished),
          );
        }(),
    ];
  }

  Future<void> _showSafeChatPicker() async {
    _cancelRollGuide();
    final session = widget.onlineSession;
    if (session == null || safeChat == null) return;
    final languageCode = appLanguageCodeOf(context);
    final phraseId = await showModalBottomSheet<SafeChatPhraseId>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB8071B40),
      builder: (sheetContext) => _SafeChatPickerSheet(
        languageCode: languageCode,
        onSelected: (selectedPhrase) =>
            Navigator.pop(sheetContext, selectedPhrase),
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
    if (phraseId != null) _sendSafeChat(phraseId);
  }

  Future<void> _showOwnedCosmetics() async {
    _cancelRollGuide();
    final wallet = widget.wallet;
    if (wallet == null) return;
    _cancelTokenSelection();

    void equipped() {
      if (!mounted) return;
      setState(() {});
      unawaited(_saveMatchCheckpoint());
    }

    final desktop = MediaQuery.sizeOf(context).width >= 700;
    if (desktop) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          key: const ValueKey('owned-cosmetics-dialog'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
            child: _OwnedCosmeticsPicker(
              wallet: wallet,
              onEquipped: equipped,
              onClose: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .82,
        child: _OwnedCosmeticsPicker(
          wallet: wallet,
          onEquipped: equipped,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  void _sendSafeChat(SafeChatPhraseId phraseId) {
    final session = widget.onlineSession;
    final controller = safeChat;
    if (session == null || controller == null) return;
    final sender = session.participantForColor(PlayerColor.red);
    final result = controller.send(senderId: sender.id, phraseId: phraseId);
    if (result != SafeChatSendResult.sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: PopText('Espera un momento antes de enviar otro mensaje.'),
        ),
      );
      return;
    }
    _presentSafeChat(controller.messages.last, sender);
    chatReactionTimer?.cancel();
    chatReactionTimer = Timer(const Duration(milliseconds: 1250), () {
      if (!mounted || widget.onlineSession == null) return;
      final opponents = session.participants
          .where((participant) => participant.color != PlayerColor.red)
          .toList(growable: false);
      final variation = phraseId.index + engine.turnNumber;
      final opponent = opponents[variation % opponents.length];
      final reaction = const SafeChatReactionPolicy().phraseFor(
        SafeChatMoment.greatMove,
        variation: variation,
      );
      final sent = controller.send(senderId: opponent.id, phraseId: reaction);
      if (sent == SafeChatSendResult.sent) {
        _presentSafeChat(controller.messages.last, opponent);
      }
    });
  }

  /// Makes automated opponents react only with reviewed, preset phrases. The
  /// event decides the phrase, so chat follows the match instead of sending
  /// random comments at confusing moments.
  void _reactToMatchEvent(GameEvent event) {
    final session = widget.onlineSession;
    final controller = safeChat;
    if (session == null || controller == null) return;

    SafeChatMoment? moment;
    PlayerColor? senderColor;
    switch (event.type) {
      case GameEventType.capture:
        senderColor = event.playerColor == PlayerColor.red
            ? event.targetColor
            : event.playerColor;
        moment = event.playerColor == PlayerColor.red
            ? SafeChatMoment.wasCaptured
            : SafeChatMoment.capturedOpponent;
        break;
      case GameEventType.goal:
        senderColor = event.playerColor;
        moment = SafeChatMoment.reachedGoal;
        break;
      case GameEventType.trap:
        if (event.targetColor == null) return; // A hidden trap was armed.
        senderColor = event.targetColor;
        final wentToBase =
            event.description.contains('cárcel') ||
            event.description.contains('BOMBA');
        moment = wentToBase
            ? SafeChatMoment.returnedToBase
            : SafeChatMoment.fellIntoTrap;
        break;
      case GameEventType.threeDoublesPenalty:
        senderColor = event.playerColor;
        moment = SafeChatMoment.returnedToBase;
        break;
      default:
        return;
    }
    if (senderColor == null) return;
    final sender = session.participantForColor(senderColor);
    if (!sender.isVirtuallyControlled) return;

    eventChatTimer?.cancel();
    eventChatTimer = Timer(
      Duration(milliseconds: 550 + (event.sequence % 4) * 180),
      () {
        if (!mounted) return;
        final phrase = const SafeChatReactionPolicy().phraseFor(
          moment!,
          variation: event.turn + event.sequence,
        );
        final result = controller.send(senderId: sender.id, phraseId: phrase);
        if (result == SafeChatSendResult.sent) {
          _presentSafeChat(controller.messages.last, sender);
        }
      },
    );
  }

  void _presentSafeChat(SafeChatMessage message, OnlineParticipant sender) {
    if (!mounted) return;
    chatTimer?.cancel();
    setState(() {
      visibleChatMessage = message;
      visibleChatSender = sender;
    });
    chatTimer = Timer(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      setState(() {
        visibleChatMessage = null;
        visibleChatSender = null;
      });
    });
  }

  Future<void> _returnToStart() => _leaveToHome(discardSavedMatch: true);

  void _logMatchAbandoned(MatchAbandonReason reason) {
    if (matchAbandonAnalyticsLogged || matchCompletionAnalyticsLogged) return;
    matchAbandonAnalyticsLogged = true;
    unawaited(
      widget.analytics.logEvent(
        MatchAbandonedEvent(
          match: analyticsMatch,
          reason: reason,
          secondsPlayed: matchElapsed.inSeconds,
          turnsPlayed: math.max(0, engine.turnNumber),
        ),
      ),
    );
  }

  Future<void> _leaveToHome({required bool discardSavedMatch}) async {
    finalReturnTimer?.cancel();
    if (discardSavedMatch) {
      if (engine.gameOver) {
        _logMatchCompleted(placement: engine.placementFor(PlayerColor.red));
        _logRewardedDeclinedIfIgnored();
      } else {
        _logMatchAbandoned(MatchAbandonReason.backButton);
      }
    }
    final store = await SharedPreferences.getInstance();
    if (discardSavedMatch) {
      await store.remove('active_match_checkpoint');
    } else {
      await _saveMatchCheckpoint();
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    navigator.pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _handleBackRequest() async {
    if (engine.gameOver || !mounted) return;
    if (_usesGuidedTutorial) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
      return;
    }
    if (_sessionHasRemoteHuman(widget.onlineSession)) {
      final leaveOnline = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => _MatchExitDialogFrame(
          icon: Icons.public_off_rounded,
          iconColor: PopColors.red,
          title: '¿ABANDONAR PARTIDA?',
          message:
              'Esta partida es online. Si sales ahora, perderás la partida.',
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const PopText('SEGUIR JUGANDO'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PopColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const PopText('SALIR Y PERDER'),
            ),
          ],
        ),
      );
      if (leaveOnline == true) await _leaveToHome(discardSavedMatch: true);
      return;
    }

    final cpuExit = await showDialog<_CpuExitChoice>(
      context: context,
      builder: (dialogContext) => _MatchExitDialogFrame(
        icon: Icons.save_rounded,
        iconColor: PopColors.blue,
        title: '¿GUARDAR PARTIDA?',
        message: 'Podrás continuar contra CPU desde exactamente este punto.',
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () =>
                Navigator.pop(dialogContext, _CpuExitChoice.cancel),
            child: const PopText('CANCELAR'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD867),
              side: const BorderSide(color: Color(0xFFFFD867), width: 1.5),
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, _CpuExitChoice.discard),
            child: const PopText('SALIR SIN GUARDAR'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PopColors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, _CpuExitChoice.save),
            child: const PopText('GUARDAR Y SALIR'),
          ),
        ],
      ),
    );
    if (cpuExit == _CpuExitChoice.save) {
      await _leaveToHome(discardSavedMatch: false);
    } else if (cpuExit == _CpuExitChoice.discard) {
      await _leaveToHome(discardSavedMatch: true);
    }
  }

  Future<void> _playCpuTurn() async {
    cpuThinking = true;
    await Future<void>.delayed(_nextCpuThinkDelay());
    if (!mounted || engine.gameOver || !_isCpuControlledTurn) {
      cpuThinking = false;
      return;
    }
    if (engine.currentPlayer.inventory != null &&
        engine.currentPlayer.inventory != PowerUp.shield &&
        engine.cpuLevel != 'Fácil') {
      engine.usePowerUp();
    }
    if (!engine.hasRolled) engine.roll();
    await Future<void>.delayed(_nextCpuThinkDelay());
    while (mounted &&
        !engine.gameOver &&
        _isCpuControlledTurn &&
        engine.hasRolled &&
        engine.remainingDice.isNotEmpty) {
      final token = engine.chooseCpuMove();
      if (token == null) break;
      final die = engine.chooseCpuDie(token);
      final usedAllDice = die == null && engine.canMoveUsingAllDice(token);
      final moved = usedAllDice
          ? engine.moveTokenUsingAllDice(token)
          : die != null && engine.moveToken(token, die: die);
      if (!moved) break;
      await Future<void>.delayed(
        Duration(
          milliseconds:
              (300 +
                      (usedAllDice
                              ? engine.dice.fold<int>(
                                  0,
                                  (total, value) => total + value,
                                )
                              : die!) *
                          58)
                  .clamp(550, 1350)
                  .toInt(),
        ),
      );
      while (mounted && engine.effectResolving) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    cpuThinking = false;
    if (mounted && !engine.gameOver && _isCpuControlledTurn) {
      Future<void>.microtask(_onGameChanged);
    }
  }

  Duration _nextCpuThinkDelay() {
    final suppliedDelay = widget.cpuThinkDelayProvider?.call();
    if (suppliedDelay != null) return suppliedDelay;
    return Duration(milliseconds: 1000 + cpuPacingRandom.nextInt(1001));
  }

  Offset get _mobileBoardFocus => switch (mobileBoardCameraMode) {
    _MobileBoardCameraMode.manual => mobileBoardManualFocus,
    _MobileBoardCameraMode.fullBoard => const Offset(.5, .5),
  };

  void _setMobileBoardManualFocus(Offset normalizedFocus) {
    _cancelRollGuide();
    final next = clampMobileBoardFocusForTesting(normalizedFocus);
    if (mobileBoardCameraMode == _MobileBoardCameraMode.manual &&
        mobileBoardManualFocus == next) {
      return;
    }
    setState(() {
      mobileBoardCameraMode = _MobileBoardCameraMode.manual;
      mobileBoardManualFocus = next;
    });
  }

  void _showFullMobileBoard() {
    if (mobileBoardCameraMode == _MobileBoardCameraMode.fullBoard) return;
    setState(() => mobileBoardCameraMode = _MobileBoardCameraMode.fullBoard);
  }

  Offset? _boardCellForToken(GameToken token) {
    return _displayTokenCells(engine, compactPhone: compactPhoneBoard)[token];
  }

  GameToken? _ownTokenAt(
    Offset tapped, {
    double? radius,
    GameToken? excluding,
  }) {
    GameToken? nearest;
    var best = radius ?? (compactPhoneBoard ? .78 : .70);
    for (final token in engine.currentPlayer.tokens) {
      if (token.finished || identical(token, excluding)) continue;
      final cell = _boardCellForToken(token);
      if (cell == null) continue;
      final distance = (cell - tapped).distance;
      if (distance < best) {
        nearest = token;
        best = distance;
      }
    }
    return nearest;
  }

  bool _trySelectOwnTokenAt(Offset tapped, {GameToken? excluding}) {
    final tappedToken = _ownTokenAt(tapped, excluding: excluding);
    if (tappedToken == null) return false;
    if (!_tutorialAllowsToken(tappedToken)) return true;
    if (!identical(tappedToken, selectedToken)) {
      final canSelect =
          engine.legalDiceFor(tappedToken).isNotEmpty ||
          engine.canMoveUsingAllDice(tappedToken);
      setState(() {
        selectedToken = canSelect ? tappedToken : null;
        if (canSelect) {
          mobileBoardCameraMode = _MobileBoardCameraMode.fullBoard;
        }
      });
    }
    return true;
  }

  bool _trySelectOwnTokenAtBoardPosition(
    Offset localPosition,
    double boardSize, {
    bool excludeSelected = false,
  }) {
    if (!_isLocallyControlledTurn ||
        engine.effectResolving ||
        !engine.hasRolled) {
      return false;
    }
    final tapped = _BoardGeometry(
      boardSize,
      compactPhone: compactPhoneBoard,
    ).toLogical(localPosition);
    return _trySelectOwnTokenAt(
      tapped,
      excluding: excludeSelected ? selectedToken : null,
    );
  }

  void _tapBoard(Offset localPosition, double boardSize) {
    if (!_isLocallyControlledTurn || engine.effectResolving) return;
    final tapped = _BoardGeometry(
      boardSize,
      compactPhone: compactPhoneBoard,
    ).toLogical(localPosition);
    if (!engine.hasRolled) {
      _cancelRollGuide();
      return;
    }
    if (_trySelectOwnTokenAt(tapped)) return;
    final selectedDestination = _visibleMoveDestinationPreviews(
      selectedToken,
    ).where((preview) => _moveDestinationPath(preview, 1).contains(tapped));
    if (selectedDestination.isNotEmpty) {
      final preview = selectedDestination.first;
      if (preview.usesAllDice) {
        _moveSelectedTokenUsingAllDice();
      } else {
        _moveSelectedToken(preview.value);
      }
      return;
    }
    _cancelTokenSelection();
  }

  void _moveSelectedToken(int die) {
    final token = selectedToken;
    if (token == null ||
        engine.effectResolving ||
        !_tutorialAllowsMove(token, die) ||
        !engine.legalDiceFor(token).contains(die)) {
      return;
    }
    setState(() => selectedToken = null);
    engine.moveToken(token, die: die);
  }

  void _moveSelectedTokenUsingAllDice() {
    final token = selectedToken;
    if (token == null ||
        engine.effectResolving ||
        !_tutorialAllowsMove(
          token,
          engine.allDiceTotalFor(token) ?? -1,
          usesAllDice: true,
        ) ||
        !engine.canMoveUsingAllDice(token)) {
      return;
    }
    setState(() => selectedToken = null);
    engine.moveTokenUsingAllDice(token);
  }

  void _cancelTokenSelection() {
    if (selectedToken == null) return;
    setState(() => selectedToken = null);
  }

  Widget? _buildMovePopup() {
    final token = selectedToken;
    if (token == null || engine.effectResolving) return null;
    final choices = engine
        .legalDieValuesFor(token)
        .where((die) => _tutorialAllowsMove(token, die))
        .toList(growable: false);
    final rawAllDiceTotal = engine.allDiceTotalFor(token);
    final allDiceTotal =
        rawAllDiceTotal != null &&
            _tutorialAllowsMove(token, rawAllDiceTotal, usesAllDice: true)
        ? rawAllDiceTotal
        : null;
    if (choices.isEmpty && allDiceTotal == null) return null;
    final twentyStepColor = _twentyStepGuideColor(token.id);
    final captureTargetsByDie = <int, GameToken>{};
    for (final choice in choices) {
      final target = engine.captureTargetFor(token, choice);
      if (target != null) captureTargetsByDie[choice] = target;
    }
    return _TokenMovePopup(
      tokenNumber: token.id + 1,
      tokenInNest: token.inNest,
      choices: choices,
      twentyStepColor: twentyStepColor,
      homeEntryCaptureChoices: {
        for (final choice in choices)
          if (engine.isHomeEntryCaptureMove(token, choice)) choice,
      },
      captureTargetsByDie: captureTargetsByDie,
      rolledDice: engine.dice,
      onChoice: _moveSelectedToken,
      allDiceTotal: allDiceTotal,
      allDiceCaptureTarget: allDiceTotal == null
          ? null
          : engine.captureTargetUsingAllDice(token),
      onAllDice: _moveSelectedTokenUsingAllDice,
      onCancel: _cancelTokenSelection,
    );
  }

  Widget? _buildTrapAlert() {
    final kind = engine.effectKind;
    if (!engine.effectResolving ||
        (kind != PowerEffectKind.triggered &&
            kind != PowerEffectKind.blocked)) {
      return null;
    }
    final type = engine.effectPowerUp;
    final title = kind == PowerEffectKind.blocked
        ? 'ESCUDO ACTIVADO'
        : switch (type) {
            PowerUp.glueTrap => 'CAÍSTE EN PEGAMENTO',
            PowerUp.setbackTrap => 'CAÍSTE EN RETROCESO',
            PowerUp.prisonTrap => 'CAÍSTE EN TRAMPA CÁRCEL',
            PowerUp.bomb => 'CAÍSTE EN UNA BOMBA',
            _ => 'TRAMPA ACTIVADA',
          };
    final color = kind == PowerEffectKind.blocked
        ? PopColors.blue
        : switch (type) {
            PowerUp.glueTrap => const Color(0xFF7B61FF),
            PowerUp.setbackTrap => const Color(0xFFFF8A24),
            PowerUp.prisonTrap || PowerUp.bomb => PopColors.red,
            _ => PopColors.yellow,
          };
    final icon = kind == PowerEffectKind.blocked
        ? Icons.shield_rounded
        : switch (type) {
            PowerUp.glueTrap => Icons.pause_circle_filled_rounded,
            PowerUp.setbackTrap => Icons.fast_rewind_rounded,
            PowerUp.prisonTrap => Icons.lock_rounded,
            PowerUp.bomb => Icons.local_fire_department_rounded,
            _ => Icons.warning_amber_rounded,
          };
    return _TrapAlertBanner(
      title: title,
      message: engine.message,
      color: color,
      icon: icon,
    );
  }

  Widget? _buildTrapDiagnostics() {
    if (!trapDiagnosticsEnabled || !engine.isChaos || engine.traps.isEmpty) {
      return null;
    }
    return _TrapDiagnosticsStrip(engine: engine);
  }

  Widget? _buildSpectatorBar({required bool compact}) {
    if (!engine.spectatorContinuationActive || engine.gameOver) return null;
    return Container(
      key: const ValueKey('spectator-bar'),
      margin: const EdgeInsets.fromLTRB(4, 3, 4, 0),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: PopColors.navy.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PopColors.green, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: PopColors.navy.withValues(alpha: .20),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_rounded,
            color: PopColors.green,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PopText(
                  compact ? 'OBSERVANDO' : 'MODO ESPECTADOR',
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
                if (!compact)
                  PopText(
                    'La partida continúa por los lugares restantes.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .74),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            height: compact ? 28 : 32,
            child: OutlinedButton.icon(
              key: const ValueKey('spectator-exit-button'),
              onPressed: _returnToStart,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: PopColors.red, width: 1.5),
                backgroundColor: PopColors.red.withValues(alpha: .22),
                padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(Icons.exit_to_app_rounded, size: compact ? 14 : 16),
              label: const PopText(
                'SALIR',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildChatBanner() {
    final message = visibleChatMessage;
    final sender = visibleChatSender;
    if (message == null || sender == null) return null;
    return _SafeChatBanner(
      sender: sender,
      text: message.textForLanguage(appLanguageCodeOf(context)),
    );
  }

  void _showPowerStatus() {
    _cancelRollGuide();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PopText(
                  'Poderes y trampas',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const PopText(
                  'El Escudo se guarda y se activa solo. Cada trampa '
                  'se arma en el cristal que la entregó, y puedes mantener varias en el tablero. '
                  'Las trampas rivales permanecen ocultas hasta activarse.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
                if (trapDiagnosticsEnabled && engine.traps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _TrapDiagnosticsNotice(),
                ],
                const SizedBox(height: 14),
                for (final player in engine.players)
                  _PowerStatusTile(
                    engine: engine,
                    player: player,
                    revealTrapDetails: trapDiagnosticsEnabled,
                    participant: widget.onlineSession?.participantForColor(
                      player.color,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventHistory() {
    _cancelRollGuide();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final events = engine.eventHistory.reversed.toList(growable: false);
        final height = MediaQuery.sizeOf(context).height * .82;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: DecoratedBox(
                  key: const ValueKey('game-event-history-sheet'),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F9FE),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: PopColors.blue.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.history_rounded,
                                color: PopColors.blue,
                              ),
                            ),
                            const SizedBox(width: 11),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PopText(
                                    'Historial de la partida',
                                    style: TextStyle(
                                      color: PopColors.navy,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  PopText(
                                    'Más reciente primero',
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: appTranslate(context, 'Cerrar'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
                        child: PopText(
                          'Cada acción importante queda guardada durante esta partida.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          key: const ValueKey('game-event-history-list'),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
                          itemCount: events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _GameEventHistoryTile(event: events[index]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localParticipant = widget.onlineSession?.participantForColor(
      PlayerColor.red,
    );
    final currentParticipant = widget.onlineSession?.participantForColor(
      engine.currentPlayer.color,
    );
    final localThemeId =
        widget.wallet?.equippedProductId(CosmeticCategory.theme) ??
        localParticipant?.loadout.themeId;
    final playerThemeIds = <PlayerColor, String?>{
      if (widget.onlineSession case final onlineSession?)
        for (final participant in onlineSession.participants)
          participant.color: participant.loadout.themeId,
      // The live wallet must win over the snapshot captured when online
      // matchmaking began so changing an owned item updates immediately.
      PlayerColor.red: localThemeId,
    };
    final localTokenStyleId =
        widget.wallet?.equippedProductId(CosmeticCategory.tokens) ??
        localParticipant?.loadout.tokensId;
    final tokenStyleIds = <PlayerColor, String?>{
      if (widget.onlineSession case final onlineSession?)
        for (final participant in onlineSession.participants)
          participant.color: resolvedTokenStyleIdForTheme(
            themeId: participant.loadout.themeId,
            selectedTokenStyleId: participant.loadout.tokensId,
          ),
      PlayerColor.red: resolvedTokenStyleIdForTheme(
        themeId: localThemeId,
        selectedTokenStyleId: localTokenStyleId,
      ),
    };
    final localAvatarId =
        widget.wallet?.equippedProductId(CosmeticCategory.avatar) ??
        localParticipant?.avatarId ??
        'avatar_default';
    final avatarIds = <PlayerColor, String?>{
      if (widget.onlineSession case final onlineSession?)
        for (final participant in onlineSession.participants)
          participant.color: participant.avatarId,
      PlayerColor.red: localAvatarId,
    };
    final robotTokens = localTokenStyleId == 'tokens_robot';
    final robotTokenColors = <PlayerColor>{
      for (final entry in tokenStyleIds.entries)
        if (entry.value == 'tokens_robot') entry.key,
    };
    final playerLabels = <PlayerColor, String>{
      if (widget.onlineSession case final onlineSession?)
        for (final participant in onlineSession.participants)
          participant.color: participant.isVirtuallyControlled
              ? 'CPU · ${participant.displayName}'
              : participant.displayName,
    };
    final standingEntries = _standingEntries(avatarIds);
    final localDiceStyleId =
        widget.wallet?.equippedProductId(CosmeticCategory.dice) ??
        localParticipant?.loadout.diceId;
    final diceStyleId = engine.currentPlayer.color == PlayerColor.red
        ? localDiceStyleId
        : currentParticipant?.loadout.diceId;
    final gameBackground = defaultThemeVisualSpec.gameBackgroundColor;
    final mobileAdsSupported =
        MobileAdsScope.maybeOf(context)?.supported ?? false;
    return PopScope(
      // Leaving a live match must always happen through its explicit
      // home/exit action, never through an accidental system back swipe.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBackRequest());
      },
      child: Scaffold(
        backgroundColor: gameBackground,
        body: ColoredBox(
          color: Colors.white,
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: _AnimatedThemeBackdrop(themeId: 'theme_default'),
                ),
                LayoutBuilder(
                  builder: (context, box) {
                    compactPhoneBoard = _usesCompactPhoneBoard(context);
                    final sideBySide =
                        box.maxWidth >= 560 &&
                        box.maxWidth >= box.maxHeight * 1.15;
                    final mobileBoardTools = compactPhoneBoard && !sideBySide;
                    final interactionState = GameInteractionState.derive(
                      engine: engine,
                      isLocallyControlledTurn: _isLocallyControlledTurn,
                      selectedToken: selectedToken,
                    );
                    const railGap = 4.0;
                    final minimumRailWidth = (box.maxWidth * .25)
                        .clamp(205.0, 290.0)
                        .toDouble();
                    final boardSize = sideBySide
                        ? math
                              .min(
                                box.maxHeight,
                                math.max(
                                  0,
                                  box.maxWidth - minimumRailWidth - railGap,
                                ),
                              )
                              .toDouble()
                        : box.maxWidth;
                    final availableRailWidth = sideBySide
                        ? math.max(0.0, box.maxWidth - boardSize - railGap)
                        : 0.0;
                    final phoneLandscape =
                        sideBySide &&
                        box.maxHeight <= 430 &&
                        availableRailWidth >= 330;
                    final selectedMovePreviews =
                        _visibleMoveDestinationPreviews(
                          selectedToken,
                        ).where((preview) => !preview.overview).toList();
                    final mobileMoveChoicesVisible =
                        mobileBoardTools && selectedMovePreviews.isNotEmpty;
                    final mobileTurnDecisionVisible =
                        mobileBoardTools &&
                        _isLocallyControlledTurn &&
                        !engine.gameOver &&
                        (engine.hasRolled || engine.effectResolving);
                    final rawMovePopup = mobileMoveChoicesVisible
                        ? null
                        : _buildMovePopup();
                    final movePopup = rawMovePopup == null
                        ? null
                        : TapRegion(
                            groupId: moveSelectionTapGroup,
                            onTapOutside: (_) => _cancelTokenSelection(),
                            child: rawMovePopup,
                          );
                    final trapAlert = _buildTrapAlert();
                    final trapDiagnostics = _buildTrapDiagnostics();
                    final chatBanner = _buildChatBanner();
                    final spectatorBar = _buildSpectatorBar(
                      compact: sideBySide,
                    );
                    final mobileFocus = _mobileBoardFocus;
                    final mobileFullBoard =
                        mobileBoardCameraMode ==
                        _MobileBoardCameraMode.fullBoard;
                    final cameraScale = mobileBoardTools && !mobileFullBoard
                        ? _mobileBoardZoomScale
                        : 1.0;
                    final cameraTranslation = Offset(
                      boardSize * (.5 - cameraScale * mobileFocus.dx),
                      boardSize * (.5 - cameraScale * mobileFocus.dy),
                    );
                    final cameraTransform = Matrix4.identity()
                      ..setEntry(0, 0, cameraScale)
                      ..setEntry(1, 1, cameraScale)
                      ..setTranslationRaw(
                        cameraTranslation.dx,
                        cameraTranslation.dy,
                        0,
                      );
                    final tokenChoiceGuideTarget = _tokenChoiceGuideTarget;
                    final tokenChoicePromptTarget = mobileBoardTools
                        ? _tokenChoicePromptTarget
                        : null;
                    final boardTokenCells = _displayTokenCells(
                      engine,
                      compactPhone: compactPhoneBoard,
                    );
                    final ownTokenCenters = <Offset>[];
                    for (final token in engine.currentPlayer.tokens) {
                      if (token.finished) continue;
                      final center = boardTokenCells[token];
                      if (center != null) ownTokenCenters.add(center);
                    }
                    final tokenChoiceGuideCell = tokenChoiceGuideTarget == null
                        ? null
                        : boardTokenCells[tokenChoiceGuideTarget];
                    final tokenChoicePromptCell =
                        tokenChoicePromptTarget == null
                        ? null
                        : boardTokenCells[tokenChoicePromptTarget];
                    final boardGeometry = _BoardGeometry(
                      boardSize,
                      compactPhone: compactPhoneBoard,
                    );
                    final boardHitPlane = SizedBox.square(
                      key: const ValueKey('game-board-hit-plane'),
                      dimension: boardSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTapUp: interactionState.boardInputEnabled
                            ? (details) =>
                                  _tapBoard(details.localPosition, boardSize)
                            : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GameBoardMockup(
                              engine: engine,
                              compactPhone: compactPhoneBoard,
                              selectedToken: selectedToken,
                              movePreviews: _visibleMoveDestinationPreviews(
                                selectedToken,
                              ),
                              revealAllTraps: trapDiagnosticsEnabled,
                              playerThemeIds: playerThemeIds,
                              robotTokens: robotTokens,
                              robotTokenColors: robotTokenColors,
                              tokenStyleIds: tokenStyleIds,
                              playerLabels: playerLabels,
                            ),
                            if (mobileMoveChoicesVisible)
                              _BoardMoveChoiceCallouts(
                                previews: selectedMovePreviews,
                                geometry: boardGeometry,
                                selectedTokenCenter: selectedToken == null
                                    ? null
                                    : boardTokenCells[selectedToken!],
                                avoidTokenCenters: ownTokenCenters,
                                onChoice: (preview) {
                                  if (preview.usesAllDice) {
                                    _moveSelectedTokenUsingAllDice();
                                  } else {
                                    _moveSelectedToken(preview.value);
                                  }
                                },
                                onTapAt: (boardPosition) =>
                                    _trySelectOwnTokenAtBoardPosition(
                                      boardPosition,
                                      boardSize,
                                      excludeSelected: true,
                                    ),
                              ),
                            if (mobileBoardTools && trapAlert != null)
                              _MobileBoardNotice(
                                anchor: engine.effectBoardCell,
                                child: trapAlert,
                              ),
                            if (mobileBoardTools &&
                                mobileTurnDecisionVisible &&
                                trapAlert == null &&
                                chatBanner != null)
                              _MobileBoardNotice(
                                anchor: null,
                                preferTop: true,
                                height: 58,
                                child: chatBanner,
                              ),
                            if (mobileBoardTools &&
                                !mobileMoveChoicesVisible &&
                                rawMovePopup != null)
                              _MobileBoardNotice(
                                anchor: selectedToken == null
                                    ? null
                                    : _displayTokenCells(
                                        engine,
                                        compactPhone: compactPhoneBoard,
                                      )[selectedToken!],
                                interactive: true,
                                height: 108,
                                child: movePopup!,
                              ),
                            if (tokenChoicePromptTarget != null &&
                                tokenChoicePromptCell != null)
                              _BoardTokenChoiceCallout(
                                geometry: boardGeometry,
                                target: tokenChoicePromptCell,
                                avoidTokenCenters: ownTokenCenters,
                                rolledDice: engine.dice,
                                remainingDice: _guidedTutorialActive
                                    ? <int>[
                                        tutorialScenario!.expectedDie(
                                          _guidedTutorialStep,
                                        )!,
                                      ]
                                    : engine.remainingDice,
                                onTap: () {
                                  setState(() {
                                    selectedToken = tokenChoicePromptTarget;
                                    mobileBoardCameraMode =
                                        _MobileBoardCameraMode.fullBoard;
                                  });
                                },
                                onTapAt: (boardPosition) =>
                                    _trySelectOwnTokenAtBoardPosition(
                                      boardPosition,
                                      boardSize,
                                      excludeSelected: true,
                                    ),
                              ),
                            if (tokenChoiceGuideTarget != null &&
                                tokenChoiceGuideCell != null)
                              _TokenChoiceGuide(
                                key: ValueKey(
                                  'token-choice-guide-target-'
                                  '${tokenChoiceGuideTarget.id}',
                                ),
                                center: boardGeometry.toPixel(
                                  tokenChoiceGuideCell,
                                ),
                                cell: boardGeometry.cell,
                                hand: diceHandPreference,
                              ),
                          ],
                        ),
                      ),
                    );
                    final board = TapRegion(
                      groupId: moveSelectionTapGroup,
                      onTapOutside: (_) => _cancelTokenSelection(),
                      child: SizedBox.square(
                        key: const ValueKey('game-board'),
                        dimension: boardSize,
                        child: mobileBoardTools
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Transform(
                                  key: const ValueKey(
                                    'mobile-board-camera-transform',
                                  ),
                                  alignment: Alignment.topLeft,
                                  transform: cameraTransform,
                                  transformHitTests: true,
                                  child: boardHitPlane,
                                ),
                              )
                            : boardHitPlane,
                      ),
                    );
                    final mobileBoardNavigator = mobileBoardTools
                        ? _MobileBoardNavigator(
                            boardPainter: _ParcheseBoardPainter(
                              engine,
                              compactPhone: true,
                              selectedToken: selectedToken,
                              animatedCells: _displayTokenCells(
                                engine,
                                compactPhone: true,
                              ),
                              pulse: .32,
                              cubeSpin: .28,
                              effectProgress: 0,
                              playerThemeIds: playerThemeIds,
                              revealAllTraps: trapDiagnosticsEnabled,
                              robotTokens: robotTokens,
                              robotTokenColors: robotTokenColors,
                              tokenStyleIds: tokenStyleIds,
                              playerLabels: playerLabels,
                              localPlayerLabel: appTranslate(context, 'TÚ'),
                              languageCode: appLanguageCodeOf(context),
                              movePreviews: _visibleMoveDestinationPreviews(
                                selectedToken,
                              ),
                            ),
                            focus: mobileFocus,
                            fullBoard: mobileFullBoard,
                            onFocusChanged: _setMobileBoardManualFocus,
                            onInteractionEnd: _showFullMobileBoard,
                          )
                        : null;
                    final rawPanel = GameControlPanel(
                      engine: engine,
                      selectedToken: selectedToken,
                      onDieSelected: _moveSelectedToken,
                      onCancelSelection: _cancelTokenSelection,
                      onRollRequested: _rollDiceFromHud,
                      rollEnabled:
                          interactionState.canRollDice && _tutorialAllowsRoll,
                      rollGuideEnabled: rollGuideEnabled,
                      rollGuideVisible: rollGuideVisible,
                      rollGuidePulseSerial: rollGuidePulseSerial,
                      diceHandPreference: diceHandPreference,
                      onShowChat: widget.onlineSession == null
                          ? null
                          : _showSafeChatPicker,
                      onCustomize: widget.wallet == null
                          ? null
                          : _showOwnedCosmetics,
                      diceStyleId: diceStyleId,
                      avatarIds: avatarIds,
                      mobileBoardNavigator: mobileBoardNavigator,
                      mobileBoardFullView: mobileFullBoard,
                      visibleRemainingDice: _guidedVisibleRemainingDice,
                    );
                    final Widget panel = mobileBoardTools
                        ? TapRegion(
                            groupId: moveSelectionTapGroup,
                            child: rawPanel,
                          )
                        : rawPanel;
                    final quickBar = _GameQuickBar(
                      chaos: engine.isChaos,
                      matchFormat: engine.matchFormat,
                      compact: sideBySide,
                      phoneLandscape: phoneLandscape,
                      attached: !sideBySide,
                      elapsed: matchElapsed,
                      onBack: _handleBackRequest,
                      onShowPowers: _showPowerStatus,
                      onShowHistory: _showEventHistory,
                      onShowGuide: () {
                        _cancelRollGuide();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GameGuideScreen(
                              initialMode:
                                  engine.matchFormat == MatchFormat.quickPop
                                  ? GameGuideMode.quickPop
                                  : engine.isChaos
                                  ? GameGuideMode.chaos
                                  : GameGuideMode.traditional,
                            ),
                          ),
                        );
                      },
                      onShowSettings: _openGameSettings,
                    );
                    return KeyedSubtree(
                      key: const ValueKey('game-content-area'),
                      child: sideBySide
                          ? KeyedSubtree(
                              key: phoneLandscape
                                  ? const ValueKey('phone-landscape-layout')
                                  : null,
                              child: Row(
                                key: const ValueKey('game-side-layout'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  board,
                                  const SizedBox(width: railGap),
                                  Expanded(
                                    key: const ValueKey('game-rail-slot'),
                                    child: phoneLandscape
                                        ? Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Column(
                                                children: [
                                                  quickBar,
                                                  ?spectatorBar,
                                                  const SizedBox(height: 3),
                                                  Expanded(
                                                    child: _GameSideRail(
                                                      engine: engine,
                                                      elapsed: matchElapsed,
                                                      selectedToken:
                                                          selectedToken,
                                                      onDieSelected:
                                                          _moveSelectedToken,
                                                      onCancelSelection:
                                                          _cancelTokenSelection,
                                                      onRollRequested:
                                                          _rollDiceFromHud,
                                                      rollEnabled:
                                                          interactionState
                                                              .canRollDice &&
                                                          _tutorialAllowsRoll,
                                                      rollGuideEnabled:
                                                          rollGuideEnabled,
                                                      rollGuideVisible:
                                                          rollGuideVisible,
                                                      rollGuidePulseSerial:
                                                          rollGuidePulseSerial,
                                                      diceHandPreference:
                                                          diceHandPreference,
                                                      onShowPowers:
                                                          _showPowerStatus,
                                                      onShowChat:
                                                          widget.onlineSession ==
                                                              null
                                                          ? null
                                                          : _showSafeChatPicker,
                                                      onCustomize:
                                                          widget.wallet == null
                                                          ? null
                                                          : _showOwnedCosmetics,
                                                      diceStyleId: diceStyleId,
                                                      onlineSession:
                                                          widget.onlineSession,
                                                      avatarIds: avatarIds,
                                                      revealTrapDetails:
                                                          trapDiagnosticsEnabled,
                                                      wideShortLandscape: true,
                                                      visibleRemainingDice:
                                                          _guidedVisibleRemainingDice,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (trapDiagnostics != null)
                                                Positioned(
                                                  top:
                                                      49 +
                                                      (spectatorBar == null
                                                          ? 0
                                                          : 40),
                                                  left: 5,
                                                  right: 66,
                                                  child: trapDiagnostics,
                                                ),
                                              if (movePopup ??
                                                      trapAlert ??
                                                      chatBanner
                                                  case final overlay?)
                                                Positioned(
                                                  left: 5,
                                                  right: 66,
                                                  bottom: 5,
                                                  child: ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxHeight: 170,
                                                        ),
                                                    child:
                                                        SingleChildScrollView(
                                                          child: overlay,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          )
                                        : Column(
                                            children: [
                                              quickBar,
                                              ?spectatorBar,
                                              ?trapDiagnostics,
                                              ?chatBanner,
                                              ?trapAlert,
                                              ?movePopup,
                                              const SizedBox(height: 3),
                                              Expanded(
                                                child: _GameSideRail(
                                                  engine: engine,
                                                  elapsed: matchElapsed,
                                                  selectedToken: selectedToken,
                                                  onDieSelected:
                                                      _moveSelectedToken,
                                                  onCancelSelection:
                                                      _cancelTokenSelection,
                                                  onRollRequested:
                                                      _rollDiceFromHud,
                                                  rollEnabled:
                                                      interactionState
                                                          .canRollDice &&
                                                      _tutorialAllowsRoll,
                                                  rollGuideEnabled:
                                                      rollGuideEnabled,
                                                  rollGuideVisible:
                                                      rollGuideVisible,
                                                  rollGuidePulseSerial:
                                                      rollGuidePulseSerial,
                                                  diceHandPreference:
                                                      diceHandPreference,
                                                  onShowPowers:
                                                      _showPowerStatus,
                                                  onShowChat:
                                                      widget.onlineSession ==
                                                          null
                                                      ? null
                                                      : _showSafeChatPicker,
                                                  onCustomize:
                                                      widget.wallet == null
                                                      ? null
                                                      : _showOwnedCosmetics,
                                                  diceStyleId: diceStyleId,
                                                  onlineSession:
                                                      widget.onlineSession,
                                                  avatarIds: avatarIds,
                                                  revealTrapDetails:
                                                      trapDiagnosticsEnabled,
                                                  visibleRemainingDice:
                                                      _guidedVisibleRemainingDice,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                            )
                          : mobileBoardTools
                          ? Column(
                              key: const ValueKey(
                                'mobile-portrait-game-layout',
                              ),
                              children: [
                                quickBar,
                                const SizedBox(height: 3),
                                Expanded(
                                  key: const ValueKey('mobile-board-stage'),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      alignment: Alignment.topCenter,
                                      child: board,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      panel,
                                      if (spectatorBar ?? chatBanner
                                          case final overlay?)
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          right: 0,
                                          child: overlay,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  quickBar,
                                  ?spectatorBar,
                                  const SizedBox(height: 3),
                                  board,
                                  ?trapDiagnostics,
                                  ?chatBanner,
                                  ?trapAlert,
                                  ?movePopup,
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      4,
                                      4,
                                      4,
                                    ),
                                    child: panel,
                                  ),
                                ],
                              ),
                            ),
                    );
                  },
                ),
                if (_usesGuidedTutorial &&
                    widget.tutorial?.lifecycle == TutorialLifecycle.inProgress)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 62,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _TutorialCoachBanner(
                          controller: widget.tutorial!,
                          onSkip: () async {
                            final navigator = Navigator.of(context);
                            await widget.tutorial!.skip();
                            if (!mounted) return;
                            if (widget.guidedTutorial && navigator.canPop()) {
                              navigator.pop();
                            } else {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                if (tutorialCompletionVisible)
                  Positioned.fill(
                    child: BlockSemantics(
                      child: _TutorialCompletionCard(
                        onDone: () {
                          final navigator = Navigator.of(context);
                          if (navigator.canPop()) {
                            navigator.pop();
                          } else {
                            setState(() => tutorialCompletionVisible = false);
                          }
                        },
                      ),
                    ),
                  ),
                if (showVictory && engine.winner != null)
                  Positioned.fill(
                    child: BlockSemantics(
                      child: _VictoryCelebration(
                        winner: engine.winner!,
                        mode: engine.mode,
                        matchFormat: engine.matchFormat,
                        elapsed: matchElapsed,
                        standings: standingEntries,
                        standingsComplete: engine.standingsComplete,
                        rewardCoins: matchRewardCoinsAwarded,
                        doubleRewardCoins: widget.progression == null
                            ? 100
                            : matchBasePayout,
                        onContinueWatching: engine.canContinueAfterWinner
                            ? _continueWatching
                            : null,
                        onWatchRewarded:
                            widget.wallet != null &&
                                (widget.progression == null
                                    ? engine.standingsComplete
                                    : matchPlacementRewardSettled &&
                                          matchBasePayout > 0) &&
                                mobileAdsSupported &&
                                !endMatchRewardClaimed &&
                                !postVictoryNavigationInProgress
                            ? _watchEndMatchRewarded
                            : null,
                        rewardInProgress: endMatchRewardInProgress,
                        rewardClaimed: endMatchRewardClaimed,
                        navigationInProgress: postVictoryNavigationInProgress,
                        onPlayAgain: _playAgainFromVictory,
                        onHome: _homeFromVictory,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialCoachBanner extends StatelessWidget {
  const _TutorialCoachBanner({required this.controller, required this.onSkip});

  final TutorialController controller;
  final VoidCallback onSkip;

  (String, String, IconData) get _copy => switch (controller.currentStep) {
    TutorialStep.firstRoll => (
      '1 · TIRA LOS DADOS',
      'Toca los dados. Esta práctica prepara un 5 y un 2.',
      Icons.casino_rounded,
    ),
    TutorialStep.releaseToken => (
      '2 · SACA UNA FICHA',
      'Toca la ficha señalada y usa el 5 para sacarla.',
      Icons.outbound_rounded,
    ),
    TutorialStep.chooseMove => (
      '3 · ELIGE EL DESTINO',
      'Vuelve a tocar la ficha y elige la burbuja de 2 pasos.',
      Icons.touch_app_rounded,
    ),
    TutorialStep.safeSquare => (
      '4 · BUSCA UNA ESTRELLA',
      'Ejemplo preparado: usa el 2 para caer en la estrella.',
      Icons.star_rounded,
    ),
    TutorialStep.capture => (
      '5 · CAPTURA',
      'Usa el 3 para caer sobre la ficha rival señalada.',
      Icons.flash_on_rounded,
    ),
    TutorialStep.reachHome => (
      '6 · LLEGA A META',
      'Último ejemplo: usa el 1 exacto para entrar al centro.',
      Icons.flag_rounded,
    ),
    null => ('TUTORIAL LISTO', 'Ya conoces la partida.', Icons.check_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final completed = controller.completedSteps.length;
    return Material(
      key: const ValueKey('contextual-tutorial-banner'),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
        decoration: BoxDecoration(
          color: const Color(0xF516294F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PopColors.yellow, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66020B27),
              blurRadius: 14,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: const BoxDecoration(
                color: PopColors.yellow,
                shape: BoxShape.circle,
              ),
              child: Icon(copy.$3, color: PopColors.navy),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopText(
                    copy.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  PopText(
                    copy.$2,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFDCE8FF),
                      fontSize: 10.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      for (
                        var index = 0;
                        index < TutorialController.orderedSteps.length;
                        index++
                      )
                        Container(
                          width: 18,
                          height: 4,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: index < completed
                                ? PopColors.green
                                : index == completed
                                ? PopColors.yellow
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('tutorial-skip'),
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(44, 44),
              ),
              child: const PopText(
                'YA SÉ JUGAR',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialCompletionCard extends StatelessWidget {
  const _TutorialCompletionCard({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xB3020B27),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          key: const ValueKey('tutorial-complete-card'),
          color: Colors.white,
          elevation: 14,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: PopColors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 15),
                const PopText(
                  '¡TUTORIAL LISTO!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PopColors.navy,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const PopText(
                  'Ya sabes tirar, sacar una ficha, elegir un movimiento, '
                  'usar seguros, capturar y entrar a meta.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF667085), height: 1.3),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('tutorial-complete-done'),
                    onPressed: onDone,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const PopText('LISTO PARA JUGAR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _OwnedCosmeticsPicker extends StatelessWidget {
  const _OwnedCosmeticsPicker({
    required this.wallet,
    required this.onEquipped,
    required this.onClose,
  });

  final WalletController wallet;
  final VoidCallback onEquipped;
  final VoidCallback onClose;

  static const categories = <CosmeticCategory>[
    CosmeticCategory.theme,
    CosmeticCategory.dice,
    CosmeticCategory.tokens,
    CosmeticCategory.avatar,
  ];

  String _categoryLabel(CosmeticCategory category) => switch (category) {
    CosmeticCategory.theme => 'TEMAS',
    CosmeticCategory.dice => 'DADOS',
    CosmeticCategory.tokens => 'FICHAS',
    CosmeticCategory.avatar => 'AVATARES',
  };

  IconData _categoryIcon(CosmeticCategory category) => switch (category) {
    CosmeticCategory.theme => Icons.palette_rounded,
    CosmeticCategory.dice => Icons.casino_rounded,
    CosmeticCategory.tokens => Icons.stars_rounded,
    CosmeticCategory.avatar => Icons.face_rounded,
  };

  List<WalletProduct> _owned(CosmeticCategory category) => wallet.ownedProducts
      .where((product) => product.category == category)
      .toList(growable: false);

  Future<void> _equip(BuildContext context, WalletProduct product) async {
    final result = await wallet.equip(product.id);
    if (result == EquipResult.equipped ||
        result == EquipResult.alreadyEquipped) {
      onEquipped();
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: PopText('${product.name} está en uso.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: categories.length,
    child: Material(
      key: const ValueKey('owned-cosmetics-picker'),
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2457A2), PopColors.navy],
          ),
          borderRadius: BorderRadius.circular(27),
          border: Border.all(color: PopColors.yellow, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x8007132D),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 13, 9, 8),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: PopColors.yellow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.checkroom_rounded,
                      color: PopColors.navy,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopText(
                          'MIS DISEÑOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        PopText(
                          'Cambia aquí los artículos que ya compraste.',
                          style: TextStyle(
                            color: Color(0xFFD7E4FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('owned-cosmetics-close'),
                    tooltip: appTranslate(context, 'Cerrar'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: TabBar(
                key: const ValueKey('owned-cosmetics-tabs'),
                isScrollable: false,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: PopColors.yellow,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: PopColors.navy,
                unselectedLabelColor: Colors.white,
                labelPadding: EdgeInsets.zero,
                tabs: [
                  for (final category in categories)
                    Tab(
                      height: 50,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_categoryIcon(category), size: 18),
                            const SizedBox(height: 2),
                            PopText(
                              _categoryLabel(category),
                              style: const TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedBuilder(
                animation: wallet,
                builder: (context, _) => TabBarView(
                  children: [
                    for (final category in categories)
                      _OwnedCosmeticsList(
                        products: _owned(category),
                        wallet: wallet,
                        onEquip: (product) => _equip(context, product),
                      ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 3, 16, 13),
              child: PopText(
                'Solo aparecen artículos comprados. Cada jugador conserva su propio lado.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFD7E4FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OwnedCosmeticsList extends StatelessWidget {
  const _OwnedCosmeticsList({
    required this.products,
    required this.wallet,
    required this.onEquip,
  });

  final List<WalletProduct> products;
  final WalletController wallet;
  final ValueChanged<WalletProduct> onEquip;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
    itemCount: products.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final product = products[index];
      final equipped = wallet.isEquipped(product.id);
      return Material(
        key: ValueKey('owned-cosmetic-${product.id}'),
        color: equipped ? const Color(0xFFE8FFF2) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: equipped ? null : () => onEquip(product),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: equipped ? PopColors.green : const Color(0xFFDCE4F2),
                width: equipped ? 2.5 : 1.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 66,
                  height: 58,
                  child: _ShopProductPreview(product: product),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PopText(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PopColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      PopText(
                        product.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 76,
                    minHeight: 44,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: equipped ? PopColors.green : PopColors.blue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: PopText(
                    equipped ? 'EN USO' : 'USAR',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _TrapDiagnosticsNotice extends StatelessWidget {
  const _TrapDiagnosticsNotice();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('trap-diagnostics-notice'),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3C4),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: PopColors.yellow, width: 1.5),
    ),
    child: const Row(
      children: [
        Icon(Icons.bug_report_rounded, color: PopColors.navy, size: 18),
        SizedBox(width: 7),
        Expanded(
          child: PopText(
            'VISTA DE PRUEBA · TODAS LAS TRAMPAS SON VISIBLES',
            style: TextStyle(
              color: PopColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TrapDiagnosticsStrip extends StatelessWidget {
  const _TrapDiagnosticsStrip({required this.engine});

  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final traps = engine.traps.toList(growable: false)
      ..sort((left, right) => left.loopIndex.compareTo(right.loopIndex));
    return Container(
      key: const ValueKey('trap-diagnostics-strip'),
      margin: const EdgeInsets.fromLTRB(4, 3, 4, 0),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: PopColors.navy.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PopColors.yellow, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3517284D),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bug_report_rounded,
            color: PopColors.yellow,
            size: 17,
          ),
          const SizedBox(width: 5),
          const PopText(
            'PRUEBA · TRAMPAS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < traps.length; index++) ...[
                    if (index > 0) const SizedBox(width: 5),
                    _trapChip(context, traps[index]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trapChip(BuildContext context, BoardTrap trap) {
    final owner = engine.players.firstWhere(
      (player) => player.color == trap.owner,
    );
    final ownerColor = _playerUiColor(trap.owner);
    final trapName = appTranslate(context, engine.powerUpName(trap.type));
    final square = appTranslate(context, 'casilla ${trap.loopIndex + 1}');
    final label = '${owner.name} · $trapName · $square';
    final foreground = trap.owner == PlayerColor.yellow
        ? PopColors.navy
        : Colors.white;
    return Tooltip(
      message: label,
      child: Container(
        key: ValueKey(
          'debug-trap-${trap.owner.name}-${trap.type.name}-${trap.loopIndex}',
        ),
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: ownerColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_powerUiIcon(trap.type), color: foreground, size: 13),
            const SizedBox(width: 4),
            Flexible(
              child: _AutoFitSingleLineText(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrapAlertBanner extends StatelessWidget {
  const _TrapAlertBanner({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('trap-alert-banner'),
    margin: const EdgeInsets.fromLTRB(4, 3, 4, 0),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color.lerp(color, Colors.white, .88)!,
          Color.lerp(color, Colors.white, .72)!,
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .24),
          blurRadius: 9,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PopText(
                title,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: Color.lerp(color, PopColors.navy, .52),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              PopText(
                message,
                maxLines: 2,
                style: const TextStyle(
                  color: PopColors.navy,
                  fontSize: 10,
                  height: 1.12,
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

class _SafeChatPickerSheet extends StatelessWidget {
  const _SafeChatPickerSheet({
    required this.languageCode,
    required this.onSelected,
    required this.onClose,
  });

  final String languageCode;
  final ValueChanged<SafeChatPhraseId> onSelected;
  final VoidCallback onClose;

  static const _accents = <Color>[
    PopColors.blue,
    PopColors.yellow,
    PopColors.green,
    PopColors.red,
    Color(0xFF6B55E7),
    Color(0xFFFF8A24),
  ];

  IconData _iconFor(SafeChatPhraseId phraseId) => switch (phraseId) {
    SafeChatPhraseId.hello => Icons.waving_hand_rounded,
    SafeChatPhraseId.goodLuck => Icons.auto_awesome_rounded,
    SafeChatPhraseId.goodGame => Icons.sports_esports_rounded,
    SafeChatPhraseId.greatMove => Icons.bolt_rounded,
    SafeChatPhraseId.wellPlayed => Icons.workspace_premium_rounded,
    SafeChatPhraseId.wow => Icons.celebration_rounded,
    SafeChatPhraseId.yourTurn => Icons.touch_app_rounded,
    SafeChatPhraseId.thanks => Icons.favorite_rounded,
    SafeChatPhraseId.almost => Icons.flag_rounded,
    SafeChatPhraseId.oops => Icons.sentiment_dissatisfied_rounded,
    SafeChatPhraseId.rematch => Icons.replay_rounded,
    SafeChatPhraseId.funGame => Icons.sentiment_very_satisfied_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.top - media.padding.bottom - 12;
    final maxHeight = math.min(620.0, availableHeight);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
          child: DecoratedBox(
            key: const ValueKey('safe-chat-sheet'),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF203B73), Color(0xFF101A31)],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: PopColors.yellow, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x73020B27),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  Flexible(child: _buildPhraseGrid(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
    key: const ValueKey('safe-chat-header'),
    padding: const EdgeInsets.fromLTRB(14, 8, 10, 13),
    child: Column(
      children: [
        Container(
          width: 46,
          height: 5,
          decoration: BoxDecoration(
            color: PopColors.yellow,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 11),
        Row(
          children: [
            Transform.rotate(
              angle: -.07,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFDD55), Color(0xFFFFA918)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x50020B27),
                      blurRadius: 8,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.casino_rounded,
                  color: PopColors.navy,
                  size: 29,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    'PARCHÍS POP!',
                    style: TextStyle(
                      color: PopColors.yellow,
                      fontSize: 11,
                      height: 1,
                      letterSpacing: .7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  PopText(
                    'MENSAJES RÁPIDOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  PopText(
                    'Solo frases preseleccionadas y seguras.',
                    style: TextStyle(
                      color: Color(0xFFC8D6F2),
                      fontSize: 11.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const ValueKey('safe-chat-close'),
                tooltip: appTranslate(context, 'Cerrar'),
                onPressed: onClose,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: .10),
                  side: BorderSide(color: Colors.white.withValues(alpha: .24)),
                ),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildPhraseGrid(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFF8FAFF), Color(0xFFEAF2FF)],
      ),
      border: Border(top: BorderSide(color: PopColors.yellow, width: 2)),
    ),
    child: SingleChildScrollView(
      key: const ValueKey('safe-chat-scroll'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final columns = textScale > 1.35
              ? 1
              : constraints.maxWidth >= 600
              ? 3
              : 2;
          const spacing = 10.0;
          final buttonWidth =
              (constraints.maxWidth - (spacing * (columns - 1))) / columns;
          return Wrap(
            key: const ValueKey('safe-chat-grid'),
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (
                var index = 0;
                index < SafeChatCatalog.phrases.length;
                index++
              )
                SizedBox(
                  width: buttonWidth,
                  child: _SafeChatPhraseButton(
                    key: ValueKey(
                      'safe-chat-${SafeChatCatalog.phrases[index].id.name}',
                    ),
                    label: SafeChatCatalog.phrases[index].textForLanguage(
                      languageCode,
                    ),
                    icon: _iconFor(SafeChatCatalog.phrases[index].id),
                    accent: _accents[index % _accents.length],
                    onPressed: () =>
                        onSelected(SafeChatCatalog.phrases[index].id),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _SafeChatPhraseButton extends StatelessWidget {
  const _SafeChatPhraseButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accentForeground = accent == PopColors.yellow
        ? PopColors.navy
        : Colors.white;
    return Semantics(
      button: true,
      label: '${appTranslate(context, 'Mensajes rápidos')}: $label',
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: PopColors.navy.withValues(alpha: .18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: .55), width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: .13)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .28),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: accentForeground, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PopText(
                      label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PopColors.navy,
                        fontSize: 13,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SafeChatBanner extends StatelessWidget {
  const _SafeChatBanner({required this.sender, required this.text});

  final OnlineParticipant sender;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('safe-chat-banner'),
    margin: const EdgeInsets.fromLTRB(4, 3, 4, 0),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: _playerUiColor(sender.color).withValues(alpha: .65),
        width: 1.5,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2817284D),
          blurRadius: 9,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        _AvatarArt(avatarId: sender.avatarId, size: 34, withFrame: true),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AutoFitSingleLineText(
                '${sender.displayName} ${sender.flag}',
                style: const TextStyle(
                  color: PopColors.navy,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              PopText(
                text,
                style: const TextStyle(
                  color: PopColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _GameQuickBar extends StatelessWidget {
  const _GameQuickBar({
    required this.chaos,
    required this.matchFormat,
    required this.compact,
    this.phoneLandscape = false,
    required this.attached,
    required this.elapsed,
    required this.onBack,
    required this.onShowPowers,
    required this.onShowHistory,
    required this.onShowGuide,
    required this.onShowSettings,
  });

  final bool chaos;
  final MatchFormat matchFormat;
  final bool compact;
  final bool phoneLandscape;
  final bool attached;
  final Duration elapsed;
  final VoidCallback onBack;
  final VoidCallback onShowPowers;
  final VoidCallback onShowHistory;
  final VoidCallback onShowGuide;
  final VoidCallback onShowSettings;

  @override
  Widget build(BuildContext context) {
    final modeLabel = matchFormat == MatchFormat.quickPop
        ? 'Quick Pop'
        : chaos
        ? 'Caos'
        : 'Tradicional';
    final iconSize = compact ? (phoneLandscape ? 19.0 : 18.0) : 20.0;
    final height = compact ? (phoneLandscape ? 44.0 : 48.0) : 44.0;
    final borderRadius = attached
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          )
        : BorderRadius.circular(compact ? 12 : 14);
    return Material(
      key: const ValueKey('game-quick-bar'),
      color: Colors.white.withValues(alpha: attached ? .96 : .86),
      elevation: attached ? 3 : 0,
      shadowColor: PopColors.navy.withValues(alpha: .24),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Split-screen previews can make this bar much narrower than a
            // phone. Keep the essential 44-point controls reachable and hide
            // only secondary labels/help at that extreme width.
            final veryNarrow = constraints.maxWidth < 280;
            return Row(
              children: [
                _GameBackAction(
                  tooltip: appTranslate(context, 'Volver al inicio'),
                  compact: compact,
                  expandedTarget: phoneLandscape,
                  onPressed: onBack,
                ),
                if (veryNarrow)
                  const Spacer()
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => _AutoFitSingleLineText(
                        key: const ValueKey('game-mode-indicator'),
                        compact || box.maxWidth < 92
                            ? modeLabel
                            : 'Parchís Pop · $modeLabel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: PopColors.navy,
                          fontSize: compact ? 11 : 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (!veryNarrow && (!compact || phoneLandscape)) ...[
                  const SizedBox(width: 3),
                  _MatchTimerBadge(elapsed: elapsed, compact: phoneLandscape),
                  const SizedBox(width: 2),
                ],
                if (chaos)
                  _GameQuickAction(
                    tooltip: appTranslate(context, 'Poderes y trampas'),
                    icon: Icons.backpack_rounded,
                    iconSize: iconSize,
                    expandedTarget: phoneLandscape,
                    onPressed: onShowPowers,
                  ),
                _GameQuickAction(
                  key: const ValueKey('game-history-button'),
                  tooltip: appTranslate(context, 'Historial de eventos'),
                  icon: Icons.history_rounded,
                  iconSize: iconSize,
                  expandedTarget: phoneLandscape,
                  onPressed: onShowHistory,
                ),
                if (!veryNarrow)
                  _GameQuickAction(
                    tooltip: appTranslate(context, 'Cómo jugar'),
                    icon: Icons.help_rounded,
                    iconSize: iconSize,
                    expandedTarget: phoneLandscape,
                    onPressed: onShowGuide,
                  ),
                _GameQuickAction(
                  key: const ValueKey('game-settings-button'),
                  tooltip: appTranslate(context, 'Ajustes'),
                  icon: Icons.settings_rounded,
                  iconSize: iconSize,
                  expandedTarget: phoneLandscape,
                  onPressed: onShowSettings,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GameQuickAction extends StatelessWidget {
  const _GameQuickAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    this.expandedTarget = false,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool expandedTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.standard,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    iconSize: iconSize,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

/// Deliberately different from the utility icons: leaving a match is a
/// meaningful action, so the affordance follows the rounded arcade buttons
/// used by the rest of the game instead of looking like a system back button.
class _GameBackAction extends StatelessWidget {
  const _GameBackAction({
    required this.tooltip,
    required this.compact,
    required this.expandedTarget,
    required this.onPressed,
  });

  final String tooltip;
  final bool compact;
  final bool expandedTarget;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visualSize = expandedTarget ? 38.0 : (compact ? 29.0 : 33.0);
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            key: const ValueKey('game-back-button'),
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(22),
              child: Center(
                child: Ink(
                  width: visualSize,
                  height: visualSize,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF6B78), PopColors.red],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.6),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4AF04452),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: compact ? 18 : 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchTimerBadge extends StatelessWidget {
  const _MatchTimerBadge({required this.elapsed, this.compact = false});

  final Duration elapsed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = _formatMatchDuration(elapsed);
    return Tooltip(
      message: appTranslate(context, 'Tiempo de partida'),
      child: Semantics(
        label: '${appTranslate(context, 'Tiempo de partida')}: $value',
        child: Container(
          key: const ValueKey('match-elapsed-timer'),
          height: compact ? 24 : 27,
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFD867), PopColors.yellow],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white, width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E07132D),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: compact ? 13 : 14,
                color: PopColors.navy,
              ),
              const SizedBox(width: 3),
              PopText(
                value,
                key: const ValueKey('match-elapsed-value'),
                style: TextStyle(
                  color: PopColors.navy,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameEventHistoryTile extends StatelessWidget {
  const _GameEventHistoryTile({required this.event});

  final GameEvent event;

  String get label => switch (event.type) {
    GameEventType.matchStarted => 'INICIO',
    GameEventType.turnStarted => 'TURNO',
    GameEventType.roll => 'TIRADA',
    GameEventType.move => 'MOVIMIENTO',
    GameEventType.departure => 'SALIDA DEL NIDO',
    GameEventType.barrierFormed => 'BARRERA FORMADA',
    GameEventType.barrierOpened => 'BARRERA ABIERTA',
    GameEventType.capture => 'CAPTURA',
    GameEventType.threeDoublesPenalty => 'TRES DOBLES',
    GameEventType.noMove => 'SIN MOVIMIENTOS',
    GameEventType.goal => 'META',
    GameEventType.powerUp => 'PODER',
    GameEventType.trap => 'TRAMPA',
    GameEventType.victory => 'VICTORIA',
  };

  IconData get icon => switch (event.type) {
    GameEventType.matchStarted => Icons.sports_esports_rounded,
    GameEventType.turnStarted => Icons.play_circle_fill_rounded,
    GameEventType.roll => Icons.casino_rounded,
    GameEventType.move => Icons.route_rounded,
    GameEventType.departure => Icons.output_rounded,
    GameEventType.barrierFormed => Icons.lock_rounded,
    GameEventType.barrierOpened => Icons.lock_open_rounded,
    GameEventType.capture => Icons.flash_on_rounded,
    GameEventType.threeDoublesPenalty => Icons.warning_amber_rounded,
    GameEventType.noMove => Icons.block_rounded,
    GameEventType.goal => Icons.flag_rounded,
    GameEventType.powerUp => Icons.auto_awesome_rounded,
    GameEventType.trap => Icons.bolt_rounded,
    GameEventType.victory => Icons.emoji_events_rounded,
  };

  Color get eventColor => switch (event.type) {
    GameEventType.threeDoublesPenalty => PopColors.red,
    GameEventType.capture || GameEventType.trap => const Color(0xFFFF7A24),
    GameEventType.barrierFormed => PopColors.navy,
    GameEventType.barrierOpened => const Color(0xFF7057FF),
    GameEventType.goal || GameEventType.victory => const Color(0xFFE2A500),
    _ => _eventPlayerColor(event.playerColor),
  };

  @override
  Widget build(BuildContext context) {
    final color = eventColor;
    final rolledDice = event.dice;
    return Container(
      key: ValueKey('game-event-row-${event.sequence}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .24), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1017284D),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _eventPlayerColor(event.playerColor),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: _AutoFitSingleLineText(
                        appTranslate(context, event.playerName),
                        style: const TextStyle(
                          color: PopColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: PopText(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                PopText(
                  event.description,
                  style: const TextStyle(
                    color: PopColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    PopText(
                      'Turno ${event.turn} · #${event.sequence}',
                      style: const TextStyle(
                        color: Color(0xFF7A8498),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (rolledDice != null) ...[
                      const Spacer(),
                      _HistoryDie(value: rolledDice.$1, color: PopColors.blue),
                      const SizedBox(width: 4),
                      _HistoryDie(value: rolledDice.$2, color: PopColors.red),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDie extends StatelessWidget {
  const _HistoryDie({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .24),
          blurRadius: 5,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Text(
      '$value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _GameSideRail extends StatefulWidget {
  const _GameSideRail({
    required this.engine,
    required this.elapsed,
    required this.selectedToken,
    required this.onDieSelected,
    required this.onCancelSelection,
    required this.onRollRequested,
    required this.rollEnabled,
    required this.rollGuideEnabled,
    required this.rollGuideVisible,
    required this.rollGuidePulseSerial,
    required this.diceHandPreference,
    required this.onShowPowers,
    this.onShowChat,
    this.onCustomize,
    this.avatarIds = const <PlayerColor, String?>{},
    this.diceStyleId,
    this.onlineSession,
    this.revealTrapDetails = false,
    this.wideShortLandscape = false,
    this.visibleRemainingDice,
  });

  final GameEngine engine;
  final Duration elapsed;
  final GameToken? selectedToken;
  final ValueChanged<int> onDieSelected;
  final VoidCallback onCancelSelection;
  final VoidCallback onRollRequested;
  final bool rollEnabled;
  final bool rollGuideEnabled;
  final bool rollGuideVisible;
  final int rollGuidePulseSerial;
  final DiceHandPreference diceHandPreference;
  final VoidCallback onShowPowers;
  final VoidCallback? onShowChat;
  final VoidCallback? onCustomize;
  final Map<PlayerColor, String?> avatarIds;
  final String? diceStyleId;
  final OnlineMatchSession? onlineSession;
  final bool revealTrapDetails;
  final bool wideShortLandscape;
  final List<int>? visibleRemainingDice;

  @override
  State<_GameSideRail> createState() => _GameSideRailState();
}

class _GameSideRailState extends State<_GameSideRail> {
  late int lastPlayerIndex = widget.engine.currentPlayerIndex;
  late int selectedTab = widget.engine.currentPlayer.isHuman ? 0 : 1;

  @override
  void didUpdateWidget(covariant _GameSideRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (lastPlayerIndex != widget.engine.currentPlayerIndex) {
      lastPlayerIndex = widget.engine.currentPlayerIndex;
      // Desktop keeps the roster below the dice controls, so there is no
      // separate Players tab to switch to on macOS.
      final macDesktopRail = defaultTargetPlatform == TargetPlatform.macOS;
      selectedTab = macDesktopRail || widget.engine.currentPlayer.isHuman
          ? 0
          : 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chaos = widget.engine.isChaos;
    // On macOS the side rail has enough vertical room to keep the roster
    // visible below the dice controls. This avoids an otherwise empty area
    // and lets desktop players check every player without leaving Play.
    final macDesktopRail = defaultTargetPlatform == TargetPlatform.macOS;
    final showRosterBelowControls = macDesktopRail;
    // A very short Mac window must still use the desktop rail.  The compact
    // landscape dock is a phone-only layout and includes a Players tab.
    final usePhoneLandscapeRail = widget.wideShortLandscape && !macDesktopRail;
    Widget selectedContent() => switch (selectedTab) {
      0 =>
        usePhoneLandscapeRail
            ? Column(
                key: const ValueKey('game-rail-control'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameControlPanel(
                    engine: widget.engine,
                    selectedToken: widget.selectedToken,
                    onDieSelected: widget.onDieSelected,
                    onCancelSelection: widget.onCancelSelection,
                    onRollRequested: widget.onRollRequested,
                    rollEnabled: widget.rollEnabled,
                    rollGuideEnabled: widget.rollGuideEnabled,
                    rollGuideVisible: widget.rollGuideVisible,
                    rollGuidePulseSerial: widget.rollGuidePulseSerial,
                    diceHandPreference: widget.diceHandPreference,
                    onShowChat: widget.onShowChat,
                    onCustomize: widget.onCustomize,
                    compact: true,
                    landscapeHud: true,
                    diceStyleId: widget.diceStyleId,
                    avatarIds: widget.avatarIds,
                    visibleRemainingDice: widget.visibleRemainingDice,
                  ),
                  const SizedBox(height: 5),
                  _LandscapePlayerStrip(
                    engine: widget.engine,
                    onlineSession: widget.onlineSession,
                    avatarIds: widget.avatarIds,
                  ),
                ],
              )
            : Column(
                key: const ValueKey('game-rail-control'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameControlPanel(
                    engine: widget.engine,
                    selectedToken: widget.selectedToken,
                    onDieSelected: widget.onDieSelected,
                    onCancelSelection: widget.onCancelSelection,
                    onRollRequested: widget.onRollRequested,
                    rollEnabled: widget.rollEnabled,
                    rollGuideEnabled: widget.rollGuideEnabled,
                    rollGuideVisible: widget.rollGuideVisible,
                    rollGuidePulseSerial: widget.rollGuidePulseSerial,
                    diceHandPreference: widget.diceHandPreference,
                    onShowChat: widget.onShowChat,
                    onCustomize: widget.onCustomize,
                    compact: true,
                    diceStyleId: widget.diceStyleId,
                    avatarIds: widget.avatarIds,
                    visibleRemainingDice: widget.visibleRemainingDice,
                  ),
                  if (showRosterBelowControls) ...[
                    const SizedBox(height: 7),
                    PlayerRoster(
                      key: const ValueKey('macos-roster-below-controls'),
                      engine: widget.engine,
                      onlineSession: widget.onlineSession,
                      avatarIds: widget.avatarIds,
                      revealTrapDetails: widget.revealTrapDetails,
                    ),
                  ],
                ],
              ),
      1 => PlayerRoster(
        key: const ValueKey('game-rail-roster'),
        engine: widget.engine,
        onlineSession: widget.onlineSession,
        avatarIds: widget.avatarIds,
        revealTrapDetails: widget.revealTrapDetails,
      ),
      _ => _GamePowerRail(
        key: const ValueKey('game-rail-power-panel'),
        engine: widget.engine,
        onShowPowers: widget.onShowPowers,
        onlineSession: widget.onlineSession,
        revealTrapDetails: widget.revealTrapDetails,
      ),
    };
    if (usePhoneLandscapeRail) {
      return Container(
        key: const ValueKey('game-side-rail'),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF214F94), PopColors.navy],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4017284D),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(6, 6, 5, 7),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: selectedContent(),
                ),
              ),
            ),
            Container(
              key: const ValueKey('phone-landscape-tab-dock'),
              width: 62,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                border: Border(
                  left: BorderSide(
                    color: Colors.white.withValues(alpha: .28),
                    width: 1.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: _GameRailTab(
                      key: const ValueKey('game-rail-play'),
                      selected: selectedTab == 0,
                      icon: Icons.casino_rounded,
                      label: 'Jugar',
                      verticalDock: true,
                      onTap: () => setState(() => selectedTab = 0),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: _GameRailTab(
                      key: const ValueKey('game-rail-players'),
                      selected: selectedTab == 1,
                      icon: Icons.groups_rounded,
                      label: 'Jugadores',
                      verticalDock: true,
                      onTap: () => setState(() => selectedTab = 1),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: _GameRailTab(
                      key: const ValueKey('game-rail-powers'),
                      selected: selectedTab == 2,
                      icon: chaos
                          ? Icons.auto_awesome_rounded
                          : Icons.menu_book_rounded,
                      label: chaos ? 'Trampas' : 'Reglas',
                      verticalDock: true,
                      onTap: () => setState(() => selectedTab = 2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const ValueKey('game-side-rail'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .74),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2417284D),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 7, 0),
            child: Row(
              children: [
                const Expanded(
                  child: PopText(
                    'Tiempo de partida',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PopColors.navy,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _MatchTimerBadge(elapsed: widget.elapsed, compact: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: _GameRailTab(
                    key: const ValueKey('game-rail-play'),
                    selected: selectedTab == 0,
                    icon: Icons.casino_rounded,
                    label: 'Jugar',
                    onTap: () => setState(() => selectedTab = 0),
                  ),
                ),
                if (!showRosterBelowControls) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _GameRailTab(
                      key: const ValueKey('game-rail-players'),
                      selected: selectedTab == 1,
                      icon: Icons.groups_rounded,
                      label: 'Jugadores',
                      onTap: () => setState(() => selectedTab = 1),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Expanded(
                  child: _GameRailTab(
                    key: const ValueKey('game-rail-powers'),
                    selected: selectedTab == 2,
                    icon: chaos
                        ? Icons.auto_awesome_rounded
                        : Icons.menu_book_rounded,
                    label: chaos ? 'Trampas' : 'Reglas',
                    onTap: () => setState(() => selectedTab = 2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(17),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(5, 2, 5, 7),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: selectedContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameRailTab extends StatelessWidget {
  const _GameRailTab({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.verticalDock = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool verticalDock;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? (verticalDock ? PopColors.yellow : PopColors.blue)
        : (verticalDock
              ? Colors.white.withValues(alpha: .12)
              : PopColors.cloud),
    borderRadius: BorderRadius.circular(11),
    child: InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 3,
          vertical: verticalDock ? 4 : 7,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: verticalDock ? 19 : 18,
              color: verticalDock
                  ? (selected ? PopColors.navy : Colors.white)
                  : (selected ? Colors.white : PopColors.navy),
            ),
            PopText(
              label,
              maxLines: 1,
              style: TextStyle(
                color: verticalDock
                    ? (selected ? PopColors.navy : Colors.white)
                    : (selected ? Colors.white : PopColors.navy),
                fontSize: verticalDock ? 7.5 : 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LandscapePlayerStrip extends StatelessWidget {
  const _LandscapePlayerStrip({
    required this.engine,
    required this.onlineSession,
    required this.avatarIds,
  });

  final GameEngine engine;
  final OnlineMatchSession? onlineSession;
  final Map<PlayerColor, String?> avatarIds;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('landscape-player-strip'),
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: Row(
      children: [
        for (var index = 0; index < engine.players.length; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          Expanded(
            child: _LandscapePlayerMiniTile(
              player: engine.players[index],
              active: index == engine.currentPlayerIndex,
              participant: onlineSession?.participantForColor(
                engine.players[index].color,
              ),
              avatarId: avatarIds[engine.players[index].color],
              engine: engine,
            ),
          ),
        ],
      ],
    ),
  );
}

class _LandscapePlayerMiniTile extends StatelessWidget {
  const _LandscapePlayerMiniTile({
    required this.player,
    required this.active,
    required this.participant,
    required this.avatarId,
    required this.engine,
  });

  final PlayerState player;
  final bool active;
  final OnlineParticipant? participant;
  final String? avatarId;
  final GameEngine engine;

  @override
  Widget build(BuildContext context) {
    final color = _playerUiColor(player.color);
    final completed = player.tokens.where((token) => token.finished).length;
    final traps = engine.activeTrapsFor(player.color).length;
    final held = player.inventory;
    final displayName = participant?.displayName ?? player.name;
    final requiredFinishedTokens = engine.rules.tokensRequiredToWin;
    return Tooltip(
      message: appTranslate(
        context,
        '$displayName · $completed de $requiredFinishedTokens en meta'
        '${held == null ? '' : ' · ${engine.powerUpName(held)}'}'
        '${traps == 0 ? '' : ' · $traps trampas'}',
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: .16) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: active ? color : color.withValues(alpha: .20),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: color.withValues(alpha: .18),
              child: _AvatarArt(
                avatarId:
                    avatarId ??
                    participant?.avatarId ??
                    (player.isHuman ? 'avatar_default' : 'avatar_robot'),
                size: 20,
                withFrame: false,
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AutoFitSingleLineText(
                    displayName,
                    style: TextStyle(
                      color: PopColors.navy,
                      fontSize: 8.5,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      PopText(
                        '$completed/$requiredFinishedTokens',
                        style: TextStyle(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (held != null || traps > 0) ...[
                        const SizedBox(width: 3),
                        Icon(
                          held == PowerUp.shield
                              ? Icons.shield_rounded
                              : traps > 0
                              ? Icons.warning_amber_rounded
                              : Icons.auto_awesome_rounded,
                          size: 10,
                          color: held == PowerUp.shield
                              ? PopColors.blue
                              : traps > 0
                              ? PopColors.red
                              : const Color(0xFF7B61FF),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GamePowerRail extends StatelessWidget {
  const _GamePowerRail({
    super.key,
    required this.engine,
    required this.onShowPowers,
    this.onlineSession,
    this.revealTrapDetails = false,
  });

  final GameEngine engine;
  final VoidCallback onShowPowers;
  final OnlineMatchSession? onlineSession;
  final bool revealTrapDetails;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            engine.isChaos
                ? Icons.auto_awesome_rounded
                : Icons.workspace_premium_rounded,
            color: engine.isChaos ? const Color(0xFF7B61FF) : PopColors.blue,
            size: 34,
          ),
          const SizedBox(height: 7),
          PopText(
            engine.isChaos ? 'Poderes y trampas' : 'Reglas tradicionales',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PopColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (engine.isChaos) ...[
            for (final player in engine.players)
              _PowerStatusTile(
                engine: engine,
                player: player,
                revealTrapDetails: revealTrapDetails,
                participant: onlineSession?.participantForColor(player.color),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onShowPowers,
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const PopText('Ver detalle'),
            ),
          ],
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => engine.isChaos
                    ? const TrapPowerLabScreen()
                    : GameGuideScreen(
                        initialMode: engine.matchFormat == MatchFormat.quickPop
                            ? GameGuideMode.quickPop
                            : GameGuideMode.traditional,
                      ),
              ),
            ),
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: PopText(engine.isChaos ? 'Probar efectos' : 'Cómo jugar'),
          ),
        ],
      ),
    ),
  );
}

@immutable
class _FinalStandingEntry {
  const _FinalStandingEntry({
    required this.placement,
    required this.points,
    required this.player,
    required this.displayName,
    required this.avatarId,
    required this.reachedGoal,
    this.flag,
    this.level,
  });

  final int placement;
  final int points;
  final PlayerState player;
  final String displayName;
  final String? avatarId;
  final bool reachedGoal;
  final String? flag;
  final int? level;
}

class _VictoryCelebration extends StatefulWidget {
  const _VictoryCelebration({
    required this.winner,
    required this.mode,
    required this.matchFormat,
    required this.elapsed,
    required this.standings,
    required this.standingsComplete,
    this.rewardCoins = 0,
    this.doubleRewardCoins = 0,
    this.onContinueWatching,
    this.onWatchRewarded,
    this.rewardInProgress = false,
    this.rewardClaimed = false,
    this.navigationInProgress = false,
    required this.onPlayAgain,
    required this.onHome,
  });

  final PlayerState winner;
  final GameMode mode;
  final MatchFormat matchFormat;
  final Duration elapsed;
  final List<_FinalStandingEntry> standings;
  final bool standingsComplete;
  final int rewardCoins;
  final int doubleRewardCoins;
  final VoidCallback? onContinueWatching;
  final VoidCallback? onWatchRewarded;
  final bool rewardInProgress;
  final bool rewardClaimed;
  final bool navigationInProgress;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  State<_VictoryCelebration> createState() => _VictoryCelebrationState();
}

class _VictoryCelebrationState extends State<_VictoryCelebration>
    with TickerProviderStateMixin {
  late final AnimationController entranceController;
  late final AnimationController confettiController;

  Widget? _buildEarlyRewardSummary() {
    if (widget.rewardCoins <= 0 &&
        widget.onWatchRewarded == null &&
        !widget.rewardClaimed) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        key: const ValueKey('victory-early-reward'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.rewardCoins > 0)
            Container(
              key: const ValueKey('victory-early-earned-reward'),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
              decoration: BoxDecoration(
                color: PopColors.yellow.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: PopColors.yellow),
              ),
              child: PopText(
                '+${widget.rewardCoins} MONEDAS POR JUGAR',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PopColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          if (widget.rewardCoins > 0 &&
              (widget.onWatchRewarded != null || widget.rewardClaimed))
            const SizedBox(height: 10),
          if (widget.onWatchRewarded != null)
            FilledButton.icon(
              key: const ValueKey('victory-early-rewarded-ad'),
              onPressed: widget.rewardInProgress
                  ? null
                  : widget.onWatchRewarded,
              style: FilledButton.styleFrom(
                backgroundColor: PopColors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              icon: widget.rewardInProgress
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_circle_fill_rounded),
              label: PopText(
                widget.rewardInProgress
                    ? 'CARGANDO ANUNCIO…'
                    : 'VER ANUNCIO\n'
                          '+${widget.doubleRewardCoins} MONEDAS EXTRA',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else if (widget.rewardClaimed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: PopColors.green.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: PopColors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: PopText(
                      '+${widget.doubleRewardCoins} MONEDAS EXTRA RECIBIDAS',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: PopColors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildPinnedRewardSummary(
    BuildContext context, {
    required bool stacked,
  }) {
    if (widget.rewardCoins <= 0 &&
        widget.onWatchRewarded == null &&
        !widget.rewardClaimed) {
      return null;
    }
    final english = appLanguageCodeOf(context) == 'en';
    final earnedKey = ValueKey(
      widget.standingsComplete
          ? 'victory-earned-reward'
          : 'victory-early-earned-reward',
    );
    final rewardedKey = ValueKey(
      widget.standingsComplete
          ? 'victory-rewarded-ad'
          : 'victory-early-rewarded-ad',
    );

    Widget? earned;
    if (widget.rewardCoins > 0) {
      earned = Semantics(
        label: english
            ? 'Reward credited: ${widget.rewardCoins} coins'
            : 'Recompensa acreditada: ${widget.rewardCoins} monedas',
        excludeSemantics: true,
        child: Container(
          key: earnedKey,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: PopColors.yellow.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PopColors.yellow.withValues(alpha: .72)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.monetization_on_rounded,
                color: Color(0xFFC58C00),
                size: 21,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PopText(
                      '+${widget.rewardCoins} MONEDAS',
                      maxLines: 1,
                      style: const TextStyle(
                        color: PopColors.navy,
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const PopText(
                      'POR JUGAR',
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xFF6A5830),
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget? extra;
    if (widget.onWatchRewarded != null) {
      final onPressed = widget.rewardInProgress || widget.navigationInProgress
          ? null
          : widget.onWatchRewarded;
      extra = Semantics(
        label: english
            ? 'Optional. Watch an ad to receive '
                  '${widget.doubleRewardCoins} extra coins'
            : 'Opcional. Ver anuncio para recibir '
                  '${widget.doubleRewardCoins} monedas extra',
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
        excludeSemantics: true,
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: rewardedKey,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE4F7EC),
              foregroundColor: const Color(0xFF09663E),
              disabledBackgroundColor: const Color(0xFFE9EFEA),
              disabledForegroundColor: const Color(0xFF66746B),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              side: const BorderSide(color: Color(0xFF178552), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: widget.rewardInProgress
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF09663E),
                    ),
                  )
                : const Icon(Icons.play_circle_fill_rounded, size: 21),
            label: widget.rewardInProgress
                ? const PopText(
                    'CARGANDO…',
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PopText(
                        '+${widget.doubleRewardCoins} EXTRA',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const PopText(
                        'VER ANUNCIO',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } else if (widget.rewardClaimed) {
      extra = Semantics(
        label: english
            ? '${widget.doubleRewardCoins} extra coins received'
            : '${widget.doubleRewardCoins} monedas extra recibidas',
        excludeSemantics: true,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: PopColors.green.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PopColors.green.withValues(alpha: .38)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF09663E),
                size: 20,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PopText(
                      '+${widget.doubleRewardCoins} MONEDAS',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF09663E),
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const PopText(
                      'EXTRA RECIBIDAS',
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xFF09663E),
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = <Widget>[
      if (earned != null) Expanded(child: earned),
      if (earned != null && extra != null) const SizedBox(width: 8),
      if (extra != null) Expanded(child: extra),
    ];
    if (stacked) {
      return Column(
        key: const ValueKey('victory-pinned-reward'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (earned != null) SizedBox(width: double.infinity, child: earned),
          if (earned != null && extra != null) const SizedBox(height: 8),
          if (extra != null) SizedBox(width: double.infinity, child: extra),
        ],
      );
    }

    return Row(
      key: const ValueKey('victory-pinned-reward'),
      children: children,
    );
  }

  Widget _buildVictoryActions(BuildContext context, {required bool compact}) {
    final compactPlayAgainLabel = appLanguageCodeOf(context) == 'en'
        ? 'PLAY AGAIN'
        : 'OTRA VEZ';
    final compactHomeLabel = appLanguageCodeOf(context) == 'en'
        ? 'HOME'
        : 'INICIO';
    final buttonHeight = compact ? 48.0 : 0.0;

    Widget playAgainButton() => Semantics(
      label: appTranslate(context, 'JUGAR OTRA VEZ'),
      button: true,
      enabled: !widget.navigationInProgress,
      onTap: widget.navigationInProgress ? null : widget.onPlayAgain,
      excludeSemantics: true,
      child: FilledButton.icon(
        key: const ValueKey('victory-play-again'),
        onPressed: widget.navigationInProgress ? null : widget.onPlayAgain,
        style: FilledButton.styleFrom(
          backgroundColor: PopColors.blue,
          foregroundColor: Colors.white,
          minimumSize: compact ? Size(0, buttonHeight) : null,
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
        ),
        icon: Icon(Icons.replay_rounded, size: compact ? 20 : 24),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: PopText(compact ? compactPlayAgainLabel : 'JUGAR OTRA VEZ'),
        ),
      ),
    );

    Widget homeButton() => Semantics(
      label: appTranslate(context, 'VOLVER AL INICIO'),
      button: true,
      enabled: !widget.navigationInProgress,
      onTap: widget.navigationInProgress ? null : widget.onHome,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        key: const ValueKey('victory-home'),
        onPressed: widget.navigationInProgress ? null : widget.onHome,
        style: OutlinedButton.styleFrom(
          foregroundColor: PopColors.navy,
          minimumSize: compact ? Size(0, buttonHeight) : null,
          padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
          side: BorderSide(
            color: PopColors.navy.withValues(alpha: .24),
            width: 1.5,
          ),
        ),
        icon: Icon(Icons.home_rounded, size: compact ? 20 : 24),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: PopText(compact ? compactHomeLabel : 'VOLVER AL INICIO'),
        ),
      ),
    );

    final continueWatching = widget.onContinueWatching == null
        ? null
        : SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('victory-continue-watching'),
              onPressed: widget.navigationInProgress
                  ? null
                  : widget.onContinueWatching,
              style: FilledButton.styleFrom(
                backgroundColor: PopColors.green,
                foregroundColor: Colors.white,
                minimumSize: compact ? Size(0, buttonHeight) : null,
                padding: EdgeInsets.symmetric(vertical: compact ? 12 : 15),
              ),
              icon: Icon(Icons.visibility_rounded, size: compact ? 20 : 24),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: PopText('SEGUIR VIENDO LA PARTIDA'),
              ),
            ),
          );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (continueWatching != null) ...[
            continueWatching,
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: playAgainButton()),
              const SizedBox(width: 8),
              Expanded(child: homeButton()),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (continueWatching != null) ...[
          continueWatching,
          const SizedBox(height: 9),
        ],
        SizedBox(width: double.infinity, child: playAgainButton()),
        const SizedBox(height: 9),
        SizedBox(width: double.infinity, child: homeButton()),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    entranceController.dispose();
    confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _FinalStandingEntry? winnerStanding;
    for (final entry in widget.standings) {
      if (entry.player.color == widget.winner.color) {
        winnerStanding = entry;
        break;
      }
    }
    final winnerColor = _playerUiColor(widget.winner.color);
    final humanWon = widget.winner.isHuman;
    final winnerName = winnerStanding?.displayName ?? widget.winner.name;
    final title = widget.standingsComplete
        ? 'CLASIFICACIÓN FINAL'
        : humanWon
        ? '¡GANASTE!'
        : '¡BUENA PARTIDA!';
    final winnerLabel = humanWon
        ? 'TÚ ERES EL CAMPEÓN'
        : '${winnerName.toUpperCase()} GANA';
    final tokenDescription = widget.matchFormat == MatchFormat.quickPop
        ? 'dos fichas'
        : 'cuatro fichas';
    final description = humanWon
        ? 'Tus $tokenDescription llegaron a la meta.'
        : '$winnerName llevó sus $tokenDescription a la meta. '
              '¡La revancha está lista!';
    final semanticsLabel = widget.standingsComplete
        ? '$title. La partida terminó. Estos son los resultados.'
        : '$title $winnerLabel';

    return Semantics(
      container: true,
      liveRegion: true,
      label: appTranslate(context, semanticsLabel),
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: Listenable.merge([entranceController, confettiController]),
          builder: (context, _) {
            final fade = Curves.easeOut.transform(entranceController.value);
            final scale =
                .72 +
                Curves.elasticOut.transform(entranceController.value) * .28;
            return LayoutBuilder(
              builder: (context, viewport) {
                final pinActions =
                    viewport.maxWidth <= 600 && viewport.maxHeight < 820;
                final stackPinnedReward = viewport.maxWidth < 350;
                final pinnedReward = pinActions
                    ? _buildPinnedRewardSummary(
                        context,
                        stacked: stackPinnedReward,
                      )
                    : null;
                final actionDockHeight =
                    (widget.onContinueWatching == null ? 68.0 : 124.0) +
                    (pinnedReward == null
                        ? 0.0
                        : stackPinnedReward
                        ? 128.0
                        : 64.0);
                return Stack(
                  key: const ValueKey('victory-celebration'),
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: PopColors.navy.withValues(alpha: .88 * fade),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ConfettiPainter(
                            progress: confettiController.value,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          pinActions ? 12 : 24,
                          20,
                          pinActions ? actionDockHeight + 28 : 24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              0.0,
                              viewport.maxHeight -
                                  (pinActions ? actionDockHeight + 40 : 48),
                            ),
                          ),
                          child: Center(
                            child: Opacity(
                              opacity: fade,
                              child: Transform.scale(
                                scale: scale,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  child: Container(
                                    key: const ValueKey('victory-card'),
                                    padding: EdgeInsets.fromLTRB(
                                      pinActions ? 16 : 24,
                                      pinActions ? 14 : 22,
                                      pinActions ? 16 : 24,
                                      pinActions ? 16 : 24,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFFFFFFF),
                                          Color(0xFFFFF8DC),
                                          Color(0xFFF1F7FF),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(34),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: .32,
                                          ),
                                          blurRadius: 34,
                                          offset: const Offset(0, 18),
                                        ),
                                        BoxShadow(
                                          color: PopColors.yellow.withValues(
                                            alpha: .36,
                                          ),
                                          blurRadius: 28,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Transform.rotate(
                                          angle:
                                              math.sin(
                                                confettiController.value *
                                                    math.pi *
                                                    2,
                                              ) *
                                              .035,
                                          child: Container(
                                            width: pinActions ? 52 : 92,
                                            height: pinActions ? 52 : 92,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFFFE56A),
                                                  Color(0xFFFFB514),
                                                  Color(0xFFFF8A24),
                                                ],
                                              ),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: pinActions ? 4 : 5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: PopColors.yellow
                                                      .withValues(alpha: .55),
                                                  blurRadius: 22,
                                                  offset: const Offset(0, 9),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.emoji_events_rounded,
                                              color: Colors.white,
                                              size: pinActions ? 31 : 54,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: pinActions ? 6 : 14),
                                        PopText(
                                          title,
                                          key: const ValueKey('victory-title'),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color:
                                                widget.standingsComplete ||
                                                    humanWon
                                                ? PopColors.navy
                                                : winnerColor,
                                            fontSize: pinActions ? 28 : 34,
                                            height: 1,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: .3,
                                          ),
                                        ),
                                        SizedBox(height: pinActions ? 6 : 12),
                                        if (widget.standingsComplete) ...[
                                          PopText(
                                            'La partida terminó. Estos son los resultados.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: const Color(0xFF526078),
                                              fontSize: pinActions ? 13 : 15,
                                              height: 1.25,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(
                                            height: pinActions ? 10 : 16,
                                          ),
                                          _FinalRanking(
                                            entries: widget.standings,
                                            compact: pinActions,
                                          ),
                                          SizedBox(height: pinActions ? 8 : 12),
                                          if (!pinActions &&
                                              widget.rewardCoins > 0) ...[
                                            Container(
                                              key: const ValueKey(
                                                'victory-earned-reward',
                                              ),
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 11,
                                                    horizontal: 14,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: PopColors.yellow
                                                    .withValues(alpha: .22),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: PopColors.yellow,
                                                ),
                                              ),
                                              child: PopText(
                                                '+${widget.rewardCoins} MONEDAS POR JUGAR',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: PopColors.navy,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                          ],
                                          if (!pinActions &&
                                              widget.onWatchRewarded != null)
                                            SizedBox(
                                              width: double.infinity,
                                              child: FilledButton.icon(
                                                key: const ValueKey(
                                                  'victory-rewarded-ad',
                                                ),
                                                onPressed:
                                                    widget.rewardInProgress
                                                    ? null
                                                    : widget.onWatchRewarded,
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      PopColors.green,
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 13,
                                                      ),
                                                ),
                                                icon: widget.rewardInProgress
                                                    ? const SizedBox.square(
                                                        dimension: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .play_circle_fill_rounded,
                                                      ),
                                                label: PopText(
                                                  widget.rewardInProgress
                                                      ? 'CARGANDO ANUNCIO…'
                                                      : 'VER ANUNCIO\n'
                                                            '+${widget.doubleRewardCoins} MONEDAS EXTRA',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    height: 1.05,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (!pinActions &&
                                              widget.rewardClaimed)
                                            Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                    horizontal: 14,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: PopColors.green
                                                    .withValues(alpha: .12),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle_rounded,
                                                    color: PopColors.green,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Flexible(
                                                    child: PopText(
                                                      '+${widget.doubleRewardCoins} MONEDAS EXTRA RECIBIDAS',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: PopColors.green,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (!pinActions)
                                            const SizedBox(height: 10),
                                        ] else ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 9,
                                            ),
                                            decoration: BoxDecoration(
                                              color: winnerColor,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: winnerColor.withValues(
                                                    alpha: .30,
                                                  ),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (winnerStanding?.avatarId
                                                    case final avatarId?)
                                                  _AvatarArt(
                                                    avatarId: avatarId,
                                                    size: 24,
                                                    withFrame: false,
                                                  )
                                                else
                                                  Icon(
                                                    humanWon
                                                        ? Icons.star_rounded
                                                        : Icons
                                                              .smart_toy_rounded,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                                const SizedBox(width: 7),
                                                Flexible(
                                                  child: PopText(
                                                    winnerLabel,
                                                    key: const ValueKey(
                                                      'victory-winner',
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: .3,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height: pinActions ? 10 : 13,
                                          ),
                                          PopText(
                                            description,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Color(0xFF526078),
                                              fontSize: 15,
                                              height: 1.25,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(
                                            height: pinActions ? 11 : 14,
                                          ),
                                          Wrap(
                                            alignment: WrapAlignment.center,
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _VictoryStat(
                                                icon: Icons.flag_rounded,
                                                label:
                                                    widget.matchFormat ==
                                                        MatchFormat.quickPop
                                                    ? '2 / 2 EN META'
                                                    : '4 / 4 EN META',
                                                color: winnerColor,
                                              ),
                                              _VictoryStat(
                                                icon:
                                                    widget.mode ==
                                                        GameMode.chaos
                                                    ? Icons.bolt_rounded
                                                    : Icons
                                                          .workspace_premium_rounded,
                                                label:
                                                    widget.matchFormat ==
                                                        MatchFormat.quickPop
                                                    ? 'QUICK POP'
                                                    : widget.mode ==
                                                          GameMode.chaos
                                                    ? 'MODO CAOS'
                                                    : 'TRADICIONAL',
                                                color:
                                                    widget.mode ==
                                                        GameMode.chaos
                                                    ? const Color(0xFF7B61FF)
                                                    : PopColors.yellow,
                                              ),
                                              _VictoryStat(
                                                icon: Icons.timer_outlined,
                                                label:
                                                    '${appTranslate(context, 'TIEMPO')} '
                                                    '${_formatMatchDuration(widget.elapsed)}',
                                                color: PopColors.blue,
                                              ),
                                              if (winnerStanding
                                                  case final standing?)
                                                if (standing.level != null)
                                                  _VictoryStat(
                                                    icon: Icons
                                                        .military_tech_rounded,
                                                    label:
                                                        '${standing.flag ?? ''}  '
                                                        'NIVEL ${standing.level}',
                                                    color: winnerColor,
                                                  ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 11,
                                            ),
                                            decoration: BoxDecoration(
                                              color: PopColors.green.withValues(
                                                alpha: .10,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color: PopColors.green
                                                    .withValues(alpha: .28),
                                              ),
                                            ),
                                            child: const Column(
                                              children: [
                                                PopText(
                                                  'PARTIDA EN PAUSA',
                                                  style: TextStyle(
                                                    color: PopColors.green,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                SizedBox(height: 3),
                                                PopText(
                                                  'Los demás jugadores siguen compitiendo por su posición.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Color(0xFF526078),
                                                    fontSize: 12,
                                                    height: 1.2,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!pinActions)
                                            ?_buildEarlyRewardSummary(),
                                        ],
                                        if (!pinActions) ...[
                                          const SizedBox(height: 22),
                                          _buildVictoryActions(
                                            context,
                                            compact: false,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (pinActions)
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 12,
                        child: Opacity(
                          opacity: fade,
                          child: Container(
                            key: const ValueKey('victory-action-dock'),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFFFFF), Color(0xFFFFF8DC)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .28),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pinnedReward != null) ...[
                                  pinnedReward,
                                  const SizedBox(height: 8),
                                ],
                                _buildVictoryActions(context, compact: true),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FinalRanking extends StatelessWidget {
  const _FinalRanking({required this.entries, this.compact = false});

  final List<_FinalStandingEntry> entries;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = List<_FinalStandingEntry>.of(entries)
      ..sort((a, b) => a.placement.compareTo(b.placement));
    return Semantics(
      container: true,
      label: appTranslate(context, 'CLASIFICACIÓN FINAL'),
      child: Container(
        key: const ValueKey('final-ranking'),
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          compact ? 6 : 9,
          compact ? 6 : 9,
          compact ? 6 : 9,
          compact ? 7 : 10,
        ),
        decoration: BoxDecoration(
          color: PopColors.navy,
          borderRadius: BorderRadius.circular(compact ? 20 : 24),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: PopColors.navy.withValues(alpha: .20),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 6 : 9,
                compact ? 0 : 2,
                compact ? 6 : 9,
                compact ? 5 : 8,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: PopColors.yellow,
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: PopText(
                      'CLASIFICACIÓN FINAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  PopText(
                    'PUNTOS',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                ],
              ),
            ),
            for (final entry in sortedEntries)
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 4 : 6),
                child: _FinalRankingRow(entry: entry, compact: compact),
              ),
          ],
        ),
      ),
    );
  }
}

class _FinalRankingRow extends StatelessWidget {
  const _FinalRankingRow({required this.entry, required this.compact});

  final _FinalStandingEntry entry;
  final bool compact;

  Color get medalColor => switch (entry.placement) {
    1 => const Color(0xFFFFBE24),
    2 => const Color(0xFF8AA3C7),
    3 => const Color(0xFFE9823B),
    _ => const Color(0xFF64748B),
  };

  String _placementLabel(BuildContext context) {
    final placement = entry.placement;
    if (appLanguageCodeOf(context) != 'en') return '$placement.º';
    final suffix = switch (placement) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
    return '$placement$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final playerColor = _playerUiColor(entry.player.color);
    final placementLabel = _placementLabel(context);
    final flag = entry.flag?.trim();
    final semanticName = [
      entry.displayName,
      if (flag != null && flag.isNotEmpty) flag,
    ].join(' ');
    return Semantics(
      label:
          '$placementLabel, $semanticName, ${entry.points} '
          '${appTranslate(context, 'PUNTOS')}',
      child: Container(
        key: ValueKey('final-ranking-${entry.placement}'),
        constraints: BoxConstraints(minHeight: compact ? 46 : 58),
        padding: EdgeInsets.fromLTRB(
          compact ? 6 : 8,
          compact ? 4 : 7,
          compact ? 7 : 10,
          compact ? 4 : 7,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Color.lerp(Colors.white, playerColor, .10)!],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: entry.placement == 1
                ? medalColor
                : Colors.white.withValues(alpha: .72),
            width: entry.placement == 1 ? 2.2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .11),
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 30 : 36,
              height: compact ? 30 : 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: medalColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withValues(alpha: .34),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: PopText(
                placementLabel,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SizedBox(width: compact ? 5 : 7),
            _AvatarArt(
              avatarId:
                  entry.avatarId ??
                  (entry.player.isHuman ? 'avatar_default' : 'avatar_robot'),
              size: compact ? 31 : 38,
            ),
            SizedBox(width: compact ? 6 : 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 19,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: PopText(
                        [
                          entry.displayName,
                          if (flag != null && flag.isNotEmpty) flag,
                        ].join(' '),
                        maxLines: 1,
                        style: TextStyle(
                          color: PopColors.navy,
                          fontSize: compact ? 13 : 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (entry.level case final level?)
                    PopText(
                      'Nivel $level',
                      style: TextStyle(
                        color: playerColor,
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  else
                    PopText(
                      entry.reachedGoal ? 'EN META' : 'ÚLTIMO LUGAR',
                      style: TextStyle(
                        color: playerColor,
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: compact ? 5 : 7),
            Container(
              key: ValueKey('final-ranking-points-${entry.placement}'),
              constraints: BoxConstraints(minWidth: compact ? 49 : 58),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: compact ? 5 : 7,
              ),
              decoration: BoxDecoration(
                color: playerColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: playerColor.withValues(alpha: .26),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: PopText(
                '${entry.points} PTS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VictoryStat extends StatelessWidget {
  const _VictoryStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .26)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 5),
        PopText(
          label,
          style: TextStyle(
            color: Color.lerp(color, PopColors.navy, .30),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress});

  final double progress;

  static const colors = [
    PopColors.red,
    PopColors.blue,
    PopColors.yellow,
    PopColors.green,
    Color(0xFF7B61FF),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < 58; index++) {
      final seed = ((index * 37) % 101) / 101;
      final fall = (progress + seed) % 1;
      final horizontal = ((index * 53) % 97) / 97;
      final sway = math.sin((progress * 2 + index * .17) * math.pi * 2) * 16;
      final center = Offset(
        horizontal * size.width + sway,
        -28 + fall * (size.height + 56),
      );
      final particleSize = 5.0 + (index % 5) * 1.35;
      final paint = Paint()..color = colors[index % colors.length];
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(progress * math.pi * 4 + index * .63);
      if (index % 4 == 0) {
        canvas.drawCircle(Offset.zero, particleSize * .62, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particleSize,
              height: particleSize * 1.85,
            ),
            Radius.circular(particleSize * .28),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _TokenMovePopup extends StatelessWidget {
  const _TokenMovePopup({
    required this.tokenNumber,
    required this.tokenInNest,
    required this.choices,
    required this.twentyStepColor,
    required this.homeEntryCaptureChoices,
    required this.captureTargetsByDie,
    required this.rolledDice,
    required this.onChoice,
    required this.allDiceTotal,
    required this.allDiceCaptureTarget,
    required this.onAllDice,
    required this.onCancel,
  });

  final int tokenNumber;
  final bool tokenInNest;
  final List<int> choices;
  final Color twentyStepColor;
  final Set<int> homeEntryCaptureChoices;
  final Map<int, GameToken> captureTargetsByDie;
  final List<int> rolledDice;
  final ValueChanged<int> onChoice;
  final int? allDiceTotal;
  final GameToken? allDiceCaptureTarget;
  final VoidCallback onAllDice;
  final VoidCallback onCancel;

  String _captureColorName(
    BuildContext context,
    PlayerColor color, {
    bool semantic = false,
  }) {
    final english = appLanguageCodeOf(context) == 'en';
    return switch ((english, semantic, color)) {
      (true, _, PlayerColor.red) => semantic ? 'red' : 'RED',
      (true, _, PlayerColor.green) => semantic ? 'green' : 'GREEN',
      (true, _, PlayerColor.yellow) => semantic ? 'yellow' : 'YELLOW',
      (true, _, PlayerColor.blue) => semantic ? 'blue' : 'BLUE',
      (false, true, PlayerColor.red) => 'roja',
      (false, true, PlayerColor.green) => 'verde',
      (false, true, PlayerColor.yellow) => 'amarilla',
      (false, true, PlayerColor.blue) => 'azul',
      (false, false, PlayerColor.red) => 'ROJO',
      (false, false, PlayerColor.green) => 'VERDE',
      (false, false, PlayerColor.yellow) => 'AMARILLO',
      (false, false, PlayerColor.blue) => 'AZUL',
    };
  }

  Color _captureColor(PlayerColor color) => switch (color) {
    PlayerColor.red => PopColors.red,
    PlayerColor.green => PopColors.green,
    PlayerColor.yellow => PopColors.yellow,
    PlayerColor.blue => PopColors.blue,
  };

  Widget _withCaptureLabel(
    BuildContext context,
    Widget primary,
    GameToken? target, {
    required String keySuffix,
  }) {
    if (target == null) return primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(flex: 3, child: primary),
          const SizedBox(height: 1),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.gps_fixed_rounded,
                    color: Colors.white,
                    size: 10,
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _captureColor(target.owner),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                  const SizedBox(width: 2),
                  PopText(
                    'KILL ${_captureColorName(context, target.owner)}',
                    key: ValueKey('popup-move-choice-kill-$keySuffix'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceButton(BuildContext context, int value) {
    final color = value == 20
        ? twentyStepColor
        : _moveChoiceColor(rolledDice, value);
    final isExit = tokenInNest && value == 5;
    final isHomeEntryCapture = homeEntryCaptureChoices.contains(value);
    final target = captureTargetsByDie[value];
    final english = appLanguageCodeOf(context) == 'en';
    final baseLabel = isExit
        ? english
              ? 'Move piece $tokenNumber out of jail with $value'
              : 'Sacar ficha $tokenNumber de la cárcel con $value'
        : isHomeEntryCapture
        ? english
              ? 'Capture the piece blocking the home entry with $value'
              : 'Capturar la ficha que bloquea la entrada con $value'
        : value == 20
        ? english
              ? 'Move piece $tokenNumber with the 20-step bonus'
              : 'Mover ficha $tokenNumber con el bono de 20 pasos'
        : english
        ? 'Move piece $tokenNumber, $value '
              '${value == 1 ? 'step' : 'steps'}'
        : 'Mover ficha $tokenNumber, $value '
              '${value == 1 ? 'paso' : 'pasos'}';
    final semanticColor = target == null
        ? null
        : _captureColorName(context, target.owner, semantic: true);
    final semanticLabel = target == null
        ? baseLabel
        : isHomeEntryCapture
        ? english
              ? 'Capture the $semanticColor piece blocking the home entry '
                    'with $value'
              : 'Capturar la ficha $semanticColor que bloquea la entrada '
                    'con $value'
        : english
        ? '$baseLabel and capture the $semanticColor piece'
        : '$baseLabel y capturar la ficha $semanticColor';
    final primary = isExit
        ? const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.directions_run_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 3),
                PopText(
                  'SALIDA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          )
        : isHomeEntryCapture
        ? const FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gps_fixed_rounded, color: Colors.white, size: 15),
                SizedBox(width: 3),
                PopText(
                  'CAPTURAR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .1,
                  ),
                ),
              ],
            ),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopText(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 3),
                PopText(
                  value == 1 ? 'paso' : 'pasos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticLabel,
      onTap: () => onChoice(value),
      child: SizedBox(
        key: ValueKey('move-choice-$value'),
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onChoice(value),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(color, Colors.white, .12)!,
                    color,
                    Color.lerp(color, PopColors.navy, .12)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .30),
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _withCaptureLabel(
                context,
                primary,
                target,
                keySuffix: '${target?.owner.name ?? 'none'}-$value',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _allDiceButton(BuildContext context, int total) {
    const color = Color(0xFF7057FF);
    final target = allDiceCaptureTarget;
    final english = appLanguageCodeOf(context) == 'en';
    final baseLabel = english
        ? 'Move piece $tokenNumber using both dice, $total steps total'
        : 'Mover ficha $tokenNumber usando ambos dados, $total pasos en total';
    final semanticColor = target == null
        ? null
        : _captureColorName(context, target.owner, semantic: true);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: target == null
          ? baseLabel
          : english
          ? '$baseLabel and capture the $semanticColor piece'
          : '$baseLabel y capturar la ficha $semanticColor',
      onTap: onAllDice,
      child: SizedBox(
        key: const ValueKey('move-choice-all'),
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onAllDice,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(color, Colors.white, .14)!,
                    color,
                    Color.lerp(color, PopColors.navy, .16)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .32),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _withCaptureLabel(
                context,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 3),
                      const PopText(
                        'TODOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopText(
                        '$total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                target,
                keySuffix: '${target?.owner.name ?? 'none'}-all',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = choices.contains(20)
        ? twentyStepColor
        : const Color(0xFF7057FF);
    final popupStart = Color.lerp(accentColor, Colors.white, .93)!;
    final popupEnd = Color.lerp(accentColor, Colors.white, .86)!;

    final buttons = <Widget>[
      ...choices.map((value) => _choiceButton(context, value)),
      if (allDiceTotal case final total?) _allDiceButton(context, total),
    ];
    return Material(
      key: const ValueKey('token-move-popup'),
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 3, 4, 0),
        padding: const EdgeInsets.fromLTRB(10, 7, 7, 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [popupStart, popupEnd],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: accentColor, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: .24),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: PopText(
                    '$tokenNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: PopText(
                    'FICHA $tokenNumber · '
                    '${tokenInNest
                        ? 'SALIDA'
                        : homeEntryCaptureChoices.isNotEmpty
                        ? 'CAPTURA'
                        : choices.contains(20)
                        ? 'BONO +20'
                        : 'PASOS'}',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      color: PopColors.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: appTranslate(context, 'Cerrar'),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                for (var index = 0; index < buttons.length; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(child: buttons[index]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBoardNotice extends StatelessWidget {
  const _MobileBoardNotice({
    required this.child,
    this.anchor,
    this.preferTop = false,
    this.interactive = false,
    this.height = 72,
  });

  final Widget child;
  final Offset? anchor;
  final bool preferTop;
  final bool interactive;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Keep short-lived feedback inside the board's existing square instead of
    // inserting another row into the phone layout. Place it opposite the
    // affected cell so the animation and token remain visible.
    final placeAtTop = preferTop || (anchor?.dy ?? 0) >= 10;
    final notice = SizedBox(width: 350, height: height, child: child);
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Align(
          alignment: placeAtTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: interactive
              ? notice
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: notice,
                ),
        ),
      ),
    );
  }
}

enum _MoveCalloutPointerSide { top, right, bottom, left }

class _BoardTokenChoiceCallout extends StatelessWidget {
  const _BoardTokenChoiceCallout({
    required this.geometry,
    required this.target,
    required this.avoidTokenCenters,
    required this.rolledDice,
    required this.remainingDice,
    required this.onTap,
    required this.onTapAt,
  });

  final _BoardGeometry geometry;
  final Offset target;
  final List<Offset> avoidTokenCenters;
  final List<int> rolledDice;
  final List<int> remainingDice;
  final VoidCallback onTap;
  final bool Function(Offset boardPosition) onTapAt;

  @override
  Widget build(BuildContext context) {
    const size = Size(160, 50);
    const margin = 8.0;
    final targetPixel = geometry.toPixel(target);
    final boardExtent = geometry.cell * 20 + geometry.inset * 2;
    final bounds = Rect.fromLTWH(
      margin,
      margin,
      boardExtent - margin * 2,
      boardExtent - margin * 2,
    );
    final horizontalReach = size.width / 2 + 13;
    final verticalReach = size.height / 2 + 13;
    final candidates = <Offset>[
      if (targetPixel.dy >= boardExtent / 2)
        Offset(0, -verticalReach)
      else
        Offset(0, verticalReach),
      if (targetPixel.dx < boardExtent / 2)
        Offset(horizontalReach, 0)
      else
        Offset(-horizontalReach, 0),
      if (targetPixel.dx < boardExtent / 2)
        Offset(-horizontalReach, 0)
      else
        Offset(horizontalReach, 0),
      if (targetPixel.dy >= boardExtent / 2)
        Offset(0, verticalReach)
      else
        Offset(0, -verticalReach),
    ];
    final protectedCenters = avoidTokenCenters
        .where((center) => (center - target).distance > .01)
        .map(geometry.toPixel)
        .toList(growable: false);
    final protectedRadius = math.max(24.0, geometry.cell * .82);
    Rect? calloutRect;
    var bestScore = double.infinity;
    for (
      var candidateIndex = 0;
      candidateIndex < candidates.length;
      candidateIndex++
    ) {
      final offset = candidates[candidateIndex];
      final candidate = Rect.fromCenter(
        center: targetPixel + offset,
        width: size.width,
        height: size.height,
      );
      if (bounds.contains(candidate.topLeft) &&
          bounds.contains(candidate.bottomRight)) {
        var score = candidateIndex * 10.0;
        for (final center in protectedCenters) {
          if (candidate.inflate(protectedRadius).contains(center)) {
            score += 1000000;
          }
        }
        if (score < bestScore) {
          bestScore = score;
          calloutRect = candidate;
        }
      }
    }
    calloutRect ??= Rect.fromLTWH(
      (targetPixel.dx - size.width / 2)
          .clamp(bounds.left, bounds.right - size.width)
          .toDouble(),
      (targetPixel.dy - size.height - 12)
          .clamp(bounds.top, bounds.bottom - size.height)
          .toDouble(),
      size.width,
      size.height,
    );
    final pointerSide = _moveCalloutPointerSide(calloutRect, targetPixel);
    final pointerOffset = _moveCalloutPointerOffset(
      calloutRect,
      targetPixel,
      pointerSide,
    );
    final values = remainingDice.toSet().take(3).toList(growable: false);
    final english = Localizations.localeOf(context).languageCode == 'en';
    final diceLabel = values.join(english ? ' or ' : ' o ');

    return Positioned.fromRect(
      rect: calloutRect,
      child: Semantics(
        key: const ValueKey('board-token-choice-callout'),
        button: true,
        excludeSemantics: true,
        label: english
            ? 'Choose a highlighted piece. Available dice: $diceLabel.'
            : 'Elige una ficha marcada. Dados disponibles: $diceLabel.',
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final boardPosition = calloutRect!.topLeft + details.localPosition;
            if (!onTapAt(boardPosition)) onTap();
          },
          child: CustomPaint(
            painter: _MoveCalloutBubblePainter(
              color: PopColors.yellow,
              side: pointerSide,
              pointerOffset: pointerOffset,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.touch_app_rounded,
                    color: PopColors.blue,
                    size: 18,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PopText(
                          english ? 'CHOOSE' : 'ELIGE',
                          maxLines: 1,
                          style: const TextStyle(
                            color: PopColors.navy,
                            fontSize: 8.5,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        PopText(
                          english ? 'PIECE' : 'FICHA',
                          maxLines: 1,
                          style: const TextStyle(
                            color: PopColors.navy,
                            fontSize: 8.5,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final value in values) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _moveChoiceColor(rolledDice, value),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.4),
                      ),
                      child: PopText(
                        '$value',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _BoardMoveCalloutLayout {
  const _BoardMoveCalloutLayout({
    required this.preview,
    required this.originalIndex,
    required this.rect,
    required this.target,
    required this.pointerSide,
    required this.pointerOffset,
    required this.pointerTip,
  });

  final MoveDestinationPreview preview;
  final int originalIndex;
  final Rect rect;
  final Offset target;
  final _MoveCalloutPointerSide pointerSide;
  final double pointerOffset;
  final Offset pointerTip;
}

Size _boardMoveCalloutSize(MoveDestinationPreview preview) {
  // Leave a small margin above the 48-point accessibility minimum because
  // the complete board can be fractionally scaled on short phones.
  if (preview.captureTarget != null) return const Size(112, 50);
  if (preview.usesAllDice) return const Size(100, 50);
  if (preview.isHomeEntryCapture) return const Size(104, 50);
  if (preview.isExit || preview.isGoal || preview.value == 20) {
    return const Size(92, 50);
  }
  return Size(preview.value >= 10 ? 90 : 84, 50);
}

_MoveCalloutPointerSide _moveCalloutPointerSide(Rect rect, Offset target) {
  if (target.dy < rect.top) return _MoveCalloutPointerSide.top;
  if (target.dx > rect.right) return _MoveCalloutPointerSide.right;
  if (target.dy > rect.bottom) return _MoveCalloutPointerSide.bottom;
  if (target.dx < rect.left) return _MoveCalloutPointerSide.left;

  final distances = <(_MoveCalloutPointerSide, double)>[
    (_MoveCalloutPointerSide.top, (target.dy - rect.top).abs()),
    (_MoveCalloutPointerSide.right, (rect.right - target.dx).abs()),
    (_MoveCalloutPointerSide.bottom, (rect.bottom - target.dy).abs()),
    (_MoveCalloutPointerSide.left, (target.dx - rect.left).abs()),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return distances.first.$1;
}

double _moveCalloutPointerOffset(
  Rect rect,
  Offset target,
  _MoveCalloutPointerSide side,
) => switch (side) {
  _MoveCalloutPointerSide.top || _MoveCalloutPointerSide.bottom =>
    (target.dx - rect.left).clamp(15.0, rect.width - 15).toDouble(),
  _MoveCalloutPointerSide.left || _MoveCalloutPointerSide.right =>
    (target.dy - rect.top).clamp(15.0, rect.height - 15).toDouble(),
};

Offset _moveCalloutPointerTip(
  Rect rect,
  _MoveCalloutPointerSide side,
  double pointerOffset,
) => switch (side) {
  _MoveCalloutPointerSide.top => Offset(
    rect.left + pointerOffset,
    rect.top - 8,
  ),
  _MoveCalloutPointerSide.right => Offset(
    rect.right + 8,
    rect.top + pointerOffset,
  ),
  _MoveCalloutPointerSide.bottom => Offset(
    rect.left + pointerOffset,
    rect.bottom + 8,
  ),
  _MoveCalloutPointerSide.left => Offset(
    rect.left - 8,
    rect.top + pointerOffset,
  ),
};

List<_BoardMoveCalloutLayout> _layoutBoardMoveCallouts({
  required List<MoveDestinationPreview> previews,
  required _BoardGeometry geometry,
  required Offset? selectedTokenCenter,
  required List<Offset> avoidTokenCenters,
}) {
  if (previews.isEmpty) return const <_BoardMoveCalloutLayout>[];

  const margin = 7.0;
  const separation = 8.0;
  final boardBounds = Rect.fromLTWH(
    margin,
    margin,
    geometry.cell * 20 - margin * 2 + geometry.inset * 2,
    geometry.cell * 20 - margin * 2 + geometry.inset * 2,
  );
  final targets = previews
      .map((preview) => geometry.toPixel(preview.cell))
      .toList(growable: false);
  final avoidPoints = <Offset>[
    ...targets,
    if (selectedTokenCenter != null) geometry.toPixel(selectedTokenCenter),
  ];
  final protectedTokenCenters = avoidTokenCenters
      .map(geometry.toPixel)
      .toList(growable: false);
  final protectedTokenRadius = math.max(24.0, geometry.cell * .82);
  final ordered = previews.indexed.toList()
    ..sort((a, b) {
      if (a.$2.usesAllDice != b.$2.usesAllDice) {
        return a.$2.usesAllDice ? -1 : 1;
      }
      return b.$2.value.compareTo(a.$2.value);
    });
  final result = <_BoardMoveCalloutLayout>[];

  for (final entry in ordered) {
    final originalIndex = entry.$1;
    final preview = entry.$2;
    final target = targets[originalIndex];
    final size = _boardMoveCalloutSize(preview);
    final horizontalReach = size.width + 14;
    final verticalReach = size.height / 2 + 15;
    final candidates = <Offset>[
      Offset(0, -verticalReach),
      Offset(horizontalReach, 0),
      Offset(-horizontalReach, 0),
      Offset(0, verticalReach),
      Offset(horizontalReach * .76, -verticalReach * 1.05),
      Offset(-horizontalReach * .76, -verticalReach * 1.05),
      Offset(horizontalReach * .76, verticalReach * 1.05),
      Offset(-horizontalReach * .76, verticalReach * 1.05),
      Offset(0, -verticalReach * 2.55),
      Offset(horizontalReach * 1.65, 0),
      Offset(-horizontalReach * 1.65, 0),
      Offset(0, verticalReach * 2.55),
      Offset(horizontalReach * 1.35, -verticalReach * 2.05),
      Offset(-horizontalReach * 1.35, -verticalReach * 2.05),
      Offset(horizontalReach * 1.35, verticalReach * 2.05),
      Offset(-horizontalReach * 1.35, verticalReach * 2.05),
    ];

    Rect? bestRect;
    var bestScore = double.infinity;
    for (
      var candidateIndex = 0;
      candidateIndex < candidates.length;
      candidateIndex++
    ) {
      final rect = Rect.fromCenter(
        center: target + candidates[candidateIndex],
        width: size.width,
        height: size.height,
      );
      if (!boardBounds.contains(rect.topLeft) ||
          !boardBounds.contains(rect.bottomRight)) {
        continue;
      }

      var score = candidateIndex * 12.0;
      for (final placed in result) {
        final overlap = rect.intersect(placed.rect.inflate(separation));
        if (!overlap.isEmpty) {
          score += 10000000 + overlap.width * overlap.height * 1000;
        }
      }
      for (final point in avoidPoints) {
        if (rect.inflate(5).contains(point)) score += 1000000;
      }
      for (final center in protectedTokenCenters) {
        if (rect.inflate(protectedTokenRadius).contains(center)) {
          score += 10000000;
        }
      }
      final nearest = Offset(
        target.dx.clamp(rect.left, rect.right).toDouble(),
        target.dy.clamp(rect.top, rect.bottom).toDouble(),
      );
      score += (nearest - target).distance;
      if (score < bestScore) {
        bestScore = score;
        bestRect = rect;
      }
    }

    bestRect ??= Rect.fromLTWH(
      (target.dx - size.width / 2)
          .clamp(boardBounds.left, boardBounds.right - size.width)
          .toDouble(),
      (target.dy > geometry.cell * 10
              ? target.dy - size.height - 12
              : target.dy + 12)
          .clamp(boardBounds.top, boardBounds.bottom - size.height)
          .toDouble(),
      size.width,
      size.height,
    );
    final pointerSide = _moveCalloutPointerSide(bestRect, target);
    final pointerOffset = _moveCalloutPointerOffset(
      bestRect,
      target,
      pointerSide,
    );
    result.add(
      _BoardMoveCalloutLayout(
        preview: preview,
        originalIndex: originalIndex,
        rect: bestRect,
        target: target,
        pointerSide: pointerSide,
        pointerOffset: pointerOffset,
        pointerTip: _moveCalloutPointerTip(
          bestRect,
          pointerSide,
          pointerOffset,
        ),
      ),
    );
  }
  return result..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
}

class _BoardMoveChoiceCallouts extends StatelessWidget {
  const _BoardMoveChoiceCallouts({
    required this.previews,
    required this.geometry,
    required this.selectedTokenCenter,
    required this.avoidTokenCenters,
    required this.onChoice,
    required this.onTapAt,
  });

  final List<MoveDestinationPreview> previews;
  final _BoardGeometry geometry;
  final Offset? selectedTokenCenter;
  final List<Offset> avoidTokenCenters;
  final ValueChanged<MoveDestinationPreview> onChoice;
  final bool Function(Offset boardPosition) onTapAt;

  @override
  Widget build(BuildContext context) {
    final layouts = _layoutBoardMoveCallouts(
      previews: previews,
      geometry: geometry,
      selectedTokenCenter: selectedTokenCenter,
      avoidTokenCenters: avoidTokenCenters,
    );
    return KeyedSubtree(
      key: const ValueKey('board-move-callout-layer'),
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _MoveCalloutConnectorPainter(layouts),
              child: const SizedBox.expand(),
            ),
          ),
          for (final layout in layouts)
            Positioned.fromRect(
              rect: layout.rect,
              child: _BoardMoveChoiceCallout(
                key: ValueKey(
                  layout.preview.usesAllDice
                      ? 'board-move-callout-token-'
                            '${layout.preview.token.id}-all'
                      : 'board-move-callout-token-'
                            '${layout.preview.token.id}-die-'
                            '${layout.preview.value}',
                ),
                layout: layout,
                onTap: () => onChoice(layout.preview),
                onTapAt: onTapAt,
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardMoveChoiceCallout extends StatefulWidget {
  const _BoardMoveChoiceCallout({
    super.key,
    required this.layout,
    required this.onTap,
    required this.onTapAt,
  });

  final _BoardMoveCalloutLayout layout;
  final VoidCallback onTap;
  final bool Function(Offset boardPosition) onTapAt;

  @override
  State<_BoardMoveChoiceCallout> createState() =>
      _BoardMoveChoiceCalloutState();
}

class _BoardMoveChoiceCalloutState extends State<_BoardMoveChoiceCallout> {
  bool pressed = false;

  String _colorName(BuildContext context, PlayerColor color) {
    final english = appLanguageCodeOf(context) == 'en';
    return switch ((english, color)) {
      (true, PlayerColor.red) => 'RED',
      (true, PlayerColor.green) => 'GREEN',
      (true, PlayerColor.yellow) => 'YELLOW',
      (true, PlayerColor.blue) => 'BLUE',
      (false, PlayerColor.red) => 'ROJO',
      (false, PlayerColor.green) => 'VERDE',
      (false, PlayerColor.yellow) => 'AMARILLO',
      (false, PlayerColor.blue) => 'AZUL',
    };
  }

  String _semanticColorName(BuildContext context, PlayerColor color) {
    final english = appLanguageCodeOf(context) == 'en';
    return switch ((english, color)) {
      (true, PlayerColor.red) => 'red',
      (true, PlayerColor.green) => 'green',
      (true, PlayerColor.yellow) => 'yellow',
      (true, PlayerColor.blue) => 'blue',
      (false, PlayerColor.red) => 'roja',
      (false, PlayerColor.green) => 'verde',
      (false, PlayerColor.yellow) => 'amarilla',
      (false, PlayerColor.blue) => 'azul',
    };
  }

  Color _teamColor(PlayerColor color) => switch (color) {
    PlayerColor.red => PopColors.red,
    PlayerColor.green => PopColors.green,
    PlayerColor.yellow => PopColors.yellow,
    PlayerColor.blue => PopColors.blue,
  };

  String _semanticLabel(BuildContext context) {
    final preview = widget.layout.preview;
    final tokenNumber = preview.token.id + 1;
    final english = appLanguageCodeOf(context) == 'en';
    final target = preview.captureTarget;
    final targetColor = target == null
        ? null
        : _semanticColorName(context, target.owner);
    if (preview.isHomeEntryCapture && targetColor != null) {
      return english
          ? 'Capture the $targetColor piece blocking the home entry with '
                '${preview.value}'
          : 'Capturar la ficha $targetColor que bloquea la entrada con '
                '${preview.value}';
    }
    late final String baseLabel;
    if (preview.isExit) {
      baseLabel = english
          ? 'Move piece $tokenNumber out of jail with ${preview.value}'
          : 'Sacar ficha $tokenNumber de la cárcel con ${preview.value}';
    } else if (preview.isHomeEntryCapture) {
      baseLabel = english
          ? 'Capture the piece blocking the home entry with ${preview.value}'
          : 'Capturar la ficha que bloquea la entrada con ${preview.value}';
    } else if (preview.usesAllDice) {
      baseLabel = english
          ? 'Move piece $tokenNumber using both dice, '
                '${preview.value} steps total'
          : 'Mover ficha $tokenNumber usando ambos dados, '
                '${preview.value} pasos en total';
    } else {
      baseLabel = english
          ? 'Move piece $tokenNumber, ${preview.value} '
                '${preview.value == 1 ? 'step' : 'steps'}'
          : 'Mover ficha $tokenNumber, ${preview.value} '
                '${preview.value == 1 ? 'paso' : 'pasos'}';
    }
    if (target == null) return baseLabel;
    return english
        ? '$baseLabel and capture the $targetColor piece'
        : '$baseLabel y capturar la ficha $targetColor';
  }

  Widget _numberBadge(int value, Color color) => Container(
    width: 25,
    height: 25,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .28),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: PopText(
      '$value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  Widget _primaryContent(MoveDestinationPreview preview) {
    final color = preview.color;
    if (preview.usesAllDice) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fast_forward_rounded, color: color, size: 15),
            const SizedBox(width: 2),
            const PopText(
              'TODOS',
              style: TextStyle(
                color: PopColors.navy,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            _numberBadge(preview.value, color),
          ],
        ),
      );
    }

    final specialLabel = preview.isExit
        ? 'SALIDA'
        : preview.isHomeEntryCapture
        ? 'CAPTURAR'
        : preview.isGoal
        ? 'META'
        : preview.value == 20
        ? '+20'
        : null;
    if (specialLabel != null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              preview.isExit
                  ? Icons.directions_run_rounded
                  : preview.isHomeEntryCapture
                  ? Icons.gps_fixed_rounded
                  : preview.isGoal
                  ? Icons.flag_rounded
                  : Icons.add_circle_rounded,
              color: color,
              size: 15,
            ),
            const SizedBox(width: 3),
            PopText(
              specialLabel,
              style: const TextStyle(
                color: PopColors.navy,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 5),
            _numberBadge(preview.value, color),
          ],
        ),
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _numberBadge(preview.value, color),
          const SizedBox(width: 5),
          PopText(
            preview.value == 1 ? 'PASO' : 'PASOS',
            style: const TextStyle(
              color: PopColors.navy,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, MoveDestinationPreview preview) {
    final target = preview.captureTarget;
    if (target == null) return _primaryContent(preview);
    final targetColor = _teamColor(target.owner);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(flex: 3, child: _primaryContent(preview)),
        const SizedBox(height: 1),
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gps_fixed_rounded, color: PopColors.red, size: 11),
                const SizedBox(width: 3),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: targetColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: PopColors.navy, width: 1),
                  ),
                ),
                const SizedBox(width: 3),
                PopText(
                  'KILL ${_colorName(context, target.owner)}',
                  key: ValueKey('move-choice-kill-${target.owner.name}'),
                  style: const TextStyle(
                    color: PopColors.navy,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.layout.preview;
    final legacyKey = preview.usesAllDice
        ? const ValueKey('move-choice-all')
        : ValueKey('move-choice-${preview.value}');
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      excludeSemantics: true,
      sortKey: OrdinalSortKey(widget.layout.originalIndex.toDouble()),
      label: _semanticLabel(context),
      onTap: widget.onTap,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final boardPosition =
                widget.layout.rect.topLeft + details.localPosition;
            if (!widget.onTapAt(boardPosition)) widget.onTap();
          },
          child: AnimatedScale(
            scale: reduceMotion || !pressed ? 1 : .96,
            duration: const Duration(milliseconds: 80),
            child: CustomPaint(
              painter: _MoveCalloutBubblePainter(
                color: preview.color,
                side: widget.layout.pointerSide,
                pointerOffset: widget.layout.pointerOffset,
              ),
              child: SizedBox(
                key: legacyKey,
                width: double.infinity,
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: _content(context, preview),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveCalloutBubblePainter extends CustomPainter {
  const _MoveCalloutBubblePainter({
    required this.color,
    required this.side,
    required this.pointerOffset,
  });

  final Color color;
  final _MoveCalloutPointerSide side;
  final double pointerOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)),
      );
    final pointer = Path();
    switch (side) {
      case _MoveCalloutPointerSide.top:
        pointer
          ..moveTo(pointerOffset - 7, 1)
          ..lineTo(pointerOffset, -8)
          ..lineTo(pointerOffset + 7, 1);
        break;
      case _MoveCalloutPointerSide.right:
        pointer
          ..moveTo(size.width - 1, pointerOffset - 7)
          ..lineTo(size.width + 8, pointerOffset)
          ..lineTo(size.width - 1, pointerOffset + 7);
        break;
      case _MoveCalloutPointerSide.bottom:
        pointer
          ..moveTo(pointerOffset - 7, size.height - 1)
          ..lineTo(pointerOffset, size.height + 8)
          ..lineTo(pointerOffset + 7, size.height - 1);
        break;
      case _MoveCalloutPointerSide.left:
        pointer
          ..moveTo(1, pointerOffset - 7)
          ..lineTo(-8, pointerOffset)
          ..lineTo(1, pointerOffset + 7);
        break;
    }
    pointer.close();
    final path = Path.combine(PathOperation.union, body, pointer);
    canvas.drawShadow(path, PopColors.navy.withValues(alpha: .26), 7, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color.lerp(color, Colors.white, .91)!],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = PopColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _MoveCalloutBubblePainter oldDelegate) =>
      color != oldDelegate.color ||
      side != oldDelegate.side ||
      pointerOffset != oldDelegate.pointerOffset;
}

class _MoveCalloutConnectorPainter extends CustomPainter {
  const _MoveCalloutConnectorPainter(this.layouts);

  final List<_BoardMoveCalloutLayout> layouts;

  @override
  void paint(Canvas canvas, Size size) {
    for (final layout in layouts) {
      final delta = layout.target - layout.pointerTip;
      final distance = delta.distance;
      if (distance <= 1) continue;
      final direction = delta / distance;
      final end = layout.target - direction * 7;
      canvas.drawLine(
        layout.pointerTip,
        end,
        Paint()
          ..color = Colors.white.withValues(alpha: .94)
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        layout.pointerTip,
        end,
        Paint()
          ..color = layout.preview.color
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MoveCalloutConnectorPainter oldDelegate) =>
      !listEquals(layouts, oldDelegate.layouts);
}

class _AnimatedThemeBackdrop extends StatefulWidget {
  const _AnimatedThemeBackdrop({required this.themeId});

  final String? themeId;

  @override
  State<_AnimatedThemeBackdrop> createState() => _AnimatedThemeBackdropState();
}

class _AnimatedThemeBackdropState extends State<_AnimatedThemeBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  bool motionConfigured = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(covariant _AnimatedThemeBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeId != widget.themeId) {
      motionConfigured = false;
      _configureMotion();
    }
  }

  void _configureMotion() {
    final theme = themeVisualSpecFor(widget.themeId);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate = theme.motif != ThemeMotif.classic && !reduceMotion;
    if (motionConfigured && shouldAnimate == controller.isAnimating) return;
    motionConfigured = true;
    if (shouldAnimate) {
      controller.repeat();
    } else {
      controller
        ..stop()
        ..value = theme.motif == ThemeMotif.classic ? 0 : .38;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = themeVisualSpecFor(widget.themeId);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => CustomPaint(
              key: ValueKey('game-theme-backdrop-${theme.id}'),
              painter: ThemeScenePainter(
                theme: theme,
                progress: controller.value,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class GameBoardMockup extends StatefulWidget {
  const GameBoardMockup({
    super.key,
    required this.engine,
    this.compactPhone = false,
    this.selectedToken,
    this.movePreviews,
    this.themeId,
    this.playerThemeIds = const <PlayerColor, String?>{},
    this.revealAllTraps = false,
    this.robotTokens = false,
    this.robotTokenColors = const <PlayerColor>{},
    this.tokenStyleIds = const <PlayerColor, String?>{},
    this.playerLabels = const <PlayerColor, String>{},
  });
  final GameEngine engine;
  final bool compactPhone;
  final GameToken? selectedToken;
  final List<MoveDestinationPreview>? movePreviews;

  /// Legacy single-player theme. When supplied it only styles the red/local
  /// quadrant; shared routes and the other three bases remain neutral.
  final String? themeId;
  final Map<PlayerColor, String?> playerThemeIds;
  final bool revealAllTraps;
  final bool robotTokens;
  final Set<PlayerColor> robotTokenColors;
  final Map<PlayerColor, String?> tokenStyleIds;
  final Map<PlayerColor, String> playerLabels;

  Map<PlayerColor, String?> get resolvedPlayerThemeIds {
    final resolved = <PlayerColor, String?>{...playerThemeIds};
    if (!resolved.containsKey(PlayerColor.red) && themeId != null) {
      resolved[PlayerColor.red] = themeId;
    }
    return resolved;
  }

  @override
  State<GameBoardMockup> createState() => _GameBoardMockupState();
}

class _GameBoardMockupState extends State<GameBoardMockup>
    with TickerProviderStateMixin {
  late final AnimationController controller;
  late final AnimationController pulseController;
  late final AnimationController cubeController;
  late final AnimationController effectController;
  int lastEffectSerial = 0;
  bool lastGameOver = false;
  bool motionConfigured = false;
  final Map<GameToken, Offset> lastCells = {};
  final Map<GameToken, Offset> fromCells = {};
  final Map<GameToken, Offset> viaCells = {};
  final Map<GameToken, Offset> toCells = {};
  final Map<GameToken, int> lastProgress = {};
  final Map<GameToken, List<Offset>> routeCells = {};

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    cubeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    lastEffectSerial = widget.engine.effectSerial;
    lastGameOver = widget.engine.gameOver;
    lastCells.addAll(_currentCells());
    for (final player in widget.engine.players) {
      for (final token in player.tokens) {
        lastProgress[token] = token.progress;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureAmbientMotion();
  }

  void _configureAmbientMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate = !lastGameOver && !reduceMotion;
    if (motionConfigured &&
        pulseController.isAnimating == shouldAnimate &&
        cubeController.isAnimating == shouldAnimate) {
      return;
    }
    motionConfigured = true;
    if (shouldAnimate) {
      pulseController.repeat(reverse: true);
      cubeController.repeat();
    } else {
      pulseController
        ..stop()
        ..value = .5;
      cubeController
        ..stop()
        ..value = .25;
    }
  }

  @override
  void didUpdateWidget(covariant GameBoardMockup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compactPhone != widget.compactPhone) {
      controller.reset();
      fromCells.clear();
      viaCells.clear();
      toCells.clear();
      routeCells.clear();
      lastCells
        ..clear()
        ..addAll(_currentCells());
    }
    if (lastGameOver != widget.engine.gameOver) {
      lastGameOver = widget.engine.gameOver;
      motionConfigured = false;
      _configureAmbientMotion();
    }
    final hasNewEffect = lastEffectSerial != widget.engine.effectSerial;
    final next = _currentCells();
    final currentVisualCells = _animatedCells();
    final nextFromCells = <GameToken, Offset>{};
    final nextViaCells = <GameToken, Offset>{};
    final nextToCells = <GameToken, Offset>{};
    final nextRouteCells = <GameToken, List<Offset>>{};
    for (final token in next.keys) {
      if (lastCells[token] != next[token]) {
        final from =
            currentVisualCells[token] ?? lastCells[token] ?? next[token]!;
        final to = next[token]!;
        nextFromCells[token] = from;
        nextToCells[token] = to;
        final effectIndex = widget.engine.effectLoopIndex;
        if (hasNewEffect &&
            widget.engine.effectToken == token &&
            effectIndex != null) {
          nextViaCells[token] = GameEngine.loop[effectIndex];
        } else {
          nextRouteCells[token] = _movementRoute(
            token,
            lastProgress[token],
            token.progress,
            from,
            to,
          );
        }
      }
      lastProgress[token] = token.progress;
    }
    lastCells
      ..clear()
      ..addAll(next);
    if (nextFromCells.isNotEmpty) {
      fromCells
        ..clear()
        ..addAll(nextFromCells);
      viaCells
        ..clear()
        ..addAll(nextViaCells);
      toCells
        ..clear()
        ..addAll(nextToCells);
      routeCells
        ..clear()
        ..addAll(nextRouteCells);
      final longestRoute = nextRouteCells.values.fold<int>(
        1,
        (longest, route) => math.max(longest, route.length - 1),
      );
      controller.duration = nextViaCells.isEmpty
          ? Duration(
              milliseconds: (280 + longestRoute * 58).clamp(420, 1050).toInt(),
            )
          : const Duration(milliseconds: 950);
      controller.forward(from: 0);
    }
    if (hasNewEffect) {
      lastEffectSerial = widget.engine.effectSerial;
      effectController.forward(from: 0);
    }
  }

  Map<GameToken, Offset> _currentCells() {
    return _displayTokenCells(widget.engine, compactPhone: widget.compactPhone);
  }

  List<Offset> _movementRoute(
    GameToken token,
    int? previousProgress,
    int nextProgress,
    Offset from,
    Offset to,
  ) {
    final route = <Offset>[from];
    if (previousProgress != null &&
        previousProgress >= 0 &&
        nextProgress >= 0 &&
        previousProgress != nextProgress) {
      final direction = nextProgress > previousProgress ? 1 : -1;
      for (
        var progress = previousProgress + direction;
        progress != nextProgress + direction;
        progress += direction
      ) {
        final cell = widget.engine.cellForProgress(token.owner, progress);
        if (cell != null) route.add(cell);
      }
    }
    if (route.length == 1) {
      route.add(to);
    } else if (nextProgress >= GameEngine.finishProgress && route.last != to) {
      // Let the piece visibly touch the center/meta before it is filed in the
      // completed column inside its own base.
      route.add(to);
    } else {
      route[route.length - 1] = to;
    }
    return route;
  }

  Map<GameToken, Offset> _animatedCells() {
    final curve = Curves.easeInOutCubic.transform(controller.value);
    final result = <GameToken, Offset>{};
    for (final entry in lastCells.entries) {
      final token = entry.key;
      if (!fromCells.containsKey(token)) {
        result[token] = entry.value;
        continue;
      }
      final from = fromCells[token]!;
      final to = toCells[token]!;
      final via = viaCells[token];
      if (via == null) {
        final route = routeCells[token];
        if (route == null || route.length < 2) {
          result[token] = Offset.lerp(from, to, curve)!;
          continue;
        }
        final routePosition = curve * (route.length - 1);
        final segment = routePosition
            .floor()
            .clamp(0, route.length - 2)
            .toInt();
        final segmentProgress = routePosition - segment;
        result[token] = Offset.lerp(
          route[segment],
          route[segment + 1],
          segmentProgress,
        )!;
        continue;
      }
      if (controller.value < .46) {
        final arrival = Curves.easeOutCubic.transform(
          (controller.value / .46).clamp(0.0, 1.0),
        );
        result[token] = Offset.lerp(from, via, arrival)!;
      } else {
        final reaction = Curves.easeInOutCubic.transform(
          ((controller.value - .46) / .54).clamp(0.0, 1.0),
        );
        result[token] = Offset.lerp(via, to, reaction)!;
      }
    }
    return result;
  }

  @override
  void dispose() {
    controller.dispose();
    pulseController.dispose();
    cubeController.dispose();
    effectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D17284D),
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AnimatedBuilder(
          animation: Listenable.merge([
            controller,
            pulseController,
            cubeController,
            effectController,
          ]),
          builder: (context, _) => CustomPaint(
            painter: _ParcheseBoardPainter(
              widget.engine,
              compactPhone: widget.compactPhone,
              selectedToken: widget.selectedToken,
              animatedCells: _animatedCells(),
              pulse: pulseController.value,
              cubeSpin: cubeController.value,
              effectProgress: effectController.value,
              playerThemeIds: widget.resolvedPlayerThemeIds,
              revealAllTraps: widget.revealAllTraps,
              robotTokens: widget.robotTokens,
              robotTokenColors: widget.robotTokenColors,
              tokenStyleIds: widget.tokenStyleIds,
              playerLabels: widget.playerLabels,
              localPlayerLabel: appTranslate(context, 'TÚ'),
              languageCode: appLanguageCodeOf(context),
              movePreviews:
                  widget.movePreviews ??
                  _moveDestinationPreviews(widget.engine, widget.selectedToken),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _ParcheseBoardPainter extends CustomPainter {
  const _ParcheseBoardPainter(
    this.engine, {
    required this.compactPhone,
    required this.selectedToken,
    required this.animatedCells,
    required this.pulse,
    required this.cubeSpin,
    required this.effectProgress,
    required this.playerThemeIds,
    required this.revealAllTraps,
    required this.robotTokens,
    required this.robotTokenColors,
    required this.tokenStyleIds,
    required this.playerLabels,
    required this.localPlayerLabel,
    required this.languageCode,
    required this.movePreviews,
  });
  final GameEngine engine;
  final bool compactPhone;
  final GameToken? selectedToken;
  final Map<GameToken, Offset> animatedCells;
  final double pulse;
  final double cubeSpin;
  final double effectProgress;
  final Map<PlayerColor, String?> playerThemeIds;
  final bool revealAllTraps;
  final bool robotTokens;
  final Set<PlayerColor> robotTokenColors;
  final Map<PlayerColor, String?> tokenStyleIds;
  final Map<PlayerColor, String> playerLabels;
  final String localPlayerLabel;
  final String languageCode;
  final List<MoveDestinationPreview> movePreviews;

  List<BoardTrap> get displayedTraps =>
      (revealAllTraps
              ? engine.traps
              : engine.visibleTrapsFor(engine.localViewerColor))
          .toList(growable: false);

  Color trapOwnerColor(BoardTrap trap) => _playerColor(trap.owner);

  static const grid = 20;
  // Four gray safe stars plus the four special home-entry stars.  For
  // example, red's entrance is printed between squares 63 and 65.
  static const visibleStarIndices = {7, 12, 24, 29, 41, 46, 58, 63};
  static const departureColors = {
    0: PopColors.red,
    17: PopColors.green,
    34: PopColors.yellow,
    51: PopColors.blue,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final geometry = _BoardGeometry(side, compactPhone: compactPhone);
    final cell = geometry.cell;
    final outerBoard = Rect.fromLTWH(0, 0, side, side);
    final frameCell = side / grid;
    // A cosmetic belongs to a player, not to the shared table. Keep the
    // routes and frame classic so every quadrant can show its owner's
    // independent loadout without changing another player's side. Each goal
    // triangle is themed independently for the player who owns it.
    const theme = defaultThemeVisualSpec;
    final boardSurface = theme.boardSurfaceColor;
    final framePrimary = theme.framePrimaryColor;
    final frameAccent = theme.frameAccentColor;
    final outline = Paint()
      ..color = theme.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, cell * (compactPhone ? .042 : .055));

    ThemeScenePainter(
      theme: theme,
      progress: cubeSpin,
    ).paint(canvas, outerBoard.size);
    canvas.drawRect(
      outerBoard,
      Paint()
        ..color = boardSurface.withValues(
          alpha: theme.motif == ThemeMotif.classic ? .82 : .16,
        ),
    );
    _themePattern(canvas, outerBoard, theme, frameCell, cubeSpin);
    canvas.save();
    canvas.translate(geometry.inset, geometry.inset);

    _base(
      canvas,
      cell,
      0,
      0,
      PopColors.blue,
      PlayerColor.blue,
      themeVisualSpecFor(playerThemeIds[PlayerColor.blue]),
      cubeSpin,
    );
    _base(
      canvas,
      cell,
      13,
      0,
      PopColors.yellow,
      PlayerColor.yellow,
      themeVisualSpecFor(playerThemeIds[PlayerColor.yellow]),
      cubeSpin,
    );
    _base(
      canvas,
      cell,
      0,
      13,
      PopColors.red,
      PlayerColor.red,
      themeVisualSpecFor(playerThemeIds[PlayerColor.red]),
      cubeSpin,
    );
    _base(
      canvas,
      cell,
      13,
      13,
      PopColors.green,
      PlayerColor.green,
      themeVisualSpecFor(playerThemeIds[PlayerColor.green]),
      cubeSpin,
    );

    for (var index = 0; index < GameEngine.loop.length; index++) {
      final departure = departureColors[index];
      final isStar = visibleStarIndices.contains(index);
      final sectorOwner = visualSectorOwnerForLoopIndex(index);
      final sectorTheme = themeVisualSpecFor(playerThemeIds[sectorOwner]);
      final isCosmic = sectorTheme.motif == ThemeMotif.cosmic;
      final fill = isCosmic
          ? (departure == null
                ? sectorTheme.trackSurfaceColor
                : Color.lerp(departure, sectorTheme.scenePrimaryColor, .58)!)
          : departure ??
                (isStar ? const Color(0xFFC9CDD3) : theme.trackSurfaceColor);
      final transition = _transitionTrackPath(index, cell);
      if (transition == null) {
        final rect = _trackRect(GameEngine.loop[index], cell);
        _raisedCell(canvas, rect, fill, outline);
        if (isCosmic) {
          _cosmicCellOverlay(
            canvas,
            Path()..addRect(rect),
            rect,
            sectorTheme,
            index,
            outline,
            emphasized: departure != null,
          );
        }
      } else {
        _raisedPathCell(canvas, transition, fill, outline);
        if (isCosmic) {
          _cosmicCellOverlay(
            canvas,
            transition,
            transition.getBounds(),
            sectorTheme,
            index,
            outline,
            emphasized: departure != null,
          );
        }
      }
    }

    for (final entry in GameEngine.homeLanes.entries) {
      final teamColor = _playerColor(entry.key);
      final ownerTheme = themeVisualSpecFor(playerThemeIds[entry.key]);
      final color = ownerTheme.motif == ThemeMotif.classic
          ? teamColor
          : Color.lerp(teamColor, ownerTheme.scenePrimaryColor, .18)!;
      for (var laneIndex = 0; laneIndex < entry.value.length; laneIndex++) {
        final center = entry.value[laneIndex];
        final rect = _homeRect(entry.key, center, cell);
        _raisedCell(canvas, rect, color, outline, strong: true);
        if (ownerTheme.motif == ThemeMotif.cosmic) {
          _cosmicCellOverlay(
            canvas,
            Path()..addRect(rect),
            rect,
            ownerTheme,
            100 + entry.key.index * 10 + laneIndex,
            outline,
            emphasized: laneIndex == entry.value.length - 1,
          );
        }
      }
    }

    _center(canvas, cell, playerThemeIds, cubeSpin);

    for (var index = 0; index < GameEngine.loop.length; index++) {
      final logicalCenter = GameEngine.loop[index];
      final center = logicalCenter * cell;
      if (visibleStarIndices.contains(index)) {
        final safeTheme = themeVisualSpecFor(
          playerThemeIds[visualSectorOwnerForLoopIndex(index)],
        );
        final starCenter =
            (logicalCenter +
                safeStarPaintNudgeForTesting(
                  index,
                  compactPhone: compactPhone,
                )) *
            cell;
        _safe(canvas, cell, starCenter, theme: safeTheme);
      } else if (!departureColors.containsKey(index)) {
        final numberTheme = themeVisualSpecFor(
          playerThemeIds[visualSectorOwnerForLoopIndex(index)],
        );
        _number(
          canvas,
          cell,
          center,
          index + 1,
          color: numberTheme.motif == ThemeMotif.cosmic
              ? const Color(0xFFFFF4ED)
              : null,
        );
      }
    }

    if (engine.isChaos) {
      for (final index in engine.itemLoopIndices) {
        _item(canvas, cell, GameEngine.loop[index] * cell, index);
      }
      for (final trap in displayedTraps) {
        _trap(canvas, cell, GameEngine.loop[trap.loopIndex] * cell, trap);
      }
    }

    _moveDestinationHighlights(canvas, cell);
    _tokens(canvas, cell);
    _moveDestinationBadges(canvas, cell);
    if (engine.effectBoardCell case final effectCell?) {
      _effect(canvas, cell, effectCell * cell, engine.effectPowerUp);
    }
    canvas.restore();
    final roundedBoard = RRect.fromRectAndRadius(
      outerBoard.deflate(frameCell * .08),
      Radius.circular(frameCell * .55),
    );
    canvas.drawRRect(
      roundedBoard,
      Paint()
        ..color = framePrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = frameCell * .22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        outerBoard.deflate(frameCell * .20),
        Radius.circular(frameCell * .45),
      ),
      Paint()
        ..color = frameAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = frameCell * .10,
    );
  }

  void _themePattern(
    Canvas canvas,
    Rect board,
    ThemeVisualSpec theme,
    double unit,
    double progress,
  ) {
    if (theme.motif == ThemeMotif.classic) return;
    final accent = Paint()
      ..color = theme.frameAccentColor.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * .075)
      ..strokeCap = StrokeCap.round;
    switch (theme.motif) {
      case ThemeMotif.neon:
        final scanY = board.top + board.height * progress;
        canvas.drawRect(
          Rect.fromLTWH(board.left, scanY, board.width, unit * .34),
          Paint()
            ..shader =
                LinearGradient(
                  colors: [
                    Colors.transparent,
                    theme.scenePrimaryColor.withValues(alpha: .34),
                    Colors.transparent,
                  ],
                ).createShader(
                  Rect.fromLTWH(board.left, scanY, board.width, unit * .34),
                ),
        );
        for (var offset = -board.height; offset < board.width; offset += unit) {
          canvas.drawLine(
            Offset(offset + progress * unit, board.bottom),
            Offset(offset + board.height + progress * unit, board.top),
            accent,
          );
        }
        break;
      case ThemeMotif.golden:
        for (var index = 0; index < 5; index++) {
          final center = Offset(
            board.width * (.10 + index * .20),
            board.height * (.10 + ((index + 1) % 2) * .80),
          );
          final pyramid = Path()
            ..moveTo(center.dx, center.dy - unit * .38)
            ..lineTo(center.dx + unit * .45, center.dy + unit * .30)
            ..lineTo(center.dx - unit * .45, center.dy + unit * .30)
            ..close();
          canvas.drawPath(
            pyramid,
            Paint()
              ..color = theme.sceneGlowColor.withValues(
                alpha:
                    .22 + .12 * math.sin((progress + index / 5) * math.pi * 2),
              ),
          );
          canvas.drawPath(pyramid, accent);
        }
        break;
      case ThemeMotif.tropical:
        for (var index = 0; index < 8; index++) {
          final phase = progress * math.pi * 2 + index;
          final center = Offset(
            board.width * ((.08 + index * .13) % .92),
            board.height * (index.isEven ? .08 : .92),
          );
          _themeLeaf(
            canvas,
            center,
            unit * .55,
            phase * .08,
            theme.scenePrimaryColor.withValues(alpha: .34),
          );
          canvas.drawCircle(
            Offset(
              board.width * ((index * .17 + progress * .11) % 1),
              board.height * (.18 + (index % 4) * .21),
            ),
            unit * .065,
            Paint()
              ..color = theme.sceneGlowColor.withValues(
                alpha: .48 + .32 * math.sin(phase).abs(),
              ),
          );
        }
        break;
      case ThemeMotif.retro:
        final horizon = board.top + board.height * .48;
        final sunsetCenter = Offset(
          board.center.dx,
          board.top + board.height * .24,
        );
        final sunsetRadius = unit * 1.28;
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(center: sunsetCenter, radius: sunsetRadius),
          ),
        );
        canvas.drawCircle(
          sunsetCenter,
          sunsetRadius,
          Paint()
            ..shader =
                RadialGradient(
                  colors: [
                    theme.sceneGlowColor.withValues(alpha: .34),
                    theme.scenePrimaryColor.withValues(alpha: .22),
                  ],
                ).createShader(
                  Rect.fromCircle(center: sunsetCenter, radius: sunsetRadius),
                ),
        );
        for (var stripe = 0; stripe < 6; stripe++) {
          canvas.drawRect(
            Rect.fromLTWH(
              sunsetCenter.dx - sunsetRadius,
              sunsetCenter.dy - sunsetRadius + unit * (.26 + stripe * .36),
              sunsetRadius * 2,
              unit * .11,
            ),
            Paint()..color = theme.sceneSkyColor.withValues(alpha: .52),
          );
        }
        canvas.restore();
        _themeRetroGrid(
          canvas,
          Rect.fromLTRB(board.left, horizon, board.right, board.bottom),
          theme.sceneSecondaryColor.withValues(alpha: .28),
          progress,
        );
        final scanY = board.top + board.height * ((progress * 1.18 + .08) % 1);
        canvas.drawRect(
          Rect.fromLTWH(board.left, scanY, board.width, unit * .06),
          Paint()..color = theme.sceneGlowColor.withValues(alpha: .22),
        );
        for (var index = 0; index < 10; index++) {
          final isTop = index.isEven;
          final center = Offset(
            board.left + board.width * (.06 + (index * .113) % .88),
            isTop ? board.top + unit * .25 : board.bottom - unit * .25,
          );
          _themePixelSpark(
            canvas,
            center,
            unit * (.10 + (index % 3) * .025),
            (index.isEven ? theme.scenePrimaryColor : theme.sceneSecondaryColor)
                .withValues(
                  alpha:
                      .35 +
                      math.sin((progress + index * .13) * math.pi * 2).abs() *
                          .22,
                ),
          );
        }
        break;
      case ThemeMotif.aurora:
        final sky = Rect.fromLTWH(
          board.left,
          board.top,
          board.width,
          board.height * .52,
        );
        _themeAuroraRibbon(
          canvas,
          sky,
          progress,
          theme.scenePrimaryColor.withValues(alpha: .21),
          verticalOffset: .16,
          amplitude: .13,
        );
        _themeAuroraRibbon(
          canvas,
          sky,
          progress + .31,
          theme.sceneSecondaryColor.withValues(alpha: .18),
          verticalOffset: .34,
          amplitude: .16,
        );
        _themeAuroraRibbon(
          canvas,
          sky,
          progress + .67,
          theme.sceneGlowColor.withValues(alpha: .12),
          verticalOffset: .50,
          amplitude: .10,
        );
        _themeMountainRange(
          canvas,
          Rect.fromLTWH(
            board.left,
            board.bottom - board.height * .18,
            board.width,
            board.height * .18,
          ),
          theme.sceneSkyColor.withValues(alpha: .34),
          theme.sceneGlowColor.withValues(alpha: .18),
        );
        for (var index = 0; index < 14; index++) {
          final fall = (index * .091 + progress * (.07 + index % 3 * .014)) % 1;
          final x =
              board.left +
              board.width *
                  ((index * .173 +
                          math.sin(progress * math.pi * 2 + index) * .012) %
                      1);
          final y = board.top + board.height * fall;
          canvas.drawCircle(
            Offset(x, y),
            unit * (.025 + (index % 3) * .012),
            Paint()
              ..color = Colors.white.withValues(
                alpha:
                    .30 +
                    math.sin((progress + index * .07) * math.pi * 2).abs() *
                        .24,
              ),
          );
        }
        break;
      case ThemeMotif.cosmic:
        for (var index = 0; index < 18; index++) {
          final x = board.left + board.width * ((index * .173 + .04) % .94);
          final y = board.top + board.height * ((index * .287 + .08) % .86);
          final twinkle =
              .18 +
              math.sin((progress + index * .097) * math.pi * 2).abs() * .24;
          canvas.drawCircle(
            Offset(x, y),
            unit * (.018 + (index % 3) * .008),
            Paint()
              ..color = (index % 5 == 0 ? theme.sceneGlowColor : Colors.white)
                  .withValues(alpha: twinkle),
          );
        }
        break;
      case ThemeMotif.classic:
        break;
    }
  }

  void _themeLeaf(
    Canvas canvas,
    Offset center,
    double size,
    double rotation,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final leaf = Path()
      ..moveTo(0, -size * .52)
      ..quadraticBezierTo(size * .55, -size * .10, 0, size * .52)
      ..quadraticBezierTo(-size * .55, -size * .10, 0, -size * .52)
      ..close();
    canvas.drawPath(leaf, Paint()..color = color);
    canvas.drawLine(
      Offset(0, -size * .38),
      Offset(0, size * .38),
      Paint()
        ..color = Colors.white.withValues(alpha: .24)
        ..strokeWidth = math.max(1, size * .06),
    );
    canvas.restore();
  }

  void _themePixelSpark(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
  ) {
    final pixel = math.max(1.0, size);
    final paint = Paint()..color = color;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: pixel, height: pixel * 3),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: pixel * 3, height: pixel),
      paint,
    );
  }

  void _themeRetroGrid(
    Canvas canvas,
    Rect bounds,
    Color color,
    double progress,
  ) {
    if (bounds.isEmpty) return;
    final horizon = Offset(bounds.center.dx, bounds.top);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, bounds.shortestSide * .008);
    for (var index = 0; index <= 10; index++) {
      final x = bounds.left + bounds.width * index / 10;
      canvas.drawLine(horizon, Offset(x, bounds.bottom), paint);
    }
    for (var index = 0; index < 8; index++) {
      final phase = (index / 8 + progress * .20) % 1;
      final eased = phase * phase;
      final y = bounds.top + bounds.height * eased;
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
    }
  }

  void _themeAuroraRibbon(
    Canvas canvas,
    Rect bounds,
    double phase,
    Color color, {
    required double verticalOffset,
    required double amplitude,
  }) {
    final wave = math.sin(phase * math.pi * 2);
    final drift = math.cos((phase + .23) * math.pi * 2);
    final y = bounds.top + bounds.height * verticalOffset;
    final height = bounds.height * .13;
    final path = Path()
      ..moveTo(bounds.left, y)
      ..cubicTo(
        bounds.left + bounds.width * .24,
        y + bounds.height * amplitude * wave,
        bounds.left + bounds.width * .38,
        y - bounds.height * amplitude * drift,
        bounds.left + bounds.width * .56,
        y + bounds.height * amplitude * .32,
      )
      ..cubicTo(
        bounds.left + bounds.width * .72,
        y + bounds.height * amplitude * drift,
        bounds.left + bounds.width * .88,
        y - bounds.height * amplitude * wave,
        bounds.right,
        y + bounds.height * amplitude * .12,
      )
      ..lineTo(bounds.right, y + height)
      ..cubicTo(
        bounds.left + bounds.width * .82,
        y + height - bounds.height * amplitude * wave,
        bounds.left + bounds.width * .69,
        y + height + bounds.height * amplitude * drift,
        bounds.left + bounds.width * .53,
        y + height,
      )
      ..cubicTo(
        bounds.left + bounds.width * .34,
        y + height - bounds.height * amplitude * drift,
        bounds.left + bounds.width * .18,
        y + height + bounds.height * amplitude * wave,
        bounds.left,
        y + height,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(path.getBounds()),
    );
  }

  void _themeMountainRange(
    Canvas canvas,
    Rect bounds,
    Color mountainColor,
    Color snowColor,
  ) {
    final mountain = Path()
      ..moveTo(bounds.left, bounds.bottom)
      ..lineTo(bounds.left, bounds.top + bounds.height * .62)
      ..lineTo(
        bounds.left + bounds.width * .14,
        bounds.top + bounds.height * .28,
      )
      ..lineTo(
        bounds.left + bounds.width * .27,
        bounds.top + bounds.height * .66,
      )
      ..lineTo(
        bounds.left + bounds.width * .45,
        bounds.top + bounds.height * .08,
      )
      ..lineTo(
        bounds.left + bounds.width * .62,
        bounds.top + bounds.height * .61,
      )
      ..lineTo(
        bounds.left + bounds.width * .78,
        bounds.top + bounds.height * .24,
      )
      ..lineTo(bounds.right, bounds.top + bounds.height * .66)
      ..lineTo(bounds.right, bounds.bottom)
      ..close();
    canvas.drawPath(mountain, Paint()..color = mountainColor);
    final snow = Path()
      ..moveTo(
        bounds.left + bounds.width * .37,
        bounds.top + bounds.height * .34,
      )
      ..lineTo(
        bounds.left + bounds.width * .45,
        bounds.top + bounds.height * .08,
      )
      ..lineTo(
        bounds.left + bounds.width * .53,
        bounds.top + bounds.height * .33,
      )
      ..lineTo(
        bounds.left + bounds.width * .48,
        bounds.top + bounds.height * .27,
      )
      ..lineTo(
        bounds.left + bounds.width * .45,
        bounds.top + bounds.height * .38,
      )
      ..lineTo(
        bounds.left + bounds.width * .42,
        bounds.top + bounds.height * .26,
      )
      ..close();
    canvas.drawPath(snow, Paint()..color = snowColor);
  }

  void _raisedCell(
    Canvas canvas,
    Rect rect,
    Color color,
    Paint outline, {
    bool strong = false,
  }) {
    final depth = math.max(1.0, rect.shortestSide * (strong ? .10 : .06));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .58, 1],
          colors: [
            Color.lerp(color, Colors.white, strong ? .26 : .15)!,
            color,
            Color.lerp(color, PopColors.navy, strong ? .18 : .08)!,
          ],
        ).createShader(rect),
    );
    canvas.drawLine(
      rect.topLeft + Offset(depth, depth * .45),
      rect.topRight + Offset(-depth, depth * .45),
      Paint()
        ..color = Colors.white.withValues(alpha: strong ? .40 : .26)
        ..strokeWidth = depth * .55,
    );
    canvas.drawLine(
      rect.bottomLeft - Offset(0, depth * .35),
      rect.bottomRight - Offset(0, depth * .35),
      Paint()
        ..color = PopColors.navy.withValues(alpha: strong ? .28 : .14)
        ..strokeWidth = depth * .55,
    );
    canvas.drawRect(rect, outline);
  }

  void _raisedPathCell(Canvas canvas, Path path, Color color, Paint outline) {
    final bounds = path.getBounds();
    final depth = math.max(1.0, bounds.shortestSide * .06);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, .58, 1],
          colors: [
            Color.lerp(color, Colors.white, .15)!,
            color,
            Color.lerp(color, PopColors.navy, .08)!,
          ],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawLine(
      bounds.topLeft + Offset(depth, depth * .45),
      bounds.topRight + Offset(-depth, depth * .45),
      Paint()
        ..color = Colors.white.withValues(alpha: .26)
        ..strokeWidth = depth * .55,
    );
    canvas.drawLine(
      bounds.bottomLeft - Offset(0, depth * .35),
      bounds.bottomRight - Offset(0, depth * .35),
      Paint()
        ..color = PopColors.navy.withValues(alpha: .14)
        ..strokeWidth = depth * .55,
    );
    canvas.restore();
    canvas.drawPath(path, outline);
  }

  void _cosmicCellOverlay(
    Canvas canvas,
    Path shape,
    Rect bounds,
    ThemeVisualSpec theme,
    int seed,
    Paint outline, {
    bool emphasized = false,
  }) {
    final unit = bounds.shortestSide;
    final phase = cubeSpin * math.pi * 2;
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            math.sin(seed * 1.73) * .55,
            math.cos(seed * 1.19) * .55,
          ),
          radius: 1.05,
          colors: [
            theme.scenePrimaryColor.withValues(alpha: emphasized ? .68 : .44),
            theme.sceneSecondaryColor.withValues(alpha: .24),
            theme.sceneGroundColor.withValues(alpha: .74),
          ],
        ).createShader(bounds),
    );
    for (var star = 0; star < 3; star++) {
      final x = ((seed * 37 + star * 29) % 83 + 8) / 100;
      final y = ((seed * 19 + star * 41) % 79 + 10) / 100;
      final twinkle =
          .38 + math.sin(phase + seed * .31 + star * 1.7).abs() * .46;
      canvas.drawCircle(
        Offset(bounds.left + bounds.width * x, bounds.top + bounds.height * y),
        math.max(.7, unit * (star == 0 ? .038 : .025)),
        Paint()
          ..color = (star == 0 ? theme.sceneGlowColor : Colors.white)
              .withValues(alpha: twinkle),
      );
    }
    if (emphasized) {
      canvas.drawCircle(
        bounds.center,
        unit * (.30 + math.sin(phase).abs() * .04),
        Paint()
          ..color = theme.sceneGlowColor.withValues(alpha: .18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .12),
      );
    }
    canvas.restore();
    canvas.drawPath(shape, outline);
  }

  void _base(
    Canvas canvas,
    double cell,
    int col,
    int row,
    Color color,
    PlayerColor playerColor,
    ThemeVisualSpec theme,
    double progress,
  ) {
    final baseRect = Rect.fromLTWH(col * cell, row * cell, 7 * cell, 7 * cell);
    final baseCell = cell;
    canvas.drawRect(
      baseRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .10)!,
            color,
            Color.lerp(color, PopColors.navy, .10)!,
          ],
        ).createShader(baseRect),
    );
    _baseThemeMotif(canvas, baseRect, theme, baseCell, progress);
    final nestCenter = baseRect.center;
    const nestShadowRadius = 2.38;
    const nestRadius = 2.35;
    canvas.drawCircle(
      nestCenter + Offset(0, baseCell * .16),
      baseCell * nestShadowRadius,
      Paint()
        ..color = PopColors.navy.withValues(alpha: .18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseCell * .18),
    );
    canvas.drawCircle(
      nestCenter,
      baseCell * nestRadius,
      Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-.35, -.45),
              radius: 1,
              colors: [
                Colors.white,
                const Color(0xFFFFFDF7),
                Color.lerp(color, Colors.white, .86)!,
              ],
            ).createShader(
              Rect.fromCircle(
                center: nestCenter,
                radius: baseCell * nestRadius,
              ),
            ),
    );
    const nestSlots = [
      Offset(2.5, 2.5),
      Offset(4.5, 2.5),
      Offset(2.5, 4.5),
      Offset(4.5, 4.5),
    ];
    const slotRadius = .48;
    const slotShadowRadius = .50;
    for (final point in nestSlots) {
      final center = Offset(
        baseRect.left + baseRect.width * point.dx / 7,
        baseRect.top + baseRect.height * point.dy / 7,
      );
      canvas.drawCircle(
        center + Offset(0, baseCell * .09),
        baseCell * slotShadowRadius,
        Paint()..color = PopColors.navy.withValues(alpha: .18),
      );
      canvas.drawCircle(
        center,
        baseCell * slotRadius,
        Paint()
          ..shader =
              const RadialGradient(
                center: Alignment(-.35, -.45),
                colors: [Color(0xFFF3F4F6), Color(0xFFC5CAD1)],
              ).createShader(
                Rect.fromCircle(center: center, radius: baseCell * slotRadius),
              ),
      );
      canvas.drawCircle(
        center,
        baseCell * slotRadius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = baseCell * .15,
      );
    }
    final fallback = playerColor == PlayerColor.red
        ? localPlayerLabel
        : playerColor == PlayerColor.blue
        ? 'CPU 3'
        : playerColor == PlayerColor.yellow
        ? 'CPU 2'
        : 'CPU 1';
    final fullLabel = playerColor == PlayerColor.red
        ? localPlayerLabel
        : (playerLabels[playerColor] ?? fallback).toUpperCase();
    _baseLabel(canvas, baseRect, baseCell, row == 0, fullLabel);
  }

  void _baseThemeMotif(
    Canvas canvas,
    Rect base,
    ThemeVisualSpec theme,
    double cell,
    double progress,
  ) {
    if (theme.motif == ThemeMotif.classic) return;
    canvas.save();
    canvas.clipRect(base);
    canvas.drawRect(
      base,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.1),
          radius: .95,
          colors: [
            theme.sceneGlowColor.withValues(alpha: .16),
            Colors.transparent,
          ],
        ).createShader(base),
    );
    switch (theme.motif) {
      case ThemeMotif.neon:
        final skylinePaint = Paint()
          ..color = theme.sceneSkyColor.withValues(alpha: .42);
        for (var index = 0; index < 8; index++) {
          final buildingWidth = base.width / 8;
          final buildingHeight = cell * (.72 + (index % 3) * .32);
          final building = Rect.fromLTWH(
            base.left + index * buildingWidth,
            base.bottom - buildingHeight,
            buildingWidth * .86,
            buildingHeight,
          );
          canvas.drawRect(building, skylinePaint);
          for (var window = 0; window < 3; window++) {
            final lit =
                ((index * 3 + window + (progress * 9).floor()) % 4) != 0;
            canvas.drawRect(
              Rect.fromLTWH(
                building.left + building.width * .22,
                building.top + cell * (.18 + window * .22),
                building.width * .18,
                cell * .07,
              ),
              Paint()
                ..color =
                    (lit ? theme.scenePrimaryColor : theme.sceneSecondaryColor)
                        .withValues(alpha: lit ? .78 : .35),
            );
          }
        }
        final scanX = base.left + base.width * progress;
        canvas.drawRect(
          Rect.fromLTWH(scanX - cell * .10, base.top, cell * .20, base.height),
          Paint()
            ..shader =
                LinearGradient(
                  colors: [
                    Colors.transparent,
                    theme.scenePrimaryColor.withValues(alpha: .56),
                    Colors.transparent,
                  ],
                ).createShader(
                  Rect.fromLTWH(
                    scanX - cell * .10,
                    base.top,
                    cell * .20,
                    base.height,
                  ),
                ),
        );
        final circuit = Paint()
          ..color = theme.frameAccentColor.withValues(alpha: .66)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .08);
        for (final point in const [Offset(.10, .18), Offset(.90, .18)]) {
          final x = base.left + base.width * point.dx;
          final y = base.top + base.height * point.dy;
          canvas.drawLine(Offset(x, y), Offset(base.center.dx, y), circuit);
          canvas.drawCircle(Offset(x, y), cell * .10, circuit);
        }
        break;
      case ThemeMotif.golden:
        canvas.drawCircle(
          Offset(base.right - cell * .72, base.top + cell * .70),
          cell * .36,
          Paint()
            ..color = theme.sceneGlowColor.withValues(
              alpha: .48 + math.sin(progress * math.pi * 2).abs() * .22,
            ),
        );
        for (final point in const [Offset(.15, .24), Offset(.84, .82)]) {
          final center = Offset(
            base.left + base.width * point.dx,
            base.top + base.height * point.dy,
          );
          final pyramid = Path()
            ..moveTo(center.dx, center.dy - cell * .58)
            ..lineTo(center.dx + cell * .70, center.dy + cell * .46)
            ..lineTo(center.dx - cell * .70, center.dy + cell * .46)
            ..close();
          canvas.drawPath(
            pyramid,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  theme.sceneGlowColor.withValues(alpha: .62),
                  theme.sceneSecondaryColor.withValues(alpha: .52),
                ],
              ).createShader(pyramid.getBounds()),
          );
          canvas.drawLine(
            Offset(center.dx, center.dy - cell * .58),
            Offset(center.dx, center.dy + cell * .46),
            Paint()
              ..color = Colors.white.withValues(alpha: .34)
              ..strokeWidth = math.max(1, cell * .055),
          );
        }
        break;
      case ThemeMotif.tropical:
        for (var index = 0; index < 6; index++) {
          final isTop = index < 3;
          final center = Offset(
            base.left + base.width * (.10 + (index % 3) * .40),
            isTop ? base.top + cell * .52 : base.bottom - cell * .50,
          );
          _themeLeaf(
            canvas,
            center,
            cell * .92,
            (isTop ? math.pi : 0) +
                math.sin(progress * math.pi * 2 + index) * .10,
            (index.isEven ? theme.scenePrimaryColor : theme.sceneSecondaryColor)
                .withValues(alpha: .62),
          );
        }
        final river = Path()..moveTo(base.left, base.center.dy);
        for (var step = 0; step <= 14; step++) {
          final x = base.left + base.width * step / 14;
          river.lineTo(
            x,
            base.center.dy +
                math.sin(progress * math.pi * 2 + step * .70) * cell * .18,
          );
        }
        canvas.drawPath(
          river,
          Paint()
            ..color = theme.sceneSecondaryColor.withValues(alpha: .52)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .26
            ..strokeCap = StrokeCap.round,
        );
        break;
      case ThemeMotif.retro:
        final horizon = base.top + base.height * .53;
        final sunsetCenter = Offset(
          base.center.dx,
          base.top + base.height * .30,
        );
        final sunsetRadius = cell * 1.16;
        canvas.save();
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(center: sunsetCenter, radius: sunsetRadius),
          ),
        );
        canvas.drawCircle(
          sunsetCenter,
          sunsetRadius,
          Paint()
            ..shader =
                LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.sceneGlowColor.withValues(alpha: .70),
                    theme.scenePrimaryColor.withValues(alpha: .62),
                  ],
                ).createShader(
                  Rect.fromCircle(center: sunsetCenter, radius: sunsetRadius),
                ),
        );
        for (var stripe = 0; stripe < 6; stripe++) {
          canvas.drawRect(
            Rect.fromLTWH(
              sunsetCenter.dx - sunsetRadius,
              sunsetCenter.dy - sunsetRadius + cell * (.34 + stripe * .34),
              sunsetRadius * 2,
              cell * .11,
            ),
            Paint()..color = theme.sceneSkyColor.withValues(alpha: .72),
          );
        }
        canvas.restore();
        final ridge = Path()
          ..moveTo(base.left, horizon + cell * .12)
          ..lineTo(base.left + base.width * .13, horizon - cell * .28)
          ..lineTo(base.left + base.width * .27, horizon + cell * .10)
          ..lineTo(base.left + base.width * .42, horizon - cell * .52)
          ..lineTo(base.left + base.width * .58, horizon + cell * .08)
          ..lineTo(base.left + base.width * .76, horizon - cell * .34)
          ..lineTo(base.right, horizon + cell * .12)
          ..lineTo(base.right, base.bottom)
          ..lineTo(base.left, base.bottom)
          ..close();
        canvas.drawPath(
          ridge,
          Paint()..color = theme.sceneSkyColor.withValues(alpha: .64),
        );
        _themeRetroGrid(
          canvas,
          Rect.fromLTRB(base.left, horizon, base.right, base.bottom),
          theme.sceneSecondaryColor.withValues(alpha: .62),
          progress,
        );
        for (var index = 0; index < 8; index++) {
          final point = const [
            Offset(.09, .12),
            Offset(.90, .14),
            Offset(.12, .42),
            Offset(.89, .43),
            Offset(.08, .72),
            Offset(.91, .73),
            Offset(.21, .89),
            Offset(.79, .88),
          ][index];
          _themePixelSpark(
            canvas,
            Offset(
              base.left + base.width * point.dx,
              base.top + base.height * point.dy,
            ),
            cell * (.065 + (index % 2) * .025),
            (index.isEven ? theme.scenePrimaryColor : theme.sceneGlowColor)
                .withValues(
                  alpha:
                      .48 +
                      math.sin((progress + index * .17) * math.pi * 2).abs() *
                          .28,
                ),
          );
        }
        final scanY = base.top + base.height * ((progress * 1.12 + .12) % 1);
        canvas.drawRect(
          Rect.fromLTWH(base.left, scanY, base.width, cell * .06),
          Paint()..color = Colors.white.withValues(alpha: .20),
        );
        break;
      case ThemeMotif.aurora:
        _themeAuroraRibbon(
          canvas,
          base,
          progress,
          theme.scenePrimaryColor.withValues(alpha: .64),
          verticalOffset: .18,
          amplitude: .10,
        );
        _themeAuroraRibbon(
          canvas,
          base,
          progress + .29,
          theme.sceneSecondaryColor.withValues(alpha: .54),
          verticalOffset: .34,
          amplitude: .13,
        );
        _themeAuroraRibbon(
          canvas,
          base,
          progress + .63,
          theme.sceneGlowColor.withValues(alpha: .30),
          verticalOffset: .49,
          amplitude: .08,
        );
        _themeMountainRange(
          canvas,
          Rect.fromLTWH(
            base.left,
            base.bottom - base.height * .36,
            base.width,
            base.height * .36,
          ),
          theme.sceneSkyColor.withValues(alpha: .76),
          Colors.white.withValues(alpha: .54),
        );
        for (var index = 0; index < 16; index++) {
          final fall =
              (index * .083 + progress * (.06 + (index % 4) * .012)) % 1;
          final drift =
              math.sin(progress * math.pi * 2 + index * .73) * cell * .12;
          canvas.drawCircle(
            Offset(
              base.left + base.width * ((index * .147 + .05) % 1) + drift,
              base.top + base.height * fall,
            ),
            cell * (.025 + (index % 3) * .014),
            Paint()
              ..color = Colors.white.withValues(
                alpha:
                    .34 +
                    math.sin((progress + index * .09) * math.pi * 2).abs() *
                        .32,
              ),
          );
        }
        break;
      case ThemeMotif.cosmic:
        canvas.drawRect(
          base,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-.22, .08),
              radius: 1.08,
              colors: [
                theme.scenePrimaryColor.withValues(alpha: .82),
                theme.sceneSecondaryColor.withValues(alpha: .36),
                theme.sceneGroundColor.withValues(alpha: .94),
              ],
            ).createShader(base),
        );
        for (var index = 0; index < 13; index++) {
          final x = base.left + base.width * ((index * .223 + .07) % .90);
          final y = base.top + base.height * ((index * .371 + .08) % .84);
          final twinkle =
              .38 +
              math.sin((progress + index * .113) * math.pi * 2).abs() * .42;
          canvas.drawCircle(
            Offset(x, y),
            cell * (.026 + (index % 3) * .014),
            Paint()
              ..color = (index % 4 == 0 ? theme.sceneGlowColor : Colors.white)
                  .withValues(alpha: twinkle),
          );
        }
        final orbitCenter = base.center;
        final orbitAngle = progress * math.pi * 2;
        for (var orbit = 0; orbit < 3; orbit++) {
          canvas.save();
          canvas.translate(orbitCenter.dx, orbitCenter.dy);
          canvas.rotate(orbitAngle * (orbit.isEven ? 1 : -1) + orbit * .72);
          canvas.translate(-orbitCenter.dx, -orbitCenter.dy);
          final orbitRect = Rect.fromCenter(
            center: orbitCenter,
            width: cell * (4.15 + orbit * .24),
            height: cell * (3.62 + orbit * .22),
          );
          canvas.drawArc(
            orbitRect,
            orbit * .83,
            math.pi * (1.04 + orbit * .08),
            false,
            Paint()
              ..color =
                  (orbit == 1
                          ? theme.sceneSecondaryColor
                          : theme.sceneGlowColor)
                      .withValues(alpha: orbit == 1 ? .46 : .66)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, cell * (orbit == 0 ? .10 : .065))
              ..strokeCap = StrokeCap.round,
          );
          canvas.restore();
        }
        canvas.drawCircle(
          orbitCenter,
          cell * (2.18 + math.sin(orbitAngle).abs() * .05),
          Paint()
            ..color = theme.scenePrimaryColor.withValues(alpha: .26)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .12
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .08),
        );
        break;
      case ThemeMotif.classic:
        break;
    }
    canvas.restore();
  }

  void _baseLabel(
    Canvas canvas,
    Rect baseRect,
    double baseCell,
    bool top,
    String label,
  ) {
    TextPainter buildPainter(double fontSize) => TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final maxWidth = baseRect.width * .90;
    final preferredFontSize = baseCell * (compactPhone ? .76 : .70);
    var text = buildPainter(preferredFontSize);
    if (text.width > maxWidth) {
      text = buildPainter(preferredFontSize * maxWidth / text.width);
    }
    final center = Offset(
      baseRect.center.dx,
      top ? baseRect.top + baseCell * .70 : baseRect.bottom - baseCell * .70,
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  void _center(
    Canvas canvas,
    double cell,
    Map<PlayerColor, String?> playerThemeIds,
    double progress,
  ) {
    // The four goal triangles meet at the same point, but each one still
    // belongs to a different player. Clip every theme layer to its owner's
    // triangle so selecting a board never repaints somebody else's goal.
    for (final owner in const [
      PlayerColor.blue,
      PlayerColor.yellow,
      PlayerColor.green,
      PlayerColor.red,
    ]) {
      canvas.save();
      canvas.clipPath(_boardGoalPath(owner, cell));
      _centerThemeLayer(
        canvas,
        cell,
        boardCenterThemeForPlayerThemeIds(playerThemeIds, owner),
        progress,
      );
      canvas.restore();
    }

    final center = Offset(10 * cell, 10 * cell);
    final centerRect = Rect.fromLTWH(8 * cell, 8 * cell, 4 * cell, 4 * cell);
    final border = Paint()
      ..color = PopColors.navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * .06;
    canvas.drawRect(centerRect, border);
    canvas.drawLine(Offset(8 * cell, 8 * cell), center, border);
    canvas.drawLine(Offset(12 * cell, 8 * cell), center, border);
    canvas.drawLine(Offset(12 * cell, 12 * cell), center, border);
    canvas.drawLine(Offset(8 * cell, 12 * cell), center, border);
  }

  void _centerThemeLayer(
    Canvas canvas,
    double cell,
    ThemeVisualSpec theme,
    double progress,
  ) {
    final center = Offset(10 * cell, 10 * cell);
    final top = Path()
      ..moveTo(8 * cell, 8 * cell)
      ..lineTo(12 * cell, 8 * cell)
      ..lineTo(center.dx, center.dy)
      ..close();
    final right = Path()
      ..moveTo(12 * cell, 8 * cell)
      ..lineTo(12 * cell, 12 * cell)
      ..lineTo(center.dx, center.dy)
      ..close();
    final bottom = Path()
      ..moveTo(12 * cell, 12 * cell)
      ..lineTo(8 * cell, 12 * cell)
      ..lineTo(center.dx, center.dy)
      ..close();
    final left = Path()
      ..moveTo(8 * cell, 12 * cell)
      ..lineTo(8 * cell, 8 * cell)
      ..lineTo(center.dx, center.dy)
      ..close();
    final centerRect = Rect.fromLTWH(8 * cell, 8 * cell, 4 * cell, 4 * cell);
    Color facetColor(Color teamColor, Color themeColor) =>
        theme.motif == ThemeMotif.classic
        ? teamColor
        : Color.lerp(teamColor, themeColor, .56)!;
    Paint depthPaint(Color color) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(
            color,
            theme.motif == ThemeMotif.classic
                ? Colors.white
                : theme.sceneGlowColor,
            .28,
          )!,
          color,
          Color.lerp(
            color,
            theme.motif == ThemeMotif.classic
                ? PopColors.navy
                : theme.sceneGroundColor,
            .24,
          )!,
        ],
      ).createShader(centerRect);
    canvas.drawPath(
      top,
      depthPaint(facetColor(PopColors.blue, theme.scenePrimaryColor)),
    );
    canvas.drawPath(
      right,
      depthPaint(facetColor(PopColors.yellow, theme.sceneSecondaryColor)),
    );
    canvas.drawPath(
      bottom,
      depthPaint(facetColor(PopColors.green, theme.scenePrimaryColor)),
    );
    canvas.drawPath(
      left,
      depthPaint(facetColor(PopColors.red, theme.sceneSecondaryColor)),
    );
    if (theme.motif == ThemeMotif.classic) return;
    canvas.drawRect(
      centerRect.deflate(cell * .07),
      Paint()
        ..color = theme.frameAccentColor.withValues(alpha: .62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * .045,
    );
    canvas.drawCircle(
      center,
      cell * .58,
      Paint()
        ..color = theme.sceneGlowColor.withValues(
          alpha: .22 + math.sin(progress * math.pi * 2).abs() * .12,
        ),
    );
    canvas.drawCircle(
      center,
      cell * .48,
      Paint()..color = PopColors.navy.withValues(alpha: .54),
    );
    switch (theme.motif) {
      case ThemeMotif.neon:
        final diamond = Path()
          ..moveTo(center.dx, center.dy - cell * .31)
          ..lineTo(center.dx + cell * .31, center.dy)
          ..lineTo(center.dx, center.dy + cell * .31)
          ..lineTo(center.dx - cell * .31, center.dy)
          ..close();
        canvas.drawPath(
          diamond,
          Paint()
            ..color = theme.scenePrimaryColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .10,
        );
        canvas.drawCircle(
          center,
          cell * .09,
          Paint()..color = theme.sceneSecondaryColor,
        );
        break;
      case ThemeMotif.golden:
        final pyramid = Path()
          ..moveTo(center.dx, center.dy - cell * .30)
          ..lineTo(center.dx + cell * .34, center.dy + cell * .25)
          ..lineTo(center.dx - cell * .34, center.dy + cell * .25)
          ..close();
        canvas.drawPath(
          pyramid,
          Paint()..color = theme.sceneGlowColor.withValues(alpha: .94),
        );
        break;
      case ThemeMotif.tropical:
        _themeLeaf(
          canvas,
          center,
          cell * .66,
          progress * math.pi * .20,
          theme.scenePrimaryColor.withValues(alpha: .96),
        );
        break;
      case ThemeMotif.retro:
        _themePixelSpark(canvas, center, cell * .11, theme.sceneGlowColor);
        canvas.drawRect(
          Rect.fromCenter(
            center: center + Offset(0, cell * .30),
            width: cell * .64,
            height: cell * .055,
          ),
          Paint()..color = theme.sceneSecondaryColor.withValues(alpha: .88),
        );
        for (final dx in const [-.22, 0.0, .22]) {
          canvas.drawLine(
            center + Offset(0, cell * .30),
            center + Offset(cell * dx, cell * .42),
            Paint()
              ..color = theme.scenePrimaryColor.withValues(alpha: .84)
              ..strokeWidth = math.max(1, cell * .045),
          );
        }
        break;
      case ThemeMotif.aurora:
        canvas.save();
        canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: cell * .43)),
        );
        _themeAuroraRibbon(
          canvas,
          Rect.fromCircle(center: center, radius: cell * .43),
          progress,
          theme.scenePrimaryColor.withValues(alpha: .96),
          verticalOffset: .16,
          amplitude: .11,
        );
        _themeAuroraRibbon(
          canvas,
          Rect.fromCircle(center: center, radius: cell * .43),
          progress + .38,
          theme.sceneSecondaryColor.withValues(alpha: .88),
          verticalOffset: .40,
          amplitude: .12,
        );
        _themeMountainRange(
          canvas,
          Rect.fromLTWH(
            center.dx - cell * .43,
            center.dy + cell * .05,
            cell * .86,
            cell * .38,
          ),
          theme.sceneSkyColor.withValues(alpha: .98),
          Colors.white.withValues(alpha: .82),
        );
        canvas.restore();
        break;
      case ThemeMotif.cosmic:
        canvas.drawCircle(
          center,
          cell * .34,
          Paint()
            ..shader = RadialGradient(
              colors: [
                theme.sceneGlowColor,
                theme.scenePrimaryColor,
                theme.sceneGroundColor,
              ],
            ).createShader(Rect.fromCircle(center: center, radius: cell * .34)),
        );
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(progress * math.pi * 2);
        canvas.translate(-center.dx, -center.dy);
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: cell * .70,
            height: cell * .28,
          ),
          Paint()
            ..color = Colors.white.withValues(alpha: .82)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .055,
        );
        canvas.restore();
        break;
      case ThemeMotif.classic:
        break;
    }
  }

  void _safe(
    Canvas canvas,
    double cell,
    Offset center, {
    ThemeVisualSpec theme = defaultThemeVisualSpec,
  }) {
    final cosmic = theme.motif == ThemeMotif.cosmic;
    final starSize = cell * (compactPhone ? .92 : .86);
    if (cosmic) {
      canvas.drawCircle(
        center,
        cell * (.46 + math.sin(cubeSpin * math.pi * 2).abs() * .035),
        Paint()
          ..color = theme.sceneGlowColor.withValues(alpha: .34)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .12),
      );
      canvas.drawCircle(
        center,
        cell * .42,
        Paint()
          ..color = theme.scenePrimaryColor.withValues(alpha: .48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .07),
      );
    }
    final shadow = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          color: (cosmic ? theme.sceneGlowColor : PopColors.navy).withValues(
            alpha: cosmic ? .48 : .24,
          ),
          fontSize: starSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    shadow.paint(
      canvas,
      center -
          Offset(shadow.width / 2, shadow.height / 2) +
          Offset(0, cell * .08),
    );
    final text = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          color: Colors.white,
          fontSize: starSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  void _number(
    Canvas canvas,
    double cell,
    Offset center,
    int number, {
    Color? color,
  }) {
    final text = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: color ?? const Color(0xFF252A32),
          fontSize: cell * (compactPhone ? .46 : .40),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  void _item(Canvas canvas, double cell, Offset center, int itemIndex) {
    final phase = cubeSpin * math.pi * 2 + itemIndex * .83;
    final floatingCenter =
        center +
        Offset(math.cos(phase) * cell * .05, math.sin(phase * 2) * cell * .12);
    final radius = cell * .36;
    final depthVector = Offset(
      math.cos(phase * .72) * cell * .17,
      -cell * (.13 + math.sin(phase) * .035),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, cell * .39),
        width: cell * (.72 + math.sin(phase).abs() * .12),
        height: cell * .19,
      ),
      Paint()
        ..color = PopColors.navy.withValues(alpha: .24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .10),
    );

    List<Offset> triangle(Offset origin) => List.generate(3, (index) {
      final angle = phase - math.pi / 2 + index * math.pi * 2 / 3;
      return origin + Offset(math.cos(angle), math.sin(angle)) * radius;
    });

    Path polygon(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    final front = triangle(floatingCenter);
    final back = front.map((point) => point + depthVector).toList();
    canvas.drawPath(
      polygon(back),
      Paint()..color = Color.lerp(PopColors.yellow, PopColors.navy, .34)!,
    );

    final sides = <({Path path, double depth, Color color})>[];
    final sideColors = [
      Color.lerp(PopColors.blue, PopColors.navy, .12)!,
      Color.lerp(PopColors.red, PopColors.navy, .08)!,
      Color.lerp(PopColors.yellow, PopColors.navy, .24)!,
    ];
    for (var index = 0; index < 3; index++) {
      final next = (index + 1) % 3;
      sides.add((
        path: polygon([back[index], back[next], front[next], front[index]]),
        depth: (front[index].dy + front[next].dy) / 2,
        color: sideColors[index],
      ));
    }
    sides.sort((a, b) => a.depth.compareTo(b.depth));
    for (final side in sides) {
      canvas.drawPath(side.path, Paint()..color = side.color);
      canvas.drawPath(
        side.path,
        Paint()
          ..color = Colors.white.withValues(alpha: .48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.7, cell * .045),
      );
    }

    final frontPath = polygon(front);
    canvas.drawPath(
      frontPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(PopColors.yellow, Colors.white, .48)!,
            PopColors.yellow,
            Color.lerp(PopColors.yellow, PopColors.red, .22)!,
          ],
        ).createShader(frontPath.getBounds()),
    );
    canvas.drawPath(
      frontPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, cell * .06),
    );

    final highlightStart = Offset.lerp(front[0], front[1], .18)!;
    final highlightEnd = Offset.lerp(front[0], front[1], .55)!;
    canvas.drawLine(
      highlightStart,
      highlightEnd,
      Paint()
        ..color = Colors.white.withValues(alpha: .90)
        ..strokeWidth = math.max(1, cell * .08)
        ..strokeCap = StrokeCap.round,
    );

    final sparkle =
        center + Offset(math.cos(phase), math.sin(phase) * .62) * (cell * .58);
    canvas.drawCircle(
      sparkle,
      cell * .075,
      Paint()
        ..color = Colors.white.withValues(alpha: .92)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .035),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: cell * .54),
      phase - .75,
      .58,
      false,
      Paint()
        ..color = PopColors.yellow.withValues(alpha: .48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, cell * .045),
    );
  }

  void _trap(Canvas canvas, double cell, Offset center, BoardTrap trap) {
    final angle = cubeSpin * math.pi * 2;
    final ownerColor = trapOwnerColor(trap);
    final color = revealAllTraps ? ownerColor : _powerColor(trap.type);
    final radius = cell * (.31 + math.sin(angle * 2) * .025);
    if (revealAllTraps) {
      final cellRect = Rect.fromCenter(
        center: center,
        width: cell * .92,
        height: cell * .92,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, Radius.circular(cell * .12)),
        Paint()..color = ownerColor.withValues(alpha: .30),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cellRect, Radius.circular(cell * .12)),
        Paint()
          ..color = ownerColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, cell * .10),
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, cell * .24),
        width: cell * .70,
        height: cell * .22,
      ),
      Paint()
        ..color = PopColors.navy.withValues(alpha: .24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .08),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.sin(angle) * .12);
    final diamond = Path()
      ..moveTo(0, -radius)
      ..lineTo(radius, 0)
      ..lineTo(0, radius)
      ..lineTo(-radius, 0)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, .30)!,
            color,
            Color.lerp(color, PopColors.navy, .24)!,
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawPath(
      diamond,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * .06,
    );
    final symbol = switch (trap.type) {
      PowerUp.glueTrap => '⏸',
      PowerUp.setbackTrap => '↶',
      PowerUp.prisonTrap => '☠',
      PowerUp.bomb => '✹',
      _ => '!',
    };
    final text = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          color: Colors.white,
          fontSize: cell * .42,
          fontWeight: FontWeight.w900,
          height: 1,
          shadows: const [
            Shadow(
              color: Color(0x8017284D),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  void _effect(Canvas canvas, double cell, Offset center, PowerUp? type) {
    if (effectProgress <= 0 || effectProgress >= 1) return;
    final color = _effectColor(engine.effectKind, type);
    final eased = Curves.easeOutCubic.transform(effectProgress);
    final alpha = (1 - effectProgress).clamp(0.0, 1.0).toDouble();
    for (var ring = 0; ring < 3; ring++) {
      canvas.drawCircle(
        center,
        cell * (.42 + eased * (1.10 + ring * .34)),
        Paint()
          ..color = color.withValues(alpha: alpha * (.78 - ring * .19))
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (.15 - ring * .032),
      );
    }
    _boardEventAccents(canvas, cell, center, color, eased, alpha);

    final (symbol, sourceLabel) = _effectPresentation(engine.effectKind, type);
    final label = translateForLanguage(sourceLabel, languageCode);
    final burstPulse = math
        .sin(effectProgress * math.pi)
        .clamp(0.0, 1.0)
        .toDouble();
    final burstScale = .74 + burstPulse * .26;
    final burstRadius = cell * .72 * burstScale;
    final burst = Path();
    for (var point = 0; point < 20; point++) {
      final angle = -math.pi / 2 + point * math.pi / 10;
      final radius = point.isEven ? burstRadius : burstRadius * .68;
      final offset = Offset(math.cos(angle), math.sin(angle)) * radius;
      if (point == 0) {
        burst.moveTo(center.dx + offset.dx, center.dy + offset.dy);
      } else {
        burst.lineTo(center.dx + offset.dx, center.dy + offset.dy);
      }
    }
    burst.close();
    canvas.drawPath(
      burst,
      Paint()
        ..color = color.withValues(alpha: alpha * .88)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .025),
    );
    canvas.drawCircle(
      center,
      cell * .45 * burstScale,
      Paint()..color = Colors.white.withValues(alpha: alpha * .96),
    );
    final symbolPainter = TextPainter(
      text: TextSpan(
        text: symbol,
        style: TextStyle(
          color: color,
          fontSize: cell * .62,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (engine.effectKind == PowerEffectKind.departure) {
      final direction =
          GameEngine.departureArrowDirection[engine.effectOwner] ??
          const Offset(1, 0);
      canvas.rotate(math.atan2(direction.dy, direction.dx));
    }
    symbolPainter.paint(
      canvas,
      Offset(-symbolPainter.width / 2, -symbolPainter.height / 2),
    );
    canvas.restore();

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: cell * .32,
          fontWeight: FontWeight.w900,
          letterSpacing: cell * .012,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: cell * 6.4);
    final labelWidth = labelPainter.width + cell * .58;
    final labelHeight = labelPainter.height + cell * .30;
    final boardWidth = cell * grid;
    var labelLeft = center.dx - labelWidth / 2;
    labelLeft = labelLeft
        .clamp(cell * .10, boardWidth - labelWidth - cell * .10)
        .toDouble();
    var labelTop = center.dy - cell * 1.42;
    if (labelTop < cell * .10) {
      labelTop = center.dy + cell * .72;
    }
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
      Radius.circular(cell * .28),
    );
    canvas.drawRRect(
      labelRect.shift(Offset(0, cell * .08)),
      Paint()..color = PopColors.navy.withValues(alpha: alpha * .25),
    );
    canvas.drawRRect(
      labelRect,
      Paint()..color = PopColors.navy.withValues(alpha: alpha * .94),
    );
    canvas.drawRRect(
      labelRect,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .055),
    );
    labelPainter.paint(
      canvas,
      Offset(
        labelLeft + (labelWidth - labelPainter.width) / 2,
        labelTop + (labelHeight - labelPainter.height) / 2,
      ),
    );
  }

  void _boardEventAccents(
    Canvas canvas,
    double cell,
    Offset center,
    Color color,
    double eased,
    double alpha,
  ) {
    switch (engine.effectKind) {
      case PowerEffectKind.capture || PowerEffectKind.departureCapture:
        for (var ray = 0; ray < 10; ray++) {
          final angle = -math.pi / 2 + ray * math.pi / 5 + effectProgress * .32;
          final direction = Offset(math.cos(angle), math.sin(angle));
          final inner = center + direction * cell * (.66 + eased * .18);
          final outer =
              center +
              direction * cell * (1.02 + eased * (ray.isEven ? .72 : .46));
          canvas.drawLine(
            inner,
            outer,
            Paint()
              ..color = (ray.isEven ? Colors.white : color).withValues(
                alpha: alpha * .90,
              )
              ..strokeWidth = cell * (ray.isEven ? .12 : .075)
              ..strokeCap = StrokeCap.round,
          );
        }
      case PowerEffectKind.departure:
        final direction =
            GameEngine.departureArrowDirection[engine.effectOwner] ??
            const Offset(1, 0);
        final perpendicular = Offset(-direction.dy, direction.dx);
        for (var streak = 0; streak < 4; streak++) {
          final phase = (effectProgress + streak * .18) % 1;
          final position = center + direction * cell * (-1.05 + phase * 2.15);
          final width = cell * (.34 + streak * .035);
          final tip = position + direction * cell * .16;
          final back = position - direction * cell * .12;
          final chevron = Path()
            ..moveTo(
              back.dx + perpendicular.dx * width,
              back.dy + perpendicular.dy * width,
            )
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(
              back.dx - perpendicular.dx * width,
              back.dy - perpendicular.dy * width,
            );
          canvas.drawPath(
            chevron,
            Paint()
              ..color = (streak.isEven ? Colors.white : color).withValues(
                alpha: alpha * (1 - phase) * .90,
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * .10
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      case PowerEffectKind.goal:
        for (var piece = 0; piece < 14; piece++) {
          final angle = -math.pi / 2 + piece * math.pi * 2 / 14;
          final distance = cell * (.58 + eased * (.75 + (piece % 3) * .16));
          final position =
              center + Offset(math.cos(angle), math.sin(angle)) * distance;
          final size = cell * (piece.isEven ? .16 : .11);
          canvas.save();
          canvas.translate(position.dx, position.dy);
          canvas.rotate(angle + effectProgress * math.pi);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset.zero,
                width: size,
                height: size * 1.8,
              ),
              Radius.circular(size * .25),
            ),
            Paint()
              ..color = (piece % 3 == 0 ? Colors.white : color).withValues(
                alpha: alpha * .95,
              ),
          );
          canvas.restore();
        }
      case PowerEffectKind.pickup ||
          PowerEffectKind.armed ||
          PowerEffectKind.triggered ||
          PowerEffectKind.blocked ||
          PowerEffectKind.activated ||
          null:
        return;
    }
  }

  (String, String) _effectPresentation(PowerEffectKind? kind, PowerUp? type) {
    if (kind == PowerEffectKind.departure) {
      return ('➜', '¡SALIDA!');
    }
    if (kind == PowerEffectKind.capture) {
      return ('✕', '¡CAPTURA!');
    }
    if (kind == PowerEffectKind.departureCapture) {
      return ('✹', '¡SALIDA + CAPTURA!');
    }
    if (kind == PowerEffectKind.goal) {
      return ('★', '¡FICHA EN META!');
    }
    if (kind == PowerEffectKind.pickup) {
      return switch (type) {
        PowerUp.shield => ('◆', 'ESCUDO CONSEGUIDO'),
        PowerUp.boost => ('➜', 'TURBO CONSEGUIDO'),
        PowerUp.glueTrap ||
        PowerUp.setbackTrap ||
        PowerUp.prisonTrap ||
        PowerUp.bomb => ('◇', 'TRAMPA ARMADA'),
        null => ('?', '¡SORPRESA!'),
      };
    }
    if (kind == PowerEffectKind.armed) {
      return ('◇', 'TRAMPA ARMADA');
    }
    if (kind == PowerEffectKind.blocked) {
      return ('◆', 'ESCUDO BLOQUEÓ');
    }
    if (kind == PowerEffectKind.activated) {
      return switch (type) {
        PowerUp.shield => ('◆', 'ESCUDO ACTIVADO'),
        PowerUp.boost => ('➜', 'TURBO +3'),
        _ => ('✦', 'PODER ACTIVADO'),
      };
    }
    return switch (type) {
      PowerUp.glueTrap => ('Ⅱ', 'PEGAMENTO · TURNO PERDIDO'),
      PowerUp.setbackTrap => ('↶', 'RETROCESO'),
      PowerUp.prisonTrap => ('▦', '¡A LA CÁRCEL!'),
      PowerUp.bomb => ('✹', '¡BOMBA!'),
      PowerUp.shield => ('◆', 'ESCUDO'),
      PowerUp.boost => ('➜', 'TURBO +3'),
      null => ('?', '¡SORPRESA!'),
    };
  }

  Color _effectColor(PowerEffectKind? kind, PowerUp? type) {
    if (kind == PowerEffectKind.capture ||
        kind == PowerEffectKind.departureCapture) {
      return const Color(0xFFFF6B35);
    }
    if (kind == PowerEffectKind.departure) {
      return engine.effectOwner == null
          ? PopColors.green
          : _playerColor(engine.effectOwner!);
    }
    if (kind == PowerEffectKind.goal) {
      final ownerColor = engine.effectOwner == null
          ? PopColors.yellow
          : _playerColor(engine.effectOwner!);
      return Color.lerp(ownerColor, PopColors.yellow, .58)!;
    }
    return _powerColor(type);
  }

  Color _powerColor(PowerUp? type) => switch (type) {
    PowerUp.glueTrap => const Color(0xFF7B61FF),
    PowerUp.setbackTrap => PopColors.yellow,
    PowerUp.prisonTrap || PowerUp.bomb => PopColors.red,
    PowerUp.shield => PopColors.blue,
    PowerUp.boost => PopColors.green,
    null => PopColors.yellow,
  };

  Rect _trackRect(Offset center, double cell) {
    return _boardTrackRect(center, cell);
  }

  Rect _homeRect(PlayerColor color, Offset center, double cell) {
    return _boardHomeRect(color, center, cell);
  }

  Path _movePreviewPath(MoveDestinationPreview preview, double cell) {
    return _moveDestinationPath(preview, cell);
  }

  Path _homeEntryCapturePath(MoveDestinationPreview preview, double cell) {
    final index = GameEngine.homeEntryOffset[preview.owner]!;
    return _transitionTrackPath(index, cell) ??
        (Path()..addRect(_trackRect(GameEngine.loop[index], cell)));
  }

  void _moveDestinationHighlights(Canvas canvas, double cell) {
    final wave = Curves.easeInOut.transform(pulse);
    for (final preview in movePreviews) {
      final path = _movePreviewPath(preview, cell);
      canvas.drawPath(
        path,
        Paint()..color = preview.color.withValues(alpha: .10 + wave * .10),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = preview.color.withValues(alpha: .34 + wave * .22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (.18 + wave * .07)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .11),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: .88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .16,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = preview.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (.085 + wave * .035),
      );
      if (preview.captureCell != null) {
        final capturePath = _homeEntryCapturePath(preview, cell);
        canvas.drawPath(
          capturePath,
          Paint()..color = PopColors.red.withValues(alpha: .15 + wave * .15),
        );
        canvas.drawPath(
          capturePath,
          Paint()
            ..color = PopColors.red.withValues(alpha: .65 + wave * .25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * (.11 + wave * .05)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .08),
        );
      }
    }
  }

  void _moveDestinationBadge(
    Canvas canvas,
    double cell, {
    required Offset center,
    required Color color,
    required String label,
    required double wave,
    double scale = 1,
  }) {
    final radius = cell * (.28 + wave * .025) * scale;
    canvas.drawCircle(
      center + Offset(0, cell * .07 * scale),
      radius * 1.20,
      Paint()
        ..color = PopColors.navy.withValues(alpha: .20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * .08),
    );
    canvas.drawCircle(center, radius * 1.18, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.35, -.45),
          colors: [
            Color.lerp(color, Colors.white, .22)!,
            color,
            Color.lerp(color, PopColors.navy, .18)!,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: cell * (label.length > 1 ? .26 : .34) * scale,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  Offset _moveDestinationBadgeCenter(
    MoveDestinationPreview preview,
    double cell,
  ) {
    if (!preview.overview) return preview.cell * cell;
    final peers = movePreviews
        .where(
          (candidate) => candidate.overview && candidate.cell == preview.cell,
        )
        .toList();
    if (peers.length <= 1) return preview.cell * cell;
    final index = peers.indexOf(preview);
    final offsets = switch (peers.length) {
      2 => const [Offset(-.25, 0), Offset(.25, 0)],
      3 => const [Offset(0, -.25), Offset(-.24, .20), Offset(.24, .20)],
      _ => const [
        Offset(-.23, -.20),
        Offset(.23, -.20),
        Offset(-.23, .20),
        Offset(.23, .20),
      ],
    };
    return preview.cell * cell + offsets[index] * cell;
  }

  void _moveDestinationBadges(Canvas canvas, double cell) {
    final wave = Curves.easeInOut.transform(pulse);
    for (final preview in movePreviews) {
      final label = preview.overview
          ? 'F${preview.token.id + 1}'
          : preview.isExit
          ? 'S'
          : preview.usesAllDice
          ? 'Σ${preview.value}'
          : '${preview.value}';
      _moveDestinationBadge(
        canvas,
        cell,
        center: _moveDestinationBadgeCenter(preview, cell),
        color: preview.color,
        label: label,
        wave: wave,
        scale: preview.overview ? .88 : 1,
      );
      if (preview.captureCell case final captureCell?) {
        _moveDestinationBadge(
          canvas,
          cell,
          center: captureCell * cell,
          color: PopColors.red,
          label: 'X',
          wave: wave,
          scale: .72,
        );
      }
    }
  }

  void _tokens(Canvas canvas, double cell) {
    final displayCells = _displayTokenCells(engine, compactPhone: compactPhone);
    final captureTargets = movePreviews
        .map((preview) => preview.captureTarget)
        .whereType<GameToken>()
        .toSet();
    final tokenRadiusScale = compactPhone ? .47 : .43;
    final tokenShadowScale = compactPhone ? .47 : .44;
    final tokenGlowScale = compactPhone ? .51 : .48;
    final twentyStepGuideActive =
        engine.currentPlayer.isHuman &&
        engine.hasRolled &&
        !engine.effectResolving &&
        !engine.gameOver &&
        engine.remainingDice.contains(20);
    for (final player in engine.players) {
      final color = _playerColor(player.color);
      final legacyRobot =
          robotTokenColors.contains(player.color) ||
          (robotTokens && player.color == PlayerColor.red);
      final tokenStyle = tokenVisualSpecFor(
        tokenStyleIds[player.color] ??
            (legacyRobot ? 'tokens_robot' : 'tokens_default'),
      );
      for (final token in player.tokens) {
        final logicalCenter = animatedCells[token] ?? displayCells[token]!;
        final center = logicalCenter * cell;
        final tokenCell = cell;
        // During a turn, every piece belonging to the active player (including
        // pieces still in the nest) receives a subtle 10% focus scale. Keeping
        // the transform centered preserves its exact board position.
        final activeTurnToken =
            !engine.gameOver && player.color == engine.currentPlayer.color;
        final isCaptureTarget = captureTargets.contains(token);
        if (activeTurnToken) {
          final turnScale = 1.095 + pulse * .01;
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.scale(turnScale);
          canvas.translate(-center.dx, -center.dy);
        }
        if (isCaptureTarget) {
          canvas.drawCircle(
            center,
            tokenCell * (.72 + pulse * .07),
            Paint()
              ..color = PopColors.red.withValues(alpha: .30 - pulse * .10)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokenCell * .14),
          );
          canvas.drawCircle(
            center,
            tokenCell * (.65 + pulse * .03),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .15,
          );
          canvas.drawCircle(
            center,
            tokenCell * (.62 + pulse * .03),
            Paint()
              ..color = PopColors.red
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .09,
          );
        }
        canvas.drawCircle(
          center + Offset(0, tokenCell * .10),
          tokenCell * tokenShadowScale,
          Paint()
            ..color = Colors.black.withValues(alpha: .22)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokenCell * .12),
        );
        if (tokenStyle.motif != TokenMotif.star) {
          canvas.drawCircle(
            center,
            tokenCell * (tokenGlowScale + pulse * .025),
            Paint()
              ..color = tokenStyle.glowColor.withValues(
                alpha: .28 + pulse * .20,
              )
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokenCell * .13),
          );
        }
        final radius = tokenCell * tokenRadiusScale;
        final isSelected = identical(token, selectedToken);
        final canUseTwenty = twentyStepGuideActive && engine.canMove(token, 20);
        final guideColor = _twentyStepGuideColor(token.id);
        if (isSelected) {
          final selectionColor = canUseTwenty
              ? guideColor
              : const Color(0xFF7057FF);
          canvas.drawCircle(
            center,
            tokenCell * (.67 + pulse * .06),
            Paint()
              ..color = selectionColor.withValues(alpha: .28 - pulse * .10)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokenCell * .12),
          );
          canvas.drawCircle(
            center,
            tokenCell * (.60 + pulse * .035),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .18,
          );
          canvas.drawCircle(
            center,
            tokenCell * (.58 + pulse * .035),
            Paint()
              ..color = selectionColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .10,
          );
        } else if (canUseTwenty) {
          canvas.drawCircle(
            center,
            tokenCell * (.65 + pulse * .07),
            Paint()
              ..color = guideColor.withValues(alpha: .25 - pulse * .08)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, tokenCell * .12),
          );
          canvas.drawCircle(
            center,
            tokenCell * (.60 + pulse * .04),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .16,
          );
          canvas.drawCircle(
            center,
            tokenCell * (.58 + pulse * .04),
            Paint()
              ..color = guideColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .10,
          );
        } else if (engine.currentPlayer.isHuman &&
            engine.hasRolled &&
            !engine.effectResolving &&
            (engine.legalDiceFor(token).isNotEmpty ||
                engine.canMoveUsingAllDice(token))) {
          canvas.drawCircle(
            center,
            tokenCell * (.57 + pulse * .09),
            Paint()
              ..color = PopColors.yellow.withValues(alpha: .55 - pulse * .25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .12,
          );
        }
        if (player.shielded) {
          canvas.drawCircle(
            center,
            tokenCell * (tokenGlowScale + pulse * .04),
            Paint()
              ..color = const Color(
                0xFF73D7FF,
              ).withValues(alpha: .62 - pulse * .16)
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .11,
          );
        }
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-.35, -.45),
              radius: .9,
              colors: [
                Color.lerp(color, Colors.white, .35)!,
                color,
                Color.lerp(color, Colors.black, .20)!,
              ],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
        if (tokenStyle.motif == TokenMotif.cosmicCore) {
          // Cosmic pieces use a polished coin-like double rim. The previous
          // thick white ring combined with the closed orbit mark and made the
          // piece read like an eye instead of a round game token.
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = tokenStyle.detailColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .075,
          );
          canvas.drawCircle(
            center,
            radius - tokenCell * .045,
            Paint()
              ..color = tokenStyle.highlightColor.withValues(alpha: .88)
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .020,
          );
        } else {
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = tokenCell * .09,
          );
        }
        _tokenMark(canvas, center, tokenCell, color, tokenStyle);
        if (isCaptureTarget) {
          final badgeCenter =
              center + Offset(tokenCell * .38, -tokenCell * .38);
          final badgeRadius = tokenCell * .22;
          canvas.drawCircle(
            badgeCenter,
            badgeRadius * 1.22,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            badgeCenter,
            badgeRadius,
            Paint()..color = PopColors.red,
          );
          final crossPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = tokenCell * .075
            ..strokeCap = StrokeCap.round;
          final crossArm = tokenCell * .075;
          canvas.drawLine(
            badgeCenter - Offset(crossArm, crossArm),
            badgeCenter + Offset(crossArm, crossArm),
            crossPaint,
          );
          canvas.drawLine(
            badgeCenter + Offset(crossArm, -crossArm),
            badgeCenter + Offset(-crossArm, crossArm),
            crossPaint,
          );
        }
        if (canUseTwenty) {
          final badgeCenter =
              center + Offset(tokenCell * .34, -tokenCell * .34);
          canvas.drawCircle(
            badgeCenter,
            tokenCell * .235,
            Paint()..color = Colors.white,
          );
          canvas.drawCircle(
            badgeCenter,
            tokenCell * .19,
            Paint()..color = guideColor,
          );
          final badge = TextPainter(
            text: TextSpan(
              text: 'F${token.id + 1}',
              style: TextStyle(
                color: Colors.white,
                fontSize: tokenCell * .15,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          badge.paint(
            canvas,
            badgeCenter - Offset(badge.width / 2, badge.height / 2),
          );
        }
        if (activeTurnToken) canvas.restore();
      }
    }
  }

  void _tokenMark(
    Canvas canvas,
    Offset center,
    double cell,
    Color teamColor,
    TokenVisualSpec style,
  ) {
    switch (style.motif) {
      case TokenMotif.star:
        _starTokenMark(canvas, center, cell, style.detailColor);
        break;
      case TokenMotif.robot:
        _robotTokenMark(canvas, center, cell, teamColor);
        break;
      case TokenMotif.crystal:
        final gem = Path()
          ..moveTo(center.dx, center.dy - cell * .27)
          ..lineTo(center.dx + cell * .23, center.dy - cell * .04)
          ..lineTo(center.dx + cell * .11, center.dy + cell * .25)
          ..lineTo(center.dx - cell * .11, center.dy + cell * .25)
          ..lineTo(center.dx - cell * .23, center.dy - cell * .04)
          ..close();
        canvas.drawPath(
          gem.shift(Offset(0, cell * .035)),
          Paint()..color = PopColors.navy.withValues(alpha: .22),
        );
        canvas.drawPath(
          gem,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [style.highlightColor, style.detailColor],
            ).createShader(gem.getBounds()),
        );
        canvas.drawPath(
          gem,
          Paint()
            ..color = style.outlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .045,
        );
        canvas.drawLine(
          center + Offset(-cell * .18, -cell * .03),
          center + Offset(cell * .11, cell * .25),
          Paint()
            ..color = teamColor.withValues(alpha: .48)
            ..strokeWidth = cell * .035,
        );
        canvas.drawLine(
          center + Offset(cell * .18, -cell * .03),
          center + Offset(-cell * .11, cell * .25),
          Paint()
            ..color = teamColor.withValues(alpha: .32)
            ..strokeWidth = cell * .035,
        );
        break;
      case TokenMotif.rocket:
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.pi / 4);
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: cell * .24,
            height: cell * .52,
          ),
          Radius.circular(cell * .14),
        );
        canvas.drawRRect(
          body,
          Paint()
            ..shader = LinearGradient(
              colors: [style.highlightColor, style.detailColor],
            ).createShader(body.outerRect),
        );
        canvas.drawRRect(
          body,
          Paint()
            ..color = style.outlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .035,
        );
        canvas.drawCircle(
          Offset(0, -cell * .08),
          cell * .065,
          Paint()..color = teamColor,
        );
        final fins = Path()
          ..moveTo(-cell * .11, cell * .11)
          ..lineTo(-cell * .23, cell * .25)
          ..lineTo(-cell * .08, cell * .21)
          ..moveTo(cell * .11, cell * .11)
          ..lineTo(cell * .23, cell * .25)
          ..lineTo(cell * .08, cell * .21);
        canvas.drawPath(
          fins,
          Paint()
            ..color = style.highlightColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .065
            ..strokeJoin = StrokeJoin.round,
        );
        final flame = Path()
          ..moveTo(-cell * .065, cell * .28)
          ..quadraticBezierTo(0, cell * .48, cell * .065, cell * .28)
          ..close();
        canvas.drawPath(flame, Paint()..color = const Color(0xFFFF7A28));
        canvas.restore();
        break;
      case TokenMotif.crown:
        final crown = Path()
          ..moveTo(center.dx - cell * .25, center.dy + cell * .16)
          ..lineTo(center.dx - cell * .20, center.dy - cell * .18)
          ..lineTo(center.dx - cell * .06, center.dy - cell * .04)
          ..lineTo(center.dx, center.dy - cell * .25)
          ..lineTo(center.dx + cell * .08, center.dy - cell * .04)
          ..lineTo(center.dx + cell * .23, center.dy - cell * .18)
          ..lineTo(center.dx + cell * .25, center.dy + cell * .16)
          ..close();
        canvas.drawPath(
          crown.shift(Offset(0, cell * .045)),
          Paint()..color = PopColors.navy.withValues(alpha: .24),
        );
        canvas.drawPath(
          crown,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [style.highlightColor, style.detailColor],
            ).createShader(crown.getBounds()),
        );
        canvas.drawPath(
          crown,
          Paint()
            ..color = style.outlineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * .035
            ..strokeJoin = StrokeJoin.round,
        );
        for (final dx in const [-.13, 0.0, .13]) {
          canvas.drawCircle(
            center + Offset(cell * dx, cell * .105),
            cell * .028,
            Paint()..color = teamColor,
          );
        }
        break;
      case TokenMotif.neonPulse:
        _paintNeonPulseTokenMark(canvas, center, cell, style, teamColor);
        break;
      case TokenMotif.solarScarab:
        _paintSolarScarabTokenMark(canvas, center, cell, style, teamColor);
        break;
      case TokenMotif.jungleTotem:
        _paintJungleTotemTokenMark(canvas, center, cell, style, teamColor);
        break;
      case TokenMotif.pixelBlaster:
        _paintPixelBlasterTokenMark(canvas, center, cell, style, teamColor);
        break;
      case TokenMotif.auroraShard:
        _paintAuroraShardTokenMark(canvas, center, cell, style, teamColor);
        break;
      case TokenMotif.cosmicCore:
        _paintCosmicCoreTokenMark(canvas, center, cell, style, teamColor);
        break;
    }
  }

  void _starTokenMark(
    Canvas canvas,
    Offset center,
    double cell,
    Color detailColor,
  ) {
    final star = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(color: detailColor, fontSize: cell * .43),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final starShadow = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          color: PopColors.navy.withValues(alpha: .22),
          fontSize: cell * .43,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    starShadow.paint(
      canvas,
      center -
          Offset(starShadow.width / 2, starShadow.height / 2) +
          Offset(0, cell * .045),
    );
    star.paint(canvas, center - Offset(star.width / 2, star.height / 2));
  }

  void _robotTokenMark(
    Canvas canvas,
    Offset center,
    double cell,
    Color teamColor,
  ) {
    final face = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center + Offset(0, cell * .025),
        width: cell * .48,
        height: cell * .34,
      ),
      Radius.circular(cell * .10),
    );
    canvas.drawRRect(
      face.shift(Offset(0, cell * .035)),
      Paint()..color = PopColors.navy.withValues(alpha: .20),
    );
    canvas.drawLine(
      center + Offset(0, -cell * .17),
      center + Offset(0, -cell * .27),
      Paint()
        ..color = Colors.white
        ..strokeWidth = cell * .055
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center + Offset(0, -cell * .29),
      cell * .055,
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(face, Paint()..color = Colors.white);
    for (final direction in const [-1.0, 1.0]) {
      canvas.drawCircle(
        center + Offset(direction * cell * .115, -cell * .015),
        cell * .045,
        Paint()..color = Color.lerp(teamColor, PopColors.navy, .38)!,
      );
    }
    canvas.drawLine(
      center + Offset(-cell * .105, cell * .105),
      center + Offset(cell * .105, cell * .105),
      Paint()
        ..color = Color.lerp(teamColor, PopColors.navy, .34)!
        ..strokeWidth = cell * .045
        ..strokeCap = StrokeCap.round,
    );
  }

  Color _playerColor(PlayerColor color) => switch (color) {
    PlayerColor.red => PopColors.red,
    PlayerColor.green => PopColors.green,
    PlayerColor.yellow => PopColors.yellow,
    PlayerColor.blue => PopColors.blue,
  };

  @override
  bool shouldRepaint(covariant _ParcheseBoardPainter oldDelegate) => true;
}

class _MobileBoardNavigator extends StatefulWidget {
  const _MobileBoardNavigator({
    required this.boardPainter,
    required this.focus,
    required this.fullBoard,
    required this.onFocusChanged,
    required this.onInteractionEnd,
  });

  final CustomPainter boardPainter;
  final Offset focus;
  final bool fullBoard;
  final ValueChanged<Offset> onFocusChanged;
  final VoidCallback onInteractionEnd;

  @override
  State<_MobileBoardNavigator> createState() => _MobileBoardNavigatorState();
}

class _MobileBoardNavigatorState extends State<_MobileBoardNavigator> {
  int? activePointer;

  @override
  void didUpdateWidget(covariant _MobileBoardNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullBoard && !oldWidget.fullBoard) activePointer = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      final size = Size.square(side);
      final viewport = mobileBoardViewportRectForTesting(
        size: size,
        focus: widget.focus,
        fullBoard: widget.fullBoard,
      ).deflate(3);

      void moveFocus(Offset localPosition) {
        widget.onFocusChanged(
          Offset(
            (localPosition.dx / side).clamp(0.0, 1.0).toDouble(),
            (localPosition.dy / side).clamp(0.0, 1.0).toDouble(),
          ),
        );
      }

      void endInteraction(int pointer) {
        if (activePointer != pointer) return;
        activePointer = null;
        widget.onInteractionEnd();
      }

      final cameraValue = widget.fullBoard
          ? appTranslate(context, 'Tablero completo')
          : appTranslate(context, 'Vista ampliada');
      return Semantics(
        container: true,
        label: appTranslate(context, 'Visor del tablero'),
        value: cameraValue,
        hint: appTranslate(
          context,
          'Mantén el dedo sobre el minimapa para ampliar y arrastra para mover la vista.',
        ),
        child: Listener(
          key: const ValueKey('mobile-board-navigator'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (details) {
            if (activePointer != null) return;
            activePointer = details.pointer;
            moveFocus(details.localPosition);
          },
          onPointerMove: (details) {
            if (activePointer == details.pointer) {
              moveFocus(details.localPosition);
            }
          },
          onPointerUp: (details) => endInteraction(details.pointer),
          onPointerCancel: (details) => endInteraction(details.pointer),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {},
            onPanUpdate: (_) {},
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F6FB),
                    border: Border.all(
                      color: const Color(0xFF7E8BA2),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('mobile-board-miniature'),
                          painter: widget.boardPainter,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: viewport,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey(
                              'mobile-board-navigator-window',
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: const Color(0xFFFFD34F),
                                width: 4,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x8010182B),
                                  blurRadius: 5,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: widget.fullBoard
                                ? null
                                : Center(
                                    child: Transform.rotate(
                                      angle: math.pi / 4,
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFB82E),
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFFE8A1),
                                            width: 2,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x660C162C),
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Transform.rotate(
                                          angle: -math.pi / 4,
                                          child: const Icon(
                                            Icons.open_with_rounded,
                                            color: PopColors.navy,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class GameControlPanel extends StatelessWidget {
  const GameControlPanel({
    super.key,
    required this.engine,
    this.selectedToken,
    this.onDieSelected,
    this.onCancelSelection,
    this.onRollRequested,
    this.rollEnabled = true,
    this.rollGuideEnabled = true,
    this.rollGuideVisible = false,
    this.rollGuidePulseSerial = 0,
    this.diceHandPreference = DiceHandPreference.right,
    this.onShowChat,
    this.onCustomize,
    this.compact = false,
    this.landscapeHud = false,
    this.diceStyleId,
    this.avatarIds = const <PlayerColor, String?>{},
    this.mobileBoardNavigator,
    this.mobileBoardFullView = false,
    this.visibleRemainingDice,
  });
  final GameEngine engine;
  final GameToken? selectedToken;
  final ValueChanged<int>? onDieSelected;
  final VoidCallback? onCancelSelection;
  final VoidCallback? onRollRequested;
  final bool rollEnabled;
  final bool rollGuideEnabled;
  final bool rollGuideVisible;
  final int rollGuidePulseSerial;
  final DiceHandPreference diceHandPreference;
  final VoidCallback? onShowChat;
  final VoidCallback? onCustomize;
  final bool compact;
  final bool landscapeHud;
  final String? diceStyleId;
  final Map<PlayerColor, String?> avatarIds;
  final Widget? mobileBoardNavigator;
  final bool mobileBoardFullView;
  final List<int>? visibleRemainingDice;

  String? get diceId => diceStyleId;
  bool get galaxyDice => diceStyleId == 'dice_galaxy';

  @override
  Widget build(BuildContext context) {
    final diceStyle = diceVisualSpecFor(diceStyleId);
    final activeTraps = engine
        .activeTrapsFor(engine.currentPlayer.color)
        .toList(growable: false);
    final engineMoveChoices = selectedToken == null || engine.effectResolving
        ? const <int>[]
        : engine.legalDieValuesFor(selectedToken!);
    final moveChoices = visibleRemainingDice == null
        ? engineMoveChoices
        : engineMoveChoices
              .where(visibleRemainingDice!.contains)
              .toList(growable: false);
    final allDiceTotal =
        visibleRemainingDice != null ||
            selectedToken == null ||
            engine.effectResolving
        ? null
        : engine.allDiceTotalFor(selectedToken!);
    final boardCalloutsOwnMoveChoice =
        mobileBoardNavigator != null &&
        selectedToken != null &&
        moveChoices.isNotEmpty;
    final bonusTwentyActive =
        engine.currentPlayer.isHuman &&
        engine.hasRolled &&
        !engine.effectResolving &&
        engine.remainingDice.contains(20);
    final phaseLabel = engine.effectResolving
        ? 'Resolviendo el efecto…'
        : selectedToken != null
        ? moveChoices.contains(20)
              ? 'F${selectedToken!.id + 1}: mira dónde cae con +20'
              : selectedToken!.inNest
              ? 'Pulsa SALIDA'
              : allDiceTotal != null
              ? 'Elige un dado o TODOS ($allDiceTotal)'
              : 'Elige cuántos pasos'
        : bonusTwentyActive
        ? 'BONO +20 · Elige una ficha por color'
        : engine.hasRolled
        ? 'Elige una ficha'
        : 'Lanza los dados';
    final trapFeedbackIsOutsidePanel =
        engine.effectResolving &&
        (engine.effectKind == PowerEffectKind.triggered ||
            engine.effectKind == PowerEffectKind.blocked);
    final panelMessage = trapFeedbackIsOutsidePanel
        ? 'Resolviendo la trampa…'
        : engine.message;
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 175 : 230),
          child: _AutoFitSingleLineText(
            engine.currentPlayer.name,
            alignment: Alignment.center,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        if (engine.isChaos && engine.currentPlayer.isHuman) ...[
          const SizedBox(height: 3),
          _PowerSlotBadge(engine: engine, player: engine.currentPlayer),
          const SizedBox(height: 3),
        ],
        PopText(
          phaseLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: bonusTwentyActive ? const Color(0xFFB54A18) : PopColors.red,
            fontWeight: bonusTwentyActive ? FontWeight.w900 : FontWeight.normal,
          ),
        ),
        if (onShowChat != null || onCustomize != null) ...[
          const SizedBox(height: 3),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 3,
            children: [
              if (onShowChat != null)
                _HudMessageButton(onPressed: onShowChat!, compact: true),
              if (onCustomize != null)
                _HudCosmeticsButton(onPressed: onCustomize!, compact: true),
            ],
          ),
        ],
      ],
    );
    final remainingForSlots = <int>[
      ...(visibleRemainingDice ?? engine.remainingDice),
    ];
    final remainingDiceForDisplay =
        visibleRemainingDice ?? engine.remainingDice;
    final dieAvailable = [
      for (final value in engine.dice)
        !engine.hasRolled || remainingForSlots.remove(value),
    ];
    final canRollDice =
        rollEnabled &&
        engine.currentPlayer.isHuman &&
        !engine.hasRolled &&
        !engine.gameOver &&
        !engine.effectResolving;

    void rollDice() {
      if (!canRollDice) return;
      onCancelSelection?.call();
      if (onRollRequested case final request?) {
        request();
      } else {
        engine.roll();
      }
    }

    final dice = Semantics(
      key: const ValueKey('dice-roll-target'),
      container: true,
      button: canRollDice,
      enabled: canRollDice,
      excludeSemantics: canRollDice,
      label: canRollDice
          ? appTranslate(context, 'Toca los dados para lanzar.')
          : null,
      onTap: canRollDice ? rollDice : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canRollDice ? rollDice : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            key: const ValueKey('dice-group'),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(diceStyle.stageColor, Colors.white, .88)!,
                  Color.lerp(diceStyle.stageColor, Colors.white, .62)!,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color.lerp(diceStyle.borderColor, Colors.white, .32)!,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: diceStyle.glowColor.withValues(alpha: .18),
                  blurRadius: 9,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DieSlot(
                      key: const ValueKey('die-slot-0'),
                      slotIndex: 0,
                      value: engine.dice[0],
                      style: diceStyle,
                      animationId: engine.rollSerial,
                      available: dieAvailable[0],
                      selectable:
                          !boardCalloutsOwnMoveChoice &&
                          moveChoices.contains(engine.dice[0]),
                      onTap: onDieSelected,
                    ),
                    const SizedBox(width: 5),
                    _DieSlot(
                      key: const ValueKey('die-slot-1'),
                      slotIndex: 1,
                      value: engine.dice[1],
                      style: diceStyle,
                      animationId: engine.rollSerial,
                      available: dieAvailable[1],
                      selectable:
                          !boardCalloutsOwnMoveChoice &&
                          moveChoices.contains(engine.dice[1]),
                      onTap: onDieSelected,
                    ),
                  ],
                ),
                if (bonusTwentyActive) ...[
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('capture-bonus-20'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFA143), Color(0xFFFF7043)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3DFF7043),
                          blurRadius: 7,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_circle_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        SizedBox(width: 4),
                        PopText(
                          'BONO +20',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (engine.hasRolled) ...[
                  const SizedBox(height: 4),
                  PopText(
                    remainingDiceForDisplay.length == 1
                        ? '1 dado disponible'
                        : '${remainingDiceForDisplay.length} dados disponibles',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final guidedMobileDice = _DiceRollGuideTarget(
      visible: rollGuideEnabled && rollGuideVisible && canRollDice,
      pulseSerial: rollGuidePulseSerial,
      hand: diceHandPreference,
      child: dice,
    );
    final heldPower = engine.currentPlayer.inventory;
    final trapCount = activeTraps.length;
    final canUseHeldPower = heldPower == PowerUp.boost;
    final hiddenCpuPower =
        !engine.currentPlayer.isHuman &&
        (heldPower != null || activeTraps.isNotEmpty);
    final trapCountLabel = trapCount == 1
        ? '1 trampa armada'
        : '$trapCount trampas armadas';
    final itemLabel = !engine.isChaos
        ? 'Modo tradicional'
        : hiddenCpuPower
        ? 'Objeto oculto'
        : heldPower == PowerUp.shield
        ? 'Escudo listo · automático'
        : heldPower == PowerUp.boost
        ? 'Usar: Turbo'
        : heldPower != null
        ? 'Trampa automática'
        : activeTraps.isNotEmpty
        ? trapCountLabel
        : 'Sin objeto';
    final ownItemDetails = <String>[
      if (heldPower != null)
        '${engine.powerUpName(heldPower)}: '
            '${engine.powerUpDescription(heldPower)}',
      for (final trap in activeTraps)
        '${engine.powerUpName(trap.type)} · casilla ${trap.loopIndex + 1}',
    ];
    final itemTooltip =
        engine.currentPlayer.isHuman && ownItemDetails.isNotEmpty
        ? ownItemDetails.join('\n')
        : itemLabel;
    final item = Tooltip(
      message: appTranslate(context, itemTooltip),
      child: OutlinedButton.icon(
        key: const ValueKey('item-action'),
        onPressed:
            !engine.isChaos ||
                !engine.currentPlayer.isHuman ||
                engine.effectResolving ||
                boardCalloutsOwnMoveChoice ||
                !canUseHeldPower
            ? null
            : () {
                onCancelSelection?.call();
                engine.usePowerUp();
              },
        icon: Icon(
          !engine.isChaos
              ? Icons.workspace_premium_rounded
              : hiddenCpuPower
              ? Icons.visibility_off_rounded
              : heldPower == PowerUp.shield
              ? Icons.shield_rounded
              : heldPower == PowerUp.boost
              ? Icons.bolt_rounded
              : activeTraps.isNotEmpty
              ? Icons.warning_amber_rounded
              : Icons.auto_awesome_rounded,
        ),
        label: PopText(itemLabel),
      ),
    );
    final portraitItemLabel = !engine.isChaos
        ? 'Modo tradicional'
        : hiddenCpuPower
        ? 'Objeto oculto'
        : heldPower == PowerUp.shield
        ? 'Escudo automático'
        : heldPower == PowerUp.boost
        ? 'Usar Turbo'
        : heldPower != null
        ? 'Trampa automática'
        : activeTraps.isNotEmpty
        ? trapCountLabel
        : 'Sin objeto';
    final portraitItem = Tooltip(
      message: appTranslate(context, itemTooltip),
      child: OutlinedButton.icon(
        key: const ValueKey('item-action'),
        onPressed:
            !engine.isChaos ||
                !engine.currentPlayer.isHuman ||
                engine.effectResolving ||
                boardCalloutsOwnMoveChoice ||
                !canUseHeldPower
            ? null
            : () {
                onCancelSelection?.call();
                engine.usePowerUp();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: .58),
          side: BorderSide(
            color: Colors.white.withValues(alpha: .62),
            width: 1.4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
        icon: Icon(
          !engine.isChaos
              ? Icons.workspace_premium_rounded
              : hiddenCpuPower
              ? Icons.visibility_off_rounded
              : heldPower == PowerUp.shield
              ? Icons.shield_rounded
              : heldPower == PowerUp.boost
              ? Icons.bolt_rounded
              : activeTraps.isNotEmpty
              ? Icons.warning_amber_rounded
              : Icons.auto_awesome_rounded,
          size: 16,
        ),
        label: _AutoFitSingleLineText(
          portraitItemLabel,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('game-control-panel'),
      child: LayoutBuilder(
        builder: (context, box) {
          if (landscapeHud) {
            return Container(
              key: const ValueKey('phone-landscape-game-hud'),
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2D7BE8), Color(0xFF12376F)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .90),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D07152F),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    key: const ValueKey('landscape-player-status'),
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: ClipOval(
                          child: _AvatarArt(
                            avatarId:
                                avatarIds[engine.currentPlayer.color] ??
                                (engine.currentPlayer.isHuman
                                    ? 'avatar_default'
                                    : 'avatar_robot'),
                            size: 30,
                            withFrame: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AutoFitSingleLineText(
                              engine.currentPlayer.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            _AutoFitSingleLineText(
                              phaseLabel,
                              style: TextStyle(
                                color: bonusTwentyActive
                                    ? PopColors.yellow
                                    : const Color(0xFFFFD5DA),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onShowChat != null) ...[
                        _HudMessageButton(
                          onPressed: onShowChat!,
                          compact: true,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (onCustomize != null) ...[
                        _HudCosmeticsButton(
                          onPressed: onCustomize!,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    key: const ValueKey('landscape-control-main-row'),
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      guidedMobileDice,
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canRollDice)
                              _AutoFitSingleLineText(
                                appTranslate(
                                  context,
                                  'Toca los dados para lanzar.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (engine.isChaos) ...[
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 38,
                                width: double.infinity,
                                child: portraitItem,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    key: const ValueKey('landscape-game-message'),
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 27),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FE),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .88),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 14,
                          color: PopColors.blue,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _AutoFitSingleLineText(
                              panelMessage,
                              key: ValueKey(panelMessage),
                              style: const TextStyle(
                                color: PopColors.navy,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          final portraitHud = !compact && box.maxWidth < 600;
          if (portraitHud && mobileBoardNavigator != null) {
            final currentColor = switch (engine.currentPlayer.color) {
              PlayerColor.red => PopColors.red,
              PlayerColor.green => PopColors.green,
              PlayerColor.yellow => PopColors.yellow,
              PlayerColor.blue => PopColors.blue,
            };
            final dicePrompt = selectedToken != null && moveChoices.isNotEmpty
                ? 'Elige ${moveChoices.join(' o ')}'
                : engine.hasRolled
                ? 'Elige una ficha'
                : 'Lanza los dados';
            final isLocalTurn = engine.currentPlayer.isHuman;
            final navigatorWidth = ((box.maxWidth - 32) * .43)
                .clamp(128.0, 156.0)
                .toDouble();
            return Container(
              key: const ValueKey('portrait-game-hud'),
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF19243E), Color(0xFF101A31)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF4E5E7A)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x52071122),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    key: const ValueKey('portrait-player-status'),
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: currentColor.withValues(alpha: .42),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(currentColor, Colors.white, .32),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AutoFitSingleLineText(
                              isLocalTurn
                                  ? 'Tu movimiento'
                                  : engine.currentPlayer.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _AutoFitSingleLineText(
                              isLocalTurn
                                  ? engine.hasRolled
                                        ? 'Selecciona un dado o revisa el tablero'
                                        : 'Lanza los dados o revisa el tablero'
                                  : 'Observa el turno en el tablero',
                              style: const TextStyle(
                                color: Color(0xFFB8C1D2),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onShowChat != null) ...[
                        const SizedBox(width: 4),
                        _HudMessageButton(
                          onPressed: onShowChat!,
                          compact: true,
                        ),
                      ],
                      if (onCustomize != null) ...[
                        const SizedBox(width: 4),
                        _HudCosmeticsButton(
                          onPressed: onCustomize!,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Divider(height: 1, color: Color(0xFF40506C)),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        key: const ValueKey('portrait-dice-column'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 18,
                              child: Row(
                                children: [
                                  const PopText(
                                    'DADOS',
                                    style: TextStyle(
                                      color: Color(0xFFB8C1D2),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: _AutoFitSingleLineText(
                                      canRollDice
                                          ? 'TOCA PARA LANZAR'
                                          : dicePrompt,
                                      alignment: Alignment.centerRight,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: guidedMobileDice,
                            ),
                            if (engine.isChaos) ...[
                              const SizedBox(height: 5),
                              SizedBox(
                                height: 40,
                                width: double.infinity,
                                child: portraitItem,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        key: const ValueKey('portrait-minimap-column'),
                        width: navigatorWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 18,
                              child: Row(
                                children: [
                                  const PopText(
                                    'MINIMAPA',
                                    style: TextStyle(
                                      color: Color(0xFFB8C1D2),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    mobileBoardFullView
                                        ? Icons.touch_app_rounded
                                        : Icons.zoom_in_rounded,
                                    color: Colors.white,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: _AutoFitSingleLineText(
                                      mobileBoardFullView
                                          ? 'MANTÉN Y ARRASTRA'
                                          : 'SUELTA PARA VOLVER',
                                      alignment: Alignment.centerRight,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                            AspectRatio(
                              aspectRatio: 1,
                              child: mobileBoardNavigator!,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          if (portraitHud) {
            return Container(
              key: const ValueKey('portrait-game-hud'),
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2457A2), PopColors.navy],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D07152F),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                  BoxShadow(
                    color: PopColors.yellow,
                    blurRadius: 0,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    key: const ValueKey('portrait-player-status'),
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: ClipOval(
                          child: _AvatarArt(
                            avatarId:
                                avatarIds[engine.currentPlayer.color] ??
                                (engine.currentPlayer.isHuman
                                    ? 'avatar_default'
                                    : 'avatar_robot'),
                            size: 30,
                            withFrame: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AutoFitSingleLineText(
                              engine.currentPlayer.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 1),
                            _AutoFitSingleLineText(
                              phaseLabel,
                              key: const ValueKey('portrait-phase'),
                              style: TextStyle(
                                color: bonusTwentyActive
                                    ? PopColors.yellow
                                    : const Color(0xFFFFCED4),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      if (onShowChat != null) ...[
                        _HudMessageButton(onPressed: onShowChat!),
                        const SizedBox(width: 6),
                      ],
                      if (onCustomize != null) ...[
                        _HudCosmeticsButton(onPressed: onCustomize!),
                      ],
                    ],
                  ),
                  if (engine.isChaos && engine.currentPlayer.isHuman) ...[
                    const SizedBox(height: 4),
                    _PowerSlotBadge(
                      engine: engine,
                      player: engine.currentPlayer,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    key: const ValueKey('portrait-control-main-row'),
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      guidedMobileDice,
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          key: const ValueKey('portrait-control-actions'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canRollDice)
                              _AutoFitSingleLineText(
                                appTranslate(
                                  context,
                                  'Toca los dados para lanzar.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (engine.isChaos) ...[
                              const SizedBox(height: 5),
                              SizedBox(
                                height: 40,
                                width: double.infinity,
                                child: portraitItem,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: const ValueKey('portrait-message'),
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .86),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 15,
                          color: PopColors.blue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: PopText(
                              panelMessage,
                              key: ValueKey(panelMessage),
                              maxLines: 2,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                color: PopColors.navy,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return Card(
            elevation: 5,
            shadowColor: PopColors.navy.withValues(alpha: .18),
            child: Padding(
              padding: EdgeInsets.all(compact ? 7 : 12),
              child: box.maxWidth < 600
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        status,
                        SizedBox(height: compact ? 6 : 12),
                        dice,
                        if (engine.isChaos) ...[
                          SizedBox(height: compact ? 5 : 8),
                          SizedBox(width: double.infinity, child: item),
                        ],
                        SizedBox(height: compact ? 5 : 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: PopText(
                                panelMessage,
                                textAlign: TextAlign.center,
                                maxLines: compact ? 2 : null,
                                overflow: compact
                                    ? TextOverflow.ellipsis
                                    : null,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [status, dice, if (engine.isChaos) item],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _DiceRollGuideTarget extends StatelessWidget {
  const _DiceRollGuideTarget({
    required this.child,
    required this.visible,
    required this.pulseSerial,
    required this.hand,
  });

  final Widget child;
  final bool visible;
  final int pulseSerial;
  final DiceHandPreference hand;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (visible)
          Positioned.fill(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: KeyedSubtree(
                  key: const ValueKey('dice-roll-guide'),
                  child: reduceMotion
                      ? _StaticDiceRollGuide(hand: hand)
                      : _RepeatingDiceRollGuide(
                          key: ValueKey(
                            'dice-roll-guide-pulse-$pulseSerial-${hand.name}',
                          ),
                          hand: hand,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RepeatingDiceRollGuide extends StatefulWidget {
  const _RepeatingDiceRollGuide({super.key, required this.hand});

  final DiceHandPreference hand;

  @override
  State<_RepeatingDiceRollGuide> createState() =>
      _RepeatingDiceRollGuideState();
}

class _RepeatingDiceRollGuideState extends State<_RepeatingDiceRollGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final progress = controller.value;
      final touchProgress = progress < .72 ? progress / .72 : 0.0;
      final reach = math.sin(math.pi * touchProgress.clamp(0.0, 1.0));
      return _AnimatedDiceRollGuide(hand: widget.hand, reach: reach);
    },
  );
}

class _TokenChoiceGuide extends StatelessWidget {
  const _TokenChoiceGuide({
    super.key,
    required this.center,
    required this.cell,
    required this.hand,
  });

  final Offset center;
  final double cell;
  final DiceHandPreference hand;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Positioned.fill(
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: KeyedSubtree(
            key: const ValueKey('token-choice-guide'),
            child: reduceMotion
                ? _TokenChoiceGuideVisual(
                    key: ValueKey('token-choice-guide-static-${hand.name}'),
                    center: center,
                    cell: cell,
                    hand: hand,
                    reach: 1,
                  )
                : _RepeatingTokenChoiceGuide(
                    center: center,
                    cell: cell,
                    hand: hand,
                  ),
          ),
        ),
      ),
    );
  }
}

class _RepeatingTokenChoiceGuide extends StatefulWidget {
  const _RepeatingTokenChoiceGuide({
    required this.center,
    required this.cell,
    required this.hand,
  });

  final Offset center;
  final double cell;
  final DiceHandPreference hand;

  @override
  State<_RepeatingTokenChoiceGuide> createState() =>
      _RepeatingTokenChoiceGuideState();
}

class _RepeatingTokenChoiceGuideState extends State<_RepeatingTokenChoiceGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final progress = controller.value;
      final touchProgress = progress < .72 ? progress / .72 : 0.0;
      final reach = math.sin(math.pi * touchProgress.clamp(0.0, 1.0));
      return _TokenChoiceGuideVisual(
        key: ValueKey('token-choice-guide-${widget.hand.name}'),
        center: widget.center,
        cell: widget.cell,
        hand: widget.hand,
        reach: reach,
      );
    },
  );
}

class _TokenChoiceGuideVisual extends StatelessWidget {
  const _TokenChoiceGuideVisual({
    super.key,
    required this.center,
    required this.cell,
    required this.hand,
    required this.reach,
  });

  final Offset center;
  final double cell;
  final DiceHandPreference hand;
  final double reach;

  @override
  Widget build(BuildContext context) {
    final fromRight = hand == DiceHandPreference.right;
    final easedReach = Curves.easeInOutCubic.transform(reach);
    final handOpacity = .28 + (.22 * easedReach);
    final shadowOpacity = .28 + (.16 * easedReach);
    final guideSize = (cell * 2.8).clamp(40.0, 52.0).toDouble();
    final haloSize = cell * (1.55 + .14 * easedReach);
    final handCenter =
        center + Offset((fromRight ? .48 : -.48) * cell, .78 * cell);
    final approachOffset = Offset(
      (1 - easedReach) * (fromRight ? .55 : -.55) * cell,
      (1 - easedReach) * .60 * cell,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: center.dx - haloSize / 2,
          top: center.dy - haloSize / 2,
          width: haloSize,
          height: haloSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(
                0xFF3A94FF,
              ).withValues(alpha: .08 + .10 * easedReach),
              border: Border.all(
                color: const Color(
                  0xFFD9EEFF,
                ).withValues(alpha: .20 + .04 * easedReach),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF3A94FF,
                  ).withValues(alpha: .18 + .06 * easedReach),
                  blurRadius: 7,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: handCenter.dx - guideSize / 2,
          top: handCenter.dy - guideSize / 2,
          width: guideSize,
          height: guideSize,
          child: Transform.translate(
            offset: approachOffset,
            child: Transform.scale(
              scale: .88 + .12 * easedReach,
              child: Transform.rotate(
                angle: fromRight ? -.40 : .40,
                child: Icon(
                  Icons.pan_tool_alt_rounded,
                  color: const Color(0xFFE7F5FF).withValues(alpha: handOpacity),
                  size: guideSize,
                  shadows: [
                    Shadow(
                      color: const Color(
                        0xFF0A2452,
                      ).withValues(alpha: shadowOpacity),
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedDiceRollGuide extends StatelessWidget {
  const _AnimatedDiceRollGuide({required this.hand, required this.reach});

  final DiceHandPreference hand;
  final double reach;

  @override
  Widget build(BuildContext context) {
    final fromRight = hand == DiceHandPreference.right;
    final easedReach = Curves.easeInOutCubic.transform(reach);
    final handOpacity = .26 + (.22 * easedReach);
    final shadowOpacity = .24 + (.18 * easedReach);
    final horizontalOffset = (1 - easedReach) * (fromRight ? 22.0 : -22.0);
    final verticalOffset = (1 - easedReach) * 14;
    return KeyedSubtree(
      key: ValueKey('dice-roll-guide-${hand.name}'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: (.12 + (.14 * easedReach)).clamp(0.0, .26).toDouble(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFD9EEFF),
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x553A94FF),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DiceGuideMotionPainter(
                intensity: easedReach,
                fromRight: fromRight,
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: fromRight
                  ? const Alignment(.62, .68)
                  : const Alignment(-.62, .68),
              child: Transform.translate(
                offset: Offset(horizontalOffset, verticalOffset),
                child: Transform.rotate(
                  angle: fromRight ? -.43 : .43,
                  child: Icon(
                    Icons.pan_tool_alt_rounded,
                    color: const Color(
                      0xFFE7F5FF,
                    ).withValues(alpha: handOpacity),
                    size: 65,
                    shadows: [
                      Shadow(
                        color: const Color(
                          0xFF0A2452,
                        ).withValues(alpha: shadowOpacity),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticDiceRollGuide extends StatelessWidget {
  const _StaticDiceRollGuide({required this.hand});

  final DiceHandPreference hand;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: ValueKey('dice-roll-guide-static-${hand.name}'),
    child: Align(
      alignment: hand == DiceHandPreference.right
          ? const Alignment(.62, .68)
          : const Alignment(-.62, .68),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x143A94FF),
          border: Border.all(color: const Color(0x5CD9EEFF), width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x293A94FF), blurRadius: 12),
          ],
        ),
        child: const Icon(
          Icons.touch_app_rounded,
          color: Color(0x66E7F5FF),
          size: 30,
        ),
      ),
    ),
  );
}

class _DiceGuideMotionPainter extends CustomPainter {
  const _DiceGuideMotionPainter({
    required this.intensity,
    required this.fromRight,
  });

  final double intensity;
  final bool fromRight;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= .01) return;
    canvas.save();
    if (!fromRight) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..color = const Color(0xFFD9EEFF).withValues(alpha: .24 * intensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .42,
        -size.height * .04,
        size.width * .50,
        size.height * .78,
      ),
      -.92,
      .66,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .53,
        size.height * .08,
        size.width * .40,
        size.height * .66,
      ),
      -.95,
      .48,
      false,
      paint..strokeWidth = 1.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiceGuideMotionPainter oldDelegate) =>
      intensity != oldDelegate.intensity || fromRight != oldDelegate.fromRight;
}

class _HudCosmeticsButton extends StatelessWidget {
  const _HudCosmeticsButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visualDimension = compact ? 28.0 : 32.0;
    return SizedBox.square(
      key: const ValueKey('game-owned-cosmetics-button'),
      dimension: 44,
      child: Tooltip(
        message: appTranslate(context, 'Mis diseños'),
        child: Semantics(
          button: true,
          label: appTranslate(context, 'Cambiar artículos comprados'),
          child: Center(
            child: Material(
              color: PopColors.yellow,
              elevation: 3,
              shadowColor: const Color(0x6607152F),
              shape: CircleBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: .94),
                  width: 1.4,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: visualDimension,
                  child: Icon(
                    Icons.checkroom_rounded,
                    color: PopColors.navy,
                    size: compact ? 16 : 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HudMessageButton extends StatelessWidget {
  const _HudMessageButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visualDimension = compact ? 28.0 : 32.0;
    return SizedBox.square(
      key: const ValueKey('game-safe-chat-button'),
      dimension: 44,
      child: Tooltip(
        message: appTranslate(context, 'Mensajes rápidos'),
        child: Semantics(
          button: true,
          label: appTranslate(context, 'Mensajes rápidos'),
          child: Center(
            child: Material(
              color: const Color(0xFF6B55E7),
              elevation: 3,
              shadowColor: const Color(0x6607152F),
              shape: CircleBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: .92),
                  width: 1.4,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: visualDimension,
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: compact ? 15 : 17,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DieSlot extends StatelessWidget {
  const _DieSlot({
    super.key,
    required this.slotIndex,
    required this.value,
    required this.style,
    required this.animationId,
    required this.available,
    required this.selectable,
    this.onTap,
  });

  final int slotIndex;
  final int value;
  final DiceVisualSpec style;
  final int animationId;
  final bool available;
  final bool selectable;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: selectable,
    enabled: selectable,
    label: appTranslate(
      context,
      available ? 'Dado $value disponible' : 'Dado $value usado',
    ),
    child: GestureDetector(
      onTap: selectable ? () => onTap?.call(value) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: available ? 1 : .24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selectable
                ? const Color(0xFF7057FF).withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selectable ? const Color(0xFF7057FF) : Colors.transparent,
              width: 2,
            ),
          ),
          child: _DieFace(
            key: ValueKey('die-face-$slotIndex'),
            value: value,
            style: style,
            slotIndex: slotIndex,
            animationId: animationId,
          ),
        ),
      ),
    ),
  );
}

class PlayerRoster extends StatelessWidget {
  const PlayerRoster({
    super.key,
    required this.engine,
    this.onlineSession,
    this.avatarIds = const <PlayerColor, String?>{},
    this.revealTrapDetails = false,
  });
  final GameEngine engine;
  final OnlineMatchSession? onlineSession;
  final Map<PlayerColor, String?> avatarIds;
  final bool revealTrapDetails;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (engine.isChaos) ...[
            const Row(
              children: [
                Icon(Icons.backpack_rounded, size: 17, color: PopColors.navy),
                SizedBox(width: 6),
                Expanded(
                  child: PopText(
                    'PODER AUTOMÁTICO · TRAMPAS ACTIVAS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: PopColors.navy,
                      letterSpacing: .25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
          for (var index = 0; index < engine.players.length; index++)
            _playerRow(
              engine.players[index],
              index == engine.currentPlayerIndex,
              onlineSession?.participantForColor(engine.players[index].color),
            ),
        ],
      ),
    ),
  );

  Widget _playerRow(
    PlayerState player,
    bool active,
    OnlineParticipant? participant,
  ) {
    final color = _colorFor(player.color);
    final completed = player.tokens.where((token) => token.finished).length;
    final displayName = participant?.displayName ?? player.name;
    final style = participant == null
        ? ''
        : participant.loadout.productIds.map(_cosmeticGlyph).join(' ');
    final controlLabel = participant == null
        ? ''
        : _participantRoleLabel(participant);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: .14) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: .18),
                child: _AvatarArt(
                  avatarId:
                      avatarIds[player.color] ??
                      participant?.avatarId ??
                      (player.isHuman ? 'avatar_default' : 'avatar_robot'),
                  size: 26,
                  withFrame: false,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AutoFitSingleLineText(
                      displayName,
                      style: TextStyle(
                        fontSize: participant == null ? null : 12,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    if (participant != null)
                      _AutoFitSingleLineText(
                        '${participant.flag} Nv. ${participant.level} · $controlLabel'
                        '${style.isEmpty ? '' : ' · $style'}',
                        key: ValueKey(
                          'online-profile-${participant.color.name}',
                        ),
                        style: TextStyle(
                          fontSize: 8.5,
                          color: participant.kind == ParticipantKind.local
                              ? PopColors.green
                              : PopColors.blue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (engine.isChaos) ...[
                      const SizedBox(height: 3),
                      _PowerSlotBadge(
                        engine: engine,
                        player: player,
                        revealTrapDetails: revealTrapDetails,
                      ),
                    ],
                  ],
                ),
              ),
              PopText(
                '$completed/${engine.rules.tokensRequiredToWin}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 3),
                Icon(Icons.play_arrow_rounded, color: color, size: 16),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _colorFor(PlayerColor color) => switch (color) {
    PlayerColor.red => PopColors.red,
    PlayerColor.green => PopColors.green,
    PlayerColor.yellow => PopColors.yellow,
    PlayerColor.blue => PopColors.blue,
  };
}

class _PowerSlotBadge extends StatelessWidget {
  const _PowerSlotBadge({
    required this.engine,
    required this.player,
    this.revealTrapDetails = false,
  });
  final GameEngine engine;
  final PlayerState player;
  final bool revealTrapDetails;

  Widget _pill(
    BuildContext context, {
    required Key key,
    required String label,
    required String tooltip,
    required IconData icon,
    required Color color,
  }) {
    final background = Color.lerp(color, Colors.white, .84)!;
    final foreground = Color.lerp(color, PopColors.navy, .34)!;
    return Tooltip(
      message: appTranslate(context, tooltip),
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Color.lerp(color, Colors.white, .18)!,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2407132D),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
            Expanded(
              child: _AutoFitSingleLineText(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  color: PopColors.navy,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .05,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final held = player.inventory;
    final traps = engine.activeTrapsFor(player.color).toList(growable: false);
    final heldHidden = player.color != engine.localViewerColor;
    final trapsHidden =
        player.color != engine.localViewerColor && !revealTrapDetails;
    final latestTrap = traps.isEmpty ? null : traps.last;
    final rows = <Widget>[];

    if (held != null) {
      final label = heldHidden
          ? 'Poder automático oculto'
          : held == PowerUp.shield
          ? 'PODER · Escudo listo · AUTO'
          : held == PowerUp.boost
          ? 'PODER · Turbo guardado'
          : 'Trampa automática';
      rows.add(
        _pill(
          context,
          key: ValueKey(
            heldHidden
                ? 'hidden-held-${player.color.name}'
                : 'held-${held.name}',
          ),
          label: label,
          tooltip: heldHidden
              ? label
              : 'PODER AUTOMÁTICO · ${engine.powerUpName(held)}: '
                    '${engine.powerUpDescription(held)}',
          icon: heldHidden ? Icons.visibility_off_rounded : _powerUiIcon(held),
          color: heldHidden
              ? _playerUiColor(player.color)
              : _powerUiColor(held),
        ),
      );
    }

    if (latestTrap != null) {
      final count = traps.length;
      final latestName = switch (latestTrap.type) {
        PowerUp.glueTrap => 'Pegamento',
        PowerUp.setbackTrap => 'Retroceso',
        PowerUp.prisonTrap => 'Cárcel',
        PowerUp.bomb => 'Bomba',
        PowerUp.shield => 'Escudo',
        PowerUp.boost => 'Turbo',
      };
      final label = trapsHidden
          ? count == 1
                ? '1 trampa oculta'
                : '$count trampas ocultas'
          : count == 1
          ? 'TRAMPA · $latestName · #${latestTrap.loopIndex + 1}'
          : 'TRAMPAS ×$count · última $latestName #${latestTrap.loopIndex + 1}';
      final details = trapsHidden
          ? label
          : traps
                .map(
                  (trap) =>
                      '${engine.powerUpName(trap.type)} · casilla ${trap.loopIndex + 1}',
                )
                .join('\n');
      rows.add(
        _pill(
          context,
          key: ValueKey(
            trapsHidden
                ? 'hidden-traps-${player.color.name}-$count'
                : count == 1
                ? 'trap-${latestTrap.type.name}-${latestTrap.loopIndex}'
                : 'traps-${player.color.name}-$count',
          ),
          label: label,
          tooltip: details,
          icon: trapsHidden
              ? Icons.visibility_off_rounded
              : _powerUiIcon(latestTrap.type),
          color: revealTrapDetails
              ? _playerUiColor(player.color)
              : trapsHidden
              ? _playerUiColor(player.color)
              : _powerUiColor(latestTrap.type),
        ),
      );
    }

    if (rows.isEmpty) {
      rows.add(
        _pill(
          context,
          key: ValueKey('empty-${player.color.name}'),
          label: 'Sin poder ni trampa',
          tooltip: 'Sin poder ni trampa',
          icon: Icons.radio_button_unchecked_rounded,
          color: const Color(0xFF98A2B3),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: Column(
        key: ValueKey(
          'power-trap-status-${player.color.name}-${held?.name}-${traps.length}',
        ),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: 2),
            rows[index],
          ],
        ],
      ),
    );
  }
}

class _PowerStatusTile extends StatelessWidget {
  const _PowerStatusTile({
    required this.engine,
    required this.player,
    this.participant,
    this.revealTrapDetails = false,
  });
  final GameEngine engine;
  final PlayerState player;
  final OnlineParticipant? participant;
  final bool revealTrapDetails;

  @override
  Widget build(BuildContext context) {
    final traps = engine.activeTrapsFor(player.color).toList(growable: false);
    final held = player.inventory;
    final latestTrap = traps.isEmpty ? null : traps.last;
    final power = held ?? latestTrap?.type;
    final heldHidden = player.color != engine.localViewerColor && held != null;
    final trapsHidden =
        player.color != engine.localViewerColor &&
        traps.isNotEmpty &&
        !revealTrapDetails;
    final powerHidden = held != null ? heldHidden : trapsHidden;
    final color = _playerUiColor(player.color);
    final descriptions = <String>[
      if (held != null)
        heldHidden
            ? 'Poder automático oculto'
            : held == PowerUp.shield
            ? 'PODER · Escudo listo · automático'
            : 'PODER · ${engine.powerUpName(held)} guardado',
      if (traps.isNotEmpty)
        trapsHidden
            ? traps.length == 1
                  ? '1 trampa oculta'
                  : '${traps.length} trampas ocultas'
            : traps
                  .map(
                    (trap) =>
                        '${engine.powerUpName(trap.type)} · casilla ${trap.loopIndex + 1}',
                  )
                  .join('  •  '),
      if (held == null && traps.isEmpty) 'Sin poder · 0 trampas',
    ];
    final description = descriptions.join('\n');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: _AvatarArt(
              avatarId:
                  participant?.avatarId ??
                  (player.isHuman ? 'avatar_default' : 'avatar_robot'),
              size: 36,
              withFrame: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AutoFitSingleLineText(
                  participant == null
                      ? player.name
                      : '${participant!.displayName} ${participant!.flag}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (participant != null)
                  PopText(
                    'Nivel ${participant!.level} · '
                    '${_participantRoleLabel(participant!)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: PopColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                PopText(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: power == null
                ? PopColors.cloud
                : (powerHidden ? color : _powerUiColor(power)).withValues(
                    alpha: .16,
                  ),
            child: Icon(
              power == null
                  ? Icons.add_rounded
                  : powerHidden
                  ? Icons.visibility_off_rounded
                  : traps.length > 1 && held == null
                  ? Icons.warning_amber_rounded
                  : _powerUiIcon(power),
              color: power == null
                  ? const Color(0xFF98A2B3)
                  : powerHidden
                  ? color
                  : _powerUiColor(power),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _powerUiIcon(PowerUp power) => switch (power) {
  PowerUp.shield => Icons.shield_rounded,
  PowerUp.boost => Icons.bolt_rounded,
  PowerUp.glueTrap => Icons.pause_circle_filled_rounded,
  PowerUp.setbackTrap => Icons.undo_rounded,
  PowerUp.prisonTrap => Icons.lock_rounded,
  PowerUp.bomb => Icons.local_fire_department_rounded,
};

Color _powerUiColor(PowerUp? power) => switch (power) {
  PowerUp.shield => PopColors.blue,
  PowerUp.boost => PopColors.green,
  PowerUp.glueTrap => const Color(0xFF7B61FF),
  PowerUp.setbackTrap => PopColors.yellow,
  PowerUp.prisonTrap || PowerUp.bomb => PopColors.red,
  null => const Color(0xFF98A2B3),
};

Color _playerUiColor(PlayerColor color) => switch (color) {
  PlayerColor.red => PopColors.red,
  PlayerColor.green => PopColors.green,
  PlayerColor.yellow => PopColors.yellow,
  PlayerColor.blue => PopColors.blue,
};

class _DieFace extends StatefulWidget {
  const _DieFace({
    super.key,
    required this.value,
    required this.style,
    required this.slotIndex,
    required this.animationId,
  });
  final int value;
  final DiceVisualSpec style;
  final int slotIndex;
  final int animationId;

  @override
  State<_DieFace> createState() => _DieFaceState();
}

class _DieFaceState extends State<_DieFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _DieFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationId != widget.animationId ||
        oldWidget.value != widget.value) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final faceColor = widget
            .style
            .faceColors[widget.slotIndex % widget.style.faceColors.length];
        final progress = controller.value;
        final spin = Curves.easeOutQuart.transform(progress);
        final rolling = controller.isAnimating && progress < .995;
        final faceStep = (progress * 14).floor();
        final shown = rolling && progress < .86
            ? ((widget.value + widget.slotIndex * 2 + faceStep * 5) % 6) + 1
            : widget.value;
        final firstHopProgress = (progress / .70).clamp(0.0, 1.0);
        final firstHop = progress < .70
            ? math.sin(firstHopProgress * math.pi) * 10.5
            : 0.0;
        final settleProgress = ((progress - .70) / .30).clamp(0.0, 1.0);
        final settleHop = progress >= .70
            ? math.sin(settleProgress * math.pi) * (1 - settleProgress) * 4.5
            : 0.0;
        final hop = firstHop + settleHop;
        final direction = widget.slotIndex.isEven ? 1.0 : -1.0;
        final sideways =
            math.sin(progress * math.pi * 7) * (1 - progress) * direction * 2;
        final scale = 1 + math.sin(progress * math.pi) * .055;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, .0022)
          ..rotateX(spin * math.pi * (widget.slotIndex.isEven ? 6 : 8))
          ..rotateY(spin * math.pi * (widget.slotIndex.isEven ? 8 : 6))
          ..rotateZ(
            direction * spin * math.pi * 4 +
                math.sin(progress * math.pi * 6) * (1 - progress) * .12,
          );
        return Transform.translate(
          offset: Offset(sideways, -hop),
          child: Transform.scale(
            scale: scale,
            child: Transform(
              alignment: Alignment.center,
              transform: transform,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(faceColor, Colors.white, .34)!,
                      faceColor,
                      Color.lerp(faceColor, PopColors.navy, .30)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.style.borderColor.withValues(alpha: .94),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.style.glowColor.withValues(alpha: .58),
                      blurRadius: 8 + hop * .35,
                      offset: Offset(0, 4 + hop * .18),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DiceMotifPainter(
                          motif: widget.style.motif,
                          accent: widget.style.borderColor.withValues(
                            alpha: .18,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PipDiePainter(
                          shown,
                          color: widget.style.pipColor,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 4,
                      right: 10,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: .40),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PipDiePainter extends CustomPainter {
  const _PipDiePainter(this.value, {this.color = Colors.white});
  final int value;
  final Color color;

  static const positions = <int, List<int>>{
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final pip = Paint()..color = color;
    final shadow = Paint()..color = PopColors.navy.withValues(alpha: .24);
    final radius = size.shortestSide * .075;
    for (final index in positions[value.clamp(1, 6)]!) {
      final row = index ~/ 3;
      final col = index % 3;
      final center = Offset(
        size.width * (.24 + col * .26),
        size.height * (.24 + row * .26),
      );
      canvas.drawCircle(center + const Offset(0, 1.2), radius, shadow);
      canvas.drawCircle(center, radius, pip);
    }
  }

  @override
  bool shouldRepaint(covariant _PipDiePainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}

class _DiceMotifPainter extends CustomPainter {
  const _DiceMotifPainter({required this.motif, required this.accent});

  final DiceMotif motif;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (motif == DiceMotif.classic) return;
    final thin = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.shortestSide * .025)
      ..strokeCap = StrokeCap.round;
    switch (motif) {
      case DiceMotif.galaxy:
        final stars = [
          const Offset(.18, .20),
          const Offset(.76, .18),
          const Offset(.84, .55),
          const Offset(.24, .76),
          const Offset(.66, .82),
        ];
        for (var index = 0; index < stars.length; index++) {
          final center = Offset(
            stars[index].dx * size.width,
            stars[index].dy * size.height,
          );
          canvas.drawCircle(
            center,
            size.shortestSide * (index.isEven ? .035 : .022),
            Paint()..color = accent,
          );
        }
        canvas.drawArc(
          Rect.fromCircle(
            center: size.center(Offset.zero),
            radius: size.shortestSide * .36,
          ),
          -.8,
          2.4,
          false,
          thin,
        );
        break;
      case DiceMotif.candy:
        for (var offset = -size.height; offset < size.width; offset += 10) {
          canvas.drawLine(
            Offset(offset, size.height),
            Offset(offset + size.height, 0),
            thin,
          );
        }
        break;
      case DiceMotif.volcano:
        final flame = Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width * .15, size.height * .70)
          ..lineTo(size.width * .31, size.height * .91)
          ..lineTo(size.width * .48, size.height * .60)
          ..lineTo(size.width * .68, size.height * .88)
          ..lineTo(size.width * .84, size.height * .66)
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(flame, Paint()..color = accent);
        break;
      case DiceMotif.ice:
        for (final center in [
          Offset(size.width * .20, size.height * .22),
          Offset(size.width * .80, size.height * .72),
        ]) {
          for (var index = 0; index < 3; index++) {
            final angle = index * math.pi / 3;
            final delta = Offset(
              math.cos(angle) * size.width * .11,
              math.sin(angle) * size.height * .11,
            );
            canvas.drawLine(center - delta, center + delta, thin);
          }
        }
        break;
      case DiceMotif.arcade:
        for (var index = 1; index < 5; index++) {
          final position = index / 5;
          canvas.drawLine(
            Offset(size.width * position, 0),
            Offset(size.width * position, size.height),
            thin,
          );
          canvas.drawLine(
            Offset(0, size.height * position),
            Offset(size.width, size.height * position),
            thin,
          );
        }
        break;
      case DiceMotif.ocean:
        for (var row = 1; row <= 3; row++) {
          final y = size.height * row / 4;
          final wave = Path()..moveTo(0, y);
          for (var column = 1; column <= 8; column++) {
            wave.lineTo(
              size.width * column / 8,
              y + math.sin(column * math.pi / 2) * size.shortestSide * .045,
            );
          }
          canvas.drawPath(wave, thin);
        }
        break;
      case DiceMotif.prism:
        final triangles = [
          [
            const Offset(.10, .18),
            const Offset(.48, .08),
            const Offset(.32, .42),
          ],
          [
            const Offset(.60, .26),
            const Offset(.91, .18),
            const Offset(.78, .55),
          ],
          [
            const Offset(.28, .58),
            const Offset(.65, .50),
            const Offset(.50, .90),
          ],
        ];
        for (final points in triangles) {
          final path = Path()
            ..moveTo(
              points.first.dx * size.width,
              points.first.dy * size.height,
            );
          for (final point in points.skip(1)) {
            path.lineTo(point.dx * size.width, point.dy * size.height);
          }
          path.close();
          canvas.drawPath(path, thin);
        }
        break;
      case DiceMotif.midnight:
        final constellation = [
          const Offset(.16, .74),
          const Offset(.32, .34),
          const Offset(.56, .54),
          const Offset(.78, .20),
          const Offset(.87, .68),
        ];
        final path = Path();
        for (var index = 0; index < constellation.length; index++) {
          final point = Offset(
            constellation[index].dx * size.width,
            constellation[index].dy * size.height,
          );
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawCircle(
            point,
            size.shortestSide * (index.isEven ? .032 : .022),
            Paint()..color = accent,
          );
        }
        canvas.drawPath(path, thin);
        break;
      case DiceMotif.classic:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DiceMotifPainter oldDelegate) =>
      motif != oldDelegate.motif || accent != oldDelegate.accent;
}

ShopProductType _shopAnalyticsProductType(CosmeticCategory category) =>
    switch (category) {
      CosmeticCategory.theme => ShopProductType.theme,
      CosmeticCategory.dice => ShopProductType.dice,
      CosmeticCategory.tokens => ShopProductType.tokens,
      CosmeticCategory.avatar => ShopProductType.avatar,
    };

class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    this.wallet,
    this.showTestCoinControls,
    this.analytics = const NoopGameAnalytics(),
  });

  final WalletController? wallet;
  final bool? showTestCoinControls;
  final GameAnalytics analytics;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const categories = [
    'Destacados',
    'Avatares',
    'Temas',
    'Dados',
    'Fichas',
  ];

  late final WalletController wallet;
  late final bool ownsWallet;
  late final AnalyticsCorrelation analyticsCorrelation;
  String selectedCategory = categories.first;
  bool rewardedOfferAnalyticsLogged = false;

  bool get testCoinControlsVisible =>
      kDebugMode && (widget.showTestCoinControls ?? true);

  @override
  void initState() {
    super.initState();
    ownsWallet = widget.wallet == null;
    wallet = widget.wallet ?? WalletController();
    analyticsCorrelation = AnalyticsCorrelation(
      anonymousSessionId: _newAnalyticsReference('shop_session'),
    );
    wallet.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ads = MobileAdsScope.maybeOf(context);
    if (!shopRewardedCoinsEnabled ||
        rewardedOfferAnalyticsLogged ||
        ads == null ||
        !ads.supported) {
      return;
    }
    rewardedOfferAnalyticsLogged = true;
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: RewardedAdStage.offered,
          placement: RewardedAdPlacement.shopCoins,
          rewardCoins: 100,
          correlation: analyticsCorrelation,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (ownsWallet) wallet.dispose();
    super.dispose();
  }

  Future<void> _watchRewardedAd(AppAdsController ads) async {
    final balanceBefore = wallet.balance;
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: RewardedAdStage.started,
          placement: RewardedAdPlacement.shopCoins,
          rewardCoins: 100,
          correlation: analyticsCorrelation,
        ),
      ),
    );
    var adResult = RewardedAdResult.failed;
    try {
      adResult = await ads.showRewardedWithResult();
    } catch (_) {
      debugPrint('Optional shop rewarded ad could not be completed.');
    }
    final earned = adResult.didEarnReward;
    if (earned) {
      await wallet.addCoins(100);
    }
    unawaited(
      widget.analytics.logEvent(
        RewardedAdEvent(
          stage: switch (adResult) {
            RewardedAdResult.earned => RewardedAdStage.completed,
            RewardedAdResult.dismissed => RewardedAdStage.declined,
            RewardedAdResult.unavailable => RewardedAdStage.unavailable,
            RewardedAdResult.failed => RewardedAdStage.failed,
          },
          placement: RewardedAdPlacement.shopCoins,
          rewardCoins: 100,
          correlation: analyticsCorrelation,
        ),
      ),
    );
    if (earned) {
      unawaited(
        widget.analytics.logEvent(
          CurrencyEvent(
            flow: CurrencyFlow.earned,
            source: CurrencySource.rewardedAd,
            amount: 100,
            balanceBefore: balanceBefore,
            balanceAfter: wallet.balance,
            anonymousTransactionId: _newAnalyticsReference(
              'reward_transaction',
            ),
            correlation: analyticsCorrelation,
          ),
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: PopText(switch (adResult) {
          RewardedAdResult.earned => '¡Recibiste 100 monedas!',
          RewardedAdResult.dismissed => 'El anuncio no se completó.',
          RewardedAdResult.unavailable => 'No hay un anuncio disponible ahora.',
          RewardedAdResult.failed => 'No se pudo mostrar el anuncio.',
        }),
      ),
    );
  }

  Future<void> _showProductPreview(WalletProduct product) async {
    unawaited(
      widget.analytics.logEvent(
        ShopEvent(
          stage: ShopStage.previewed,
          productId: product.id,
          productType: _shopAnalyticsProductType(product.category),
          correlation: analyticsCorrelation,
        ),
      ),
    );
    final useProduct = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final accent = _shopProductColor(product);
        final owned = wallet.isOwned(product.id);
        final equipped = wallet.isEquipped(product.id);
        return Dialog(
          key: ValueKey('shop-large-preview-${product.id}'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: math.max(320, screen.height - 28),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x6617284D),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(17, 15, 17, 17),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.visibility_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const PopText(
                                'VISTA PREVIA EN GRANDE',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .5,
                                ),
                              ),
                              _AutoFitSingleLineText(
                                product.name,
                                style: const TextStyle(
                                  color: PopColors.navy,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: appTranslate(dialogContext, 'Cerrar'),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    AspectRatio(
                      aspectRatio: 1.2,
                      child: _ShopProductPreview(product: product, large: true),
                    ),
                    const SizedBox(height: 12),
                    PopText(
                      product.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: PopColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const PopText(
                      'Así se verá este diseño dentro del juego.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        key: ValueKey('shop-preview-action-${product.id}'),
                        onPressed: equipped
                            ? null
                            : () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          disabledBackgroundColor: PopColors.green,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        icon: Icon(
                          equipped
                              ? Icons.check_circle_rounded
                              : owned
                              ? Icons.style_rounded
                              : Icons.shopping_bag_rounded,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: PopText(
                            equipped
                                ? 'YA ESTÁ EN USO'
                                : owned
                                ? 'USAR ESTE DISEÑO'
                                : 'COMPRAR · 🪙 ${_formatCoins(product.price)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (useProduct == true && mounted) {
      await _handleProduct(product.id);
    }
  }

  Future<void> _handleProduct(String productId) async {
    if (wallet.isOwned(productId)) {
      final result = await wallet.equip(productId);
      final product = wallet.productById(productId);
      if (result != EquipResult.alreadyEquipped && product != null) {
        unawaited(
          widget.analytics.logEvent(
            ShopEvent(
              stage: ShopStage.equipped,
              productId: product.id,
              productType: _shopAnalyticsProductType(product.category),
              correlation: analyticsCorrelation,
            ),
          ),
        );
      }
      if (!mounted) return;
      final message = result == EquipResult.alreadyEquipped
          ? 'Ese diseño ya está activo.'
          : 'Diseño equipado.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: PopText(message)));
      return;
    }
    final product = wallet.productById(productId);
    if (product == null) return;
    if (wallet.balance < product.price) {
      if (testCoinControlsVisible) {
        await _showAddCoinsDialog(context, wallet);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: PopText('No tienes monedas suficientes.')),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final accent = _shopProductColor(product);
        final balanceAfterPurchase = wallet.balance - product.price;
        return Dialog(
          key: const ValueKey('shop-purchase-dialog'),
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 430,
              maxHeight: math.max(300, screen.height - 36),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x5517284D),
                    blurRadius: 24,
                    offset: Offset(0, 13),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: .32),
                                blurRadius: 9,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shopping_bag_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const PopText(
                                'VISTA PREVIA',
                                style: TextStyle(
                                  color: Color(0xFF667085),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .6,
                                ),
                              ),
                              _AutoFitSingleLineText(
                                product.name,
                                style: const TextStyle(
                                  color: PopColors.navy,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: appTranslate(dialogContext, 'Cerrar'),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 174,
                      child: _ShopProductPreview(product: product),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: PopColors.cloud,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDDE5F2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const PopText(
                                  'TU SALDO',
                                  style: TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                PopText(
                                  '🪙 ${_formatCoins(wallet.balance)}',
                                  style: const TextStyle(
                                    color: PopColors.navy,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF98A2B3),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const PopText(
                                  'DESPUÉS DE COMPRAR',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                PopText(
                                  '🪙 ${_formatCoins(balanceAfterPurchase)}',
                                  style: TextStyle(
                                    color: balanceAfterPurchase >= 0
                                        ? PopColors.green
                                        : PopColors.red,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const PopText(
                      'Artículo cosmético · no da ventajas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        key: const ValueKey('shop-confirm-purchase'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: const Icon(Icons.monetization_on_rounded),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: PopText(
                            'COMPRAR · 🪙 ${_formatCoins(product.price)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true) return;
    final balanceBefore = wallet.balance;
    final result = await wallet.purchase(productId);
    if (result == PurchaseResult.purchased) {
      await wallet.equip(productId);
      unawaited(
        widget.analytics.logEvent(
          CurrencyEvent(
            flow: CurrencyFlow.spent,
            source: CurrencySource.shopPurchase,
            amount: product.price,
            balanceBefore: balanceBefore,
            balanceAfter: wallet.balance,
            anonymousTransactionId: _newAnalyticsReference('shop_transaction'),
            correlation: analyticsCorrelation,
          ),
        ),
      );
      unawaited(
        widget.analytics.logEvent(
          ShopEvent(
            stage: ShopStage.purchased,
            productId: product.id,
            productType: _shopAnalyticsProductType(product.category),
            priceCoins: product.price,
            correlation: analyticsCorrelation,
          ),
        ),
      );
      unawaited(
        widget.analytics.logEvent(
          ShopEvent(
            stage: ShopStage.equipped,
            productId: product.id,
            productType: _shopAnalyticsProductType(product.category),
            correlation: analyticsCorrelation,
          ),
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: PopText(
          result == PurchaseResult.purchased
              ? '¡${product.name} comprado y equipado!'
              : result == PurchaseResult.insufficientFunds
              ? 'No tienes monedas suficientes.'
              : 'Ese artículo ya está en tu colección.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ads = MobileAdsScope.maybeOf(context);
    final visibleItems = selectedCategory == categories.first
        ? shopCatalog.where((item) => item.featured).toList(growable: false)
        : shopCatalog
              .where(
                (item) => _shopCategoryLabel(item.category) == selectedCategory,
              )
              .toList();
    return AnimatedBuilder(
      animation: wallet,
      builder: (context, _) => _PopRouteScaffold(
        child: PageShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('shop-header'),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1817284D),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      key: const ValueKey('shop-back'),
                      tooltip: appTranslate(context, 'Volver'),
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PopText(
                            'Tienda',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 25,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: PopColors.navy,
                            ),
                          ),
                          SizedBox(height: 4),
                          PopText(
                            'Personaliza tu juego',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CoinPill(wallet: wallet),
                  ],
                ),
              ),
              if (testCoinControlsVisible) ...[
                const SizedBox(height: 10),
                _ShopBalanceCard(
                  wallet: wallet,
                  onAdd: () => _showAddCoinsDialog(context, wallet),
                ),
              ],
              if (shopRewardedCoinsEnabled && ads?.supported == true) ...[
                const SizedBox(height: 10),
                _ShopRewardedCoinsCard(
                  controller: ads!,
                  onWatch: _watchRewardedAd,
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: PopColors.yellow.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: PopColors.yellow.withValues(alpha: .7),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 20,
                      color: Color(0xFF8A6300),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: PopText(
                        'Personaliza tu juego sin ventajas competitivas.',
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.15,
                          color: PopColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('shop-filters'),
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = category == selectedCategory;
                    return ChoiceChip(
                      selected: selected,
                      showCheckmark: false,
                      label: PopText(category),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : PopColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                      selectedColor: PopColors.blue,
                      backgroundColor: Colors.white.withValues(alpha: .88),
                      side: BorderSide(
                        color: selected
                            ? PopColors.blue
                            : const Color(0xFFDDE3EA),
                      ),
                      onSelected: (_) {
                        setState(() => selectedCategory = category);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final count = box.maxWidth >= 940
                      ? 4
                      : box.maxWidth >= 620
                      ? 3
                      : box.maxWidth >= 330
                      ? 2
                      : 1;
                  return GridView.builder(
                    key: const ValueKey('shop-grid'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: count == 1 ? 270 : 282,
                    ),
                    itemCount: visibleItems.length,
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return _ShopItemCard(
                        item: item,
                        owned: wallet.isOwned(item.id),
                        equipped: wallet.isEquipped(item.id),
                        onPreview: () => _showProductPreview(item),
                        onAction: () => _handleProduct(item.id),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

String _shopCategoryLabel(CosmeticCategory category) => switch (category) {
  CosmeticCategory.theme => 'Temas',
  CosmeticCategory.dice => 'Dados',
  CosmeticCategory.tokens => 'Fichas',
  CosmeticCategory.avatar => 'Avatares',
};

String _shopRarityLabel(CosmeticRarity rarity) => switch (rarity) {
  CosmeticRarity.basic => 'BÁSICO',
  CosmeticRarity.common => 'ESPECIAL',
  CosmeticRarity.rare => 'RARO',
  CosmeticRarity.epic => 'ÉPICO',
  CosmeticRarity.legendary => 'LEGENDARIO',
};

Color _shopRarityColor(CosmeticRarity rarity) => switch (rarity) {
  CosmeticRarity.basic => const Color(0xFF667085),
  CosmeticRarity.common => PopColors.green,
  CosmeticRarity.rare => PopColors.blue,
  CosmeticRarity.epic => const Color(0xFF7B61FF),
  CosmeticRarity.legendary => const Color(0xFFB77900),
};

Color _shopProductColor(WalletProduct product) => switch (product.category) {
  CosmeticCategory.theme => themeVisualSpecFor(product.id).framePrimaryColor,
  CosmeticCategory.dice => diceVisualSpecFor(product.id).faceColors.first,
  CosmeticCategory.tokens => Color.lerp(
    tokenVisualSpecFor(product.id).stageColor,
    PopColors.navy,
    .46,
  )!,
  CosmeticCategory.avatar => avatarVisualSpecFor(
    product.id,
  ).backgroundColors.first,
};

class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.onPreview,
    required this.onAction,
  });

  final WalletProduct item;
  final bool owned;
  final bool equipped;
  final VoidCallback onPreview;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = _shopProductColor(item);
    final rarityColor = _shopRarityColor(item.rarity);
    return Card(
      elevation: equipped ? 10 : 6,
      shadowColor: (equipped ? PopColors.green : color).withValues(alpha: .28),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: equipped ? PopColors.green : Colors.white,
          width: equipped ? 3 : 2,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: .34),
              color.withValues(alpha: .11),
              Colors.white,
            ],
            stops: const [0, .48, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 1),
                      child: _ShopProductPreview(product: item),
                    ),
                  ),
                  Positioned(
                    top: 9,
                    right: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: rarityColor.withValues(alpha: .32),
                        ),
                      ),
                      child: PopText(
                        _shopRarityLabel(item.rarity),
                        style: TextStyle(
                          color: rarityColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 34,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PopText(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.04,
                          fontWeight: FontWeight.w900,
                          color: PopColors.navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: _AutoFitSingleLineText(
                          item.description,
                          alignment: Alignment.centerLeft,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: PopColors.yellow,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: PopText(
                          item.price == 0
                              ? 'GRATIS'
                              : '🪙 ${_formatCoins(item.price)}',
                          style: const TextStyle(
                            color: PopColors.navy,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: ValueKey('shop-preview-button-${item.id}'),
                            onPressed: onPreview,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              foregroundColor: PopColors.navy,
                              side: BorderSide(
                                color: color.withValues(alpha: .55),
                              ),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: PopText(
                                'PREVIEW',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.icon(
                            key: ValueKey('shop-action-${item.id}'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              backgroundColor: equipped
                                  ? PopColors.green
                                  : color,
                              disabledBackgroundColor: PopColors.green,
                            ),
                            onPressed: equipped ? null : onAction,
                            icon: Icon(
                              equipped
                                  ? Icons.check_circle_rounded
                                  : owned
                                  ? Icons.style_rounded
                                  : Icons.shopping_bag_rounded,
                              size: 16,
                            ),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: PopText(
                                equipped
                                    ? 'EN USO'
                                    : owned
                                    ? 'USAR'
                                    : 'COMPRAR',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProductPreview extends StatelessWidget {
  const _ShopProductPreview({required this.product, this.large = false});

  final WalletProduct product;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = _shopProductColor(product);
    final diceStyle = product.category == CosmeticCategory.dice
        ? diceVisualSpecFor(product.id)
        : null;
    final stageColor = switch (product.category) {
      CosmeticCategory.theme => themeVisualSpecFor(product.id).stageColor,
      CosmeticCategory.dice => diceStyle!.stageColor,
      CosmeticCategory.tokens => tokenVisualSpecFor(product.id).stageColor,
      CosmeticCategory.avatar => avatarVisualSpecFor(
        product.id,
      ).backgroundColors.last,
    };
    return RepaintBoundary(
      key: ValueKey('shop-preview-${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              stageColor.withValues(alpha: .96),
              Color.lerp(stageColor, Colors.white, .26)!,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .78)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: .22),
              blurRadius: 9,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: switch (product.category) {
            CosmeticCategory.dice => _ShopDicePreview(
              style: diceStyle!,
              large: large,
            ),
            CosmeticCategory.theme => _ShopThemePreview(
              themeId: product.id,
              large: large,
            ),
            CosmeticCategory.tokens => _ShopTokenPreview(
              styleId: product.id,
              large: large,
            ),
            CosmeticCategory.avatar => _ShopAvatarPreview(
              avatarId: product.id,
              large: large,
            ),
          },
        ),
      ),
    );
  }
}

class _ShopDicePreview extends StatelessWidget {
  const _ShopDicePreview({required this.style, this.large = false});

  final DiceVisualSpec style;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final dieSize = math
            .min(box.maxWidth * .39, box.maxHeight * .54)
            .clamp(38.0, large ? 118.0 : 66.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DiceMotifPainter(
                  motif: style.motif,
                  accent: style.borderColor.withValues(alpha: .34),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(dieSize * .27, -dieSize * .10),
              child: Transform.rotate(
                angle: .13,
                child: _ShopDieVisual(
                  key: ValueKey('shop-die-${style.id}-1'),
                  value: 3,
                  size: dieSize * .87,
                  faceColor: style.faceColors[1],
                  style: style,
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(-dieSize * .25, dieSize * .13),
              child: Transform.rotate(
                angle: -.12,
                child: _ShopDieVisual(
                  key: ValueKey('shop-die-${style.id}-0'),
                  value: 5,
                  size: dieSize,
                  faceColor: style.faceColors[0],
                  style: style,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShopDieVisual extends StatelessWidget {
  const _ShopDieVisual({
    super.key,
    required this.value,
    required this.size,
    required this.faceColor,
    required this.style,
  });

  final int value;
  final double size;
  final Color faceColor;
  final DiceVisualSpec style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(faceColor, Colors.white, .34)!,
            faceColor,
            Color.lerp(faceColor, PopColors.navy, .32)!,
          ],
        ),
        borderRadius: BorderRadius.circular(size * .23),
        border: Border.all(color: style.borderColor, width: size * .055),
        boxShadow: [
          BoxShadow(
            color: style.glowColor,
            blurRadius: size * .25,
            spreadRadius: size * .015,
            offset: Offset(0, size * .12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .26),
            blurRadius: size * .12,
            offset: Offset(0, size * .13),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DiceMotifPainter(
                motif: style.motif,
                accent: style.borderColor.withValues(alpha: .20),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _PipDiePainter(value, color: style.pipColor),
            ),
          ),
          Positioned(
            left: size * .14,
            top: size * .10,
            right: size * .20,
            height: size * .16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: .42),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the theme for one player's goal triangle. The center shares an
/// outline, but none of its four triangles inherits another player's theme.
@visibleForTesting
ThemeVisualSpec boardCenterThemeForPlayerThemeIds(
  Map<PlayerColor, String?> playerThemeIds,
  PlayerColor owner,
) => themeVisualSpecFor(playerThemeIds[owner]);

@visibleForTesting
ThemeVisualSpec shopThemePreviewThemeForPlayer(
  String themeId,
  PlayerColor color,
) => color == PlayerColor.red
    ? themeVisualSpecFor(themeId)
    : defaultThemeVisualSpec;

@visibleForTesting
String shopThemePreviewTokenStyleIdForPlayer(
  String themeId,
  PlayerColor color,
) =>
    matchingTokenStyleIdForTheme(
      shopThemePreviewThemeForPlayer(themeId, color).id,
    ) ??
    'tokens_default';

/// Builds the exact board painter used by a match with a quiet, deterministic
/// store state. Keeping the real 20×20 geometry here makes the theme preview a
/// faithful miniature instead of a decorative approximation.
@visibleForTesting
CustomPainter shopThemeBoardPreviewPainter({
  required GameEngine engine,
  required String themeId,
  double progress = .38,
  bool compactPhone = false,
  String localPlayerLabel = 'TÚ',
  String languageCode = 'es',
}) {
  final tokenStyleId = shopThemePreviewTokenStyleIdForPlayer(
    themeId,
    PlayerColor.red,
  );
  return _ParcheseBoardPainter(
    engine,
    compactPhone: compactPhone,
    selectedToken: null,
    animatedCells: _displayTokenCells(engine, compactPhone: compactPhone),
    pulse: .24,
    cubeSpin: progress,
    effectProgress: 0,
    playerThemeIds: {PlayerColor.red: themeId},
    revealAllTraps: false,
    robotTokens: false,
    robotTokenColors: const <PlayerColor>{},
    tokenStyleIds: {PlayerColor.red: tokenStyleId},
    playerLabels: const <PlayerColor, String>{},
    localPlayerLabel: localPlayerLabel,
    languageCode: languageCode,
    movePreviews: const <MoveDestinationPreview>[],
  );
}

class _ShopThemePreview extends StatefulWidget {
  const _ShopThemePreview({required this.themeId, this.large = false});

  final String themeId;
  final bool large;

  @override
  State<_ShopThemePreview> createState() => _ShopThemePreviewState();
}

class _ShopThemePreviewState extends State<_ShopThemePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final GameEngine previewEngine;
  bool motionConfigured = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );
    previewEngine = GameEngine(mode: GameMode.traditional);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionConfigured) return;
    motionConfigured = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      controller.value = .42;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    previewEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = themeVisualSpecFor(widget.themeId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            math.min(constraints.maxWidth, constraints.maxHeight) *
            (widget.large ? .95 : .90);
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) => RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  key: ValueKey('shop-theme-scene-${widget.themeId}'),
                  painter: ThemeScenePainter(
                    theme: defaultThemeVisualSpec,
                    progress: controller.value,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .12),
                        theme.framePrimaryColor.withValues(alpha: .10),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: SizedBox.square(
                    dimension: side,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: ValueKey(
                          'shop-theme-board-${widget.themeId}'
                          '${widget.large ? '-large' : ''}',
                        ),
                        painter: shopThemeBoardPreviewPainter(
                          engine: previewEngine,
                          themeId: widget.themeId,
                          progress: controller.value,
                          compactPhone: _usesCompactPhoneBoard(context),
                          localPlayerLabel: appTranslate(context, 'TÚ'),
                          languageCode: appLanguageCodeOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShopTokenPreview extends StatelessWidget {
  const _ShopTokenPreview({required this.styleId, this.large = false});

  final String styleId;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = tokenVisualSpecFor(styleId);
    const colors = [
      PopColors.blue,
      PopColors.yellow,
      PopColors.red,
      PopColors.green,
    ];
    final tokenSize = large ? 70.0 : 38.0;
    final spacing = large ? 12.0 : 8.0;
    return Center(
      child: SizedBox(
        width: tokenSize * 2 + spacing,
        height: tokenSize * 2 + spacing,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: colors.length,
          itemBuilder: (context, index) => _MiniCosmeticToken(
            key: ValueKey('shop-token-$styleId-$index'),
            color: colors[index],
            style: style,
            size: tokenSize,
          ),
        ),
      ),
    );
  }
}

class _MiniCosmeticToken extends StatelessWidget {
  const _MiniCosmeticToken({
    super.key,
    required this.color,
    required this.style,
    this.size = 38,
  });

  final Color color;
  final TokenVisualSpec style;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color.lerp(color, Colors.white, .30)!, color],
      ),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: [
        BoxShadow(
          color: Color.alphaBlend(
            style.glowColor,
            color.withValues(alpha: .24),
          ),
          blurRadius: 9,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: CustomPaint(painter: _MiniTokenMarkPainter(style, teamColor: color)),
  );
}

void _paintNeonPulseTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  canvas.drawCircle(
    center,
    scale * .27,
    Paint()
      ..color = style.glowColor.withValues(alpha: .32)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .07),
  );
  final ring = Paint()
    ..color = style.detailColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = scale * .06
    ..strokeCap = StrokeCap.round;
  final ringBounds = Rect.fromCircle(center: center, radius: scale * .23);
  for (var index = 0; index < 4; index++) {
    canvas.drawArc(
      ringBounds,
      index * math.pi / 2 + .12,
      math.pi / 2 - .34,
      false,
      ring,
    );
    final angle = index * math.pi / 2;
    final inner = center + Offset.fromDirection(angle, scale * .115);
    final outer = center + Offset.fromDirection(angle, scale * .285);
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..color = index.isEven ? style.highlightColor : style.outlineColor
        ..strokeWidth = scale * .045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      outer,
      scale * .037,
      Paint()..color = style.highlightColor,
    );
  }
  canvas.drawCircle(center, scale * .115, Paint()..color = style.outlineColor);
  canvas.drawCircle(center, scale * .075, Paint()..color = teamColor);
  canvas.drawCircle(
    center + Offset(-scale * .025, -scale * .025),
    scale * .022,
    Paint()..color = style.highlightColor,
  );
}

void _paintSolarScarabTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  Path wing({required bool left}) {
    final direction = left ? -1.0 : 1.0;
    return Path()
      ..moveTo(center.dx + direction * scale * .035, center.dy - scale * .08)
      ..quadraticBezierTo(
        center.dx + direction * scale * .33,
        center.dy - scale * .23,
        center.dx + direction * scale * .30,
        center.dy + scale * .05,
      )
      ..quadraticBezierTo(
        center.dx + direction * scale * .25,
        center.dy + scale * .23,
        center.dx + direction * scale * .07,
        center.dy + scale * .18,
      )
      ..close();
  }

  final leftWing = wing(left: true);
  final rightWing = wing(left: false);
  final wingPaint = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [style.highlightColor, style.detailColor],
    ).createShader(Rect.fromCircle(center: center, radius: scale * .34));
  canvas.drawPath(leftWing, wingPaint);
  canvas.drawPath(rightWing, wingPaint);
  final outline = Paint()
    ..color = style.outlineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = scale * .035
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(leftWing, outline);
  canvas.drawPath(rightWing, outline);
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: center + Offset(0, scale * .055),
      width: scale * .15,
      height: scale * .40,
    ),
    Radius.circular(scale * .08),
  );
  canvas.drawRRect(body, Paint()..color = style.detailColor);
  canvas.drawRRect(body, outline);
  canvas.drawCircle(
    center - Offset(0, scale * .20),
    scale * .105,
    Paint()..color = style.highlightColor,
  );
  canvas.drawCircle(
    center - Offset(0, scale * .20),
    scale * .053,
    Paint()..color = teamColor,
  );
  canvas.drawLine(
    center + Offset(-scale * .24, scale * .02),
    center + Offset(-scale * .08, scale * .08),
    outline,
  );
  canvas.drawLine(
    center + Offset(scale * .24, scale * .02),
    center + Offset(scale * .08, scale * .08),
    outline,
  );
}

void _paintJungleTotemTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  void leaf(double rotation, double xOffset) {
    canvas.save();
    canvas.translate(center.dx + scale * xOffset, center.dy - scale * .24);
    canvas.rotate(rotation);
    final leafPath = Path()
      ..moveTo(0, -scale * .17)
      ..quadraticBezierTo(scale * .13, -scale * .04, 0, scale * .13)
      ..quadraticBezierTo(-scale * .13, -scale * .04, 0, -scale * .17)
      ..close();
    canvas.drawPath(leafPath, Paint()..color = style.highlightColor);
    canvas.drawLine(
      Offset(0, -scale * .11),
      Offset(0, scale * .09),
      Paint()
        ..color = style.detailColor
        ..strokeWidth = scale * .025,
    );
    canvas.restore();
  }

  leaf(-.55, -.13);
  leaf(0, 0);
  leaf(.55, .13);
  final mask = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: center + Offset(0, scale * .055),
      width: scale * .40,
      height: scale * .47,
    ),
    Radius.circular(scale * .12),
  );
  canvas.drawRRect(
    mask,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [style.highlightColor, style.detailColor],
      ).createShader(mask.outerRect),
  );
  canvas.drawRRect(
    mask,
    Paint()
      ..color = style.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .04,
  );
  for (final dx in const [-.105, .105]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(scale * dx, 0),
          width: scale * .10,
          height: scale * .065,
        ),
        Radius.circular(scale * .025),
      ),
      Paint()..color = teamColor,
    );
  }
  final nose = Path()
    ..moveTo(center.dx, center.dy + scale * .025)
    ..lineTo(center.dx + scale * .055, center.dy + scale * .13)
    ..lineTo(center.dx - scale * .055, center.dy + scale * .13)
    ..close();
  canvas.drawPath(nose, Paint()..color = teamColor.withValues(alpha: .78));
  canvas.drawLine(
    center + Offset(-scale * .10, scale * .18),
    center + Offset(scale * .10, scale * .18),
    Paint()
      ..color = teamColor
      ..strokeWidth = scale * .035
      ..strokeCap = StrokeCap.round,
  );
}

void _paintPixelBlasterTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  final pixel = scale * .075;
  const primaryPixels = [
    Offset(0, -3),
    Offset(-1, -2),
    Offset(0, -2),
    Offset(1, -2),
    Offset(-2, -1),
    Offset(-1, -1),
    Offset(0, -1),
    Offset(1, -1),
    Offset(2, -1),
    Offset(-2, 0),
    Offset(-1, 0),
    Offset(0, 0),
    Offset(1, 0),
    Offset(2, 0),
    Offset(-3, 1),
    Offset(-2, 1),
    Offset(2, 1),
    Offset(3, 1),
  ];
  for (final point in primaryPixels) {
    final rect = Rect.fromCenter(
      center: center + Offset(point.dx * pixel, point.dy * pixel),
      width: pixel * .92,
      height: pixel * .92,
    );
    canvas.drawRect(
      rect.shift(Offset(0, pixel * .22)),
      Paint()..color = Colors.black.withValues(alpha: .22),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = point.dy <= -2 ? style.highlightColor : style.detailColor,
    );
  }
  for (final dx in const [-1.0, 1.0]) {
    canvas.drawRect(
      Rect.fromCenter(
        center: center + Offset(dx * pixel, -pixel * .85),
        width: pixel * .72,
        height: pixel * .72,
      ),
      Paint()..color = teamColor,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: center + Offset(dx * pixel * 2, pixel * 2.05),
        width: pixel * .72,
        height: pixel * 1.15,
      ),
      Paint()..color = style.outlineColor,
    );
  }
}

void _paintAuroraShardTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  final mainShard = Path()
    ..moveTo(center.dx, center.dy - scale * .32)
    ..lineTo(center.dx + scale * .18, center.dy - scale * .05)
    ..lineTo(center.dx + scale * .08, center.dy + scale * .30)
    ..lineTo(center.dx - scale * .13, center.dy + scale * .20)
    ..lineTo(center.dx - scale * .18, center.dy - scale * .06)
    ..close();
  canvas.drawPath(
    mainShard,
    Paint()
      ..color = style.glowColor.withValues(alpha: .48)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .07),
  );
  canvas.drawPath(
    mainShard,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          style.highlightColor,
          style.detailColor,
          style.glowColor.withValues(alpha: 1),
        ],
      ).createShader(mainShard.getBounds()),
  );
  canvas.drawPath(
    mainShard,
    Paint()
      ..color = style.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .04
      ..strokeJoin = StrokeJoin.round,
  );
  final facet = Path()
    ..moveTo(center.dx, center.dy - scale * .28)
    ..lineTo(center.dx + scale * .02, center.dy + scale * .18)
    ..lineTo(center.dx - scale * .12, center.dy + scale * .16)
    ..close();
  canvas.drawPath(facet, Paint()..color = teamColor.withValues(alpha: .42));
  for (final side in const [-1.0, 1.0]) {
    final shard = Path()
      ..moveTo(center.dx + side * scale * .25, center.dy - scale * .13)
      ..lineTo(center.dx + side * scale * .33, center.dy + scale * .06)
      ..lineTo(center.dx + side * scale * .20, center.dy + scale * .12)
      ..close();
    canvas.drawPath(shard, Paint()..color = style.highlightColor);
  }
}

void _paintCosmicCoreTokenMark(
  Canvas canvas,
  Offset center,
  double scale,
  TokenVisualSpec style,
  Color teamColor,
) {
  final medallionRadius = scale * .235;
  canvas.drawCircle(
    center,
    scale * .265,
    Paint()
      ..color = style.glowColor.withValues(alpha: .32)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .07),
  );
  canvas.drawCircle(
    center,
    medallionRadius,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.38, -.42),
        radius: 1.05,
        colors: [
          Color.lerp(teamColor, Colors.white, .32)!,
          teamColor,
          style.stageColor,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: medallionRadius)),
  );
  canvas.drawCircle(
    center,
    medallionRadius,
    Paint()
      ..color = style.detailColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .034,
  );

  // Partial, tilted arcs suggest an orbit without enclosing the core in the
  // eye-shaped oval used by the first version of this piece.
  final orbitRect = Rect.fromCenter(
    center: center,
    width: scale * .53,
    height: scale * .36,
  );
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(-math.pi / 7);
  canvas.translate(-center.dx, -center.dy);
  final orbitPaint = Paint()
    ..color = style.detailColor.withValues(alpha: .92)
    ..style = PaintingStyle.stroke
    ..strokeWidth = scale * .026
    ..strokeCap = StrokeCap.round;
  canvas.drawArc(orbitRect, .18, math.pi * .72, false, orbitPaint);
  canvas.drawArc(orbitRect, math.pi * 1.12, math.pi * .63, false, orbitPaint);
  canvas.restore();

  canvas.drawArc(
    Rect.fromCircle(center: center, radius: medallionRadius * .78),
    math.pi * 1.10,
    math.pi * .48,
    false,
    Paint()
      ..color = style.highlightColor.withValues(alpha: .78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .022
      ..strokeCap = StrokeCap.round,
  );

  final star = Path();
  for (var point = 0; point < 8; point++) {
    final angle = -math.pi / 2 + point * math.pi / 4;
    final radius = scale * (point.isEven ? .125 : .045);
    final position = center + Offset.fromDirection(angle, radius);
    if (point == 0) {
      star.moveTo(position.dx, position.dy);
    } else {
      star.lineTo(position.dx, position.dy);
    }
  }
  star.close();
  canvas.drawPath(
    star.shift(Offset(0, scale * .018)),
    Paint()..color = Colors.black.withValues(alpha: .24),
  );
  canvas.drawPath(
    star,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [style.highlightColor, style.detailColor],
      ).createShader(star.getBounds()),
  );

  canvas.drawCircle(
    center + Offset(scale * .225, -scale * .115),
    scale * .039,
    Paint()..color = style.detailColor,
  );
  canvas.drawCircle(
    center + Offset(scale * .225, -scale * .115),
    scale * .039,
    Paint()
      ..color = style.detailColor.withValues(alpha: .44)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .035),
  );
}

class _MiniTokenMarkPainter extends CustomPainter {
  const _MiniTokenMarkPainter(this.style, {required this.teamColor});

  final TokenVisualSpec style;
  final Color teamColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = size.shortestSide;
    final fill = Paint()..color = style.detailColor;
    final accent = Paint()..color = style.highlightColor;
    final outline = Paint()
      ..color = style.outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale * .055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (style.motif) {
      case TokenMotif.star:
        final star = Path();
        for (var index = 0; index < 10; index++) {
          final angle = -math.pi / 2 + index * math.pi / 5;
          final radius = scale * (index.isEven ? .28 : .125);
          final point = center + Offset.fromDirection(angle, radius);
          if (index == 0) {
            star.moveTo(point.dx, point.dy);
          } else {
            star.lineTo(point.dx, point.dy);
          }
        }
        star.close();
        canvas.drawPath(star, fill);
        break;
      case TokenMotif.robot:
        final face = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(0, scale * .02),
            width: scale * .52,
            height: scale * .38,
          ),
          Radius.circular(scale * .10),
        );
        canvas.drawRRect(face, fill);
        canvas.drawLine(
          center + Offset(0, -scale * .19),
          center + Offset(0, -scale * .30),
          outline,
        );
        canvas.drawCircle(
          center + Offset(0, -scale * .31),
          scale * .045,
          accent,
        );
        for (final dx in const [-.13, .13]) {
          canvas.drawCircle(
            center + Offset(scale * dx, -scale * .02),
            scale * .045,
            Paint()..color = const Color(0xFF17284D),
          );
        }
        canvas.drawLine(
          center + Offset(-scale * .11, scale * .11),
          center + Offset(scale * .11, scale * .11),
          outline,
        );
        break;
      case TokenMotif.crystal:
        final gem = Path()
          ..moveTo(center.dx, center.dy - scale * .30)
          ..lineTo(center.dx + scale * .25, center.dy - scale * .04)
          ..lineTo(center.dx + scale * .12, center.dy + scale * .27)
          ..lineTo(center.dx - scale * .12, center.dy + scale * .27)
          ..lineTo(center.dx - scale * .25, center.dy - scale * .04)
          ..close();
        canvas.drawPath(
          gem,
          Paint()
            ..shader = LinearGradient(
              colors: [style.highlightColor, style.detailColor],
            ).createShader(gem.getBounds()),
        );
        canvas.drawPath(gem, outline);
        canvas.drawLine(
          center + Offset(-scale * .20, -scale * .03),
          center + Offset(scale * .11, scale * .25),
          outline,
        );
        break;
      case TokenMotif.rocket:
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.pi / 4);
        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: scale * .26,
            height: scale * .58,
          ),
          Radius.circular(scale * .14),
        );
        canvas.drawRRect(
          body,
          Paint()
            ..shader = LinearGradient(
              colors: [style.highlightColor, style.detailColor],
            ).createShader(body.outerRect),
        );
        canvas.drawRRect(body, outline);
        canvas.drawCircle(
          Offset(0, -scale * .09),
          scale * .065,
          Paint()..color = teamColor,
        );
        final flame = Path()
          ..moveTo(-scale * .07, scale * .30)
          ..quadraticBezierTo(0, scale * .48, scale * .07, scale * .30)
          ..close();
        canvas.drawPath(flame, Paint()..color = const Color(0xFFFF7A28));
        canvas.restore();
        break;
      case TokenMotif.crown:
        final crown = Path()
          ..moveTo(center.dx - scale * .28, center.dy + scale * .18)
          ..lineTo(center.dx - scale * .22, center.dy - scale * .20)
          ..lineTo(center.dx - scale * .07, center.dy - scale * .04)
          ..lineTo(center.dx, center.dy - scale * .28)
          ..lineTo(center.dx + scale * .09, center.dy - scale * .04)
          ..lineTo(center.dx + scale * .25, center.dy - scale * .20)
          ..lineTo(center.dx + scale * .28, center.dy + scale * .18)
          ..close();
        canvas.drawPath(
          crown,
          Paint()
            ..shader = LinearGradient(
              colors: [style.highlightColor, style.detailColor],
            ).createShader(crown.getBounds()),
        );
        canvas.drawPath(crown, outline);
        break;
      case TokenMotif.neonPulse:
        _paintNeonPulseTokenMark(canvas, center, scale, style, teamColor);
        break;
      case TokenMotif.solarScarab:
        _paintSolarScarabTokenMark(canvas, center, scale, style, teamColor);
        break;
      case TokenMotif.jungleTotem:
        _paintJungleTotemTokenMark(canvas, center, scale, style, teamColor);
        break;
      case TokenMotif.pixelBlaster:
        _paintPixelBlasterTokenMark(canvas, center, scale, style, teamColor);
        break;
      case TokenMotif.auroraShard:
        _paintAuroraShardTokenMark(canvas, center, scale, style, teamColor);
        break;
      case TokenMotif.cosmicCore:
        _paintCosmicCoreTokenMark(canvas, center, scale, style, teamColor);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTokenMarkPainter oldDelegate) =>
      oldDelegate.style != style || oldDelegate.teamColor != teamColor;
}

class _ShopAvatarPreview extends StatelessWidget {
  const _ShopAvatarPreview({required this.avatarId, this.large = false});

  final String avatarId;
  final bool large;

  @override
  Widget build(BuildContext context) => Center(
    child: _AvatarArt(
      key: ValueKey('shop-avatar-$avatarId'),
      avatarId: avatarId,
      size: large ? 176 : 92,
    ),
  );
}

class _AvatarArt extends StatelessWidget {
  const _AvatarArt({
    super.key,
    required this.avatarId,
    required this.size,
    this.withFrame = true,
  });

  final String? avatarId;
  final double size;
  final bool withFrame;

  @override
  Widget build(BuildContext context) {
    final style = avatarVisualSpecFor(avatarId);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: style.backgroundColors,
          ),
          shape: BoxShape.circle,
          border: withFrame
              ? Border.all(
                  color: style.borderColor,
                  width: math.max(1.5, size * .055),
                )
              : null,
          boxShadow: withFrame
              ? [
                  BoxShadow(
                    color: style.glowColor,
                    blurRadius: size * .17,
                    offset: Offset(0, size * .075),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: size * .08,
                    offset: Offset(0, size * .055),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(size * .14),
          child: CustomPaint(painter: _AvatarArtPainter(style)),
        ),
      ),
    );
  }
}

class _AvatarArtPainter extends CustomPainter {
  const _AvatarArtPainter(this.style);

  final AvatarVisualSpec style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final unit = size.shortestSide;
    final primary = Paint()..color = style.primaryColor;
    final accent = Paint()..color = style.accentColor;
    final dark = Paint()..color = const Color(0xFF17284D);
    final line = Paint()
      ..color = style.accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * .075)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (style.motif) {
      case AvatarMotif.controller:
        final controller = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(0, unit * .05),
            width: unit * .84,
            height: unit * .50,
          ),
          Radius.circular(unit * .22),
        );
        canvas.drawRRect(controller, primary);
        canvas.drawLine(
          center + Offset(-unit * .24, unit * .05),
          center + Offset(-unit * .06, unit * .05),
          line,
        );
        canvas.drawLine(
          center + Offset(-unit * .15, -unit * .04),
          center + Offset(-unit * .15, unit * .14),
          line,
        );
        canvas.drawCircle(
          center + Offset(unit * .17, unit * .01),
          unit * .065,
          accent,
        );
        canvas.drawCircle(
          center + Offset(unit * .30, unit * .11),
          unit * .055,
          accent,
        );
        break;
      case AvatarMotif.astronaut:
        canvas.drawCircle(center, unit * .40, primary);
        final visor = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center - Offset(0, unit * .04),
            width: unit * .59,
            height: unit * .34,
          ),
          Radius.circular(unit * .17),
        );
        canvas.drawRRect(
          visor,
          Paint()
            ..shader = LinearGradient(
              colors: [style.accentColor, const Color(0xFF2474E5)],
            ).createShader(visor.outerRect),
        );
        canvas.drawRRect(
          visor,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * .045,
        );
        canvas.drawCircle(
          center + Offset(unit * .12, -unit * .08),
          unit * .035,
          Paint()..color = Colors.white.withValues(alpha: .85),
        );
        canvas.drawLine(
          center + Offset(-unit * .17, unit * .27),
          center + Offset(unit * .17, unit * .27),
          Paint()
            ..color = style.accentColor
            ..strokeWidth = unit * .07
            ..strokeCap = StrokeCap.round,
        );
        break;
      case AvatarMotif.ninja:
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: unit * .72,
            height: unit * .82,
          ),
          primary,
        );
        final eyes = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center - Offset(0, unit * .04),
            width: unit * .58,
            height: unit * .19,
          ),
          Radius.circular(unit * .09),
        );
        canvas.drawRRect(eyes, accent);
        for (final dx in const [-.14, .14]) {
          canvas.drawOval(
            Rect.fromCenter(
              center: center + Offset(unit * dx, -unit * .035),
              width: unit * .10,
              height: unit * .055,
            ),
            dark,
          );
        }
        canvas.drawLine(
          center + Offset(-unit * .30, unit * .20),
          center + Offset(unit * .28, unit * .08),
          line,
        );
        break;
      case AvatarMotif.robot:
        final head = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(0, unit * .04),
            width: unit * .70,
            height: unit * .58,
          ),
          Radius.circular(unit * .14),
        );
        canvas.drawRRect(head, primary);
        canvas.drawLine(
          center - Offset(0, unit * .28),
          center - Offset(0, unit * .43),
          line,
        );
        canvas.drawCircle(center - Offset(0, unit * .45), unit * .06, accent);
        for (final dx in const [-.18, .18]) {
          canvas.drawCircle(
            center + Offset(unit * dx, -unit * .03),
            unit * .075,
            accent,
          );
          canvas.drawCircle(
            center + Offset(unit * dx, -unit * .03),
            unit * .03,
            dark,
          );
        }
        canvas.drawLine(
          center + Offset(-unit * .18, unit * .20),
          center + Offset(unit * .18, unit * .20),
          Paint()
            ..color = const Color(0xFF17284D)
            ..strokeWidth = unit * .055
            ..strokeCap = StrokeCap.round,
        );
        break;
      case AvatarMotif.explorer:
        canvas.drawCircle(center, unit * .39, primary);
        canvas.drawCircle(center, unit * .29, accent);
        canvas.drawCircle(
          center,
          unit * .29,
          Paint()
            ..color = style.primaryColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * .055,
        );
        final needle = Path()
          ..moveTo(center.dx, center.dy - unit * .25)
          ..lineTo(center.dx + unit * .10, center.dy + unit * .05)
          ..lineTo(center.dx, center.dy + unit * .25)
          ..lineTo(center.dx - unit * .10, center.dy - unit * .05)
          ..close();
        canvas.drawPath(
          needle,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [PopColors.red, style.primaryColor],
            ).createShader(needle.getBounds()),
        );
        canvas.drawCircle(center, unit * .055, dark);
        break;
      case AvatarMotif.comet:
        final tail = Path()
          ..moveTo(center.dx - unit * .38, center.dy + unit * .24)
          ..quadraticBezierTo(
            center.dx - unit * .05,
            center.dy + unit * .12,
            center.dx + unit * .12,
            center.dy - unit * .14,
          )
          ..quadraticBezierTo(
            center.dx - unit * .12,
            center.dy + unit * .02,
            center.dx - unit * .45,
            center.dy + unit * .04,
          )
          ..close();
        canvas.drawPath(tail, accent);
        canvas.drawCircle(
          center + Offset(unit * .13, -unit * .10),
          unit * .30,
          primary,
        );
        for (final dx in const [.06, .22]) {
          canvas.drawCircle(
            center + Offset(unit * dx, -unit * .14),
            unit * .035,
            dark,
          );
        }
        canvas.drawArc(
          Rect.fromCenter(
            center: center + Offset(unit * .14, -unit * .03),
            width: unit * .20,
            height: unit * .14,
          ),
          .12,
          math.pi - .24,
          false,
          Paint()
            ..color = const Color(0xFF17284D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * .035,
        );
        break;
      case AvatarMotif.axolotl:
        for (final direction in const [-1.0, 1.0]) {
          for (var index = -1; index <= 1; index++) {
            final start =
                center + Offset(direction * unit * .28, index * unit * .13);
            canvas.drawLine(
              start,
              start + Offset(direction * unit * .19, index * unit * .055),
              Paint()
                ..color = style.primaryColor
                ..strokeWidth = unit * .10
                ..strokeCap = StrokeCap.round,
            );
          }
        }
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: unit * .66,
            height: unit * .58,
          ),
          primary,
        );
        for (final dx in const [-.16, .16]) {
          canvas.drawCircle(
            center + Offset(unit * dx, -unit * .06),
            unit * .045,
            dark,
          );
        }
        canvas.drawArc(
          Rect.fromCenter(
            center: center + Offset(0, unit * .08),
            width: unit * .24,
            height: unit * .16,
          ),
          .12,
          math.pi - .24,
          false,
          Paint()
            ..color = const Color(0xFF17284D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * .035,
        );
        break;
      case AvatarMotif.toucan:
        canvas.drawOval(
          Rect.fromCenter(
            center: center + Offset(-unit * .10, unit * .07),
            width: unit * .52,
            height: unit * .72,
          ),
          primary,
        );
        canvas.drawCircle(
          center + Offset(-unit * .08, -unit * .20),
          unit * .23,
          accent,
        );
        final beak = Path()
          ..moveTo(center.dx + unit * .02, center.dy - unit * .20)
          ..quadraticBezierTo(
            center.dx + unit * .50,
            center.dy - unit * .20,
            center.dx + unit * .40,
            center.dy + unit * .02,
          )
          ..lineTo(center.dx, center.dy - unit * .02)
          ..close();
        canvas.drawPath(beak, accent);
        canvas.drawLine(
          center + Offset(unit * .03, -unit * .02),
          center + Offset(unit * .38, unit * .01),
          Paint()
            ..color = const Color(0xFF17284D)
            ..strokeWidth = unit * .028,
        );
        canvas.drawCircle(
          center + Offset(-unit * .06, -unit * .22),
          unit * .045,
          dark,
        );
        canvas.drawCircle(
          center + Offset(-unit * .075, -unit * .235),
          unit * .014,
          Paint()..color = Colors.white,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarArtPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _HomeProfileDialog extends StatelessWidget {
  const _HomeProfileDialog({
    required this.profile,
    required this.wallet,
    this.progression,
    this.tutorial,
    required this.authGateway,
    required this.analytics,
    this.onLocalDataDeleted,
    required this.onProfileChanged,
  });

  final PlayerProfile profile;
  final WalletController wallet;
  final PlayerProgressionController? progression;
  final TutorialController? tutorial;
  final PlayerAuthGateway authGateway;
  final GameAnalytics analytics;
  final Future<void> Function()? onLocalDataDeleted;
  final ValueChanged<PlayerProfile> onProfileChanged;

  Future<void> _deleteAccountAndData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.delete_forever_rounded,
          color: PopColors.red,
          size: 40,
        ),
        title: const PopText('Eliminar cuenta y datos'),
        content: const PopText(
          'Se borrarán de este dispositivo el perfil, las credenciales '
          'locales, las partidas guardadas, el progreso, las monedas, los '
          'cosméticos y las preferencias. Esta acción no se puede deshacer.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const PopText('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PopColors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const PopText('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await authGateway.deleteAccount();
    await progression?.resetLocalData();
    await wallet.resetLocalData();
    await tutorial?.resetLocalData();
    final analyticsControl = analytics;
    if (analyticsControl is AnalyticsPrivacyControl) {
      await (analyticsControl as AnalyticsPrivacyControl)
          .setAnalyticsCollectionEnabled(false);
    }
    final store = await SharedPreferences.getInstance();
    await store.clear();
    await onLocalDataDeleted?.call();
    if (onLocalDataDeleted == null) {
      onProfileChanged(PlayerProfile.guest);
    }
    if (context.mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: wallet,
    builder: (context, _) {
      final avatarId = wallet.equippedProductId(CosmeticCategory.avatar);
      final maxHeight = MediaQuery.sizeOf(context).height * .88;
      return Dialog(
        key: const ValueKey('home-profile-dialog'),
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460, maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF103779),
                    PopColors.blue,
                    Color(0xFF6947D6),
                  ],
                ),
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(32),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x6607132D),
                    blurRadius: 25,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: _HomeArcadeBackdropPainter(1),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: PopColors.yellow,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x3D000000),
                                    blurRadius: 7,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: PopColors.navy,
                              ),
                            ),
                            const SizedBox(width: 11),
                            const Expanded(
                              child: PopText(
                                'Perfil',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x55000000),
                                      offset: Offset(0, 2),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('home-profile-close'),
                              tooltip: appTranslate(context, 'Cerrar'),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: .16,
                                ),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF071B40,
                            ).withValues(alpha: .56),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .34),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 92,
                                height: 92,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFFE168),
                                      PopColors.yellow,
                                      Color(0xFFFFA924),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 7),
                                    ),
                                  ],
                                ),
                                child: _AvatarArt(
                                  key: ValueKey(
                                    'profile-avatar-${avatarId ?? 'default'}',
                                  ),
                                  avatarId: avatarId,
                                  size: 82,
                                  withFrame: false,
                                ),
                              ),
                              const SizedBox(height: 13),
                              _AutoFitSingleLineText(
                                '${profile.name} ${profile.flag}',
                                alignment: Alignment.center,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: PopColors.yellow,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: PopText(
                                  'Nv. ${profile.level}',
                                  style: const TextStyle(
                                    color: PopColors.navy,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 13),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .18),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.email_rounded,
                                      color: Colors.white70,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _AutoFitSingleLineText(
                                        profile.email,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (authGateway.currentAccount != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .13),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .22),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_user_rounded,
                                  color: PopColors.yellow,
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: PopText(
                                    'Cuenta protegida con correo y contraseña',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const ValueKey(
                                    'profile-change-password',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white),
                                  ),
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => _ChangePasswordDialog(
                                      authGateway: authGateway,
                                    ),
                                  ),
                                  icon: const Icon(Icons.password_rounded),
                                  label: const PopText('Cambiar clave'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton.icon(
                          key: const ValueKey('home-profile-edit'),
                          style: FilledButton.styleFrom(
                            backgroundColor: PopColors.yellow,
                            foregroundColor: PopColors.navy,
                            side: const BorderSide(
                              color: Colors.white,
                              width: 2,
                            ),
                            elevation: 8,
                            shadowColor: const Color(0x66000000),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.edit_rounded),
                          label: const PopText(
                            'Editar perfil',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const ValueKey('home-profile-delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: Color(0xFFFFA3A9),
                              width: 1.5,
                            ),
                          ),
                          onPressed: () => _deleteAccountAndData(context),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const PopText('Eliminar cuenta y datos'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.authGateway});

  final PlayerAuthGateway authGateway;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final formKey = GlobalKey<FormState>();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  bool obscure = true;

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.authGateway.changePassword(
        currentPassword: currentPassword.text,
        newPassword: newPassword.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: PopText('Contraseña actualizada.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is PlayerAuthException
          ? error.message
          : 'No se pudo cambiar la contraseña.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: PopText(message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('change-password-dialog'),
    icon: const Icon(Icons.password_rounded, color: PopColors.blue, size: 38),
    title: const PopText('Cambiar contraseña'),
    content: Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: currentPassword,
            obscureText: obscure,
            validator: (value) => (value ?? '').isEmpty
                ? appTranslate(context, 'Escribe tu contraseña actual.')
                : null,
            decoration: InputDecoration(
              labelText: appTranslate(context, 'Contraseña actual'),
              prefixIcon: const Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: newPassword,
            obscureText: obscure,
            validator: (value) {
              final issues = PlayerCredentialValidator.validatePassword(
                value ?? '',
                confirmation: confirmation.text,
              );
              return issues.isEmpty
                  ? null
                  : appTranslate(
                      context,
                      'Usa 8 caracteres con mayúscula, minúscula y número.',
                    );
            },
            decoration: InputDecoration(
              labelText: appTranslate(context, 'Nueva contraseña'),
              prefixIcon: const Icon(Icons.password_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: confirmation,
            obscureText: obscure,
            validator: (value) => value != newPassword.text
                ? appTranslate(context, 'Las contraseñas no coinciden.')
                : null,
            decoration: InputDecoration(
              labelText: appTranslate(context, 'Confirmar contraseña'),
              prefixIcon: const Icon(Icons.verified_user_rounded),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const PopText('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('change-password-submit'),
        onPressed: busy ? null : _submit,
        child: const PopText('Guardar clave'),
      ),
    ],
  );
}

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.profile,
    required this.onChanged,
  });
  final PlayerProfile profile;
  final ValueChanged<PlayerProfile> onChanged;

  @override
  Widget build(BuildContext context) => _PopRouteScaffold(
    child: PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PopText(
            'Perfil',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              color: PopColors.navy,
            ),
          ),
          const SizedBox(height: 18),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  PopText(profile.flag, style: const TextStyle(fontSize: 64)),
                  PopText(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  PopText(
                    profile.email,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileSetupScreen(
                          initial: profile,
                          onSaved: onChanged,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded),
                    label: const PopText('Editar perfil'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.themeId,
    this.analytics = const NoopGameAnalytics(),
  });

  final String? themeId;
  final GameAnalytics analytics;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool sound = true;
  bool music = true;
  bool vibration = true;
  bool rollGuide = true;
  bool anonymousAnalytics = false;
  DiceHandPreference diceHand = DiceHandPreference.right;
  final AppLanguageController localLanguage = AppLanguageController();
  Future<void> musicPreferenceWrites = Future<void>.value();

  @override
  void initState() {
    super.initState();
    final analytics = widget.analytics;
    if (analytics is AnalyticsPrivacyControl) {
      anonymousAnalytics =
          (analytics as AnalyticsPrivacyControl).analyticsCollectionEnabled;
    }
    localLanguage.initialize();
    _loadSettings();
  }

  @override
  void dispose() {
    localLanguage.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final store = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      sound = store.getBool('settings_sound') ?? true;
      music = store.getBool('settings_music') ?? true;
      vibration = store.getBool('settings_vibration') ?? true;
      rollGuide = store.getBool(settingsRollGuideKey) ?? true;
      diceHand = diceHandPreferenceFromStorage(
        store.getString(settingsDiceHandKey),
      );
    });
  }

  Future<void> _setPreference(String key, bool value) async {
    final store = await SharedPreferences.getInstance();
    await store.setBool(key, value);
  }

  void _updateMusicPreference(bool value) {
    setState(() => music = value);
    unawaited(gameAudio.setMusicEnabled(value));
    musicPreferenceWrites = musicPreferenceWrites
        .then((_) => _setPreference('settings_music', value))
        .catchError((Object _) {});
  }

  Future<void> _setStringPreference(String key, String value) async {
    final store = await SharedPreferences.getInstance();
    await store.setString(key, value);
  }

  Future<void> _setAnonymousAnalytics(bool value) async {
    final analytics = widget.analytics;
    if (analytics is! AnalyticsPrivacyControl) return;
    try {
      await (analytics as AnalyticsPrivacyControl)
          .setAnalyticsCollectionEnabled(value);
      if (mounted) setState(() => anonymousAnalytics = value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: PopText('No se pudo guardar la preferencia de analítica.'),
        ),
      );
    }
  }

  Future<void> _selectLanguage(
    BuildContext dialogContext,
    AppLanguageController language,
    AppLanguagePreference preference,
  ) async {
    await language.select(preference);
    if (!mounted) return;
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  }

  void _showLanguagePicker(AppLanguageController language) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('settings-language-selector'),
        icon: const Icon(
          Icons.language_rounded,
          color: PopColors.blue,
          size: 42,
        ),
        title: const PopText('Selecciona el idioma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageChoiceTile(
              key: const ValueKey('settings-language-system'),
              flag: '🌐',
              title: 'Idioma del sistema',
              subtitle: 'Usar el idioma del dispositivo',
              selected: language.preference == AppLanguagePreference.system,
              onTap: () => _selectLanguage(
                dialogContext,
                language,
                AppLanguagePreference.system,
              ),
            ),
            const SizedBox(height: 9),
            _LanguageChoiceTile(
              key: const ValueKey('settings-language-es'),
              flag: 'ES',
              title: 'Español',
              subtitle: 'Mostrar el juego en español',
              selected: language.preference == AppLanguagePreference.spanish,
              onTap: () => _selectLanguage(
                dialogContext,
                language,
                AppLanguagePreference.spanish,
              ),
            ),
            const SizedBox(height: 9),
            _LanguageChoiceTile(
              key: const ValueKey('settings-language-en'),
              flag: 'EN',
              title: 'English',
              subtitle: 'Mostrar el juego en inglés',
              selected: language.preference == AppLanguagePreference.english,
              onTap: () => _selectLanguage(
                dialogContext,
                language,
                AppLanguagePreference.english,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const PopText('Cancelar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLanguage = AppLanguageScope.maybeOf(context);
    if (appLanguage != null) return _buildSettings(context, appLanguage);
    return AppLanguageScope(
      controller: localLanguage,
      child: AnimatedBuilder(
        animation: localLanguage,
        builder: (context, _) => _buildSettings(context, localLanguage),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, AppLanguageController language) {
    final theme = themeVisualSpecFor(widget.themeId);
    return Scaffold(
      backgroundColor: theme.gameBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedThemeBackdrop(themeId: widget.themeId),
          SafeArea(
            child: PageShell(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                decoration: BoxDecoration(
                  color: PopColors.navy.withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.frameAccentColor.withValues(alpha: .95),
                    width: 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x73020B27),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton.filled(
                          key: const ValueKey('settings-back'),
                          tooltip: appTranslate(context, 'Volver'),
                          onPressed: () => Navigator.maybePop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: PopColors.yellow,
                            foregroundColor: PopColors.navy,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PopText(
                                'Ajustes',
                                style: TextStyle(
                                  fontSize: 29,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x8B000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              PopText(
                                'Controla tu experiencia de juego',
                                style: TextStyle(
                                  color: Color(0xFFD7E6FF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Card(
                      elevation: 10,
                      shadowColor: Colors.black.withValues(alpha: .32),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: theme.frameAccentColor,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            key: const ValueKey('settings-sound'),
                            value: sound,
                            onChanged: (value) {
                              setState(() => sound = value);
                              _setPreference('settings_sound', value);
                            },
                            title: const PopText('Sonido'),
                            subtitle: const PopText(
                              'Dados, fichas, capturas y efectos',
                            ),
                            secondary: const Icon(Icons.volume_up_rounded),
                          ),
                          SwitchListTile(
                            key: const ValueKey('settings-music'),
                            value: music,
                            onChanged: _updateMusicPreference,
                            title: const PopText('Música'),
                            subtitle: const PopText('Menú y música de partida'),
                            secondary: const Icon(Icons.music_note_rounded),
                          ),
                          SwitchListTile(
                            key: const ValueKey('settings-vibration'),
                            value: vibration,
                            onChanged: (value) {
                              setState(() => vibration = value);
                              _setPreference('settings_vibration', value);
                            },
                            title: const PopText('Vibración'),
                            subtitle: const PopText(
                              'Respuesta al lanzar y capturar',
                            ),
                            secondary: const Icon(Icons.vibration_rounded),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            key: const ValueKey('settings-roll-guide'),
                            value: rollGuide,
                            onChanged: (value) {
                              setState(() => rollGuide = value);
                              _setPreference(settingsRollGuideKey, value);
                            },
                            title: const PopText('Guía de lanzamiento'),
                            subtitle: const PopText(
                              'Señala los dados y las fichas disponibles',
                            ),
                            secondary: const Icon(Icons.touch_app_rounded),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: rollGuide ? 1 : .48,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.back_hand_rounded, size: 24),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            PopText(
                                              'Mano para los dados',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            PopText(
                                              'Elige cómo aparece la guía de lanzamiento',
                                              style: TextStyle(
                                                color: Color(0xFF667085),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: SegmentedButton<DiceHandPreference>(
                                      key: const ValueKey('settings-dice-hand'),
                                      showSelectedIcon: false,
                                      segments: const [
                                        ButtonSegment(
                                          value: DiceHandPreference.left,
                                          icon: Icon(Icons.back_hand_rounded),
                                          label: PopText(
                                            'IZQUIERDA',
                                            key: ValueKey(
                                              'settings-dice-hand-left',
                                            ),
                                          ),
                                        ),
                                        ButtonSegment(
                                          value: DiceHandPreference.right,
                                          icon: Icon(Icons.front_hand_rounded),
                                          label: PopText(
                                            'DERECHA',
                                            key: ValueKey(
                                              'settings-dice-hand-right',
                                            ),
                                          ),
                                        ),
                                      ],
                                      selected: {diceHand},
                                      onSelectionChanged: rollGuide
                                          ? (selection) {
                                              final value = selection.single;
                                              setState(() => diceHand = value);
                                              _setStringPreference(
                                                settingsDiceHandKey,
                                                value.name,
                                              );
                                            }
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey('settings-language'),
                            leading: const Icon(Icons.language_rounded),
                            title: const PopText('Idioma'),
                            subtitle: PopText(switch (language.preference) {
                              AppLanguagePreference.system =>
                                'Sistema · ${language.effectiveLanguageCode == 'en' ? 'English' : 'Español'}',
                              AppLanguagePreference.spanish => 'Español',
                              AppLanguagePreference.english => 'English',
                            }),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showLanguagePicker(language),
                          ),
                          if (widget.analytics is AnalyticsPrivacyControl)
                            SwitchListTile(
                              key: const ValueKey(
                                'settings-anonymous-analytics',
                              ),
                              value: anonymousAnalytics,
                              onChanged: _setAnonymousAnalytics,
                              title: const PopText('Analítica anónima'),
                              subtitle: const PopText(
                                'Ayuda a mejorar el juego sin enviar tu nombre ni correo',
                              ),
                              secondary: const Icon(Icons.insights_rounded),
                            ),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_rounded),
                            title: const PopText('Privacidad y políticas'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PoliciesScreen(),
                              ),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.menu_book_rounded),
                            title: const PopText('Ayuda y cómo jugar'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const GameGuideScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageChoiceTile extends StatelessWidget {
  const _LanguageChoiceTile({
    super.key,
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? PopColors.blue.withValues(alpha: .12) : PopColors.cloud,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? PopColors.blue : const Color(0xFFDDE3EF),
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            PopText(flag, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    title,
                    style: const TextStyle(
                      color: PopColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  PopText(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? PopColors.blue : const Color(0xFF98A2B3),
            ),
          ],
        ),
      ),
    ),
  );
}

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ads = MobileAdsScope.maybeOf(context);

    Widget buildScreen() => Scaffold(
      appBar: AppBar(title: const PopText('Privacidad y políticas')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            title: const PopText('Política de privacidad'),
            subtitle: const PopText(
              'liisgo.com/#/apps/ParchesePop/privacy',
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPrivacyPolicy(context),
          ),
          ListTile(
            title: const PopText('Términos de uso'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPolicy(
              context,
              'Términos de uso',
              'Parchís Pop es un juego de entretenimiento. Las monedas de esta '
                  'versión son virtuales, no tienen valor monetario y no '
                  'otorgan ventajas competitivas.',
            ),
          ),
          ListTile(
            title: const PopText('Política de nombres y conducta'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPolicy(
              context,
              'Nombres y conducta',
              'No se permiten nombres ofensivos, amenazas, acoso ni contenido '
                  'sexual. Los mensajes durante la partida se limitarán a '
                  'frases preaprobadas.',
            ),
          ),
          ListTile(
            title: const PopText('Publicidad y preferencias'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPolicy(
              context,
              'Publicidad',
              'Android y iOS pueden mostrar banners únicamente fuera de la '
                  'partida, la guía y la búsqueda de jugadores. Los anuncios '
                  'recompensados son voluntarios al finalizar la mesa. Jugar '
                  'otra vez, Volver al inicio y Reanudar nunca '
                  'abren anuncios. '
                  'Puedes administrar el consentimiento y las preferencias '
                  'disponibles desde esta pantalla. La versión de macOS no '
                  'muestra estos anuncios.',
            ),
          ),
          if (ads?.supported == true && ads!.privacyOptionsRequired)
            ListTile(
              key: const ValueKey('ad-privacy-options'),
              leading: const Icon(Icons.privacy_tip_rounded),
              title: const PopText('Opciones de privacidad de anuncios'),
              trailing: const Icon(Icons.chevron_right),
              onTap: ads.showPrivacyOptions,
            ),
          ListTile(
            title: const PopText('Eliminar cuenta y datos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPolicy(
              context,
              'Eliminar datos',
              'El perfil y sus credenciales se guardan localmente. Desde Mi '
                  'perfil puedes usar Eliminar cuenta y datos para borrar del '
                  'dispositivo el perfil, la contraseña protegida, las '
                  'partidas guardadas, el tutorial, el progreso, las monedas, '
                  'los cosméticos y las preferencias asociadas.',
            ),
          ),
        ],
      ),
    );

    if (ads == null) return buildScreen();
    return AnimatedBuilder(
      animation: ads,
      builder: (context, _) => buildScreen(),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse('https://liisgo.com/#/apps/ParchesePop/privacy'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: PopText('No se pudo abrir la política. Visita liisgo.com.'),
        ),
      );
    }
  }

  void _openPolicy(BuildContext context, String title, String body) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PolicyDetailScreen(title: title, body: body),
      ),
    );
  }
}

class _PolicyDetailScreen extends StatelessWidget {
  const _PolicyDetailScreen({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: PopText(title)),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Icon(
          Icons.verified_user_rounded,
          size: 56,
          color: PopColors.blue,
        ),
        const SizedBox(height: 18),
        PopText(
          body,
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: PopColors.ink,
          ),
        ),
      ],
    ),
  );
}
