import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/player_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'current release offers only the working local email method',
    () {
      for (final platform in PlayerAuthPlatform.values) {
        expect(PlayerAuthPolicy.methodsFor(platform), {
          PlayerAuthMethod.emailPassword,
        });
        expect(
          PlayerAuthPolicy.allows(platform, PlayerAuthMethod.google),
          isFalse,
        );
        expect(
          PlayerAuthPolicy.allows(platform, PlayerAuthMethod.apple),
          isFalse,
        );
      }
    },
  );

  test('email and password validation catches weak credentials', () {
    expect(PlayerCredentialValidator.isValidEmail('juan@example.com'), isTrue);
    expect(PlayerCredentialValidator.isValidEmail('not-an-email'), isFalse);

    expect(
      PlayerCredentialValidator.validatePassword(
        'weak',
        confirmation: 'different',
      ),
      containsAll({
        CredentialIssue.passwordTooShort,
        CredentialIssue.passwordNeedsUppercase,
        CredentialIssue.passwordNeedsNumber,
        CredentialIssue.passwordsDoNotMatch,
      }),
    );
    expect(
      PlayerCredentialValidator.validatePassword(
        'Parchese9',
        confirmation: 'Parchese9',
      ),
      isEmpty,
    );
  });

  test(
    'local email account never stores the raw password and can change it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = await LocalPlayerAuthGateway.create();

      final account = await gateway.registerWithEmail(
        email: 'Juan@Example.com',
        password: 'Parchese9',
      );
      expect(account.email, 'juan@example.com');
      expect(gateway.currentAccount, isNotNull);

      final store = await SharedPreferences.getInstance();
      expect(store.getKeys(), isNotEmpty);
      expect(
        store.getKeys().map(store.get).whereType<String>(),
        isNot(contains('Parchese9')),
      );

      await gateway.changePassword(
        currentPassword: 'Parchese9',
        newPassword: 'Parchese10',
      );
      await gateway.signOut();
      expect(
        gateway.signInWithEmail(
          email: 'juan@example.com',
          password: 'Parchese9',
        ),
        throwsA(isA<PlayerAuthException>()),
      );
      expect(
        await gateway.signInWithEmail(
          email: 'juan@example.com',
          password: 'Parchese10',
        ),
        isA<AuthenticatedPlayerAccount>(),
      );
      await gateway.dispose();
    },
  );
}
