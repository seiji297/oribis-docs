# Worker直接指示機能 設計書

**作成日**: 2026-05-21
**ステータス**: 実装完了（Phase 1）
**関連**: design-commercial-io-channels-20260521.md

## 背景

Oribisデスクトップアプリにおいて、Human→Worker直接指示パスが未実装。現状はUI→anima_chat→LLM推論→execution_engine→Worker spawnの経路のみ。Producerの要件:「CLIの直接入力と同じ使い勝手」「Animaの記憶データ保存なども通常通り動作」「速度重視でLLM推論スキップ」。

### Producer原文
- 「何もつけなければAnimaに対しての内容とする」
- 「デフォルトWorkerは不要かな」
- 「Animaは、人間がWorkerに対して直接指示したことを把握してほしい。Animaの動作はさっきも言った通り通常通り行う想定。ただしこの辺の細かい設定は色々オフも可能」
- 「PTYそのものもいじれるなら、CLI直接いじるほうが早い問題なっｂとかなるくね？これも追加で。現状維持れる設計だと思うが、より直感的に維持れるよう修正」

## 確定方針

### UI: チャット欄統一 + @メンションルーティング + PTYパネル併用

```
[チャット入力欄]（既存と同じ1つの入力欄）

@SysDev ファイル修正して    → SysDev Worker直接dispatch
@AFD バグ調査して           → AFD Worker直接dispatch
ファイル修正して            → Anima会話（@なし = 常にAnima）
今日の調子は？             → Anima会話
```

- モード切替UI不要（既存チャット欄そのまま）
- **@メンション必須**。デフォルトWorkerなし。@なし=常にAnima
- @入力で補完候補リスト表示（登録済みWorker alias一覧）
- 分類器: 正規表現ベース（LLM推論なし・1ms以下）
- **PTYパネル直接操作も維持**（後述）

### 2経路の使い分け

| 経路 | 用途 | 記憶保存 | UI |
|------|------|---------|-----|
| チャット欄@メンション | 構造化された指示。Anima把握・記憶保存あり | あり（二層構造） | チャット欄インライン表示 |
| PTYパネル直接入力 | CLI同等の自由入力。raw操作 | MCP memory_save経由（Worker自身が保存） | XtermTerminal（既存） |

---

## @メンション分類器（DispatchIntent）

### 解決ルール

1. `@`の直後トークンが**登録済みWorker aliasと完全一致**した場合のみWorker宛て
2. メンションは**文頭または空白/改行直後**のみ有効
3. 以下の`@`は無視:
   - コードブロック内（\`\`\`....\`\`\`）
   - 引用内（> ...）
   - メールアドレス形式（xxx@yyy.zzz）
   - URL内
4. alias正規化: 大文字小文字無視、全角半角正規化
5. 複数メンション（`@SysDev @AFD`）: 先頭の1つのみ有効（複数Worker同時dispatch禁止）

### DispatchIntent正規化

```rust
struct DispatchIntent {
    intent_type: IntentType,      // CompanionChat | WorkerDispatch
    target_worker_id: Option<String>,
    project_id: String,
    message: String,
    routing_reason: String,       // "explicit_mention:SysDev" / "no_mention"
}

enum IntentType {
    CompanionChat,     // @なし → Anima会話
    WorkerDispatch,    // @alias → Worker直接dispatch
}
```

### 分類フロー

```
入力テキスト
  → コードブロック/引用/URL/メール除外
  → 文頭or空白後の@トークン抽出
  → Worker alias完全一致チェック
    → 一致: WorkerDispatch（worker_id解決）
    → 不一致: CompanionChat（通常Anima会話）
  → @なし: CompanionChat
```

---

## バックエンド: anima_direct_dispatch

```
anima_direct_dispatch(worker_id, task, sender)
  → [同期] タスクサニタイズ（制御文字除去 + 4096文字制限）
  → [同期] WorkerManager.validate_dispatch_target(worker_id) — Idle確認
  → [同期] DispatchIntent生成（ULID dispatch_id）
  → [同期] WorkerManager.dispatch(worker_id, intent) — status=Running化
  → [同期] PTY write（pty_write経由）— ベストエフォート
  → [同期] イベント記録:
    → WorkerOps: "Human→{worker_id}: {task先頭100文字}"
    → Companion: "observed_human_direct_dispatch: {worker_id}"
  → [同期] Tauri Event emit("worker-dispatch-{worker_id}", payload)
  → [非同期] enrich_dispatch_event(dispatch_id, worker_id) — スタブ（ログのみ）
