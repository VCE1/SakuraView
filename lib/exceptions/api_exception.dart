class ApiException implements Exception {
  final String message;
  final int? statusCode; // 可选，如果知道HTTP状态码
  final dynamic originalError; // 原始错误对象，方便调试

  ApiException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() {
    String statusInfo = statusCode != null ? ' (Status: $statusCode)' : '';
    return 'ApiException: $message$statusInfo';
  }
}
