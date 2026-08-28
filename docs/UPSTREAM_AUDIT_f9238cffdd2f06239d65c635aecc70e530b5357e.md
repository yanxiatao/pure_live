# 上游同步审计：`f9238cffdd2f`（v3.0.7 / build 4095）

- fork_sha: `0204a045879643ad852ce3daff436d4478668783`
- upstream_sha: `f9238cffdd2f06239d65c635aecc70e530b5357e`（tag v3.0.7）
- merge_base: `74543f68194f8c8bc504bbb627c1c622cd568142`
- incoming_range: `74543f68194f8c8bc504bbb627c1c622cd568142..f9238cffdd2f06239d65c635aecc70e530b5357e`（59 个入站提交，108 个变更文件）
- report: `local-artifacts/upstream-reviews/upstream-f9238cffdd2f.json`

## 结论摘要

本轮按“保留本 fork 功能与更新/下载源、其余以上游优先”处置：67 个高风险文件中只有 3 个产生文本冲突（`.github/workflows/build_pure_live_release.yml`、`assets/version.json`、`lib/player/core/player_session.dart`），另有 4 处无文本冲突但需要判断的语义冲突（`en.json` 键缺失、`video_player.dart` 生命周期监听被删、`pubspec.lock` 与 fork 腾讯镜像冲突且上游锁不可 enforce、上游自带测试断言与模型不一致）。发布身份统一为 3.0.7/4095、tag `v3.0.7`，下载与更新指向 `yanxiatao/pure_live`。

## file_review

