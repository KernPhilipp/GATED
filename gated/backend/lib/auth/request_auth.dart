import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

import '../db/database.dart';
import 'jwt_service.dart';

class AuthenticatedRequestContext {
  const AuthenticatedRequestContext({required this.user});

  final DbUser user;
}

Future<AuthenticatedRequestContext> authenticateRequest(
  Request request,
  DatabaseService db,
) async {
  final authHeader = request.headers['Authorization'];

  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    throw RequestAuthenticationException(Response.forbidden('No token'));
  }

  final token = authHeader.substring(7);

  try {
    final jwt = verifyJwt(token);
    final rawUserId = jwt.payload['uid'];
    final userId = rawUserId is int ? rawUserId : int.tryParse('$rawUserId');

    if (userId == null) {
      throw RequestAuthenticationException(
        Response.forbidden('Invalid token'),
      );
    }

    final user = await db.getUserById(userId);
    if (user == null) {
      throw RequestAuthenticationException(
        Response.forbidden('User not found'),
      );
    }

    return AuthenticatedRequestContext(user: user);
  } on JWTExpiredException {
    throw RequestAuthenticationException(
      Response.forbidden('Token expired'),
    );
  } on JWTInvalidException {
    throw RequestAuthenticationException(
      Response.forbidden('Invalid token'),
    );
  }
}

class RequestAuthenticationException implements Exception {
  const RequestAuthenticationException(this.response);

  final Response response;
}
