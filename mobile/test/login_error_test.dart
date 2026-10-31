import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labelguard_mobile/providers/auth_provider.dart';

DioException _withStatus(int code, [Object? data]) {
  final options = RequestOptions(path: '/auth/login');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: code, data: data),
  );
}

void main() {
  test('a wrong password says so', () {
    expect(loginErrorMessage(_withStatus(401)), 'Invalid username/email or password');
  });

  test('a lockout shows the server\'s wait time, not "wrong password"', () {
    final e = _withStatus(429, {'detail': 'Too many failed logins. Try again in 15 minute(s).'});
    expect(loginErrorMessage(e), 'Too many failed logins. Try again in 15 minute(s).');
    expect(loginErrorMessage(_withStatus(429)), 'Too many failed logins. Try again later.');
  });

  test('no response means the server was not reached', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/auth/login'),
      type: DioExceptionType.connectionError,
    );
    expect(loginErrorMessage(e), contains("Can't reach the server"));
  });
}
