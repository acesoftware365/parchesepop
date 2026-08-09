import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'online_lobby.dart';

class RoomInviteFormatException implements FormatException {
  const RoomInviteFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => 'RoomInviteFormatException: $message';
}

/// Shareable invitation for one Parchís Pop room.
///
/// [customUri] is registered by the native applications. [httpsUri] is the
/// share-safe fallback; it is not considered a verified Universal/App Link
/// until the web domain publishes the corresponding platform association
/// files.
class RoomInvite {
  const RoomInvite(this.roomCode);

  static const String appScheme = 'parchesepop';
  static const String customRoomHost = 'room';
  static const String fallbackScheme = 'https';
  static const String fallbackHost = 'parchese-pop.web.app';
  static const String fallbackJoinSegment = 'join';

  final RoomCode roomCode;

  Uri get customUri => Uri(
    scheme: appScheme,
    host: customRoomHost,
    pathSegments: [roomCode.value],
  );

  Uri get httpsUri => Uri(
    scheme: fallbackScheme,
    host: fallbackHost,
    pathSegments: [fallbackJoinSegment, roomCode.value],
  );

  String get shareSubject => 'Invitación a Parchís Pop';

  String get shareText =>
      'Únete a mi sala de Parchís Pop.\n'
      'Código: ${roomCode.value}\n'
      '$httpsUri';

  static RoomInvite parse(Uri uri) {
    final code = _roomCodeFromUri(uri);
    if (code == null) {
      throw RoomInviteFormatException(
        'The URI is not a valid Parchís Pop room invitation.',
        uri.toString(),
      );
    }
    return RoomInvite(code);
  }

  static RoomInvite? tryParse(Uri uri) {
    final code = _roomCodeFromUri(uri);
    return code == null ? null : RoomInvite(code);
  }

  static RoomInvite? tryParseText(String rawUri) {
    final uri = Uri.tryParse(rawUri.trim());
    return uri == null ? null : tryParse(uri);
  }

  static RoomCode? _roomCodeFromUri(Uri uri) {
    final pathSegments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    String? rawCode;

    if (uri.scheme.toLowerCase() == appScheme &&
        uri.host.toLowerCase() == customRoomHost &&
        pathSegments.length == 1) {
      rawCode = pathSegments.single;
    } else if (uri.scheme.toLowerCase() == fallbackScheme &&
        uri.host.toLowerCase() == fallbackHost &&
        pathSegments.length == 2 &&
        pathSegments.first.toLowerCase() == fallbackJoinSegment) {
      rawCode = pathSegments.last;
    }

    if (rawCode == null || !RoomCode.isValid(rawCode)) return null;
    return RoomCode.parse(rawCode);
  }
}

typedef NativeInviteShare = Future<ShareResult> Function(ShareParams params);

/// Opens the operating system's share sheet with a room invitation.
///
/// This service never chooses a recipient and never sends a message itself.
/// WhatsApp, Mail, Messages, and other installed destinations are presented by
/// the operating system for the player to select and confirm.
class RoomInviteShareService {
  RoomInviteShareService({NativeInviteShare? nativeShare})
    : _nativeShare = nativeShare ?? SharePlus.instance.share;

  final NativeInviteShare _nativeShare;

  Future<ShareResult> share(RoomInvite invite, {Rect? sharePositionOrigin}) =>
      _nativeShare(
        ShareParams(
          title: invite.shareSubject,
          subject: invite.shareSubject,
          text: invite.shareText,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
}
