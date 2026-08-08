import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative patterns painted over dice and their preview stages.
enum DiceMotif {
  classic,
  galaxy,
  candy,
  volcano,
  ice,
  arcade,
  ocean,
  prism,
  midnight,
}

/// Original scene identities used by a complete board theme.
///
/// The persisted product IDs remain stable. These motif values describe the
/// richer scenes now attached to those products:
/// neon = futuristic city, golden = pyramid temple, tropical = living jungle,
/// retro = pixel arcade and aurora = arctic northern lights.
enum ThemeMotif { classic, neon, golden, tropical, retro, aurora, cosmic }

/// Center marks painted inside a piece while preserving its team color.
enum TokenMotif {
  star,
  robot,
  crystal,
  rocket,
  crown,
  neonPulse,
  solarScarab,
  jungleTotem,
  pixelBlaster,
  auroraShard,
  cosmicCore,
}

/// Original, code-drawn avatar identities. No platform emoji is required.
enum AvatarMotif {
  controller,
  astronaut,
  ninja,
  robot,
  explorer,
  comet,
  axolotl,
  toucan,
}

@immutable
class DiceVisualSpec {
  const DiceVisualSpec({
    required this.id,
    required this.faceColors,
    required this.pipColor,
    required this.borderColor,
    required this.glowColor,
    required this.stageColor,
    required this.motif,
  });

  final String id;
  final List<Color> faceColors;
  final Color pipColor;
  final Color borderColor;
  final Color glowColor;
  final Color stageColor;
  final DiceMotif motif;
}

@immutable
class ThemeVisualSpec {
  const ThemeVisualSpec({
    required this.id,
    required this.gameBackgroundColor,
    required this.boardSurfaceColor,
    required this.framePrimaryColor,
    required this.frameAccentColor,
    required this.trackSurfaceColor,
    required this.outlineColor,
    required this.stageColor,
    required this.sceneSkyColor,
    required this.sceneGroundColor,
    required this.scenePrimaryColor,
    required this.sceneSecondaryColor,
    required this.sceneGlowColor,
    required this.motif,
  });

  final String id;
  final Color gameBackgroundColor;
  final Color boardSurfaceColor;
  final Color framePrimaryColor;
  final Color frameAccentColor;
  final Color trackSurfaceColor;
  final Color outlineColor;
  final Color stageColor;
  final Color sceneSkyColor;
  final Color sceneGroundColor;
  final Color scenePrimaryColor;
  final Color sceneSecondaryColor;
  final Color sceneGlowColor;
  final ThemeMotif motif;
}

@immutable
class TokenVisualSpec {
  const TokenVisualSpec({
    required this.id,
    required this.detailColor,
    required this.highlightColor,
    required this.outlineColor,
    required this.glowColor,
    required this.stageColor,
    required this.motif,
  });

  final String id;
  final Color detailColor;
  final Color highlightColor;
  final Color outlineColor;
  final Color glowColor;
  final Color stageColor;
  final TokenMotif motif;
}

@immutable
class AvatarVisualSpec {
  const AvatarVisualSpec({
    required this.id,
    required this.backgroundColors,
    required this.primaryColor,
    required this.accentColor,
    required this.borderColor,
    required this.glowColor,
    required this.motif,
  });

  final String id;
  final List<Color> backgroundColors;
  final Color primaryColor;
  final Color accentColor;
  final Color borderColor;
  final Color glowColor;
  final AvatarMotif motif;
}

const defaultDiceVisualSpec = DiceVisualSpec(
  id: 'dice_default',
  faceColors: [Color(0xFF2474E5), Color(0xFFF04452)],
  pipColor: Colors.white,
  borderColor: Colors.white,
  glowColor: Color(0x662474E5),
  stageColor: Color(0xFFF1F5FC),
  motif: DiceMotif.classic,
);

const Map<String, DiceVisualSpec> diceVisualSpecs = {
  'dice_default': defaultDiceVisualSpec,
  'dice_galaxy': DiceVisualSpec(
    id: 'dice_galaxy',
    faceColors: [Color(0xFF6C3BE8), Color(0xFF00AFC4)],
    pipColor: Color(0xFFF7F2FF),
    borderColor: Color(0xFFE8DDFF),
    glowColor: Color(0x997B61FF),
    stageColor: Color(0xFF151B43),
    motif: DiceMotif.galaxy,
  ),
  'dice_candy_pop': DiceVisualSpec(
    id: 'dice_candy_pop',
    faceColors: [Color(0xFFFF5EAE), Color(0xFFFFA143)],
    pipColor: Colors.white,
    borderColor: Color(0xFFFFF5FC),
    glowColor: Color(0x99FF5EAE),
    stageColor: Color(0xFFFFEDF8),
    motif: DiceMotif.candy,
  ),
  'dice_volcano': DiceVisualSpec(
    id: 'dice_volcano',
    faceColors: [Color(0xFFFF5A24), Color(0xFF2B1822)],
    pipColor: Color(0xFFFFF3BE),
    borderColor: Color(0xFFFFD45C),
    glowColor: Color(0xB3FF5722),
    stageColor: Color(0xFF2A161B),
    motif: DiceMotif.volcano,
  ),
  'dice_ice_crystal': DiceVisualSpec(
    id: 'dice_ice_crystal',
    faceColors: [Color(0xFF7DEBFF), Color(0xFF8EA9FF)],
    pipColor: Color(0xFF164B8C),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x9973D7FF),
    stageColor: Color(0xFFEAFBFF),
    motif: DiceMotif.ice,
  ),
  'dice_arcade_neon': DiceVisualSpec(
    id: 'dice_arcade_neon',
    faceColors: [Color(0xFFFF4FD8), Color(0xFF00D6A3)],
    pipColor: Color(0xFFCCFF4D),
    borderColor: Color(0xFF58F5FF),
    glowColor: Color(0xB3FF3BCB),
    stageColor: Color(0xFF10142F),
    motif: DiceMotif.arcade,
  ),
  'dice_ocean_pearl': DiceVisualSpec(
    id: 'dice_ocean_pearl',
    faceColors: [Color(0xFF19C6C7), Color(0xFF2563EB)],
    pipColor: Color(0xFFFFFFFF),
    borderColor: Color(0xFFE7FFFF),
    glowColor: Color(0x9922D3D3),
    stageColor: Color(0xFF0E3F68),
    motif: DiceMotif.ocean,
  ),
  'dice_prism_party': DiceVisualSpec(
    id: 'dice_prism_party',
    faceColors: [Color(0xFFFF4D8D), Color(0xFF6C4DFF)],
    pipColor: Color(0xFFFFF9C4),
    borderColor: Color(0xFF78F1FF),
    glowColor: Color(0xA66C4DFF),
    stageColor: Color(0xFF281A59),
    motif: DiceMotif.prism,
  ),
  'dice_midnight_gold': DiceVisualSpec(
    id: 'dice_midnight_gold',
    faceColors: [Color(0xFF1B2345), Color(0xFF34224F)],
    pipColor: Color(0xFFFFD76A),
    borderColor: Color(0xFFEAC35C),
    glowColor: Color(0x99E8BD4F),
    stageColor: Color(0xFF11152E),
    motif: DiceMotif.midnight,
  ),
};

