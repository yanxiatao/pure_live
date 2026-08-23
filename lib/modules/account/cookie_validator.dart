import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/utils/douyin/douyin_request_params.dart';

/// Cookie 有效性校验结果。
enum CookieValidationStatus {
  /// 校验通过：平台接口确认登录态有效。
  valid,

  /// 校验不通过：接口确认登录态失效。
  invalid,

  /// 校验请求本身异常（网络不通等）；Cookie 可能仍有效，建议重试。
  error,

  /// 该平台无公开校验端点，仅保存不校验。
  unverified,
}

/// 各平台 Cookie 有效性校验。
///
/// 仅覆盖存在公开登录态端点的平台（douyin/twitch）；
/// 其余平台返回 [CookieValidationStatus.unverified]，由调用方按保存成功处理。
/// 校验请求经 [HttpClient]，自动遵循应用代理设置。
class CookieValidator {
  CookieValidator._();

  static Future<CookieValidationStatus> validate(String platform, String cookie) async {
    if (cookie.trim().isEmpty) return CookieValidationStatus.invalid;
    switch (platform) {
      case 'douyin':
        return _validateDouyin(cookie);
      case 'twitch':
        return _validateTwitch(cookie);
      default:
        return CookieValidationStatus.unverified;
    }
  }

  /// 抖音：webcast/user/me 携带 cookie 请求，返回非空 data 即登录有效
  /// （请求形态与 DouyinSite.getUserInfoByCookie 一致）。
  static Future<CookieValidationStatus> _validateDouyin(String cookie) async {
    try {
      final result = await HttpClient.instance.getJson(
        'https://live.douyin.com/webcast/user/me/',
        queryParameters: {'aid': DouyinRequestParams.aidValue},
        header: {
          'user-agent': DouyinRequestParams.kDefaultUserAgent,
          'accept': 'application/json, text/plain, */*',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Cookie': cookie,
        },
      );
      final data = result is Map ? result['data'] : null;
      return data is Map && data.isNotEmpty ? CookieValidationStatus.valid : CookieValidationStatus.invalid;
    } catch (_) {
      return CookieValidationStatus.error;
    }
  }

  /// Twitch：gql 携带 Cookie 查询当前用户，返回非空 currentUser 即登录有效。
  /// Client-ID 为 Twitch 网页端公开客户端标识。
  static Future<CookieValidationStatus> _validateTwitch(String cookie) async {
    try {
      final result = await HttpClient.instance.postJson(
        'https://gql.twitch.tv/gql',
        data: {'query': '{ currentUser { id login } }'},
        header: {'Client-ID': 'kimne78kx3ncx6brgo4mv6wki5h1ko', 'Cookie': cookie},
      );
      final data = result is Map ? result['data'] : null;
      final user = data is Map ? data['currentUser'] : null;
      return user != null ? CookieValidationStatus.valid : CookieValidationStatus.invalid;
    } catch (_) {
      return CookieValidationStatus.error;
    }
  }
}
