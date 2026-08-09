import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/online_invite.dart';
import 'package:parchesepop/online_lobby.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  final invite = RoomInvite(RoomCode.parse('ABC234'));

  group('RoomInvite links', () {
    test('builds the custom URI and HTTPS fallback exactly', () {
      expect(invite.customUri.toString(), 'parchesepop://room/ABC234');
      expect(
        invite.httpsUri.toString(),
        'https://parchese-pop.web.app/join/ABC234',
      );
    });

    test('share text contains the room code and safe HTTPS fallback', () {
      expect(invite.shareSubject, 'Invitación a Parchís Pop');
      expect(invite.shareText, contains('Código: ABC234'));
      expect(
        invite.shareText,
        contains('https://parchese-pop.web.app/join/ABC234'),
      );
      expect(invite.shareText, isNot(contains(invite.customUri.toString())));
    });

    test('parses custom and HTTPS room links with normalized codes', () {
      expect(
        RoomInvite.parse(Uri.parse('parchesepop://room/abc234')).roomCode.value,
        'ABC234',
      );
      expect(
        RoomInvite.parse(
          Uri.parse('https://parchese-pop.web.app/join/abc234'),
        ).roomCode.value,
        'ABC234',
      );
      expect(
        RoomInvite.tryParseText(
          ' https://parchese-pop.web.app/join/ABC234 ',
        )?.roomCode.value,
        'ABC234',
      );
    });

    test('rejects another scheme, host, path, or ambiguous code', () {
      for (final rawUri in [
        'http://parchese-pop.web.app/join/ABC234',
        'https://example.com/join/ABC234',
        'https://parchese-pop.web.app/room/ABC234',
        'https://parchese-pop.web.app/join/ABC234/extra',
        'parchesepop://other/ABC234',
        'parchesepop://room/ABCI23',
      ]) {
        expect(RoomInvite.tryParse(Uri.parse(rawUri)), isNull, reason: rawUri);
      }
      expect(
        () => RoomInvite.parse(Uri.parse('parchesepop://room/ABCO23')),
        throwsA(isA<RoomInviteFormatException>()),
      );
    });
  });

  test(
    'share service delegates only to the native system share sheet',
    () async {
      ShareParams? captured;
      const expected = ShareResult('test-share', ShareResultStatus.success);
      final service = RoomInviteShareService(
        nativeShare: (params) async {
          captured = params;
          return expected;
        },
      );
      const origin = Rect.fromLTWH(8, 12, 44, 52);

      final result = await service.share(invite, sharePositionOrigin: origin);

      expect(result, expected);
      expect(captured?.title, invite.shareSubject);
      expect(captured?.subject, invite.shareSubject);
      expect(captured?.text, invite.shareText);
      expect(captured?.sharePositionOrigin, origin);
      expect(captured?.uri, isNull);
      expect(captured?.files, isNull);
    },
  );
}
