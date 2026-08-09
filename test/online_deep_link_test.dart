import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_deep_link.dart';
import 'package:parchesepop/online_invite.dart';

void main() {
  group('OnlineDeepLinkService', () {
    test(
      'emits the initial invite once before queued incoming links',
      () async {
        final initial = Completer<Uri?>();
        final gateway = _FakeAppLinksGateway(initialLink: initial.future);
        final service = OnlineDeepLinkService(gateway: gateway);
        final emittedCodes = <String>[];
        final subscription = service.roomInvites.listen(
          (invite) => emittedCodes.add(invite.roomCode.value),
        );
        addTearDown(() async {
          await subscription.cancel();
          await service.dispose();
          await gateway.close();
        });

        final firstStart = service.start();
        final secondStart = service.start();
        gateway.add(Uri.parse('parchesepop://room/XYZ789'));
        initial.complete(Uri.parse('https://parchese-pop.web.app/join/ABC234'));
        await Future.wait(<Future<void>>[firstStart, secondStart]);

        expect(gateway.initialLinkRequests, 1);
        expect(gateway.streamListenCount, 1);
        expect(emittedCodes, <String>['ABC234', 'XYZ789']);
      },
    );

    test(
      'ignores invalid links and duplicates by normalized room code',
      () async {
        final gateway = _FakeAppLinksGateway(
          initialLink: Future<Uri?>.value(
            Uri.parse('parchesepop://room/abc234'),
          ),
        );
        final service = OnlineDeepLinkService(gateway: gateway);
        final emitted = <RoomInvite>[];
        final subscription = service.roomInvites.listen(emitted.add);
        addTearDown(() async {
          await subscription.cancel();
          await service.dispose();
          await gateway.close();
        });

        await service.start();
        gateway
          ..add(Uri.parse('https://parchese-pop.web.app/join/ABC234'))
          ..add(Uri.parse('https://example.com/join/DEF567'))
          ..add(Uri.parse('parchesepop://room/ABCI23'))
          ..add(Uri.parse('parchesepop://room/DEF567'))
          ..add(Uri.parse('parchesepop://room/def567'));
        await Future<void>.delayed(Duration.zero);

        expect(emitted.map((invite) => invite.roomCode.value), <String>[
          'ABC234',
          'DEF567',
        ]);
      },
    );

    test(
      'dispose cancels incoming links and closes the output stream',
      () async {
        final gateway = _FakeAppLinksGateway(
          initialLink: Future<Uri?>.value(null),
        );
        final service = OnlineDeepLinkService(gateway: gateway);
        final emittedCodes = <String>[];
        var outputClosed = false;
        final subscription = service.roomInvites.listen(
          (invite) => emittedCodes.add(invite.roomCode.value),
          onDone: () => outputClosed = true,
        );

        await service.start();
        gateway.add(Uri.parse('parchesepop://room/ABC234'));
        expect(emittedCodes, <String>['ABC234']);

        await service.dispose();
        gateway.add(Uri.parse('parchesepop://room/DEF567'));
        await Future<void>.delayed(Duration.zero);

        expect(service.disposed, isTrue);
        expect(gateway.streamCancelCount, 1);
        expect(outputClosed, isTrue);
        expect(emittedCodes, <String>['ABC234']);
        await subscription.cancel();
        await gateway.close();
      },
    );

    test(
      'the same room link may be opened again after the debounce window',
      () async {
        var now = DateTime.utc(2026, 8, 9, 12);
        final gateway = _FakeAppLinksGateway(
          initialLink: Future<Uri?>.value(null),
        );
        final service = OnlineDeepLinkService(gateway: gateway, now: () => now);
        final emittedCodes = <String>[];
        final subscription = service.roomInvites.listen(
          (invite) => emittedCodes.add(invite.roomCode.value),
        );
        addTearDown(() async {
          await subscription.cancel();
          await service.dispose();
          await gateway.close();
        });

        await service.start();
        gateway
          ..add(Uri.parse('parchesepop://room/ABC234'))
          ..add(Uri.parse('parchesepop://room/ABC234'));
        now = now.add(const Duration(seconds: 3));
        gateway.add(Uri.parse('parchesepop://room/ABC234'));

        expect(emittedCodes, <String>['ABC234', 'ABC234']);
      },
    );

    test(
      'dispose while initial lookup is pending suppresses late results',
      () async {
        final initial = Completer<Uri?>();
        final gateway = _FakeAppLinksGateway(initialLink: initial.future);
        final service = OnlineDeepLinkService(gateway: gateway);
        final emitted = <RoomInvite>[];
        final subscription = service.roomInvites.listen(emitted.add);

        final starting = service.start();
        gateway.add(Uri.parse('parchesepop://room/DEF567'));
        await service.dispose();
        initial.complete(Uri.parse('parchesepop://room/ABC234'));
        await starting;

        expect(emitted, isEmpty);
        expect(gateway.streamCancelCount, 1);
        await subscription.cancel();
        await gateway.close();
      },
    );
  });
}

final class _FakeAppLinksGateway implements OnlineAppLinksGateway {
  _FakeAppLinksGateway({required this.initialLink});

  final Future<Uri?> initialLink;
  late final StreamController<Uri> _incoming = StreamController<Uri>.broadcast(
    sync: true,
    onListen: () => streamListenCount++,
    onCancel: () => streamCancelCount++,
  );
  int initialLinkRequests = 0;
  int streamListenCount = 0;
  int streamCancelCount = 0;

  @override
  Future<Uri?> getInitialLink() {
    initialLinkRequests++;
    return initialLink;
  }

  @override
  Stream<Uri> get uriLinkStream => _incoming.stream;

  void add(Uri uri) => _incoming.add(uri);

  Future<void> close() => _incoming.close();
}