const Set<String> supportedDiceStyleIds = {
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

DiceVisualSpec diceVisualSpecFor(String? productId) =>
    diceVisualSpecs[productId] ?? defaultDiceVisualSpec;

const defaultThemeVisualSpec = ThemeVisualSpec(
  id: 'theme_default',
  gameBackgroundColor: Color(0xFFE9F0FA),
  boardSurfaceColor: Color(0xFFFFFDF7),
  framePrimaryColor: Color(0xFF17284D),
  frameAccentColor: Color(0xFFFFC83D),
  trackSurfaceColor: Color(0xFFFFFFFF),
  outlineColor: Color(0xFF17284D),
  stageColor: Color(0xFFE9F0FA),
  sceneSkyColor: Color(0xFFE9F0FA),
  sceneGroundColor: Color(0xFFD7E3F4),
  scenePrimaryColor: Color(0xFF2474E5),
  sceneSecondaryColor: Color(0xFFFFC83D),
  sceneGlowColor: Color(0x99FFFFFF),
  motif: ThemeMotif.classic,
);

const Map<String, ThemeVisualSpec> themeVisualSpecs = {
  'theme_default': defaultThemeVisualSpec,
  'theme_neon_rush': ThemeVisualSpec(
    id: 'theme_neon_rush',
    gameBackgroundColor: Color(0xFF090E2C),
    boardSurfaceColor: Color(0xFF111942),
    framePrimaryColor: Color(0xFF00E5FF),
    frameAccentColor: Color(0xFFFF3FD2),
    trackSurfaceColor: Color(0xFFF1F5FF),
    outlineColor: Color(0xFF101B48),
    stageColor: Color(0xFF080D2A),
    sceneSkyColor: Color(0xFF111A51),
    sceneGroundColor: Color(0xFF070A20),
    scenePrimaryColor: Color(0xFF00E5FF),
    sceneSecondaryColor: Color(0xFFFF3FD2),
    sceneGlowColor: Color(0xFF9A7DFF),
    motif: ThemeMotif.neon,
  ),
  'theme_golden_night': ThemeVisualSpec(
    id: 'theme_golden_night',
    gameBackgroundColor: Color(0xFF392513),
    boardSurfaceColor: Color(0xFFFFE3A3),
    framePrimaryColor: Color(0xFF7A4311),
    frameAccentColor: Color(0xFFFFD258),
    trackSurfaceColor: Color(0xFFFFF8E6),
    outlineColor: Color(0xFF4A2A12),
    stageColor: Color(0xFF623A1B),
    sceneSkyColor: Color(0xFF6C4A78),
    sceneGroundColor: Color(0xFFE09A31),
    scenePrimaryColor: Color(0xFFFFC84B),
    sceneSecondaryColor: Color(0xFF9B5A1F),
    sceneGlowColor: Color(0xFFFFF1A3),
    motif: ThemeMotif.golden,
  ),
  'theme_tropical_splash': ThemeVisualSpec(
    id: 'theme_tropical_splash',
    gameBackgroundColor: Color(0xFF0A3D35),
    boardSurfaceColor: Color(0xFFF2FFF0),
    framePrimaryColor: Color(0xFF0B6B46),
    frameAccentColor: Color(0xFFFFC53D),
    trackSurfaceColor: Color(0xFFF8FFF1),
    outlineColor: Color(0xFF123F32),
    stageColor: Color(0xFF0B604A),
    sceneSkyColor: Color(0xFF105F57),
    sceneGroundColor: Color(0xFF073B2B),
    scenePrimaryColor: Color(0xFF34D17B),
    sceneSecondaryColor: Color(0xFF28BFD0),
    sceneGlowColor: Color(0xFFFFE56B),
    motif: ThemeMotif.tropical,
  ),
  'theme_celestial_carnival': ThemeVisualSpec(
    id: 'theme_celestial_carnival',
    gameBackgroundColor: Color(0xFF160A32),
    boardSurfaceColor: Color(0xFF211440),
    framePrimaryColor: Color(0xFFFF4FD8),
    frameAccentColor: Color(0xFF58F5FF),
    trackSurfaceColor: Color(0xFFFFF7FD),
    outlineColor: Color(0xFF2B1751),
    stageColor: Color(0xFF13082D),
    sceneSkyColor: Color(0xFF351467),
    sceneGroundColor: Color(0xFF090923),
    scenePrimaryColor: Color(0xFFFF4FD8),
    sceneSecondaryColor: Color(0xFF58F5FF),
    sceneGlowColor: Color(0xFFFFE45C),
    motif: ThemeMotif.retro,
  ),
  'theme_velvet_lounge': ThemeVisualSpec(
    id: 'theme_velvet_lounge',
    gameBackgroundColor: Color(0xFF06162E),
    boardSurfaceColor: Color(0xFFEAF8FF),
    framePrimaryColor: Color(0xFF36E6C2),
    frameAccentColor: Color(0xFF9A7DFF),
    trackSurfaceColor: Color(0xFFF7FCFF),
    outlineColor: Color(0xFF123555),
    stageColor: Color(0xFF06152F),
    sceneSkyColor: Color(0xFF0B2454),
    sceneGroundColor: Color(0xFF07172D),
    scenePrimaryColor: Color(0xFF38E8C6),
    sceneSecondaryColor: Color(0xFF9A7DFF),
    sceneGlowColor: Color(0xFFD9FFFF),
    motif: ThemeMotif.aurora,
  ),
  'theme_cosmic_realms_red': ThemeVisualSpec(
    id: 'theme_cosmic_realms_red',
    gameBackgroundColor: Color(0xFF160611),
    boardSurfaceColor: Color(0xFF2A0A1D),
    framePrimaryColor: Color(0xFF7E1738),
    frameAccentColor: Color(0xFFFFD56A),
    trackSurfaceColor: Color(0xFF3C102A),
    outlineColor: Color(0xFF16091B),
    stageColor: Color(0xFF14040F),
    sceneSkyColor: Color(0xFF190617),
    sceneGroundColor: Color(0xFF05040D),
    scenePrimaryColor: Color(0xFFE42E62),
    sceneSecondaryColor: Color(0xFF8C3DFF),
    sceneGlowColor: Color(0xFFFFD76B),
    motif: ThemeMotif.cosmic,
  ),
  'theme_cosmic_realms_yellow': ThemeVisualSpec(
    id: 'theme_cosmic_realms_yellow',
    gameBackgroundColor: Color(0xFF160F02),
    boardSurfaceColor: Color(0xFF2D1C05),
    framePrimaryColor: Color(0xFF7A5200),
    frameAccentColor: Color(0xFFFFF0A3),
    trackSurfaceColor: Color(0xFF3E2907),
    outlineColor: Color(0xFF171006),
    stageColor: Color(0xFF120C02),
    sceneSkyColor: Color(0xFF1C1204),
    sceneGroundColor: Color(0xFF05040B),
    scenePrimaryColor: Color(0xFFF2B51D),
    sceneSecondaryColor: Color(0xFFFF7A3D),
    sceneGlowColor: Color(0xFFFFF2A6),
    motif: ThemeMotif.cosmic,
  ),
  'theme_cosmic_realms_blue': ThemeVisualSpec(
    id: 'theme_cosmic_realms_blue',
    gameBackgroundColor: Color(0xFF030D1E),
    boardSurfaceColor: Color(0xFF071B36),
    framePrimaryColor: Color(0xFF0B4F9B),
    frameAccentColor: Color(0xFF72E7FF),
    trackSurfaceColor: Color(0xFF0B294E),
    outlineColor: Color(0xFF041023),
    stageColor: Color(0xFF020A18),
    sceneSkyColor: Color(0xFF051329),
    sceneGroundColor: Color(0xFF020611),
    scenePrimaryColor: Color(0xFF248BFF),
    sceneSecondaryColor: Color(0xFF26D8D2),
    sceneGlowColor: Color(0xFFA7F3FF),
    motif: ThemeMotif.cosmic,
  ),
  'theme_cosmic_realms_green': ThemeVisualSpec(
    id: 'theme_cosmic_realms_green',
    gameBackgroundColor: Color(0xFF02150E),
    boardSurfaceColor: Color(0xFF06281C),
    framePrimaryColor: Color(0xFF08724D),
    frameAccentColor: Color(0xFFBDFB72),
    trackSurfaceColor: Color(0xFF0B3A29),
    outlineColor: Color(0xFF03150E),
    stageColor: Color(0xFF020F0A),
    sceneSkyColor: Color(0xFF041C14),
    sceneGroundColor: Color(0xFF020A08),
    scenePrimaryColor: Color(0xFF20C982),
    sceneSecondaryColor: Color(0xFF62E85D),
    sceneGlowColor: Color(0xFFD8FF8C),
    motif: ThemeMotif.cosmic,
  ),
};

const Set<String> supportedThemeStyleIds = {
  'theme_default',
  'theme_neon_rush',
  'theme_golden_night',
  'theme_tropical_splash',
  'theme_celestial_carnival',
  'theme_velvet_lounge',
  'theme_cosmic_realms_red',
  'theme_cosmic_realms_yellow',
  'theme_cosmic_realms_blue',
  'theme_cosmic_realms_green',
};

ThemeVisualSpec themeVisualSpecFor(String? productId) =>
    themeVisualSpecs[productId] ?? defaultThemeVisualSpec;

/// Paints the animated, code-drawn environment belonging to a board theme.
///
/// [progress] is a repeating value from 0 to 1. The painter clamps values
/// outside that range, so callers can safely pass an animation controller.
/// Every scene is deterministic and uses only Flutter drawing primitives.
class ThemeScenePainter extends CustomPainter {
  const ThemeScenePainter({required ThemeVisualSpec theme, this.progress = 0})
    : spec = theme;

  final ThemeVisualSpec spec;
  ThemeVisualSpec get theme => spec;
  final double progress;

  double get _progress {
    if (!progress.isFinite) return 0;
    return progress.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [spec.sceneSkyColor, spec.sceneGroundColor],
        ).createShader(bounds),
    );

    switch (spec.motif) {
      case ThemeMotif.classic:
        _paintClassic(canvas, size);
      case ThemeMotif.neon:
        _paintFuturisticCity(canvas, size);
      case ThemeMotif.golden:
        _paintPyramidTemple(canvas, size);
      case ThemeMotif.tropical:
        _paintLivingJungle(canvas, size);
      case ThemeMotif.retro:
        _paintRetroArcade(canvas, size);
      case ThemeMotif.aurora:
        _paintArcticAurora(canvas, size);
      case ThemeMotif.cosmic:
        _paintCosmicRealm(canvas, size);
    }
    canvas.restore();
  }

  void _paintClassic(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final line = Paint()
      ..color = spec.scenePrimaryColor.withValues(alpha: .16)
      ..strokeWidth = math.max(1, unit * .012);
    for (var index = -2; index < 9; index++) {
      final offset = index * unit * .22;
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        line,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .22),
      unit * .13,
      Paint()..color = spec.sceneGlowColor.withValues(alpha: .36),
    );
  }

  void _paintCosmicRealm(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;
    final bounds = Offset.zero & size;
    final nebulaCenter = Offset(
      size.width * (.34 + math.sin(p * math.pi * 2) * .025),
      size.height * (.43 + math.cos(p * math.pi * 2) * .018),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: nebulaCenter,
        width: size.width * .88,
        height: size.height * .62,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            spec.scenePrimaryColor.withValues(alpha: .54),
            spec.sceneSecondaryColor.withValues(alpha: .24),
            Colors.transparent,
          ],
        ).createShader(bounds)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .07),
    );
    final orbitCenter = Offset(size.width * .64, size.height * .40);
    for (var orbit = 0; orbit < 3; orbit++) {
      final orbitRect = Rect.fromCenter(
        center: orbitCenter,
        width: size.width * (.30 + orbit * .15),
        height: size.height * (.16 + orbit * .09),
      );
      canvas.save();
      canvas.translate(orbitCenter.dx, orbitCenter.dy);
      canvas.rotate(p * math.pi * 2 + orbit * .72);
      canvas.translate(-orbitCenter.dx, -orbitCenter.dy);
      canvas.drawArc(
        orbitRect,
        orbit * .9,
        math.pi * 1.16,
        false,
        Paint()
          ..color =
              (orbit.isEven ? spec.sceneGlowColor : spec.sceneSecondaryColor)
                  .withValues(alpha: .38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, unit * .012)
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
    const stars = [
      Offset(.06, .14),
      Offset(.14, .74),
      Offset(.24, .26),
      Offset(.34, .84),
      Offset(.43, .12),
      Offset(.53, .68),
      Offset(.64, .18),
      Offset(.72, .78),
      Offset(.81, .31),
      Offset(.91, .60),
      Offset(.96, .12),
    ];
    for (var index = 0; index < stars.length; index++) {
      final seed = stars[index];
      final twinkle =
          .42 + math.sin((p + index * .137) * math.pi * 2).abs() * .50;
      canvas.drawCircle(
        Offset(seed.dx * size.width, seed.dy * size.height),
        math.max(1, unit * (.007 + (index % 3) * .003)),
        Paint()
          ..color = (index % 4 == 0 ? spec.sceneGlowColor : Colors.white)
              .withValues(alpha: twinkle),
      );
    }
  }

  void _paintFuturisticCity(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;
    final horizon = size.height * .54;

    canvas.drawCircle(
      Offset(size.width * .76, size.height * .22),
      unit * .16,
      Paint()
        ..color = spec.sceneSecondaryColor.withValues(alpha: .34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .06),
    );
    canvas.drawCircle(
      Offset(size.width * .76, size.height * .22),
      unit * .095,
      Paint()..color = spec.sceneSecondaryColor.withValues(alpha: .76),
    );

    final buildings = <({double x, double width, double height})>[
      (x: .01, width: .12, height: .31),
      (x: .12, width: .16, height: .45),
      (x: .28, width: .10, height: .28),
      (x: .39, width: .18, height: .52),
      (x: .58, width: .11, height: .36),
      (x: .70, width: .17, height: .47),
      (x: .87, width: .12, height: .30),
    ];
    for (
      var buildingIndex = 0;
      buildingIndex < buildings.length;
      buildingIndex++
    ) {
      final building = buildings[buildingIndex];
      final rect = Rect.fromLTWH(
        size.width * building.x,
        horizon - size.height * building.height,
        size.width * building.width,
        size.height * building.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(spec.sceneGroundColor, spec.scenePrimaryColor, .28)!,
              spec.sceneGroundColor,
            ],
          ).createShader(rect),
      );
      canvas.drawLine(
        rect.topLeft,
        rect.bottomLeft,
        Paint()
          ..color = buildingIndex.isEven
              ? spec.scenePrimaryColor
              : spec.sceneSecondaryColor
          ..strokeWidth = math.max(1, unit * .012),
      );
      final windowPaint = Paint()
        ..color =
            (buildingIndex.isEven
                    ? spec.sceneSecondaryColor
                    : spec.scenePrimaryColor)
                .withValues(alpha: .86);
      final windowWidth = math.max(1.5, rect.width * .16);
      final windowHeight = math.max(1.5, unit * .018);
      for (var row = 0; row < 4; row++) {
        final y = rect.top + rect.height * (.20 + row * .18);
        for (var column = 0; column < 2; column++) {
          if ((row + column + buildingIndex) % 3 == 0) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                rect.left + rect.width * (.20 + column * .42),
                y,
                windowWidth,
                windowHeight,
              ),
              Radius.circular(windowHeight),
            ),
            windowPaint,
          );
        }
      }
    }

    final grid = Paint()
      ..color = spec.scenePrimaryColor.withValues(alpha: .54)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * .008);
    final vanishingPoint = Offset(size.width * .5, horizon);
    for (var index = -5; index <= 5; index++) {
      canvas.drawLine(
        vanishingPoint,
        Offset(size.width * (.5 + index * .18), size.height),
        grid,
      );
    }
    for (var index = 0; index < 7; index++) {
      final t = ((index / 7 + p) % 1);
      final eased = t * t;
      final y = horizon + (size.height - horizon) * eased;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final trafficY = horizon + (size.height - horizon) * .64;
    for (var index = 0; index < 3; index++) {
      final x = size.width * ((p + index * .37) % 1);
      canvas.drawCircle(
        Offset(x, trafficY + index * unit * .025),
        math.max(1.5, unit * .018),
        Paint()
          ..color = index.isEven
              ? spec.sceneSecondaryColor
              : spec.sceneGlowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .018),
      );
    }
  }

  void _paintPyramidTemple(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;
    final sun = Offset(size.width * .78, size.height * .20);
    canvas.drawCircle(
      sun,
      unit * .14,
      Paint()
        ..color = spec.sceneGlowColor.withValues(alpha: .42)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .05),
    );
    canvas.drawCircle(
      sun,
      unit * .09,
      Paint()..color = spec.sceneGlowColor.withValues(alpha: .92),
    );

    final rearDune = Path()
      ..moveTo(0, size.height * .62)
      ..quadraticBezierTo(
        size.width * .24,
        size.height * (.49 + math.sin(p * math.pi * 2) * .01),
        size.width * .53,
        size.height * .62,
      )
      ..quadraticBezierTo(
        size.width * .78,
        size.height * .73,
        size.width,
        size.height * .57,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      rearDune,
      Paint()..color = spec.scenePrimaryColor.withValues(alpha: .74),
    );

    _drawPyramid(
      canvas,
      size,
      centerX: .31,
      baseY: .76,
      width: .52,
      height: .48,
    );
    _drawPyramid(
      canvas,
      size,
      centerX: .74,
      baseY: .72,
      width: .35,
      height: .32,
    );

    final foreground = Path()
      ..moveTo(0, size.height * .79)
      ..quadraticBezierTo(
        size.width * .30,
        size.height * .69,
        size.width * .58,
        size.height * .82,
      )
      ..quadraticBezierTo(
        size.width * .82,
        size.height * .90,
        size.width,
        size.height * .75,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(foreground, Paint()..color = spec.sceneGroundColor);

    final sand = Paint()..color = spec.sceneGlowColor.withValues(alpha: .78);
    for (var index = 0; index < 7; index++) {
      final x = size.width * ((index * .19 + p) % 1);
      final y = size.height * (.74 + (index % 3) * .07);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: unit * .035,
          height: unit * .012,
        ),
        sand,
      );
    }
  }

  void _drawPyramid(
    Canvas canvas,
    Size size, {
    required double centerX,
    required double baseY,
    required double width,
    required double height,
  }) {
    final apex = Offset(size.width * centerX, size.height * (baseY - height));
    final left = Offset(
      size.width * (centerX - width / 2),
      size.height * baseY,
    );
    final right = Offset(
      size.width * (centerX + width / 2),
      size.height * baseY,
    );
    final seam = Offset(size.width * (centerX + width * .08), right.dy);
    final litFace = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(seam.dx, seam.dy)
      ..close();
    final shadowFace = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(seam.dx, seam.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(litFace, Paint()..color = spec.scenePrimaryColor);
    canvas.drawPath(shadowFace, Paint()..color = spec.sceneSecondaryColor);
    canvas.drawLine(
      apex,
      seam,
      Paint()
        ..color = spec.sceneGlowColor.withValues(alpha: .6)
        ..strokeWidth = math.max(1, size.shortestSide * .009),
    );
  }

  void _paintLivingJungle(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;
    final horizon = Offset(size.width * .53, size.height * .39);
    final river = Path()
      ..moveTo(horizon.dx - size.width * .045, horizon.dy)
      ..cubicTo(
        size.width * .36,
        size.height * .60,
        size.width * .72,
        size.height * .72,
        size.width * .90,
        size.height,
      )
      ..lineTo(size.width * .28, size.height)
      ..cubicTo(
        size.width * .46,
        size.height * .74,
        size.width * .42,
        size.height * .57,
        horizon.dx + size.width * .045,
        horizon.dy,
      )
      ..close();
    canvas.drawPath(
      river,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            spec.sceneSecondaryColor.withValues(alpha: .74),
            Color.lerp(spec.sceneSecondaryColor, Colors.white, .34)!,
          ],
        ).createShader(Offset.zero & size),
    );

    _drawJungleCanopy(canvas, size, top: true);
    _drawJungleCanopy(canvas, size, top: false);

    final waterLine = Paint()
      ..color = spec.sceneGlowColor.withValues(alpha: .46)
      ..strokeWidth = math.max(1, unit * .009)
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 5; index++) {
      final t = ((index / 5 + p) % 1);
      final y = size.height * (.45 + t * .48);
      final centerX = size.width * (.52 + math.sin(t * math.pi * 3) * .06);
      final halfWidth = size.width * (.025 + t * .18);
      canvas.drawLine(
        Offset(centerX - halfWidth, y),
        Offset(centerX + halfWidth, y),
        waterLine,
      );
    }

    final fireflyPaint = Paint()
      ..color = spec.sceneGlowColor
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .014);
    const points = [
      Offset(.18, .34),
      Offset(.82, .30),
      Offset(.28, .61),
      Offset(.75, .58),
      Offset(.14, .76),
      Offset(.88, .80),
    ];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final pulse =
          .5 + .5 * math.sin((p * 2 + index / points.length) * math.pi * 2);
      fireflyPaint.color = spec.sceneGlowColor.withValues(
        alpha: .36 + pulse * .64,
      );
      canvas.drawCircle(
        Offset(
          point.dx * size.width +
              math.sin(p * math.pi * 2 + index) * unit * .018,
          point.dy * size.height +
              math.cos(p * math.pi * 2 + index) * unit * .014,
        ),
        math.max(1.5, unit * (.010 + pulse * .008)),
        fireflyPaint,
      );
    }
  }

  void _drawJungleCanopy(Canvas canvas, Size size, {required bool top}) {
    final unit = size.shortestSide;
    final leafPaint = Paint()..color = spec.scenePrimaryColor;
    final darkLeafPaint = Paint()
      ..color = Color.lerp(spec.sceneGroundColor, Colors.black, .16)!;
    final points = top
        ? const [
            Offset(.02, .04),
            Offset(.15, .02),
            Offset(.30, .08),
            Offset(.47, .02),
            Offset(.67, .07),
            Offset(.84, .02),
            Offset(.97, .09),
          ]
        : const [
            Offset(.00, .53),
            Offset(.10, .68),
            Offset(.02, .86),
            Offset(.98, .54),
            Offset(.90, .70),
            Offset(.99, .88),
          ];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final center = Offset(point.dx * size.width, point.dy * size.height);
      final radius = unit * (top ? .15 : .13);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((index.isEven ? -1 : 1) * .35);
      final leaf = Path()
        ..moveTo(-radius, 0)
        ..quadraticBezierTo(0, -radius * .72, radius, 0)
        ..quadraticBezierTo(0, radius * .72, -radius, 0)
        ..close();
      canvas.drawPath(leaf, index.isEven ? leafPaint : darkLeafPaint);
      canvas.drawLine(
        Offset(-radius * .72, 0),
        Offset(radius * .72, 0),
        Paint()
          ..color = spec.sceneGlowColor.withValues(alpha: .18)
          ..strokeWidth = math.max(1, unit * .007),
      );
      canvas.restore();
    }
  }

  void _paintRetroArcade(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;
    final horizon = size.height * .55;
    final sunCenter = Offset(size.width * .72, size.height * .25);
    final sunRadius = unit * .19;

    canvas.drawCircle(
      sunCenter,
      sunRadius * 1.32,
      Paint()
        ..color = spec.scenePrimaryColor.withValues(alpha: .22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .07),
    );
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [spec.sceneGlowColor, spec.scenePrimaryColor],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius)),
    );
    final sunStripe = Paint()
      ..color = spec.sceneSkyColor.withValues(alpha: .88)
      ..strokeWidth = math.max(1, unit * .014);
    for (var index = 0; index < 6; index++) {
      final y = sunCenter.dy - sunRadius * .45 + index * sunRadius * .19;
      final normalized = ((y - sunCenter.dy) / sunRadius).clamp(-1.0, 1.0);
      final halfWidth =
          math.sqrt(math.max(0, 1 - normalized * normalized)) * sunRadius;
      canvas.drawLine(
        Offset(sunCenter.dx - halfWidth, y),
        Offset(sunCenter.dx + halfWidth, y),
        sunStripe,
      );
    }

    final farMountains = Path()
      ..moveTo(0, horizon)
      ..lineTo(size.width * .14, size.height * .37)
      ..lineTo(size.width * .25, size.height * .49)
      ..lineTo(size.width * .39, size.height * .31)
      ..lineTo(size.width * .52, size.height * .47)
      ..lineTo(size.width * .66, size.height * .35)
      ..lineTo(size.width * .83, size.height * .49)
      ..lineTo(size.width, size.height * .34)
      ..lineTo(size.width, horizon)
      ..close();
    canvas.drawPath(
      farMountains,
      Paint()..color = spec.scenePrimaryColor.withValues(alpha: .31),
    );
    final nearMountains = Path()
      ..moveTo(0, horizon)
      ..lineTo(size.width * .18, size.height * .43)
      ..lineTo(size.width * .33, size.height * .55)
      ..lineTo(size.width * .52, size.height * .39)
      ..lineTo(size.width * .69, size.height * .54)
      ..lineTo(size.width * .87, size.height * .42)
      ..lineTo(size.width, size.height * .52)
      ..lineTo(size.width, horizon)
      ..close();
    canvas.drawPath(nearMountains, Paint()..color = spec.sceneGroundColor);
    canvas.drawPath(
      nearMountains,
      Paint()
        ..color = spec.sceneSecondaryColor.withValues(alpha: .66)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, unit * .009),
    );

    final skylinePaint = Paint()
      ..color = Color.lerp(spec.sceneGroundColor, Colors.black, .22)!;
    const skyline = [
      (.02, .08, .10),
      (.10, .07, .15),
      (.18, .11, .08),
      (.30, .08, .18),
      (.39, .13, .12),
      (.54, .07, .17),
      (.63, .10, .11),
      (.74, .08, .19),
      (.84, .13, .13),
    ];
    for (var index = 0; index < skyline.length; index++) {
      final building = skyline[index];
      final rect = Rect.fromLTWH(
        size.width * building.$1,
        horizon - size.height * building.$3,
        size.width * building.$2,
        size.height * building.$3,
      );
      canvas.drawRect(rect, skylinePaint);
      final antennaColor = index.isEven
          ? spec.scenePrimaryColor
          : spec.sceneSecondaryColor;
      canvas.drawLine(
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, rect.top - unit * .035),
        Paint()
          ..color = antennaColor.withValues(alpha: .88)
          ..strokeWidth = math.max(1, unit * .008),
      );
      for (var row = 0; row < 2; row++) {
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + rect.width * .20,
            rect.top + rect.height * (.30 + row * .30),
            math.max(1.5, rect.width * .55),
            math.max(1.5, unit * .010),
          ),
          Paint()..color = antennaColor.withValues(alpha: .72),
        );
      }
    }

    final grid = Paint()
      ..color = spec.sceneSecondaryColor.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * .008);
    final vanishingPoint = Offset(size.width * .5, horizon);
    for (var index = -6; index <= 6; index++) {
      canvas.drawLine(
        vanishingPoint,
        Offset(size.width * (.5 + index * .16), size.height),
        grid,
      );
    }
    for (var index = 0; index < 8; index++) {
      final t = (index / 8 + p) % 1;
      final eased = t * t;
      final y = horizon + (size.height - horizon) * eased;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final scanlinePaint = Paint()
      ..color = spec.sceneGlowColor.withValues(alpha: .055)
      ..strokeWidth = math.max(1, unit * .005);
    for (var y = unit * .03; y < size.height; y += unit * .055) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanlinePaint);
    }

    const pixelStars = [
      Offset(.08, .16),
      Offset(.19, .27),
      Offset(.37, .13),
      Offset(.51, .23),
      Offset(.88, .14),
      Offset(.94, .31),
    ];
    for (var index = 0; index < pixelStars.length; index++) {
      final star = pixelStars[index];
      final pulse =
          .45 + .55 * math.sin((p * 2 + index * .21) * math.pi * 2).abs();
      final center = Offset(star.dx * size.width, star.dy * size.height);
      final radius = unit * (.008 + pulse * .008);
      final color = index.isEven
          ? spec.sceneGlowColor
          : spec.sceneSecondaryColor;
      canvas.drawRect(
        Rect.fromCenter(center: center, width: radius * 2, height: radius * 2),
        Paint()
          ..color = color.withValues(alpha: .55 + pulse * .45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .45),
      );
    }

    final racerX = size.width * ((p * 1.15 + .08) % 1);
    final racerY = horizon + size.height * .20;
    final racerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(racerX, racerY),
        width: unit * .13,
        height: unit * .045,
      ),
      Radius.circular(unit * .018),
    );
    canvas.drawRRect(
      racerRect,
      Paint()
        ..color = spec.scenePrimaryColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .014),
    );
    canvas.drawLine(
      Offset(racerX - unit * .18, racerY),
      Offset(racerX - unit * .07, racerY),
      Paint()
        ..color = spec.sceneSecondaryColor.withValues(alpha: .78)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, unit * .014),
    );
  }

  void _paintArcticAurora(Canvas canvas, Size size) {
    final p = _progress;
    final unit = size.shortestSide;

    const stars = [
      Offset(.07, .12),
      Offset(.16, .28),
      Offset(.27, .09),
      Offset(.38, .21),
      Offset(.50, .12),
      Offset(.61, .30),
      Offset(.73, .10),
      Offset(.84, .24),
      Offset(.94, .14),
      Offset(.31, .36),
      Offset(.68, .39),
    ];
    for (var index = 0; index < stars.length; index++) {
      final point = stars[index];
      final twinkle =
          .35 + .65 * math.sin((p * 2 + index * .17) * math.pi * 2).abs();
      final radius = unit * (.004 + twinkle * .006);
      canvas.drawCircle(
        Offset(point.dx * size.width, point.dy * size.height),
        math.max(1, radius),
        Paint()
          ..color = spec.sceneGlowColor.withValues(alpha: .34 + twinkle * .66),
      );
    }

    _drawAuroraRibbon(
      canvas,
      size,
      phase: p,
      baseY: .18,
      amplitude: .085,
      color: spec.scenePrimaryColor,
      width: .12,
    );
    _drawAuroraRibbon(
      canvas,
      size,
      phase: (p + .34) % 1,
      baseY: .27,
      amplitude: .095,
      color: spec.sceneSecondaryColor,
      width: .10,
    );
    _drawAuroraRibbon(
      canvas,
      size,
      phase: (p + .67) % 1,
      baseY: .35,
      amplitude: .07,
      color: spec.sceneGlowColor,
      width: .055,
    );

    final rearMountains = Path()
      ..moveTo(0, size.height * .74)
      ..lineTo(size.width * .13, size.height * .46)
      ..lineTo(size.width * .24, size.height * .64)
      ..lineTo(size.width * .40, size.height * .38)
      ..lineTo(size.width * .55, size.height * .65)
      ..lineTo(size.width * .70, size.height * .43)
      ..lineTo(size.width * .84, size.height * .62)
      ..lineTo(size.width, size.height * .42)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      rearMountains,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(spec.sceneSecondaryColor, Colors.white, .24)!,
            spec.sceneGroundColor,
          ],
        ).createShader(Offset.zero & size),
    );

    final snowCaps = Path()
      ..moveTo(size.width * .13, size.height * .46)
      ..lineTo(size.width * .085, size.height * .555)
      ..lineTo(size.width * .13, size.height * .525)
      ..lineTo(size.width * .17, size.height * .57)
      ..close()
      ..moveTo(size.width * .40, size.height * .38)
      ..lineTo(size.width * .34, size.height * .485)
      ..lineTo(size.width * .40, size.height * .455)
      ..lineTo(size.width * .46, size.height * .49)
      ..close()
      ..moveTo(size.width * .70, size.height * .43)
      ..lineTo(size.width * .65, size.height * .52)
      ..lineTo(size.width * .70, size.height * .495)
      ..lineTo(size.width * .75, size.height * .535)
      ..close()
      ..moveTo(size.width, size.height * .42)
      ..lineTo(size.width * .94, size.height * .54)
      ..lineTo(size.width, size.height * .50)
      ..close();
    canvas.drawPath(
      snowCaps,
      Paint()..color = spec.sceneGlowColor.withValues(alpha: .86),
    );

    final foreground = Path()
      ..moveTo(0, size.height * .76)
      ..quadraticBezierTo(
        size.width * .26,
        size.height * .68,
        size.width * .52,
        size.height * .80,
      )
      ..quadraticBezierTo(
        size.width * .76,
        size.height * .91,
        size.width,
        size.height * .73,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(foreground, Paint()..color = spec.sceneGroundColor);

    final iceGlow = Paint()
      ..color = spec.scenePrimaryColor.withValues(alpha: .40)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, unit * .009);
    for (var index = 0; index < 5; index++) {
      final t = (index / 5 + p) % 1;
      final y = size.height * (.78 + t * .18);
      final halfWidth = size.width * (.04 + t * .20);
      final centerX = size.width * (.50 + math.sin(t * math.pi * 2) * .06);
      canvas.drawLine(
        Offset(centerX - halfWidth, y),
        Offset(centerX + halfWidth, y),
        iceGlow,
      );
    }

    const snowSeeds = [
      Offset(.06, .06),
      Offset(.18, .17),
      Offset(.29, .03),
      Offset(.42, .14),
      Offset(.56, .06),
      Offset(.69, .20),
      Offset(.81, .04),
      Offset(.93, .16),
      Offset(.11, .38),
      Offset(.52, .43),
      Offset(.88, .36),
    ];
    for (var index = 0; index < snowSeeds.length; index++) {
      final seed = snowSeeds[index];
      final drift = (p + index * .093) % 1;
      final x =
          (seed.dx + math.sin((p + index) * math.pi * 2) * .025) * size.width;
      final y = ((seed.dy + drift * .72) % 1) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        math.max(1, unit * (.005 + (index % 3) * .003)),
        Paint()..color = spec.sceneGlowColor.withValues(alpha: .58),
      );
    }
  }

  void _drawAuroraRibbon(
    Canvas canvas,
    Size size, {
    required double phase,
    required double baseY,
    required double amplitude,
    required Color color,
    required double width,
  }) {
    final unit = size.shortestSide;
    final wave = math.sin(phase * math.pi * 2);
    final path = Path()
      ..moveTo(-size.width * .08, size.height * (baseY + amplitude * wave))
      ..cubicTo(
        size.width * .18,
        size.height *
            (baseY - amplitude * math.sin((phase + .18) * math.pi * 2)),
        size.width * .34,
        size.height *
            (baseY + amplitude * math.sin((phase + .38) * math.pi * 2)),
        size.width * .52,
        size.height *
            (baseY - amplitude * math.sin((phase + .56) * math.pi * 2)),
      )
      ..cubicTo(
        size.width * .68,
        size.height *
            (baseY + amplitude * math.sin((phase + .72) * math.pi * 2)),
        size.width * .86,
        size.height *
            (baseY - amplitude * math.sin((phase + .88) * math.pi * 2)),
        size.width * 1.08,
        size.height *
            (baseY + amplitude * math.sin((phase + 1.06) * math.pi * 2)),
      );
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height * .55);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: .08),
            color.withValues(alpha: .72),
            spec.sceneGlowColor.withValues(alpha: .26),
            color.withValues(alpha: .08),
          ],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = unit * width * 1.9
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * width * .52),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: .20),
            color.withValues(alpha: .92),
            spec.sceneGlowColor.withValues(alpha: .56),
            color.withValues(alpha: .20),
          ],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1, unit * width * .56),
    );
  }

  @override
  bool shouldRepaint(covariant ThemeScenePainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate._progress != _progress;
}

