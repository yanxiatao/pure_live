import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/account/cookie_validator.dart';

/// Edge CDP cookie 抓取状态。
enum EdgeCaptureState {
  /// 定位 msedge.exe。
  locating,

  /// 启动 Edge 并等待调试端点就绪。
  launching,

  /// 等待用户在 Edge 中登录；登录完成后由用户点击「我已登录完成」触发抓取。
  waitingLogin,

  /// 已捕获 Cookie。
  captured,

  /// 失败（找不到 Edge/启动失败）。
  failed,

  /// 用户取消。
  cancelled,
}

/// 平台抓取配置：登录页地址与 Cookie 归属域名。
class EdgeCaptureTarget {
  const EdgeCaptureTarget({required this.platform, required this.loginUrl, required this.domains});

  /// 平台标识（与账户模块一致），用于抓取后经平台接口校验登录态。
  final String platform;

  /// 打开的登录页/站点地址。
  final String loginUrl;

  /// Cookie 归属域名（后缀匹配，如 'twitch.tv' 匹配 '.twitch.tv'）。
  final List<String> domains;
}

/// 各平台抓取配置（key 与账户模块的平台标识一致）。
const Map<String, EdgeCaptureTarget> kEdgeCaptureTargets = {
  'douyin': EdgeCaptureTarget(platform: 'douyin', loginUrl: 'https://www.douyin.com/', domains: ['douyin.com']),
  'huya': EdgeCaptureTarget(platform: 'huya', loginUrl: 'https://www.huya.com/', domains: ['huya.com']),
  'kuaishou': EdgeCaptureTarget(platform: 'kuaishou', loginUrl: 'https://www.kuaishou.com/', domains: ['kuaishou.com']),
  'soop': EdgeCaptureTarget(platform: 'soop', loginUrl: 'https://www.sooplive.co.kr/', domains: ['sooplive.co.kr']),
  'twitch': EdgeCaptureTarget(platform: 'twitch', loginUrl: 'https://www.twitch.tv/login', domains: ['twitch.tv']),
};

/// 通过 Edge CDP（Chrome DevTools Protocol）抓取站点 Cookie。
///
/// 流程（lib-3 调研结论）：
/// 1. 定位 msedge.exe（已知路径 → 注册表 App Paths）；
/// 2. bind(0) 取空闲调试端口，创建独立临时 user-data-dir
///    （Chromium 136+ 在默认 profile 下忽略调试端口参数，临时目录是
///    必选项，同时避免读取用户默认配置文件的隐私问题）；
/// 3. 启动 Edge 打开平台登录页，轮询 /json/version 等待调试端点就绪；
/// 4. 等待用户在 Edge 中完成登录，点击「我已登录完成」后**单次**抓取：
///    经 CDP `Storage.getCookies` 按域名过滤组装 `name=value; ...` 返回，
///    并经平台接口校验登录态（无效则提示后保持等待，可再次点击）。
///
/// 不做任何自动轮询：Storage.getCookies 需序列化全浏览器 Cookie，
/// 周期调用会与登录页加载争抢 Cookie 后端导致页面卡顿（实测）。
/// 使用独立临时 profile 意味着用户需要在打开的 Edge 里重新登录一次；
/// 抓取完成后该临时实例会被关闭并清理。
class EdgeCookieCapture {
  EdgeCookieCapture({required this.target});

  final EdgeCaptureTarget target;

  final StreamController<EdgeCaptureState> _stateController = StreamController<EdgeCaptureState>.broadcast();
  Stream<EdgeCaptureState> get stateStream => _stateController.stream;

  /// 抓取过程的用户提示（如「未捕获到 Cookie」「Cookie 无效」），
  /// 由对话框展示；空消息不发射。
  final StreamController<String> _hintController = StreamController<String>.broadcast();
  Stream<String> get hintStream => _hintController.stream;

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  Process? _edgeProcess;
  WebSocket? _cdpSocket;
  int? _cdpPort;
  bool _finished = false;
  bool _captureInFlight = false;
  String? _resultCookie;
  int _cdpRequestId = 0;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingCdp = <int, Completer<Map<String, dynamic>?>>{};

  /// 抓取结果：成功收口时为组装好的 Cookie 字符串；取消/失败为 null。
  /// 对话框关闭后由调用方读取。
  String? get resultCookie => _resultCookie;

