# 統一応答パイプライン + CLI Adapter 設計書

**バージョン**: 2.1（spec-pipeline.md + spec-cli-adapter.md 統合、HTTP provider配線反映）
**最終更新**: 2026-06-14

---

## 1. 概要

全応答（ユーザーメッセージ・Anima通知）を単一パイプラインで処理する統一設計。

### 設計判断

- メインチャットとAnimaを**完全分離しない**（統一パイプライン採用）
- CLI Adapter抽象化でバックエンド差異を吸収
- `anthropic` / `openai_compat` は保存済みprovider設定を `ResolvedModelConfig` に解決し、HTTP providerへ直接接続する
- スクリプトファースト: LLM呼出は表現生成時のみ
- **CLI非依存原則**: マーカー方式でCLI共通動作。CLI固有機能に依存しない

---

## 2. InputEvent 型

```rust
pub enum InputEvent {
    UserMessage { text: String },
    AnimaState {
        category: AnimaCategory,
        context: Option<String>,
    },
}
```

テキスト入力からの変換:

```rust
pub fn parse_input_event(text: &str) -> InputEvent {
    if let Some(category) = parse_anima_notification(text) {
        InputEvent::AnimaState { category, context: None }
    } else {
        InputEvent::UserMessage { text: text.to_string() }
    }
}
```

Anima通知書式: `[システム通知: {category}]`（スペース有無どちらでも可）

### LLM入力への変換

```rust
pub fn event_to_llm_input(event: &InputEvent) -> String {
    match event {
        InputEvent::UserMessage { text } => text.clone(),
        InputEvent::AnimaState { category, context } => {
            let cat_str = category_to_string(category);
            match context {
                Some(ctx) => format!("[システム通知: {} ({})]", cat_str, ctx),
                None => format!("[システム通知: {}]", cat_str),
            }
        }
    }
}
```

`execute_pipeline()` 内で `Prompt.user_input` として使用。

---

## 3. PipelineResponse 型

```rust
pub enum PipelineResponse {
    Generated {
        text: String,
        affinity_delta: i8,
        raw_text: String,
        anima_control: Option<AnimaControl>,
        session_id: Option<String>,
        usage: Option<TokenUsage>,
    },
    CacheHit { text: String },
    Suppressed,           // throttleによりスキップ
    Error(String),
}
```

---

## 4. PipelineConfig

```rust
pub struct PipelineConfig {
    pub base_dir: PathBuf,
    pub project_id: String,
    pub backend: String,          // "claude" | "codex" | "local" | "anthropic" | "openai_compat" | ""
    pub anima_mode: AnimaMode,    // Cache / Ai / Hybrid
    pub context_mode: ContextMode, // StatefulSession | StatelessRequest
}
```

`anima_mode` は `anima_mode.toml` から読込。詳細 → `spec-anima.md`

`context_mode` はL3注入戦略を制御:
- `StatefulSession` — CLI/GUIチャット。コンテキストがターン間で保持される。`NormalTurn` では episodes のみ注入、`SessionStart` / `AfterCompaction` で全チャネル + 履歴を注入。
- `StatelessRequest` — API/Anima自動応答。各リクエストが独立。毎ターン全チャネル + 履歴を注入。

呼出元ごとのデフォルト設定:
- `anima_chat()` → `StatefulSession`（ユーザーとのGUIチャット）
- `anima_state()` → `StatelessRequest`（Anima自動応答）
- `generate_ai_response()` 内部 → `StatelessRequest` ハードコード（Anima通知フロー）

---

## 5. パイプライン処理フロー

### 5.1 エントリポイント

```
execute_pipeline(config, event, adapter)
  ├── InputEvent::AnimaState → execute_anima_pipeline()
  └── InputEvent::UserMessage → execute_chat_pipeline()
```

### 5.2 Animaパイプライン

```
execute_anima_pipeline(config, category, adapter)
  1. throttle::should_speak_at() → false → Suppressed
  2. load_affinity_at() → tier取得
  3. cache::cache_exists() → true → CacheHit
  4. AnimaMode確認
     - Cache  → キャッシュのみ（AI呼出なし）
     - Ai     → AI生成（キャッシュ不使用）
     - Hybrid → キャッシュあり→CacheHit、なし→AI生成
  5. build_context_at() → Prompt構築
  6. adapter.send_message() → LLM呼出
  7. parse_response() → マーカー解析
  8. affinity_delta処理（Animaは通常0）
  9. → Generated
```

