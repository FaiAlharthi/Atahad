import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../theme/theme_state.dart';

enum Role { member, admin }

// who is logged in. The backend uses Basic Auth, so the email and password are kept (encrypted)
// and sent with every request. In a widget: context.watch<AuthState>().profile?['name']
class AuthState extends ChangeNotifier {
  final ApiClient api;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Role? role;
  Map<String, dynamic>? profile; // MemberResponse or AdminResponse
  bool isLocked = false; // unpaid penalties: the app shows the lock screen

  AuthState(this.api) {
    api.onUnauthorized = () {
      if (isLoggedIn) logout(callServer: false);
    };
    api.onForbidden = (_) => refreshLock();
  }

  bool get isLoggedIn => role != null;
  bool get isMember => role == Role.member;
  bool get isAdmin => role == Role.admin;
  int? get userId => profile?['id'] as int?; // memberId or adminId (the same as the user id)

  // on app start: log in again with the saved email and password
  Future<void> restore() async {
    try {
      final email = await _storage.read(key: 'email');
      final password = await _storage.read(key: 'password');
      if (email == null || password == null) return;
      await _signIn(email, password);
    } catch (_) {
      await _clear();
    }
  }

  Future<void> login(String email, String password) async {
    await _signIn(email.trim().toLowerCase(), password);
    await _storage.write(key: 'email', value: email.trim().toLowerCase());
    await _storage.write(key: 'password', value: password);
    notifyListeners();
  }

  Future<void> register({required String name, required String email, required String phone, required String password}) async {
    await api.post('/api/v1/member/register', auth: false, body: {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'password': password,
    });
    await login(email, password);
  }

  Future<void> logout({bool callServer = true}) async {
    if (callServer) {
      try {
        await api.post('/api/v1/user/auth/logout');
      } catch (_) {}
    }
    await _clear();
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (!isLoggedIn) return;
    final path = isMember ? '/api/v1/member/profile' : '/api/v1/admin/profile';
    profile = Map<String, dynamic>.from(await api.get(path) as Map);
    if (isMember) isLocked = profile!['isLocked'] == true;
    notifyListeners();
  }

  // called after any 403 and after a donation or an excuse
  Future<void> refreshLock() async {
    if (!isMember) return;
    try {
      final status = await api.get('/api/v1/commitment/lockStatus') as Map;
      final locked = status['isLocked'] == true;
      if (locked != isLocked) {
        isLocked = locked;
        notifyListeners();
      }
    } catch (_) {}
  }

  // a member first, if the account is not a member (403) it is an admin
  Future<void> _signIn(String email, String password) async {
    api.setCredentials(email, password);
    try {
      profile = Map<String, dynamic>.from(await api.get('/api/v1/member/profile') as Map);
      role = Role.member;
      isLocked = profile!['isLocked'] == true;
    } on ApiException catch (e) {
      if (!e.isForbidden) {
        api.clearCredentials();
        rethrow;
      }
      try {
        profile = Map<String, dynamic>.from(await api.get('/api/v1/admin/profile') as Map);
        role = Role.admin;
        isLocked = false;
      } catch (_) {
        api.clearCredentials();
        rethrow;
      }
    }
  }

  Future<void> _clear() async {
    api.clearCredentials();
    role = null;
    profile = null;
    isLocked = false;
    // Keep installation-wide settings; logout only clears account data.
    final keys = (await _storage.readAll()).keys.where(
      (key) =>
          key != ThemeState.storageKey && key != 'walking_installation',
    ).toList();
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }
}