| 状态 | 文件 | 风险 | 上游目的 | 维护分支相关实现 | 处置 |
| --- | --- | --- | --- | --- | --- |
| M | `.github/workflows/build_pure_live_release.yml` | high / workflows_and_release（+14/-14） | release_tag 默认值 v3.0.4 -> v3.0.7；Android 说明改为 API 26；gh release view 增取 body/author；把 setup-java 固定提交换成可变标签 @v6；上传/检出动作的版本注释纠正为真实标签；删除 release_sync_note 输入与正文占位；顶层权限降为 contents: read。 | 本 fork 的 sync-upstream.yml 以 release_sync_note 派发该工作流，输入必须保留；动作固定 40 位提交是仓库硬性策略；顶层 contents: read 可接受（publish/update-json 已有作业级 contents: write）。 | `adapt` |
| M | `.github/workflows/feature-build.yml` | high / workflows_and_release（+2/-2） | release_tag 默认值改为 v3.0.14；Android 正文说明改为 API 26。 | 本 fork 发布身份定为 3.0.7/4095，v3.0.14 与本仓库实际版本不符，默认标签回写 v3.0.7；Release 正文的 pure_live 下载行改指 yanxiatao/pure_live，TV 行保留上游。 | `adapt` |
| M | `.github/workflows/publish-staged-release.yml` | high / workflows_and_release（+1/-1） | 草稿标签默认值改为 v3.0.14。 | 同样回写 v3.0.7，避免手工派发时生成不存在的标签。 | `adapt` |
| M | `.github/workflows/stage-hosted-artifacts.yml` | high / workflows_and_release（+1/-1） | 暂存标签默认值改为 v3.0.14。 | 同样回写 v3.0.7。 | `adapt` |
| M | `.vscode/launch.json` | low / repository_metadata（+2/-5） | 移除 --android-skip-build-dependency-validation 参数（与 minSdk 提高、去掉 overrideLibrary 配套）。 | 仅影响本机调试启动配置，不进入构建产物。 | `accept` |
| M | `RELEASE_NOTES.md` | high / workflows_and_release（+218/-0） | 追加 v3.0.5..v3.0.14 共 218 行版本说明，含被上游回滚的 3.0.13/3.0.14 段落。 | 属于上游变更历史文本，fork 未改动该文件；保留上游全文，版本头与 3.0.7 不同为上游自身漂移，已在校验中记录。 | `accept` |
| M | `android/app/build.gradle.kts` | high / android_native（+23/-21） | minSdk 由 flutter.minSdkVersion 改为固定 26；debug 构建类型在 key.properties 完整时改用 release 签名配置；清理注释。 | 录制依赖 FFmpegKit 原生 API 26 下限，fork 的 Android 用户最低支持版本随之上移；本机 debug 包可能带正式签名，属于上游刻意变更，已记录为交付说明项。 | `accept` |
| M | `android/app/src/main/AndroidManifest.xml` | high / android_native（+0/-1） | 删除 uses-sdk overrideLibrary=ffmpeg_kit_extended_flutter。 | 与 minSdk 26 配套，取消绕过插件最低版本的做法；合并后已确认全仓库 XML 不再含 overrideLibrary。 | `accept` |
| M | `android/build.gradle.kts` | high / android_native（+2/-1） | 插件 defaultConfig.minSdk 23 -> 26。 | 同上，Android 全量用户安装门槛提高，需在 Release 说明中体现。 | `accept` |
| A | `assets/cacert.pem` | medium / translations_and_assets（+2950/-0） | 新增 Mozilla CA 快照（188900 字节 / 121 段），供 Android 侧 FFmpegKit 自带 TLS 栈校验 HTTPS 输入。 | 录制路径新增依赖：缺失或损坏会让 FFmpegManager.initialize() 失败，进而影响录制与合并；已在合并后校验文件大小与 PEM 段数。 | `accept` |
| M | `assets/releases.json` | high / workflows_and_release（+3932/-4860） | 上游 CI 重新生成发布索引：由 fork/基线的 {"releases": [...]} 详细结构改为扁平数组（version/title/date/github/author/changelog/files），条目 145 -> 120。 | 该文件是 CI 生成物，非人工维护；lib/modules/about/version_history.dart 同时兼容两种结构。版本历史源已按要求改指本 fork，fork 的 update-json 作业会用 yanxiatao 的 Release 再生成。 | `accept` |
| M | `assets/translations/en.json` | medium / translations_and_assets（+31/-1） | 新增 portrait_custom_height*、recorder_stage_*、quality_* 等 30 个键。 | 自动合并成功；但 fork 侧曾从 en.json 删除 audience_ranking_rule_desc、audience_yy_detail、quality_limited_to、quality_stream_unchanged，而这 4 个键仍被 player_controller.dart 与 audience_metric_settings_page.dart 调用，已按上游文本补回（英文界面此前会显示原始键名）。 | `adapt` |
| M | `assets/translations/zh.json` | medium / translations_and_assets（+31/-1） | 与 en.json 对称的 30 个新键。 | 自动合并，无键丢失；已用脚本比对基线/上游/合并三方的键集合。 | `accept` |
| M | `assets/version.json` | high / workflows_and_release（+31/-31） | 版本推进到 3.0.7 / build 4095 / version_num 300074095，更新描述；download_url 指向 liuchuancong。 | 文本冲突。取上游全部版本字段与描述，6 处 download_url 全部改写为 https://github.com/yanxiatao/pure_live/releases/tag/v3.0.7；上游同时修正了 fork 中 windows/linux/macos/ios 的 version_num 少一位问题。 | `adapt` |
| A | `docs/PLAYER_RECOVERY_AUDIT_3_0_14.md` | low / tooling_and_policy（+49/-0） | 上游播放器恢复策略自查记录（来源隔离、解码恢复、引擎回退预算）。 | 纯文档；其 3.0.14/4102 版本标签与本 fork 采用的 3.0.7/4095 交付身份不同，只作为上游证据留档。 | `accept` |
| A | `docs/RECORDING_AUDIT_3_0_13.md` | low / tooling_and_policy（+67/-0） | 上游录制链路自查记录（CA 证书、分片计量、失败分类、合并清单）。 | 纯文档；3.0.13/4101 标签同样不等于本 fork 的版本身份。 | `accept` |
| A | `docs/STAGE_UPDATE_3_0_13.md` | low / tooling_and_policy（+23/-0） | 上游 3.0.13 阶段交付说明（arm64-only、API 26 依据）。 | 纯文档，留档；不与 fork Release 资产混用。 | `accept` |
| A | `docs/STAGE_UPDATE_3_0_14.md` | low / tooling_and_policy（+23/-0） | 上游 3.0.14 阶段交付说明。 | 纯文档，留档；本轮 fork 的验证记录以本审计文档为准。 | `accept` |
| M | `ios/Runner/Info.plist` | high / apple_native（+4/-0） | 新增 NSAppTransportSecurity/NSAllowsArbitraryLoads=true 与 UIBackgroundModes=[audio]。 | iOS 属社区验证范围。全局放开 ATS 是安全性下降项，本轮不改动，但已在质量评估中单列为风险。 | `accept` |
| M | `lib/common/global/initialized.dart` | medium / common_runtime（+132/-122） | 移动端 FFmpeg 预热改为首帧前同步启动（CRLF -> LF 造成大量空白差异），并抽出 @visibleForTesting shouldStartRecorderPrewarmImmediately。 | 根因是 Android 首次录制 I/O 失败；fork 未改动该文件，接受上游时序。 | `accept` |
| M | `lib/common/global/platform/desktop_manager.dart` | medium / common_runtime（+5/-2） | capturePiPGeometry 传入 player.rawVideoAspectRatio。 | 与本 fork 的 Windows 小窗/画中画共用；配合 window_helper 的竖屏几何分离，属改善项。 | `accept` |
| M | `lib/common/index.dart` | medium / common_runtime（+3/-0） | 仅新增空行。 | 无行为影响。 | `accept` |
| M | `lib/common/models/release_model.dart` | medium / common_runtime（+111/-12） | GitHub Release 解析放宽（tagName/publishedAt/html_url/assets/body/download_count/browser_download_url 容错），新增 AuthorModel.defaultAuthor()。 | 默认作者回退硬编码 liuchuancong 头像与主页；因版本历史已改指 fork 的 releases.json 且每条含 author 字段，触发概率低，记为显示层已知偏差。 | `accept` |
| M | `lib/common/services/settings/backup_controller.dart` | high / persisted_settings（+1/-1） | exportAllSettings 默认 includeSensitiveData false -> true，使备份包含 cookie 与 webdav 配置。 | 本 fork 的 WebDAV 上传、Firebase 云同步、本地备份文件、设置预览四个调用点均未显式传参，因此默认会把各平台 cookie 与 WebDAV 凭据写入备份；用户明确要求全部接受上游默认，不改调用点。fork 的 redactSensitiveData 仍是无调用死代码，backup_privacy_test.dart 只测静态脱敏函数，已不构成隐私保证。 | `accept` |
| M | `lib/common/services/settings/player_settings_controller.dart` | high / persisted_settings（+43/-29） | 新增 portraitVideoHeightMode（默认 adaptive）与 portraitCustomHeight（默认 0.0）两个 Hive 键，新增 PlayerSettingsController.to；resetMpvPlayerSettings 不再重置 portraitLayoutMode/portraitDanmakuMode。 | 均为新增键，旧安装缺键时取声明默认值，无需迁移；重置行为范围收窄属上游有意调整，记为体验变更。fromJson 未钳制 portraitCustomHeight，导入备份可写入负值，仅界面侧钳制。 | `accept` |
| M | `lib/common/services/settings/window_size_controller.dart` | high / persisted_settings（+86/-17） | WindowPipGeometry 增加竖屏一组键（windows_pip_portrait_*），clearWindowsPipGeometry 改为 clearAll()。 | 竖屏/横屏小窗几何不再互相覆盖，对本 fork 的 Windows 小窗是改善；代价是关闭记住小窗位置时连横屏几何一起清除。 | `accept` |
| M | `lib/common/utils/version_util.dart` | medium / common_runtime（+1/-0） | 仅新增 defaultAvatar 常量（上游头像 ID），更新源字段未变。 | updateOwner/updateRepository/projectUrl/releaseUrl/mirror 仍来自生成的 AppConfig，即 yanxiatao/pure_live；fork 的 test/release_asset_urls_test.dart 断言通过。 | `accept` |
| M | `lib/common/widgets/common_appbar_actions.dart` | medium / common_runtime（+11/-11） | 多画面同看入口改为受 SettingsService.to.app.enableMultiView 控制。 | fork 的 enableMultiView 默认 true，普通用户行为不变；该开关原为 fork 专有，上游直接接入。 | `accept` |
| M | `lib/core/interface/live_site.dart` | high / platform_interfaces（+36/-0） | 新增两个可选能力接口：LivePlayUrlCursorResolver（按线路惰性签名，供录制逐线重试）与 LiveSiteRecordRoomResolver（录制前严格房间查询，必须抛出传输/结构错误）。 | 以 is 探测、非强制实现，fork 无额外站点类，编译不受影响；未实现该接口的站点会静默回到旧的“瞬时错误被当作下线”路径。 | `accept` |
| M | `lib/core/site/bilibili/bilibili_site.dart` | high / platform_interfaces（+22/-6） | 实现录制专用房间解析；画质标签归一；live_status 解析放宽为字符串容错。 | 录制定时任务路径不再走 getRoomDetail，因此不会取弹幕凭据；播放路径不变。 | `accept` |
| M | `lib/core/site/cc/cc_site.dart` | high / platform_interfaces（+54/-6） | 新增 _qualitySort（档位 ×1e6 + 码率钳制），原画缺 vbr 不再沉底；CDN 直连解析只允许 http(s)，修正 ?/& 分隔。 | 画质排序变化会影响清晰度选择与录制取流，已有 test/cc_quality_parser_test.dart 覆盖。 | `accept` |
| M | `lib/core/site/douyin/douyin_site.dart` | high / platform_interfaces（+73/-18） | 画质次序改由 sdk_key 档位/level 决定、码率退为次要键，SD1/SD2 语义互换；新增 _decodeSdkParams 与按 URL 集合去重；实现录制房间解析。 | 去重会让清晰度选择器条目变少（如 FULL_HD1 与 uhd 合并）；录制候选顺序变化属预期。 | `accept` |
| M | `lib/core/site/douyu/douyu_site.dart` | high / platform_interfaces（+82/-19） | parsePlayUrl 优先级反转（rtmp_live 完整签名 URL 优先），避免把 CDN 目录当播放地址；新增离线判定与录制/游标解析接口实现。 | 与本 fork 近期修正的 douyu 搜索探测相互独立；已有 test/douyu_playback_parser_test.dart 覆盖。 | `accept` |
| M | `lib/core/site/huya/huya_site.dart` | high / platform_interfaces（+143/-40） | 画质标签归一并保留 bitRate 作为 id；新增 resolvePlayUrlAtRaw 游标解析；getRoomDetail 拆分出 allowUiFallback=false 的录制解析并显式识别 OFF/OFFLINE/CLOSED；buildAntiCode 调用点移出，改为每次取流重新签名（含 HLS 与预签名 FLV），并重写签名默认值与 wsTime 续期。 | 文本冲突（fork 侧仅把 play_config.json 的 GitHubMirror owner 从 liuchuancong 改为 yanxiatao）。合并后已确认工作树仍为 owner: yanxiatao，且该行是与上游唯一差异；重新签名使播放与录制可并发拿到不同 token。 | `adapt` |
| M | `lib/core/site/iptv/iptv_site.dart` | high / platform_interfaces（+9/-1） | 实现录制房间解析（委托 getRoomDetail，数据库即权威来源）。 | IPTV 竖屏显示与 fork 的 IPTV 解析路径不冲突。 | `accept` |
| M | `lib/core/site/kuaishou/kuaishou_site.dart` | high / platform_interfaces（+25/-3） | 录制解析在离线时只在能产出可播档位的情况下采纳推荐卡片；isLiving 接受 1/"true"；接入标签归一。 | 上游“修复快手直播源获取错误”落在该文件；传 id 含 NUL 分隔符会在标签归一里被丢弃，同名档位可能塌缩为“默认”。 | `accept` |
| M | `lib/core/site/soop/soop_site.dart` | high / platform_interfaces（+59/-12） | getPlayUrls 由 catch 返回空列表改为 rethrow；画质标识小写去重；_qualitySort 档位 ×1e8 + 码率；新增录制解析（RESULT 0/-2 显式离线/封禁，其他抛 StateError）。 | 本 fork 的 SOOP Cookie 模块与该站点的错误呈现相关：错误现在会以 Toast 暴露而不是静默；已有 test/soop_platform_test.dart 覆盖。 | `accept` |
| M | `lib/core/site/twitch/twitch_site.dart` | high / platform_interfaces（+27/-11） | chunked（源画质）sort 改为 1<<30，避免被瞬时高码率转码压过；标签归一。 | fork 的 Twitch 代理设置不受影响；断言由精确 sort 改为相对大小，覆盖面略降。 | `accept` |
| M | `lib/core/site/yy/yy_site.dart` | high / platform_interfaces（+15/-3） | resultCode 字符串容错；标签归一（id 为 gear）。 | YY 热度语义未变。 | `accept` |
| A | `lib/core/utils/live_quality_label.dart` | high / platform_interfaces（+121/-0） | 新增画质标签归一器：含 CJK 直接返回，按平台映射中文档位，再退化为分辨率/码率标签。 | 不改 id/data/sort，录制按 selectionId 取流不受影响；但 player_controller._setDefaultResolution 用显示标签匹配用户偏好，历史偏好 蓝光8M/蓝光4M 归一后可能不再命中而落到启发式默认，已记入回归计划。 | `accept` |
| M | `lib/modules/about/version_history.dart` | medium / app_modules（+21/-10） | 作者区改为强类型 ReleaseModel + CommonAvatar，github 为空时禁用跳转，抓取增加 no-cache 头并支持强制刷新。 |  releases.json 抓取源原为硬编码 liuchuancong；按“下载信息指向本 fork”要求改为 AppConfig.pureliveUpdateOwner/pureliveUpdateRepository（与 VersionUtil 同一策略）。 | `adapt` |
| M | `lib/modules/live_play/controllers/live_play_controller.dart` | high / live_playback（+9/-6） | openRecordCenter 的图层恢复由 finally 改为 catch 兜底，恢复职责交给路由观察者。 | 与 navigation_observer 的延迟恢复配套；未触及 fork 的路由级 PopScope 语义。 | `accept` |
| M | `lib/modules/live_play/dialogs/play_other.dart` | high / live_playback（+1/-1） | “其他直播间”弹层宽度 clamp(200,400)。 | 小屏适配改善，fork 未改该文件。 | `accept` |
| M | `lib/modules/live_play/widgets/button/record_action_button.dart` | high / live_playback（+5/-10） | 改为 addTask(room, startImmediately: true)，去掉 addTask + forceStartTask 两个竞争启动意图。 | 与录制控制器新签名一致；监控入口仍用 startImmediately: false。 | `accept` |
| M | `lib/modules/live_play/widgets/layout/live_play_content.dart` | high / live_playback（+66/-65） | showPanel=false 时直接渲染全黑视频（跳过 LayoutBuilder 分支）；竖屏/桌面构建移出 LayoutBuilder；两处 Scaffold.body 移除 SafeArea。 | 本 fork 最高风险的不变量区域：竖屏普通页需同时可见顶栏、视频、清晰度/线路入口与弹幕列表。SafeArea 改由 LivePlayVideoFrame 在 expandToMobile 时处理，底部导航条与状态栏避让需设备采样；现有 content_first_panel_layout / live_play_navigation_ui 确定性测试通过。 | `accept` |
| M | `lib/modules/live_play/widgets/layout/live_play_shell.dart` | high / live_playback（+32/-2） | 新增 showPanel 参数，false 时只挂视频宿主。 | 与 content 层联动，纯表达层，不销毁会话。 | `accept` |
| M | `lib/modules/live_play/widgets/layout/live_play_video.dart` | high / live_playback（+27/-8） | expandToParent 在移动端改为按 PortraitVideoHeightMode（adaptive 带 SafeArea(top)/custom 固定高/full）计算，删除旧 v3.0.1 注释。 | 刘海屏适配即上游 3.0.7 描述项；与 fork 的小屏选择其他直播间功能叠加，需竖屏采样。 | `accept` |
| M | `lib/modules/live_play/widgets/video_player/video_controller.dart` | high / live_playback（+80/-8） | initPlayerListener 提前到播放等待之前（修复原生同步终态错误被丢弃导致界面假“播放中”）；状态由 hasError/isPlayingNow 推导；onPlaying/onLoading 加 distinct；错误 Toast 按消息签名 2 秒去重；新增 enterLandscapeFullScreen / applyFullscreenOrientationPolicy。 | 强化了 fork 的“以播放器真正打开成功为提交点”不变量；错误去重只压制 Toast，状态仍为 error。 | `accept` |
| M | `lib/modules/live_play/widgets/video_player/video_player.dart` | high / live_playback（+54/-133） | _DelayedVideoWidget（20ms 定时器 + 重建视频子树）替换为无状态 StableVideoLayer（Android 保持离屏挂载，Windows 覆盖路由时卸载纹理），并删除 _VideoPlayerState 的 WidgetsBindingObserver。 | 文本无冲突但存在语义冲突：观察者删除后 PlayerManager.commitAudioOnlyPowerSaving / prepareAudioOnlyVideoRestore 变成无调用死代码，且“不应后台续播时自动暂停 / 回前台恢复”一并丢失（live_play_controller 的生命周期回调只处理弹幕呈现恢复）。按用户决定在 StableVideoLayer 版本上重新接回观察者与三段逻辑，其余上游改动保留。 | `adapt` |
| M | `lib/modules/settings/pages/font_family_manager_page.dart` | medium / app_modules（+6/-3） | 应用按钮配色 primary/onPrimary -> primaryContainer/onPrimaryContainer。 | 纯对比度修正。 | `accept` |
| M | `lib/modules/settings/pages/navigation_settings_page.dart` | medium / app_modules（+10/-13） | 多画面同看开关从仅 Windows 显示改为全平台显示。 | fork 的 multiview 此前只在桌面暴露入口，Android 现在也可见；需确认移动端布局档位与音频焦点互斥在手机上可用，列入设备采样。 | `accept` |
| M | `lib/modules/settings/pages/portrait_live_settings_page.dart` | medium / app_modules（+190/-5） | 新增移动端竖屏视频高度模式（自适应/自定义/充满）与自定义高度对话框、预设高度筹码，并接入重置项。 | 与 fork 的“增加小屏选择其他直播间”同页共存；重置入口只清高度模式，不清 fork 的竖屏布局/弹幕模式（见 player_settings_controller 条目）。 | `accept` |
| M | `lib/modules/settings/pages/video_settings_page.dart` | medium / app_modules（+1/-1） | 仅两行 import 顺序。 | 无行为影响。 | `accept` |
| M | `lib/player/adapters/fijk_adapter.dart` | high / live_playback（+285/-280） | 整文件 CRLF -> LF（+285/-280 绝大部分为空白差异），实质改动两处：原生错误监听加 print，改调用重命名的 setFijkOption(enableHardwareCodec:)。 | 未填 PlayerException.code；print 而非 Log，属上游日志习惯。 | `accept` |
| M | `lib/player/adapters/media_kit_adapter.dart` | high / live_playback（+16/-11） | applyNativeLiveProperties 协议白名单增加 rtmp/rtmps/rtsp/srt，删除 demuxer-lavf-analyzeduration=2，新增 hwdec-software-fallback=1；stop() 不再 seek 到 0。 | 该静态属性被 fork 的多画面同看每个格子共用，探测变慢会拉长黑屏窗口、软解回退更快；已在校验中单列。 | `accept` |
| M | `lib/player/core/audio_stream_loader.dart` | high / live_playback（+5/-2） | 迁移到 buildAudioStreamArguments(..., caFile: FFmpegManager.to.caFilePath) 与新 FFmpegService.start(arguments:)。 | 音频-only 录制同样受内置 CA 影响，无额外 fork 冲突。 | `accept` |
| M | `lib/player/core/engine_fallback_manager.dart` | high / live_playback（+9/-4） | maxRetryCount 默认 2 -> 1（并 clamp(1,100)），优先级列表改集合并去重。 | 根因是多数引擎只回调一次终态，等待第二次会卡在错误态；代价是首次确认失败即切引擎。fork 的 multiview 不构造该管理器，仅主播放器受影响。 | `accept` |
| M | `lib/player/core/playback_header_resolver.dart` | high / live_playback（+133/-41） | if 链改为 10 平台穷尽 switch；roomId 做 Uri.encodeComponent；Huya UA 直接读进程内 HuyaSite.playUserAgent（不再发网络请求）；bilibili 生成匿名 buvid 兜底；头名白名单与 CR/LF/NUL 清洗；返回不可变映射。 | 播放、多画面同看与录制三条路径共用该解析器；首次进入即读不到 UA 时可能为空，属可接受降级。 | `accept` |
| M | `lib/player/core/player_manager.dart` | high / live_playback（+95/-15） | 新增 _isCurrentPlayerSession(player, sessionId)，所有适配器订阅（onPlaying/onLoading/onComplete/onStateChanged/onError/宽高/竖屏）都同时校验 sessionId 与当前实例；_switchEngineInternal 重排为“创建 -> 赋当前 -> 置位并提升呈现版本 -> 清订阅 -> 绑定 -> 销毁旧实例”；新增 Windows 画中画 100ms 去抖几何更新。 | fork 的画中画/小窗复用同一 PlayerManager，呈现版本与 videoKey 递增可被 fork 观察者消费；旧实例错误事件在换实例后被守卫丢弃，是已记录的残留风险。 | `accept` |
| M | `lib/player/core/player_session.dart` | high / live_playback（+94/-0） | 空文件补上 PlayerSession（含 audioOnly）、PlayRequest 与 PlayRequestStatus（含 30 秒有效期校验）。 | 文本冲突：fork 侧只多一个换行。取上游内容；该文件在 lib/ 与 test/ 内目前无任何引用，属未接线的脚手架，不改变现有会话机制（仍为 PlayerManager 私有 _sessionId）。 | `accept` |
| M | `lib/player/core/portrait_stream_support.dart` | high / live_playback（+5/-0） | 新增 enum PortraitVideoHeightMode { adaptive, custom, full }。 | 供竖屏高度设置与 live_play_video 消费。 | `accept` |
| M | `lib/player/interface/fijk_player_accessor.dart` | high / live_playback（+1/-1） | 仅补文件末尾换行。 | 无行为影响。 | `accept` |
| M | `lib/player/models/player_exception.dart` | high / live_playback（+5/-1） | 新增可选机器可读 code 字段。 | 目前无赋值方，恢复策略仍解析本地化文本，记为上游未完成项。 | `accept` |
| M | `lib/player/utils/fijk_helper.dart` | high / live_playback（+70/-63） | enableCodec 重命名为 enableHardwareCodec 且默认值 true -> false；新增 start-on-prepared=0、overlay-format、min-frames=50、framedrop=0、reconnect_delay_max=5，超时 30s -> 15s，显式协议白名单；headers 为空时不写选项。 | 与“还原ijk/replace ijk”两个提交配套；start-on-prepared=0 需与 fijk 的 autoPlay:true 组合验证 Android 实际起播，framedrop=0 在弱网可能累积延迟，列入设备采样。 | `accept` |
| M | `lib/player/utils/window_helper.dart` | high / live_playback（+33/-15） | Windows 小窗几何按横竖屏分别存取（ratio<0.95 走 pip.portrait*），capturePiPGeometry 接收 videoRatio。 | 直接改善 fork 的 Windows 小窗在竖屏房间下几何互相覆盖的问题。 | `accept` |
| A | `lib/recorder/ffmpeg/android_ca_certificate_manager.dart` | high / recording_and_storage（+123/-0） | 新增：把 assets/cacert.pem 解到应用支持目录（临时文件 + 重命名、≥1024B 与 PEM 标记校验），缓存为静态 Future。 | 失败结果会被永久缓存（仅 clearCache 可复位），是已记录的健壮性风险。 | `accept` |
| M | `lib/recorder/ffmpeg/ffmpeg_command_builder.dart` | high / recording_and_storage（+281/-112） | 字符串命令改 argv 列表；-y -> -n；分片命名 %Y%m%d_%H%M%S.ts -> <prefix>_%06d.ts 并显式 -segment_start_number 0；协议白名单扩展；analyzeduration/probesize 提到 5M；-fflags 改 +genpts+discardcorrupt；新增 -ca_file、按协议分支选项与多项钳制；头名小写化并清洗 CR/LF。 | 与旧命名分片不兼容（仅崩溃恢复允许 legacy 合并）；-n 叠加 file exists 致命标记使前缀冲突无法自动恢复；新重连选项要求较新 FFmpeg，老 kit 会归为不可重试。 | `accept` |
| M | `lib/recorder/ffmpeg/ffmpeg_manager.dart` | high / recording_and_storage（+35/-21） | 新增 _caFilePath 与 initialize()（含 CA 预检），start() 接受 argv 列表与 liveRecording 标志；大量 CRLF 噪声。 | CA 预检失败会让整个录制子系统不可用。 | `accept` |
| M | `lib/recorder/ffmpeg/ffmpeg_scheduler.dart` | high / recording_and_storage（+55/-13） | Future.delayed 改为可跟踪 Timer（修复重复调度与 _isScheduling 不复位）；cancel()/clearAll() 以 20s 超时等待任务；TaskCancelToken.onCancel 支持晚注册闭包。 | clearAll 不再先清 _runningTasks，晚注册取消走 unawaited，存在越过 isCancelled 检查的窗口。 | `accept` |
| M | `lib/recorder/models/live_record_task.dart` | high / recording_and_storage（+456/-311） | 整体重写：宽松类型转换、枚举按名持久化并按索引回退、新增 selectedQualityId/selectedLineIndex/lastError/lastErrorStage、currentUrl 不再持久化且读取时强制置空、beginNewRecording 与 beginNewAttempt 拆分并引入毫秒级 recordingFilePrefix。 | 写出的 schemaVersion 为 4，而上游自带断言为 3（合并后已按模型改测试）；旧安装的录制 JSON 无 schemaVersion，读侧靠容错回退，不阻塞。 | `adapt` |
| M | `lib/recorder/pages/recorder/recorder_controller.dart` | high / recording_and_storage（+914/-699） | 约 900 行实质变更：以会话 id 守卫所有 FFmpeg 事件；改为按磁盘分片计数（1s Timer + O(1) 跟踪）作为体积/码率/秒数真值并重连与轮询分离、指数退避有界；_finalizationFutures 去重；addTask 返回任务并可立即启动；按条目恢复中断录制并重合并；onClose 统一取消计时/订阅与 scheduler.clearAll()；删除私有路径守卫与 updateTask 排序。 | 事件监听是 async + unawaited（可重入），合并状态改由调度槽内 await convertToMp4 回传；_doFinalizeAttempt 会在收尾完成前结束生命周期。fork 未改动录制控制器，接受上游实现。 | `accept` |
| M | `lib/recorder/pages/recorder/recorder_page.dart` | high / recording_and_storage（+146/-41） | 可滚动 TabBar 改 RecorderStatusSelector 网格、TabBarView 禁止滑动、任务列表按状态优先级排序、线路筹码与 Mbps 格式化、失败阶段与错误面板。 | 新增 recorder_stage_*、recorder_last_error 文案键；_getStatusPriority 需与 RecordStatus 保持穷尽。 | `accept` |
| M | `lib/recorder/services/cache_service.dart` | high / recording_and_storage（+62/-8） | 目录保护引用计数（protectDirectory/releaseDirectory），受保护路径不参与 clearAll/deleteOldest/enforceLimit；clearAll 改为递归并自底向上清理空目录；Windows/macOS 大小写折叠。 | 任务被丢弃而不 release 会永久阻止缓存清理，属残留风险。 | `accept` |
| M | `lib/recorder/services/ffmpeg_service.dart` | high / recording_and_storage（+437/-173） | 新增 FFmpegFailureClassifier（8 类 × 是否可重试）与终态判定（live 代码 0 或 -541478725 视为意外 EOF、可重试、不算完成）；按 argv 建会话；started 仅在首次真实统计后置位；startAck；有界诊断环形缓冲（120 行/12k 字符）且对 URL/cookie/token 脱敏；重复启动抛 StateError；stop() 10s 超时。 | decoder 桶按含 “codec/decode” 判定易误分类；一直不产出统计的会话不会报告 started。 | `accept` |
| M | `lib/recorder/services/recorder_continuation_policy.dart` | high / recording_and_storage（+50/-2） | invalid argument / no such file 从致命标记移除，新增 option/protocol/muxer/file exists；提供 pollingDelay 与 reconnectDelay（指数上限 20）及重试上限后转轮询判定。 | unexpectedEof 不进入轮询，永久 EOF 的房间会以 ≤15s 间隔无限重连。 | `accept` |
| A | `lib/recorder/services/recorder_diagnostics.dart` | high / recording_and_storage（+28/-0） | 新增诊断文本脱敏与有界缓冲工具。 | 持久化时一并脱敏，降低 cookie 泄漏面。 | `accept` |
| A | `lib/recorder/services/recording_output_metrics.dart` | high / recording_and_storage（+148/-0） | 新增全量测量与 RecordingOutputTracker（按 %06d.ts 顺序采样，O(1)）以及单次尝试累计进度。 | 仅识别 .ts 且严格 6 位序号，旧命名分片不参与。 | `accept` |
| M | `lib/recorder/services/stream_resolver_service.dart` | high / recording_and_storage（+360/-99） | 返回 ResolvedRecordStream（url/quality/qualityCursorId/lineIndex/candidateUrls）；单尝试游标推进（同画质下一线路 -> 下一画质首线 -> 回绕）、按 selectionId 去重、sort 降序 + 标签/比例匹配；封禁/回放/未知状态分支；scheme 白名单与去签名流标识；站点解析可注入。 | 未实现游标接口的站点退化为仅画质轮转；candidateUrls 目前控制器未使用。fork 未改该文件。 | `accept` |
| M | `lib/recorder/services/video_processor_service.dart` | high / recording_and_storage（+289/-210） | 合并只取本次尝试前缀的分片（崩溃恢复才允许 legacy）；改写 ffconcat version 1.0 清单并转义引号反斜杠；输出 .partial 后改名并处理冲突；合并超时按输入体积与时长动态计算（30s..3600s）；支持 cancel() 与 finally 清理。 | 取消只在终态事件后被观察到；进度分母使用 task.recordedSeconds；_uniqueOutputFile 循环无上界。 | `accept` |
| A | `lib/recorder/widgets/recorder_bounded_scroll.dart` | high / recording_and_storage（+186/-0） | 新增 RecorderStatusSelector（3/5/N 列自适应网格，绑定 DefaultTabController）与 RecorderBoundedTaskList（夹紧物理滚动 + 帧后边界校正）。 | 自管理 ScrollController 释放。 | `accept` |
| M | `lib/routes/navigation_observer.dart` | high / navigation_and_startup（+21/-3） | kRecordPage 的 didPop 不再立即显示视频图层，改为等待路由完全退出 + 一个 endOfFrame 再 updateUI(displayVideoLayer: true)。 | 修复 flutter_windows.dll 访问越界；与 StableVideoLayer 配对；不涉及返回/PopScope 语义，fork 的 live_play_back_scope 与 multiview PopScope 未被触及。 | `accept` |
| M | `plugins/flame_barrage/pubspec.lock` | high / dependencies_and_vendored（+25/-25） | 25 处 hosted 源由腾讯镜像改为 pub.dev，版本零变化。 | 按 fork 环境统一使用腾讯镜像的决定回退为基线内容（版本与上游一致，仅 url 还原）。 | `adapt` |
| M | `pubspec.lock` | high / dependencies_and_vendored（+320/-320） | 13 个包补丁级升级、全部 hosted 源由腾讯镜像改为 pub.dev；git 依赖与 resolved-ref 未变。 | 上游锁文件自身不可 --enforce-lockfile（android_file_picker 锁 1.0.2 但解析要求 1.0.3）。已用镜像重新解析并提交镜像 URL 的锁文件：本地 enforce 通过，远端 pub.dev 仍按锁定版本解析；代价是镜像缺 3 个新版本（shared_preferences_android 2.4.27、url_launcher_android 6.3.32、url_launcher_windows 3.1.5 比上游锁低一档）。 | `adapt` |
| M | `pubspec.yaml` | high / dependencies_and_vendored（+3/-1） | 版本 3.0.4+4092 -> 3.0.7+4095；新增 schemastore 注释；把 assets/cacert.pem 加入 flutter assets。 | 与 fork 采用的 3.0.7/4095 身份一致。 | `accept` |
| A | `test/app_initializer_recorder_policy_test.dart` | low / tests（+9/-0） | 新增：断言移动端首帧前同步预热 FFmpeg。 | 与 initialized.dart 改动配对。 | `accept` |
| A | `test/cc_quality_parser_test.dart` | low / tests（+56/-0） | 新增：CC 档位排序与 javascript: 方案丢弃。 | 覆盖 cc_site 变更。 | `accept` |
| M | `test/douyin_playback_parser_test.dart` | low / tests（+81/-0） | 扩展：sdk_key 档位排序、URL 集合去重、中文标签。 | 覆盖 douyin_site 变更。 | `accept` |
| M | `test/douyu_playback_parser_test.dart` | low / tests（+11/-0） | 扩展：优先取完整签名 URL、离线判定。 | 覆盖 douyu_site 变更。 | `accept` |
| A | `test/engine_fallback_manager_test.dart` | low / tests（+43/-0） | 新增：一次确认失败即切引擎、显式预算 2 时先保持同引擎、优先级从用户引擎起算。 | 与 maxRetryCount 1 的新默认一致。 | `accept` |
| A | `test/ffmpeg_failure_classifier_test.dart` | low / tests（+43/-0） | 新增：输出/输入侧错误、403/TLS/格式/解码分类与 -2 不误判。 | 覆盖 FFmpegFailureClassifier。 | `accept` |
| M | `test/ffmpeg_record_command_test.dart` | low / tests（+87/-12） | 重写为 argv 断言：精确 -i、无引号、钳制、分协议选项、头注入失效、formatArguments 不改入参。 | 覆盖 ffmpeg_command_builder。 | `accept` |
| A | `test/ffmpeg_scheduler_cancel_token_test.dart` | low / tests（+20/-0） | 新增：晚注册的 onCancel 恰好触发一次。 | 覆盖 TaskCancelToken。 | `accept` |
| M | `test/huya_play_url_test.dart` | low / tests（+8/-0） | 扩展：重新签名（seqid/wsTime 续期）与离线状态。 | 覆盖 huya_site 变更；fork 的 UA 镜像行不受影响。 | `accept` |
| A | `test/live_quality_label_test.dart` | low / tests（+31/-0） | 新增：标签归一映射与 CJK 早退。 | 覆盖 live_quality_label。 | `accept` |
| A | `test/live_record_task_persistence_test.dart` | low / tests（+120/-0） | 新增：枚举按名持久化、损坏数据回退、毫秒前缀、URL 不落盘、诊断脱敏。 | 上游自带断言 schemaVersion==3 与模型写出的 4 冲突，合并后完整回归首次运行即失败；已按模型改为 4（该字段无读侧分支）。 | `adapt` |
| M | `test/playback_header_resolver_test.dart` | low / tests（+23/-0） | 扩展：9 个 HTTP 平台 origin/referer/UA 确定性、头名小写、值不含换行。 | 覆盖 playback_header_resolver。 | `accept` |
| M | `test/recorder_continuation_policy_test.dart` | low / tests（+35/-0） | 扩展：新增致命标记、退避有界与上限后轮询。 | 覆盖 continuation policy。 | `accept` |
| M | `test/recorder_storage_policy_test.dart` | low / tests（+40/-0） | 扩展：受保护目录不被 enforceLimit/clearAll 清除、引用计数。 | 覆盖 cache_service。 | `accept` |
| A | `test/recording_platform_contract_test.dart` | low / tests（+12/-0） | 新增：要求 Sites.supportedSiteIds 全部 10 个站点实现 LiveSiteRecordRoomResolver。 | fork 未新增站点类，10 个实现齐备，测试通过；未来 fork 若加站点需同步实现。 | `accept` |
| M | `test/soop_platform_test.dart` | low / tests（+5/-3） | 扩展：错误改为 rethrow、档位小写去重。 | 覆盖 soop_site。 | `accept` |
| M | `test/twitch_playback_parser_test.dart` | low / tests（+21/-2） | 扩展：源画质 sort 高于转码；由精确 sort 改为相对大小断言。 | 覆盖 twitch_site，断言强度略降。 | `accept` |
| A | `test/video_processor_manifest_test.dart` | low / tests（+37/-0） | 新增：清单转义与本次尝试/legacy 分片选择。 | 覆盖 video_processor_service。 | `accept` |
| M | `third_party/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/VideoOutput.java` | high / dependencies_and_vendored（+382/-86） | 整体替换为新版 Surface/WID 管理（252 -> 548 行）：新增 SurfaceProducer 路径、disposed 守卫、WID 释放延迟 5000ms。 | vendored 第三方插件补丁，随上游走；影响 Android 视频纹理生命周期，与 fork 的多画面同看共用同一插件实现，列为需要设备采样确认的点。 | `accept` |
| M | `tool/prefetch_android_native.ps1` | low / tooling_and_policy（+101/-10） | 新增按锁文件推导 FFmpeg 原生包版本与 builder profile 映射（0.5.13 -> 0.10.5、0.6.0 -> 0.11.0）及 Windows 解包缓存重置。 | 当前锁为 0.6.0，哈希与既有值一致；锁版本无已审 profile 时直接抛错。 | `accept` |
| A | `tool/update_actions_sha.py` | low / tooling_and_policy（+225/-0） | 新增：把已按 40 位提交固定的 uses 行重新解析为标签并刷新注释。 | 它跳过非 SHA 引用，无法修复可变标签；也未接入任何工作流，本轮不作为门禁。 | `accept` |
| M | `tool/validate_build_policy.ps1` | low / tooling_and_policy（+7/-0） | 新增两条门禁：Android minSdk 必须为 26；清单不得含 ffmpeg_kit 的 overrideLibrary。 | 与本 fork 既有串行阶段、签名、资源守卫检查并存且同时可满足；fork 侧的 publishNeedsPattern（要求 publish-release 依赖 quality/android/windows/linux）在合并结果中仍然成立。 | `accept` |
| A | `tool/verify_actions_sha.py` | low / tooling_and_policy（+147/-0） | 新增：校验 workflow 内固定提交是否可达。 | 同样忽略可变引用，未接入工作流。 | `accept` |
| M | `windows/packaging/msix/make_config.yaml` | high / windows_native（+1/-1） | msix_version 3.0.4.4092 -> 3.0.7.4095。 | 与 fork 采用的 3.0.7/4095 身份一致，发布者与签名配置未变。 | `accept` |

