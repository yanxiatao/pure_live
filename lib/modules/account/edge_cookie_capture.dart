import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pure_live/common/index.dart';

/// Edge CDP cookie 抓取状态。
enum EdgeCaptureState {
  /// 定位 msedge.exe。
  locating,

  /// 启动 Edge 并等待调试端点就绪。
  launching,

  /// 等待用户在 Edge 中登录（轮询特征 Cookie）。
  waitingLogin,

  /// 已捕获 Cookie。
  captured,

  /// 失败（找不到 Edge/启动失败/超时）。
  failed,

  /// 用户取消。
  cancelled,
}

/// 平台抓取配置：登录页地址、Cookie 域名与登录态特征 Cookie。
class EdgeCaptureTarget {
  const EdgeCaptureTarget({required this.loginUrl, required this.domains, this.characteristicCookies = const []});

  /// 打开的登录页/站点地址。
  final String loginUrl;

  /// Cookie 归属域名（后缀匹配，如 'twitch.tv' 匹配 '.twitch.tv'）。
  final List<String> domains;

  /// 登录态特征 Cookie 名；全部出现时自动完成抓取。
  /// 空列表表示无法自动判定，依赖用户手动点击「我已登录完成」。
  final List<String> characteristicCookies;
}

/// 各平台抓取配置（key 与账户模块的平台标识一致）。
const Map<String, EdgeCaptureTarget> kEdgeCaptureTargets = {
  'douyin': EdgeCaptureTarget(
    loginUrl: 'https://www.douyin.com/',
    domains: ['douyin.com'],
    characteristicCookies: ['sessionid_ss', 'sid_tt'],
  ),
  'huya': EdgeCaptureTarget(loginUrl: 'https://www.huya.com/', domains: ['huya.com']),
  'kuaishou': EdgeCaptureTarget(loginUrl: 'https://www.kuaishou.com/', domains: ['kuaishou.com']),
  'soop': EdgeCaptureTarget(loginUrl: 'https://www.sooplive.co.kr/', domains: ['sooplive.co.kr']),
  'twitch': EdgeCaptureTarget(
    loginUrl: 'https://www.twitch.tv/login',
    domains: ['twitch.tv'],
    characteristicCookies: ['auth-token'],
  ),
};

/// 通过 Edge CDP（Chrome DevTools Protocol）抓取站点 Cookie。
///
/// 流程（lib-3 调研结论）：
/// 1. 定位 msedge.exe（已知路径 → 注册表 App Paths）；
/// 2. bind(0) 取空闲调试端口，创建独立临时 user-data-dir
///    （Chromium 136+ 在默认 profile 下忽略调试端口参数，临时目录是
///    必选项，同时避免读取用户默认配置文件的隐私问题）；
/// 3. 启动 Edge 打开平台登录页，轮询 /json/version 等待调试端点就绪；
/// 4. 周期经 CDP `Storage.getCookies` 抓取 Cookie：特征 Cookie 齐全时
///    自动完成，用户也可点「我已登录完成」手动收口；
/// 5. 按域名过滤组装 `name=value; ...` 字符串返回。
///
/// 使用独立临时 profile 意味着用户需要在打开的 Edge 里重新登录一次；
/// 抓取完成后该临时实例会被关闭并清理。
class EdgeCookieCapture {
  EdgeCookieCapture({required this.target});

  final EdgeCaptureTarget target;

  final StreamController<EdgeCaptureState> _stateController = StreamController<EdgeCaptureState>.broadcast();
  Stream<EdgeCaptureState> get stateStream => _stateController.stream;

  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  Process? _edgeProcess;
  WebSocket? _cdpSocket;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  bool _manualComplete = false;
  bool _finished = false;
  String? _lastCookie;
  int _cdpRequestId = 0;
  final Map<int, Completer<Map<String, dynamic>?>> _pendingCdp = <int, Completer<Map<String, dynamic>?>>{};

