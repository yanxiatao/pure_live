# 上游同步审计：`3c7c8fc4`（v3.0.9 后续增量）

- fork_sha: `ebce984adf76e715ff1c5b74004bf32c7d37a9cd`
- upstream_sha: `3c7c8fc4830782bfc7e455f6775f35e15ef2d529`
- merge_base: `41b2b8cee10a7a72f906d304aa70e23472db6864`
- incoming_range: `41b2b8ce..3c7c8fc4`（6 个入站提交，18 个变更文件，7 个高风险）
- report: `local-artifacts/upstream-reviews/upstream-3c7c8fc48307.json`

## 结论摘要

本轮合并上游 v3.0.9 之后的 6 个增量提交（超聊 messageId、分类接口重定向、代码整理、multiview 全屏退出、收藏夹下拉刷新、超聊消息分页）。仅 2 个文件产生文本冲突（`lib/modules/multiview/multiview_controller.dart`、`lib/modules/multiview/multiview_page.dart`），均为 import 块重组冲突。按"相同功能模块上游有不同则优先保留上游、fork 独有功能保留 fork"原则处置：multiview 全屏退出采用上游 `MultiviewFullscreenSurface`，fork 独有每格控件/搜索面板保留。另修复 3 处合并衍生问题：`web_socket_util.dart` 采用上游版本（补回代理路由函数）、补齐上游缺失的 4 个 i18n 键、修正 PowerShell 覆盖导致的 UTF-16 编码。fork 特有文件（`sync-upstream.yml`、`multiview_cell_controls_layout.dart`、`multiview_room_search_*.dart`、`tool/apply_fork_identity.py` 等）全部保留。

## file_review

| 状态 | 文件 | 风险 | 上游目的 | 维护分支相关实现 | 处置 |
| --- | --- | --- | --- | --- | --- |
| M | `lib/modules/multiview/multiview_controller.dart` | high / live_playback | import 块重组（flame_barrage、live_site 等） | 文本冲突；取并集去重，保留上游 live_site/flame_barrage，移除未使用的 latest_async_value_queue/platform_utils | `adapt` |
| M | `lib/modules/multiview/multiview_page.dart` | high / live_playback | 新增 `MultiviewFullscreenSurface` 全屏退出表面（ac9ed43b） | 文本冲突；上游全屏退出实现优先采用，fork 每格控件（CellControls）与搜索面板（RoomSearchPanel）为 fork 独有功能保留 | `adapt` |
| A | `lib/modules/multiview/widgets/multiview_fullscreen_surface.dart` | high / live_playback | 全屏模式退出钮表面 | fork 原无此文件，直接采用上游 | `accept` |
| A | `test/multiview_fullscreen_surface_test.dart` | medium / tests | 全屏表面回归测试 | 直接采用上游 | `accept` |
| M | `lib/core/common/web_socket_util.dart` | high / platform_interfaces | 新增 `configureWebSocketProxyRouting`/`resolveWebSocketProxyDirective`（代理路由） | fork 旧版缺这些函数导致 `initialized.dart` 编译失败；采用上游完整版本 | `accept` |
| M | `assets/translations/en.json`、`zh.json` | medium / translations_and_assets | 新增 multiview_fullscreen_exit 等键 | 合并后 i18n 键一致性测试发现 4 个键缺失（remote_sync_enter_address、remote_sync_invalid_qr、stop、start），上游自身缺陷，fork 补齐中英翻译 | `adapt` |
| M | `lib/common/models/live_message.dart` | medium / app_modules | `LiveSuperChatMessage` 增加 `messageId` 字段（3c7c8fc4） | 自动合并成功 | `accept` |
| M | `lib/core/danmaku/huya_danmaku.dart` | high / platform_interfaces | 超聊消息使用 messageId 排序（3c7c8fc4） | 自动合并成功 | `accept` |
| M | `lib/core/site/huya/huya_site.dart`、`huya_utils.dart` | high / platform_interfaces | 分类接口处理 API 重定向并保持默认分类（88b2fa2c） | 自动合并成功 | `accept` |
| M | `lib/core/site/cc/cc_site.dart` | high / platform_interfaces | 代码整理（0b9b5008） | 自动合并成功 | `accept` |
| M | `lib/modules/favorite/room_grid_view.dart` | medium / app_modules | 收藏夹下拉刷新包装测试（d8a6b852） | 自动合并成功 | `accept` |
| M | `lib/modules/live_play/pages/super_chat_page.dart` | medium / app_modules | 超聊消息分页 50 条（75b09e2a） | 自动合并成功 | `accept` |
| M | `lib/modules/multiview/models/multiview_models.dart` | medium / live_playback | 模型整理 | 自动合并成功 | `accept` |
| M | `pubspec.lock`、`windows/packaging/msix/make_config.yaml` | medium | 上游锁定更新 | 自动合并成功 | `accept` |
| M | `docs/ISSUE_AUDIT_2026_08_31.md`、`docs/STAGE_UPDATE_3_1_3.md` | low / tooling_and_policy | 上游文档 | 直接采用 | `accept` |

## semantic_change_ledger