## semantic_change_ledger

每个入站提交一行；`upstream intent / before → after`、`implementation`、`quality_assessment`、`fork_feature_impact`、`regression_plan` 按提交聚合到其落点文件（详见 file_review 对应行）。`issue_and_bug_mapping` 列给出来源分类：本批全部为上游自身演进，无本 fork Issue 直接对应，冲突项分类见下表与 conflict_resolution。

| commit | file / module | upstream intent / before → after | issue_and_bug_mapping | disposition |
| --- | --- | --- | --- | --- |
| `213cbbf449293350342e3b520c7a521ffa5d3a44` | persisted_settings | exportAllSettings 默认 includeSensitiveData 改为 true，使备份/同步携带 cookie 与 WebDAV 配置。（原始信息：修复: 更新exportAllSettings方法的includeSensitiveData默认值为true） | external-drift（上游自身行为） | `accept` |
| `5a158989e20b310b1ec58231ea32bcd7be4cc39e` | live_playback/windows | Windows 小窗几何按横竖屏分离存取，避免竖屏房间覆盖横屏矩形。（原始信息：feat: 增强画中画功能，支持竖屏模式下的窗口几何更新） | external-drift（上游自身行为） | `accept` |
| `7626dc9d91ac25ff04e2a5f330771610998abb4f` | app_modules | 顶栏多画面同看入口改由 enableMultiView 控制。（原始信息：feat: 根据设置条件动态显示多视图选项） | external-drift（上游自身行为） | `accept` |
| `b315109f88c7489bb3b10438c5f8fa4c8297c342` | workflows_and_release | 版本推进 3.0.5 并修描述与下载链接。（原始信息：fix: 更新版本号至3.0.5，修复相关描述和下载链接） | external-drift（上游自身行为） | `accept` |
| `31929bdb826c595f4cb7a69d1a2375b99428b052` | workflows_and_release | 版本推进 3.0.5。（原始信息：fix: 更新版本号至3.0.5） | external-drift（上游自身行为） | `accept` |
| `2136a2e24005bd7ee9251d79e5803a57a499d76c` | recording_and_storage | 录制流与画质选择加固：会话 id 守卫、按磁盘分片计量、游标式线路推进。（原始信息：fix(recorder): harden streams and quality selection） | external-drift（上游自身行为） | `accept` |
| `7910d2125972cb0bfb81a730ddc4ff3dc3eeaaf7` | workflows_and_release | CI 再生成 v3.0.5 发布索引。（原始信息：chore: update releases.json for v3.0.5 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `d35fee6530a84f658c85aa87fd30f8953929b173` | app_modules/recording | 字体管理按钮配色对比度修正；FFmpeg 增加 Android TLS 校验选项。（原始信息：fix(font): 更新按钮颜色以适应主题容器，增强可读性 fix(ffmpeg): 添加Android平台的TLS验证选项） | external-drift（上游自身行为） | `accept` |
| `63ae94ad2d9e6cfa7b91bbf0a8d394549ca15d23` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `f0c0fbf021b158f73a32e588adebaefdab3d2ee7` | live_playback | 新增 showPanel，纯视频站点不再预留空白面板。（原始信息：feat(live_play): 添加 showPanel 属性以控制面板显示） | external-drift（上游自身行为） | `accept` |
| `a22160e99189d98b1f9bb8107c667ed72917ef10` | live_playback | 提高 media_kit demuxer analyzeduration 以改善直播流探测。（原始信息：fix(media_kit): 增加 demuxer-lavf-analyzeduration 属性值以优化直播流解析） | external-drift（上游自身行为） | `accept` |
| `a2d34d6005abba85d480c1c088ead6afce771ca1` | workflows_and_release | 版本推进 3.0.6。（原始信息：chore: 更新版本号至 3.0.6，调整相关配置文件以匹配新版本） | external-drift（上游自身行为） | `accept` |
| `f0401db7b488e1624c113a7de2de42a6d3aa9388` | workflows_and_release | version_desc 改为带版本号的格式。（原始信息：fix(version): 更新版本描述格式，添加版本号和更新信息） | external-drift（上游自身行为） | `accept` |
| `59d6ecb196ad909857d5080ceed87437b7e2c192` | android_native/recording | 各平台录制启动加固并把 minSdk 固定为 26、移除 overrideLibrary 绕过。（原始信息：fix(recorder): harden all platform capture startup） | external-drift（上游自身行为） | `accept` |
| `63e43634bdf7328d387977c03e20f35fbfad13eb` | workflows_and_release | CI 再生成 v3.0.6 发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `a724764fd15a1c6506cf5ad24de22f190cc0b356` | live_playback/recording | 宽泛的性能与健壮性改动（提交信息未细化），实际内容并入录制/播放器同批文件审查。（原始信息：Implement code changes to enhance functionality and improve performance） | external-drift（上游自身行为） | `accept` |
| `db55c1b45a30dfcc48921df88c2e50f8df9209e5` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `c6a4c735f3046c7bba3103f1fc7c7681544acd35` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `01358dc65b6c2d4a9350afae8a5cb92922cfb305` | live_playback | 移除 media_kit 上不必要的直播探测属性。（原始信息：fix(media_kit_adapter): remove unnecessary property for live stream analysis） | external-drift（上游自身行为） | `accept` |
| `536737231632dfb9c87b719ec1f8a616f87571d0` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `6584fa659a5061e61ffdbc948f721c2adea35ff2` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `200beb88b90bb376e5510f68db625314a8e1de21` | recording_and_storage | FFmpeg 命令构建简化为 argv 并改善参数处理。（原始信息：refactor(ffmpeg_command_builder): simplify command building and improve argument handling） | external-drift（上游自身行为） | `accept` |
| `81fa899413d1512c73eafea88ec3e45b855ca67d` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `97c665621784fa90baad0f7f6531068f014888d1` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `a6a57153d4670d7662d6aefd2c68daac2a3ea167` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `430fcdbecc58ec7bc90dd61b1a475d84e4b3cf39` | recording_and_storage | 头部处理与参数格式化整理。（原始信息：refactor(ffmpeg_command_builder): streamline header handling and improve argument formatting） | external-drift（上游自身行为） | `accept` |
| `8fd0a4506cb6c2658bbe7dc52305015f136b23e4` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `6bdf38e11b42481497b0a3a93c3ec4739adec5c0` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `2e1fcd31ef1f764ea01deba9486b5fabd5c20948` | live_playback | 播放器来源与解码恢复加固（监听绑定顺序、状态推导、错误去重）。（原始信息：fix(player): harden source and decoder recovery） | external-drift（上游自身行为） | `accept` |
| `8b7a001c1a76f43faeb039e8b7d0d0c34802e100` | live_playback | 按当前播放器实例校验会话，避免旧实例事件污染新会话。（原始信息：fix(player): improve session validation for current player） | external-drift（上游自身行为） | `accept` |
| `5d73fbdacb6c6821fd4d08b517ec59bbe57fb527` | recording_and_storage | 音频流命令与参数处理增强。（原始信息：fix(ffmpeg_command_builder): enhance audio stream command and argument handling） | external-drift（上游自身行为） | `accept` |
| `a218922bf837b22a6075db54c296912fa60b2584` | live_playback | 移除直播处理上不必要的 media_kit 属性。（原始信息：fix(media_kit_adapter): remove unnecessary properties for live stream handling） | external-drift（上游自身行为） | `accept` |
| `e696bb79e28c5c09f1e6e03264ededce69b9266e` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `5834cb21466ec91f130c1f81c2017431710d025a` | dependencies_and_vendored | ffmpeg_kit_extended_flutter 回退到 0.5.3。（原始信息：fix(pubspec): ffmpeg_kit_extended_flutter to 0.5.3） | external-drift（上游自身行为） | `accept` |
| `fa4ec2a5ec17eab9aa1326e482e7aa55ebf705bf` | dependencies_and_vendored | ffmpeg_kit_extended_flutter 推进到 0.5.7。（原始信息：fix(pubspec): update ffmpeg_kit_extended_flutter to 0.5.7） | external-drift（上游自身行为） | `accept` |
| `7de0fe0b11c878f7e920305a2017de1d023c2ca4` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `870e1cf3d950bdd335f1ac4bb0814bdb08243ca9` | live_playback | 手工调整 media_kit_adapter 直播属性。（原始信息：更新 media_kit_adapter.dart） | external-drift（上游自身行为） | `accept` |
| `9fffef35356beb89d9bae6dc32accfa45d0a8302` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `5bf2979e66a671b3a4259c3c0003f71a1938084f` | workflows_and_release | CI 再生成发布索引。（原始信息：chore: update releases.json for v3.0.6 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `9b1c0a6ee0c469e1363fbb214ad7abf26f775a27` | workflows_and_release | 上游把发布回滚到 3.0.5（其版本自述与 3.0.13/3.0.14 文档因此漂移）。（原始信息：回滚至3.0.5） | external-drift（上游自身行为） | `accept` |
| `82aa7a747c1560a52ed9fff8a52ab8cf3bd1411c` | recording_and_storage/windows | 合并超时按输入规模计算；录制页状态选择器与有界列表；路由退出后恢复视频图层以避免 Windows 越界；依赖升到 0.6.0；删除过期测试；改进 media_kit_video 的 Surface/WID 释放。（原始信息：feat(video_processor): enhance merge timeout calculation based on input size and duration feat(recorder): add RecorderStatusSelector and RecorderBoundedTaskList for improved UI fix(navigation_observer): restore video layer after route exit to prevent access violations chore(deps): update ffmpeg_kit_extended_flutter to version 0.6.0 refactor(tests): remove obsolete recorder_stream_resolver_test fix(media_kit_video): improve Surface/WID management and cleanup logic） | external-drift（上游自身行为） | `accept` |
| `1938117718ae542833c963eec1827abeab7c2e3a` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `6b8760f0007e7a7093e2452aa44f9c269b088368` | recording_and_storage | 录制任务列表按状态优先级排序。（原始信息：feat(recorder_page): add task status priority sorting in task list） | external-drift（上游自身行为） | `accept` |
| `41c8343e748be601a68d003dcf61203bad2d3efc` | live_playback | openRecordCenter 注释与错误处理改进（finally -> catch 兜底）。（原始信息：fix(live_play_controller): improve comments and error handling in openRecordCenter method） | external-drift（上游自身行为） | `accept` |
| `f5b84b2b07c3e1bed95ab4cf8455068e348e1822` | live_playback | 播放器错误处理与状态管理增强。（原始信息：feat(video_controller): enhance player error handling and status management） | external-drift（上游自身行为） | `accept` |
| `5fb45f77ce09a43429d69b93c3a66ab55dcd197b` | android_native | debug 构建类型在有 key.properties 时改用 release 签名配置。（原始信息：fix(build.gradle.kts): update debug build type to use release signing configuration） | external-drift（上游自身行为） | `accept` |
| `4b54e8e9eabe6a858a34ce0be0b450d613bf32d1` | recording_and_storage | 修复 Android 证书导致的录制失败（内置 CA 与 -ca_file）。（原始信息：修复证书导致的android 录制失败） | external-drift（上游自身行为） | `accept` |
| `e2fba23e786ae958505bea02f555fadf33d72e34` | recording_and_storage | 移除 caFile 调试 print。（原始信息：fix(ffmpeg_command_builder): remove debug print statements for caFile） | external-drift（上游自身行为） | `accept` |
| `9dea1a36ebd533f6d6623c200e09801fc9689dc2` | live_playback | replace ijk：调整 fijk 选项与错误日志。（原始信息：replace ijk） | external-drift（上游自身行为） | `accept` |
| `323b4519a1f839aa9200c2bb38b77daaec908f67` | live_playback | PlayerSession 增加 audioOnly 并补 PlayRequest 管理（当前无调用方）。（原始信息：feat(player_session): add audioOnly property and enhance PlayRequest management） | external-drift（上游自身行为） | `accept` |
| `f90f3a1cf1fa6a9b986d56e18b8885fea4dd5d3d` | workflows_and_release | release 3.0.7：版本与更新说明落盘。（原始信息：release 3.0.7） | external-drift（上游自身行为） | `accept` |
| `23133c7f7218fc0f04726a7eaeed68791f32476d` | workflows_and_release | 工作流默认标签推进 v3.0.7。（原始信息：chore: update default release tag to v3.0.7） | external-drift（上游自身行为） | `accept` |
| `3da5b41622a8282af324ad496d96d832fface834` | live_playback | 还原 ijk 相关改动。（原始信息：还原ijk） | external-drift（上游自身行为） | `accept` |
| `dd4108eace5ce870b0b3fdd50734d4d0bdf0e5ad` | workflows_and_release | CI 再生成 v3.0.7 发布索引。（原始信息：chore: update releases.json for v3.0.7 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `4e0ba055a18d739ff0eaccdce84ebea66e25901c` | live_playback | fijk_helper 扩展 setFijkOption 选项与错误处理；fijk_adapter 增加原生错误日志并调整 codec 选项。（原始信息：feat(fijk_helper): enhance setFijkOption with additional options and improve error handling fix(fijk_adapter): add logging for native errors and update codec option handling） | external-drift（上游自身行为） | `accept` |
| `5f601f1f0babbbc7905b000f2d6b3aeda96d3091` | history | 上游内部合并提交，无独立内容。（原始信息：Merge branch 'master' of https://github.com/liuchuancong/pure_live） | external-drift（上游自身行为） | `accept` |
| `36dae5c9ff078102a8d8a803fe42e92bc51858cb` | workflows_and_release | CI 定时再生成发布索引。（原始信息：chore: 定时更新 releases.json 数据 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `f87f04a492a277061e58614389af3634bdc1cd08` | workflows_and_release | CI 再生成 v3.0.7 发布索引。（原始信息：chore: update releases.json for v3.0.7 [skip ci]） | external-drift（上游自身行为） | `accept` |
| `f9238cffdd2f06239d65c635aecc70e530b5357e` | workflows_and_release | CI 定时再生成发布索引（冻结点）。（原始信息：chore: 定时更新 releases.json 数据 [skip ci]） | external-drift（上游自身行为） | `accept` |

