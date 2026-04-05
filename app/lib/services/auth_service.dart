import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:html' as html show window;
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
  bool _loading = true; // Start true — gate UI until init() completes
  String? _pendingResumeConversationId;

  UserProfile? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isLoggedIn => _user != null;
  bool get loading => _loading;

  /// Conversation ID to resume after returning from Google auth redirect
  String? get pendingResumeConversationId => _pendingResumeConversationId;

  void clearPendingResume() {
    _pendingResumeConversationId = null;
    if (kIsWeb) {
      html.window.localStorage.remove('beriwo_pending_convo');
    }
  }

  Future<void> init() async {
    if (kIsWeb) {
      // On web, onLoad() handles returning users after redirect
      try {
        final creds = await _auth0Web!.onLoad(
          audience: auth0Audience.isNotEmpty ? auth0Audience : null,
          scopes: {'openid', 'profile', 'email', 'offline_access'},
          useRefreshTokens: true,
          cacheLocation: CacheLocation.localStorage,
        );
        if (creds != null) {
          _user = creds.user;
          _accessToken = creds.accessToken;
          _refreshToken = creds.refreshToken;

          // Auth0 SPA JS SDK stores the refresh token in its internal
          // localStorage cache but doesn't expose it via Credentials.
          // Extract it directly so Token Vault can use it.
          _refreshToken ??= _extractRefreshTokenFromCache();

          debugPrint(
            'Auth0 web login: accessToken=${_accessToken != null}, refreshToken=${_refreshToken != null}',
          );
          if (_refreshToken == null) {
            debugPrint(
              'WARNING: No refresh token available. Enable Refresh Token Rotation '
              'in Auth0 Application Settings and "Allow Offline Access" in your Auth0 API.',
            );
          }
        }

        // Check if returning from Google auth redirect
        final pendingConvo = html.window.localStorage['beriwo_pending_convo'];
        if (pendingConvo != null && pendingConvo.isNotEmpty && _user != null) {
          _pendingResumeConversationId = pendingConvo;
          debugPrint(
            'Returning from Google auth, pending convo: $pendingConvo',
          );
        } else if (pendingConvo != null) {
          // Auth failed or user is null — clean up stale key
          html.window.localStorage.remove('beriwo_pending_convo');
          debugPrint('Cleaned up stale pending convo (user not logged in)');
        }
      } catch (e) {
        debugPrint('Auth0 web onLoad error: $e');
        // Clean up stale pending convo on failure
        html.window.localStorage.remove('beriwo_pending_convo');
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
    _loading = false;
    notifyListeners();
  }

  Future<void> login() async {
    _loading = true;
    notifyListeners();

    try {
      if (kIsWeb) {
        await _auth0Web!.loginWithRedirect(
          redirectUrl: Uri.base.origin,
          audience: auth0Audience.isNotEmpty ? auth0Audience : null,
          scopes: {'openid', 'profile', 'email', 'offline_access'},
          parameters: {
            'connection': 'google-oauth2',
            'connection_scope':
                'openid '
                'https://www.googleapis.com/auth/gmail.readonly '
                'https://www.googleapis.com/auth/gmail.send '
                'https://www.googleapis.com/auth/calendar.readonly '
                'https://www.googleapis.com/auth/calendar.events '
                'https://www.googleapis.com/auth/drive.readonly',
            'access_type': 'offline',
            'prompt': 'consent',
          },
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

  /// Connect Google account via popup (no page redirect).
  /// Returns true if authorization succeeded.
  Future<bool> connectGoogle(String conversationId) async {
    if (!kIsWeb) return false;

    try {
      final creds = await _auth0Web!.loginWithPopup(
        audience: auth0Audience.isNotEmpty ? auth0Audience : null,
        scopes: {'openid', 'profile', 'email', 'offline_access'},
        parameters: {
          'connection': 'google-oauth2',
          'connection_scope':
              'openid '
              'https://www.googleapis.com/auth/gmail.readonly '
              'https://www.googleapis.com/auth/gmail.send '
              'https://www.googleapis.com/auth/calendar.readonly '
              'https://www.googleapis.com/auth/calendar.events '
              'https://www.googleapis.com/auth/drive.readonly',
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

      _user = creds.user;
      _accessToken = creds.accessToken;
      // After popup, the SDK's cache is updated. Extract the fresh refresh
      // token which now includes the Google connection grant.
      _refreshToken = creds.refreshToken;
      _refreshToken ??= _extractRefreshTokenFromCache();

      if (_refreshToken == null) {
        debugPrint(
          'WARNING: connectGoogle popup succeeded but no refresh token found. '
          'Token Vault will not be able to resolve Google tokens.',
        );
      }

      // Remember that Google is connected for this session
      html.window.localStorage['beriwo_google_connected'] = 'true';

      debugPrint(
        'Google connected via popup: accessToken=${_accessToken != null}, '
        'refreshToken=${_refreshToken != null}',
      );

      notifyListeners();
      return _refreshToken != null;
    } catch (e) {
      debugPrint('Google connect popup error: $e');
      return false;
    }
  }

  /// Step-up authentication: force a fresh login via popup so that
  /// the resulting JWT has a recent auth_time claim.  Used before
  /// high-risk write operations (send email, delete events).
  Future<bool> stepUpAuth() async {
    if (!kIsWeb) return false;

    try {
      final creds = await _auth0Web!.loginWithPopup(
        audience: auth0Audience.isNotEmpty ? auth0Audience : null,
        scopes: {'openid', 'profile', 'email', 'offline_access'},
        parameters: {
          'connection': 'google-oauth2',
          'max_age': '0', // Forces re-authentication
          'connection_scope':
              'openid '
              'https://www.googleapis.com/auth/gmail.readonly '
              'https://www.googleapis.com/auth/gmail.send '
              'https://www.googleapis.com/auth/calendar.readonly '
              'https://www.googleapis.com/auth/calendar.events '
              'https://www.googleapis.com/auth/drive.readonly',
        },
      );

      _user = creds.user;
      _accessToken = creds.accessToken;
      _refreshToken = creds.refreshToken;
      _refreshToken ??= _extractRefreshTokenFromCache();

      debugPrint('Step-up auth complete: accessToken=${_accessToken != null}');
      notifyListeners();
      return _accessToken != null;
    } catch (e) {
      debugPrint('Step-up auth error: $e');
      return false;
    }
  }

  /// Whether the user has previously connected their Google account
  /// in this browser session.
  bool get isGoogleConnected =>
      kIsWeb && html.window.localStorage['beriwo_google_connected'] == 'true';

  /// Extract the refresh token from Auth0 SPA JS SDK's localStorage cache.
  /// The SDK stores tokens under keys starting with '@@auth0spajs@@'.
  /// Also checks for a second pattern '@@auth0spajs@@::' used in some SDK versions.
  String? _extractRefreshTokenFromCache() {
    if (!kIsWeb) return null;
    try {
      final storage = html.window.localStorage;
      String? bestToken;
      for (final key in storage.keys) {
        if (!key.startsWith('@@auth0spajs@@')) continue;
        final raw = storage[key];
        if (raw == null) continue;
        try {
          final data = jsonDecode(raw);
          // Direct body.refresh_token
          final rt = data['body']?['refresh_token'];
          if (rt is String && rt.isNotEmpty) {
            bestToken = rt;
            debugPrint(
              'Found refresh token in cache key: ${key.substring(0, 30)}... '
              'token: ${rt.substring(0, 8)}...',
            );
          }
        } catch (_) {
          // Some cache entries might not be valid JSON
        }
      }
      if (bestToken != null) {
        debugPrint('Using refresh token from Auth0 SPA cache');
      } else {
        debugPrint(
          'WARNING: No refresh token found in any Auth0 SPA cache entry',
        );
        // Log all auth0 keys for debugging
        final authKeys = storage.keys
            .where((k) => k.startsWith('@@auth0'))
            .toList();
        debugPrint('Auth0 cache keys: $authKeys');
      }
      return bestToken;
    } catch (e) {
      debugPrint('Could not extract refresh token from cache: $e');
    }
    return null;
  }

  Future<void> logout() async {
    _loading = true;
    notifyListeners();

    // Clear Google connection flag
    if (kIsWeb) {
      html.window.localStorage.remove('beriwo_google_connected');
      html.window.localStorage.remove('beriwo_pending_convo');
      html.window.localStorage.remove('beriwo_pending_message');
    }

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