const defaultTokenVisualSpec = TokenVisualSpec(
  id: 'tokens_default',
  detailColor: Color(0xFFFFFFFF),
  highlightColor: Color(0xCCFFFFFF),
  outlineColor: Color(0xFFFFFFFF),
  glowColor: Color(0x4017284D),
  stageColor: Color(0xFFF1F5FC),
  motif: TokenMotif.star,
);

const Map<String, TokenVisualSpec> tokenVisualSpecs = {
  'tokens_default': defaultTokenVisualSpec,
  'tokens_robot': TokenVisualSpec(
    id: 'tokens_robot',
    detailColor: Color(0xFFFFFFFF),
    highlightColor: Color(0xFFDFF6FF),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0x6632B875),
    stageColor: Color(0xFFDDF6EA),
    motif: TokenMotif.robot,
  ),
  'tokens_crystal': TokenVisualSpec(
    id: 'tokens_crystal',
    detailColor: Color(0xFFFFFFFF),
    highlightColor: Color(0xFFC8F7FF),
    outlineColor: Color(0xFFF3FEFF),
    glowColor: Color(0x9973D7FF),
    stageColor: Color(0xFFEAFBFF),
    motif: TokenMotif.crystal,
  ),
  'tokens_rocket': TokenVisualSpec(
    id: 'tokens_rocket',
    detailColor: Color(0xFFFFFFFF),
    highlightColor: Color(0xFFFFE082),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0x99FF8A24),
    stageColor: Color(0xFFFFF2DF),
    motif: TokenMotif.rocket,
  ),
  'tokens_crown': TokenVisualSpec(
    id: 'tokens_crown',
    detailColor: Color(0xFFFFD45C),
    highlightColor: Color(0xFFFFF4B0),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0x99D8A51E),
    stageColor: Color(0xFFFFF7D9),
    motif: TokenMotif.crown,
  ),
  'tokens_neon_pulse': TokenVisualSpec(
    id: 'tokens_neon_pulse',
    detailColor: Color(0xFF58F5FF),
    highlightColor: Color(0xFFFF4FD8),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xB300E5FF),
    stageColor: Color(0xFF090E2C),
    motif: TokenMotif.neonPulse,
  ),
  'tokens_solar_scarab': TokenVisualSpec(
    id: 'tokens_solar_scarab',
    detailColor: Color(0xFFFFC84B),
    highlightColor: Color(0xFFFFF1A3),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xB3D89A26),
    stageColor: Color(0xFF392513),
    motif: TokenMotif.solarScarab,
  ),
  'tokens_jungle_totem': TokenVisualSpec(
    id: 'tokens_jungle_totem',
    detailColor: Color(0xFFD8FF79),
    highlightColor: Color(0xFFFFFFFF),
    outlineColor: Color(0xFFF3FFE7),
    glowColor: Color(0xA634D17B),
    stageColor: Color(0xFF0A3D35),
    motif: TokenMotif.jungleTotem,
  ),
  'tokens_pixel_blaster': TokenVisualSpec(
    id: 'tokens_pixel_blaster',
    detailColor: Color(0xFFFF4FD8),
    highlightColor: Color(0xFF58F5FF),
    outlineColor: Color(0xFFFFE45C),
    glowColor: Color(0xB3FF4FD8),
    stageColor: Color(0xFF160A32),
    motif: TokenMotif.pixelBlaster,
  ),
  'tokens_aurora_shard': TokenVisualSpec(
    id: 'tokens_aurora_shard',
    detailColor: Color(0xFF38E8C6),
    highlightColor: Color(0xFFD9FFFF),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xB39A7DFF),
    stageColor: Color(0xFF06162E),
    motif: TokenMotif.auroraShard,
  ),
  'tokens_cosmic_realms_red': TokenVisualSpec(
    id: 'tokens_cosmic_realms_red',
    detailColor: Color(0xFFFFD76B),
    highlightColor: Color(0xFFFFEEF6),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xCCE42E62),
    stageColor: Color(0xFF160611),
    motif: TokenMotif.cosmicCore,
  ),
  'tokens_cosmic_realms_yellow': TokenVisualSpec(
    id: 'tokens_cosmic_realms_yellow',
    detailColor: Color(0xFFFFE071),
    highlightColor: Color(0xFFFFF8D4),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xCCF2B51D),
    stageColor: Color(0xFF160F02),
    motif: TokenMotif.cosmicCore,
  ),
  'tokens_cosmic_realms_blue': TokenVisualSpec(
    id: 'tokens_cosmic_realms_blue',
    detailColor: Color(0xFF79E9FF),
    highlightColor: Color(0xFFEAFBFF),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xCC248BFF),
    stageColor: Color(0xFF030D1E),
    motif: TokenMotif.cosmicCore,
  ),
  'tokens_cosmic_realms_green': TokenVisualSpec(
    id: 'tokens_cosmic_realms_green',
    detailColor: Color(0xFFD4FF7A),
    highlightColor: Color(0xFFEFFFF4),
    outlineColor: Color(0xFFFFFFFF),
    glowColor: Color(0xCC20C982),
    stageColor: Color(0xFF02150E),
    motif: TokenMotif.cosmicCore,
  ),
};

