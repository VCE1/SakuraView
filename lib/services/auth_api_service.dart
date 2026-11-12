class AuthApiService {
  final String _baseUrl = 'https://yande.re';
  final String _loginPagePath = '/user/login';
  final String _authenticatePath = '/user/authenticate';

  String get loginPageUrl => '$_baseUrl$_loginPagePath';
  String get authenticateUrl => '$_baseUrl$_authenticatePath';
  String get baseUrl => _baseUrl;
  String get loginPath => _loginPagePath;
}
