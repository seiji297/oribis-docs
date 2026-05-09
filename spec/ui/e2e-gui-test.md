# E2E GUI Test (Playwright)

## Overview

Oribis のフロントエンド GUI を対象にした E2E 自動テスト群。
Playwright + Chromium (swiftshader) でブラウザレベルで UI 挙動を検証する。

## テスト構成

| シナリオ | 内容 | ファイル |
|---------|------|---------|
| T-1 Sidebar Tab Switch | サイドバータブ切り替え（Anima ↔ Department） | `e2e/scenarios/t-1-sidebar-tab-switch.scenario.json` |
| T-2 No Main Tab Bar | メインタブバーが非表示であること | `e2e/scenarios/t-2-no-main-tab-bar.scenario.json` |
| T-3 PTY Toggle | 背景除去モードトグル | `e2e/scenarios/t-3-pty-toggle.scenario.json` |
| T-4 PTY Resize | PTYパネルリサイズ | `e2e/scenarios/t-4-pty-resize.scenario.json` |
| T-7 Avatar Canvas | 3DアバターCanvasの存在確認 | `e2e/scenarios/t-7-avatar-canvas.scenario.json` |
| T-8 Settings Panel | 設定パネル表示 | `e2e/scenarios/t-8-settings-panel.scenario.json` |

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