const Set<String> supportedTokenStyleIds = {
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
  'tokens_cosmic_realms_red',
  'tokens_cosmic_realms_yellow',
  'tokens_cosmic_realms_blue',
  'tokens_cosmic_realms_green',
};

TokenVisualSpec tokenVisualSpecFor(String? productId) =>
    tokenVisualSpecs[productId] ?? defaultTokenVisualSpec;

/// Matching pieces used to present every board theme as a coordinated set.
///
/// Most products remain independently purchasable and equippable. A small
/// number of complete packs deliberately bundle their matching pieces.
const Map<String, String> matchingTokenStyleIdByThemeId = {
  'theme_default': 'tokens_default',
  'theme_neon_rush': 'tokens_neon_pulse',
  'theme_golden_night': 'tokens_solar_scarab',
  'theme_tropical_splash': 'tokens_jungle_totem',
  'theme_celestial_carnival': 'tokens_pixel_blaster',
  'theme_velvet_lounge': 'tokens_aurora_shard',
  'theme_cosmic_realms_red': 'tokens_cosmic_realms_red',
  'theme_cosmic_realms_yellow': 'tokens_cosmic_realms_yellow',
  'theme_cosmic_realms_blue': 'tokens_cosmic_realms_blue',
  'theme_cosmic_realms_green': 'tokens_cosmic_realms_green',
};

