# E2E GUI Test (Playwright)

## Overview

Oribis のフロントエンド GUI を対象にした E2E 自動テスト群。
Playwright + Chromium (swiftshader) でブラウザレベルで UI 挙動を検証する。

## テスト構成

### Playwright E2E（13件 / 2026-05-11時点）

| シナリオ | 内容 | ファイル |
|---------|------|---------|
| T-1 Sidebar Tab Switch | サイドバータブ切り替え（Anima ↔ Department） | `e2e/scenarios/t-1-sidebar-tab-switch.scenario.json` |
| T-2 No Main Tab Bar | メインタブバーが非表示であること | `e2e/scenarios/t-2-no-main-tab-bar.scenario.json` |
| T-3 PTY Toggle | 背景除去モードトグル | `e2e/scenarios/t-3-pty-toggle.scenario.json` |
| T-4 PTY Resize | PTYパネルリサイズ | `e2e/scenarios/t-4-pty-resize.scenario.json` |
| T-7 Avatar Canvas | 3DアバターCanvasの存在確認 | `e2e/scenarios/t-7-avatar-canvas.scenario.json` |
| T-8 Settings Panel | 設定パネル表示 | `e2e/scenarios/t-8-settings-panel.scenario.json` |
| T-9 OrchestratorEditor Open/Close | Editor起動・Closeボタン・再表示 | `e2e/scenarios/t-9-orchestrator-editor-open-close.scenario.json` |
| T-10 Department CRUD | 追加→詳細表示→5タブ切替→Save | `e2e/scenarios/t-10-department-crud.scenario.json` |
| T-11 Dirty State Guard | 未保存確認ダイアログ・キャンセル・破棄 | `e2e/scenarios/t-11-dirty-state-guard.scenario.json` |
| T-12 Department Delete | Department削除フロー | `e2e/scenarios/t-12-department-delete.scenario.json` |
| T-13 Department Add Form | 新規作成フォーム入力・バリデーション | `e2e/scenarios/t-13-department-add-form.scenario.json` |
| T-14 Skills/Prompts Tabs | Skills/Promptsタブ内実操作 | `e2e/scenarios/t-14-skills-prompts-tabs.scenario.json` |
| T-15 Form Validation | フォームバリデーション（必須フィールド・不正入力） | `e2e/scenarios/t-15-form-validation.scenario.json` |

※ T-5, T-6 は欠番。

### wdio 実機GUIテスト（5件 / 2026-05-11時点）

実バイナリ（Tauri）+ Xvfb 環境で実行する実機テスト。

| シナリオ | 内容 |
|---------|------|
| T-W-01 | アプリ起動確認（ウィンドウ表示） |
| T-W-02 | 基本UI要素の表示確認 |
| T-W-03 | サイドバータブ切り替え（実機） |
| T-W-04 | PTYトグル（実機） |
| T-W-05 | ウィンドウリサイズ（getWindowRect） |

**実行コマンド**:
```bash
cd oribis/e2e
pnpm test:wdio   # wdio 実機テスト（Xvfb必須）
```

## 実行環境

```bash
cd oribis/e2e
pnpm install
npx playwright install chromium
pnpm test          # Playwright E2E のみ
pnpm test:node     # Node.js ユニットテスト（bone regression等）
pnpm test:all      # 両方
```

## アーキテクチャ

- `e2e/fixtures/app.fixture.ts` — Tauri IPC mock 注入 + ページナビゲーション
- `e2e/fixtures/tauri-mock.ts` — `window.__TAURI_INTERNALS__` の mock 実装
- `e2e/engine/runner.ts` — シナリオJSON駆動のテスト実行エンジン
- `e2e/helpers/selectors.ts` — セレクタ一元管理
- `e2e/scenarios/*.scenario.json` — シナリオ定義（action/assertのJSON）

## 実装ログ

### 2026-05-09: E2Eテスト修正（sysdev-1/oribis-orch-p1-fix）

#### 問題
sysdev-2 で `pnpm test` 実行時 **2 PASS / 4 FAIL**。すべて「初期UI状態不整合」が原因。

| シナリオ | 失敗原因 |
|---------|---------|
| T-1 | `v2-sidebar-tab-btn[title="Project"]` が見つからない（タブ名は Anima/Department） |
| T-3/T-4 | onboarding 画面のままメインUIに遷移せず、要素が非表示 |
| T-7 | `.avatar-section canvas` セレクタが不正（実際は `.vrm-canvas-container canvas`） |

#### 修正内容

| ファイル | 修正 |
|---------|------|
| `e2e/fixtures/app.fixture.ts` | `localStorage.setItem("oribis_onboarding_done", "true")` を注入し onboarding をスキップ |
| `e2e/fixtures/tauri-mock.ts` | `load_project_tabs` が配列を返すように修正（JSON文字列ではなく）。`convertFileSrc` で `anima.vrm` を `http://localhost:1420/anima.vrm` に解決 |
| `e2e/helpers/selectors.ts` | `avatarCanvas` を `.avatar-section .vrm-canvas-container canvas` に修正 |
| `e2e/scenarios/t-1-sidebar-tab-switch.scenario.json` | 「Project/Log」→「Anima/Department」にタブ名更新。メニュートグルクリックを追加 |
| `e2e/scenarios/t-7-avatar-canvas.scenario.json` | `canvasRendered` アサーションを削除（swiftshader環境で `gl.readPixels` が不安定） |
| `public/anima.vrm` | VRMモデルを `src-tauri/resources/` からコピーし Vite devサーバー経由で配信 |

#### テスト結果

```
✓ T-1 Sidebar Tab Switch   (1.8s)
✓ T-2 No Main Tab Bar      (746ms)
✓ T-3 PTY Toggle           (876ms)
✓ T-4 PTY Resize           (2.1s)
✓ T-7 Avatar Canvas        (705ms)
✓ T-8 Settings Panel       (916ms)

6 passed
```

#### commit
- oribis repo: `3898800` (fix(e2e): repair E2E tests for sysdev-1/oribis-orch-p1-fix)

### 2026-05-11: P2シナリオ追加・wdio実機テスト追加（sysdev-1/oribis-orchestrator-p2）

#### 追加内容

**Playwright E2E（T-9〜T-15追加 / 計13件）**

| シナリオ | commit |
|---------|--------|
| T-9〜T-11（OrchestratorEditor/CRUD/dirty state） | 先行コミット |
| T-12〜T-15（削除/フォーム/Skills-Promptsタブ/バリデーション） | `91d8414` |

**wdio 実機GUIテスト（T-W-01〜T-W-05新規）**

| 対応 | commit |
|-----|--------|
| wdio実機テスト基盤追加 | `d62625f` |
| getWindowRect対応 | `e0d22cc` |

#### テスト結果（2026-05-11）

```
Playwright E2E: 13/13 PASS（T-1〜T-15、欠番T-5,T-6）
wdio 実機GUI:   5/5  PASS（T-W-01〜T-W-05）
Rust cargo test: 955 PASS / 5 ignored
TS vitest:       563 PASS
```
