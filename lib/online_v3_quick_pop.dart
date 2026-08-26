import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'firebase_online_transport.dart' show parchesePopRealtimeDatabaseUrl;
import 'firebase_options.dart';
import 'online_v3_models.dart';

const onlineV3FunctionsRegion = 'us-east1';
const onlineV3RootPath = 'onlineV3';

/// Hostless Quick Pop V3 gateway.
///
/// The gateway speaks only to callable server endpoints for mutations. RTDB is
/// used as a read-only subscription channel for the canonical state published
/// by that backend. It is deliberately independent of the Online V2 transport.
final class OnlineV3QuickPopClient {
  OnlineV3QuickPopClient({
    required FirebaseAuth auth,
    required FirebaseDatabase database,
    required FirebaseFunctions functions,
  }) : _auth = auth,
       _database = database,
       _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final FirebaseFunctions _functions;
  final Map<String, String> _presenceEpochs = {};

  String get uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw const OnlineV3Exception('Sign in before using Quick Pop V3.');
    }
    return user.uid;
  }

  /// Opens one native Firebase SDK session on every supported platform.
  ///
  /// Unlike the V2 macOS REST fallback, callable functions need the Firebase
  /// SDK to automatically attach the Firebase Auth and App Check tokens.
  static Future<OnlineV3QuickPopClient> connect() async {
    final app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          )
        : Firebase.app();
    await _activateAppCheckWhenAvailable(app);
    final auth = FirebaseAuth.instanceFor(app: app);
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    if (auth.currentUser == null) {
      throw const OnlineV3Exception(
        'Firebase did not return an online identity.',
      );
    }
    return OnlineV3QuickPopClient(
      auth: auth,
      database: FirebaseDatabase.instanceFor(
        app: app,
        databaseURL: parchesePopRealtimeDatabaseUrl,
      ),
      functions: FirebaseFunctions.instanceFor(
        app: app,
        region: onlineV3FunctionsRegion,
      ),
    );
  }

  /// Sends or refreshes a deterministic V3 queue ticket.
  Future<OnlineV3QuickPopTicket> join({
    required String attemptId,
    required String queueKey,
    required String playerName,
    int minPlayers = 2,
    int maxPlayers = 4,
  }) async {
    final result = await _call('joinQuickPopV3', {
      'attemptId': attemptId,
      'queueKey': queueKey,
      'displayName': playerName.trim(),
      'mode': 'traditional',
      'minPlayers': minPlayers,
      'maxPlayers': maxPlayers,
    });
    return OnlineV3QuickPopTicket.fromJson(result);
  }

  /// Subscribes to canonical server state. This does not write anything.
  Stream<OnlineV3MatchState?> watchMatch(String roomId) =>
      _database.ref('$onlineV3RootPath/matches/$roomId').onValue.map((event) {
        final value = event.snapshot.value;
        if (value == null) return null;
        if (value is! Map) {
          throw const FormatException(
            'Online V3 match state is not an object.',
          );
        }
        return OnlineV3MatchState.fromJson(Map<Object?, Object?>.from(value));
      });

  /// Registers this device as present and lets RTDB mark it disconnected even
  /// when the app is backgrounded or its process is stopped abruptly.
  Future<void> beginPresence(String roomId) async {
    final epoch = _presenceEpochs.putIfAbsent(roomId, _newPresenceEpoch);
    final reference = _database.ref('$onlineV3RootPath/presence/$roomId/$uid');
    final disconnected = <String, Object?>{
      'state': 'disconnected',
      'epoch': epoch,
      'changedAt': ServerValue.timestamp,
    };
    await reference.onDisconnect().set(disconnected);
    await reference.set({
      'state': 'connected',
      'epoch': epoch,
      'changedAt': ServerValue.timestamp,
    });
  }

  /// Use for a deliberate leave. A later [beginPresence] creates a new epoch,
  /// making an already queued CPU-takeover task harmless.
  Future<void> endPresence(String roomId) async {
    final epoch = _presenceEpochs[roomId] ?? _newPresenceEpoch();
    final reference = _database.ref('$onlineV3RootPath/presence/$roomId/$uid');
    await reference.onDisconnect().cancel();
    await reference.set({
      'state': 'disconnected',
      'epoch': epoch,
      'changedAt': ServerValue.timestamp,
    });
    _presenceEpochs.remove(roomId);
  }

  /// Marks this seat AFK immediately when the app goes to Home. The server
  /// will use a temporary CPU until this device returns and reasserts presence.
  Future<void> markAfk(String roomId) async {
    final epoch = _presenceEpochs[roomId] ?? _newPresenceEpoch();
    _presenceEpochs[roomId] = epoch;
    await _database.ref('$onlineV3RootPath/presence/$roomId/$uid').set({
      'state': 'disconnected',
      'epoch': epoch,
      'changedAt': ServerValue.timestamp,
    });
  }

  Future<void> leaveQuickPop(String roomId) async {
    await _call('leaveQuickPopV3', {
      'queueKey': 'traditional_v3_beta',
      'roomId': roomId,
    });
  }

  Future<OnlineV3CommandResult> sendCommand({
    required String roomId,
    required int expectedRevision,
    required OnlineV3QuickPopCommandKind kind,
    Map<String, Object?> payload = const {},
    String? idempotencyKey,
  }) async {
    final result = await _call('submitQuickPopCommandV3', {
      'roomId': roomId,
      'expectedRevision': expectedRevision,
      'idempotencyKey': idempotencyKey ?? _newIdempotencyKey(),
      'kind': kind.name,
      'payload': payload,
    });
    return OnlineV3CommandResult.fromJson(result);
  }

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call<Object?>(data);
      if (result.data is! Map) {
        throw const OnlineV3Exception(
          'The Online V3 server returned an invalid response.',
        );
      }
      return Map<Object?, Object?>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw OnlineV3Exception(
        error.message ?? 'Online V3 server error: ${error.code}.',
      );
    }
  }

  String _newIdempotencyKey() {
    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-';
    final random = Random.secure();
    return List<String>.generate(
      24,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _newPresenceEpoch() => 'presence_${_newIdempotencyKey()}';
}

/// App Check is token-only until each released platform is registered in the
/// Firebase console. This is safe because the callable endpoints still require
/// Firebase Auth and V3 RTDB Rules deny all client writes. Windows requires a
/// registered debug token during development, supplied via --dart-define.
Future<void> _activateAppCheckWhenAvailable(FirebaseApp app) async {
  try {
    final appCheck = FirebaseAppCheck.instanceFor(app: app);
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await appCheck.activate(
          providerAndroid: const AndroidPlayIntegrityProvider(),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        await appCheck.activate(
          providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      case TargetPlatform.windows:
        const token = String.fromEnvironment('PARCHese_APP_CHECK_DEBUG_TOKEN');
        if (token.isNotEmpty) {
          await appCheck.activate(
            providerWindows: WindowsDebugProvider(debugToken: token),
          );
        }
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return;
    }
  } catch (error) {
    // App Check enrolment is staged separately from the V3 protocol. A token
    // failure must not turn an authenticated beta player into a stuck client.
    debugPrint('Online V3 App Check not available: $error');
  }
}

final class OnlineV3Exception implements Exception {
  const OnlineV3Exception(this.message);

  final String message;

  @override
  String toString() => message;
}