  /// 执行启动流程；之后由用户点击「我已登录完成」触发 [completeManually]
  /// 单次抓取。取消/失败返回 null。
  Future<void> start() async {
    _emit(EdgeCaptureState.locating);
    final edgePath = await _locateEdge();
    if (edgePath == null) {
      _log('msedge.exe not found');
      _finish(null, EdgeCaptureState.failed);
      return;
    }

    final port = await _pickFreePort();
    if (port == null) {
      _log('no free port');
      _finish(null, EdgeCaptureState.failed);
      return;
    }

    final profileDir = '${Directory.systemTemp.path}/purelive-cdp-$port';
    _emit(EdgeCaptureState.launching);
    try {
      Directory(profileDir).createSync(recursive: true);
    } catch (_) {}

    try {
      _edgeProcess = await Process.start(edgePath, [
        '--remote-debugging-port=$port',
        '--user-data-dir=$profileDir',
        '--no-first-run',
        '--no-default-browser-check',
        target.loginUrl,
      ]);
    } catch (error) {
      _log('launch failed: $error');
      _finish(null, EdgeCaptureState.failed);
      return;
    }

    // 等待调试端点就绪（Edge 冷启动需数秒），随后进入等待登录阶段。
    final ready = await _waitForDebugEndpoint(port, const Duration(seconds: 30));
    if (!ready) {
      _log('debug endpoint not ready in time');
      _cleanup(port);
      _finish(null, EdgeCaptureState.failed);
      return;
    }

    // 等待调试端点就绪（Edge 冷启动需数秒），随后连接浏览器级 CDP WebSocket
    // （「我已登录完成」的单次抓取经此通道），进入等待登录阶段。
    _cdpPort = port;

    final wsUrl = await _fetchBrowserWsUrl(port);
    if (wsUrl == null) {
      _log('browser ws url unavailable');
      _cleanup(port);
      _finish(null, EdgeCaptureState.failed);
      return;
    }
    final socket = await WebSocket.connect(wsUrl);
    _cdpSocket = socket;
    socket.listen((data) {
      if (data is! String) return;
      final message = jsonDecode(data);
      final id = message['id'];
      if (id is int && _pendingCdp.containsKey(id)) {
        _pendingCdp.remove(id)!.complete(message);
      }
    });

    _emit(EdgeCaptureState.waitingLogin);
  }

  /// 用户点击「我已登录完成」：单次抓取 Cookie 并校验登录态。
  ///
  /// 有效（或平台无校验端点）→ 收口返回；无效 → 提示后保持等待，
  /// 用户可确认登录完成后再次点击；未捕获到 Cookie 同样提示并保持等待。
  Future<void> completeManually() async {
    if (_finished || _captureInFlight) return;
    final socket = _cdpSocket;
    final port = _cdpPort;
    if (socket == null || port == null) {
      _hint(i18n('cookie_capture_not_ready'));
      return;
    }

    _captureInFlight = true;
    try {
      final cookies = await _fetchCookiesViaCdp(socket);
      final cookie = cookies != null ? _assembleCookieString(cookies) : null;
      if (cookie == null) {
        _hint(i18n('cookie_capture_empty_hint'));
        return;
      }

      final validation = await CookieValidator.validate(target.platform, cookie);
      switch (validation) {
        case CookieValidationStatus.valid || CookieValidationStatus.unverified:
          _finish(cookie, EdgeCaptureState.captured);
        case CookieValidationStatus.invalid:
          // 无效：提示后保持弹层等待，用户可确认登录完成后再次点击。
          _hint(i18n('cookie_invalid_retry'));
        case CookieValidationStatus.error:
          _hint(i18n('cookie_check_failed'));
      }
    } finally {
      _captureInFlight = false;
    }
  }

  /// 取消抓取并清理。
  void cancel() {
    _finish(null, EdgeCaptureState.cancelled);
  }

  Future<List<Map<String, dynamic>>?> _fetchCookiesViaCdp(WebSocket socket) async {
    final response = await _cdpCommand(socket, 'Storage.getCookies');
    if (response == null) return null;
    final result = response['result'];
    if (result is! Map) return null;
    final cookies = result['cookies'];
    return cookies is List ? cookies.whereType<Map<String, dynamic>>().toList() : null;
  }

