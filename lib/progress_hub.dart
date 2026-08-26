import 'package:flutter/material.dart';

import 'app_language.dart';
import 'feature_rollout.dart';
import 'player_progression.dart';
import 'wallet.dart';

class ProgressHubScreen extends StatelessWidget {
  const ProgressHubScreen({
    super.key,
    required this.progression,
    required this.wallet,
    this.rollout = AppFeatureRollout.safeDefaults,
  });

  final PlayerProgressionController progression;
  final WalletController wallet;
  final AppFeatureRollout rollout;

  static const _navy = Color(0xFF17284D);
  static const _blue = Color(0xFF2474E5);
  static const _yellow = Color(0xFFFFC83D);
  static const _green = Color(0xFF32B875);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF0F5FF),
    appBar: AppBar(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      title: const PopText(
        'Tu progreso',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    body: SafeArea(
      top: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([progression, wallet]),
        builder: (context, _) {
          final daily = progression.dailyMissions;
          final sharedTable = progression.sharedTableMissions;
          final weekly = progression.weeklyMission;
          return ListView(
            key: const ValueKey('progress-hub-list'),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              _BalanceHero(balance: wallet.balance),
              const SizedBox(height: 16),
              const _SectionTitle(
                icon: Icons.today_rounded,
                title: 'MISIONES DE HOY',
                subtitle: 'Juega normalmente; los premios llegan solos.',
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-move-20'),
                icon: Icons.directions_walk_rounded,
                title: 'Mueve 20 casillas',
                value: daily.cellsMoved,
                target: daily.moveTarget,
                reward: progression.policy.dailyMoveMissionCoins,
                claimed: daily.moveRewardClaimed,
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-release-token'),
                icon: Icons.outbound_rounded,
                title: 'Saca una ficha',
                value: daily.tokenReleased ? 1 : 0,
                target: 1,
                reward: progression.policy.dailyReleaseMissionCoins,
                claimed: daily.releaseRewardClaimed,
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-finish-match'),
                icon: Icons.sports_score_rounded,
                title: 'Termina una partida',
                value: daily.matchCompleted ? 1 : 0,
                target: 1,
                reward: progression.policy.firstMatchOfDayCoins,
                claimed: daily.finishRewardClaimed,
              ),
              const SizedBox(height: 20),
              const _SectionTitle(
                icon: Icons.groups_rounded,
                title: 'MESA COMPARTIDA',
                subtitle:
                    'Misiones locales para jugar hasta 4 en un dispositivo.',
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-shared-table-turns'),
                icon: Icons.swap_horiz_rounded,
                title: 'Tomen 8 turnos',
                value: sharedTable.turnsPlayed,
                target: sharedTable.turnTarget,
                reward: progression.policy.sharedTableTurnsCoins,
                claimed: sharedTable.turnRewardClaimed,
                accent: _green,
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-shared-table-match'),
                icon: Icons.table_restaurant_rounded,
                title: 'Termina una partida local',
                value: sharedTable.matchCompleted ? 1 : 0,
                target: 1,
                reward: progression.policy.sharedTableMatchCoins,
                claimed: sharedTable.matchRewardClaimed,
                accent: _green,
              ),
              const SizedBox(height: 20),
              const _SectionTitle(
                icon: Icons.calendar_month_rounded,
                title: 'OBJETIVO SEMANAL',
                subtitle: 'Completa partidas; ganar no es obligatorio.',
              ),
              const SizedBox(height: 10),
              _MissionCard(
                key: const ValueKey('mission-weekly-matches'),
                icon: Icons.emoji_events_rounded,
                title: 'Termina 7 partidas',
                value: weekly.matchesCompleted,
                target: weekly.target,
                reward: progression.policy.weeklyMatchesCoins,
                claimed: weekly.rewardClaimed,
                accent: _yellow,
              ),
              const SizedBox(height: 20),
              const _FairPlayCard(),
              const SizedBox(height: 12),
              if (!rollout.rankedPlay || !rollout.weeklyEvents)
                const _ServerGateCard(),
            ],
          );
        },
      ),
    ),
  );
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2474E5), Color(0xFF6547D9)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x442474E5),
          blurRadius: 18,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: ProgressHubScreen._yellow,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(
            Icons.monetization_on_rounded,
            color: ProgressHubScreen._navy,
            size: 34,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PopText(
                'MONEDAS DISPONIBLES',
                style: TextStyle(
                  color: Color(0xFFDCE9FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              Text(
                '$balance',
                key: const ValueKey('progress-wallet-balance'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const PopText(
                'Un tema de 1,800 se alcanza jugando varios días.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: ProgressHubScreen._blue),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PopText(
              title,
              style: const TextStyle(
                color: ProgressHubScreen._navy,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            PopText(
              subtitle,
              style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.target,
    required this.reward,
    required this.claimed,
    this.accent = ProgressHubScreen._green,
  });

  final IconData icon;
  final String title;
  final int value;
  final int target;
  final int reward;
  final bool claimed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final progress = (value / target).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .32), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PopText(
                        title,
                        style: const TextStyle(
                          color: ProgressHubScreen._navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PopText(
                      claimed ? 'LISTO' : '$value / $target',
                      style: TextStyle(
                        color: claimed ? ProgressHubScreen._green : accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE8EDF6),
                    color: claimed ? ProgressHubScreen._green : accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Chip(
            avatar: const Icon(Icons.monetization_on_rounded, size: 16),
            label: Text('+$reward'),
            backgroundColor: ProgressHubScreen._yellow.withValues(alpha: .25),
            side: BorderSide.none,
          ),
        ],
      ),
    );
  }
}

class _FairPlayCard extends StatelessWidget {
  const _FairPlayCard();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFFE8F8EF),
    child: ListTile(
      leading: Icon(Icons.verified_user_rounded, color: Color(0xFF238B57)),
      title: PopText(
        'Premios por jugar, no por pagar',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: PopText(
        'Terminar, quedar en una posición y volver cada día entrega monedas. '
        'Los anuncios son opcionales y los cosméticos no dan ventaja.',
      ),
    ),
  );
}

class _ServerGateCard extends StatelessWidget {
  const _ServerGateCard();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFFFFF6DB),
    child: ListTile(
      leading: Icon(Icons.lock_clock_rounded, color: Color(0xFF946700)),
      title: PopText(
        'Rango y eventos: protegidos',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: PopText(
        'Se activarán solo cuando el servidor pueda validar dados, movimientos, '
        'resultados y recompensas sin desincronización.',
      ),
    ),
  );
}
