import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_match.dart';
import 'package:parchesepop/wallet.dart';

OnlineParticipant participant({
  required String id,
  required String name,
  required PlayerColor color,
  required ParticipantKind kind,
  int level = 18,
  String flag = '🇩🇴',
  String avatarId = 'avatar_astro',
}) {
  return OnlineParticipant(
    id: id,
    displayName: name,
    flag: flag,
    avatarId: avatarId,
    level: level,
    color: color,
    kind: kind,
    loadout: const CosmeticLoadout(
      themeId: 'theme_neon_rush',
      diceId: 'dice_galaxy',
      tokensId: 'tokens_robot',
    ),
  );
}

List<Object?> sessionSignature(OnlineMatchSession session) => [
  session.matchId,
  session.seed,
  session.mode,
  for (final player in session.participants) ...[
    player.id,
    player.displayName,
    player.flag,
    player.avatarId,
    player.level,
    player.color,
    player.kind,
    ...player.loadout.productIds,
  ],
];

void main() {
  final local = participant(
    id: 'local-juan',
    name: 'JuanPop',
    color: PlayerColor.red,
    kind: ParticipantKind.local,
    level: 20,
  );

  test('the same seeds and inputs keep virtual profiles deterministic', () {
    const seeds = [0, 1, 99, 8042, 104729, 0x7FFFFFFF];

    for (final seed in seeds) {
      for (final mode in GameMode.values) {
        final matchId = 'match-deterministic-$seed-${mode.name}';
        final first = VirtualProfileFactory(
          seed: seed,
        ).createSession(matchId: matchId, mode: mode, localPlayer: local);
        final second = VirtualProfileFactory(
          seed: seed,
        ).createSession(matchId: matchId, mode: mode, localPlayer: local);

        expect(
          sessionSignature(second),
          sessionSignature(first),
          reason: 'Seed $seed must be stable in ${mode.name} mode.',
        );
      }
    }
  });

  test('the curated identity catalog has complete unique pairings', () {
    expect(VirtualProfileFactory.profilePool, isNotEmpty);

    final names = <String>{};
    final flags = <String>{};
    for (final identity in VirtualProfileFactory.profilePool) {
      expect(identity.displayName.trim(), identity.displayName);
      expect(identity.displayName, isNotEmpty);
      expect(
        identity.displayName.length,
        inInclusiveRange(3, 12),
        reason: '${identity.displayName} must fit the online profile UI.',
      );
      expect(
        names.add(identity.displayName.toLowerCase()),
        isTrue,
        reason: 'Each curated display name must identify one profile.',
      );
      expect(
        identity.allowedFlags,
        isNotEmpty,
        reason: '${identity.displayName} needs at least one plausible flag.',
      );
      expect(
        identity.allowedFlags.length,
        lessThan(VirtualProfileFactory.flagPool.length),
        reason:
            '${identity.displayName} must not accept every flag independently.',
      );
      expect(
        identity.allowedFlags.toSet(),
        hasLength(identity.allowedFlags.length),
        reason: '${identity.displayName} repeats an allowed flag.',
      );
      flags.addAll(identity.allowedFlags);
    }

    expect(
      VirtualProfileFactory.namePool.map((name) => name.toLowerCase()).toSet(),
      names,
    );
    expect(VirtualProfileFactory.flagPool.toSet(), flags);
  });

  test('generated names and flags always come from one curated identity', () {
    final identityByName = <String, VirtualProfileIdentity>{
      for (final identity in VirtualProfileFactory.profilePool)
        identity.displayName.toLowerCase(): identity,
    };

    for (var sample = 0; sample < 80; sample++) {
      final seed = 17 + (sample * 7919);
      final mode = GameMode.values[sample % GameMode.values.length];
      final session = VirtualProfileFactory(seed: seed).createSession(
        matchId: 'match-profile-pairing-$sample',
        mode: mode,
        localPlayer: local,
      );
      final virtualPlayers = session.participants.where(
        (player) => player.kind == ParticipantKind.virtual,
      );

      expect(virtualPlayers, hasLength(3));
      expect(
        session.participants.map((player) => player.id).toSet(),
        hasLength(4),
        reason: 'Participant IDs must remain unique in sample $sample.',
      );
      expect(
        session.participants
            .map((player) => player.displayName.toLowerCase())
            .toSet(),
        hasLength(4),
        reason: 'Display names must remain unique in sample $sample.',
      );
      expect(
        session.participants.map((player) => player.color).toSet(),
        hasLength(4),
        reason: 'Player colors must remain unique in sample $sample.',
      );

      for (final player in virtualPlayers) {
        final identity = identityByName[player.displayName.toLowerCase()];
        expect(
          identity,
          isNotNull,
          reason:
              '${player.displayName} must come from the curated identity pool.',
        );
        expect(
          identity!.allowedFlags,
          contains(player.flag),
          reason:
              '${player.displayName} cannot be generated with ${player.flag}.',
        );
      }
    }
  });

  test('generated profiles are unique and use valid catalog IDs', () {
    const factory = VirtualProfileFactory(seed: 99);
    final session = factory.createSession(
      matchId: 'match-catalog',
      mode: GameMode.traditional,
      localPlayer: local,
    );

    final catalogIds = walletCatalog.map((product) => product.id).toSet();
    final validLoadoutIds = {
      ...catalogIds,
      ...bundledTokenStyleIdByThemeId.values,
    };
    final ids = session.participants.map((player) => player.id).toSet();
    final names = session.participants
        .map((player) => player.displayName.toLowerCase())
        .toSet();
    final colors = session.participants.map((player) => player.color).toSet();
    final virtualAvatars = session.participants
        .where((player) => player.kind == ParticipantKind.virtual)
        .map((player) => player.avatarId)
        .toSet();

    expect(session.participants, hasLength(4));
    expect(ids, hasLength(4));
    expect(names, hasLength(4));
    expect(colors, hasLength(4));
    expect(virtualAvatars, hasLength(3));
    expect(session.participants.where((player) => player.isLocallyControlled), [
      local,
    ]);

    for (final player in session.participants) {
      expect(player.level, greaterThan(0));
      expect(catalogIds, contains(player.avatarId));
      if (player.kind == ParticipantKind.virtual) {
        expect(VirtualProfileFactory.namePool, contains(player.displayName));
        expect(VirtualProfileFactory.flagPool, contains(player.flag));
        expect(VirtualProfileFactory.avatarPool, contains(player.avatarId));
        expect(
          player.loadout.tokensId,
          matchingTokenStyleIdForTheme(player.loadout.themeId),
          reason:
              '${player.displayName} should use pieces coordinated with '
              '${player.loadout.themeId}.',
        );
      }
      for (final productId in player.loadout.productIds) {
        expect(validLoadoutIds, contains(productId));
      }
    }
  });

  test('found humans are preserved and only empty seats are filled', () {
    final greenHuman = participant(
      id: 'remote-green',
      name: 'MarAzul',
      color: PlayerColor.green,
      kind: ParticipantKind.remoteHuman,
      avatarId: 'avatar_ninja',
    );
    final yellowHuman = participant(
      id: 'remote-yellow',
      name: 'SolCaribe',
      color: PlayerColor.yellow,
      kind: ParticipantKind.remoteHuman,
      avatarId: 'avatar_robot',
    );

    const factory = VirtualProfileFactory(seed: 713);
    final session = factory.createSession(
      matchId: 'match-partial',
      mode: GameMode.chaos,
      localPlayer: local,
      foundHumans: [greenHuman, yellowHuman],
    );

    expect(session.participantForColor(PlayerColor.red), same(local));
    expect(session.participantForColor(PlayerColor.green), same(greenHuman));
    expect(session.participantForColor(PlayerColor.yellow), same(yellowHuman));
    expect(
      session.participantForColor(PlayerColor.blue).kind,
      ParticipantKind.virtual,
    );
    expect(
      session.participants.where(
        (player) => player.kind == ParticipantKind.virtual,
      ),
      hasLength(1),
    );
  });

  test('takeover keeps a disconnected human identity and cosmetics', () {
    final remote = participant(
      id: 'remote-player',
      name: 'RayoReal',
      color: PlayerColor.green,
      kind: ParticipantKind.remoteHuman,
      level: 27,
      flag: '🇨🇴',
      avatarId: 'avatar_explorer',
    );
    const factory = VirtualProfileFactory(seed: 415);
    final original = factory.createSession(
      matchId: 'match-takeover',
      mode: GameMode.traditional,
      localPlayer: local,
      foundHumans: [remote],
    );

    final takenOver = original.takeOverDisconnectedHuman(remote.id);
    final replacement = takenOver.participantById(remote.id);

    expect(
      original.participantById(remote.id).kind,
      ParticipantKind.remoteHuman,
    );
    expect(replacement.kind, ParticipantKind.humanTakenOver);
    expect(replacement.id, remote.id);
    expect(replacement.displayName, remote.displayName);
    expect(replacement.flag, remote.flag);
    expect(replacement.avatarId, remote.avatarId);
    expect(replacement.level, remote.level);
    expect(replacement.color, remote.color);
    expect(replacement.loadout, same(remote.loadout));
    expect(takenOver.hasVirtualControl, isTrue);
  });
}