## issue_and_bug_mapping

本轮没有新的 fork Issue 入站；下表把上游侧可观察问题映射到维护分支状态。

| Issue / Bug | 版本与日期 | 维护分支状态 | 来源分类 | 根因 | 代码落点 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| Android 录制因证书失败 | 3.0.7，2026-08-28 | `present` | external-drift | FFmpegKit 自带 TLS 栈不读 Android 系统信任库 | `lib/recorder/ffmpeg/android_ca_certificate_manager.dart`、`assets/cacert.pem` | `accept` |
| 快手直播源获取错误 | 3.0.7，2026-08-27 | `present` | external-drift | 离线判定与推荐卡片采纳条件过松 | `lib/core/site/kuaishou/kuaishou_site.dart` | `accept` |
| 录制中房间瞬时错误被当成下线导致提前停止 | 3.0.13 系列，2026-08-28 | `present` | external-drift | UI 侧兜底房间把传输错误压成离线状态 | `lib/core/interface/live_site.dart` 与各站点录制解析 | `accept` |
| Windows 录制页返回后 flutter_windows.dll 越界 | 3.0.13，2026-08-28 | `present` | external-drift | 路由未退出即恢复视频图层 | `lib/routes/navigation_observer.dart`、`lib/modules/live_play/widgets/video_player/video_player.dart` | `adapt` |
| 一次原生终态错误后播放器卡在错误态 | 3.0.14 段落，2026-08-28 | `present` | external-drift | 引擎回退等待第二次终态回调 | `lib/player/core/engine_fallback_manager.dart` | `accept` |
| 上游自带测试与模型 schemaVersion 不一致 | 3.0.7，2026-08-27 | `present` | upstream-existing | 模型写 4、测试断言 3 | `test/live_record_task_persistence_test.dart` | `adapt` |
| 上游 `pubspec.lock` 不可 enforce | 3.0.7，2026-08-28 | `present` | upstream-existing | 锁定 `android_file_picker 1.0.2` 与解析必需版本矛盾 | `pubspec.lock` | `adapt` |
| 本 fork 普通页布局与返回语义 | 不适用 | `not-reproduced` | 不适用 | 本轮上游改动未触及 PopScope/返回通道 | `lib/modules/live_play/widgets/layout/live_play_content.dart`（需采样） | `accept` |
| Linux/macOS/iOS 运行结果 | 不适用 | `community-platform` | 不适用 | 无对应设备证据 | `ios/Runner/Info.plist`、`tool/prefetch_android_native.ps1` | `defer` |

