import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

import '../db/database.dart';
import 'jwt_service.dart';

class VerifiedAccessToken {
  const VerifiedAccessToken({required this.userId, required this.sessionId});

  final int userId;
  final String sessionId;
}

class AuthenticatedRequestContext {
  const AuthenticatedRequestContext({
    required this.user,
    required this.sessionId,
  });

  final DbUser user;
  final String sessionId;
}

VerifiedAccessToken readVerifiedAccessToken(Request request) {
  final authHeader = request.headers['Authorization'];

  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    throw RequestAuthenticationException(Response.forbidden('No token'));
  }

  final token = authHeader.substring(7);

  try {
    final jwt = verifyAccessToken(token);
    final rawUserId = jwt.payload['uid'];
    final rawSessionId = jwt.payload['sid'];
    final userId = rawUserId is int ? rawUserId : int.tryParse('$rawUserId');
    final sessionId = rawSessionId is String ? rawSessionId.trim() : '';

    if (userId == null || sessionId.isEmpty) {
      throw RequestAuthenticationException(Response.forbidden('Invalid token'));
    }

    return VerifiedAccessToken(userId: userId, sessionId: sessionId);
  } on JWTExpiredException {
    throw RequestAuthenticationException(Response.forbidden('Token expired'));
  } on JWTInvalidException {
    throw RequestAuthenticationException(Response.forbidden('Invalid token'));
  }
}

Future<AuthenticatedRequestContext> authenticateRequest(
  Request request,
  DatabaseService db,
) async {
  final verifiedToken = readVerifiedAccessToken(request);
  final session = await db.getAuthSessionById(verifiedToken.sessionId);
  if (session == null) {
    throw RequestAuthenticationException(
      Response.forbidden('Session not found'),
    );
  }

  if (session.userId != verifiedToken.userId) {
    throw RequestAuthenticationException(Response.forbidden('Invalid token'));
  }

  if (session.revokedAt != null) {
    throw RequestAuthenticationException(Response.forbidden('Session revoked'));
  }

  final expiresAt = DateTime.tryParse(session.expiresAt);
  if (expiresAt == null) {
    throw RequestAuthenticationException(Response.forbidden('Invalid token'));
  }

  if (!expiresAt.isAfter(DateTime.now().toUtc())) {
    throw RequestAuthenticationException(Response.forbidden('Session expired'));
  }

  final user = await db.getUserById(verifiedToken.userId);
  if (user == null) {
    throw RequestAuthenticationException(Response.forbidden('User not found'));
  }

  return AuthenticatedRequestContext(user: user, sessionId: session.id);
}

class RequestAuthenticationException implements Exception {
  const RequestAuthenticationException(this.response);

  final Response response;
}