```

### 実装済みTauriコマンド

```rust
// lib.rs
#[tauri::command]
async fn anima_direct_dispatch(
    worker_id: String,
    task: String,
    sender: String,
    app_handle: tauri::AppHandle,
) -> Result<DirectDispatchResult, String>

#[tauri::command]
async fn cancel_direct_dispatch(
    worker_id: String,
    dispatch_id: String,
    app_handle: tauri::AppHandle,
) -> Result<(), String>
```

### DirectDispatchResult

```rust
pub struct DirectDispatchResult {
    pub dispatch_id: String,   // ULID一意ID
    pub worker_id: String,
    pub status: String,        // "dispatched"
}
```

### DispatchIntent（worker_manager.rs）

```rust
pub struct DispatchIntent {
    pub target_worker_id: String,
    pub task: String,
    pub sender: String,
    pub dispatch_id: String,   // ULID
    pub created_at: String,
}
```

### cancel_direct_dispatch フロー

```
cancel_direct_dispatch(worker_id, dispatch_id)
  → WorkerManager.cancel_dispatch(worker_id, dispatch_id) — active_dispatch_idクリア+Idle化
  → PTY write("\x03") — Ctrl+C送信（ベストエフォート）
  → キャンセルイベント記録（WorkerOps）
  → Tauri Event emit
```

---

## 記憶保存: 二層構造

### 同期層（LLMなし・高速）

`events::append_event()`で事実記録。

```rust
NewMemoryEvent {
    kind: "worker_direct_instruction",
    domain: "WorkerOps",
    source: "human_direct",
    content: "Human→{worker_id}: {message}",
    salience: None,           // LLMなしのため未評価
    valence: None,
    arousal: None,
    novelty: None,
    entities: vec![],
    topics: vec![],
    semantic_enriched: false,  // LLM未処理マーカー
}
```

### 非同期層（オフ可能）

Worker完了後にLLM後処理で記憶enrichment:
- PTY出力を圧縮・重要行抽出（上限トークン制御）
- 秘匿情報マスキング後にLLMへ
- 生成結果はoribis-metaに近い形で保存
- `semantic_enriched: true`に更新
- 失敗してもdispatch自体は成功扱い

### domain分離

| イベント | domain | 用途 |
|---------|--------|------|
| 人間→Worker直接指示 | WorkerOps | 実操作ログ |
| Worker応答・完了・失敗 | WorkerOps | 実操作ログ |
| Anima把握（「人間がWorkerに指示した」） | Companion | Animaの自己状態・ユーザー理解 |
| LLM後処理 enriched memory | Companion | 意味づけ済み記憶 |

---

## チェックポイントイベント（長時間タスク対応）

```
worker_dispatch_requested  → dispatch開始時（同期・必須）
worker_dispatch_started    → Worker受理確認時
worker_output_chunk        → 要約済み中間ログ（30秒〜2分間隔）
worker_progress_checkpoint → 出力サイズ閾値ごと
worker_completed           → 正常完了
worker_failed              → 異常終了（partial enrichmentも実行）
worker_cancelled           → ユーザーキャンセル
worker_timeout             → タイムアウト
```

- 全PTY出力をevent storeに入れない。メタデータ+要約のみ
- 完全ログは別ストレージ（ファイル or 専用テーブル）
- enrichment jobは冪等。`dispatch_id`単位で再実行可能

---

## Worker応答表示: チャット欄インライン

```
[あなた] @SysDev ファイル修正して
[Worker:SysDev-1] (Run: abc123)
  > ファイル確認中...
  > src/lib.rs を修正
  > cargo test PASS
  > 完了。3ファイル修正
  [▼ 詳細ログ] [■ 停止] [↻ 再送]
```

### PTY出力ストリーミング設計

```
Worker PTY output
  → Rust側リングバッファ蓄積（PTY読み取りは止めない）
  → 50-100ms時間窓バッファリング or 4-16KBチャンク単位
  → Tauri Event emit（worker-output / worker-status / worker-error）
  → React UIバッチappend（逐次state更新回避）
  → チャット欄インライン: 最新200-500行のみ表示
  → 古い行: 折りたたみ（"... N lines omitted"）
  → 完全ログ: PTYパネル展開 or 別ログビュー