## fork_feature_impact

- 普通竖屏、横屏、全屏、画中画、小窗、音频模式：`live_play_content.dart` 移除两处 `SafeArea` 并把避让下沉到 `LivePlayVideoFrame`，竖屏普通页四要素（顶栏/视频/清晰度线路入口/弹幕列表）仍由确定性测试守护，但状态栏与导航条避让需真机采样；Windows 小窗几何新增竖屏独立存储，方向切换不再互相覆盖；`video_player.dart` 的应用生命周期监听在合并中被上游删除，已重新接回，音频-only 省电与后台自动暂停保持原行为。
- 播放器、清晰度、线路和弹幕会话：`player_manager.dart` 的会话与实例双重守卫、`video_controller.dart` 监听绑定提前，均强化“以真正打开成功为提交点”；画质标签归一后，历史偏好 `蓝光8M/蓝光4M` 可能不再命中标签匹配而落到启发式默认；引擎回退预算 2 -> 1 让首次确认失败即换引擎；`player_session.dart` 新类型暂无调用方，多画面同看仍走原有 `PlayerManager` 会话机制。
- 设置默认值、迁移、备份恢复：新增 `portraitVideoHeightMode`、`portraitCustomHeight` 与 `windows_pip_portrait_*` 均为新增键，缺键取声明默认（自适应高度、0 自定义高、竖屏几何未设），旧安装无需迁移写入；`clearWindowsPipGeometry` 改为 `clearAll()`，关闭记住小窗位置时横屏几何一并清除；`resetMpvPlayerSettings` 不再重置竖屏布局与弹幕模式；备份默认包含 cookie 与 WebDAV 配置（用户明确接受）。
- 首页、关注、搜索、排行和平台接口：站点侧新增录制/游标能力接口与画质归一；douyu 播放地址优先级反转、twitch 源画质排序提高、CC 与 SOOP 档位去重与排序调整、SOOP 取流失败改为抛错（错误从静默变为 Toast）；本 fork 的抖音/虎牙等平台 Cookie 校验与抓取模块未被触及。
- Windows 窗口、安装、数据目录和资源趋势：MSIX 版本随上游推进到 3.0.7.4095；录制缓存在保护目录下的清理语义变化；数据目录与迁移逻辑本轮未改。
- 版本、签名、更新源、工作流和 Release 资产：版本身份统一为 3.0.7/4095、tag `v3.0.7`；`assets/version.json` 的 6 处 download_url、四个工作流的 `release_tag` 默认值、Release 正文下载行均指向本 fork；`.env`/`lib/gen/env.g.dart`/`VersionUtil` 更新源保持 `yanxiatao/pure_live`；`huya_site.dart` 的 play_config 镜像 owner 保持 `yanxiatao`；版本历史页的 releases.json 抓取源改为本 fork；`setup-java` 动作重新固定为 40 位提交。

