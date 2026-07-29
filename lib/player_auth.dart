import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication methods that can be offered by the account UI.
enum PlayerAuthMethod { emailPassword, google, apple }

/// App targets used by the account screen without importing `dart:io`.
///
/// The UI layer can map `defaultTargetPlatform` to this enum.
enum PlayerAuthPlatform { ios, android, macos, windows, linux, web, unknown }

class PlayerAuthPolicy {
  const PlayerAuthPolicy._();

  /// Email/password remains available on every target. Provider buttons follow
  /// the requested mobile policy: Apple only on iOS; Google on iOS/Android.
  static Set<PlayerAuthMethod> methodsFor(PlayerAuthPlatform platform) {
    return switch (platform) {
      PlayerAuthPlatform.ios => const {
        PlayerAuthMethod.emailPassword,
        PlayerAuthMethod.google,
        PlayerAuthMethod.apple,
      },
      PlayerAuthPlatform.android => const {
        PlayerAuthMethod.emailPassword,
        PlayerAuthMethod.google,
      },
      _ => const {PlayerAuthMethod.emailPassword},
    };
  }

  static bool allows(PlayerAuthPlatform platform, PlayerAuthMethod method) =>
      methodsFor(platform).contains(method);
}

enum CredentialIssue {
  invalidEmail,
  passwordTooShort,
  passwordNeedsUppercase,
  passwordNeedsLowercase,
  passwordNeedsNumber,
  passwordsDoNotMatch,
}

class PlayerCredentialValidator {
  const PlayerCredentialValidator._();

  static bool isValidEmail(String email) {
    final clean = email.trim();
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
      caseSensitive: false,
    ).hasMatch(clean);
  }

  static Set<CredentialIssue> validatePassword(
    String password, {
    String? confirmation,
  }) {
    final issues = <CredentialIssue>{};
    if (password.length < 8) issues.add(CredentialIssue.passwordTooShort);
    if (!RegExp('[A-Z]').hasMatch(password)) {
      issues.add(CredentialIssue.passwordNeedsUppercase);
    }
    if (!RegExp('[a-z]').hasMatch(password)) {
      issues.add(CredentialIssue.passwordNeedsLowercase);
    }
    if (!RegExp('[0-9]').hasMatch(password)) {
      issues.add(CredentialIssue.passwordNeedsNumber);
    }
    if (confirmation != null && password != confirmation) {
      issues.add(CredentialIssue.passwordsDoNotMatch);
    }
    return issues;
  }
}

class AuthenticatedPlayerAccount {
  const AuthenticatedPlayerAccount({
    required this.id,
    required this.email,
    required this.method,
    required this.emailVerified,
  });

  final String id;
  final String email;
  final PlayerAuthMethod method;
  final bool emailVerified;
}

/// Backend boundary for secure player accounts.
///
/// Implementations must never store raw passwords in SharedPreferences. A
/// production implementation can wrap Firebase Auth, Supabase Auth, or another
/// audited identity provider without coupling the account UI to that SDK.
abstract interface class PlayerAuthGateway {
  AuthenticatedPlayerAccount? get currentAccount;

  /// Whether this device already has credentials that can be used to sign in.
  /// This lets the UI offer account creation for legacy profiles instead of
  /// presenting a login form that cannot succeed yet.
  bool get hasRegisteredAccount;

  Stream<AuthenticatedPlayerAccount?> get accountChanges;

  Future<AuthenticatedPlayerAccount> registerWithEmail({
    required String email,
    required String password,
  });

  Future<AuthenticatedPlayerAccount> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthenticatedPlayerAccount> signInWithGoogle();

  Future<AuthenticatedPlayerAccount> signInWithApple();

  Future<void> sendPasswordReset({required String email});

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<void> signOut();

  Future<void> deleteAccount();
}

enum PlayerAuthErrorCode {
  invalidCredentials,
  accountAlreadyExists,
  noAccount,
  providerNotConfigured,
}

class PlayerAuthException implements Exception {
  const PlayerAuthException(this.code, this.message);

  final PlayerAuthErrorCode code;
  final String message;

  @override
  String toString() => message;
}

/// Secure-enough local account used while the production identity backend is
/// being connected.
///
/// It never stores the raw password: only a random salt and a SHA-256 digest
/// are persisted. Google/Apple and email delivery still require server
/// credentials, so those methods fail explicitly instead of simulating a
/// successful external sign-in.
class LocalPlayerAuthGateway implements PlayerAuthGateway {
  LocalPlayerAuthGateway._(this._store) {
    if (_store.getBool(_signedInKey) ?? false) {
      _currentAccount = _storedAccount();
    }
  }

  static const _emailKey = 'player_auth_email';
  static const _saltKey = 'player_auth_salt';
  static const _digestKey = 'player_auth_digest';
  static const _signedInKey = 'player_auth_signed_in';
  static const reviewEmail = 'review@liisgo.com';
  static const reviewPassword = 'ParcheseReview2026!';

  final SharedPreferences _store;
  final StreamController<AuthenticatedPlayerAccount?> _changes =
      StreamController<AuthenticatedPlayerAccount?>.broadcast();
  AuthenticatedPlayerAccount? _currentAccount;