  /// 执行抓取；返回组装好的 Cookie 字符串，取消/失败/超时返回 null。
  Future<String?> capture() async {
    _emit(EdgeCaptureState.locating);
    final edgePath = await _locateEdge();
    if (edgePath == null) {
      _log('msedge.exe not found');
      _finish(null, EdgeCaptureState.failed);
      return null;
    }

    final port = await _pickFreePort();
    if (port == null) {
      _log('no free port');
      _finish(null, EdgeCaptureState.failed);
      return null;
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
      return null;
    }

    // 等待调试端点就绪（Edge 冷启动需数秒）。
    final ready = await _waitForDebugEndpoint(port, const Duration(seconds: 30));
    if (!ready) {
      _log('debug endpoint not ready in time');
      _cleanup(port);
      _finish(null, EdgeCaptureState.failed);
      return null;
    }

    _emit(EdgeCaptureState.waitingLogin);

    // 总超时兜底：5 分钟未完成视为放弃。
    _timeoutTimer = Timer(const Duration(minutes: 5), () => _finish(_lastCookie, EdgeCaptureState.failed));

    final cookie = await _pollLoop(port);
    _cleanup(port);
    return cookie;
  }

  /// 用户确认登录完成：立即用当前已抓到的 Cookie 收口。
  void completeManually() {
    _manualComplete = true;
  }

  /// 取消抓取并清理。
  void cancel() {
    _manualComplete = false;
    _finish(null, EdgeCaptureState.cancelled);
  }

  Future<String?> _pollLoop(int port) async {
    // 连接浏览器级 CDP WebSocket。
    final wsUrl = await _fetchBrowserWsUrl(port);
    if (wsUrl == null) {
      _log('browser ws url unavailable');
      return _lastCookie;
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

    while (!_finished) {
      final cookies = await _fetchCookiesViaCdp(socket);
      if (cookies != null) {
        _lastCookie = _assembleCookieString(cookies);
        final autoDetected = _hasCharacteristicCookies(cookies);
        if (autoDetected || _manualComplete) {
          _finish(_lastCookie, EdgeCaptureState.captured);
          return _lastCookie;
        }
      }
      // Edge 进程退出（用户关窗）且未手动完成 → 结束。
      if (_edgeProcess == null) break;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return _lastCookie;
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
    // 单次命令超时兜底，避免 WS 半死状态卡死轮询。
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

  bool _hasCharacteristicCookies(List<Map<String, dynamic>> cookies) {
    if (target.characteristicCookies.isEmpty) return false;
    final names = cookies.where(_domainMatches).map((c) => c['name']?.toString()).toSet();
    return target.characteristicCookies.every(names.contains);
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

  void _finish(String? cookie, EdgeCaptureState state) {
    if (_finished) return;
    _finished = true;
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    try {
      _cdpSocket?.close();
    } catch (_) {}
    _cdpSocket = null;
    try {
      _edgeProcess?.kill();
    } catch (_) {}
    _edgeProcess = null;
    _emit(cookie != null ? EdgeCaptureState.captured : state);
    if (!_stateController.isClosed) _stateController.close();
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
  /// 对话框实时展示抓取状态，并提供「我已登录完成」（手动收口）与
  /// 「取消」按钮；抓取结束（捕获/失败/取消）自动关闭。
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

    final captureFuture = capture.capture();
    unawaited(
      showDialog<void>(
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
                StreamBuilder<EdgeCaptureState>(
                  stream: capture.stateStream,
                  initialData: EdgeCaptureState.locating,
                  builder: (context, snapshot) {
                    final state = snapshot.data ?? EdgeCaptureState.locating;
                    if (state != EdgeCaptureState.waitingLogin) return const SizedBox.shrink();
                    return Text(i18n('cookie_capture_waiting_hint'), style: AppTextStyles.t12);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: capture.completeManually, child: Text(i18n('cookie_capture_done_button'))),
              TextButton(onPressed: capture.cancel, child: Text(i18n('cancel'))),
            ],
          ),
        ),
      ),
    );

    final cookie = await captureFuture;
    stateSub.cancel();
    closeDialog();
    return cookie;
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