## quality_assessment

- 正确性与边界：录制重写覆盖面明显提升（严格房间解析、逐线路游标、失败分类与脱敏）。已识别的上游侧边界缺陷：`-n` 叠加 `file exists` 致命标记使分片前缀冲突不可恢复；`unexpectedEof` 不进入轮询会长时间以 ≤15s 间隔重连；`decoder` 分类按关键字匹配易误判；`recorder_page` 排序在每次进度刷新内重算。
- 异步竞态和生命周期：`ffmpeg_scheduler` 用可跟踪 Timer 取代 `Future.delayed` 并让取消等待收敛（20s/10s 超时），方向正确；残留窗口是 `clearAll` 未先清 `_runningTasks` 与晚注册取消走 `unawaited`。播放器换引擎时先替换当前实例再清订阅，旧实例的真实错误可能被守卫吞掉。
- Timer / Stream / Worker / Controller / 纹理 / 缓存释放：`recorder_controller.onClose` 统一取消；`video_processor_service` 在 `finally` 清理订阅与临时文件；`cache_service` 引用计数保护目录，但任务被丢弃而不 release 会永久阻止清理；`AndroidCaCertificateManager` 会永久缓存失败的准备 Future。
- 性能与网络请求：media_kit `analyzeduration/probesize` 提高到 5M 会延长首帧探测；虎牙每次取流重新签名增加哈希计算但换来播放/录制并发可用；`playback_header_resolver` 读进程内 UA 去掉了一次网络请求。
- 数据迁移：录制任务 JSON 标记升到 schemaVersion 4 且不再持久化签名 URL，读侧容错回退；旧命名分片（`%Y%m%d_%H%M%S.ts`、`list.txt`）只有崩溃恢复路径能合并，用户手动重合并旧录像会报“无 TS 文件”。本轮不额外补写迁移，按上游语义交付并在回归计划中标注。
- 更优方案与决定：曾考虑把 `assets/releases.json` 与 README 的上游历史链接一并改写为本 fork，但 fork 的 `tool/update_releases.py` 会合并上游与本地 Release、且 fork 未发布 3.0.5/3.0.7 历史版本，改写会产生 404，故只把抓取源与自身发布链接指向本 fork；曾考虑把全平台工作流输入默认值改为 false 以满足策略脚本，但那会破坏 fork 自身 `sync-upstream.yml` 的发布派发（详见 conflict_resolution 的未修项）。

