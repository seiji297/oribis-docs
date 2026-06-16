# Anima

## Overview

# Anima 仕様サマリ

## 参照 spec
- `projects/oribis-track-b/docs/spec/files/oribis-phase1-integrated.md`
- `projects/oribis-track-b/docs/spec/files/anima-spec.md`

## モジュール構成

| モジュール | ファイル |
|-----------|---------|
| parser | anima/parser.rs |
| cli_adapter | anima/cli_adapter.rs |
| cache | anima/cache.rs |
| db | anima/db.rs |
| memory | anima/memory.rs |
| task | anima/task.rs |
| throttle | anima/throttle.rs |
| counter | anima/counter.rs |
| context | anima/context.rs |
| pipeline | anima/pipeline.rs |

## マーカー仕様
- `[AFFINITY:N]`: last-occurrence 有効、±5 clamp
- `[ANIMA:expression=...,intensity=...,motion=...,gaze=...]`: 1件抽出、全件除去
- `[TASK:add/update/complete/remove:title:status]`: 複数対応
- `[MEMORY_SAVE:...]` / `[MEMORY_QUERY:...]`: 複数対応

## キャッシュパス
`~/.config/oribis/anima/anima_cache/{category}_{tier}.json`

## Implementation Notes

# Anima 実装ログ

## 2026-04-26 — Phase 1 (Prep) + Phase 2 (Track B) 完了

### Phase 1: Git Worktree Prep
- `feat/anima-track-a` / `feat/anima-track-b` ブランチ作成
- oribis-track-a / oribis-track-b worktree 作成
- scaffold (anima/mod.rs + 空ファイル群) commit 4322485
- 両ブランチ push 完了

### Phase 2: Track B 実装（AC: tdd-guide → codex-reviewer → DA）

#### Step 2: parser.rs (commit ce68ca7)
- 21 tests PASS
- AFFINITY last-occurrence, ANIMA/TASK/MEMORY マーカーパース
- Codex R1 FAIL（ANIMA replace→replace_all）→修正→R2 PASS
- DA: GO

#### Step 3: cli_adapter.rs (commit e2f922f)
- 6 tests PASS
- CliAdapter trait, Prompt/RawResponse, Backend enum, factory
- Codex PASS (LOW: streaming stub test) → バックログ
- DA: GO

#### Step 8: cache.rs (commit 49c00e3)
- 11 tests PASS
- AnimaCategory(13), AffinityTier(6), AnimaMode(3), 3段フォールバック
- Codex R1 FAIL（HIGH false positive + MEDIUM env var並列）→ serial_test 追加→R2 PASS
- DA: GO

### Phase 3: Integration 実装

#### context.rs 取込 + STUB 置換 (commits f93272f + cb1c3d2, branch: feat/anima-integration)
- feat/anima-track-a の context.rs を cherry-pick（f93272f）
- pipeline.rs の STUB build_context → context::build_context_at 置換（cb1c3d2）
- 型変換: context.LLMContext.history: Vec<serde_json::Value> → Prompt.history: Vec<String>（v.to_string()）
- format_active_tasks_for_prompt_at / format_counters_for_prompt_at: context.rs L76/L81 に存在確認
- テスト: 92件 PASS（従来73→増加）

#### Step 5: pipeline.rs (commit f568ccc, branch: feat/anima-integration)
- 13 tests PASS（全体: 73件 PASS）
- InputEvent/AnimaResponse enums, execute_pipeline, execute_ai, apply_response
- adapter injection パターン（MockCliAdapter でテスト）
- 6 stubs: build_context/determine_mode/apply_delta/append_to_history/execute_cache/get_project_backend
- Codex R1 FAIL（MEDIUM: env var並列汚染）→ serial_test 追加→R2 PASS（LOW: execute_pipeline直接テスト → BL-4）
- DA: GO

#### ClaudeCliAdapter send_message 本実装 (commits a11b0e7→a7a3f9a, branch: feat/anima-integration)
- 14 tests PASS（全体: 14 cli_adapter + 92 total）
- format_prompt_to_jsonl, extract_text_from_result, send_message with stream-json
- fake_claude バイナリ（ok/fail/malformed_json/multi_line 4モード）でテスト
- Codex R1 FAIL（exit code未確認）→ R2 FAIL（stdout drain + None=failure）→ R3 FAIL（env var並列）→ R4 FAIL（stdin/stdout逐次デッドロック）→ R5 PASS
- 修正系列: exit code check → drain loop → #[serial] → tokio::spawn 並行化
- DA: GO（AC1-5全PASS、HIGH/MEDIUM 0件）
- LOW BL追加: stdin write エラー握りつぶし → BL-5

### 合計テスト: 92件 PASS（Track A: context含む, Track B: 38, Integration pipeline+cli_adapter）

## 2026-04-27 — Phase 4: feat/character-integration 完了

### L-10: useAnima統合（前セッション完了）
- useAnima.ts: pipeline mode切替実装（commit 6ec66ef）
- AnimaState → execute_pipeline 経由に統合

