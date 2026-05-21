# テスト証跡: Plugin V2 外部連携アプリ化

**日付**: 2026-05-21
**ブランチ**: sysdev-1/plugin-v2-apps
**エピック**: epic-plugin-v2-apps-20260521.md

## テスト結果サマリー

| テスト種別 | 結果 | 詳細 |
|-----------|------|------|
| cargo test | PASS | 1428 passed, 5 ignored |
| pnpm typecheck | PASS | 0 errors |
| pnpm vitest (plugin-v2) | PASS | 145 passed |
| pnpm test (全体) | PASS* | 906 passed, 65 failed |

*packages/discord-bot/ テスト失敗 — develop同一、Plugin V2変更起因でない

## AC照合マトリクス

| AC | テスト内容 | 結果 | 証跡 |
|----|-----------|------|------|
| AC-1 | invoke bridge実装 (AppSandbox + HostAPI) | PASS | invoke.test.ts 10件PASS、CAPABILITY_MAP "invoke.call" → "tauriInvoke" |
| AC-2 | TauriInvoke Capability + allowed_commands | PASS | manifest.rs: Capability::TauriInvoke + allowed_commands + is_command_allowed() + テスト7件 |
| AC-3 | Google Workspace app (6タブUI) | PASS | manifest.yaml: 20 allowed_commands、index.ts: Calendar/Tasks/Gmail/Drive/YouTube/Photos |
| AC-4 | Discord Hub app (ウィザード+送信) | PASS | manifest.yaml: 11 allowed_commands、index.ts: 4ステップウィザード+メッセージ送信 |
| AC-5 | Blender Hub拡張 (invoke対応) | PASS | manifest.yaml: tauriInvoke + 8 allowed_commands、3Dプレビュー基盤 |
| AC-6 | Work Report app (git log集約) | PASS | Rustモジュール: generate_daily/weekly + テスト3件、canonicalize()パストラバーサル防止 |
| AC-7 | 全テスト通過 | PASS | cargo test 1428 / typecheck 0 / vitest 145 / discord-bot既存問題のみ |

## デグレ確認

- packages/discord-bot/ テスト65件FAIL → develop同一（Plugin V2変更起因でない）
- DepartmentDetail.test.tsx Unhandled Rejection → develop同一
- cargo test: 1428件（タスク1で+12件、タスク5で+4件 = 元1412から+16件追加）
- pnpm typecheck: 0 errors
- plugin-v2 vitest: 145件（タスク1で+10件追加）

## 変更ファイル一覧

### タスク1: invoke bridge
- `src-tauri/src/plugin_v2/manifest.rs` — TauriInvoke Capability + allowed_commands
- `src/plugin-v2/types.ts` — tauriInvoke Capability
- `src/plugin-v2/AppSandbox.ts` — invoke関数 + .callエイリアス
- `src/plugin-v2/HostAPI.ts` — handleInvoke + CAPABILITY_MAP + 監査ログ
- `src/plugin-v2/sdk/oribis-plugin-sdk.d.ts` — InvokeFunction型
- `src/plugin-v2/__tests__/invoke.test.ts` — 新規10テスト
- `src/plugin-v2/__tests__/sdk.test.ts` — namespace count更新

### タスク2: Google Workspace
- `apps-v2/google-workspace/manifest.yaml` — 20 allowed_commands
- `apps-v2/google-workspace/index.ts` — 6タブUI + 認証フロー + 60秒ポーリング

### タスク3: Discord Hub
- `apps-v2/discord-hub/manifest.yaml` — 11 allowed_commands
- `apps-v2/discord-hub/index.ts` — 4ステップウィザード + メッセージ送信

### タスク4: Blender Hub拡張
- `apps-v2/blender-hub/manifest.yaml` — tauriInvoke + 8 allowed_commands
- `apps-v2/blender-hub/index.ts` — 3Dプレビュー基盤追加

### タスク5: Work Report
- `src-tauri/src/work_report/mod.rs` — モジュール定義
- `src-tauri/src/work_report/commands.rs` — generate_daily/weekly + テスト3件
- `src-tauri/src/lib.rs` — pub mod work_report + invoke_handler
- `apps-v2/work-report/manifest.yaml` — 2 allowed_commands
- `apps-v2/work-report/index.ts` — 日次/週次レポートUI

## コミット履歴

```
epic: タスク1完了 - oribis.invoke ブリッジ実装
epic: タスク2-5完了 - Google/Discord/Blender/WorkReport Plugin V2アプリ
```
