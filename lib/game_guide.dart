import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_language.dart';

/// The rule sets presented by [GameGuideScreen].
enum GameGuideMode { traditional, chaos, quickPop }

/// Effects that can be previewed in [TrapPowerLab].
enum GuideEffect { shield, turbo, glue, setback, prison, bomb }

/// Standalone, game-styled help screen for Parchís Pop.
///
/// This file deliberately does not import `main.dart`, so the screen can be
/// pushed from any route without creating an import cycle.
class GameGuideScreen extends StatefulWidget {
  const GameGuideScreen({
    super.key,
    this.initialMode = GameGuideMode.traditional,
  });

  final GameGuideMode initialMode;

  @override
  State<GameGuideScreen> createState() => _GameGuideScreenState();
}

class _GameGuideScreenState extends State<GameGuideScreen> {
  final GlobalKey _powerLabKey = GlobalKey();
  late GameGuideMode _mode = widget.initialMode;

  void _showPowerLab() {
    final context = _powerLabKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      alignment: .04,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = switch (_mode) {
      GameGuideMode.traditional => traditionalRuleSections,
      GameGuideMode.chaos => [...traditionalRuleSections, ...chaosRuleSections],
      GameGuideMode.quickPop => quickPopRuleSections,
    };
    return Scaffold(
      backgroundColor: GuidePalette.navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GuidePalette.deepBlue,
              GuidePalette.navy,
              Color(0xFF111A39),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            key: const ValueKey('game-guide-scroll'),
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _GuideTopBar(onPowerLab: _showPowerLab),
              ),
              const SliverToBoxAdapter(child: _GuideHero()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: _ModeSelector(
                    value: _mode,
                    onChanged: (mode) => setState(() => _mode = mode),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    child: _ModeSummary(key: ValueKey(_mode), mode: _mode),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _RulesGrid(
                    key: ValueKey('rules-${_mode.name}'),
                    sections: sections,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  key: _powerLabKey,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: const TrapPowerLab(),
                ),
              ),
              SliverToBoxAdapter(child: _QuickReference(mode: _mode)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Focused arcade screen that contains only the Chaos traps, powers and their
/// playable animations. The complete rules remain in [GameGuideScreen].
class TrapPowerLabScreen extends StatelessWidget {
  const TrapPowerLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('trap-power-lab-screen'),
      backgroundColor: GuidePalette.navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              GuidePalette.deepBlue,
              GuidePalette.navy,
              Color(0xFF111A39),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            key: const ValueKey('trap-power-lab-scroll'),
            physics: const BouncingScrollPhysics(),
            slivers: const [
              SliverToBoxAdapter(child: _TrapLabTopBar()),
              SliverToBoxAdapter(child: _TrapLabHero()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: TrapPowerLab(mode: TrapPowerLabMode.trapsOnly),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrapLabTopBar extends StatelessWidget {
  const _TrapLabTopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _RoundButton(
            key: const ValueKey('trap-lab-back'),
            tooltip: 'Volver',
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: PopText(
              'Parchís Pop',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: GuidePalette.red,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 17),
                SizedBox(width: 5),
                PopText(
                  'MODO CAOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
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

class _TrapLabHero extends StatelessWidget {
  const _TrapLabHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        key: const ValueKey('trap-lab-hero'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [GuidePalette.red, Color(0xFF7C4DFF)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: const Row(
          children: [
            _TrapLabHeroIcon(),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    'TRAMPAS Y ANIMACIONES',
                    style: TextStyle(
                      color: GuidePalette.yellow,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  PopText(
                    'Míralos en acción',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 7),
                  PopText(
                    'Toca cada trampa o reproduce todas sus animaciones.',
                    style: TextStyle(
                      color: Color(0xFFE8EDFF),
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
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

class _TrapLabHeroIcon extends StatelessWidget {
  const _TrapLabHeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GuidePalette.yellow,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 9,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.science_rounded,
        size: 36,
        color: GuidePalette.navy,
      ),
    );
  }
}

class GuidePalette {
  static const navy = Color(0xFF17284D);
  static const deepBlue = Color(0xFF153E78);
  static const ink = Color(0xFF243047);
  static const cloud = Color(0xFFF5F8FF);
  static const blue = Color(0xFF2474E5);
  static const red = Color(0xFFF04452);
  static const yellow = Color(0xFFFFC83D);
  static const green = Color(0xFF32B875);
  static const violet = Color(0xFF7C4DFF);
  static const cyan = Color(0xFF00AFC4);
}

class GuideRuleSection {
  const GuideRuleSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.rules,
    this.badge,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<String> rules;
  final String? badge;
}

const traditionalRuleSections = <GuideRuleSection>[
  GuideRuleSection(
    icon: Icons.emoji_events_rounded,
    title: 'Objetivo y tablero',
    color: GuidePalette.yellow,
    rules: [
      'Cada jugador controla 4 fichas y lanza 2 dados.',
      'Recorre 64 casillas comunes desde tu salida, gira por las 7 casillas de tu pasillo y llega al centro.',
      'Gana quien coloque primero sus 4 fichas en la meta.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.exit_to_app_rounded,
    title: 'Salir con un 5',
    color: GuidePalette.red,
    badge: 'SALIDA',
    rules: [
      'Una ficha sale de la cárcel solo con un 5 físico en uno de los dados. No vale sumar los dos dados.',
      'Mientras queden fichas en la cárcel y la salida esté libre, cada 5 se usa obligatoriamente como SALIDA.',
      'Un doble 5 puede sacar 2 fichas. Si todas están fuera —o la salida está bloqueada— el 5 mueve 5 pasos.',
      'Si hay una sola ficha rival en tu salida, el 5 la captura. Una barrera rival de 2 fichas impide salir.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.casino_rounded,
    title: 'Usar los dos dados',
    color: GuidePalette.blue,
    rules: [
      'Puedes repartir los valores entre fichas o usar los dos dados juntos con una misma ficha.',
      'Selecciona una ficha y elige un dado por separado o pulsa TODOS para avanzar la suma y consumir ambos dados.',
      'TODOS resuelve solamente la casilla final, no incluye bonos +10/+20 y desaparece después de usar uno de los dados.',
      'Un doble muestra un solo valor, pero conserva sus 2 usos.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.star_rounded,
    title: 'Seguros y salidas',
    color: GuidePalette.green,
    badge: '12 SEGUROS',
    rules: [
      'Las 8 estrellas y las 4 casillas de salida son seguras.',
      'Un rival puede pasar sobre una ficha solitaria en un seguro, pero nunca terminar allí.',
      'Dos colores contrarios no pueden compartir un seguro. Dos fichas propias sí pueden compartirlo y forman barrera.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.my_location_rounded,
    title: 'Capturas y bono +20',
    color: GuidePalette.red,
    badge: '+20',
    rules: [
      'Para capturar debes caer exactamente sobre una ficha rival en una casilla blanca.',
      'La ficha capturada vuelve a su cárcel y recibes un movimiento de 20 pasos.',
      'El bono +20 se usa completo con una sola ficha; no se divide.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.view_week_rounded,
    title: 'Barreras',
    color: GuidePalette.violet,
    rules: [
      'Dos fichas del mismo color en una casilla forman una barrera.',
      'Ninguna ficha puede atravesar una barrera, ni siquiera con doble 5.',
      'El dueño puede mover una de las dos fichas para abrir su propia barrera.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.sync_rounded,
    title: 'Dobles',
    color: GuidePalette.cyan,
    rules: [
      'Sacar dobles concede otra tirada después de completar los movimientos legales.',
      'Al tercer doble consecutivo se anula esa jugada y la ficha propia más adelantada vuelve a la cárcel.',
      'Una ficha que ya está protegida en su pasillo final no recibe esa penalización.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.turn_right_rounded,
    title: 'Tu entrada y pasillo',
    color: GuidePalette.green,
    badge: '5 FÍSICO',
    rules: [
      'Todas tus fichas giran siempre por la entrada y el pasillo de su propio color.',
      'Una rival solitaria en la puerta bloquea el paso normal. Si estás justo antes y usas un 5 físico, la capturas, cruzas y completas los 5 pasos dentro del pasillo.',
      'Posiciones anteriores: rojo 63, verde 12, amarillo 29 y azul 46.',
      'Dos rivales en la puerta forman una barrera imposible de romper.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.home_rounded,
    title: 'Meta, +10 y victoria',
    color: GuidePalette.yellow,
    badge: '+10',
    rules: [
      'Debes obtener el número exacto para entrar a la meta; no hay rebote ni exceso.',
      'Completar una ficha concede un movimiento adicional de 10 pasos con otra ficha legal.',
      'Al completar la cuarta ficha termina la partida y aparece la celebración de victoria.',
    ],
  ),
];

const quickPopRuleSections = <GuideRuleSection>[
  GuideRuleSection(
    icon: Icons.speed_rounded,
    title: 'Quick Pop',
    color: GuidePalette.green,
    badge: '2 FICHAS',
    rules: [
      'Cada jugador usa 2 fichas en el tablero completo de 68 casillas.',
      'Las dos fichas empiezan juntas en la salida; no pasan por la cárcel.',
      'Gana quien lleve primero sus 2 fichas al centro.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.outbound_rounded,
    title: 'Empieza de inmediato',
    color: GuidePalette.blue,
    badge: 'SIN 5',
    rules: [
      'No necesitas sacar un 5 para comenzar: toca una ficha y elige un movimiento legal.',
      'La pareja inicial está protegida y no bloquea el paso como barrera.',
      'Cuando solo existe una jugada legal, el juego la realiza automáticamente.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.casino_rounded,
    title: 'Dados y decisiones',
    color: GuidePalette.violet,
    rules: [
      'Puedes repartir los dos dados entre tus fichas o usar TODOS con una sola ficha.',
      'Un doble conserva sus 2 usos y concede otra tirada al completar los movimientos.',
      'Debes obtener el número exacto para entrar a la meta.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.my_location_rounded,
    title: 'Capturas y regreso',
    color: GuidePalette.red,
    badge: '+20',
    rules: [
      'Captura al caer exactamente sobre una ficha rival fuera de una casilla segura.',
      'La ficha capturada vuelve a su salida, no a una cárcel.',
      'Capturar concede +20 y completar una ficha concede +10.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.star_rounded,
    title: 'Reglas que se conservan',
    color: GuidePalette.yellow,
    rules: [
      'Se mantienen los seguros, barreras, entradas de color y pasillos de 7 casillas.',
      'Ninguna ficha puede atravesar una barrera.',
      'Quick Pop acorta la partida sin recortar el recorrido original.',
    ],
  ),
];

const chaosRuleSections = <GuideRuleSection>[
  GuideRuleSection(
    icon: Icons.auto_awesome_rounded,
    title: 'Cristales sorpresa',
    color: GuidePalette.yellow,
    badge: 'MODO CAOS',
    rules: [
      'Caos conserva todas las reglas tradicionales y añade cristales, poderes y trampas.',
      'Hay siempre 1 cristal activo en cada lado del tablero. Debes caer exactamente sobre él para recogerlo.',
      'Al recogerlo desaparece y reaparece de inmediato en otra casilla válida del mismo lado.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.bolt_rounded,
    title: 'Poderes automáticos',
    color: GuidePalette.violet,
    rules: [
      'El Escudo se guarda para el jugador completo y se activa automáticamente cuando cualquiera de sus cuatro fichas cae en una trampa rival.',
      'El Escudo y la trampa se consumen al bloquear el efecto. Turbo se guarda y el jugador decide cuándo usarlo.',
      'Tener un Escudo o Turbo guardado nunca impide recoger y armar nuevas trampas.',
    ],
  ),
  GuideRuleSection(
    icon: Icons.visibility_off_rounded,
    title: 'Trampas ocultas',
    color: GuidePalette.red,
    rules: [
      'Pegamento, Retroceso, Cárcel y Bomba se arman automáticamente en la misma casilla donde recogiste el cristal.',
      'Puedes mantener varias trampas en el tablero. Solo el dueño ve sus tipos y ubicaciones; los rivales ven únicamente cuántas trampas ocultas existen.',
      'Cada trampa es de un solo uso, no afecta a su dueño y un Escudo puede bloquearla.',
      'Nunca aparecen en seguros, salidas, pasillos de meta, otro cristal ni otra trampa.',
    ],
  ),
];

class _GuideTopBar extends StatelessWidget {
  const _GuideTopBar({required this.onPowerLab});

  final VoidCallback onPowerLab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _RoundButton(
            key: const ValueKey('guide-back'),
            tooltip: 'Volver',
            icon: Icons.arrow_back_rounded,
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: PopText(
              'Parchís Pop',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: .2,
              ),
            ),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('show-power-lab'),
            onPressed: onPowerLab,
            icon: const Icon(Icons.science_rounded, size: 19),
            label: const PopText('Ver trampas'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .14),
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: appTranslate(context, tooltip),
      child: Material(
        color: Colors.white.withValues(alpha: .14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _GuideHero extends StatelessWidget {
  const _GuideHero();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        key: const ValueKey('guide-hero'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [GuidePalette.blue, Color(0xFF6C4DFF)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GuidePalette.yellow,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 9,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 36,
                color: GuidePalette.navy,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PopText(
                    'CÓMO JUGAR',
                    style: TextStyle(
                      color: GuidePalette.yellow,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.7,
                    ),
                  ),
                  SizedBox(height: 4),
                  PopText(
                    'De la salida a la victoria',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 7),
                  PopText(
                    'Reglas claras, ejemplos rápidos y efectos que puedes probar.',
                    style: TextStyle(
                      color: Color(0xFFE8EDFF),
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
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

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.value, required this.onChanged});

  final GameGuideMode value;
  final ValueChanged<GameGuideMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemWidth,
              child: _ModeButton(
                key: const ValueKey('guide-mode-traditional'),
                selected: value == GameGuideMode.traditional,
                icon: Icons.emoji_events_rounded,
                title: 'TRADICIONAL',
                subtitle: 'Parchís clásico',
                color: GuidePalette.blue,
                onTap: () => onChanged(GameGuideMode.traditional),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _ModeButton(
                key: const ValueKey('guide-mode-chaos'),
                selected: value == GameGuideMode.chaos,
                icon: Icons.auto_awesome_rounded,
                title: 'CAOS',
                subtitle: 'Poderes y trampas',
                color: GuidePalette.red,
                onTap: () => onChanged(GameGuideMode.chaos),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _ModeButton(
                key: const ValueKey('guide-mode-quick-pop'),
                selected: value == GameGuideMode.quickPop,
                icon: Icons.speed_rounded,
                title: 'QUICK POP',
                subtitle: 'Rápido · 2 fichas',
                color: GuidePalette.green,
                onTap: () => onChanged(GameGuideMode.quickPop),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      scale: selected ? 1 : .97,
      child: Material(
        color: selected ? color : Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 86,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: .2),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: .45),
                        blurRadius: 15,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const SizedBox(width: 9),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      PopText(
                        subtitle,
                        maxLines: 2,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .82),
                          fontSize: 11,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _ModeSummary extends StatelessWidget {
  const _ModeSummary({super.key, required this.mode});

  final GameGuideMode mode;

  @override
  Widget build(BuildContext context) {
    final (color, icon, description) = switch (mode) {
      GameGuideMode.traditional => (
        GuidePalette.blue,
        Icons.check_circle_rounded,
        'Modo Tradicional: carrera pura con dados, seguros, barreras, capturas y estrategia.',
      ),
      GameGuideMode.chaos => (
        GuidePalette.red,
        Icons.bolt_rounded,
        'Modo Caos: todas las reglas tradicionales + cristales, poderes automáticos y varias trampas ocultas.',
      ),
      GameGuideMode.quickPop => (
        GuidePalette.green,
        Icons.speed_rounded,
        'Quick Pop: tablero completo, 2 fichas ya en salida y una carrera más corta sin esperar un 5.',
      ),
    };
    return Container(
      key: ValueKey('guide-summary-${mode.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .35), width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: .12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: PopText(
              description,
              style: const TextStyle(
                color: GuidePalette.ink,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesGrid extends StatelessWidget {
  const _RulesGrid({super.key, required this.sections});

  final List<GuideRuleSection> sections;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        final itemWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final section in sections)
              SizedBox(
                width: itemWidth,
                child: _RuleCard(section: section),
              ),
          ],
        );
      },
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.section});

  final GuideRuleSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: GuidePalette.cloud,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: section.color,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: section.color.withValues(alpha: .35),
                      blurRadius: 7,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(section.icon, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PopText(
                  section.title,
                  style: const TextStyle(
                    color: GuidePalette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (section.badge case final badge?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: section.color.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: PopText(
                    badge,
                    style: TextStyle(
                      color: Color.lerp(section.color, Colors.black, .18),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 11),
          for (final rule in section.rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: section.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: PopText(
                      rule,
                      style: const TextStyle(
                        color: GuidePalette.ink,
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
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
}

@immutable
class _GuideEffectSpec {
  const _GuideEffectSpec({
    required this.type,
    required this.title,
    required this.shortRule,
    required this.callout,
    required this.icon,
    required this.color,
  });

  final GuideEffect type;
  final String title;
  final String shortRule;
  final String callout;
  final IconData icon;
  final Color color;
}

const _effectSpecs = <_GuideEffectSpec>[
  _GuideEffectSpec(
    type: GuideEffect.shield,
    title: 'Escudo',
    shortRule: 'Se activa solo y bloquea una trampa.',
    callout: '¡PROTEGIDO!',
    icon: Icons.shield_rounded,
    color: GuidePalette.blue,
  ),
  _GuideEffectSpec(
    type: GuideEffect.turbo,
    title: 'Turbo',
    shortRule: 'Concede movimiento adicional.',
    callout: '¡TURBO!',
    icon: Icons.rocket_launch_rounded,
    color: GuidePalette.green,
  ),
  _GuideEffectSpec(
    type: GuideEffect.glue,
    title: 'Pegamento',
    shortRule: 'La ficha pierde su próximo turno.',
    callout: 'TURNO PERDIDO',
    icon: Icons.water_drop_rounded,
    color: Color(0xFF9B5DE5),
  ),
  _GuideEffectSpec(
    type: GuideEffect.setback,
    title: 'Retroceso',
    shortRule: 'La ficha retrocede hasta 6 pasos.',
    callout: 'RETROCESO −6',
    icon: Icons.fast_rewind_rounded,
    color: Color(0xFFFF7A21),
  ),
  _GuideEffectSpec(
    type: GuideEffect.prison,
    title: 'Cárcel',
    shortRule: 'Devuelve esa ficha a su base.',
    callout: '¡A LA CÁRCEL!',
    icon: Icons.lock_rounded,
    color: GuidePalette.navy,
  ),
  _GuideEffectSpec(
    type: GuideEffect.bomb,
    title: 'Bomba',
    shortRule: 'Explota y devuelve la ficha a su base.',
    callout: '¡BUM! A LA CÁRCEL',
    icon: Icons.local_fire_department_rounded,
    color: GuidePalette.red,
  ),
];

enum TrapPowerLabMode { all, trapsOnly }

/// Interactive explanation of the initial Chaos effects.
class TrapPowerLab extends StatefulWidget {
  const TrapPowerLab({super.key, this.mode = TrapPowerLabMode.all});

  /// Long enough for the player to understand the complete reaction.
  static const demoDuration = Duration(milliseconds: 2200);

  final TrapPowerLabMode mode;

  @override
  State<TrapPowerLab> createState() => _TrapPowerLabState();
}

class _TrapPowerLabState extends State<TrapPowerLab>
    with SingleTickerProviderStateMixin {
  static const _trapEffects = {
    GuideEffect.glue,
    GuideEffect.setback,
    GuideEffect.prison,
    GuideEffect.bomb,
  };

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: TrapPowerLab.demoDuration)
        ..addStatusListener((status) {
          if (mounted && status == AnimationStatus.completed) {
            setState(() {});
          }
        });

  late _GuideEffectSpec _selected;
  var _sequenceId = 0;
  var _playingAll = false;

  List<_GuideEffectSpec> get _availableSpecs =>
      widget.mode == TrapPowerLabMode.trapsOnly
      ? _effectSpecs
            .where((spec) => _trapEffects.contains(spec.type))
            .toList(growable: false)
      : _effectSpecs;

  @override
  void initState() {
    super.initState();
    _selected = _availableSpecs.first;
  }

  @override
  void didUpdateWidget(covariant TrapPowerLab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode == widget.mode) return;
    _sequenceId++;
    _controller.stop();
    _playingAll = false;
    _selected = _availableSpecs.first;
  }

  void _play(_GuideEffectSpec spec) {
    _sequenceId++;
    setState(() {
      _playingAll = false;
      _selected = spec;
    });
    _controller.forward(from: 0);
  }

  Future<void> _playAll() async {
    final sequenceId = ++_sequenceId;
    setState(() => _playingAll = true);
    try {
      for (final spec in _availableSpecs) {
        if (!mounted || sequenceId != _sequenceId) return;
        setState(() => _selected = spec);
        await _controller.forward(from: 0).orCancel;
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
    } on TickerCanceled {
      return;
    } finally {
      if (mounted && sequenceId == _sequenceId) {
        setState(() => _playingAll = false);
      }
    }
  }

  void _stopSequence() {
    _sequenceId++;
    _controller.stop();
    setState(() => _playingAll = false);
  }

  @override
  void dispose() {
    _sequenceId++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final specs = _availableSpecs;
    final trapsOnly = widget.mode == TrapPowerLabMode.trapsOnly;
    return Container(
      key: const ValueKey('trap-power-lab'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: GuidePalette.yellow, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 17,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LabBadge(),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PopText(
                      trapsOnly
                          ? 'Laboratorio de trampas'
                          : 'Laboratorio de poderes',
                      style: const TextStyle(
                        color: GuidePalette.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const PopText(
                      'Toca una tarjeta o usa “Ver todos” para mirar la secuencia completa.',
                      style: TextStyle(
                        color: Color(0xFF667088),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const _PowerRulesStrip(),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 760 ? 3 : 2;
              final width = (constraints.maxWidth - (count - 1) * 8) / count;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final spec in specs)
                    SizedBox(
                      width: width,
                      child: _EffectChoice(
                        key: ValueKey('guide-effect-${spec.type.name}'),
                        spec: spec,
                        selected: spec.type == _selected.type,
                        onTap: () => _play(spec),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _PowerEffectStage(
              spec: _selected,
              progress: _controller.value,
              playing: _controller.isAnimating,
              sequencePosition: _playingAll
                  ? specs.indexOf(_selected) + 1
                  : null,
              sequenceTotal: specs.length,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  key: const ValueKey('guide-replay-effect'),
                  onPressed: () => _play(_selected),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: PopText('Probar ${_selected.title}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _selected.color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  key: const ValueKey('guide-play-all'),
                  onPressed: _playingAll ? _stopSequence : _playAll,
                  icon: Icon(
                    _playingAll
                        ? Icons.stop_rounded
                        : Icons.playlist_play_rounded,
                  ),
                  label: PopText(_playingAll ? 'Detener' : 'Ver todos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GuidePalette.navy,
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: GuidePalette.navy, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabBadge extends StatelessWidget {
  const _LabBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: GuidePalette.yellow,
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55FFB400),
            blurRadius: 9,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.science_rounded,
        color: GuidePalette.navy,
        size: 29,
      ),
    );
  }
}

class _PowerRulesStrip extends StatelessWidget {
  const _PowerRulesStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F0FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_off_rounded, color: GuidePalette.violet),
          SizedBox(width: 9),
          Expanded(
            child: PopText(
              'Las trampas son ocultas, de un solo uso y se arman automáticamente en el cristal. Puedes tener varias; no aparecen en seguros, salidas ni pasillos.',
              style: TextStyle(
                color: GuidePalette.ink,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectChoice extends StatelessWidget {
  const _EffectChoice({
    super.key,
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _GuideEffectSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: appTranslate(context, 'Probar efecto ${spec.title}'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected
                  ? spec.color.withValues(alpha: .13)
                  : const Color(0xFFF5F7FC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? spec.color : const Color(0xFFDDE3EF),
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: spec.color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(spec.icon, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: PopText(
                        spec.title,
                        maxLines: 1,
                        style: const TextStyle(
                          color: GuidePalette.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                PopText(
                  spec.shortRule,
                  maxLines: 3,
                  style: const TextStyle(
                    color: Color(0xFF667088),
                    fontSize: 11,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
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

class _PowerEffectStage extends StatelessWidget {
  const _PowerEffectStage({
    required this.spec,
    required this.progress,
    required this.playing,
    required this.sequenceTotal,
    this.sequencePosition,
  });

  final _GuideEffectSpec spec;
  final double progress;
  final bool playing;
  final int sequenceTotal;
  final int? sequencePosition;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeInOutCubic.transform(progress);
    final burst = math.sin(math.min(1, progress * 1.8) * math.pi);
    final pulse = .5 + .5 * math.sin(progress * math.pi * 8);
    final tokenMotion = _tokenMotion(spec.type, eased, progress);
    final tokenOpacity = switch (spec.type) {
      GuideEffect.prison || GuideEffect.bomb when progress > .62 => math.max(
        0.0,
        1 - (progress - .62) / .26,
      ),
      _ => 1.0,
    };
    return Container(
      key: const ValueKey('guide-effect-stage'),
      width: double.infinity,
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F1FF), Color(0xFFF6F2FF)],
        ),
        border: Border.all(color: const Color(0xFFD7E0F0), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LabGridPainter(
                color: GuidePalette.navy.withValues(alpha: .1),
              ),
            ),
          ),
          Transform.scale(
            scale: 1 + burst * .16,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: GuidePalette.navy, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 10,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                playing || progress > 0
                    ? spec.icon
                    : Icons.question_mark_rounded,
                color: spec.color,
                size: 37,
              ),
            ),
          ),
          if (progress > 0)
            for (var ring = 0; ring < 3; ring++)
              Opacity(
                opacity: math.max(0, (1 - progress) * (.75 - ring * .12)),
                child: Container(
                  width: 94 + progress * (85 + ring * 36),
                  height: 94 + progress * (85 + ring * 36),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: spec.color.withValues(alpha: .85),
                      width: math.max(1.0, 5 - progress * 4),
                    ),
                  ),
                ),
              ),
          if (spec.type == GuideEffect.shield && progress > .02)
            Transform.scale(
              scale: .72 + burst * .48,
              child: Opacity(
                opacity: math.min(1, progress * 5),
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: spec.color.withValues(alpha: .10),
                    border: Border.all(
                      color: spec.color.withValues(alpha: .88),
                      width: 5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: spec.color.withValues(alpha: .42),
                        blurRadius: 22,
                        spreadRadius: 7,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (spec.type == GuideEffect.shield && progress > .04)
            Transform.translate(
              offset: Offset(
                math.sin(progress * math.pi * 4) * 12,
                -54 - eased * 24,
              ),
              child: Opacity(
                opacity: math.max(0, 1 - progress),
                child: Transform.rotate(
                  angle: progress * math.pi,
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFF9B5DE5),
                    size: 31,
                  ),
                ),
              ),
            ),
          if (spec.type == GuideEffect.turbo && progress > .02)
            for (var trail = 0; trail < 4; trail++)
              Transform.translate(
                offset:
                    tokenMotion -
                    Offset(18.0 * (trail + 1), 1.5 * (trail.isEven ? 1 : -1)),
                child: Opacity(
                  opacity: math.max(0, (1 - progress) * (.65 - trail * .11)),
                  child: Container(
                    width: 17 - trail * 2,
                    height: 17 - trail * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: spec.color,
                      boxShadow: [BoxShadow(color: spec.color, blurRadius: 10)],
                    ),
                  ),
                ),
              ),
          if (spec.type == GuideEffect.glue && progress > .02)
            Transform.translate(
              offset: const Offset(0, 32),
              child: Transform.scale(
                scaleX: .35 + eased * .90,
                scaleY: .35 + eased * .55,
                child: Opacity(
                  opacity: math.min(1, progress * 5),
                  child: Container(
                    width: 92,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      gradient: LinearGradient(
                        colors: [
                          spec.color.withValues(alpha: .92),
                          spec.color.withValues(alpha: .42),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: spec.color.withValues(alpha: .48),
                          blurRadius: 13,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (spec.type == GuideEffect.glue && progress > .15)
            Transform.translate(
              offset: const Offset(0, -55),
              child: Opacity(
                opacity: math.min(1, (progress - .15) * 5),
                child: Icon(
                  Icons.pause_circle_filled_rounded,
                  color: spec.color,
                  size: 34,
                ),
              ),
            ),
          if (spec.type == GuideEffect.setback && progress > .02)
            for (var step = 0; step < 6; step++)
              Transform.translate(
                offset: Offset(58.0 - step * 22, 42),
                child: Opacity(
                  opacity: math.min(
                    .88,
                    math.max(0, progress * 5 - step * .10),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: spec.color,
                    size: 23,
                  ),
                ),
              ),
          if (spec.type == GuideEffect.prison && progress > .06)
            Transform.scale(
              scale: .78 + burst * .24,
              child: Opacity(
                opacity: math.max(0, 1 - math.max(0, progress - .72) / .25),
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final x in const [-27.0, -9.0, 9.0, 27.0])
                        Transform.translate(
                          offset: Offset(x, 0),
                          child: Container(
                            width: 6,
                            height: 76,
                            decoration: BoxDecoration(
                              color: spec.color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      Icon(
                        Icons.lock_rounded,
                        color: GuidePalette.yellow,
                        size: 30,
                        shadows: const [
                          Shadow(color: Colors.white, blurRadius: 7),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (spec.type == GuideEffect.bomb && progress > .08)
            ...List.generate(8, (index) {
              final angle = index * math.pi / 4;
              final distance = 28 + eased * 74;
              return Transform.translate(
                offset: Offset(
                  math.cos(angle) * distance,
                  math.sin(angle) * distance,
                ),
                child: Opacity(
                  opacity: math.max(0, 1 - progress),
                  child: Icon(
                    index.isEven
                        ? Icons.local_fire_department_rounded
                        : Icons.circle,
                    color: index.isEven
                        ? GuidePalette.red
                        : GuidePalette.yellow,
                    size: index.isEven ? 24 : 12,
                  ),
                ),
              );
            }),
          Transform.translate(
            offset: tokenMotion,
            child: Opacity(
              opacity: tokenOpacity,
              child: Transform.rotate(
                angle: spec.type == GuideEffect.setback
                    ? -progress * math.pi * 2
                    : spec.type == GuideEffect.turbo
                    ? progress * .35
                    : 0,
                child: _DemoToken(
                  color: GuidePalette.red,
                  glow: spec.type == GuideEffect.shield && progress > 0
                      ? spec.color.withValues(alpha: .45 + pulse * .35)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
          Positioned(
            top: 13,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: progress > .05 ? 1 : 0,
              child: Transform.scale(
                scale: .82 + burst * .25,
                child: Container(
                  key: const ValueKey('guide-effect-callout'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: spec.color,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: spec.color.withValues(alpha: .35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: PopText(
                    spec.callout,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: PopText(
              playing
                  ? sequencePosition == null
                        ? 'Demostración: ${spec.title}'
                        : 'Secuencia $sequencePosition de $sequenceTotal · ${spec.title}'
                  : progress >= 1
                  ? 'Efecto completado · toca para repetir'
                  : 'Elige un efecto para verlo en acción',
              key: const ValueKey('guide-effect-status'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: playing ? spec.color : GuidePalette.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset _tokenMotion(GuideEffect type, double eased, double raw) {
    return switch (type) {
      GuideEffect.shield => Offset(0, math.sin(raw * math.pi * 6) * 2),
      GuideEffect.turbo => Offset(
        -72 + eased * 144,
        -3 - math.sin(raw * math.pi) * 22,
      ),
      GuideEffect.glue => Offset(
        math.sin(raw * math.pi * 10) * (1 - raw) * 7,
        13 + math.sin(raw * math.pi * 4).abs() * 5,
      ),
      GuideEffect.setback => Offset(62 - eased * 120, 5),
      GuideEffect.prison => Offset(eased * 78, -eased * 72),
      GuideEffect.bomb => Offset(eased * 72, -eased * 76),
    };
  }
}

class _DemoToken extends StatelessWidget {
  const _DemoToken({required this.color, required this.glow});

  final Color color;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .32)!, color],
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          const BoxShadow(
            color: Color(0x55000000),
            blurRadius: 8,
            offset: Offset(0, 5),
          ),
          if (glow != Colors.transparent)
            BoxShadow(color: glow, blurRadius: 23, spreadRadius: 10),
        ],
      ),
      child: const Icon(Icons.star_rounded, color: Colors.white, size: 27),
    );
  }
}

class _LabGridPainter extends CustomPainter {
  const _LabGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LabGridPainter oldDelegate) => oldDelegate.color != color;
}

class _QuickReference extends StatelessWidget {
  const _QuickReference({required this.mode});

  final GameGuideMode mode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GuidePalette.yellow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: GuidePalette.navy),
                SizedBox(width: 8),
                PopText(
                  'CHULETA RÁPIDA',
                  style: TextStyle(
                    color: GuidePalette.navy,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: mode == GameGuideMode.quickPop
                  ? const [
                      _QuickPill(text: '2 fichas'),
                      _QuickPill(text: 'Sin 5 de salida'),
                      _QuickPill(text: 'Captura = +20'),
                      _QuickPill(text: 'Meta = +10'),
                      _QuickPill(text: 'Doble = otra tirada'),
                      _QuickPill(text: 'Meta = número exacto'),
                    ]
                  : const [
                      _QuickPill(text: '5 = SALIDA'),
                      _QuickPill(text: 'Captura = +20'),
                      _QuickPill(text: 'Meta = +10'),
                      _QuickPill(text: 'Doble = otra tirada'),
                      _QuickPill(text: '3 dobles = penalización'),
                      _QuickPill(text: 'Meta = número exacto'),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .84),
        borderRadius: BorderRadius.circular(18),
      ),
      child: PopText(
        text,
        style: const TextStyle(
          color: GuidePalette.navy,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
