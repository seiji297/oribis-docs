# Oribis テスト基盤 設計書

**作成日**: 2026-05-20
**バージョン**: 1.0
**対象**: `/home/mnadmin/agent-projects/sysdev/sysdev-1/oribis`
**ブランチ**: `sysdev-1/test-infra`（develop マージ前）

---

## 概要

Oribis のテスト基盤は **3層構成**:

| 層 | ツール | 対象 | コマンド |
|---|---|---|---|
| Unit/Component | Vitest + jsdom | React コンポーネント / hooks / ロジック | `pnpm test` |
| E2E (Browser) | Playwright | UIフロー（Tauri IPC mock 環境） | `cd e2e && pnpm test` |
| E2E (Node) | Vitest (node) | VRM ボーンリグレッション | `cd e2e && pnpm test:node` |

**現在のテスト数**: Unit 822件 / E2E シナリオ 22件 / Rust 1500件（2026-05-27更新）

---

## 1. Unit テスト基盤（Vitest）

### 1.1 設定

**vitest.config.ts**（プロジェクトルート）:
- `environment: "jsdom"` — ブラウザ DOM シミュレーション
- `setupFiles: ["./src/test/setup.ts"]` — 全テスト前に実行
- `globals: true` — `describe` / `it` / `expect` をグローバル公開
- `exclude: ["**/e2e/**"]` — E2E ディレクトリ除外

**カバレッジ設定**:
```
provider: v8
閾値: branches=60%, functions=60%, lines=65%, statements=65%
除外: node_modules, dist, src-tauri, e2e, src/test, *.d.ts, *.config.*
```

### 1.2 セットアップ（src/test/setup.ts）

```typescript
// WebGL Canvas mock（Three.js テスト用）
import "vitest-webgl-canvas-mock";

// jsdom polyfills
// - ResizeObserver（コンポーネントのリサイズ検知）
// - scrollIntoView（チャットスクロール）
// - matchMedia（レスポンシブ判定）
// - IntersectionObserver（遅延読み込み）
```

### 1.3 共通 Mock 基盤（src/test/）

#### createMockInvoke — Tauri invoke mock factory

```typescript
import { createMockInvoke } from "@/test/createMockInvoke";

const { fn, unknownCommands } = createMockInvoke({
  claude_chat: "AI応答テキスト",
  load_project_tabs: [{ id: "p1", name: "Project 1" }],
  save_project_tabs: null,
  some_command: new Error("fail"),  // → reject
});

vi.mocked(invoke).mockImplementation(fn);
```

**挙動**:
- マッピングに値があるコマンド → `Promise.resolve(value)`
- マッピングに `Error` があるコマンド → `Promise.reject(error)`
- 未定義コマンド → `Promise.resolve(null)` + `unknownCommands[]` に記録

#### createTauriMocks — Tauri API 全体 mock

```typescript
import { createTauriMocks } from "@/test/mocks/tauri";

const mocks = createTauriMocks({
  invoke: vi.fn().mockResolvedValue(null),
});

// mocks.core.invoke, mocks.core.convertFileSrc
// mocks.event.listen, mocks.event.emit, mocks.event.once
// mocks.dialog.open, mocks.dialog.save
```

#### createThreeVRMMock — VRM/GLTF mock

```typescript
import { createThreeVRMMock } from "@/test/mocks/three-vrm";

const vrm = createThreeVRMMock();
// vrm.VRM, vrm.VRMLoaderPlugin, vrm.VRMUtils
// vrm.GLTFLoader, vrm.VRMHumanBoneName, vrm.VRMLookAt
```

**提供クラス/オブジェクト**:
- `VRM` — scene, humanoid, expressionManager, lookAt, springBoneManager
- `VRMHumanBoneName` — 実ライブラリ互換 enum オブジェクト
- `VRMLookAt` — lookAt, update, reset 等
- `GLTFLoader` — `loadAsync` → `{ scene, animations, userData }`

#### createR3FMock / createDreiMock — React Three Fiber mock

