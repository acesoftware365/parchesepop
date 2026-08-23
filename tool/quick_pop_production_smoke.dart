import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:parchesepop/firebase_online_transport.dart';
import 'package:parchesepop/game_engine.dart';
import 'package:parchesepop/online_mode_services.dart';
import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

/// Authenticated smoke test for the deployed Quick Pop v2 group protocol.
/// This is intentionally a tool (not a normal unit test) because it creates
/// short-lived anonymous Firebase identities and queue records.
Future<void> main() => runProductionSmoke(clientCount: 2);

/// Four-seat variant used to verify the same production protocol at its
/// maximum human group size.
Future<void> mainFour() => runProductionSmoke(clientCount: 4);

Future<void> runProductionSmoke({required int clientCount}) async {
  if (clientCount < 2 || clientCount > 4) {
    throw ArgumentError.value(clientCount, 'clientCount', 'must be 2..4');
  }
  final labels = List<String>.generate(
    clientCount,
    (index) => String.fromCharCode('A'.codeUnitAt(0) + index),
  );
  final traces = <String, List<String>>{
    for (final label in labels) label: <String>[],
  };
  void sink(
    String client,
    String step, {
    String detail = '',
    String? path,
    bool success = false,
    bool error = false,
  }) {
    final line =
        '${error
            ? 'ERR'
            : success
            ? 'OK'
            : 'WAIT'} $step'
        '${detail.isEmpty ? '' : ' | $detail'}';
    traces[client]!.add(line);
    stdout.writeln('$client $line');
  }

  final stores = <FirebaseRestRealtimeStore>[];
  final transports = <OnlineTransportClient>[];
  final tickets = <QuickPopQueueTicket>[];
  try {
    final auth = await Future.wait<_AuthIdentity>(
      List<Future<_AuthIdentity>>.generate(
        clientCount,
        (_) => _anonymousAuth(),
      ),
    );
    for (var index = 0; index < clientCount; index++) {
      final label = labels[index];
      final identity = auth[index];
      final store = FirebaseRestRealtimeStore(idToken: identity.token);
      stores.add(store);
      transports.add(
        OnlineTransportClient(
          store: store,
          identity: OnlineTransportIdentity(
            uid: identity.uid,
            displayName: 'QA Pop $label',
          ),
          quickPopDebugSink:
              (
                step, {
                String detail = '',
                String? path,
                bool success = false,
                bool error = false,
              }) => sink(
                label,
                step,
                detail: detail,
                path: path,
                success: success,
                error: error,
              ),
        ),
      );
    }
    // The app initializes the account-resource index during Firebase
    // connection. Do the same here so this smoke test exercises the exact
    // production path rather than an intentionally incomplete new account.
    await Future.wait(transports.map((transport) => transport.syncProfile()));
    final services = transports.map(OnlineQuickPopService.new).toList();
    tickets.addAll(
      await Future.wait(
        services.map((service) => service.enqueue(mode: GameMode.traditional)),
      ),
    );
    final unexpectedQueue = tickets
        .where((ticket) => ticket.queueKey != 'traditional_quickPop_v2')
        .map((ticket) => ticket.queueKey)
        .toSet();
    if (unexpectedQueue.isNotEmpty) {
      throw StateError('Unexpected queue keys: $unexpectedQueue');
    }
    final resolutions = List<QuickPopResolution?>.filled(clientCount, null);
    // A two-player production search may legitimately settle only when the
    // shared 30-second window closes. Leave a small network margin instead
    // of treating the still-waiting group as a failed resolution.
    final endAt = DateTime.now().add(
      quickPopSearchWindow + const Duration(seconds: 8),
    );
    while (DateTime.now().isBefore(endAt) &&
        resolutions.any((resolution) => resolution == null)) {
      final pending = <Future<QuickPopResolution?>>[];
      final pendingIndices = <int>[];
      for (var index = 0; index < clientCount; index++) {
        if (resolutions[index] == null) {
          pendingIndices.add(index);
          pending.add(services[index].resolve(tickets[index]));
        }
      }
      final results = await Future.wait(pending);
      for (var index = 0; index < results.length; index++) {
        resolutions[pendingIndices[index]] = results[index];
      }
      if (resolutions.any((resolution) => resolution == null)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    final resolved = resolutions.cast<QuickPopResolution>();
    final roomIds = resolved.map((resolution) => resolution.roomId).toSet();
    if (resolved.any(
          (resolution) => resolution.kind != QuickPopResolutionKind.human,
        ) ||
        roomIds.length != 1) {
      throw StateError('Expected one human room; got $resolved');
    }
    final participants = resolved.first.participantUids.toSet();
    final expectedUids = auth.map((identity) => identity.uid).toSet();
    if (participants.length != clientCount ||
        !participants.containsAll(expectedUids)) {
      throw StateError('Unexpected participants: $participants');
    }
    stdout.writeln(
      'PASS Quick Pop v2 human smoke: clients=$clientCount '
      'queue=${tickets.first.queueKey} room=${resolved.first.roomId} '
      'participants=${participants.join(',')}',
    );
  } finally {
    // The normal app cleanup is idempotent. If a smoke assertion fails before
    // a resolution exists, cancel each ticket so the queue cannot pollute the
    // next run.
    for (var index = 0; index < transports.length; index++) {
      if (index < tickets.length) {
        try {
          await OnlineQuickPopService(transports[index]).cancel(tickets[index]);
        } catch (_) {}
      }
    }
    for (final store in stores) {
      await store.shutdown();
    }
  }
}

final class _AuthIdentity {
  const _AuthIdentity(this.uid, this.token);

  final String uid;
  final String token;
}

Future<_AuthIdentity> _anonymousAuth() async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp'
        '?key=AIzaSyBH5CwUvJU85a23cK68liMVhQDG9cVFM8Q',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{'returnSecureToken': true}));
    final response = await request.close();
    final body = jsonDecode(await utf8.decoder.bind(response).join());
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body is! Map) {
      throw StateError('Anonymous Auth failed (${response.statusCode}): $body');
    }
    final uid = body['localId'];
    final token = body['idToken'];
    if (uid is! String || token is! String) {
      throw StateError('Anonymous Auth returned no uid/token.');
    }
    return _AuthIdentity(uid, token);
  } finally {
    client.close(force: true);
  }
}