### 5.3 チャットパイプライン

```
execute_chat_pipeline(config, text, adapter)
  1. counter::increment_counter_at("user_message")
  2. load_affinity_at() → affinity_value
  3. build_context_at() → Prompt構築（L2+L3）
  4. history::append_message_at() → ユーザーメッセージ記録
  5. adapter.send_message() → LLM呼出
  6. parse_response() → マーカー解析
  7. 後処理:
     a. affinity apply_delta_at()
     b. task::execute_task_operations()
     c. memory::memory_save_with_category() ← MEMORY_SAVEマーカー
     d. memory::push_pending_memory_results() ← MEMORY_QUERYマーカー（次ターンL3注入）
  8. history::append_message_at() → Animaメッセージ記録
  9. history::compress_at()
  10. → Generated
```

---

## 6. LLMコール構築（§18）

```
build_context_at(project_id, base_dir)
  └── ContextOutput {
        system: String,   // L1: CLAUDE.md全文
        dynamic: String,  // L2+L3: Critical Prompt + 動的注入
        history: Vec<Value>, // セッション開始時のみ30件
      }
```

Prompt送信構造:

```
[system]  → ContextOutput.system
[user]    → ContextOutput.dynamic + "\n\n" + user_input
[history] → ContextOutput.history（CLI側セッション内は不要）
```

---

## 7. スクリプト処理層の原則（§15）

| 処理 | 実装場所 |
|------|---------|
| Anima通知の種別判定 | `parse_anima_notification()` |
| throttle判定 | `throttle::should_speak_at()` |
| キャッシュ検索 | `cache::extract_with_fallback()` |
| マーカー解析 | `parser::parse_response()` |
| 好感度更新 | `affinity::apply_delta_at()` |
| タスク操作 | `task::execute_task_operations()` |
| 記憶保存 | `memory::memory_save_with_category()` |
| 履歴追記・圧縮 | `history::append_message_at()` / `compress_at()` |
| カウンター更新 | `counter::increment_counter_at()` |

LLMは**Anima表現生成のみ**に使用。

### 7.1 LLM必須処理

スクリプトで代替不可 → LLM呼出が必要な処理:

- セリフ本文生成（文脈考慮・キャラ表現）
- アバター制御パラメータ選択（[ANIMA:...]マーカー出力）
- 記憶保存判断（重要情報の自律検知）
- タスク管理判断（文脈からのadd/update/complete判定）
- キャッシュ生成時のセリフ生成（オフライン）

### 7.2 純関数優先設計

副作用を持つ処理と副作用のない処理を明確に分離:

- 判定・変換・パースは純関数として実装（テスト容易性）
- 副作用（ファイルIO・LLM呼出）は明示的に上位層に集約
- `_at(base_dir, ...)` パターン = ファイルパス構築を引数化してテスト可能に

---

## 8. CLI Adapter（§5）

### 8.1 CliAdapter トレイト

```rust
#[async_trait]
pub trait CliAdapter: Send + Sync {
    fn name(&self) -> &str;

    async fn send_message(
        &self,
        prompt: Prompt,
    ) -> Result<RawResponse, anyhow::Error>;

    async fn send_message_streaming(
        &self,
        prompt: Prompt,
        tx: mpsc::Sender<StreamChunk>,
    ) -> Result<RawResponse, anyhow::Error>;
}
```

### 8.2 Prompt 型

```rust
pub struct Prompt {
    pub system: String,            // L1: CLAUDE.md全文
    pub dynamic: String,           // L2+L3: Critical Prompt + 動的注入
    pub history: Vec<serde_json::Value>, // セッション開始時のみ30件、それ以外は空
    pub user_input: String,        // ユーザー発話 or [システム通知:...]
    pub session_id: Option<String>, // CLIセッション継続ID
}
```

### 8.3 RawResponse 型

```rust
pub struct RawResponse {
    pub text: String,              // LLM応答テキスト（マーカー含む）
    pub completed: bool,           // ストリーミング完了フラグ
    pub error: Option<String>,     // エラーメッセージ（Some = エラー）
    pub session_id: Option<String>, // セッションID（次ターン継続用）
    pub usage: Option<TokenUsage>, // トークン使用量
}
```

### 8.4 TokenUsage 型