```typescript
import { createR3FMock } from "@/test/mocks/r3f";

// Canvas → <div data-testid="r3f-canvas">
// useFrame, useThree, useLoader, useGraph, extend → vi.fn()

// drei components（全て vi.fn() → null）:
// OrbitControls, Environment, Html, Center, Float, etc.

// drei hooks:
// useGLTF → { preload, clear }
// useAnimations → { actions, mixer, names, clips }
```

#### renderWithProviders — Store 注入ヘルパー

```typescript
import { renderWithProviders } from "@/test/renderWithProviders";

const result = renderWithProviders(<MyComponent />, {
  initialState: { count: 5 },  // Zustand store に部分マージ
});
```

- `initialState` を `replace: false` でマージ（actions 保持）
- `afterEach` で自動リストア

### 1.4 テスト実行コマンド

```bash
pnpm test              # 単回実行（822件）
pnpm test:coverage     # カバレッジレポート付き
pnpm test:watch        # ファイル変更検知で自動再実行
```

---

## 2. E2E テスト基盤（Playwright）

### 2.1 アーキテクチャ

```
e2e/
├── engine/                    # シナリオ実行エンジン
│   ├── types.ts               #   型定義
│   ├── registry.ts            #   アクション/アサーション登録
│   ├── runner.ts              #   ScenarioRunner
│   ├── resolve-selector.ts    #   セレクタ解決（3段階）
│   ├── ai-resolver.ts         #   AI セレクタ解決
│   ├── resolver-cache.ts      #   キャッシュ管理
│   ├── load-scenarios.ts      #   JSONファイル読み込み
│   ├── actions/               #   アクションハンドラ
│   │   ├── click.ts
│   │   ├── type.ts
│   │   ├── wait.ts
│   │   ├── drag.ts
│   │   ├── navigate.ts
│   │   └── mock-override.ts   #   setMock（IPC mock 差替）
│   └── assertions/            #   アサーションハンドラ
│       ├── visible.ts
│       ├── hidden.ts
│       ├── text.ts
│       ├── count.ts
│       ├── exists.ts
│       ├── class.ts
│       ├── canvas-render.ts
│       └── aria.ts
├── helpers/
│   ├── selectors.ts           # CSS セレクタ集約（S オブジェクト）
│   ├── canvas-ready.ts        # Canvas 描画待機
│   └── drag-resize.ts         # ドラッグユーティリティ
├── fixtures/
│   ├── app.fixture.ts         # Tauri mock 注入フィクスチャ
│   └── tauri-mock.ts          # IPC mock スクリプトビルダー
├── scenarios/                 # JSON シナリオ群（22件）
├── tests/
│   └── scenario-driven.spec.ts # 汎用シナリオドライバ
├── playwright.config.ts
└── package.json
```

### 2.2 シナリオ JSON フォーマット

```json
{
  "id": "t-17",
  "name": "T-17 チャット送受信",
  "description": "メッセージ送信とAI応答表示の確認",
  "before": [
    {
      "type": "setMock",
      "command": "anima_chat",
      "response": {
        "text": "こんにちは！",
        "affinity": 50,
        "affinity_delta": 0,
        "suppressed": false,
        "anima_control": null,
        "usage": null
      }
    }
  ],
  "steps": [
    {
      "description": "チャットパネルが表示される",
      "assert": { "type": "visible", "rawSelector": ".v2-chat-panel" }
    },
    {
      "description": "メッセージを入力",
      "action": { "type": "type", "rawSelector": ".chat-input-area textarea", "text": "こんにちは" }
    },
    {
      "description": "送信ボタンクリック",
      "action": { "type": "click", "rawSelector": ".chat-input-area button[type='submit']" }
    },
    {
      "description": "AI応答テキストが表示される",
      "assert": { "type": "hasText", "rawSelector": ".v2-msg.v2-msg-ai", "text": "こんにちは！" }
    }
  ]
}
```

### 2.3 セレクタ指定方式（3種類）

