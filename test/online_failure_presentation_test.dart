import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/main.dart';
import 'package:parchesepop/online_transport.dart';

void main() {
  test('Firebase diagnostics never expose raw paths or identifiers', () {
    final presentation = describeQuickPopOnlineFailure(
      FirebaseException(
        plugin: 'firebase_database',
        code: 'permission-denied',
        message: 'sensitive /onlineV2/users/private-uid',
      ),
    );

    expect(presentation.diagnosticCode, 'firebase_database/permission-denied');
    expect(presentation.userMessage, contains('no autorizó'));
    expect(presentation.userMessage, isNot(contains('private-uid')));
    expect(presentation.diagnosticCode, isNot(contains('private-uid')));
  });

  test('unknown errors receive a safe generic message', () {
    final presentation = describeQuickPopOnlineFailure(
      StateError('secret/room/member'),
    );

    expect(presentation.diagnosticCode, 'unexpected/StateError');
    expect(presentation.userMessage, isNot(contains('secret')));
    expect(presentation.userMessage, contains('Inténtalo otra vez'));
  });

  test('expired queue gets a specific retry message without raw details', () {
    final presentation = describeQuickPopOnlineFailure(
      const OnlineTransportException(
        OnlineTransportErrorCode.invalidQueueTicket,
        'private ticket detail',
      ),
    );

    expect(presentation.diagnosticCode, 'transport/invalidQueueTicket');
    expect(
      presentation.userMessage,
      'La búsqueda online expiró. Inténtalo otra vez.',
    );
    expect(presentation.userMessage, isNot(contains('private')));
  });
}
