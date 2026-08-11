import 'dart:async';

/// Network phase active when a Quick Pop attempt fails.
enum QuickPopSearchPhase {
  connecting,
  enqueueing,
  resolving,
  preparing,
  synchronizing,
  settling,
}

/// The single terminal decision made by a tap-to-play Quick Pop attempt.
enum QuickPopDeadlineOutcome {
  searching,
  human,
  fallback,
  unavailable,
  cancelled,
}

/// The authoritative server decision observed at the tap-to-play deadline.
enum QuickPopDeadlineSettlement { human, fallback, unavailable }

enum _QuickPopLaunchCommitState { none, possible, provisional }

/// Synchronous one-shot guard shared by every route out of the search screen.
///
/// Flutter can deliver a second tap or a system-back callback before the first
/// asynchronous cancellation reaches its first `await`. [tryStart] closes
/// that re-entrancy window without relying on a later frame rebuild.
final class QuickPopCancelGate {
  bool _started = false;

  bool get started => _started;

  bool tryStart() {
    if (_started) return false;
    _started = true;
    return true;
  }
}

/// Schedules one deadline callback and returns an idempotent cancellation.
typedef QuickPopDeadlineScheduler =
    void Function() Function(Duration delay, void Function() callback);

/// Owns the absolute tap-to-play deadline for Quick Pop matchmaking.
///
/// A human result is deliberately not terminal. The result must first be
/// prepared, start its replicated game sync, and pass the shared two-player
/// readiness barrier injected through [synchronize]. The five-second window
/// decides whether to keep searching; [humanPreparationGrace] gives a verified
/// pair a separate bounded window to finish opening the playable table.
///
/// Online operations are injected so a deadline or cancellation can dispose
/// resources that complete late without ever navigating after the CPU outcome
/// has won.
final class QuickPopDeadlineSearch<Connection, Ticket, Resolution, Prepared> {
  QuickPopDeadlineSearch({
    required this.window,
    this.humanPreparationGrace = const Duration(seconds: 10),
    required Duration Function() elapsed,
    required Future<Connection> Function() connect,
    required Future<Ticket> Function(Connection connection) enqueue,
    required Future<Resolution?> Function(Connection connection, Ticket ticket)
    resolve,
    required bool Function(Resolution resolution) isHumanResolution,
    required Future<Prepared> Function(
      Connection connection,
      Ticket ticket,
      Resolution resolution,
    )
    prepare,
    required Future<bool> Function(
      Connection connection,
      Ticket ticket,
      Resolution resolution,
      Prepared prepared,
    )
    synchronize,
    required Future<QuickPopDeadlineSettlement> Function(
      Connection connection,
      Ticket ticket,
      Resolution resolution,
      Prepared prepared,
    )
    settle,
    required Future<void> Function(Connection connection, Ticket ticket)
    cancelTicket,
    required Future<void> Function(
      Connection connection,
      Ticket ticket,
      Resolution resolution,
    )
    abandonResolution,
    required void Function(Prepared prepared) disposePrepared,
    required Future<void> Function(Connection connection) releaseConnection,
    required void Function(QuickPopSearchPhase phase) onPhaseChanged,
    required void Function(
      QuickPopSearchPhase phase,
      Object error,
      StackTrace stackTrace,
    )
    onFailure,
    required void Function(
      Connection connection,
      Resolution resolution,
      Prepared prepared,
    )
    onHuman,
    required void Function(QuickPopSearchPhase? failurePhase, Object? failure)
    onFallback,
    required void Function(Object? failure) onUnavailable,
    Future<void> Function(Duration duration)? delay,
    QuickPopDeadlineScheduler? scheduleDeadline,
    this.pollInterval = const Duration(milliseconds: 120),
  }) : assert(window > Duration.zero),
       assert(!humanPreparationGrace.isNegative),
       assert(pollInterval > Duration.zero),
       _connect = connect,
       _enqueue = enqueue,
       _resolve = resolve,
       _isHumanResolution = isHumanResolution,
       _prepare = prepare,
       _synchronize = synchronize,
       _settle = settle,
       _cancelTicket = cancelTicket,
       _abandonResolution = abandonResolution,
       _disposePrepared = disposePrepared,
       _releaseConnection = releaseConnection,
       _onPhaseChanged = onPhaseChanged,
       _onFailure = onFailure,
       _onHuman = onHuman,
       _onFallback = onFallback,
       _onUnavailable = onUnavailable,
       _elapsed = elapsed,
       _delay = delay ?? ((duration) => Future<void>.delayed(duration)),
       _scheduleDeadline =
           scheduleDeadline ??
           ((duration, callback) {
             final timer = Timer(duration, callback);
             return timer.cancel;
           });

