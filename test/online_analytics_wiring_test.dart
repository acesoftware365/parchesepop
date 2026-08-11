import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Quick Pop owns one tap-to-play deadline independent of Firebase', () {
    final source = File('lib/main.dart').readAsStringSync();
    final screenStart = source.indexOf(
      'class _QuickPopOnlineSearchScreenState',
    );
    final screenEnd = source.indexOf('class _QuickPopEntryDialog', screenStart);
    final screen = source.substring(
      screenStart,
      screenEnd == -1 ? source.length : screenEnd,
    );

    expect(source, contains('stopwatch: Stopwatch()..start()'));
    expect(screen, contains('QuickPopDeadlineSearch<'));
    expect(screen, contains('window: quickPopSearchWindow'));
    expect(screen, contains('elapsed: () => widget.searchStopwatch.elapsed'));
    expect(screen, contains('OnlineFlowStage.connectionFailed'));
    expect(screen, contains('stage: OnlineFlowStage.cpuFallback'));
    expect(screen, contains('settleQuickPopLaunch('));
    expect(screen, contains('QuickPopDeadlineSettlement.human'));
    expect(screen, contains('onUnavailable: _handleSettlementUnavailable'));
    expect(
      screen,
      contains('search.remaining + quickPopSettlementOperationTimeout'),
    );
    expect(screen, contains('PageRouteBuilder<void>'));
    expect(screen, isNot(contains("id: online.user.uid")));
    expect(screen, isNot(contains('INTENTAR DE NUEVO')));
  });

  test('Quick Pop and invitation joins guard mutually exclusive terminals', () {
    final source = File('lib/main.dart').readAsStringSync();
    final quickPopStart = source.indexOf(
      'class _QuickPopOnlineSearchScreenState',
    );
    final quickPop = source.substring(quickPopStart);
    expect(
      quickPop,
      contains('if (!mounted || cancelled || navigationCommitted) return;'),
    );
    expect(
      quickPop,
      contains('deadlineSearch?.outcome != QuickPopDeadlineOutcome.searching'),
    );
    expect(quickPop, contains('final QuickPopCancelGate cancelGate'));
    expect(
      quickPop,
      contains('if (settlementInProgress || !cancelGate.tryStart()) return;'),
    );
    expect(quickPop, contains('cancelGate.started || settlementInProgress'));

    final tableStart = source.indexOf('class _QuickTableOnlineShellState');
    final tableEnd = source.indexOf(
      'Future<void> _startOnlineSyncWithRetry',
      tableStart,
    );
    final table = source.substring(tableStart, tableEnd);
    expect(table, contains('stage: OnlineFlowStage.joinCancelled'));
    expect(table, contains('joinMethod: OnlineJoinMethod.invitation'));
    expect(table, contains('roomController.dispose();'));
  });

  test('unavailable settlement owns one guarded terminal analytics event', () {
    final source = File('lib/main.dart').readAsStringSync();
    final screenStart = source.indexOf(
      'class _QuickPopOnlineSearchScreenState',
    );
    final screenEnd = source.indexOf('class _QuickPopEntryDialog', screenStart);
    final screen = source.substring(screenStart, screenEnd);

    expect(screen, contains('bool settlementUnavailableLogged = false;'));
    expect(screen, contains('_logSettlementUnavailable(failure);'));
    expect(screen, contains('if (settlementUnavailableLogged) return;'));
    expect(
      RegExp(
        r'stage: OnlineFlowStage\.settlementUnavailable',
      ).allMatches(screen),
      hasLength(1),
    );
    expect(screen, contains('elapsedMilliseconds: searchElapsedMilliseconds'));
    expect(screen, contains('OnlineFlowFailureReason.unavailable'));
    expect(screen, contains('if (settlementUnavailable) ...['));
    expect(screen, contains('] else if (!openingMatch) ...['));
  });
}
