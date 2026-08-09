import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'firebase_options.dart';
import 'online_transport.dart';
import 'online_transport_models.dart';

const String parchesePopRealtimeDatabaseUrl =
    'https://parchese-pop-default-rtdb.firebaseio.com';

/// Firebase Realtime Database adapter for the transport's small storage API.
final class FirebaseOnlineRealtimeStore
    implements OnlineRealtimeStore, OnlineRealtimeStoreLifecycle {
  FirebaseOnlineRealtimeStore({
    required FirebaseDatabase database,
    DateTime Function()? localNow,
  }) : _database = database,
       _localNow = localNow ?? DateTime.now;

  final FirebaseDatabase _database;
  final DateTime Function() _localNow;
  final Set<StreamSubscription<DatabaseEvent>> _watchSubscriptions = {};
  bool _shutDown = false;

  DatabaseReference _reference(String path) =>
      path.isEmpty ? _database.ref() : _database.ref(path);

  @override
  Future<Object?> read(String path) async =>
      onlineValue((await _reference(path).get()).value);

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
  Future<void> set(String path, Object? value) =>
      _reference(path).set(onlineValue(value));

  @override
  Future<void> update(String path, Map<String, Object?> values) =>
      _reference(path).update(<String, Object?>{
        for (final entry in values.entries) entry.key: onlineValue(entry.value),
      });

  @override
  Future<OnlineStoreTransactionResult> transaction(
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
    await _database.goOffline();
  }
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
    required this.user,
    required this.profile,
    required this.transport,
  });

  static final Set<FirebaseOnlineConnection> _activeConnections = {};

  final User user;
  final SyncedOnlineProfile profile;
  final OnlineTransportClient transport;

  /// Initializes Firebase if needed, keeps an existing account when one is
  /// signed in, or creates a temporary anonymous account for a guest.
  static Future<FirebaseOnlineConnection> connect({
    required String displayName,
    String? avatarId,
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
    final store = FirebaseOnlineRealtimeStore(database: resolvedDatabase);
    final transport = OnlineTransportClient(
      store: store,
      identity: OnlineTransportIdentity(
        uid: user.uid,
        displayName: displayName,
        avatarId: avatarId,
      ),
    );
    final profile = await transport.syncProfile();
    final connection = FirebaseOnlineConnection._(
      user: user,
      profile: profile,
      transport: transport,
    );
    _activeConnections.add(connection);
    return connection;
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
        .where((connection) => connection.user.uid == user.uid)
        .toList(growable: false);
    final fallbackStore = FirebaseOnlineRealtimeStore(
      database: resolvedDatabase,
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