| 方式 | キー | 解決方法 | 推奨度 |
|---|---|---|---|
| rawSelector | `rawSelector: ".css-class"` | CSS セレクタ直接指定 | **推奨** |
| selector | `selector: "chatPanel"` | S レジストリキー参照 | 既存シナリオで使用 |
| target | `target: "settings"` | AI Resolver（3段階） | 実験的 |

**rawSelector を推奨する理由**: selector キーの S レジストリ→CSS 変換に既知バグあり（resolve-selector が S を import していない）。rawSelector は変換不要で最も信頼性が高い。

### 2.4 AI Resolver（3段階セレクタ解決）

```
Stage 1: DOM exact query
  → aria-label / data-testid / placeholder の完全一致検索
  → 最速・API呼び出しなし

Stage 2: Fuzzy match
  → Levenshtein 類似度 >= 0.6 で候補マッチ
  → API呼び出しなし

Stage 3: Claude API fallback
  → AI_RESOLVER_ENABLED=true のみ有効
  → DOM候補リストを Claude に渡してセレクタ生成
  → CI では無効化（ORIBIS_AI_RESOLVER_DISABLED=true）
```

**キャッシュ**: `e2e/.resolver-cache.json`（ファイルベース、atomic write）

### 2.5 アクション一覧

| type | 必須パラメータ | 説明 |
|---|---|---|
| `click` | セレクタ | 要素クリック |
| `type` | セレクタ, `text` | テキスト入力（`clear: true` で fill） |
| `wait` | `_debugMs` or セレクタ | 待機（デバッグ用 or 要素待機） |
| `drag` | セレクタ, `deltaX`, `deltaY` | ドラッグ操作 |
| `navigate` | `url` | ページ遷移 |
| `setMock` | `command`, `response` | Tauri IPC mock 差替（before で使用） |

### 2.6 アサーション一覧

| type | パラメータ | 説明 |
|---|---|---|
| `visible` | セレクタ | 要素が表示されている |
| `hidden` | セレクタ | 要素が非表示 |
| `exists` | セレクタ | DOM に存在（表示不問） |
| `hasText` | セレクタ, `text`, `match?` | テキスト含有（exact/contains/regex） |
| `hasClass` | セレクタ, `className` | CSS クラス保持 |
| `count` | セレクタ, `expected` | 要素数一致 |
| `canvasRendered` | セレクタ, `sampleSize?` | Canvas にピクセル描画済み |
| `ariaSelected` | セレクタ, `expected` | aria-selected 属性値 |
| `ariaExpanded` | セレクタ, `expected` | aria-expanded 属性値 |
| `ariaPressed` | セレクタ, `expected` | aria-pressed 属性値 |

### 2.7 Tauri IPC Mock

**仕組み**:
1. `app.fixture.ts` が `page.addInitScript()` で `window.__TAURI_INTERNALS__.invoke` を差替
2. `tauri-mock.ts` の `getDefaultMockHandlers()` が 80+ コマンドのデフォルト応答を定義
3. シナリオの `before.setMock` で個別コマンドを上書き可能
4. `runner.run()` 完了時に `resetMockOverrides()` で復元

**デフォルト mock に含まれないコマンド**（setMock 必須）:
- `anima_chat` — キャラクターチャット応答（CharacterChatResult 型）
- `app_v2_scan` — プラグイン v2 アプリ一覧

### 2.8 シナリオ一覧（22件）

