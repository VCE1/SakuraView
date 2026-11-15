/// 应用版本与构建元信息，发布构建时可通过 `--dart-define` 注入精确构建时间与版本号。
class AppBuildInfo {
  const AppBuildInfo._();

  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.4.0',
  );

  static const String buildNumber = String.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: '4',
  );

  static const String buildTime = String.fromEnvironment(
    'BUILD_TIME',
    defaultValue: '2026-11-13 20:52:00',
  );

  static String get fullVersion => '$version+$buildNumber';
}