```

### バックプレッシャー

- PTY読み取りは止めない（Workerプロセス詰まり防止）
- バックエンドでリングバッファ蓄積
- UIイベント送信はレート制限
- UIが遅延→インライン表示は最新チャンクに追随
- 完全ログはファイル/DBに追記（Tauri Eventを唯一の保存元にしない）
- ANSIエスケープはサニタイズ。HTML直接挿入禁止
- Workerごと・sessionごとに`output_seq`で順序保証

---

## PTYパネル直接操作（既存維持+改善）

既存XtermTerminal.tsx（pty_spawn/write/read/kill）を維持。CLI直接操作の経路として併用。

### 現状維持する機能
- PTY spawn/write/read/kill
- xterm.jsによるANSI/カラー/インタラクティブ対応
- Worker spawn時のPTY自動作成

### UI改善（設計書スコープ）

```
┌─ Worker PTY Panel ────────────────┐
│ [Worker: SysDev-1 ▾] [● 接続中]  │
│ ┌─ xterm ────────────────────────┐│
│ │ $ claude --project /path       ││
│ │ > ファイル確認中...            ││
│ │ > 修正完了                     ││
│ │ _                              ││
│ └────────────────────────────────┘│
│ [Detach] [Kill] [New PTY]         │
└───────────────────────────────────┘
```

- **Worker選択ドロップダウン**: 起動中Workerの一覧から切替
- **接続状態表示**: 接続中/切断/停止
- **Detach/Attach**: PTYセッションの切り離し・再接続
- PTYパネル経由の入力はWorker自身のMCP memory_save経由で記録（既存動作）
- チャット欄@メンション経由のdispatchとPTYパネル直接入力は独立動作

### 2経路の記憶保存比較

| 項目 | チャット@メンション | PTYパネル直接 |
|------|-------------------|--------------|
| 記憶保存主体 | Oribis Core（anima_direct_dispatch） | Worker自身（MCP memory_save） |
| domain | WorkerOps + Companion | WorkerOps（MCP固定） |
| Anima把握 | あり（設定ON時） | なし（Worker自己記録のみ） |
| LLM後処理 | あり（設定ON時） | なし |
| 入力記録 | InputEvent自動記録 | なし（PTY raw入力） |
| 用途 | 構造化指示・監査必要時 | CLI同等の自由操作・デバッグ |

---

## 設定（全ON/OFF可能）

| 設定キー | 説明 | デフォルト | OFF時の動作 |
|---------|------|----------|------------|
| direct_dispatch.event_record | イベント記録 | ON | **最小監査ログのみ残す**（dispatch fact記録） |
| direct_dispatch.memory_save | 記憶保存（同期層） | ON | 同期イベント記録スキップ |
| direct_dispatch.anima_awareness | Anima把握イベント | ON | Companionドメインイベントスキップ |
| direct_dispatch.async_enrichment | 非同期LLM後処理 | ON | enrichmentスキップ（事実イベントは残る） |
| direct_dispatch.consolidation | 記憶統合（L1） | ON | consolidationトリガースキップ |

### 最小監査ログ（常時記録・OFFにできない）

`event_record=OFF`でも以下は必ず記録:
- dispatch_id
- worker_id / worker_session_id
- 送信者（human）
- タイムスタンプ
- ステータス（dispatched/completed/failed）

セキュリティ・デバッグ・事故調査のため、dispatch factは完全消去不可。

### 設定永続化（実装済み）

- JSONファイル: `{ORIBIS_HOME}/config/direct_dispatch.json`
- Atomic Write: tempfile → rename パターン
- serde defaults: 未設定フィールドはデフォルト値(全ON)適用
- Tauriコマンド: `get_direct_dispatch_config` / `update_direct_dispatch_config`

```rust
pub struct DirectDispatchConfig {
    pub enabled: bool,              // default: true
    pub event_record: bool,         // default: true
    pub memory_save: bool,          // default: true
    pub anima_awareness: bool,      // default: true
    pub async_enrichment: bool,     // default: true
    pub consolidation: bool,        // default: true
    pub max_task_length: usize,     // default: 4096
}
```

---

## WorkerManager拡張（実装済み）

### 追加メソッド

```rust
impl WorkerManager {
    /// dispatch前検証: worker存在 + Idle状態確認
    pub fn validate_dispatch_target(&self, worker_id: &str) -> Result<(), DispatchError>;

