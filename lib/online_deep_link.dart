import 'dart:async';

import 'package:app_links/app_links.dart';

import 'online_invite.dart';

/// Small boundary around `app_links`, allowing deep-link behavior to be tested
/// without invoking a platform channel.
abstract interface class OnlineAppLinksGateway {
  Future<Uri?> getInitialLink();

  Stream<Uri> get uriLinkStream;
}

/// Production gateway backed by the singleton provided by `app_links`.
final class PlatformOnlineAppLinksGateway implements OnlineAppLinksGateway {
  PlatformOnlineAppLinksGateway({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;
}

/// Converts initial and foreground app links into validated room invitations.
///
/// Call [start] after attaching a listener to [roomInvites]. The initial link
/// is requested at most once, even if [start] is called concurrently or more
/// than once. Foreground links received while that request is pending are
/// queued so the initial invitation is always considered first.
final class OnlineDeepLinkService {
  OnlineDeepLinkService({
    OnlineAppLinksGateway? gateway,
    DateTime Function()? now,
    this.duplicateWindow = const Duration(seconds: 2),
  }) : _gateway = gateway ?? PlatformOnlineAppLinksGateway(),
       _now = now ?? DateTime.now;

  final OnlineAppLinksGateway _gateway;
  final DateTime Function() _now;
  final Duration duplicateWindow;
  final StreamController<RoomInvite> _roomInvites =
      StreamController<RoomInvite>.broadcast(sync: true);
  final Map<String, DateTime> _emittedRoomCodes = <String, DateTime>{};
  final List<Uri> _queuedIncomingLinks = <Uri>[];

  StreamSubscription<Uri>? _incomingSubscription;
  Future<void>? _startFuture;
  bool _initialLinkResolved = false;
  bool _disposed = false;

  Stream<RoomInvite> get roomInvites => _roomInvites.stream;

  bool get started => _startFuture != null;

  bool get disposed => _disposed;

  Future<void> start() {
    if (_disposed) {
      return Future<void>.error(
        StateError('The online deep-link service is disposed.'),
      );
    }
    return _startFuture ??= _startOnce();
  }

  Future<void> _startOnce() async {
    _incomingSubscription = _gateway.uriLinkStream.listen(
      _acceptIncomingLink,
      onError: (Object error, StackTrace stackTrace) {
        if (!_disposed && !_roomInvites.isClosed) {
          _roomInvites.addError(error, stackTrace);
        }
      },
    );

    try {
      final initialLink = await _gateway.getInitialLink();
      if (!_disposed && initialLink != null) _emitIfValid(initialLink);
    } finally {
      _initialLinkResolved = true;
      if (!_disposed) {
        final pending = List<Uri>.of(_queuedIncomingLinks);
        _queuedIncomingLinks.clear();
        for (final uri in pending) {
          _emitIfValid(uri);
        }
      } else {
        _queuedIncomingLinks.clear();
      }
    }
  }

  void _acceptIncomingLink(Uri uri) {
    if (_disposed) return;
    if (!_initialLinkResolved) {
      _queuedIncomingLinks.add(uri);
      return;
    }
    _emitIfValid(uri);
  }

  void _emitIfValid(Uri uri) {
    if (_disposed || _roomInvites.isClosed) return;
    final invite = RoomInvite.tryParse(uri);
    if (invite == null) return;
    final now = _now();
    final code = invite.roomCode.value;
    final lastEmittedAt = _emittedRoomCodes[code];
    if (lastEmittedAt != null &&
        now.difference(lastEmittedAt).abs() < duplicateWindow) {
      return;
    }
    _emittedRoomCodes.removeWhere(
      (key, emittedAt) => now.difference(emittedAt).abs() >= duplicateWindow,
    );
    _emittedRoomCodes[code] = now;
    _roomInvites.add(invite);
  }

  /// Cancels the native link stream and closes [roomInvites].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queuedIncomingLinks.clear();
    final subscription = _incomingSubscription;
    _incomingSubscription = null;
    await subscription?.cancel();
    await _roomInvites.close();
  }
}
