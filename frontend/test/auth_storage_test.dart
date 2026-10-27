import 'package:atahad/core/api/api_client.dart';
import 'package:atahad/core/auth/auth_state.dart';
import 'package:atahad/core/theme/theme_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logout clears account data but preserves the walking installation', () async {
    FlutterSecureStorage.setMockInitialValues({
      'walking_installation': 'existing-phone-installation',
      ThemeState.storageKey: 'dark',
      'email': 'test@example.com',
      'password': 'test-password',
      'group_activity_test': 'account-specific-state',
    });
    const storage = FlutterSecureStorage();
    final auth = AuthState(ApiClient());
    addTearDown(auth.dispose);
    auth.role = Role.member;
    auth.profile = {'id': 1};
    auth.isLocked = true;

    await auth.logout(callServer: false);
    expect(auth.isLoggedIn, isFalse);
    expect(auth.profile, isNull);
    expect(auth.isLocked, isFalse);
    expect(await storage.readAll(), {
      'walking_installation': 'existing-phone-installation',
      ThemeState.storageKey: 'dark',
    });

    await auth.logout(callServer: false);
    expect(await storage.read(key: 'walking_installation'),
        'existing-phone-installation');
  });
}