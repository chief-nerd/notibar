import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const _tag = '[OutlookAuth]';

class TokenResult {
  final String accessToken;
  final String? refreshToken;
  const TokenResult({required this.accessToken, this.refreshToken});
}

class OutlookAuthService {
  final String clientId;
  final String tenantId;

  static const List<String> _scopes = [
    'openid',
    'profile',
    'offline_access',
    'Mail.Read',
  ];

  OutlookAuthService({required this.clientId, this.tenantId = 'common'});

  /// Starts the OAuth2 Authorization Code flow with PKCE.
  /// Opens the browser for login and listens on a local port for the redirect.
  /// Returns the access token on success, or null on failure/cancellation.
  Future<TokenResult?> login() async {
    debugPrint(
      '$_tag starting login flow (clientId=${clientId.substring(0, 8)}..., tenant=$tenantId)',
    );
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // Use a fixed port so the redirect URI is predictable and matches
    // what's registered in Azure AD.
    const port = 23847;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final redirectUri = 'http://localhost:$port/callback';
    debugPrint('$_tag callback server listening on $redirectUri');

    final authUrl = Uri.https(
      'login.microsoftonline.com',
      '/$tenantId/oauth2/v2.0/authorize',
      {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': _scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'response_mode': 'query',
      },
    );

    // Open browser for login
    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      debugPrint('$_tag failed to open browser');
      await server.close();
      return null;
    }
    debugPrint('$_tag browser opened, waiting for callback...');

    // Wait for the callback (with a timeout)
    String? authCode;
    try {
      final request = await server.first.timeout(const Duration(minutes: 3));
      if (request.uri.path == '/callback') {
        authCode = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        if (authCode != null) {
          debugPrint('$_tag received auth code (${authCode.length} chars)');
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(
              '<html><body><h2>Login successful!</h2>'
              '<p>You can close this window and return to Notibar.</p>'
              '</body></html>',
            );
          await request.response.close();
        } else {
          debugPrint('$_tag callback error: $error');
          request.response
            ..statusCode = 400
            ..headers.contentType = ContentType.html
            ..write(
              '<html><body><h2>Login failed</h2>'
              '<p>${_escapeHtml(error ?? "Unknown error")}. You can close this window.</p>'
              '</body></html>',
            );
          await request.response.close();
        }
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } on TimeoutException {
      debugPrint('$_tag login timed out (3 min)');
    } finally {
      await server.close();
    }

    if (authCode == null) {
      debugPrint('$_tag no auth code received, aborting');
      return null;
    }

    // Exchange authorization code for tokens
    debugPrint('$_tag exchanging auth code for token...');
    return _exchangeCodeForToken(authCode, redirectUri, codeVerifier);
  }

  Future<TokenResult?> _exchangeCodeForToken(
    String code,
    String redirectUri,
    String codeVerifier,
  ) async {
    final tokenUrl = Uri.https(
      'login.microsoftonline.com',
      '/$tenantId/oauth2/v2.0/token',
    );

    final response = await http.post(
      tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
        'scope': _scopes.join(' '),
      },
    );

    if (response.statusCode != 200) {
      debugPrint(
        '$_tag token exchange failed: ${response.statusCode} ${response.body}',
      );
      return null;
    }

    final data = json.decode(response.body);
    final token = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    debugPrint(
      '$_tag token exchange OK (token=${token != null ? '${token.length} chars' : 'null'}, refresh=${refreshToken != null ? '${refreshToken.length} chars' : 'null'})',
    );
    if (token == null) return null;
    return TokenResult(accessToken: token, refreshToken: refreshToken);
  }

  /// Uses a refresh token to get a new access token (and possibly a new refresh token).
  Future<TokenResult?> refreshAccessToken(String refreshToken) async {
    debugPrint('$_tag refreshing access token...');
    final tokenUrl = Uri.https(
      'login.microsoftonline.com',
      '/$tenantId/oauth2/v2.0/token',
    );

    final response = await http.post(
      tokenUrl,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': _scopes.join(' '),
      },
    );

    if (response.statusCode != 200) {
      debugPrint(
        '$_tag refresh failed: ${response.statusCode} ${response.body}',
      );
      return null;
    }

    final data = json.decode(response.body);
    final newToken = data['access_token'] as String?;
    final newRefresh = data['refresh_token'] as String?;
    debugPrint(
      '$_tag refresh OK (token=${newToken != null ? '${newToken.length} chars' : 'null'}, refresh=${newRefresh != null ? '${newRefresh.length} chars' : 'null'})',
    );
    if (newToken == null) return null;
    return TokenResult(
      accessToken: newToken,
      refreshToken: newRefresh ?? refreshToken,
    );
  }

  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