| ID | 名前 | mock | カテゴリ |
|---|---|---|---|
| t-1 | Sidebar Tab Switch | - | UI基本 |
| t-2 | No Main Tab Bar | - | UI基本 |
| t-3 | PTY Toggle | - | ターミナル |
| t-4 | PTY Resize | - | ターミナル |
| t-7 | Avatar Canvas | - | 3D |
| t-8 | Settings Panel | - | 設定 |
| t-9 | Orchestrator Editor Open/Close | - | オーケストレーター |
| t-10 | Department CRUD | list_departments_config, create_department, etc. | オーケストレーター |
| t-11 | Dirty State Guard | list_departments_config, write_prompt_file | オーケストレーター |
| t-12 | Department Delete | list_departments_config, delete_department | オーケストレーター |
| t-13 | Department Add Form | list_departments_config, create_department | オーケストレーター |
| t-14 | Skills/Prompts Tab | list_departments_config | オーケストレーター |
| t-15 | Form Validation | list_departments_config | オーケストレーター |
| t-16 | Chat Send/Receive | anima_chat, claude_chat | チャット |
| t-17 | Department Save Flow | list_departments_config | オーケストレーター |
| t-18 | Sidebar Drawer + Project List | load_project_tabs, start/stop_project_session | セッション |
| t-19 | Project Tab Management | load_project_tabs, start/stop_project_session | プロジェクト |
| t-20 | Settings Persistence (Theme) | - | 設定 |
| t-21 | Onboarding Flow | - | UI全体 |
| t-22 | i18n Language Switch | - | i18n |
| t-23 | About Section | - | UI基本 |
| t-24 | Cost Warning Settings | - | 設定 |

### 2.9 新規シナリオ追加手順

1. `e2e/scenarios/t-{番号}-{slug}.scenario.json` を作成
2. JSON フォーマット（上記 2.2 参照）に従う
3. Tauri IPC mock が必要なら `before` に `setMock` を追加
4. セレクタは `rawSelector`（CSS セレクタ直接指定）を推奨
5. `cd e2e && pnpm test` で自動実行される（load-scenarios.ts が glob で自動読み込み）

**mock 応答の型を調べる方法**:
- `src/App.tsx` で `invoke<ReturnType>("command_name", ...)` を検索
- `src-tauri/src/` で Rust 側の戻り値型を確認
- `e2e/fixtures/tauri-mock.ts` の既存 mock を参考

### 2.10 E2E 実行コマンド

```bash
cd e2e
pnpm test              # Playwright 全シナリオ実行
pnpm test:headed       # ブラウザ表示付き実行
pnpm test:ui           # Playwright UI モード
pnpm test:debug        # デバッグモード
pnpm test:node         # Node 環境テスト（VRM ボーン）
pnpm test:all          # Playwright + Node
pnpm report            # HTML レポート表示
```

---

## 3. CSS セレクタ集約（S レジストリ）

`e2e/helpers/selectors.ts` に全 UI セレクタを集約:

```typescript
export const S = {
  // Sidebar
  sidebarTabBar: ".v2-sidebar-tab-bar",
  sidebarTabBtn: ".v2-sidebar-tab-btn",
  sidebarTabAnima: '[data-tab="anima"]',

  // Chat
  chatPanel: ".v2-chat-panel",
  chatInputArea: ".chat-input-area",
  chatTextarea: ".chat-input-area textarea",
  chatSubmitBtn: '.chat-input-area button[type="submit"]',
  chatMessageUser: ".v2-msg.v2-msg-user",
  chatMessageAi: ".v2-msg.v2-msg-ai",

  // Avatar
  avatarSection: ".avatar-section",
  avatarCanvas: ".avatar-section canvas",

  // Settings
  settingsBtn: ".titlebar-settings",
  settingsPanel: ".settings-panel",

  // Orchestrator
  orchestratorEditBtn: ".titlebar-orchestrator-edit",
  orchestratorEditorOverlay: ".orchestrator-editor-overlay",
  departmentLaneWrapper: ".department-lane-wrapper",
  // ... etc
} as const;
```

**UI 変更時はこのファイルのみ更新すれば全シナリオに反映される。**
ただし現在 `rawSelector` 直接指定のシナリオが多いため、UI セレクタ変更時はシナリオ JSON 内の rawSelector も確認が必要。

---

## 4. Rust 統合テスト基盤

### 4.1 アーキテクチャ

