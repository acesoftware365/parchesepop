import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/quick_pop_search_deadline.dart';

final class _Connection {}

final class _Ticket {}

final class _Resolution {
  const _Resolution({required this.human});

  final bool human;
}

final class _Prepared {}

final class _SearchHarness {
  _SearchHarness({
    this.connectFailure,
    this.abandonment,
    this.deferFallbackUntilDeadline = false,
    this.resolutionResults,
  }) {
    search =
        QuickPopDeadlineSearch<_Connection, _Ticket, _Resolution, _Prepared>(
          window: const Duration(seconds: 5),
          deferFallbackUntilDeadline: deferFallbackUntilDeadline,
          elapsed: () => elapsed,
          connect: () {
            connectCalls++;
            final failure = connectFailure;
            if (failure != null) return Future<_Connection>.error(failure);
            return connection.future;
          },
          enqueue: (_) {
            enqueueCalls++;
            return ticket.future;
          },
          resolve: (_, _) {
            resolveCalls++;
            final results = resolutionResults;
            if (results != null && results.isNotEmpty) {
              return Future<_Resolution?>.value(results.removeAt(0));
            }
            return resolution.future;
          },
          isHumanResolution: (result) => result.human,
          prepare: (_, _, _) {
            prepareCalls++;
            return prepared.future;
          },
          synchronize: (_, _, _, _) {
            synchronizeCalls++;
            return synchronized.future;
          },
          settle: (_, _, _, _) {
            settleCalls++;
            return settlement.future;
          },
          cancelTicket: (_, _) async {
            cancelCalls++;
          },
          abandonResolution: (_, _, _) async {
            abandonCalls++;
            await abandonment?.future;
          },
          disposePrepared: (_) {
            disposePreparedCalls++;
          },
          releaseConnection: (_) async {
            releaseCalls++;
          },
          onPhaseChanged: phases.add,
          onFailure: (phase, error, stackTrace) {
            failures.add((phase, error));
          },
          onHuman: (_, result, ready) {
            humanResults.add((result, ready));
          },
          onFallback: (phase, error) {
            fallbackResults.add((phase, error));
          },
          onUnavailable: unavailableResults.add,
          delay: (_) => pollDelay.future,
          scheduleDeadline: (delay, callback) {
            scheduledDelay = delay;
            deadlineCallback = callback;
            deadlineCancelled = false;
            return () => deadlineCancelled = true;
          },
        );
  }

  final Object? connectFailure;
  final Completer<void>? abandonment;
  final bool deferFallbackUntilDeadline;
  final List<_Resolution?>? resolutionResults;
  final connection = Completer<_Connection>();
  final ticket = Completer<_Ticket>();
  final resolution = Completer<_Resolution?>();
  final prepared = Completer<_Prepared>();
  final synchronized = Completer<bool>();
  final settlement = Completer<QuickPopDeadlineSettlement>();
  final pollDelay = Completer<void>();
  final phases = <QuickPopSearchPhase>[];
  final failures = <(QuickPopSearchPhase, Object)>[];
  final humanResults = <(_Resolution, _Prepared)>[];
  final fallbackResults = <(QuickPopSearchPhase?, Object?)>[];
  final unavailableResults = <Object?>[];
  late final QuickPopDeadlineSearch<
    _Connection,
    _Ticket,
    _Resolution,
    _Prepared
  >
  search;

  Duration elapsed = Duration.zero;
  Duration? scheduledDelay;
  void Function()? deadlineCallback;
  bool deadlineCancelled = false;
  int connectCalls = 0;
  int enqueueCalls = 0;
  int resolveCalls = 0;
  int prepareCalls = 0;
  int synchronizeCalls = 0;
  int settleCalls = 0;
  int cancelCalls = 0;
  int abandonCalls = 0;
  int disposePreparedCalls = 0;
  int releaseCalls = 0;

  void fireDeadline() {
    if (!deadlineCancelled) deadlineCallback?.call();
  }
}