  final Duration window;

  /// Extra time granted after a real opponent is found inside [window].
  ///
  /// Match preparation opens Firebase auth, the room checkpoint, presence
  /// leases, and the two-player readiness barrier. Those operations can take
  /// longer than the five-second search without meaning that the opponent
  /// disappeared. A CPU fallback is still decided at [window] when no human
  /// resolution exists; this grace only protects a verified human launch.
  final Duration humanPreparationGrace;
  final Duration pollInterval;
  final Future<Connection> Function() _connect;
  final Future<Ticket> Function(Connection connection) _enqueue;
  final Future<Resolution?> Function(Connection connection, Ticket ticket)
  _resolve;
  final bool Function(Resolution resolution) _isHumanResolution;
  final Future<Prepared> Function(
    Connection connection,
    Ticket ticket,
    Resolution resolution,
  )
  _prepare;
  final Future<bool> Function(
    Connection connection,
    Ticket ticket,
    Resolution resolution,
    Prepared prepared,
  )
  _synchronize;
  final Future<QuickPopDeadlineSettlement> Function(
    Connection connection,
    Ticket ticket,
    Resolution resolution,
    Prepared prepared,
  )
  _settle;
  final Future<void> Function(Connection connection, Ticket ticket)
  _cancelTicket;
  final Future<void> Function(
    Connection connection,
    Ticket ticket,
    Resolution resolution,
  )
  _abandonResolution;
  final void Function(Prepared prepared) _disposePrepared;
  final Future<void> Function(Connection connection) _releaseConnection;
  final void Function(QuickPopSearchPhase phase) _onPhaseChanged;
  final void Function(
    QuickPopSearchPhase phase,
    Object error,
    StackTrace stackTrace,
  )
  _onFailure;
  final void Function(
    Connection connection,
    Resolution resolution,
    Prepared prepared,
  )
  _onHuman;
  final void Function(QuickPopSearchPhase? failurePhase, Object? failure)
  _onFallback;
  final void Function(Object? failure) _onUnavailable;
  final Duration Function() _elapsed;
  final Future<void> Function(Duration duration) _delay;
  final QuickPopDeadlineScheduler _scheduleDeadline;

  final Completer<QuickPopDeadlineOutcome> _terminal = Completer();
  void Function()? _cancelDeadline;
  Connection? _connection;
  Ticket? _ticket;
  Resolution? _resolution;
  Prepared? _prepared;
  QuickPopSearchPhase _phase = QuickPopSearchPhase.connecting;
  QuickPopDeadlineOutcome _outcome = QuickPopDeadlineOutcome.searching;
  bool _started = false;
  bool _ticketCancellationStarted = false;
  bool _resolutionAbandonmentStarted = false;
  bool _preparedDisposalStarted = false;
  bool _connectionReleased = false;
  _QuickPopLaunchCommitState _launchCommitState =
      _QuickPopLaunchCommitState.none;
  bool _settlementStarted = false;
  Object? _settlementFailure;
  bool _humanPreparationDeadlineExtended = false;

  QuickPopDeadlineOutcome get outcome => _outcome;

  bool get isActive =>
      _started && _outcome == QuickPopDeadlineOutcome.searching;

  Duration get remaining {
    final value = window - _elapsed();
    return value > Duration.zero ? value : Duration.zero;
  }

  Future<QuickPopDeadlineOutcome> start() {
    if (_started) {
      throw StateError('A Quick Pop deadline search can only start once.');
    }
    _started = true;
    final initialRemaining = remaining;
    if (initialRemaining <= Duration.zero) {
      _finishFallback();
      return _terminal.future;
    }
    _cancelDeadline = _scheduleDeadline(
      initialRemaining,
      () => unawaited(_settleAtDeadline()),
    );
    unawaited(_runOnlineSearch());
    return _terminal.future;
  }

