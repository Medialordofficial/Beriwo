import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class AuthService extends ChangeNotifier {
  // Web uses Auth0Web; mobile uses Auth0
  final Auth0Web? _auth0Web = kIsWeb
      ? Auth0Web(auth0Domain, auth0ClientId)
      : null;
  final Auth0? _auth0 = kIsWeb ? null : Auth0(auth0Domain, auth0ClientId);
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
    if (kIsWeb) {
      // On web, onLoad() handles returning users after redirect
      try {
        final creds = await _auth0Web!.onLoad(
          scopes: {'openid', 'profile', 'email', 'offline_access'},
          useRefreshTokens: true,
          cacheLocation: CacheLocation.localStorage,
        );
        if (creds != null) {
          _user = creds.user;
          _accessToken = creds.accessToken;
          _refreshToken = creds.refreshToken;
        }
      } catch (e) {
        debugPrint('Auth0 web onLoad error: $e');
      }
    } else {
      // Mobile: try to renew from stored refresh token
      _refreshToken = await _storage.read(key: 'refresh_token');
      if (_refreshToken != null) {
        try {
          final credentials = await _auth0!.api.renewCredentials(
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
    }
    notifyListeners();
  }

  Future<void> login() async {
    _loading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        await _auth0Web!.loginWithRedirect(
          redirectUrl: Uri.base.origin,
          scopes: {'openid', 'profile', 'email', 'offline_access'},
        );
        // Page will redirect — won't reach here
        return;
      }

      // Mobile
      final credentials = await _auth0!.webAuthentication().login(
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
      if (kIsWeb) {
        await _auth0Web!.logout(returnToUrl: Uri.base.origin);
        return;
      }
      await _auth0!.webAuthentication().logout();
    } catch (_) {}

    _user = null;
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'refresh_token');

    _loading = false;
    notifyListeners();
  }
}
