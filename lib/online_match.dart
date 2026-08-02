import 'dart:collection';
import 'dart:math';

import 'cosmetic_visuals.dart';
import 'game_engine.dart';
import 'wallet.dart';

enum ParticipantKind { local, remoteHuman, virtual, humanTakenOver }

class CosmeticLoadout {
  const CosmeticLoadout({this.themeId, this.diceId, this.tokensId});

  final String? themeId;
  final String? diceId;
  final String? tokensId;

  Iterable<String> get productIds sync* {
    if (themeId != null) yield themeId!;
    if (diceId != null) yield diceId!;
    if (tokensId != null) yield tokensId!;
  }
}

class OnlineParticipant {
  const OnlineParticipant({
    required this.id,
    required this.displayName,
    required this.flag,
    required this.avatarId,
    required this.level,
    required this.color,
    required this.kind,
    required this.loadout,
  });

  final String id;
  final String displayName;
  final String flag;
  final String avatarId;
  final int level;
  final PlayerColor color;
  final ParticipantKind kind;
  final CosmeticLoadout loadout;

  bool get isLocallyControlled => kind == ParticipantKind.local;

  bool get isVirtuallyControlled =>
      kind == ParticipantKind.virtual || kind == ParticipantKind.humanTakenOver;

  bool get beganAsHuman =>
      kind == ParticipantKind.local ||
      kind == ParticipantKind.remoteHuman ||
      kind == ParticipantKind.humanTakenOver;

  OnlineParticipant copyWith({
    String? id,
    String? displayName,
    String? flag,
    String? avatarId,
    int? level,
    PlayerColor? color,
    ParticipantKind? kind,
    CosmeticLoadout? loadout,
  }) {
    return OnlineParticipant(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      flag: flag ?? this.flag,
      avatarId: avatarId ?? this.avatarId,
      level: level ?? this.level,
      color: color ?? this.color,
      kind: kind ?? this.kind,
      loadout: loadout ?? this.loadout,
    );
  }
}

class OnlineMatchSession {
  OnlineMatchSession({
    required this.matchId,
    required this.seed,
    required this.mode,
    required Iterable<OnlineParticipant> participants,
  }) : participants = UnmodifiableListView(
         List<OnlineParticipant>.of(participants)
           ..sort((a, b) => a.color.index.compareTo(b.color.index)),
       ) {
    _validateParticipants(this.participants);
  }

  final String matchId;
  final int seed;
  final GameMode mode;
  final List<OnlineParticipant> participants;

  bool get hasVirtualControl =>
      participants.any((participant) => participant.isVirtuallyControlled);

  OnlineParticipant participantForColor(PlayerColor color) =>
      participants.firstWhere((participant) => participant.color == color);

  OnlineParticipant participantById(String participantId) =>
      participants.firstWhere((participant) => participant.id == participantId);

  /// Transfers a disconnected remote human to the CPU while retaining the
  /// same public identity, level, color, avatar, and cosmetic loadout.
  OnlineMatchSession takeOverDisconnectedHuman(String participantId) {
    var matched = false;
    final updated = participants.map((participant) {
      if (participant.id != participantId) return participant;
      matched = true;
      if (participant.kind == ParticipantKind.humanTakenOver) {
        return participant;
      }
      if (participant.kind != ParticipantKind.remoteHuman) {
        throw StateError(
          'Only a remote human can be transferred to virtual control.',
        );
      }
      return participant.copyWith(kind: ParticipantKind.humanTakenOver);
    }).toList();

    if (!matched) {
      throw StateError('Participant $participantId is not in this match.');
    }

    return OnlineMatchSession(
      matchId: matchId,
      seed: seed,
      mode: mode,
      participants: updated,
    );
  }