/// Complete packs whose piece design is part of the purchased board theme.
const Map<String, String> bundledTokenStyleIdByThemeId = {
  'theme_cosmic_realms_red': 'tokens_cosmic_realms_red',
  'theme_cosmic_realms_yellow': 'tokens_cosmic_realms_yellow',
  'theme_cosmic_realms_blue': 'tokens_cosmic_realms_blue',
  'theme_cosmic_realms_green': 'tokens_cosmic_realms_green',
};

String? bundledTokenStyleIdForTheme(String? themeId) =>
    bundledTokenStyleIdByThemeId[themeId];

String? resolvedTokenStyleIdForTheme({
  required String? themeId,
  required String? selectedTokenStyleId,
}) => bundledTokenStyleIdForTheme(themeId) ?? selectedTokenStyleId;

String? matchingTokenStyleIdForTheme(String? themeId) =>
    matchingTokenStyleIdByThemeId[themeId];

String? matchingThemeStyleIdForToken(String? tokenStyleId) {
  if (tokenStyleId == null) return null;
  for (final entry in matchingTokenStyleIdByThemeId.entries) {
    if (entry.value == tokenStyleId) return entry.key;
  }
  return null;
}

const defaultAvatarVisualSpec = AvatarVisualSpec(
  id: 'avatar_default',
  backgroundColors: [Color(0xFFFFC83D), Color(0xFFFF9F1C)],
  primaryColor: Color(0xFF17284D),
  accentColor: Color(0xFFFFFFFF),
  borderColor: Color(0xFFFFFFFF),
  glowColor: Color(0x66FFC83D),
  motif: AvatarMotif.controller,
);