### L-11: UI統合（本セッション）

#### L-11 必須項目 (commit 4c722e9)
- `AnimaChatResult` TypeScript interface に `anima_control` フィールド追加
- `character_chat` レスポンス後: `anima_control` → avatar制御（heuristic置き換え）
- `character_chat` レスポンス後: `loadProjectTasks(silent=true)` → TASK marker反映
- queue processor にも同様変更適用
- `loadProjectTasks(silent = false)` パラメータ追加（バックグラウンド呼出でalert抑制）

#### pipeline.rs メモリ副作用 (commit 1811098)
- `execute_chat_pipeline` に MEMORY_SAVE → `memory::memory_save` 追加
- `execute_chat_pipeline` に MEMORY_QUERY → `memory_search` + `push_pending_memory_results` 追加

#### L-11 オプション項目 (commit 7b10525)
- Memoryタブ: `memory_list_cmd` / `memory_delete_cmd` 呼出・表示・削除UI
- 好感度バッジ: tier別カラーコード（intimate/close/warm/neutral/cold/hostile）+ ★ラベル
- App.css: affinity-tier-* / memory-panel スタイル追加

### L-12: テスト結果
- Rust lib: 343 PASS（2件 parallel-flaky: env var race、単独実行PASS確認）
- integration tests: 68 PASS（1件 parallel-flaky: 同上）
- TypeScript: pre-existing failures のみ（変更対象外）

### ブランチ: feat/character-integration
- Commits: 6964c3b → 150c07d → 6ec66ef → 4c722e9 → 1811098 → 7b10525
- Push済み: origin/feat/character-integration

## 2026-05-01 — character_name / user_name 設定変数化

### 変更内容
- `ProjectPersonaConfig` に `character_name?: String` / `user_name?: String` 追加（`src-tauri/src/config.rs`）
  - デフォルトヘルパー: `default_character_name()` → `"Anima"`, `default_user_name()` → `"User"`
  - `Default` トレイト実装追加
- `format_for_l3_at()` シグネチャ変更: `character_name: &str` 引数追加（`src-tauri/src/character/history.rs`）
  - 呼び出し元 (history.rs テスト) を全件修正
- TypeScript `PersonaConfig` インターフェースに `characterName?: string` / `userName?: string` 追加
- `useAnima` フックに `userName?: string` オプション追加。フレーズ内の `プロデューサー` を動的置換
- プロンプトタブに「Anima名 / ユーザー名」入力フィールド追加（`src/App.tsx`）
- `normalizeLoadedPersona` / `persistProjects` で `characterName` / `userName` を引き継ぎ

## Known Issues / Backlog

# Anima 既知課題・バックログ

## バックログ（LOW優先度）

### BL-1: cli_adapter streaming stub テスト補強
- `send_message_streaming` の stub が Err を返すだけ → PASS 時のテスト追加
- 発生: Step 3 Codex LOW 指摘

### BL-2: cache env var 復元 guard
- `setup_temp_config()` が XDG_CONFIG_HOME/HOME を上書き後に復元しない
- `serial_test` で直列化済みのため実害低
- 発生: Step 8 Codex LOW 指摘

### BL-3: extract_with_fallback 抽出失敗→Ai 直接テスト
- 空キャッシュ配置 → extract_with_fallback が Ai を返すことの直接検証が未追加
- 発生: Step 8 Codex LOW 指摘

### BL-4: execute_pipeline 直接テスト
- Test 6/7 は execute_ai を直接呼び出しており execute_pipeline 分岐（determine_mode/backend選択）を通過しない
- execute_pipeline は内部で create_adapter を呼ぶためモック注入困難 → DI構造改善時に対処
- 発生: Step 5 Codex R1/R2 LOW 指摘

### BL-5: stdin write エラー握りつぶし
- `tokio::spawn` 内 `let _ = stdin.write_all(...)` でwrite失敗時ログなし
- result未到達として最終的に completed=false で返却されるため実害低
- 発生: ClaudeCliAdapter send_message実装 Codex R5 LOW 指摘

## 未実装モジュール（後続）
- context.rs（stub 置換済み: context::build_context_at に差し替え完了）
- db.rs（Track A 実装済み）
- 好感度・履歴・モード判定の stub 置換（Phase 2 後続ステップ）

---

## 2026-05-12 — DrawerAnima 内部タブ実装（branch: sysdev-1/oribis-orchestrator-p2）

### DrawerAnima コンポーネント（src/components/DrawerAnima.tsx）

左ドロワーの "Anima" タブ内に5つの内部タブを実装。

#### タブ構成

| タブ | 内容 |
|------|------|
| Status | animaState（mode/affinity）+ 会話履歴 |
| Prompt | L1プロンプト(ANIMA.md/SOUL.md) / Critical Prompt(L2) / AnimaPhrase+AnimaCache / Persona Prompts / local専用(CLAUDE.md/USER.md/agent.md) |
| Memory | カテゴリ別メモリ一覧（削除・セクション削除・Refresh・Raw表示） |
| Console | consoleLogs + consoleStreamLogs（[AI]/[Think]/[Tool]/[Done]色分け） |
| Settings | Connection(Path/Model/Permission/TTS) / Deep Reasoning(Model/Threshold) / Character(Name/UserName/Inference/Daily/Chat) |