  static void _validateParticipants(List<OnlineParticipant> participants) {
    if (participants.length != PlayerColor.values.length) {
      throw ArgumentError.value(
        participants.length,
        'participants',
        'An online match must contain exactly four participants.',
      );
    }

    final ids = <String>{};
    final colors = <PlayerColor>{};
    for (final participant in participants) {
      if (!ids.add(participant.id)) {
        throw ArgumentError('Participant IDs must be unique.');
      }
      if (!colors.add(participant.color)) {
        throw ArgumentError('Each participant must occupy a unique color.');
      }
    }

    if (participants
            .where((participant) => participant.isLocallyControlled)
            .length !=
        1) {
      throw ArgumentError('An online match must contain one local player.');
    }
  }
}

/// A curated fictional identity used to keep generated names and flags
/// culturally plausible without inferring anything about real players.
class VirtualProfileIdentity {
  const VirtualProfileIdentity({
    required this.displayName,
    required this.allowedFlags,
  });

  final String displayName;
  final List<String> allowedFlags;
}

class VirtualProfileFactory {
  const VirtualProfileFactory({required this.seed});

  final int seed;

  static const profilePool = <VirtualProfileIdentity>[
    VirtualProfileIdentity(
      displayName: 'JuanPop',
      allowedFlags: ['🇩🇴', '🇵🇷', '🇲🇽', '🇨🇴', '🇺🇸', '🇪🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'SofiaPlay',
      allowedFlags: [
        '🇩🇴',
        '🇵🇷',
        '🇲🇽',
        '🇨🇴',
        '🇦🇷',
        '🇨🇱',
        '🇵🇪',
        '🇪🇸',
        '🇺🇸',
      ],
    ),
    VirtualProfileIdentity(
      displayName: 'CarlosTurbo',
      allowedFlags: [
        '🇩🇴',
        '🇵🇷',
        '🇲🇽',
        '🇨🇴',
        '🇵🇦',
        '🇨🇷',
        '🇪🇸',
        '🇺🇸',
      ],
    ),
    VirtualProfileIdentity(
      displayName: 'ValenRayo',
      allowedFlags: ['🇨🇴', '🇦🇷', '🇨🇱', '🇵🇪', '🇺🇾', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'DiegoPlay',
      allowedFlags: ['🇲🇽', '🇨🇴', '🇨🇱', '🇵🇪', '🇪🇸', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'CamilaPop',
      allowedFlags: ['🇨🇴', '🇦🇷', '🇨🇱', '🇵🇪', '🇺🇾', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'LuisDado',
      allowedFlags: [
        '🇩🇴',
        '🇵🇷',
        '🇲🇽',
        '🇨🇴',
        '🇵🇪',
        '🇵🇦',
        '🇨🇷',
        '🇪🇸',
        '🇺🇸',
      ],
    ),
    VirtualProfileIdentity(
      displayName: 'MariaSol',
      allowedFlags: [
        '🇩🇴',
        '🇵🇷',
        '🇲🇽',
        '🇨🇴',
        '🇦🇷',
        '🇨🇱',
        '🇵🇪',
        '🇪🇸',
        '🇺🇸',
      ],
    ),
    VirtualProfileIdentity(
      displayName: 'JoaoTurbo',
      allowedFlags: ['🇧🇷', '🇵🇹', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'BeatrizPop',
      allowedFlags: ['🇧🇷', '🇵🇹', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'MohammedPlay',
      allowedFlags: [
        '🇲🇦',
        '🇪🇬',
        '🇸🇦',
        '🇦🇪',
        '🇯🇴',
        '🇺🇸',
        '🇨🇦',
        '🇫🇷',
        '🇬🇧',
      ],
    ),
    VirtualProfileIdentity(
      displayName: 'AminaStar',
      allowedFlags: ['🇲🇦', '🇪🇬', '🇹🇳', '🇦🇪', '🇫🇷', '🇨🇦', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'OmarRayo',
      allowedFlags: ['🇪🇬', '🇯🇴', '🇱🇧', '🇸🇦', '🇦🇪', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'LaylaPop',
      allowedFlags: ['🇪🇬', '🇯🇴', '🇱🇧', '🇲🇦', '🇦🇪', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'NoahDash',
      allowedFlags: ['🇺🇸', '🇨🇦', '🇬🇧', '🇦🇺'],
    ),
    VirtualProfileIdentity(
      displayName: 'EmmaQuest',
      allowedFlags: ['🇺🇸', '🇨🇦', '🇬🇧', '🇦🇺'],
    ),
    VirtualProfileIdentity(
      displayName: 'LiamTurbo',
      allowedFlags: ['🇺🇸', '🇨🇦', '🇬🇧', '🇮🇪', '🇦🇺'],
    ),
    VirtualProfileIdentity(
      displayName: 'ChloePlay',
      allowedFlags: ['🇺🇸', '🇨🇦', '🇬🇧', '🇫🇷', '🇦🇺'],
    ),
    VirtualProfileIdentity(
      displayName: 'LucPixel',
      allowedFlags: ['🇫🇷', '🇨🇦', '🇧🇪', '🇨🇭', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'AmeliePop',
      allowedFlags: ['🇫🇷', '🇨🇦', '🇧🇪', '🇨🇭', '🇺🇸'],
    ),
    VirtualProfileIdentity(
      displayName: 'GiuliaPop',
      allowedFlags: ['🇮🇹', '🇨🇭', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'MarcoRayo',
      allowedFlags: ['🇮🇹', '🇨🇭', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'HiroPlay',
      allowedFlags: ['🇯🇵', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'YunaStar',
      allowedFlags: ['🇰🇷', '🇯🇵', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'ArjunPlay',
      allowedFlags: ['🇮🇳', '🇺🇸', '🇨🇦', '🇬🇧'],
    ),
    VirtualProfileIdentity(
      displayName: 'PriyaPop',
      allowedFlags: ['🇮🇳', '🇺🇸', '🇨🇦', '🇬🇧'],
    ),
    VirtualProfileIdentity(
      displayName: 'AishaPlay',
      allowedFlags: ['🇵🇰', '🇮🇳', '🇦🇪', '🇬🇧', '🇺🇸', '🇨🇦'],
    ),
    VirtualProfileIdentity(
      displayName: 'KwamePlay',
      allowedFlags: ['🇬🇭', '🇺🇸', '🇨🇦', '🇬🇧'],
    ),
    VirtualProfileIdentity(
      displayName: 'ZuriPop',
      allowedFlags: ['🇰🇪', '🇹🇿', '🇺🇸', '🇨🇦', '🇬🇧'],
    ),
    VirtualProfileIdentity(
      displayName: 'MilaStar',
      allowedFlags: ['🇷🇸', '🇭🇷', '🇧🇬', '🇺🇸', '🇨🇦', '🇩🇪'],
    ),
    VirtualProfileIdentity(
      displayName: 'LukaPlay',
      allowedFlags: ['🇭🇷', '🇷🇸', '🇸🇮', '🇺🇸', '🇨🇦', '🇩🇪'],
    ),
    VirtualProfileIdentity(
      displayName: 'LenaBlitz',
      allowedFlags: ['🇩🇪', '🇦🇹', '🇨🇭', '🇺🇸', '🇨🇦'],
    ),
  ];

  static final namePool = UnmodifiableListView<String>(
    profilePool.map((profile) => profile.displayName),
  );

  static final flagPool = UnmodifiableListView<String>(<String>{
    for (final profile in profilePool) ...profile.allowedFlags,
  });

  static const avatarPool = <String>[
    'avatar_default',
    'avatar_astro',
    'avatar_ninja',
    'avatar_robot',
    'avatar_explorer',
    'avatar_comet',
    'avatar_axolotl',
    'avatar_toucan',
  ];

  static const levelPool = <int>[
    4,
    6,
    8,
    11,
    14,
    17,
    20,
    24,
    28,
    33,
    39,
    46,
    54,
    63,
  ];

  OnlineMatchSession createSession({
    required String matchId,
    required GameMode mode,
    required OnlineParticipant localPlayer,
    Iterable<OnlineParticipant> foundHumans = const [],
  }) {
    if (localPlayer.kind != ParticipantKind.local) {
      throw ArgumentError.value(
        localPlayer.kind,
        'localPlayer.kind',
        'The local player must use ParticipantKind.local.',
      );
    }

    final participants = <OnlineParticipant>[localPlayer];
    final occupiedIds = <String>{localPlayer.id};
    final occupiedColors = <PlayerColor>{localPlayer.color};
    final usedNames = <String>{localPlayer.displayName.toLowerCase()};
    final usedAvatars = <String>{localPlayer.avatarId};

    for (final human in foundHumans) {
      if (human.kind != ParticipantKind.remoteHuman) {
        throw ArgumentError.value(
          human.kind,
          'foundHumans.kind',
          'Found players must use ParticipantKind.remoteHuman.',
        );
      }
      if (!occupiedIds.add(human.id)) {
        throw ArgumentError('Participant IDs must be unique.');
      }
      if (!occupiedColors.add(human.color)) {
        throw ArgumentError('Each found human must occupy an empty color.');
      }
      if (!usedNames.add(human.displayName.toLowerCase())) {
        throw ArgumentError('Participant display names must be unique.');
      }
      usedAvatars.add(human.avatarId);
      participants.add(human);
    }

    final random = Random(_sessionSeed(matchId, mode));
    final availableProfiles = List<VirtualProfileIdentity>.of(profilePool)
      ..removeWhere(
        (profile) => usedNames.contains(profile.displayName.toLowerCase()),
      )
      ..shuffle(random);
    final availableAvatars = List<String>.of(avatarPool)
      ..removeWhere(usedAvatars.contains)
      ..shuffle(random);

    var generatedIndex = 0;
    for (final color in PlayerColor.values) {
      if (occupiedColors.contains(color)) continue;

      final identity = availableProfiles.isNotEmpty
          ? availableProfiles.removeLast()
          : null;
      final generatedName =
          identity?.displayName ?? 'Jugador${generatedIndex + 1}';
      final generatedFlag = identity == null
          ? flagPool[random.nextInt(flagPool.length)]
          : identity.allowedFlags[random.nextInt(identity.allowedFlags.length)];
      final avatar = availableAvatars.isNotEmpty
          ? availableAvatars.removeLast()
          : avatarPool[generatedIndex % avatarPool.length];

      participants.add(
        OnlineParticipant(
          id: 'virtual-$seed-${_stableHash(matchId)}-${color.name}',
          displayName: generatedName,
          flag: generatedFlag,
          avatarId: avatar,
          level: _pickNearbyLevel(random, localPlayer.level),
          color: color,
          kind: ParticipantKind.virtual,
          loadout: _randomCatalogLoadout(random, generatedIndex),
        ),
      );
      generatedIndex++;
    }

    return OnlineMatchSession(
      matchId: matchId,
      seed: seed,
      mode: mode,
      participants: participants,
    );
  }

  CosmeticLoadout _randomCatalogLoadout(Random random, int generatedIndex) {
    String? pick(CosmeticCategory category) {
      final products = walletCatalog
          .where((product) => product.category == category)
          .toList();
      if (products.isEmpty) return null;
      return products[random.nextInt(products.length)].id;
    }

    final themeId = pick(CosmeticCategory.theme);
    return CosmeticLoadout(
      themeId: themeId,
      diceId: generatedIndex.isEven ? pick(CosmeticCategory.dice) : null,
      tokensId:
          matchingTokenStyleIdForTheme(themeId) ??
          pick(CosmeticCategory.tokens),
    );
  }

  int _pickNearbyLevel(Random random, int localLevel) {
    final nearby = levelPool
        .where((level) => (level - localLevel).abs() <= 10)
        .toList();
    final candidates = nearby.isEmpty ? levelPool : nearby;
    return candidates[random.nextInt(candidates.length)];
  }

  int _sessionSeed(String matchId, GameMode mode) =>
      (seed ^ _stableHash(matchId) ^ ((mode.index + 1) * 0x45D9F3B)) &
      0x7FFFFFFF;

  static int _stableHash(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }
}