## disposition

| 改动 | 处置 | 理由 | 恢复条件（如 defer） |
| --- | --- | --- | --- |
| 上游 108 文件主体 | `accept` | 录制、播放器、站点适配与设置改动均为上游自身演进，fork 无重叠实现 | 不适用 |
| `build_pure_live_release.yml` 冲突块 | `adapt` | 保留 release_sync_note 输入与正文占位（fork 自动发布派发依赖），动作引用重新固定 40 位提交，其余取上游 | 不适用 |
| `assets/version.json` | `adapt` | 版本与描述取上游 3.0.7/4095，download_url 指向本 fork | 不适用 |
| `lib/player/core/player_session.dart` | `accept` | fork 侧只有一个多余换行，取上游完整内容 | 不适用 |
| `en.json` 缺失的 4 个键 | `adapt` | fork 侧此前误删仍在调用的键，按上游补回 | 不适用 |
| `version_history.dart` releases.json 抓取源 | `adapt` | 下载信息指向本 fork（使用 `AppConfig.pureliveUpdateOwner/Repository`） | 不适用 |
| `video_player.dart` 生命周期监听 | `adapt` | 保留 StableVideoLayer，接回音频-only 省电与后台自动暂停 | 不适用 |
| `pubspec.lock` / `plugins/flame_barrage/pubspec.lock` | `adapt` | fork 环境统一使用腾讯镜像；上游锁不可 enforce | 镜像补齐 3 个较新版本后可回到上游锁定版本 |
| 备份默认包含敏感数据 | `accept` | 用户明确要求全部接受上游默认，不改调用点 | 若后续要收紧，给 WebDAV/Firebase/预览传显式参数或接回 `redactSensitiveData` |
| `ios/Runner/Info.plist` 全局放开 ATS | `accept` | iOS 属社区验证范围，本轮无设备证据 | 需要 iOS 侧确认后再决定是否收窄 |
| `live_record_task_persistence_test.dart`、`windows_pip_geometry_test.dart` | `adapt` | 上游 schema 扩展使 fork/上游断言过时，按实际契约更新断言 | 不适用 |
| 上游 trailing whitespace（`recorder_page.dart` 等） | `accept` | 保持上游字节以缩小下次同步差异面；`local_ci.ps1` 不做 whitespace 门禁 | 若仓库要把 whitespace 纳入门禁，需单独一轮格式化 |
| Linux/macOS/iOS 构建与运行 | `defer` | 本轮无对应平台证据，交付范围为远端 Release 工作流实际产出 | 需要该平台设备或远端分段构建证据后恢复 |

