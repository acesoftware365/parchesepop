import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/cosmetic_visuals.dart';
import 'package:parchesepop/wallet.dart';

void main() {
  const expectedDiceIds = {
    'dice_default',
    'dice_galaxy',
    'dice_candy_pop',
    'dice_volcano',
    'dice_ice_crystal',
    'dice_arcade_neon',
    'dice_ocean_pearl',
    'dice_prism_party',
    'dice_midnight_gold',
  };
  const expectedThemeIds = {
    'theme_default',
    'theme_neon_rush',
    'theme_golden_night',
    'theme_tropical_splash',
    'theme_celestial_carnival',
    'theme_velvet_lounge',
  };
  const expectedTokenIds = {
    'tokens_default',
    'tokens_robot',
    'tokens_crystal',
    'tokens_rocket',
    'tokens_crown',
    'tokens_neon_pulse',
    'tokens_solar_scarab',
    'tokens_jungle_totem',
    'tokens_pixel_blaster',
    'tokens_aurora_shard',
  };
  const expectedAvatarIds = {
    'avatar_default',
    'avatar_astro',
    'avatar_ninja',
    'avatar_robot',
    'avatar_explorer',
    'avatar_comet',
    'avatar_axolotl',
    'avatar_toucan',
  };

  test('every catalog category has exact registry parity', () {
    final catalogIdsByCategory = {
      for (final category in CosmeticCategory.values)
        category: walletCatalog
            .where((product) => product.category == category)
            .map((product) => product.id)
            .toSet(),
    };

    expect(catalogIdsByCategory[CosmeticCategory.dice], expectedDiceIds);
    expect(catalogIdsByCategory[CosmeticCategory.theme], expectedThemeIds);
    expect(catalogIdsByCategory[CosmeticCategory.tokens], expectedTokenIds);
    expect(catalogIdsByCategory[CosmeticCategory.avatar], expectedAvatarIds);

    expect(diceVisualSpecs.keys.toSet(), expectedDiceIds);
    expect(themeVisualSpecs.keys.toSet(), expectedThemeIds);
    expect(tokenVisualSpecs.keys.toSet(), expectedTokenIds);
    expect(avatarVisualSpecs.keys.toSet(), expectedAvatarIds);

    expect(supportedDiceStyleIds, expectedDiceIds);
    expect(supportedThemeStyleIds, expectedThemeIds);
    expect(supportedTokenStyleIds, expectedTokenIds);
    expect(supportedAvatarStyleIds, expectedAvatarIds);
  });

  test('registry keys and embedded stable IDs always match', () {
    for (final entry in diceVisualSpecs.entries) {
      expect(entry.value.id, entry.key);
      expect(diceVisualSpecFor(entry.key), same(entry.value));
    }
    for (final entry in themeVisualSpecs.entries) {
      expect(entry.value.id, entry.key);
      expect(themeVisualSpecFor(entry.key), same(entry.value));
    }
    for (final entry in tokenVisualSpecs.entries) {
      expect(entry.value.id, entry.key);
      expect(tokenVisualSpecFor(entry.key), same(entry.value));
    }
    for (final entry in avatarVisualSpecs.entries) {
      expect(entry.value.id, entry.key);
      expect(avatarVisualSpecFor(entry.key), same(entry.value));
    }
  });

  test('each dice style has a distinct motif and complete palette', () {
    final specs = diceVisualSpecs.values.toList(growable: false);

    expect(specs.map((spec) => spec.motif).toSet(), DiceMotif.values.toSet());
    expect(
      specs
          .map(
            (spec) =>
                (spec.faceColors.first, spec.faceColors.last, spec.stageColor),
          )
          .toSet(),
      hasLength(specs.length),
    );

    for (final spec in specs) {
      expect(spec.faceColors, hasLength(2));
      expect(spec.faceColors.first, isNot(spec.faceColors.last));
      expect(spec.pipColor.a, greaterThan(0));
      expect(spec.borderColor.a, greaterThan(0));
      expect(spec.glowColor.a, greaterThan(0));
      expect(spec.stageColor.a, greaterThan(0));
    }
  });

  test('each board theme has a distinct motif and usable contrast colors', () {
    final specs = themeVisualSpecs.values.toList(growable: false);

    expect(specs.map((spec) => spec.motif).toSet(), ThemeMotif.values.toSet());
    expect(
      specs
          .map(
            (spec) => (
              spec.gameBackgroundColor,
              spec.boardSurfaceColor,
              spec.framePrimaryColor,
              spec.frameAccentColor,
            ),
          )
          .toSet(),
      hasLength(specs.length),
    );

    for (final spec in specs) {
      expect(spec.framePrimaryColor, isNot(spec.frameAccentColor));
      expect(spec.boardSurfaceColor, isNot(spec.outlineColor));
      expect(spec.trackSurfaceColor.a, greaterThan(0));
      expect(spec.stageColor.a, greaterThan(0));
      expect(spec.sceneSkyColor.a, greaterThan(0));
      expect(spec.sceneGroundColor.a, greaterThan(0));
      expect(spec.scenePrimaryColor.a, greaterThan(0));
      expect(spec.sceneSecondaryColor.a, greaterThan(0));
      expect(spec.sceneGlowColor.a, greaterThan(0));
      expect(spec.sceneSkyColor, isNot(spec.sceneGroundColor));
      expect(spec.scenePrimaryColor, isNot(spec.sceneSecondaryColor));
    }

    expect(
      specs
          .map(
            (spec) => (
              spec.sceneSkyColor,
              spec.sceneGroundColor,
              spec.scenePrimaryColor,
              spec.sceneSecondaryColor,
              spec.sceneGlowColor,
            ),
          )
          .toSet(),
      hasLength(specs.length),
    );
  });

  test('every theme scene paints at compact preview size', () {
    for (final spec in themeVisualSpecs.values) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      expect(
        () => ThemeScenePainter(
          theme: spec,
          progress: .37,
        ).paint(canvas, const ui.Size(96, 64)),
        returnsNormally,
        reason: '${spec.id} must remain legible in a compact store preview',
      );
      recorder.endRecording();
    }
  });

  test('theme scenes repaint only for a visual or animation change', () {
    final original = ThemeScenePainter(
      theme: themeVisualSpecs['theme_neon_rush']!,
      progress: .25,
    );

    expect(
      ThemeScenePainter(
        theme: themeVisualSpecs['theme_neon_rush']!,
        progress: .25,
      ).shouldRepaint(original),
      isFalse,
    );
    expect(
      ThemeScenePainter(
        theme: themeVisualSpecs['theme_neon_rush']!,
        progress: .75,
      ).shouldRepaint(original),
      isTrue,
    );
    expect(
      ThemeScenePainter(
        theme: themeVisualSpecs['theme_tropical_splash']!,
        progress: .25,
      ).shouldRepaint(original),
      isTrue,
    );
  });

  test('each token style preserves a unique code-drawn motif', () {
    final specs = tokenVisualSpecs.values.toList(growable: false);

    expect(specs.map((spec) => spec.motif).toSet(), TokenMotif.values.toSet());
    expect(
      specs
          .map(
            (spec) => (
              spec.detailColor,
              spec.highlightColor,
              spec.glowColor,
              spec.stageColor,
            ),
          )
          .toSet(),
      hasLength(specs.length),
    );

    for (final spec in specs) {
      expect(spec.detailColor.a, greaterThan(0));
      expect(spec.highlightColor.a, greaterThan(0));
      expect(spec.outlineColor.a, greaterThan(0));
      expect(spec.glowColor.a, greaterThan(0));
    }
  });

  test('each avatar has an original motif and cross-platform palette', () {
    final specs = avatarVisualSpecs.values.toList(growable: false);

    expect(specs.map((spec) => spec.motif).toSet(), AvatarMotif.values.toSet());
    expect(
      specs
          .map(
            (spec) => (
              spec.backgroundColors.first,
              spec.backgroundColors.last,
              spec.primaryColor,
              spec.accentColor,
            ),
          )
          .toSet(),
      hasLength(specs.length),
    );

    for (final spec in specs) {
      expect(spec.backgroundColors, hasLength(2));
      expect(spec.backgroundColors.first, isNot(spec.backgroundColors.last));
      expect(spec.primaryColor, isNot(spec.accentColor));
      expect(spec.borderColor.a, greaterThan(0));
      expect(spec.glowColor.a, greaterThan(0));
    }
  });

  test('null and unknown IDs use stable category-specific fallbacks', () {
    expect(diceVisualSpecFor(null), same(defaultDiceVisualSpec));
    expect(diceVisualSpecFor('missing'), same(defaultDiceVisualSpec));
    expect(themeVisualSpecFor(null), same(defaultThemeVisualSpec));
    expect(themeVisualSpecFor('missing'), same(defaultThemeVisualSpec));
    expect(tokenVisualSpecFor(null), same(defaultTokenVisualSpec));
    expect(tokenVisualSpecFor('missing'), same(defaultTokenVisualSpec));
    expect(avatarVisualSpecFor(null), same(defaultAvatarVisualSpec));
    expect(avatarVisualSpecFor('missing'), same(defaultAvatarVisualSpec));

    expect(defaultDiceVisualSpec.id, 'dice_default');
    expect(defaultThemeVisualSpec.id, 'theme_default');
    expect(defaultTokenVisualSpec.id, 'tokens_default');
    expect(defaultAvatarVisualSpec.id, 'avatar_default');
  });
}