```rust
pub struct TokenUsage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_input_tokens: u64,
    pub cache_creation_input_tokens: u64,
    pub total_cost_usd: Option<f64>,
    pub duration_ms: Option<u64>,
    pub num_turns: Option<u64>,
}
```

### 8.5 Backend 列挙型 + Factory

```rust
pub enum Backend {
    Claude,
    Codex,
    Local,
}

pub fn create_adapter(backend: Backend) -> Box<dyn CliAdapter> {
    match backend {
        Backend::Claude => Box::new(ClaudeCliAdapter::new()),
        Backend::Codex => Box::new(CodexCliAdapter::new()),
        Backend::Local => Box::new(LocalLlmAdapter::new()),
    }
}
```

文字列対応:
- `"claude"` → Claude CLI互換経路
- `"codex"` → Codex CLI経路
- `"local"` / `""` → OpenClaw/ローカル経路
- `"anthropic"` → `provider_config.json` から `AnthropicProvider`
- `"openai_compat"` → `provider_config.json` から `OpenAICompatProvider`

`anthropic` / `openai_compat` はClaude CLIへフォールスルーしない。保存済みproviderとプロジェクトbackendが一致しない場合は設定エラーとして停止する。

### 8.6 ストリーミング

`send_message_streaming()` は `mpsc::Sender<StreamChunk>` で差分テキストを送信。

マーカー処理:
- ストリーミング中は `[` 検知後バッファリング
- `]` で閉じたらマーカー候補として評価
- ストリーム終了後の `RawResponse.text` からまとめて解析する方が安全

### 8.7 対応バックエンド

| Backend | 実装クラス | 状態 |
|---------|-----------|------|
| Claude CLI（Claude Code） | `ChatCoreAdapter` | 実装済 |
| Codex CLI（GPT系） | `CodexChatAdapter` | 実装済 |
| OpenCode CLI | `OpenCodeChatAdapter` | 実装済 |
| ローカルLLM/OpenClaw | `OpenClawChatAdapter` | 実装済 |
| Anthropic Messages API | `BackendProviderAdapter` → `AnthropicProvider` | 実装済 |
| OpenAI互換 Chat Completions API | `BackendProviderAdapter` → `OpenAICompatProvider` | 実装済 |

#### 8.7.1 provider_config.json

Onboardingで保存したAI provider設定は `provider_config.json` に永続化する。

```json
{
  "provider": "anthropic",
  "api_key": "dummy-key",
  "model": "claude-sonnet-4-5"
}
```

`openai_compat` の場合は保存時にAPI rootを明示値として保持する。

```json
{
  "provider": "openai_compat",
  "api_key": "dummy-key",
  "model": "gpt-4.1",
  "base_url": "https://api.openai.com"
}
```

読込処理は型付き構造体で行い、以下の3段階を分離する。

1. parse / validate: provider、APIキー、model、base URLを検証する。
2. normalize: `ModelConfig` へ変換する。
3. resolve: APIキーを含む `ResolvedModelConfig` を構築する。

`openai_compat` の `base_url` はAPI rootであり、`/v1/chat/completions` を含めない。末尾スラッシュは正規化し、認証情報埋め込みURL、不正URL、古いJSONのbase URL欠落は明示エラーとする。

#### 8.7.2 BackendProviderAdapter

`BackendProviderAdapter` はHTTP providerを既存 `CliAdapter` パイプラインへ接続するアダプターである。HTTP/SSE処理は `AnthropicProvider` / `OpenAICompatProvider` に委譲し、adapter側でprovider別HTTP処理を複製しない。

Prompt変換規則:
- `Prompt.system` と `Prompt.dynamic` は順序を保って `ConversationRequest.system_prompt` に統合する。
- `Prompt.history` は既存message列として保持する。
- `Prompt.user_input` は末尾のuser messageとして1回だけ追加する。
- `Prompt.session_id` は `ConversationRequest.conversation_id` に渡す。

応答写像規則:
- `StreamEvent::Done` 受信のみ成功完了とし、`RawResponse.completed = true`、`error = None` を返す。
- `Done.final_response.text` を `RawResponse.text` に写像する。
- `Done.usage` を `RawResponse.usage` に写像する。
- providerの `conversation_id` がある場合のみ `RawResponse.session_id` に写像する。
- provider error、Done欠落、channel closeのみの終了は成功扱いしない。