const Map<String, AvatarVisualSpec> avatarVisualSpecs = {
  'avatar_default': defaultAvatarVisualSpec,
  'avatar_astro': AvatarVisualSpec(
    id: 'avatar_astro',
    backgroundColors: [Color(0xFF2474E5), Color(0xFF6C4DFF)],
    primaryColor: Color(0xFFF7FAFF),
    accentColor: Color(0xFF73D7FF),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x802474E5),
    motif: AvatarMotif.astronaut,
  ),
  'avatar_ninja': AvatarVisualSpec(
    id: 'avatar_ninja',
    backgroundColors: [Color(0xFF7B61FF), Color(0xFF31245E)],
    primaryColor: Color(0xFF15162E),
    accentColor: Color(0xFFFFC83D),
    borderColor: Color(0xFFE8DDFF),
    glowColor: Color(0x807B61FF),
    motif: AvatarMotif.ninja,
  ),
  'avatar_robot': AvatarVisualSpec(
    id: 'avatar_robot',
    backgroundColors: [Color(0xFF32B875), Color(0xFF087F75)],
    primaryColor: Color(0xFFFFFFFF),
    accentColor: Color(0xFF58F5FF),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x8032B875),
    motif: AvatarMotif.robot,
  ),
  'avatar_explorer': AvatarVisualSpec(
    id: 'avatar_explorer',
    backgroundColors: [Color(0xFFFFA143), Color(0xFFFF6B35)],
    primaryColor: Color(0xFF6C3E1F),
    accentColor: Color(0xFFFFF4C7),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x80FF8A24),
    motif: AvatarMotif.explorer,
  ),
  'avatar_comet': AvatarVisualSpec(
    id: 'avatar_comet',
    backgroundColors: [Color(0xFF5B4BDB), Color(0xFF272A72)],
    primaryColor: Color(0xFFFFD34E),
    accentColor: Color(0xFF4DE1FF),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x805B4BDB),
    motif: AvatarMotif.comet,
  ),
  'avatar_axolotl': AvatarVisualSpec(
    id: 'avatar_axolotl',
    backgroundColors: [Color(0xFF41D6C3), Color(0xFF168F9F)],
    primaryColor: Color(0xFFFF8BA8),
    accentColor: Color(0xFFFFF8E8),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x8041D6C3),
    motif: AvatarMotif.axolotl,
  ),
  'avatar_toucan': AvatarVisualSpec(
    id: 'avatar_toucan',
    backgroundColors: [Color(0xFF27C6A3), Color(0xFF126B78)],
    primaryColor: Color(0xFF17284D),
    accentColor: Color(0xFFFF8A24),
    borderColor: Color(0xFFFFFFFF),
    glowColor: Color(0x8027C6A3),
    motif: AvatarMotif.toucan,
  ),
};

const Set<String> supportedAvatarStyleIds = {
  'avatar_default',
  'avatar_astro',
  'avatar_ninja',
  'avatar_robot',
  'avatar_explorer',
  'avatar_comet',
  'avatar_axolotl',
  'avatar_toucan',
};

AvatarVisualSpec avatarVisualSpecFor(String? productId) =>
    avatarVisualSpecs[productId] ?? defaultAvatarVisualSpec;
