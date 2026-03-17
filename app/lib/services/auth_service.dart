import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class AuthService extends ChangeNotifier {
  final Auth0 _auth0 = Auth0(auth0Domain, auth0ClientId);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  UserProfile? _user;
  String? _accessToken;
  String? _refreshToken;
  bool _loading = false;

  UserProfile? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;

  Future<void> init() async {
    _refreshToken = await _storage.read(key: 'refresh_token');
    if (_refreshToken != null) {
      try {
        final credentials = await _auth0.api.renewCredentials(
          refreshToken: _refreshToken!,
        );
        _user = credentials.user;
        _accessToken = credentials.accessToken;
        _refreshToken = credentials.refreshToken ?? _refreshToken;
        await _storage.write(key: 'refresh_token', value: _refreshToken);
      } catch (_) {
        await _storage.delete(key: 'refresh_token');
        _refreshToken = null;
      }
    }
    notifyListeners();
  }

  Future<void> login() async {
    _loading = true;
    notifyListeners();

    try {
      final credentials = await _auth0.webAuthentication().login(
        audience: auth0Audience.isNotEmpty ? auth0Audience : null,
        scopes: {'openid', 'profile', 'email', 'offline_access'},
      );

      _user = credentials.user;
      _accessToken = credentials.accessToken;
      _refreshToken = credentials.refreshToken;

      if (_refreshToken != null) {
        await _storage.write(key: 'refresh_token', value: _refreshToken);
      }
    } catch (e) {
      debugPrint('Login error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _loading = true;
    notifyListeners();

    try {
      await _auth0.webAuthentication().logout();
    } catch (_) {}

    _user = null;
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'refresh_token');

    _loading = false;
    notifyListeners();
  }
}