#### 設計ポイント
- スタイル: CSS変数（`var(--c-*)` ）+ 既存CSSクラス（`custom-prompt-editor`, `custom-prompt-textarea`, `anima-cache-btn`, `console-view`, `console-entry`, `console-empty`, `memory-section`, `memory-h2`, `memory-li`, `memory-delete-btn` 等）
- アウターコンテナは `v2-menu-drawer` のglass background/blur を継承（独自 background/height 設定なし）
- L1プロンプト・Hook Injection・AnimaCache は全バックエンド対象（`backend === "local"` 限定解除）
- CLAUDE.md/USER.md/agent.md のみ local backend 限定

#### 関連コミット
- `c7f224e` — GeneralTab Orchestrator対応 + DrawerAnima設定統合
- `9a5f188` — Deep Reasoning delegation（DelegatingAdapter + threshold）
- `45d640e` — DrawerAnima 内部タブ実装（初版）
- `641c8e3` — DrawerAnima Prompt タブ修正（L1/L2/AnimaCache 全バックエンド対応）
- `0432867` — DrawerAnima CSSクラス化（インラインハードコード暗色削除）

#### テスト
- vitest: 568 PASS / cargo test: 1036 PASS（pre-existing failures のみ）

## 2026-06-16 — Anima Dispatch Approval UI（read-only closed loop / Phase 3）

### 目的

AnimaがWorker実行を提案し、policy/audit評価を表示し、ユーザー承認後にInternal Workerのread-only Jobを実行し、結果をAnimaの説明として返すUI。
既存のPTY Workerチャットとは分離し、Jobsタブ内で「提案」「承認」「実行結果」「説明」を1画面で追跡する。

### UI構成

| コンポーネント | 役割 |
|---------------|------|
| `AnimaDispatchPanel.tsx` | pending proposal一覧、read-only確認、承認/拒否、approval record、Anima explanation、Job詳細への導線 |
| `TaskJobView.tsx` | Internal Worker Job一覧、Job詳細、Event timeline、Artifact表示 |
| `ActionAuditPanel.tsx` | Action Router audit metadata表示。actor/capability/command/target/decisionをsecret非露出で表示 |
| `useDispatchProposal.ts` | `anima_list_dispatch_proposals` / approve / reject / refresh のhook |

### 表示・安全仕様

- proposalカードは `task` / `instruction` / sanitized `contextRefs` のみ表示する
- `credentialRef`、secret値、raw context snapshotは表示しない
- built-in toolsが全件 `readOnly=true` と確認できない場合、承認ボタンを無効化する
- policy評価が `allow` / `requireConfirmation` でない場合、承認ボタンを無効化する
- 承認後は `policyDecision` / `idempotencyKey` / `expiresAt` を含めて `anima_approve_and_run_readonly_dispatch` を呼び、成功時のみJob詳細を自動選択する
- backendも `policyDecision` / `idempotencyKey` 必須でfail-closedにし、UIを迂回したTauri直呼びを拒否する
- `completed` / `partial` のみ成功扱い。`failed` / `cancelled` / `timeout` / unknown status は失敗扱い
- backend生errorはUIに表示せず、汎用エラー文言に丸める
- Job/Event/Artifact表示でもsecret-like値をredactし、artifact pathはbasenameのみ表示する

### 実GUIテスト

- `e2e/wdio/tests/anima-approval.spec.ts`
  - JobsタブにAnima Dispatch PanelとTaskJobViewが表示される
  - `anima_propose_dispatch`でseedしたproposalを承認
  - read-only Job実行、approval record、Job詳細、Event timeline、Artifact/empty、Anima explanationを実GUIで確認
- `e2e/wdio/tests/action-platform.spec.ts`
  - JobsタブのInternal Worker実データ表示とJob詳細/Event/Artifact表示を確認
- `e2e/wdio/tests/anima-approval-policy.spec.ts`
  - pending proposalのstatus/policy表示を確認
  - auditパネルの行または空状態を確認
  - secret-like値が画面textに露出しないことを確認

### テスト結果（2026-06-16）

- `pnpm run typecheck`: PASS
- `pnpm vitest run`: 918 PASS / 3 skipped
- `cargo test anima_dispatch::tests job_selector::tests anima_explainer::tests anima_policy::tests action_router::tests internal_worker`: 83 PASS
- `cargo check --no-default-features --features tauri-backend`: PASS
- WDIO `anima-approval`: 2 scenarios PASS
- WDIO `anima-approval-policy`: 3 scenarios PASS
- WDIO `action-platform`: 5 scenarios PASS
- WDIO `action-platform`: 5 scenarios PASS
