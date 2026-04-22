import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';

void main() {
  group('AppUser', () {
    test('stores all fields correctly for a Google user', () {
      const user = AppUser(
        id: 'google-id-123',
        displayName: 'Alice',
        email: 'alice@gmail.com',
        type: AuthType.google,
      );
      expect(user.id, 'google-id-123');
      expect(user.displayName, 'Alice');
      expect(user.email, 'alice@gmail.com');
      expect(user.type, AuthType.google);
    });

    test('stores all fields correctly for a local user', () {
      const user = AppUser(
        id: 'alice',
        displayName: 'alice',
        type: AuthType.local,
      );
      expect(user.id, 'alice');
      expect(user.displayName, 'alice');
      expect(user.email, isNull);
      expect(user.type, AuthType.local);
    });

    test('email defaults to null when not provided', () {
      const user = AppUser(
        id: 'x',
        displayName: 'x',
        type: AuthType.local,
      );
      expect(user.email, isNull);
    });
  });

  group('AuthType', () {
    test('has google and local values', () {
      expect(AuthType.values, containsAll([AuthType.google, AuthType.local]));
    });

    test('google and local are distinct', () {
      expect(AuthType.google, isNot(AuthType.local));
    });
  });
}