    /// dispatch実行: validate → status=Running + active_dispatch_id記録
    pub fn dispatch(&self, worker_id: &str, intent: DispatchIntent) -> Result<(), DispatchError>;

    /// dispatchキャンセル: active_dispatch_idクリア + status=Idle
    pub fn cancel_dispatch(&self, worker_id: &str, dispatch_id: &str) -> Result<(), DispatchError>;

    /// Workerステータスを手動でIdleに戻す
    pub fn mark_worker_idle(&self, worker_id: &str) -> Result<(), DispatchError>;
}
```

### DispatchError

```rust
pub enum DispatchError {
    WorkerNotFound(String),
    WorkerNotIdle { worker_id: String, current_status: String },
    NoActiveDispatch(String),
    DispatchIdMismatch { expected: String, actual: String },
    TaskTooLong { length: usize, max: usize },
}
```

### WorkerInfo拡張

```rust
// 追加フィールド
pub active_dispatch_id: Option<String>  // #[serde(default, skip_serializing_if = "Option::is_none")]
```

### dispatch検証

- worker_id存在確認（WorkerNotFoundエラー）
- Worker status == Idle（WorkerNotIdleエラー）
- メッセージサイズ上限: `intent.task.len() <= 4096`（TaskTooLongエラー）
- cancel時: dispatch_id一致確認（DispatchIdMismatchエラー）

### 未実装（将来）

- `attach_stream()`: PTY出力ストリーム接続（pty_spawn_with_streamingで代替中）
- project_id整合性チェック（Phase 2）
- worker_session_id検証（Phase 2）

---

## セキュリティ考慮

### 権限境界

直接dispatchは「会話」ではなく「操作命令」。通常チャットより権限境界を厳しく扱う。

- 誤dispatchによるファイル変更・コマンド実行リスク
- Worker PTYへのプロンプトインジェクション対策: メッセージサニタイズ（制御文字除去）
- Worker出力内の秘密情報: チャット表示・記憶・LLM後処理に保存されるリスク → enrichment前マスキング層
- project_id偽装防止: dispatch時にproject所属検証
- MCP token/WorkerSessionの紐付け検証

### 監査ログ

全dispatchに対して記録:
- 誰が（human）
- どのWorkerへ（worker_id / session_id）
- 何を（message digest、全文はオプション）
- いつ（timestamp）
- 結果（status）
- dispatch_id（一意追跡ID）

---

## 現行アーキテクチャとの関係

### anima_chat（既存・変更なし）

```
anima_chat(message, project_id)
  → PipelineConfig → InputEvent → CliAdapter → execute_pipeline()
  → LLM推論 → 記憶保存（persist_oribis_meta_event）→ UI表示
```

anima_chatはLLM会話用として維持。Worker直接指示の責務を混入させない。

### anima_direct_dispatch（新規）

anima_chatとは**別フロー**。共通で使う低レベル関数:
- `events::append_event()` — イベント記録
- `memory_save_with_category()` — カテゴリ付き記憶保存
- `entity_link::link_entities()` — エンティティリンク
- `consolidation::run_level1_consolidation()` — L1統合

### persist_oribis_meta_event()の分解方針

現状: LLM応答のOribisMeta構造体に密結合。段階的に分解:

Phase 1（本実装）: `append_event`ベースの直接記録APIを作成。persist_oribis_meta_eventは触らない
Phase 2（将来）: persist_oribis_meta_eventからLLM非依存部分を抽出し共通化

---

## 実装済みファイル一覧

### Rust（src-tauri/src/）

| ファイル | 変更内容 | ステータス |
|---------|---------|----------|
| lib.rs | `anima_direct_dispatch` / `cancel_direct_dispatch` / `get/update_direct_dispatch_config` Tauriコマンド、`sanitize_task_input`関数、`enrich_dispatch_event`スタブ | ✅ 実装済み |
| worker_manager.rs | `DispatchIntent` / `DispatchError` 構造体、`validate_dispatch_target` / `dispatch` / `cancel_dispatch` / `mark_worker_idle` メソッド | ✅ 実装済み |
| pty_commands.rs | `pty_spawn_with_streaming` — AppHandle経由でpty-output-{pid}イベントバッチemit | ✅ 実装済み |
| anima/events.rs | 変更なし（既存Domain::WorkerOps / EventType::WorkerOutcomeを活用） | — |
| anima/pipeline.rs | 変更なし（anima_chatパイプライン維持） | — |
| mcp/tools/worker.rs | 変更なし（将来、dispatch_task_to_worker MCPツール追加予定） | 🔜 Phase 2 |

### TypeScript（src/）

| ファイル | 変更内容 | ステータス |
|---------|---------|----------|
| App.tsx | @メンション分類器統合 + sendMessage分岐 + @補完ドロップダウンUI + WorkerOutputInlineレンダリング | ✅ 実装済み |
| utils/mentionParser.ts | `parseMention(text, workers)` 正規表現ベース分類器 | ✅ 新規作成 |
| utils/mentionParser.test.ts | 18件テスト（正常系+エッジケース） | ✅ 新規作成 |
| components/WorkerOutputInline.tsx | チャット欄インラインWorker出力（pty-output listen、ANSI除去、500行制限） | ✅ 新規作成 |
| components/WorkerPanel.tsx | ConnectionIndicator + DispatchIcon + Cancel Dispatchボタン | ✅ 修正済み |
| types/orchestrator.ts | WorkerInfo型に`active_dispatch_id`追加 | ✅ 修正済み |
| App.css | worker-inline-output スタイル追加 | ✅ 修正済み |

### PTY出力ストリーミング実装詳細

```rust
// pty_commands.rs — pty_spawn_with_streaming
// reader_thread内でバッチemit
const MAX_BATCH_SIZE: usize = 4096;   // 4KB
const BATCH_INTERVAL_MS: u64 = 50;    // 50ms