#### 8.7.3 Anthropic streaming完了条件

`AnthropicProvider::complete()` はstream producerとconsumerを同時に進める。容量64のchannelが満杯になっても停止しないことを100 delta SSEテストで確認済み。

成功条件:
- `StreamEvent::Done` を受信した場合のみ成功。
- usageは `Done` 由来を正とする。

失敗条件:
- `StreamEvent::Error` は即時失敗。
- producerが正常終了しても `Done` 未受信なら `StreamClosed`。
- channel closeだけでは成功しない。

### 8.8 projects.toml でのバックエンド設定

```toml
[project.default]
backend = "claude"

[project.my-project]
backend = "codex"
critical_prompt = "..."
```

### 8.9 session_id 設計判断

- CLIコンテキスト継続に使用
- セッション開始時は None、継続時は前ターンのIDを渡す
- Adapter層でClaudeのTool Use形式 vs Codexのfunction calling形式差異を吸収

---

## 9. エラー処理（§21 詳細）

### 9.1 LLM呼出失敗

- タイムアウト → リトライ1回 → Cacheフォールバック
- 接続不可 → Cacheフォールバック
- レスポンス不正 → 警告ログ + Cacheフォールバック
- `raw.error` が Some → `Error(raw.error)` 返却

### 9.2 永続化失敗

- 好感度書込失敗 → メモリ上の値で継続、警告ログ
- 履歴書込失敗 → メモリ上の値で継続、警告ログ
- 記憶書込失敗 → 警告ログ
- カウンタ書込失敗 → 警告ログ
- 起動時整合性失敗 → 初期値で再生成
- affinity/history/memory のIO失敗 → `let _ =` で無視して処理続行

### 9.3 マーカーパース失敗

- AFFINITY マーカー不正 → delta=0
- ANIMA マーカー不正 → 既存FALLBACKテーブルからフォールバック
- TASK マーカー不正 → 操作スキップ、警告ログ
- MEMORY_SAVE 不正 → 操作スキップ、警告ログ
- 数値範囲外 → クランプ

### 9.4 キャッシュ失敗

- ファイル不在 → 既存FALLBACKテーブル使用
- パース失敗 → 該当ファイル削除 + 既存FALLBACK使用
- throttle/cache のIO失敗 → エラー扱いせずデフォルト動作継続

### 9.5 CLI Adapter失敗

- backend不在 → 起動失敗 or デフォルト切替
- セッション切断 → 再接続試行 → 失敗時新規セッション
- `anthropic` / `openai_compat` のprovider設定欠落・不一致 → Claude CLIへフォールバックせず設定エラー
- HTTP provider streamがDoneなしで閉じた場合 → `StreamClosed`

---

## 10. 拡張設計（§22）

- バックエンド追加: CLI系は `CliAdapter` trait 実装、HTTP provider系は `BackendProvider` 実装 + `BackendProviderAdapter` 接続
- AnimaCategory追加: `AnimaCategory` enum + `to_cache_category()` マッピング追加
- L3注入項目追加: `build_context_at()` の dynamic 構築部を拡張
- 新マーカー追加: `parser::parse_response()` に解析規則追加 + 後処理追加

---

## 11. 実装場所

- `src-tauri/src/anima/pipeline.rs` — パイプライン本体
- `src-tauri/src/anima/cli_adapter.rs` — CliAdapter トレイト・型・BackendProviderAdapter
- `src-tauri/src/anima/providers/mod.rs` — HTTP provider factory
- `src-tauri/src/anima/providers/anthropic.rs` — Anthropic Messages API provider
- `src-tauri/src/anima/providers/openai_compat.rs` — OpenAI互換 Chat Completions provider
- `src-tauri/src/anima/context.rs` — `build_context_at()`（L2/L3構築）
- `src-tauri/src/anima/parser.rs` — `parse_response()`（マーカー解析）
- `src-tauri/src/anima/throttle.rs` — `should_speak_at()`
- `src-tauri/src/anima/cache.rs` — キャッシュ管理
- `src-tauri/src/lib.rs` — Tauri command、provider_config保存/読込、backend選択

---

## 12. 関連ドキュメント

- `spec-markers.md` — マーカー仕様
- `spec-prompt-layers.md` — L1/L2/L3構造
- `spec-anima.md` — AnimaMode・throttle・スマートキャッシュ
- `architecture-diagrams.md` §3/§4/§12/§13/§14 — パイプライン・Adapterフロー図

