import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'online_connection_safety.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

const String parchesePopRealtimeDatabaseUrl =
    'https://parchese-pop-default-rtdb.firebaseio.com';

/// Firebase Realtime Database adapter for the transport's small storage API.
final class FirebaseOnlineRealtimeStore
    implements
        OnlineRealtimeStore,
        OnlineRealtimeQueryStore,
        OnlineRealtimeExactReadPolicy,
        OnlineRealtimeStoreLifecycle {
  FirebaseOnlineRealtimeStore({
    required FirebaseDatabase database,
    FirebaseAuth? auth,
    DateTime Function()? localNow,
  }) : _database = database,
       _auth = auth,
       _localNow = localNow ?? DateTime.now;

  final FirebaseDatabase _database;
  final FirebaseAuth? _auth;
  final DateTime Function() _localNow;
  final Set<StreamSubscription<DatabaseEvent>> _watchSubscriptions = {};
  FirebaseRestRealtimeStore? _authenticatedRestFallback;
  String? _authenticatedRestFallbackToken;
  bool _shutDown = false;

  /// Exact opponent-ticket reads are authorized only after the deterministic
  /// Quick Pop claim exists in Realtime Database. The transport uses this
  /// capability marker to avoid a pre-claim read/transaction race in the
  /// production security rules; in-memory stores keep the direct check used by
  /// the deterministic unit tests.
  @override
  bool get opponentTicketExactReadRequiresClaim => true;

  DatabaseReference _reference(String path) =>
      path.isEmpty ? _database.ref() : _database.ref(path);

  /// The native Realtime Database plugin can briefly reject a write while its
  /// socket is restoring auth state (most commonly after Home/resume). The
  /// authenticated REST endpoint uses the same token and rules, but does not
  /// depend on that native socket. Keep this fallback local to this store so
  /// Quick Table and every other write continue using the native SDK normally.
  Future<FirebaseRestRealtimeStore?> _restWriteFallback() async {
    final user = _auth?.currentUser;
    if (user == null) return null;
    String? token;
    try {
      token = await user.getIdToken().timeout(
        OnlineConnectionSafety.authTokenTimeout,
      );
    } catch (error) {
      // Token refresh is a recoverable prerequisite. Returning null lets the
      // caller try the native SDK instead of turning a temporary auth delay
      // into a permanent online failure.
      debugPrint('Firebase REST token refresh unavailable: $error');
      return null;
    }
    if (token is! String || token.isEmpty) return null;
    if (_authenticatedRestFallback != null &&
        _authenticatedRestFallbackToken == token) {
      return _authenticatedRestFallback;
    }
    final previous = _authenticatedRestFallback;
    _authenticatedRestFallback = FirebaseRestRealtimeStore(idToken: token);
    _authenticatedRestFallbackToken = token;
    if (previous != null) await previous.shutdown();
    return _authenticatedRestFallback;
  }

  Future<void> _writeWithRestFallback(
    String operation,
    String path,
    Future<void> Function(FirebaseRestRealtimeStore fallback) write,
    Object nativeError,
    StackTrace nativeStack,
  ) async {
    try {
      final fallback = await _restWriteFallback();
      if (fallback == null) {
        Error.throwWithStackTrace(nativeError, nativeStack);
      }
      await OnlineConnectionSafety.bounded(
        'rest-$operation',
        path,
        () => write(fallback),
        timeout: OnlineConnectionSafety.restOperationTimeout,
      );
      debugPrint(
        'Firebase $operation recovered through authenticated REST at $path.',
      );
    } catch (fallbackError, fallbackStack) {
      final combined = StateError(
        'Firebase $operation failed at $path. '
        'Native: $nativeError. REST fallback: $fallbackError',
      );
      Error.throwWithStackTrace(combined, fallbackStack);
    }
  }

  @override
  Future<Object?> read(String path) async {
    if (OnlineConnectionSafety.enabled &&
        OnlineConnectionSafety.protectsPath(path)) {
      final fallback = await _restWriteFallback();
      if (fallback != null) {
        try {
          return await OnlineConnectionSafety.bounded(
            'rest-read',
            path,
            () => fallback.read(path),
            timeout: OnlineConnectionSafety.restOperationTimeout,
          );
        } catch (error) {
          debugPrint(
            'Firebase REST read failed at $path; trying native: $error',
          );
        }
      }
    }
    try {
      return onlineValue(
        await OnlineConnectionSafety.bounded(
          'native-read',
          path,
          () async => (await _reference(path).get()).value,
          timeout: OnlineConnectionSafety.nativeOperationTimeout,
        ),
      );
    } catch (error, stackTrace) {
      if (!OnlineConnectionSafety.enabled ||
          !OnlineConnectionSafety.protectsPath(path)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      final fallback = await _restWriteFallback();
      if (fallback == null) Error.throwWithStackTrace(error, stackTrace);
      return OnlineConnectionSafety.bounded(
        'rest-read-retry',
        path,
        () => fallback.read(path),
        timeout: OnlineConnectionSafety.restOperationTimeout,
      );
    }
  }

  @override
  Future<Object?> readOrderedChildren(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  }) async {
    // Quick Pop matchmaking is latency-sensitive and its parent queue query
    // can remain pending in the native Firebase SDK while the socket is
    // reconnecting. Use the same authenticated REST endpoint directly for
    // this one indexed queue so a client always receives a bounded snapshot;
    // all paths still use the same authenticated rules, and exact ticket
    // reads remain claim-guarded by the protocol.
    if (OnlineConnectionSafety.enabled && _isQuickPopQueuePath(path)) {
      try {
        return await _readOrderedChildrenViaRest(
          path,
          orderByChild: orderByChild,
          startAt: startAt,
          limitToFirst: limitToFirst,
        );
      } catch (error) {
        // REST is the preferred bounded path, not a second authority. If it
        // is unavailable, continue to the native query below and let the
        // same circuit breaker decide whether that attempt is usable.
        debugPrint(
          'Firebase queue REST read failed at $path; trying native: $error',
        );
      }
    }
    final query = _reference(
      path,
    ).orderByChild(orderByChild).startAt(startAt).limitToFirst(limitToFirst);
    // The native iOS/Android query can remain pending when Realtime Database
    // is reconnecting or when a rules query is rejected before the SDK
    // delivers its error. Quick Pop only has a 30-second search window, so a
    // pending read must never block the resolver until the window expires.
    // Use the authenticated REST endpoint as a bounded fallback for the
    // matchmaking queue; it applies the same Firebase rules and returns the
    // exact ordered snapshot required by the deterministic group matcher.
    try {
      return onlineValue(
        (await query.get().timeout(
          OnlineConnectionSafety.queueReadTimeout,
        )).value,
      );
    } catch (error) {
      if (!OnlineConnectionSafety.enabled || !_isQuickPopQueuePath(path)) {
        rethrow;
      }
      return _readOrderedChildrenViaRest(
        path,
        orderByChild: orderByChild,
        startAt: startAt,
        limitToFirst: limitToFirst,
      );
    }
  }

  bool _isQuickPopQueuePath(String path) {
    final normalized = path.trim().replaceFirst(RegExp(r'^/+'), '');
    return OnlineConnectionSafety.protectsPath(path) &&
        (normalized == 'onlineV2/quickQueues' ||
            normalized.startsWith('onlineV2/quickQueues/'));
  }

  Future<Object?> _readOrderedChildrenViaRest(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  }) async {
    final user = _auth?.currentUser;
    final token = await user?.getIdToken().timeout(
      OnlineConnectionSafety.authTokenTimeout,
    );
    if (token is! String || token.isEmpty) {
      throw StateError('Firebase Auth has no ID token for queue fallback.');
    }
    final cleanPath = path.trim().isEmpty ? '' : '/${path.trim()}';
    final uri = Uri.parse('$parchesePopRealtimeDatabaseUrl$cleanPath.json')
        .replace(
          queryParameters: <String, String>{
            'auth': token,
            'orderBy': jsonEncode(orderByChild),
            'startAt': '$startAt',
            'limitToFirst': '$limitToFirst',
          },
        );
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(OnlineConnectionSafety.queueReadTimeout);
      final response = await request.close().timeout(
        OnlineConnectionSafety.queueReadTimeout,
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(OnlineConnectionSafety.queueReadTimeout);
      Object? decoded;
      if (body.trim().isNotEmpty) {
        decoded = jsonDecode(body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Firebase queue REST fallback failed (${response.statusCode}): '
          '${decoded ?? 'unknown error'}',
        );
      }
      return onlineValue(decoded);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Stream<Object?> watch(String path) {
    late final StreamController<Object?> controller;
    StreamSubscription<DatabaseEvent>? subscription;
    controller = StreamController<Object?>(
      onListen: () {
        if (_shutDown) {
          unawaited(controller.close());
          return;
        }
        final current = _reference(path).onValue.listen(
          (event) => controller.add(onlineValue(event.snapshot.value)),
          onError: controller.addError,
          onDone: () {
            final active = subscription;
            if (active != null) _watchSubscriptions.remove(active);
            if (!controller.isClosed) unawaited(controller.close());
          },
        );
        subscription = current;
        _watchSubscriptions.add(current);
      },
      onCancel: () async {
        final active = subscription;
        if (active == null) return;
        _watchSubscriptions.remove(active);
        await active.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> set(String path, Object? value) async {
    // Quick Pop's queue/group/claim writes are server-authoritative. Prefer
    // the authenticated REST session for these paths so a native SDK socket
    // that is still restoring after Home/resume cannot leave the write
    // pending. The native SDK remains the fallback for transient REST errors.
    if (OnlineConnectionSafety.enabled && _isOnlineV2WritePath(path)) {
      final fallback = await _restWriteFallback();
      if (fallback != null) {
        try {
          await OnlineConnectionSafety.bounded(
            'rest-set',
            path,
            () => fallback.set(path, value),
            timeout: OnlineConnectionSafety.restOperationTimeout,
          );
          debugPrint(
            'Firebase set completed through authenticated REST at $path.',
          );
          return;
        } catch (error) {
          debugPrint(
            'Firebase REST set failed at $path; trying native: $error',
          );
        }
      }
    }
    try {
      // A restored native Firebase socket can leave a write Future pending
      // instead of completing or reporting PERMISSION_DENIED. The caller's
      // matchmaking deadline must not be held hostage by that socket.
      await OnlineConnectionSafety.bounded(
        'native-set',
        path,
        () => _reference(path).set(onlineValue(value)),
        timeout: OnlineConnectionSafety.nativeOperationTimeout,
      );
    } catch (error, stackTrace) {
      if (!OnlineConnectionSafety.enabled) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await _writeWithRestFallback(
        'set',
        path,
        (fallback) => fallback.set(path, value),
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<void> update(String path, Map<String, Object?> values) async {
    final encoded = <String, Object?>{
      for (final entry in values.entries) entry.key: onlineValue(entry.value),
    };
    if (OnlineConnectionSafety.enabled && _isOnlineV2WritePath(path)) {
      final fallback = await _restWriteFallback();
      if (fallback != null) {
        try {
          await OnlineConnectionSafety.bounded(
            'rest-update',
            path,
            () => fallback.update(path, values),
            timeout: OnlineConnectionSafety.restOperationTimeout,
          );
          debugPrint(
            'Firebase update completed through authenticated REST at $path.',
          );
          return;
        } catch (error) {
          debugPrint(
            'Firebase REST update failed at $path; trying native: $error',
          );
        }
      }
    }
    try {
      await OnlineConnectionSafety.bounded(
        'native-update',
        path,
        () => _reference(path).update(encoded),
        timeout: OnlineConnectionSafety.nativeOperationTimeout,
      );
    } catch (error, stackTrace) {
      if (!OnlineConnectionSafety.enabled) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      await _writeWithRestFallback(
        'update',
        path,
        (fallback) => fallback.update(path, values),
        error,
        stackTrace,
      );
    }
  }

  bool _isOnlineV2WritePath(String path) =>
      OnlineConnectionSafety.protectsPath(path);

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    if (OnlineConnectionSafety.enabled &&
        OnlineConnectionSafety.protectsPath(path)) {
      final fallback = await _restWriteFallback();
      if (fallback != null) {
        try {
          return await OnlineConnectionSafety.bounded(
            'rest-transaction',
            path,
            () => fallback.transaction(path, updater),
            timeout: OnlineConnectionSafety.restTransactionTimeout,
          );
        } on OnlineConnectionTimeout {
          // A timed-out REST transaction may have reached Firebase even when
          // its response was lost. Never replay the updater through native in
          // that ambiguous state; the caller can safely retry the whole
          // protocol on its next poll.
          rethrow;
        } catch (error) {
          // A permission or transient REST failure can still be accepted by
          // the native SDK after its auth socket catches up. The native
          // attempt below is bounded so a bad socket cannot freeze search.
          debugPrint(
            'Firebase REST transaction failed at $path; trying native: $error',
          );
        }
      }
    }
    return OnlineConnectionSafety.bounded(
      'native-transaction',
      path,
      () => _nativeTransaction(path, updater),
      timeout: OnlineConnectionSafety.nativeTransactionTimeout,
    );
  }

  Future<OnlineStoreTransactionResult> _nativeTransaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    final reference = _reference(path);
    // Android invokes a transaction handler immediately with its local cache.
    // On a freshly opened path that first value can be null even when the
    // server already contains the record, causing domain updaters to reject a
    // valid ticket or room before Firebase can retry it with server state.
    // A wire read tells us whether this path should already have a value. It
    // does not necessarily populate Android's transaction cache, so the first
    // transaction callback below can still receive null.
    final prefetchedValue = onlineValue((await reference.get()).value);
    var awaitingKnownServerValue = prefetchedValue != null;
    final result = await reference.runTransaction((current) {
      final currentValue = onlineValue(current);
      if (awaitingKnownServerValue && currentValue == null) {
        // Commit the same null as a compare-and-swap probe. If the known value
        // still exists, Firebase detects the stale hash and retries with the
        // real server value. If another client deleted it after our read, null
        // commits as null and we never resurrect the deleted ticket or room.
        // Do not substitute [prefetchedValue] here for that reason.
        return Transaction.success(null);
      }
      awaitingKnownServerValue = false;
      final decision = updater(currentValue);
      return switch (decision) {
        OnlineStoreCommit(:final value) => Transaction.success(
          onlineValue(value),
        ),
        OnlineStoreAbort() => Transaction.abort(),
      };
    }, applyLocally: false);
    return OnlineStoreTransactionResult(
      committed: result.committed,
      value: onlineValue(result.snapshot.value),
    );
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) =>
      _reference(path).onDisconnect().set(onlineValue(value));

  @override
  Future<void> cancelOnDisconnect(String path) =>
      _reference(path).onDisconnect().cancel();

  @override
  Future<int> serverNowMs() async {
    // Realtime Database exposes `.info` as a live special location. Android's
    // one-shot wire `get` command rejects that reserved path with
    // "Invalid token in path", while a value listener is supported on every
    // Firebase platform. Take the first event so callers still receive a
    // one-shot server-clock sample without keeping a subscription alive.
    final event = await _database.ref('.info/serverTimeOffset').onValue.first;
    final offset = event.snapshot.value;
    return _localNow().toUtc().millisecondsSinceEpoch +
        (offset is num ? offset.toInt() : 0);
  }

  /// Stops every listener created by this adapter and closes its Firebase
  /// socket. A future online connection explicitly calls `goOnline` again.
  @override
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    final subscriptions = List<StreamSubscription<DatabaseEvent>>.of(
      _watchSubscriptions,
    );
    _watchSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final fallback = _authenticatedRestFallback;
    _authenticatedRestFallback = null;
    _authenticatedRestFallbackToken = null;
    if (fallback != null) await fallback.shutdown();
    await _database.goOffline();
  }
}

/// Small Firebase Realtime Database REST adapter used by the macOS desktop
/// build. Firebase Auth's native macOS plugin persists anonymous sessions in
/// Keychain and therefore requires a Mac App Development profile with
/// Keychain Sharing enabled. The REST session uses the same Firebase project
/// and rules, while keeping the temporary anonymous identity in memory. This
/// makes Quick Table usable in a local desktop QA build and in a signed
/// desktop release without changing the room protocol.
final class FirebaseRestRealtimeStore
    implements
        OnlineRealtimeStore,
        OnlineRealtimeQueryStore,
        OnlineRealtimeExactReadPolicy,
        OnlineRealtimeStoreLifecycle {
  FirebaseRestRealtimeStore({
    required String idToken,
    HttpClient? client,
    DateTime Function()? localNow,
  }) : _idToken = idToken,
       _client = client ?? HttpClient(),
       _localNow = localNow ?? DateTime.now;

  final String _idToken;
  final HttpClient _client;
  final DateTime Function() _localNow;
  final Set<Timer> _watchTimers = <Timer>{};
  bool _shutDown = false;

  @override
  bool get opponentTicketExactReadRequiresClaim => true;

  Uri _uri(String path, [Map<String, String>? parameters]) {
    final cleanPath = path.trim().isEmpty ? '' : '/${path.trim()}';
    final query = <String, String>{'auth': _idToken, ...?parameters};
    return Uri.parse(
      '$parchesePopRealtimeDatabaseUrl$cleanPath.json',
    ).replace(queryParameters: query);
  }

  Future<_FirebaseRestResponse> _request(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (_shutDown) throw StateError('The Firebase REST session is closed.');
    final request = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 4));
    request.headers.contentType = ContentType.json;
    headers?.forEach(request.headers.set);
    // Realtime Database requires an explicit JSON `null` for a PUT that
    // deletes a path. Leaving the body empty makes Firebase return 400
    // ("No data supplied"), which surfaced when a Quick Table closed its
    // public-directory entry or cleaned its presence.
    if (body != null || method == 'PUT' || method == 'PATCH') {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 4));
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 4));
    Object? decoded;
    if (text.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = text;
      }
    }
    return _FirebaseRestResponse(
      statusCode: response.statusCode,
      body: decoded,
      etag: response.headers.value('etag'),
    );
  }

  void _check(_FirebaseRestResponse response, [String? path]) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final location = path == null || path.trim().isEmpty
        ? ''
        : ' at ${path.trim()}';
    throw StateError(
      'Firebase REST request failed (${response.statusCode})$location: '
      '${response.body ?? 'unknown error'}',
    );
  }

  @override
  Future<Object?> read(String path) async {
    final response = await _request('GET', _uri(path));
    _check(response, path);
    return onlineValue(response.body);
  }

  @override
  Future<Object?> readOrderedChildren(
    String path, {
    required String orderByChild,
    required num startAt,
    required int limitToFirst,
  }) async {
    final response = await _request(
      'GET',
      _uri(path, <String, String>{
        'orderBy': jsonEncode(orderByChild),
        'startAt': '$startAt',
        'limitToFirst': '$limitToFirst',
      }),
    );
    // The public-room index is intentionally a small denormalized directory
    // and does not have a server-side indexedAt rule. Firebase rejects the
    // ordered query with HTTP 400 in that case; fall back to the authenticated
    // snapshot and let the transport perform its deterministic local sort.
    if (response.statusCode == HttpStatus.badRequest &&
        path == 'onlineV2/publicRooms') {
      return read(path);
    }
    _check(response, path);
    return onlineValue(response.body);
  }

  @override
  Future<void> set(String path, Object? value) async {
    final response = await _request(
      'PUT',
      _uri(path),
      body: onlineValue(value),
    );
    _check(response, path);
  }

  @override
  Future<void> update(String path, Map<String, Object?> values) async {
    final response = await _request(
      'PATCH',
      _uri(path),
      body: <String, Object?>{
        for (final entry in values.entries) entry.key: onlineValue(entry.value),
      },
    );
    _check(response, path);
  }

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final readResponse = await _request(
        'GET',
        _uri(path),
        headers: const <String, String>{'X-Firebase-ETag': 'true'},
      );
      _check(readResponse, path);
      final decision = updater(onlineValue(readResponse.body));
      if (decision is OnlineStoreAbort) {
        return OnlineStoreTransactionResult(
          committed: false,
          value: onlineValue(readResponse.body),
        );
      }
      final commit = decision as OnlineStoreCommit;
      final writeResponse = await _request(
        'PUT',
        _uri(path),
        body: onlineValue(commit.value),
        headers: <String, String>{'if-match': readResponse.etag ?? 'null_etag'},
      );
      if (writeResponse.statusCode == HttpStatus.preconditionFailed) {
        continue;
      }
      _check(writeResponse, path);
      return OnlineStoreTransactionResult(
        committed: true,
        value: onlineValue(writeResponse.body),
      );
    }
    return const OnlineStoreTransactionResult(committed: false, value: null);
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) async {
    // REST has no onDisconnect endpoint. Presence is refreshed on every
    // lobby snapshot and the next connection cleans up stale room records.
  }

  @override
  Future<void> cancelOnDisconnect(String path) async {}

  @override
  Future<int> serverNowMs() async {
    try {
      final response = await _request('GET', _uri('.info/serverTimeOffset'));
      _check(response, '.info/serverTimeOffset');
      final offset = response.body;
      return _localNow().toUtc().millisecondsSinceEpoch +
          (offset is num ? offset.toInt() : 0);
    } catch (_) {
      return _localNow().toUtc().millisecondsSinceEpoch;
    }
  }

  @override
  Stream<Object?> watch(String path) {
    late final StreamController<Object?> controller;
    Timer? timer;
    Object? last;
    var first = true;
    var reading = false;

    Future<void> poll() async {
      if (reading || controller.isClosed || _shutDown) return;
      reading = true;
      try {
        final next = await read(path);
        final same = !first && jsonEncode(next) == jsonEncode(last);
        if (first || !same) {
          first = false;
          last = next;
          if (!controller.isClosed) controller.add(next);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        reading = false;
      }
    }

    controller = StreamController<Object?>(
      onListen: () {
        unawaited(poll());
        timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
          unawaited(poll());
        });
        _watchTimers.add(timer!);
      },
      onCancel: () {
        final active = timer;
        if (active != null) {
          _watchTimers.remove(active);
          active.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> shutdown() async {
    if (_shutDown) return;
    _shutDown = true;
    for (final timer in _watchTimers) {
      timer.cancel();
    }
    _watchTimers.clear();
    _client.close(force: true);
  }
}

final class _FirebaseRestResponse {
  const _FirebaseRestResponse({
    required this.statusCode,
    required this.body,
    required this.etag,
  });

  final int statusCode;
  final Object? body;
  final String? etag;
}

final class _FirebaseRestAuthResponse {
  const _FirebaseRestAuthResponse({
    required this.idToken,
    required this.localId,
  });

  final String idToken;
  final String localId;
}

enum OnlineAccountDeletionErrorCode {
  nonAnonymousIdentityRequiresBackend,
  backendCleanupRequired,
  cleanupFailed,
  identityDeletionFailed,
}

final class OnlineAccountDeletionException implements Exception {
  const OnlineAccountDeletionException(this.code, this.message, [this.cause]);

  final OnlineAccountDeletionErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class OnlineAccountDeletionResult {
  const OnlineAccountDeletionResult({
    required this.hadOnlineIdentity,
    required this.anonymousIdentityDeleted,
    required this.cleanupReports,
  });

  const OnlineAccountDeletionResult.noOnlineIdentity()
    : hadOnlineIdentity = false,
      anonymousIdentityDeleted = false,
      cleanupReports = const <OnlineAccountCleanupReport>[];

  final bool hadOnlineIdentity;
  final bool anonymousIdentityDeleted;
  final List<OnlineAccountCleanupReport> cleanupReports;
}

/// Testable ordering boundary: remote data first, listeners second, anonymous
/// Auth identity last. Any failure is surfaced so the UI can keep local data
/// and offer a safe retry while the Firebase credential still exists.
final class OnlineAnonymousAccountDeletionCoordinator {
  OnlineAnonymousAccountDeletionCoordinator({
    required Iterable<OnlineTransportClient> transports,
    required this.deleteAnonymousIdentity,
  }) : transports = List<OnlineTransportClient>.unmodifiable(transports);

  final List<OnlineTransportClient> transports;
  final Future<void> Function() deleteAnonymousIdentity;

  Future<List<OnlineAccountCleanupReport>> delete() async {
    final reports = <OnlineAccountCleanupReport>[];
    try {
      for (final transport in transports) {
        reports.add(await transport.deleteOwnOnlineData());
      }
    } on OnlineAccountCleanupRequiresBackend catch (error) {
      throw OnlineAccountDeletionException(
        OnlineAccountDeletionErrorCode.backendCleanupRequired,
        'Esta cuenta online antigua necesita una limpieza verificada. '
        'Escribe a sales@liisgo.com; nunca envíes tu contraseña.',
        error,
      );
    } catch (error) {
      // Keep the authenticated socket available after a cleanup failure so
      // the UI's retry can continue with the same identity. Shutting the
      // adapter down here made a recoverable network error impossible to
      // retry without rebuilding every active connection first.
      throw OnlineAccountDeletionException(
        OnlineAccountDeletionErrorCode.cleanupFailed,
        'No se pudieron borrar todavía los datos online. Inténtalo de nuevo.',
        error,
      );
    }

    await _shutdownBestEffort();
    try {
      await deleteAnonymousIdentity();
    } catch (error) {
      throw OnlineAccountDeletionException(
        OnlineAccountDeletionErrorCode.identityDeletionFailed,
        'Los datos online se limpiaron, pero la sesión no pudo cerrarse. '
        'Inténtalo de nuevo.',
        error,
      );
    }
    return List<OnlineAccountCleanupReport>.unmodifiable(reports);
  }

  Future<void> _shutdownBestEffort() async {
    for (final transport in transports) {
      try {
        await transport.shutdown();
      } catch (_) {
        // Cleanup/auth errors remain the actionable failure. A future connect
        // always creates a fresh adapter and explicitly reopens Firebase.
      }
    }
  }
}

/// Authenticated Firebase session ready to create/watch rooms and queues.
final class FirebaseOnlineConnection {
  FirebaseOnlineConnection._({
    required this.uid,
    required this.profile,
    required this.transport,
  });

  static final Set<FirebaseOnlineConnection> _activeConnections = {};

  final String uid;
  final SyncedOnlineProfile profile;
  final OnlineTransportClient transport;

  /// Stops retaining a connection that never reached a playable online room.
  ///
  /// The transport itself has no open listener to close here. Queue cleanup is
  /// performed by the caller before releasing the connection.
  void release() {
    _activeConnections.remove(this);
  }

  /// Initializes Firebase if needed, keeps an existing account when one is
  /// signed in, or creates a temporary anonymous account for a guest.
  static Future<FirebaseOnlineConnection> connect({
    required String displayName,
    String? avatarId,
    FirebaseApp? app,
    FirebaseAuth? auth,
    FirebaseDatabase? database,
    QuickPopDebugSink? quickPopDebugSink,
  }) async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        app == null &&
        auth == null &&
        database == null) {
      return _connectMacOsRest(
        displayName: displayName,
        avatarId: avatarId,
        quickPopDebugSink: quickPopDebugSink,
      );
    }
    final resolvedApp =
        app ??
        (Firebase.apps.isEmpty
            ? await Firebase.initializeApp(
                options: DefaultFirebaseOptions.currentPlatform,
              )
            : Firebase.app());
    final resolvedAuth = auth ?? FirebaseAuth.instanceFor(app: resolvedApp);
    var user = resolvedAuth.currentUser;
    if (user == null) {
      final credential = await resolvedAuth.signInAnonymously();
      user = credential.user;
    }
    if (user == null) {
      throw StateError('Firebase anonymous authentication returned no user.');
    }

    final resolvedDatabase =
        database ??
        FirebaseDatabase.instanceFor(
          app: resolvedApp,
          databaseURL: parchesePopRealtimeDatabaseUrl,
        );
    await resolvedDatabase.goOnline();
    final store = FirebaseOnlineRealtimeStore(
      database: resolvedDatabase,
      auth: resolvedAuth,
    );
    final transport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: user.uid,
        displayName: displayName,
        avatarId: avatarId,
      ),
      quickPopDebugSink: quickPopDebugSink,
    );
    final profile = await transport.syncProfile();
    final connection = FirebaseOnlineConnection._(
      uid: user.uid,
      profile: profile,
      transport: transport,
    );
    _activeConnections.add(connection);
    return connection;
  }

  static Future<FirebaseOnlineConnection> _connectMacOsRest({
    required String displayName,
    String? avatarId,
    QuickPopDebugSink? quickPopDebugSink,
  }) async {
    final options = DefaultFirebaseOptions.macos;
    final response = await _requestAnonymousToken(options.apiKey);
    final store = FirebaseRestRealtimeStore(idToken: response.idToken);
    final transport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: response.localId,
        displayName: displayName,
        avatarId: avatarId,
      ),
      quickPopDebugSink: quickPopDebugSink,
    );
    final profile = await transport.syncProfile();
    final connection = FirebaseOnlineConnection._(
      uid: response.localId,
      profile: profile,
      transport: transport,
    );
    _activeConnections.add(connection);
    return connection;
  }

  static Future<_FirebaseRestAuthResponse> _requestAnonymousToken(
    String apiKey,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp'
          '?key=${Uri.encodeQueryComponent(apiKey)}',
        ),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, Object?>{'returnSecureToken': true}));
      final response = await request.close();
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body is! Map) {
        throw StateError('Firebase anonymous authentication failed.');
      }
      final idToken = body['idToken'];
      final localId = body['localId'];
      if (idToken is! String || localId is! String) {
        throw StateError(
          'Firebase anonymous authentication returned no identity.',
        );
      }
      return _FirebaseRestAuthResponse(idToken: idToken, localId: localId);
    } finally {
      client.close(force: true);
    }
  }

  /// Deletes the current guest's safe realtime footprint and then its
  /// anonymous Firebase Auth identity. Local profile/wallet deletion remains
  /// in the caller and runs only after this operation succeeds.
  static Future<OnlineAccountDeletionResult> deleteCurrentOnlineAccountData({
    FirebaseApp? app,
    FirebaseAuth? auth,
    FirebaseDatabase? database,
  }) async {
    final resolvedApp =
        app ??
        (Firebase.apps.isEmpty
            ? await Firebase.initializeApp(
                options: DefaultFirebaseOptions.currentPlatform,
              )
            : Firebase.app());
    final resolvedAuth = auth ?? FirebaseAuth.instanceFor(app: resolvedApp);
    final user = resolvedAuth.currentUser;
    if (user == null) {
      return const OnlineAccountDeletionResult.noOnlineIdentity();
    }
    if (!user.isAnonymous) {
      throw const OnlineAccountDeletionException(
        OnlineAccountDeletionErrorCode.nonAnonymousIdentityRequiresBackend,
        'Esta cuenta enlazada necesita verificación del servidor antes de '
        'borrarse.',
      );
    }

    final resolvedDatabase =
        database ??
        FirebaseDatabase.instanceFor(
          app: resolvedApp,
          databaseURL: parchesePopRealtimeDatabaseUrl,
        );
    await resolvedDatabase.goOnline();
    final active = _activeConnections
        .where((connection) => connection.uid == user.uid)
        .toList(growable: false);
    final fallbackStore = FirebaseOnlineRealtimeStore(
      database: resolvedDatabase,
      auth: resolvedAuth,
    );
    final fallbackTransport = OnlineTransportClient(
      store: fallbackStore,
      identity: OnlineTransportIdentity(uid: user.uid, displayName: 'Jugador'),
    );
    final transports = <OnlineTransportClient>{
      for (final connection in active) connection.transport,
      fallbackTransport,
    };
    final coordinator = OnlineAnonymousAccountDeletionCoordinator(
      transports: transports,
      deleteAnonymousIdentity: user.delete,
    );
    final reports = await coordinator.delete();
    _activeConnections.removeAll(active);
    return OnlineAccountDeletionResult(
      hadOnlineIdentity: true,
      anonymousIdentityDeleted: true,
      cleanupReports: reports,
    );
  }
}