// emit_buf蓄積 → サイズ or 時間窓でemit
let _ = app_handle.emit(&format!("pty-output-{}", pid), &emit_buf);
```

### @メンション分類器実装詳細

```typescript
// utils/mentionParser.ts
export function parseMention(text: string, workers: WorkerEntry[]): MentionResult {
  // 1. コードブロック/引用/メール/URLをマスク
  // 2. 文頭or空白後の @([\w#-]+) で抽出
  // 3. Worker alias完全一致(case insensitive) → type='worker'
  // 4. 不一致 → type='anima'
}
```

---

## Codex Adviser指摘事項サマリー

### v1（アーキテクチャ選定）
- 方式A `anima_direct_dispatch` 推奨 → **採用**
- 記憶保存はLLM推論から分離必須 → **二層構造で対応**
- PTY+専用UI+Tauri Eventハイブリッド推奨 → **採用**

### v2（実コード調査反映）
- ハイブリッド二層構造推奨 → **採用**
- domain分離（WorkerOps + Companion）推奨 → **採用**
- persist_oribis_meta_event段階的分解 → **Phase 1/2方式で採用**
- 設定はTauri config + DB推奨 → **採用**

### v3（最終設計レビュー）
- @メンション: 登録alias完全一致のみ → **採用・実装済み**
- PTY出力: 50msバッファリング + 500行制限 → **採用・実装済み**
- dispatch時worker_session_id検証 → **Phase 2へ延期**
- 長時間タスクcheckpointイベント → **Phase 2へ延期（スタブのみ）**
- event_record OFF時も最小監査ログ残す → **採用・実装済み**
- DispatchIntent正規化 → **採用・実装済み**
- enrichment前秘匿情報マスキング → **Phase 2へ延期**

---

## Phase 1 実装結果

### テスト結果
- cargo test: 1452 passed, 5 ignored
- pnpm typecheck: 0 errors
- vitest (mentionParser): 18/18 PASS

### ブランチ
- `sysdev-1/worker-direct-dispatch` — 8 commits

### Phase 2 残課題
1. `attach_stream()` — PTY出力ストリーム接続API
2. `project_id` 整合性チェック（別プロジェクトWorker誤dispatch防止）
3. `worker_session_id` 検証（再起動後の古いセッション誤送防止）
4. チェックポイントイベント本実装（30秒〜2分間隔）
5. LLM enrichment本実装（`enrich_dispatch_event`スタブ→実装）
6. enrichment前秘匿情報マスキング
7. `dispatch_task_to_worker` MCPツール（外部MCP client用）
8. `output_seq` 順序保証（Workerごと・sessionごと）
9. L1 consolidationトリガー連携

### 証跡
- `deliverables/test-worker-direct-dispatch-20260521.md` — AC12件照合済み