---

## 13. 生成中断（cancel_current_generation）仕様

### 目的

ユーザーがストップボタン押下 or 新規メッセージ送信時に、進行中のAI生成を中断する。
Claude CLI / Codex / OpenClaw 全バックエンドで共通動作すること。

### Rust: `cancel_chat(project_id: String)` コマンド

```rust
// ProjectChatState に追加
pub async fn cancel_current_generation(&self) {
    // 1. running フラグが false なら即return
    if !self.running.load(Ordering::SeqCst) { return; }

    // 2. アクティブなバックエンドを検出してSIGINT送信
    if let Ok(mut guard) = self.proc.try_lock() {
        if let Some(proc) = guard.as_mut() {
            proc.send_sigint().await;  // Claude CLI / OpenClaw
        }
    }
    if let Ok(mut guard) = self.codex_proc.try_lock() {
        if let Some(proc) = guard.as_mut() {
            proc.send_sigint().await;  // Codex
        }
    }

    // 3. running フラグリセット（RunGuardが落ちていない場合のフォールバック）
    self.running.store(false, Ordering::SeqCst);
}
```

`PersistentProc` / `CodexAppServerProc` どちらにも `send_sigint()` を追加:
```rust
async fn send_sigint(&mut self) {
    // Unix: kill(pid, SIGINT). Windows: GenerateConsoleCtrlEvent
    #[cfg(unix)]
    if let Some(id) = self.child.id() {
        let _ = nix::sys::signal::kill(
            nix::unistd::Pid::from_raw(id as i32),
            nix::sys::signal::Signal::SIGINT,
        );
    }
    #[cfg(windows)]
    let _ = self.child.kill().await;  // Windows: killで代替
}
```

### Frontend: ストップボタン

- 表示条件: `cliState === 'thinking' || cliState === 'responding'`
- 位置: 入力欄右側（send ボタンと排他表示）
- アイコン: ■（StopCircle）
- 動作:
  1. `invoke('cancel_chat', { projectId })` を呼ぶ
  2. `markIdle()` でローカルstate即時更新（UX改善）

### 新規メッセージ送信時の自動キャンセル

```ts
const sendMessage = async (text: string) => {
    if (cliState !== 'idle') {
        await invoke('cancel_chat', { projectId: activeProject.id });
    }
    // 通常送信処理へ
    markRequestStart();
    await invoke('character_chat', { ... });
};
```

### バックエンド別動作

| バックエンド | SIGINT後の動作 |
|---|---|
| Claude CLI | 生成中断、部分応答または空で終了 |
| Codex | 生成中断 |
| OpenClaw | 生成中断（実装時に確認） |

*追記日: 2026-05-01*

---

## 14. CLI コンテキスト圧縮検知・再注入

### 14.1 背景

CLI（Claude Code / OpenCode / Codex）はコンテキスト窓が上限に達すると内部圧縮を実行する。圧縮後は過去の会話が要約に置き換わるため、L3で注入した記憶・タスク・好感度情報が失われる。

このセクションでは各バックエンドの圧縮検知手段と、検知後の L3 再注入フローを定義する。

### 14.2 アーキテクチャ

バックエンド固有のフックを**統一イベント**にマッピングし、コアハンドラに委任する。

```
┌─────────────────────────────────────────────────┐
│  CLI Backend Adapter（バックエンド固有）          │
│  Claude Code / OpenCode / Codex                  │
│  責務: バックエンド固有フック → 統一イベント変換   │
└──────────────┬──────────────────┬────────────────┘
               │                  │
     CompactPhase::Pre    CompactPhase::Post
               │                  │
               ▼                  ▼
     on_pre_compact()    on_post_compact()
     （§14.5）            （§14.6）
     コアハンドラ          コアハンドラ
```

### 14.3 バックエンド → 統一イベント マッピング

| バックエンド | バックエンド固有フック | → CompactPhase | 備考 |
|---|---|---|---|
| Claude Code | `PreCompact` | `Pre` | Phase 1 |
| Claude Code | `PostCompact` | `Post` | Phase 1・primary |
| Claude Code | `SessionStart(source="compact")` | `Post` | **フォールバック専用**（PostCompact未受信時のみ発火） |
| OpenCode | `experimental.session.compacting` | `Pre` | Phase 2 |
| OpenCode | `session.compacted` | `Post` | Phase 2 |
| Codex | なし（§14.4 参照） | degraded mode | フック不在・ベストエフォート |

