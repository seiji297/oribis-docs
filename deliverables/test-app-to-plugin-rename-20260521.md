# テスト証跡: App→Plugin 名称変更

**日付**: 2026-05-21
**ブランチ**: sysdev-1/app-to-plugin-rename
**エピック**: epic-app-to-plugin-rename-20260521.md

## テスト結果サマリー

- cargo test: 1428 passed, 5 ignored
- pnpm typecheck: 0 errors
- pnpm vitest (plugin-v2): 145 passed, 0 failed
- autotest.rs flaky test 1件（test_log_records_before_1mb_error）: 再実行でPASS。Plugin V2変更起因でない

## AC照合マトリクス

| AC | テスト内容 | 結果 | 証跡 |
|----|-----------|------|------|
| AC-1 | Rust struct/enum grep AppV2Error等 → 0件 | PASS | plugin_v2/内にAppV2Error/AppInfoDto/AppStateEntry/AppStateFile/AppRegistry/AppStorage残存なし |
| AC-2 | Rust app_v2_* grep → 0件 | PASS | lib.rs + plugin_v2/内にapp_v2_残存なし |
| AC-3 | TS AppStatus/AppInstance/AppSandbox/AppSystem grep → 0件 | PASS | plugin-v2/内に残存なし |
| AC-4 | TS app_v2_* invoke grep → 0件 | PASS | plugin-v2/ + App.tsxに残存なし |
| AC-5 | git ls-files AppSandbox/AppSystem/useAppSystem → 0件 | PASS | ファイル名変更完了（git mv使用） |
| AC-6 | ls plugins-v2/ → 5ディレクトリ存在 | PASS | bgm-radio, blender-hub, discord-hub, google-workspace, work-report |
| AC-7 | grep appLifecycle plugins-v2/*/manifest.yaml → 0件 | PASS | 全7 manifest.yaml更新完了（pluginLifecycleに変更） |
| AC-8 | grep "app." sdk/oribis-plugin-sdk.d.ts → 0件 | PASS | SDK更新完了 |
| AC-9 | Rust PluginStateFile.apps フィールド存在確認 | PASS | `apps: HashMap<String, PluginStateEntry>` 維持（互換性維持） |
| AC-10 | cargo test + typecheck + vitest 全PASS | PASS | 1428 passed / typecheck 0 errors / vitest 145 passed |

## 変更ファイル一覧

### タスク1: Rust全面リネーム（10ファイル）
- `src-tauri/src/plugin_v2/error.rs` — AppV2Error → PluginV2Error
- `src-tauri/src/plugin_v2/manifest.rs` — ExtensionPoint::AppLifecycle → PluginLifecycle + serde alias
- `src-tauri/src/plugin_v2/lifecycle.rs` — AppStateEntry/AppStateFile/AppEntry/AppRegistry → Plugin*
- `src-tauri/src/plugin_v2/storage.rs` — AppStorage → PluginStorage, 4コマンド名変更
- `src-tauri/src/plugin_v2/fs.rs` — 3コマンド名変更, validate_app_id → validate_plugin_id
- `src-tauri/src/plugin_v2/package.rs` — 2コマンド名変更
- `src-tauri/src/plugin_v2/mod.rs` — AppInfoDto → PluginInfoDto, 7コマンド名変更
- `src-tauri/src/home.rs` — apps_v2_dir() → plugins_v2_dir()
- `src-tauri/src/lib.rs` — 全16 invoke_handler登録更新
- `src-tauri/src/skill.rs` — appLifecycle → pluginLifecycle

### タスク2: TypeScript全面リネーム（13ファイル）
- `src/plugin-v2/types.ts` — AppStatus/AppState/AppInstance → Plugin*
- `src/plugin-v2/PluginSandbox.ts` — (旧AppSandbox.ts) クラス名+内容変更
- `src/plugin-v2/PluginSystem.ts` — (旧AppSystem.ts) クラス名+内容変更
- `src/plugin-v2/usePluginSystem.ts` — (旧useAppSystem.ts) hook名+invoke文字列変更
- `src/plugin-v2/HostAPI.ts` — CAPABILITY_MAP + handleApp→handlePlugin + invoke文字列
- `src/plugin-v2/sdk/oribis-plugin-sdk.d.ts` — App→Plugin namespace
- `src/App.tsx` — import更新 + invoke文字列
- テストファイル6件: PluginSandbox.test.ts, usePluginSystem.test.ts, invoke.test.ts, e2e.test.ts, HostAPI.test.ts, sdk.test.ts

### タスク3: ディレクトリ名変更 + manifest.yaml（14ファイル）
- `apps-v2/` → `plugins-v2/`（git mv, 5プラグイン全移動）
- 全7 manifest.yaml: appLifecycle → pluginLifecycle
- `src-tauri/src/home.rs` — パス文字列 "apps-v2" → "plugins-v2"
- `src-tauri/src/plugin_v2/fs.rs` — テスト用パス更新

## コミット履歴

```
epic: タスク1完了 - Rust全面リネーム App→Plugin
epic: タスク2完了 - TypeScript全面リネーム App→Plugin
epic: タスク3完了 - ディレクトリ名変更 + manifest.yaml更新
```

## デグレ確認

- cargo test: 1428件（タスク1実行前と同数）
- pnpm typecheck: 0 errors
- plugin-v2 vitest: 145件（タスク2実行前と同数）
- autotest.rs flaky test（test_log_records_before_1mb_error）: 再実行でPASS、Plugin V2変更起因でない
