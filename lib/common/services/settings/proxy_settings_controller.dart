import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';

class ProxySettingsController extends GetxController {
  final RxBool enableProxy = hiveBool('enableProxy', false);
  final RxString proxyHost = hiveString('proxyHost', '');
  final RxInt proxyPort = hiveInt('proxyPort', 7897);

  // app proxy settings
  final RxBool enableAppProxy = hiveBool('enableAppProxy', false);
  final RxString appProxyHost = hiveString('appProxyHost', '');
  final RxInt appProxyPort = hiveInt('appProxyPort', 7897);

  // Twitch 免代理播放：经 TTV LOL 类公开反代获取播放列表（实验性）。
  // 反代地址逗号分隔，按序 failover；播放流传输域名（ttvnw.net）可直连。
  final RxBool enableTwitchProxy = hiveBool('enableTwitchProxy', false);
  final RxString twitchProxyPlaylists = hiveString(
    'twitchProxyPlaylists',
    'api.ttv.lol,eu.luminous.dev,lb-eu.cdn-perfprod.com',
  );

  @override
  void onInit() {
    super.onInit();

    ever<bool>(enableAppProxy, (_) => _refreshDioConnections());
    ever<String>(appProxyHost, (_) => _refreshDioConnections());
    ever<int>(appProxyPort, (_) => _refreshDioConnections());
  }

  void _refreshDioConnections() {
    try {
      HttpClient.instance.rebuildDio();
    } catch (_) {}
  }

  Map<String, dynamic> toJson() {
    return {
      'enableProxy': enableProxy.v,
      'proxyHost': proxyHost.v,
      'proxyPort': proxyPort.v,
      'enableAppProxy': enableAppProxy.v,
      'appProxyHost': appProxyHost.v,
      'appProxyPort': appProxyPort.v,
      'enableTwitchProxy': enableTwitchProxy.v,
      'twitchProxyPlaylists': twitchProxyPlaylists.v,
    };
  }

  void fromJson(Map<String, dynamic> json) {
    enableProxy.v = json['enableProxy'] ?? false;
    proxyHost.v = json['proxyHost'] ?? '';
    proxyPort.v = json['proxyPort'] ?? 1080;
    enableAppProxy.v = json['enableAppProxy'] ?? false;
    appProxyHost.v = json['appProxyHost'] ?? '';
    appProxyPort.v = json['appProxyPort'] ?? 1080;
    enableTwitchProxy.v = json['enableTwitchProxy'] ?? false;
    twitchProxyPlaylists.v = json['twitchProxyPlaylists'] ?? 'api.ttv.lol,eu.luminous.dev,lb-eu.cdn-perfprod.com';
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final proxy = rootConfig?['proxy'] as Map<String, dynamic>? ?? {};
    return {
      'enableProxy': proxy['enableProxy'] ?? false,
      'proxyHost': proxy['proxyHost'] ?? '',
      'proxyPort': proxy['proxyPort'] ?? 7897,
      'enableAppProxy': proxy['enableAppProxy'] ?? false,
      'appProxyHost': proxy['appProxyHost'] ?? '',
      'appProxyPort': proxy['appProxyPort'] ?? 7897,
      'enableTwitchProxy': proxy['enableTwitchProxy'] ?? false,
      'twitchProxyPlaylists': proxy['twitchProxyPlaylists'] ?? 'api.ttv.lol,eu.luminous.dev,lb-eu.cdn-perfprod.com',
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final proxy = Map<String, dynamic>.from(rootConfig['proxy'] ?? {});
    updateFields.forEach((k, v) => proxy[k] = v);
    rootConfig['proxy'] = proxy;
    return rootConfig;
  }
}