**SessionStart(source="compact") の二重発火防止**: PostCompact が正常に受信された場合、同一圧縮に対する SessionStart(compact) は無視する。`compaction_id` で同一圧縮を識別する。

```rust
/// 統一イベント型
pub struct CompactEvent {
    pub phase: CompactPhase,
    pub compaction_id: Option<String>,  // 同一圧縮の二重発火防止用
}

pub enum CompactPhase {
    Pre,   // 圧縮開始前 → on_pre_compact()
    Post,  // 圧縮完了後 → on_post_compact()
}

/// CLI Adapter が実装するトレイト
pub trait CompactAware {
    /// バックエンド固有フックを統一イベントに変換して返す
    fn detect_compact(&self) -> Option<CompactEvent>;
}

/// Post 二重発火防止（SessionStart(compact) fallback 専用）
/// Pre/Post は同一 compaction_id でも独立して処理する
fn should_handle_post(event: &CompactEvent, post_handled: &mut HashSet<String>) -> bool {
    if event.phase != CompactPhase::Post {
        return true;  // Pre は常に処理（Post dedupe の対象外）
    }
    match &event.compaction_id {
        Some(id) => post_handled.insert(id.clone()),  // Post 既処理なら false
        None => {
            // ID 取得不能時（一部バックエンドの fallback event）:
            // 直近の Post 処理から 5秒以内なら二重発火とみなし skip
            !recently_handled_post_within(Duration::from_secs(5))
        }
    }
}
```

### 14.4 Codex 代替策（degraded mode）

2026-05 時点で Codex CLI には圧縮検知フックが存在しない。**Pre/Post と同等の保証は不可能**であり、ベストエフォートのチェックポイント方式で代替する。

**Pre 代替（proactive checkpointing）**:
- 一定ターン数（例: 50ターン）ごとに `on_pre_compact()` を定期実行
- history.jsonl の件数監視で間接的に長セッションを検知
- 圧縮直前のタイミングは保証されない（チェックポイント後〜実際の圧縮の間にデータが失われる可能性あり）

**Post 代替（heuristic detection）**:
- 応答に L3 情報の欠落兆候（好感度・タスク言及なし）がある場合に `on_post_compact()` を補完実行
- 偽陽性（LLMが単にL3情報に言及しなかっただけ）のリスクあり → 再注入は冪等であるため害は小さい

### 14.5 on_pre_compact() — 圧縮前フラッシュ

`CompactPhase::Pre` のコアハンドラ。CLIコンテキスト窓が要約に置換される前に、永続ストレージの整合性を確保する。

**全ステップはシリアライズ実行**（compaction mutex 下で排他的に実行し、並行書き込みによる torn snapshot を防止する）。

```rust
pub fn on_pre_compact(base_dir: &Path, project_id: &str) -> Result<()> {
    let _lock = COMPACT_MUTEX.lock()?;  // 排他ロック

    // 1. パイプライン受付停止 + 未処理フラッシュ
    //    新規メッセージの受付を一時停止し、処理中の oribis-meta 抽出を完了させる
    quiesce_and_flush_pipeline(base_dir, project_id)?;

    // 2. 固定コンテキスト源の永続化
    //    バッファ中の affinity delta / tasks 変更を確実にファイルに書き出す
    flush_fixed_context_stores(base_dir, project_id)?;

    // 3. Level 1 consolidation の前倒し実行
    //    通常はセッション終了時のみ実行される memory_events → memories 昇格を
    //    圧縮前に実施し、重要な記憶を memories テーブルに確定させる
    consolidate_level1(base_dir)?;

    // 4. open_loops の priority 再計算
    //    圧縮後に注入される open_loops の優先度が正確であることを保証
    refresh_open_loop_priorities(base_dir)?;

    Ok(())
}
```

| ステップ | 処理 | 理由 |
|---------|------|------|
| 1. パイプライン停止+フラッシュ | 受付停止 → 未処理 oribis-meta を memory_events に書き込み | 永続化漏れ防止 + 並行書き込み排除 |
| 2. 固定コンテキスト永続化 | affinity.json / tasks.json のバッファ書き出し | on_post_compact() で最新値を再注入するため |
| 3. Level 1 consolidation | memory_events → memories 昇格 | 通常セッション終了時のみの処理を前倒し |
| 4. open_loops 再計算 | priority・staleness を更新 | 圧縮後の L3 注入精度を保証 |