  Future<Map<String, dynamic>?> _cdpCommand(WebSocket socket, String method) async {
    final id = ++_cdpRequestId;
    final completer = Completer<Map<String, dynamic>?>();
    _pendingCdp[id] = completer;
    socket.add(jsonEncode({'id': id, 'method': method}));
    // 单次命令超时兜底，避免 WS 半死状态卡死交互。
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pendingCdp.remove(id);
        return null;
      },
    );
  }

  /// 按 [EdgeCaptureTarget.domains] 过滤并组装 Cookie 字符串。
  String? _assembleCookieString(List<Map<String, dynamic>> cookies) {
    final matched = cookies.where((c) => _domainMatches(c)).toList();
    if (matched.isEmpty) return null;
    // 同名 Cookie 后值覆盖前值（跨子域场景取最后一个）。
    final byName = <String, String>{};
    for (final c in matched) {
      final name = c['name']?.toString();
      final value = c['value']?.toString();
      if (name != null && name.isNotEmpty && value != null) byName[name] = value;
    }
    return byName.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  bool _domainMatches(Map<String, dynamic> cookie) {
    final domain = cookie['domain']?.toString() ?? '';
    return target.domains.any((d) => domain == d || domain == '.$d' || domain.endsWith('.$d') || domain == '.$d');
  }

  /// 轮询 /json/version 直到调试端点就绪或超时。
  Future<bool> _waitForDebugEndpoint(int port, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      while (DateTime.now().isBefore(deadline) && !_finished) {
        try {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/json/version'));
          final response = await request.close();
          if (response.statusCode == 200) {
            await response.drain<void>();
            return true;
          }
          await response.drain<void>();
        } catch (_) {
          // 端点未就绪，继续轮询。
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 读取浏览器级 WebSocket 调试地址（webSocketDebuggerUrl）。
  Future<String?> _fetchBrowserWsUrl(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/json/version'));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      return json['webSocketDebuggerUrl']?.toString();
    } catch (error) {
      _log('fetch ws url failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _emit(EdgeCaptureState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _log(String message) {
    if (!_logController.isClosed) _logController.add(message);
  }

  void _hint(String message) {
    if (!_hintController.isClosed) _hintController.add(message);
  }

  void _finish(String? cookie, EdgeCaptureState state) {
    if (_finished) return;
    _finished = true;
    _resultCookie = cookie;
    try {
      _cdpSocket?.close();
    } catch (_) {}
    _cdpSocket = null;
    _cdpPort = null;
    try {
      _edgeProcess?.kill();
    } catch (_) {}
    _edgeProcess = null;
    _emit(cookie != null ? EdgeCaptureState.captured : state);
    if (!_stateController.isClosed) _stateController.close();
    if (!_hintController.isClosed) _hintController.close();
    if (!_logController.isClosed) _logController.close();
  }

  void _cleanup(int port) {
    try {
      Directory('${Directory.systemTemp.path}/purelive-cdp-$port').deleteSync(recursive: true);
    } catch (_) {}
  }

  /// 定位 msedge.exe：已知安装路径 → 注册表 App Paths；找不到返回 null。
  static Future<String?> _locateEdge() async {
    final candidates = <String>[
      '${Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)'}\\Microsoft\\Edge\\Application\\msedge.exe',
      '${Platform.environment['ProgramFiles'] ?? r'C:\Program Files'}\\Microsoft\\Edge\\Application\\msedge.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        '/ve',
      ]);
      if (result.exitCode == 0) {
        final match = RegExp(r'REG_SZ\s+(.+)').firstMatch(result.stdout.toString());
        final path = match?.group(1)?.trim().replaceAll('"', '');
        if (path != null && File(path).existsSync()) return path;
      }
    } catch (_) {}
    return null;
  }

  /// bind(0) 取一个空闲回环端口。
  static Future<int?> _pickFreePort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (_) {
      return null;
    }
  }

  /// 弹出抓取对话框并等待完成；返回捕获的 Cookie（取消/失败返回 null）。
  ///
  /// 对话框实时展示抓取状态与提示，并提供「我已登录完成」（单次抓取）
  /// 与「取消」按钮；抓取结束（捕获/失败/取消）自动关闭。
  static Future<String?> showCaptureDialog(BuildContext context, EdgeCaptureTarget target) async {
    final capture = EdgeCookieCapture(target: target);
    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }
    }

    final stateSub = capture.stateStream.listen((state) {
      if (dialogOpen &&
          (state == EdgeCaptureState.captured ||
              state == EdgeCaptureState.failed ||
              state == EdgeCaptureState.cancelled)) {
        closeDialog();
      }
    });

    unawaited(capture.start());

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(i18n('cookie_capture_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<EdgeCaptureState>(
                stream: capture.stateStream,
                initialData: EdgeCaptureState.locating,
                builder: (context, snapshot) {
                  final state = snapshot.data ?? EdgeCaptureState.locating;
                  return Text(_captureStateText(state), style: AppTextStyles.t14);
                },
              ),
              const SizedBox(height: 8),
              StreamBuilder<String>(
                stream: capture.hintStream,
                builder: (context, snapshot) {
                  final hint = snapshot.data;
                  if (hint == null || hint.isEmpty) return const SizedBox.shrink();
                  return Text(hint, style: AppTextStyles.t12);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => unawaited(capture.completeManually()),
              child: Text(i18n('cookie_capture_done_button')),
            ),
            TextButton(onPressed: capture.cancel, child: Text(i18n('cancel'))),
          ],
        ),
      ),
    );

    stateSub.cancel();
    closeDialog();
    return capture.resultCookie;
  }

  static String _captureStateText(EdgeCaptureState state) {
    switch (state) {
      case EdgeCaptureState.locating:
        return i18n('cookie_capture_locating');
      case EdgeCaptureState.launching:
        return i18n('cookie_capture_launching');
      case EdgeCaptureState.waitingLogin:
        return i18n('cookie_capture_waiting');
      case EdgeCaptureState.captured:
        return i18n('cookie_capture_captured');
      case EdgeCaptureState.failed:
        return i18n('cookie_capture_failed');
      case EdgeCaptureState.cancelled:
        return i18n('cookie_capture_cancelled');
    }
  }
}