```
src-tauri/tests/
├── common/
│   └── mod.rs                 # 共通ヘルパー（TempTestDir, load_fixture, fixtures_dir）
├── fixtures/
│   ├── anima_memory/          # amem テストケース
│   │   └── amem_test_cases.json
│   ├── task_delegation/       # DAG フィクスチャ
│   │   ├── linear_dag.json
│   │   ├── parallel_dag.json
│   │   ├── failure_dag.json
│   │   └── cycle_dag.json
│   ├── mcp_tools/             # MCP ツール名期待値
│   │   └── expected_tool_names.json
│   ├── narration/             # ナレーション coalesce ケース
│   │   └── coalesce_cases.json
│   └── orchestrator/          # E2E オーケストレーター用
│       └── graphs/
├── e2e/
│   └── scenarios/             # E2E シナリオ記述 JSON
│       ├── t-24-anima-memory.json
│       ├── t-25-task-delegation.json
│       ├── t-26-pty-security.json
│       └── t-27-narration-pipeline.json
├── anima_memory_integration.rs     # 5 tests
├── task_delegation_integration.rs  # 4 tests
├── pty_security_integration.rs     # 4 tests
├── mcp_tools_integration.rs        # 8 tests (#[cfg(unix)])
├── narration_integration.rs        # 12 tests
└── e2e_orchestrator.rs             # 4 tests (既存)
```

### 4.2 共通ヘルパー（tests/common/mod.rs）

```rust
pub struct TempTestDir { inner: tempfile::TempDir }
impl TempTestDir {
    pub fn new() -> Self;       // tempdir 作成
    pub fn path(&self) -> &Path; // パス取得
}

pub fn fixtures_dir() -> PathBuf;     // CARGO_MANIFEST_DIR/tests/fixtures
pub fn load_fixture<T: DeserializeOwned>(domain: &str, name: &str) -> T;
```

- `TempTestDir` — Drop時自動削除の一時ディレクトリ
- `load_fixture` — `fixtures/{domain}/{name}` を読んで JSON デシリアライズ

### 4.3 テスト一覧

#### anima_memory_integration.rs（5件）

| テスト名 | 対象API | 概要 |
|---|---|---|
| test_memory_db_init_creates_tables | init_memory_db | 9テーブル以上の作成確認 |
| test_amem_lifecycle | compute_token_similarity, decide_operation, apply_strengthen | 類似度→判定→強化のライフサイクル |
| test_history_roundtrip | append_message_at, load_all_at | 書き込み→読み取りラウンドトリップ |
| test_amem_pure_functions | detect_contradiction, compute_token_similarity | テーブル駆動バリデーション |
| test_memory_archive | archive_memory | アーカイブ正常完了 |

#### task_delegation_integration.rs（4件）

| テスト名 | 対象API | 概要 |
|---|---|---|
| test_linear_dag | topological_sort, execute_graph | A→B→C直列実行 |
| test_parallel_dag | topological_sort, execute_graph | A→(B,C)→Dダイヤモンド |
| test_failure_cascading | execute_graph | B失敗→C キャンセル伝搬 |
| test_cycle_detection | topological_sort | 循環DAGでErr |

#### pty_security_integration.rs（4件）

| テスト名 | 対象 | 概要 |
|---|---|---|
| test_pty_module_exports | lib.rs | pub mod pty_commands の存在確認 |
| test_pty_feature_gated | pty_commands.rs | tauri-backend フィーチャゲート確認 |
| test_security_functions_exist | pty_commands.rs | is_allowed_shell/is_allowed_args 存在+使用確認 |
| test_existing_unit_test_coverage | cargo test subprocess | >= 5 PTY unit tests 確認 |

**注意**: PTYモジュールは `#[cfg(feature = "tauri-backend")]` でゲートされているため、統合テストからは直接API呼び出し不可。ソース検証 + サブプロセステスト実行で網羅性を担保。

#### mcp_tools_integration.rs（8件） `#[cfg(unix)]`