**レイテンシ目標**: < 500ms（圧縮自体にも時間がかかるため許容範囲）

**quiesce 解除**: `COMPACT_MUTEX` のスコープ終了（`_lock` drop）で自動解除される。`on_pre_compact()` 復帰後、通常のパイプライン処理が再開する。CLI側の圧縮処理中はそもそも新規メッセージが発生しないため、実質的にはロック期間 ≒ フラッシュ処理時間のみ。

### 14.6 on_post_compact() — 圧縮後 L3 再注入

`CompactPhase::Post` のコアハンドラ。圧縮でLLMが失った動的状態を永続ストレージから再構築して注入する。

**read-side 競合への対処**: `on_post_compact()` は圧縮完了直後に実行されるため、通常のパイプライン処理が再開する前に呼ばれる。万一並行書き込みと競合した場合でも、再注入は「最善努力のスナップショット」であり、次ターンの通常 L3 注入で最新値に上書きされるため、一時的な不整合は許容する。

```rust
pub fn on_post_compact(base_dir: &Path, project_id: &str) -> Result<String> {
    // 1. 直近30件の履歴を history.jsonl から再読込（フィルタリング付き）
    let history = recent_messages_at(base_dir, 30)?;
    let filtered = filter_for_reinjection(&history);

    // 2. 4チャネル記憶注入を再構築（prompt-layers.md §4 参照）
    //    - profile / open_loops / episodes: memory.db から取得
    //    - counters: event_counters.json から取得（SQLite統合前）
    let memory_context = build_memory_channels(base_dir)?;

    // 3. 好感度・タスク・時刻の固定注入を再生成
    let fixed_context = build_fixed_context(base_dir, project_id)?;

    // 4. 結合してユーザーメッセージプレフィックスとして返却
    Ok(format_reinject_context(&filtered, &memory_context, &fixed_context))
}
```

| ステップ | 処理 | データソース |
|---------|------|------------|
| 1. 履歴再読込 | 直近30件取得 + フィルタリング | `history.jsonl` |
| 2-a. 記憶3チャネル | profile / open_loops / episodes 再構築 | `memory.db` |
| 2-b. counters チャネル | 直近7日のカウンタ取得 | `event_counters.json`（SQLite統合後は `memory.db`） |
| 3. 固定注入 | 好感度・進行中タスク・現在時刻 | `affinity.json` / `tasks.json` |
| 4. フォーマット | セッション開始時注入と同一形式に結合 | — |

**履歴フィルタリングルール**（`filter_for_reinjection`）:
- source が `User` / `AnimaMain` / `AnimaAutonomous` のメッセージのみ対象
- text が空 or ホワイトスペースのみのエントリは除外
- 1エントリあたり最大200文字に切り詰め（トークン上限超過防止）
- フィルタリング後も30件に満たない場合は追加読込しない（圧縮後は最小限で十分）

**注入フォーマット**: セッション開始時（prompt-layers.md §4）と同等。

```
[これまでの会話]
（直近30件の履歴）

[好感度: +63（良好）]
[現在時刻: 2026-04-26 23:45 月曜]

[進行中タスク]
- [in_progress] AFDバグ修正

[あなたが覚えていること]
- 緑茶好き（食べ物）
- 夜型だが早朝作業を好む（習慣）

[気にかけていること]
- 明日14時に面接がある

[最近の出来事]
- 昨日: プロジェクト開始を報告

[行動カウンタ]
- lewd: 12回（30日: 8、7日: 3）
```

**サイズ目標**: 〜1500トークン（セッション開始時と同等）

### 14.7 実装場所

| モジュール | 責務 |
|-----------|------|
| CLI Adapter（バックエンド別） | `CompactAware` トレイト実装、フック→統一イベント変換 |
| `src-tauri/src/anima/compact.rs` | `on_pre_compact()` / `on_post_compact()` コアハンドラ |
| `src-tauri/src/anima/context.rs` | `build_memory_channels()` / `build_fixed_context()` |
| `src-tauri/src/anima/memory_db.rs` | `consolidate_level1()` / `refresh_open_loop_priorities()` |

*追記日: 2026-05-06*
