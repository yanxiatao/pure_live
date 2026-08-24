/// Generated file. Do not edit.
///
/// To regenerate, run: `dart run enven --env-files .env,.env.dev,.env.prod --class-name AppConfig`
class AppConfig {
  /// Override this instance to mock the environment.
  /// Example: `AppConfig.instance = MockEnvData();`
  static EnvData instance = EnvData();

  static String get pureliveUpdateOwner => instance.pureliveUpdateOwner;
  static String get pureliveUpdateRepository => instance.pureliveUpdateRepository;
}

class EnvData {
  final String pureliveUpdateOwner = 'yanxiatao';

  final String pureliveUpdateRepository = 'pure_live';
}