| テスト名 | 対象API | 概要 |
|---|---|---|
| test_all_tool_definitions_present | tool_definitions | 16ツール全存在（テーブル駆動） |
| test_avatar_parse_speak | parse_speak | 凍結中 → 全入力Err |
| test_avatar_parse_expression | parse_set_expression | 6ケーステーブル駆動 |
| test_avatar_parse_notify | parse_notify | 4ケーステーブル駆動 |
| test_tool_definition_schema | tool_definitions | name/description/inputSchema構造確認 |
| test_core_test_mode_disabled | is_test_mode | ORIBIS_TEST_MODE未設定→false |
| test_sub_definitions_nonempty | *_tool_definitions | 4サブ定義の空でないことを確認 |
| test_event_feed_write_tool_exists | event_feed_tool_definitions | write_event ツール存在確認 |

#### narration_integration.rs（12件）

| テスト名 | 対象API | 概要 |
|---|---|---|
| test_cursor_roundtrip | save_cursor_in, load_cursor_in | 保存→復元ラウンドトリップ |
| test_cursor_missing_returns_default | load_cursor_in | ファイル未存在→Default |
| test_cursor_malformed_json_returns_default | load_cursor_in | 不正JSON→Default |
| test_coalesce_events_table_driven | coalesce_events | 4ケーステーブル駆動 |
| test_coalesce_summary_format | coalesce_events | マージ時 "base (×3)" 形式 |
| test_filter_high_always_passes | filter_by_priority | HIGH 100%通過 |
| test_filter_deterministic | filter_by_priority | 同一入力→同一出力 |
| test_filter_low_sampling | filter_by_priority | LOW ~10%通過 |
| test_to_speech_queue_item_basic | to_speech_queue_item | 基本変換（id/text/priority/source） |
| test_to_speech_queue_item_coalesced | to_speech_queue_item | coalesced summary使用 |
| test_compute_global_since_empty | compute_global_since | 空カーソル→None |
| test_compute_global_since_returns_min | compute_global_since | 最小ULID返却 |

### 4.4 テスト設計原則（全テスト共通・恒久適用）

以下の4原則は Rust統合テスト・Unitテスト・E2Eテスト全てに適用する。新規テスト作成時は必ず遵守すること。

1. **コンポーネント指向**: テストは対象コンポーネントの公開APIのみに依存する。内部実装の変更がテスト本体の修正を要求しない設計とする（src/ 変更ゼロ原則）
2. **実行時解決**: テスト環境（DB・ファイルシステム・ソケット等）は実行時に動的に生成する。TempTestDir・tempfile・一時ソケット等を使用し、テスト間の干渉を排除する
3. **宣言的フィクスチャ**: テストデータは JSON フィクスチャとして `tests/fixtures/{domain}/` に格納する。テストケースの追加はJSONファイルの追加のみで完了し、テストコードの変更を不要とする（テーブル駆動）
4. **ヘルパー集約**: テストロジック（セットアップ・アサーション・クリーンアップ）は共通ヘルパー（`tests/common/mod.rs`・`src/test/`）に集約する。本番APIの変更時はヘルパーのみ修正すればテスト本体は変更不要

#### 実装レベル規約

- **フィーチャゲート考慮**: tauri-backend 依存APIはソース検証 + サブプロセスで対応
- **cfg(unix)**: MCP モジュールは unix ゲートのため `#![cfg(unix)]` 付与

### 4.5 実行コマンド

```bash
cd src-tauri

# 全統合テスト実行
cargo test

# 個別テスト実行
cargo test --test anima_memory_integration
cargo test --test task_delegation_integration
cargo test --test pty_security_integration
cargo test --test mcp_tools_integration
cargo test --test narration_integration
cargo test --test e2e_orchestrator

# PTY unit tests（tauri-backend feature 必要）
cargo test --lib --features tauri-backend pty_commands
```

### 4.6 E2E シナリオ記述（Rust 統合テスト用）

`tests/e2e/scenarios/` にシナリオ記述 JSON を格納。各ファイルは以下の構造:

```json
{
  "id": "t-24",
  "title": "シナリオ名",
  "description": "概要",
  "preconditions": ["前提条件"],
  "steps": [
    { "step": 1, "action": "操作内容", "expected": "期待結果" }
  ],
  "test_file": "tests/xxx_integration.rs",
  "run_command": "cargo test --test xxx_integration"
}
```

| ID | タイトル | テストファイル |
|---|---|---|
| t-24 | Anima Memory統合 | anima_memory_integration.rs |
| t-25 | タスク委譲（DAG） | task_delegation_integration.rs |
| t-26 | PTYセキュリティ | pty_security_integration.rs |
| t-27 | ナレーションパイプライン | narration_integration.rs |

---

## 5. CI 設定（旧 Section 4）

### test.yml（push/PR トリガー）

```yaml
on:
  push: [main, develop]
  pull_request: [main, develop]

env:
  ORIBIS_AI_RESOLVER_DISABLED: "true"  # AI Resolver 無効

jobs:
  unit-test:  # pnpm typecheck → pnpm test → pnpm test:coverage
  rust-test:  # cargo test --features tauri-backend
```

### pr-check.yml（PR トリガー）

Windows + Linux マトリクスで:
- TypeScript check
- Vitest
- Rust test
- Tauri build

---

## 6. 既知の問題・制約

### 5.1 Engine バグ: resolveSelector の await 欠落
- `engine/actions/click.ts` 等で `resolveSelector()` を `await` なしで呼んでいる
- `resolveSelector` は async 関数のため、Promise オブジェクトがセレクタとして渡される
- **回避策**: `rawSelector` を使用すれば同期パスで解決されるため影響なし

### 5.2 S レジストリキーマッピング未実装
- `selector: "chatPanel"` のような S レジストリキー指定は、resolve-selector が S を import していないため CSS に変換されない
- **回避策**: 新規シナリオでは `rawSelector` を使用

### 5.3 DepartmentDetail.test.tsx の非同期エラー
- "Save 失敗 → エラーメッセージ表示" テストで uncaught async error
- テスト自体は PASS するがエラーログが出力される
- 既存問題、テストインフラ起因ではない

### 5.4 オンボーディングフローの E2E テスト制約
- `app.fixture.ts` が `localStorage("oribis_onboarding_done") = "true"` を常に設定
- オンボーディング未完了状態のテストは fixture カスタマイズが必要

### 5.5 WebDriverIO E2E
- 実 Tauri バイナリを使用する E2E テスト（`pnpm test:wdio`）
- CI 対象外（バイナリビルド + GPU 必要）
- ローカル実行のみ

---

## 7. 次回テスト追加時のチェックリスト

### Unit テスト追加
- [ ] `src/components/__tests__/` or `src/adapters/` にテストファイル作成
- [ ] Tauri invoke が必要 → `createMockInvoke` 使用
- [ ] Three.js / VRM が必要 → `createThreeVRMMock` + `createR3FMock` 使用
- [ ] Context / Store が必要 → `renderWithProviders` 使用
- [ ] `pnpm test` で全量 PASS 確認

### Rust 統合テスト追加
- [ ] `src-tauri/tests/{module}_integration.rs` 作成
- [ ] `mod common;` でヘルパー import
- [ ] フィクスチャは `tests/fixtures/{domain}/` に JSON 格納
- [ ] I/O テストは `TempTestDir::new()` 使用
- [ ] MCP 関連は `#![cfg(unix)]` 付与
- [ ] tauri-backend 依存API はソース検証 or サブプロセスで対応
- [ ] `cargo test --test {name}` で PASS 確認
- [ ] E2E シナリオ JSON を `tests/e2e/scenarios/` に追加

### E2E シナリオ追加
- [ ] `e2e/scenarios/t-{番号}-{slug}.scenario.json` 作成
- [ ] セレクタは `rawSelector` で CSS 直接指定
- [ ] mock が必要なら `before` に `setMock` 追加
- [ ] mock 応答の型は `src/App.tsx` の `invoke<T>` から確認
- [ ] `cd e2e && pnpm test` で実行確認
