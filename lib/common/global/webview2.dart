import 'dart:io';

import 'package:pure_live/common/index.dart';
import 'package:url_launcher/url_launcher.dart';

/// 判断 Windows 是否安装了 WebView2 Runtime；其他平台恒为 true。
Future<bool> isWebView2Installed() async {
  if (!Platform.isWindows) return true;

  try {
    var result64 = await Process.run('reg', [
      'query',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      '/v',
      'pv',
    ]);

    var resultUser = await Process.run('reg', [
      'query',
      r'HKEY_CURRENT_USER\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      '/v',
      'pv',
    ]);

    if ((result64.exitCode == 0 && result64.stdout.toString().contains('REG_SZ')) ||
        (resultUser.exitCode == 0 && resultUser.stdout.toString().contains('REG_SZ'))) {
      return true;
    }
  } catch (e) {
    debugPrint("检测 WebView2 失败: $e");
  }
  return false;
}

/// 提示缺少 WebView2 Runtime，并引导前往官网下载安装。
void showWebView2MissingDialog() {
  Get.dialog(
    Builder(
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.report_problem_rounded, color: Theme.of(dialogContext).colorScheme.error),
              const SizedBox(width: 8),
              Text(i18n("webview2_missing_title")),
            ],
          ),
          content: Text(i18n("webview2_missing_content"), style: const TextStyle(height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n("cancel"))),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final url = Uri.parse('https://developer.microsoft.com/zh-cn/microsoft-edge/webview2/?form=MA13LH');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  ToastUtil.show(i18n("webview2_open_error"));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.primary,
                foregroundColor: Theme.of(dialogContext).colorScheme.onPrimary,
              ),
              child: Text(i18n("confirm")),
            ),
          ],
        );
      },
    ),
    barrierDismissible: false,
  );
}