## conflict_resolution

- 文本冲突：`git merge upstream/master` 产生 3 个冲突文件——`.github/workflows/build_pure_live_release.yml`（取上游 + 回补 release_sync_note、`setup-java@v6` 重新固定为 `dd06d9cba3e5552c54d9f8ea23572deb30010f7c # v6.0.0`）、`assets/version.json`（上游版本信息 + 本 fork download_url）、`lib/player/core/player_session.dart`（取上游）。
- 无文本冲突但存在的语义冲突：`en.json` 键被 fork 误删后上游补齐；`video_player.dart` 上游删除生命周期监听导致 `PlayerManager` 两个方法变死代码；`pubspec.lock` 与 fork 强制腾讯镜像冲突且上游锁本身不可 enforce；上游自带 `live_record_task_persistence_test.dart` 断言与模型矛盾、fork 的 `windows_pip_geometry_test.dart` 与新增竖屏几何键不匹配。
- 最终候选结果与上游/维护分支差异：仅发布身份与来源指向类文件（工作流默认标签、version.json、Releases 正文链接、版本历史抓取源、huya play_config 镜像 owner）、锁文件注册表 URL、被接回的生命周期监听、以及两处测试断言更新；业务实现全部跟随上游。
- 版本、更新源、签名和发布资产保留策略：`pubspec.yaml`/`assets/version.json`/`windows/packaging/msix/make_config.yaml`/四份工作流默认标签一致为 3.0.7+4095 与 `v3.0.7`；`.env`、`lib/gen/env.g.dart`、`VersionUtil`、`test/release_asset_urls_test.dart` 断言的更新与资产下载源保持 `yanxiatao/pure_live`；`build_pure_live_release.yml` 引用的签名 Secrets 与本仓库已配置的 6 个 Secrets 名称一致（`feature-build.yml` 需要 `PURELIVE_*` 前缀密钥，本仓库尚未配置，故本轮发布路径仍为前者）。
- 未修项（需仓库所有者决定，本轮不擅自改动）：`tool/validate_build_policy.ps1` 要求 `build_pure_live_release.yml` 内平台/发布输入 `default: true` 数量为 0，但该文件在合并基线、fork HEAD 与上游三处都是 6 处 `default: true`，即本地质量门禁在本次合并之前就已失败；同时 `sync-upstream.yml` 依赖这些默认为真才会构建产物。README 的 `maintenance-readme-markers` 等标记在 fork 侧 README 重写时丢失，本轮已恢复。

## regression_plan

- 受影响单元 / Widget 测试：上游新增/改写的 18 个测试文件全部纳入（录制命令 argv、失败分类、调度取消、任务持久化、存储保护、平台契约、清单合并、画质标签、各站点解析与请求头、引擎回退、初始化时序），加上 fork 侧 `test/multiview_test.dart`、`test/release_asset_urls_test.dart`、`test/player_settings_controller_test.dart`、`test/windows_pip_geometry_test.dart`、`test/live_play_back_scope_test.dart`、`test/live_play_navigation_ui_test.dart`、`test/content_first_panel_layout_test.dart`、`test/danmaku_controller_lifecycle_test.dart`、`test/backup_privacy_test.dart`、`test/github_mirror_test.dart`，最终执行整套仓库测试。
- Android 模式矩阵：普通竖屏（顶栏/视频/清晰度线路入口/弹幕列表同屏）、横屏、全屏、系统画中画、音频-only 后台续播与省电、录制启动与失败重连、Android 8.0 以下安装被拒。确定性测试覆盖前两项与布局不变量，其余需真机采样。
- Windows 模式矩阵：录制页返回后视频图层恢复、小窗横竖屏几何分别记忆、MSIX 版本 3.0.7.4095 升级安装。仅静态与单元测试覆盖，未做桌面采样。
- 接口与网络故障：站点取流失败改为抛错后的 UI 呈现、CA 提取失败导致录制不可用的表现、腾讯镜像缺版本时的解析回退。
- 旧配置、迁移和回滚：新增键缺省取声明默认；录制任务 JSON 读侧容错；旧命名录像分片仅崩溃恢复路径可合并（用户手动重合并旧录像会报无 TS 文件）。回滚点为合并前的 `origin/master` 提交 `0204a045879643ad852ce3daff436d4478668783`，单提交 `git revert -m 1 <merge>` 即可回到合并前状态；`assets/cacert.pem` 与 minSdk 26 无法在源码层部分回滚。
- 未覆盖平台与证据：Linux、macOS、iOS 无构建与运行证据；Android 竖屏避让、小窗几何、录制并发取签名、fijk 实际起播等真机场景本轮未采样（按仓库要求不做设备操作）。

## verification_plan

- 静态审计：`python tool/audit_repository.py --output local-artifacts/repository-audits/merged-upstream-sync.json` — 未通过：3826 个已跟踪文件，17 项 error、1 项 warning，全部集中在 `.github/workflows/build_pure_live_release.yml`（6 项 `workflow_default_true`、5 项 `unlocked_workflow_pub_get`、2 项 `mutable_action_reference`、`mutable_git_clone`、`mutable_dart_global_activation`、`mutable_chocolatey_package`）与 fork 自有 `.github/workflows/sync-upstream.yml`（1 项 `mutable_action_reference`）。在合并前提交 `0204a0458796` 上按相同模式复算得到完全相同的数量（6/5/2/1/1），因此属合并前既存漂移，本轮不改动发布路径。
- `git diff --check`：暂存区 820 处 whitespace 提示，全部来自上游文件字节（`lib/recorder/pages/recorder/recorder_page.dart`、`lib/recorder/pages/recorder/recorder_controller.dart` 等 CRLF/尾随空格）。为缩小下次同步差异面保留上游内容；`tool/local_ci.ps1` 不含 whitespace 门禁。
- 测试：`flutter test --no-pub --concurrency=12`（全量）— `All tests passed!`，415 个测试，0 失败，exit 0。
- Analyze：`flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` — exit 0，无问题报出。
- 依赖锁定：`flutter pub get --enforce-lockfile`（经 `tool/flutterw.ps1`，默认腾讯镜像）— 通过（合并后的锁文件已按 fork 镜像重新解析）。
- 目标平台构建：本轮交远端 GitHub Actions `build_pure_live_release.yml`（quality -> 各平台 -> publish-release -> update-json），本机不重复打包。
- 设备或桌面采样：未执行（需明确授权后另行采样）。
- 外部接口探测与时间：本轮未在本机运行 `tool/interface_probe.py`，由远端 quality 作业执行。
- 上游审查门禁：`tool/review_upstream_update.ps1 -BaseRef HEAD -UpstreamRef upstream/master -ReportOnly` 已产出机器证据 `local-artifacts/upstream-reviews/upstream-f9238cffdd2f.json`；
  该脚本对入站范围硬失败两项且不受人工批准影响：上游新增可变动作引用 `actions/setup-java@v6`（已在合并结果中重新固定为 40 位提交）与上游自身引入的 808 处 whitespace 错误（保留上游字节，见 disposition）。

## 合并结论

`upstream/master@f9238cffdd2f` 以真实 merge 合入维护分支并保留祖先关系，回滚点为 `0204a0458796`。功能实现跟随上游，版本与下载/更新来源保持本 fork，两处 fork 功能不变量（音频-only 生命周期监听、虎牙 play_config 镜像 owner）经手工核对未被覆盖。剩余风险集中在：竖屏 SafeArea 变更与 media_kit 探测参数需真机采样、备份默认携带敏感数据、镜像滞后导致 3 个依赖补丁版本低于上游、以及 `tool/validate_build_policy.ps1` 与 fork 全平台工作流默认值之间合并前就已存在的策略冲突。