| commit | file / module | upstream intent / before → after | implementation | issue_and_bug_mapping | quality_assessment | fork_feature_impact | disposition | regression_plan |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `3c7c8fc4` | `live_message.dart`、`huya_danmaku.dart` | 超聊消息增加 messageId 并用于排序 | 模型加字段，HuyaDanmaku 构造时携带 | 无关联 Issue | 字段为新增可选，向后兼容 | 不影响 fork 弹幕增强 | `accept` | 弹幕/超聊测试 |
| `88b2fa2c` | `huya_site.dart`、`huya_utils.dart` | 分类接口重定向处理 + 默认分类保持 | 跟随重定向、解析失败回退默认分类 | 无关联 Issue | 网络重定向边界已处理 | 不影响 fork | `accept` | huya 分类解析测试 |
| `0b9b5008` | 多文件 | 代码结构整理 | 重命名/移动符号 | 无 | 需全量编译验证 | 低 | `accept` | 全量 analyze |
| `ac9ed43b` | `multiview_page.dart`、`multiview_fullscreen_surface.dart` | 暴露 multiview 全屏退出钮 | 新增 FullscreenSurface 组件 | 无关联 Issue | 与 fork 全屏状态机兼容 | fork 原用无 chrome 全屏，现采用上游退出钮实现 | `adapt` | multiview_fullscreen_surface_test |
| `d8a6b852` | `room_grid_view.dart` | 收藏夹下拉刷新包装测试 | 新增测试辅助 | 无 | 测试层改动 | 低 | `accept` | 收藏夹测试 |
| `75b09e2a` | `super_chat_page.dart` | 超聊消息分页 50 条 | 页面大小与排序调整 | 无 | 分页边界 | 低 | `accept` | 超聊页测试 |

## issue_and_bug_mapping

| Issue / Bug | 版本与日期 | 维护分支状态 | 来源分类 | 根因 | 代码落点 | 结论 |
| --- | --- | --- | --- | --- | --- | --- |
| i18n 键缺失（remote_sync_enter_address 等 4 键） | 2026-09-01 | present | upstream-existing | 上游 remote_sync 功能引用 4 个键但翻译文件缺失 | `assets/translations/en.json`、`zh.json` | 已补齐中英翻译（adapt） |

## fork_feature_impact

- 普通竖屏、横屏、全屏、画中画、小窗、音频模式：不受影响。
- 播放器、清晰度、线路和弹幕会话：不受影响。
- 设置默认值、迁移、备份恢复：不受影响。
- 首页、关注、搜索、排行和平台接口：huya 分类重定向逻辑采用上游；其余不变。
- Windows 窗口、安装、数据目录和资源趋势：msix 配置随上游微调。
- 版本、签名、更新源、工作流和 Release 资产：fork 身份文件（`sync-upstream.yml`、`tool/apply_fork_identity.py`、`assets/version.json`）全部保留，更新源仍指向 yanxiatao。

## quality_assessment

- 正确性与边界：multiview 全屏退出采用上游组件，fork 每格控件保留，双实现不冲突。
- 异步竞态和生命周期：无新增。
- Timer / Stream / Worker / Controller / 纹理 / 缓存释放：无新增。
- 性能与网络请求：huya 分类重定向有界处理。
- 数据迁移：无新增配置键。
- 更优方案与决定：web_socket_util 采用上游完整版本，避免 fork 旧版缺函数。

## disposition

| 改动 | `accept/adapt/rewrite/drop/defer` | 理由 | 恢复条件（如 defer） |
| --- | --- | --- | --- |
| multiview 冲突（controller/page） | `adapt` | 上游全屏退出优先，fork 每格控件保留 | - |
| web_socket_util.dart | `accept` | 上游版本补回代理路由函数 | - |
| i18n 4 键补齐 | `adapt` | 上游自身缺陷，fork 修复 | - |
| fork 特有文件 | `drop`（拒绝上游删除） | 上游 diff 显示删除，但合并保留 fork 文件 | - |

## conflict_resolution

- 文本冲突：`multiview_controller.dart`、`multiview_page.dart` 的 import 块。controller 取并集去重（保留上游 live_site/flame_barrage）；page 上游 FullscreenSurface 优先、fork CellControls/RoomSearchPanel 保留。
- 无文本冲突但存在的语义冲突：`web_socket_util.dart` 上游新增函数 fork 缺失 → 采用上游；i18n 键缺失 → 补齐。
- 最终候选结果与上游/维护分支差异：fork 特有 multiview 控件、sync 工作流、fork 身份工具保留。
- 版本、更新源、签名和发布资产保留策略：fork 侧（version.json 指向 yanxiatao）。

## regression_plan

- 受影响单元 / Widget 测试：multiview_fullscreen_surface_test、multiview_room_search_panel_test、multiview_cell_controls_layout_test、i18n_key_parity_test。
- Android 模式矩阵：multiview 全屏/普通/每格控件。
- Windows 模式矩阵：无变化。
- 接口与网络故障：huya 分类、超聊接口。
- 旧配置、迁移和回滚：无新增键，无需迁移。
- 未覆盖平台与证据：Linux/macOS/iOS 未单独采样，社区验证。

## verification_plan

- 静态审计：`python tool/audit_repository.py`（14 个错误均为合并前既有工作流问题，本次未引入新错误）。
- `git diff --check`：通过。
- Focused / Full 测试：463/463 通过。
- Analyze：0 error（仅 1 个既有 info）。
- 目标平台构建：由后续 Release action 执行。
- 设备或桌面采样：未采样，构建门禁后由发布验证。
- 外部接口探测与时间：由后续 Release action 执行。

## 合并结论

- 最终 merge 提交：待提交（本文件随合并提交）。
- 接受、适配、重写、舍弃和延期摘要：18 个入站文件全部接受/适配；fork 特有文件拒绝删除；i18n 缺陷已修复。
- 已知限制：上游自身 i18n 键缺失已补；审计报告的 14 个工作流错误为合并前既有。
- 回滚点：合并提交即回滚点，`git reset --hard ebce984a` 可回退。