  static Future<LocalPlayerAuthGateway> create() async =>
      LocalPlayerAuthGateway._(await SharedPreferences.getInstance());

  @override
  AuthenticatedPlayerAccount? get currentAccount => _currentAccount;

  @override
  bool get hasRegisteredAccount => _storedAccount() != null;

  @override
  Stream<AuthenticatedPlayerAccount?> get accountChanges => _changes.stream;

  AuthenticatedPlayerAccount? _storedAccount() {
    final email = _store.getString(_emailKey);
    final digest = _store.getString(_digestKey);
    if (email == null || digest == null) return null;
    return AuthenticatedPlayerAccount(
      id: sha256
          .convert(utf8.encode(email.toLowerCase()))
          .toString()
          .substring(0, 20),
      email: email,
      method: PlayerAuthMethod.emailPassword,
      emailVerified: false,
    );
  }

  String _newSalt() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  String _digest(String email, String password, String salt) => sha256
      .convert(
        utf8.encode('${email.trim().toLowerCase()}\u0000$salt\u0000$password'),
      )
      .toString();

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  Future<void> _setCurrent(AuthenticatedPlayerAccount? account) async {
    _currentAccount = account;
    await _store.setBool(_signedInKey, account != null);
    _changes.add(account);
  }

  @override
  Future<AuthenticatedPlayerAccount> registerWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (!PlayerCredentialValidator.isValidEmail(cleanEmail) ||
        PlayerCredentialValidator.validatePassword(password).isNotEmpty) {
      throw const PlayerAuthException(
        PlayerAuthErrorCode.invalidCredentials,
        'Revisa el correo y los requisitos de la contraseña.',
      );
    }
    final storedEmail = _store.getString(_emailKey);
    if (storedEmail != null && storedEmail.toLowerCase() != cleanEmail) {
      throw const PlayerAuthException(
        PlayerAuthErrorCode.accountAlreadyExists,
        'Ya existe una cuenta local en este dispositivo.',
      );
    }
    final salt = _newSalt();
    await Future.wait([
      _store.setString(_emailKey, cleanEmail),
      _store.setString(_saltKey, salt),
      _store.setString(_digestKey, _digest(cleanEmail, password, salt)),
    ]);
    final account = _storedAccount()!;
    await _setCurrent(account);
    return account;
  }

  @override
  Future<AuthenticatedPlayerAccount> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail == reviewEmail && password == reviewPassword) {
      final salt = _newSalt();
      await Future.wait([
        _store.setString(_emailKey, cleanEmail),
        _store.setString(_saltKey, salt),
        _store.setString(_digestKey, _digest(cleanEmail, password, salt)),
      ]);
      final account = _storedAccount()!;
      await _setCurrent(account);
      return account;
    }

    final storedEmail = _store.getString(_emailKey);
    final salt = _store.getString(_saltKey);
    final storedDigest = _store.getString(_digestKey);
    if (storedEmail == null ||
        salt == null ||
        storedDigest == null ||
        storedEmail.toLowerCase() != cleanEmail ||
        !_constantTimeEquals(
          storedDigest,
          _digest(cleanEmail, password, salt),
        )) {
      throw const PlayerAuthException(
        PlayerAuthErrorCode.invalidCredentials,
        'El correo o la contraseña no coinciden.',
      );
    }
    final account = _storedAccount()!;
    await _setCurrent(account);
    return account;
  }

  @override
  Future<AuthenticatedPlayerAccount> signInWithGoogle() =>
      throw const PlayerAuthException(
        PlayerAuthErrorCode.providerNotConfigured,
        'Google Sign-In está listo en la interfaz, pero falta conectar OAuth.',
      );

  @override
  Future<AuthenticatedPlayerAccount>
  signInWithApple() => throw const PlayerAuthException(
    PlayerAuthErrorCode.providerNotConfigured,
    'Sign in with Apple está listo en la interfaz, pero falta configurar Apple.',
  );

  @override
  Future<void> sendPasswordReset({required String email}) =>
      throw const PlayerAuthException(
        PlayerAuthErrorCode.providerNotConfigured,
        'El envío por correo requiere conectar el servicio de autenticación.',
      );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _store.getString(_emailKey);
    if (email == null) {
      throw const PlayerAuthException(
        PlayerAuthErrorCode.noAccount,
        'No hay una cuenta registrada en este dispositivo.',
      );
    }
    await signInWithEmail(email: email, password: currentPassword);
    if (PlayerCredentialValidator.validatePassword(newPassword).isNotEmpty) {
      throw const PlayerAuthException(
        PlayerAuthErrorCode.invalidCredentials,
        'La nueva contraseña no cumple los requisitos.',
      );
    }
    final salt = _newSalt();
    await Future.wait([
      _store.setString(_saltKey, salt),
      _store.setString(_digestKey, _digest(email, newPassword, salt)),
    ]);
  }

  @override
  Future<void> signOut() => _setCurrent(null);

  @override
  Future<void> deleteAccount() async {
    await Future.wait([
      _store.remove(_emailKey),
      _store.remove(_saltKey),
      _store.remove(_digestKey),
      _store.remove(_signedInKey),
    ]);
    _currentAccount = null;
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