Future<void> _flushAsyncWork([int turns = 1]) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'slow connect falls back once at the deadline and ignores late work',
    () async {
      final harness = _SearchHarness();
      final terminal = harness.search.start();
      await _flushAsyncWork();

      expect(harness.scheduledDelay, const Duration(seconds: 5));
      harness.elapsed = const Duration(seconds: 5);
      harness.fireDeadline();
      expect(await terminal, QuickPopDeadlineOutcome.fallback);
      expect(harness.fallbackResults, hasLength(1));

      harness.connection.complete(_Connection());
      await _flushAsyncWork(2);
      expect(harness.enqueueCalls, 0);
      expect(harness.releaseCalls, 1);
      expect(harness.humanResults, isEmpty);
    },
  );

  test(
    'connect failure reports its phase and immediately falls back',
    () async {
      final failure = StateError('offline');
      final harness = _SearchHarness(connectFailure: failure);

      expect(await harness.search.start(), QuickPopDeadlineOutcome.fallback);
      expect(harness.failures, <(QuickPopSearchPhase, Object)>[
        (QuickPopSearchPhase.connecting, failure),
      ]);
      expect(harness.fallbackResults, <(QuickPopSearchPhase?, Object?)>[
        (QuickPopSearchPhase.connecting, failure),
      ]);
      expect(harness.enqueueCalls, 0);
    },
  );

  test('desktop startup failure keeps the ten-second search promise', () async {
    final failure = StateError('desktop Firebase warming up');
    final harness = _SearchHarness(
      connectFailure: failure,
      deferFallbackUntilDeadline: true,
    );
    final terminal = harness.search.start();
    await _flushAsyncWork();

    expect(harness.fallbackResults, isEmpty);
    expect(harness.scheduledDelay, const Duration(seconds: 5));

    harness.elapsed = const Duration(seconds: 5);
    harness.fireDeadline();
    expect(await terminal, QuickPopDeadlineOutcome.fallback);
    expect(harness.fallbackResults, hasLength(1));

    // Release the deferred error handler after the authoritative deadline;
    // it must not emit a second fallback or navigate again.
    harness.pollDelay.complete();
    await _flushAsyncWork(2);
    expect(harness.fallbackResults, hasLength(1));
  });

  test('CPU fallback does not try to abandon a non-human resolution', () async {
    final harness = _SearchHarness(
      resolutionResults: <_Resolution?>[const _Resolution(human: false)],
    );
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());

    final terminal = harness.search.start();
    expect(await terminal, QuickPopDeadlineOutcome.fallback);
    await _flushAsyncWork(2);

    expect(harness.fallbackResults, hasLength(1));
    expect(harness.abandonCalls, 0);
    expect(harness.cancelCalls, 1);
    expect(harness.releaseCalls, 1);
  });

  test('human ready at 4999 ms waits for deadline settlement', () async {
    final harness = _SearchHarness();
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    final terminal = harness.search.start();
    await _flushAsyncWork();

    harness.elapsed = const Duration(milliseconds: 4200);
    harness.resolution.complete(const _Resolution(human: true));
    await _flushAsyncWork();
    expect(harness.prepareCalls, 1);
    expect(harness.humanResults, isEmpty);

    harness.prepared.complete(_Prepared());
    await _flushAsyncWork();
    expect(harness.synchronizeCalls, 1);
    expect(harness.humanResults, isEmpty);

    harness.elapsed = const Duration(milliseconds: 4999);
    harness.synchronized.complete(true);
    await _flushAsyncWork();
    expect(harness.humanResults, isEmpty);

    harness.elapsed = const Duration(seconds: 5);
    harness.fireDeadline();
    await _flushAsyncWork();
    expect(harness.settleCalls, 1);
    harness.settlement.complete(QuickPopDeadlineSettlement.human);
    expect(await terminal, QuickPopDeadlineOutcome.human);
    expect(harness.humanResults, hasLength(1));
    expect(harness.deadlineCancelled, isTrue);
    expect(harness.disposePreparedCalls, 0);
    expect(harness.abandonCalls, 0);
  });

  test(
    'human preparation gets a bounded grace period before fallback',
    () async {
      final harness = _SearchHarness();
      harness.connection.complete(_Connection());
      harness.ticket.complete(_Ticket());
      final terminal = harness.search.start();
      await _flushAsyncWork();
      harness.elapsed = const Duration(milliseconds: 4700);
      harness.resolution.complete(const _Resolution(human: true));
      await _flushAsyncWork();
      expect(harness.prepareCalls, 1);

      harness.elapsed = const Duration(seconds: 5);
      harness.fireDeadline();
      await _flushAsyncWork();
      expect(harness.scheduledDelay, const Duration(seconds: 10));
      expect(harness.fallbackResults, isEmpty);

      // If the shared table never becomes ready, the extended deadline still
      // makes one deterministic CPU decision.
      harness.elapsed = const Duration(seconds: 17);
      harness.fireDeadline();
      expect(await terminal, QuickPopDeadlineOutcome.fallback);
      expect(harness.abandonCalls, 1);

      harness.prepared.complete(_Prepared());
      await _flushAsyncWork(3);
      expect(harness.disposePreparedCalls, 1);
      expect(harness.humanResults, isEmpty);
      expect(harness.synchronizeCalls, 0);
      expect(harness.fallbackResults, hasLength(1));
      expect(harness.abandonCalls, 1);
    },
  );

  test(
    'in-flight deadline resolution cannot abandon a committed human group',
    () async {
      final harness = _SearchHarness(deferFallbackUntilDeadline: true);
      harness.connection.complete(_Connection());
      harness.ticket.complete(_Ticket());
      final terminal = harness.search.start();
      await _flushAsyncWork();

      harness.elapsed = const Duration(seconds: 5);
      harness.fireDeadline();
      await _flushAsyncWork();
      expect(harness.scheduledDelay, const Duration(seconds: 10));
      expect(harness.fallbackResults, isEmpty);
      expect(harness.abandonCalls, 0);

      harness.resolution.complete(const _Resolution(human: true));
      await _flushAsyncWork(2);
      expect(harness.prepareCalls, 1);
      expect(harness.scheduledDelay, const Duration(seconds: 10));
      expect(harness.fallbackResults, isEmpty);
      expect(harness.abandonCalls, 0);

      harness.prepared.complete(_Prepared());
      await _flushAsyncWork();
      harness.synchronized.complete(true);
      await _flushAsyncWork();
      harness.settlement.complete(QuickPopDeadlineSettlement.human);
      expect(await terminal, QuickPopDeadlineOutcome.human);
      expect(harness.humanResults, hasLength(1));
      expect(harness.abandonCalls, 0);
    },
  );

  test('deadline guard polls again after a pending group read', () async {
    final harness = _SearchHarness(
      deferFallbackUntilDeadline: true,
      resolutionResults: <_Resolution?>[null, const _Resolution(human: true)],
    );
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    final terminal = harness.search.start();
    await _flushAsyncWork(2);
    expect(harness.resolveCalls, 1);

    harness.elapsed = const Duration(seconds: 5);
    harness.pollDelay.complete();
    await _flushAsyncWork(4);
    expect(harness.resolveCalls, 2);
    expect(harness.prepareCalls, 1);
    expect(harness.fallbackResults, isEmpty);
    expect(harness.abandonCalls, 0);

    harness.prepared.complete(_Prepared());
    await _flushAsyncWork();
    harness.synchronized.complete(true);
    await _flushAsyncWork();
    harness.settlement.complete(QuickPopDeadlineSettlement.human);
    expect(await terminal, QuickPopDeadlineOutcome.human);
    expect(harness.humanResults, hasLength(1));
  });

  test(
    'authoritative settlement wins an exact 5000 ms readiness race',
    () async {
      final harness = _SearchHarness();
      harness.connection.complete(_Connection());
      harness.ticket.complete(_Ticket());
      harness.resolution.complete(const _Resolution(human: true));
      harness.prepared.complete(_Prepared());
      final terminal = harness.search.start();
      await _flushAsyncWork(3);
      expect(harness.synchronizeCalls, 1);

      harness.elapsed = const Duration(seconds: 5);
      harness.synchronized.complete(true);
      harness.fireDeadline();
      await _flushAsyncWork(2);
      expect(harness.settleCalls, 1);
      harness.settlement.complete(QuickPopDeadlineSettlement.human);
      expect(await terminal, QuickPopDeadlineOutcome.human);
      await _flushAsyncWork(2);
      expect(harness.humanResults, hasLength(1));
      expect(harness.fallbackResults, isEmpty);
      expect(harness.disposePreparedCalls, 0);
      expect(harness.abandonCalls, 0);
    },
  );

  test('cancellation during preparation closes every owned resource', () async {
    final harness = _SearchHarness();
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    final terminal = harness.search.start();
    await _flushAsyncWork();
    harness.resolution.complete(const _Resolution(human: true));
    await _flushAsyncWork();

    await harness.search.cancel();
    expect(await terminal, QuickPopDeadlineOutcome.cancelled);
    await _flushAsyncWork(2);
    expect(harness.cancelCalls, 1);
    expect(harness.abandonCalls, 1);
    expect(harness.releaseCalls, 1);

    harness.prepared.complete(_Prepared());
    await _flushAsyncWork(3);
    expect(harness.disposePreparedCalls, 1);
    expect(harness.humanResults, isEmpty);
    expect(harness.fallbackResults, isEmpty);
  });

  test(
    'late human resolution after fallback is abandoned, never opened',
    () async {
      final harness = _SearchHarness();
      harness.connection.complete(_Connection());
      harness.ticket.complete(_Ticket());
      final terminal = harness.search.start();
      await _flushAsyncWork();
      expect(harness.resolveCalls, 1);

      harness.elapsed = const Duration(seconds: 5);
      harness.fireDeadline();
      expect(await terminal, QuickPopDeadlineOutcome.fallback);
      expect(harness.cancelCalls, 1);
      expect(harness.abandonCalls, 0);

      harness.resolution.complete(const _Resolution(human: true));
      await _flushAsyncWork(3);
      expect(harness.abandonCalls, 1);
      expect(harness.prepareCalls, 0);
      expect(harness.humanResults, isEmpty);
      expect(harness.fallbackResults, hasLength(1));
    },
  );

  test(
    'peer cancellation at settlement opens exactly one CPU fallback',
    () async {
      final harness = _SearchHarness();
      harness.connection.complete(_Connection());
      harness.ticket.complete(_Ticket());
      harness.resolution.complete(const _Resolution(human: true));
      harness.prepared.complete(_Prepared());
      final terminal = harness.search.start();
      await _flushAsyncWork(3);
      harness.synchronized.complete(true);
      harness.elapsed = const Duration(seconds: 5);
      harness.fireDeadline();
      await _flushAsyncWork(2);

      harness.settlement.complete(QuickPopDeadlineSettlement.fallback);
      expect(await terminal, QuickPopDeadlineOutcome.fallback);
      expect(harness.humanResults, isEmpty);
      expect(harness.fallbackResults, hasLength(1));
      await _flushAsyncWork(2);
      expect(harness.disposePreparedCalls, 1);
      expect(harness.abandonCalls, 1);
    },
  );

  test('ambiguous offline settlement never guesses CPU', () async {
    final harness = _SearchHarness();
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    harness.resolution.complete(const _Resolution(human: true));
    harness.prepared.complete(_Prepared());
    final terminal = harness.search.start();
    await _flushAsyncWork(3);
    harness.synchronized.complete(true);
    harness.elapsed = const Duration(seconds: 5);
    harness.fireDeadline();
    await _flushAsyncWork(2);

    harness.settlement.complete(QuickPopDeadlineSettlement.unavailable);
    expect(await terminal, QuickPopDeadlineOutcome.unavailable);
    expect(harness.humanResults, isEmpty);
    expect(harness.fallbackResults, isEmpty);
    expect(harness.unavailableResults, hasLength(1));
  });

  test('cancel during settlement remains the only terminal outcome', () async {
    final harness = _SearchHarness();
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    harness.resolution.complete(const _Resolution(human: true));
    harness.prepared.complete(_Prepared());
    final terminal = harness.search.start();
    await _flushAsyncWork(3);
    harness.synchronized.complete(true);
    await _flushAsyncWork(2);
    expect(harness.settleCalls, 1);

    await harness.search.cancel();
    expect(await terminal, QuickPopDeadlineOutcome.cancelled);
    harness.settlement.complete(QuickPopDeadlineSettlement.human);
    await _flushAsyncWork(3);
    expect(harness.humanResults, isEmpty);
    expect(harness.fallbackResults, isEmpty);
    expect(harness.unavailableResults, isEmpty);
    expect(harness.abandonCalls, 1);
  });

  test('explicit cancellation is immediate while cleanup is hung', () async {
    final cleanup = Completer<void>();
    final harness = _SearchHarness(abandonment: cleanup);
    harness.connection.complete(_Connection());
    harness.ticket.complete(_Ticket());
    harness.resolution.complete(const _Resolution(human: true));
    final terminal = harness.search.start();
    await _flushAsyncWork(2);

    await harness.search.cancel().timeout(const Duration(milliseconds: 50));
    expect(await terminal, QuickPopDeadlineOutcome.cancelled);
    expect(harness.abandonCalls, 1);
    cleanup.complete();
  });

  test('double tap starts only one synchronous cancellation', () {
    final gate = QuickPopCancelGate();

    expect(gate.tryStart(), isTrue);
    expect(gate.tryStart(), isFalse);
    expect(gate.started, isTrue);
  });

  test('system back followed by tap shares the cancellation gate', () {
    final gate = QuickPopCancelGate();

    final backStarted = gate.tryStart();
    final tapStarted = gate.tryStart();
    expect((backStarted, tapStarted), (true, false));
  });
}