  Future<void> cancel() {
    if (!isActive) return Future<void>.value();
    _outcome = QuickPopDeadlineOutcome.cancelled;
    _cancelDeadline?.call();
    _completeTerminal();
    // Explicit cancellation must leave the UI immediately even when Firebase
    // is offline. Cleanup remains idempotent and best-effort in the background.
    unawaited(_abandonOnlineWork());
    return Future<void>.value();
  }

  Future<void> _runOnlineSearch() async {
    try {
      _setPhase(QuickPopSearchPhase.connecting);
      final connection = await _connect();
      _connection = connection;
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }

      _setPhase(QuickPopSearchPhase.enqueueing);
      final ticket = await _enqueue(connection);
      _ticket = ticket;
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }

      _setPhase(QuickPopSearchPhase.resolving);
      Resolution? resolution;
      while (isActive) {
        resolution = await _resolve(connection, ticket);
        if (!isActive) {
          if (resolution != null) {
            _resolution = resolution;
            await _abandonOnlineWork();
          }
          return;
        }
        if (resolution != null) break;
        if (!await _waitForNextPoll()) return;
      }
      if (resolution == null || !isActive) return;
      _resolution = resolution;
      if (!_isHumanResolution(resolution)) {
        _finishFallback();
        return;
      }

      _setPhase(QuickPopSearchPhase.preparing);
      final prepared = await _prepare(connection, ticket, resolution);
      _prepared = prepared;
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }

      _setPhase(QuickPopSearchPhase.synchronizing);
      while (isActive) {
        _launchCommitState = _QuickPopLaunchCommitState.possible;
        final synchronized = await _synchronize(
          connection,
          ticket,
          resolution,
          prepared,
        );
        if (!isActive) {
          await _abandonOnlineWork();
          return;
        }
        if (_settlementStarted) return;
        if (synchronized) {
          // `inGame` is only the provisional server commit. Both devices must
          // still perform the authoritative common-deadline settlement before
          // either one may navigate into the human match. The injected server
          // settlement waits for D=min(ticket deadlines), so clients whose
          // local taps were staggered still converge on the same boundary.
          _launchCommitState = _QuickPopLaunchCommitState.provisional;
          await _settleAtDeadline();
          return;
        }
        if (!await _waitForNextPoll()) return;
      }
    } catch (error, stackTrace) {
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }
      try {
        _onFailure(_phase, error, stackTrace);
      } catch (_) {
        // Analytics/UI reporting cannot be allowed to block local play.
      }
      if (_phase == QuickPopSearchPhase.synchronizing &&
          _launchCommitState != _QuickPopLaunchCommitState.none &&
          _prepared != null) {
        // A readiness write may have reached Firebase before a later read
        // failed. Do not guess CPU while the peer could have committed the
        // provisional human room; the deadline settlement decides instead.
        _settlementFailure = error;
        return;
      }
      _finishFallback(failurePhase: _phase, failure: error);
    }
  }

  Future<bool> _waitForNextPoll() async {
    final nextDelay = remaining;
    if (nextDelay <= Duration.zero) {
      unawaited(_settleAtDeadline());
      return false;
    }
    await _delay(nextDelay < pollInterval ? nextDelay : pollInterval);
    if (!isActive) return false;
    if (_elapsed() >= window) {
      unawaited(_settleAtDeadline());
      return false;
    }
    return true;
  }

  void _setPhase(QuickPopSearchPhase phase) {
    _phase = phase;
    _onPhaseChanged(phase);
  }

  void _finishHuman(
    Connection connection,
    Resolution resolution,
    Prepared prepared,
  ) {
    if (!isActive) return;
    _outcome = QuickPopDeadlineOutcome.human;
    _cancelDeadline?.call();
    _completeTerminal();
    _onHuman(connection, resolution, prepared);
  }

  Future<void> _settleAtDeadline() async {
    if (!isActive || _settlementStarted) return;
    final connection = _connection;
    final ticket = _ticket;
    final resolution = _resolution;
    final prepared = _prepared;
    // A verified human may have been found just before the search deadline
    // while Firebase is still preparing the shared table. Keep that launch
    // alive for a short, bounded grace period instead of tearing down both
    // clients at exactly the shared search deadline. If no readiness commit arrives during
    // the grace, this method runs again and falls back normally.
    if (_launchCommitState == _QuickPopLaunchCommitState.none &&
        resolution != null &&
        _isHumanResolution(resolution) &&
        connection != null &&
        ticket != null &&
        prepared == null &&
        !_humanPreparationDeadlineExtended &&
        humanPreparationGrace > Duration.zero) {
      _humanPreparationDeadlineExtended = true;
      _cancelDeadline?.call();
      _cancelDeadline = _scheduleDeadline(
        humanPreparationGrace,
        () => unawaited(_settleAtDeadline()),
      );
      return;
    }

    if (_launchCommitState == _QuickPopLaunchCommitState.none ||
        connection == null ||
        ticket == null ||
        resolution == null ||
        prepared == null ||
        !_isHumanResolution(resolution)) {
      _finishFallback();
      return;
    }

    _settlementStarted = true;
    _cancelDeadline?.call();
    _setPhase(QuickPopSearchPhase.settling);
    try {
      final decision = await _settle(connection, ticket, resolution, prepared);
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }
      switch (decision) {
        case QuickPopDeadlineSettlement.human:
          _finishHuman(connection, resolution, prepared);
          return;
        case QuickPopDeadlineSettlement.fallback:
          _finishFallback();
          return;
        case QuickPopDeadlineSettlement.unavailable:
          _finishUnavailable(_settlementFailure);
          return;
      }
    } catch (error, stackTrace) {
      if (!isActive) {
        await _abandonOnlineWork();
        return;
      }
      try {
        _onFailure(QuickPopSearchPhase.settling, error, stackTrace);
      } catch (_) {
        // Reporting cannot decide a match outcome.
      }
      _finishUnavailable(error);
    }
  }

  void _finishFallback({QuickPopSearchPhase? failurePhase, Object? failure}) {
    if (!isActive) return;
    _outcome = QuickPopDeadlineOutcome.fallback;
    _cancelDeadline?.call();
    _completeTerminal();
    // Start every available cleanup before opening local play, but do not
    // await the network: a best-effort Firebase write must never extend the
    // player's five-second promise.
    unawaited(_abandonOnlineWork());
    _onFallback(failurePhase, failure);
  }

  void _finishUnavailable(Object? failure) {
    if (!isActive) return;
    _outcome = QuickPopDeadlineOutcome.unavailable;
    _cancelDeadline?.call();
    _completeTerminal();
    // Once a provisional human commit may exist, an offline client cannot
    // safely guess CPU. Best-effort cleanup may close the provisional room;
    // the local UI reports an honest unavailable result instead of splitting.
    unawaited(_abandonOnlineWork());
    _onUnavailable(failure);
  }

  void _completeTerminal() {
    if (!_terminal.isCompleted) _terminal.complete(_outcome);
  }

  Future<void> _abandonOnlineWork() async {
    final connection = _connection;
    final ticket = _ticket;
    final resolution = _resolution;
    final prepared = _prepared;
    final operations = <Future<void>>[];

    if (prepared != null && !_preparedDisposalStarted) {
      _preparedDisposalStarted = true;
      try {
        _disposePrepared(prepared);
      } catch (_) {
        // A late prepared sync is best-effort cleanup only.
      }
    }
    if (connection != null &&
        ticket != null &&
        resolution != null &&
        !_resolutionAbandonmentStarted) {
      _resolutionAbandonmentStarted = true;
      operations.add(
        _abandonResolution(connection, ticket, resolution).catchError((_) {
          // The peer may have committed the launch at the same boundary.
        }),
      );
    }
    if (connection != null && ticket != null && !_ticketCancellationStarted) {
      _ticketCancellationStarted = true;
      operations.add(
        _cancelTicket(connection, ticket).catchError((_) {
          // A resolved ticket makes cancellation an intentional no-op.
        }),
      );
    }
    if (connection != null && !_connectionReleased) {
      _connectionReleased = true;
      operations.add(
        _releaseConnection(connection).catchError((_) {
          // Releasing an abandoned connection is best-effort cleanup.
        }),
      );
    }
    await Future.wait(operations);
  }
}
