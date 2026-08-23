// mv-diag: 临时诊断设施（返回销毁链路冻结定位），问题闭环后本文件与
// 全仓库 `// mv-diag:` 标记行一并移除。
import 'dart:io';

import 'package:flutter/foundation.dart';

/// [mv-diag] 诊断日志双通道输出器。
///
/// Windows Release 包为 GUI 子系统，debugPrint 输出无处可看，
/// 故同步追加写入固定日志文件；调试通道保留用于开发期观察。
/// 诊断设施自身不得抛异常、不得影响任何业务行为：
/// 路径解析失败或写入失败一律降级为仅调试通道并留痕。
abstract final class MvDiagLogger {
  /// 单文件上限：首次写入时超过则先清空，防无限增长。
  static const int _maxBytes = 5 * 1024 * 1024;

  static bool _pathResolved = false;

  static File? _file;

  /// 记录一条诊断日志：debugPrint 与文件各一份。
  ///
  /// [message] 为不含时间戳的原始内容（如 `cell=0 teardown pause begin`），
  /// 时间戳与进程号由本方法统一附加。
  static void log(String message) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('[mv-diag] $message ts=$ts');
    _writeFile('[$ts] [pid=$pid] $message');
  }

  static void _writeFile(String line) {
    try {
      final file = _resolveFile();
      if (file == null) return;
      // 追加模式、写完即关（writeAsStringSync 每次独立开合）；
      // 超过上限先清空重写，防无限增长。
      if (!file.existsSync() || file.lengthSync() > _maxBytes) {
        file.writeAsStringSync('$line\n', mode: FileMode.write);
        return;
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (error) {
      // mv-diag: 文件写入失败仅回显调试通道，不递归写文件、不上抛。
      debugPrint('[mv-diag] file write failed: $error');
    }
  }

  static File? _resolveFile() {
    if (_pathResolved) return _file;
    _pathResolved = true;
    // Windows GUI 子系统下 TEMP 恒存在；LOCALAPPDATA 为兜底，均缺失则放弃文件通道。
    final base = Platform.environment['TEMP'] ?? Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) {
      _file = null;
      return null;
    }
    _file = File('$base\\pure_live_mv_diag.log');
    return _file;
  }
}
