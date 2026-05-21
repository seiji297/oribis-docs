# Worker直接指示機能 設計書

**作成日**: 2026-05-21
**ステータス**: 方針確定（Codex Adviser v3レビュー済み）
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
anima_direct_dispatch(message, worker_id, project_id, settings)
  → [同期] dispatch前検証
    → worker_id存在・起動中確認
    → worker_session_id取得
    → project_id整合性チェック
  → [同期] InputEvent記録（domain=WorkerOps, source="human_direct"）
  → [同期] Anima把握イベント（domain=Companion, kind="observed_human_direct_dispatch"）
  → [同期] WorkerManager.dispatch(worker_id, message)
    → PTY経由でWorkerにメッセージ送信
  → [ストリーミング] Worker PTY出力 → バッファリング → Tauri Event → チャット欄表示
  → [同期] OutputEvent記録（Worker応答、domain=WorkerOps）
  → [非同期・オフ可能] LLM後処理（要約・重要度判定・記憶enrichment）
  → [非同期・オフ可能] L1 consolidation
```

### 新規Tauriコマンド

```rust
#[tauri::command]
async fn anima_direct_dispatch(
    message: String,
    worker_id: String,
    project_id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<DirectDispatchResult, String>
```

### DirectDispatchResult

```rust
struct DirectDispatchResult {
    dispatch_id: String,       // 一意ID（監査・再送・enrichment紐付け用）
    worker_id: String,
    worker_session_id: String,
    pty_session_id: String,
    status: DispatchStatus,    // Dispatched / Failed
}
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

### 設定永続化

- デフォルト値: Tauri config（`tauri.conf.json`拡張 or アプリ設定ファイル）
- ユーザー/プロジェクト別実値: SQLite DB（memory_db or 設定専用テーブル）
- UI表示用キャッシュ: localStorage可（ただし実行時判定はRust側で最終確認）
- 環境変数: 開発・運用フラグとしてのみ使用

---

## WorkerManager拡張

### 追加メソッド

```rust
impl WorkerManager {
    /// Worker PTYにメッセージを送信
    pub fn dispatch(&self, worker_id: &str, message: &str) -> Result<DispatchHandle, WorkerError>;

    /// Worker PTY出力ストリームに接続
    pub fn attach_stream(&self, worker_id: &str) -> Result<PtyOutputStream, WorkerError>;

    /// Worker実行をキャンセル
    pub fn cancel(&self, worker_id: &str) -> Result<(), WorkerError>;

    /// dispatch前の検証（存在・起動中・session整合）
    pub fn validate_dispatch_target(&self, worker_id: &str, project_id: &str) -> Result<WorkerSessionInfo, WorkerError>;
}
```

### dispatch検証

- worker_id存在確認
- Worker status == Active
- worker_session_idの一致（再起動後の古いセッションへの誤送防止）
- project_id整合性（別プロジェクトWorkerへの誤dispatch防止）
- メッセージサイズ上限（4096文字、既存task sanitizeと同等）

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

## 実装対象ファイル

### Rust（src-tauri/src/）

| ファイル | 変更内容 |
|---------|---------|
| lib.rs | `anima_direct_dispatch` Tauriコマンド追加 |
| worker_manager.rs | `dispatch()` / `attach_stream()` / `cancel()` / `validate_dispatch_target()` 追加 |
| anima/events.rs | `worker_direct_instruction`イベント種別追加 |
| anima/pipeline.rs | 変更なし（anima_chatパイプライン維持） |
| mcp/tools/worker.rs | `dispatch_task_to_worker` MCPツール追加（将来、外部MCP client用） |

### TypeScript（src/）

| ファイル | 変更内容 |
|---------|---------|
| App.tsx | @メンション分類器 + anima_direct_dispatch invoke |
| components/ChatInput.tsx or 相当 | @メンション補完候補UI |
| components/XtermTerminal.tsx | Worker選択ドロップダウン・接続状態表示追加 |
| components/WorkerOutputInline.tsx | チャット欄インラインWorker出力コンポーネント（新規） |

### 設定

| ファイル | 変更内容 |
|---------|---------|
| src-tauri/tauri.conf.json | direct_dispatch設定デフォルト値 |

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
- @メンション: 登録alias完全一致のみ → **採用**
- PTY出力: 50-100msバッファリング + 200-500行制限 → **採用**
- dispatch時worker_session_id検証 → **採用**
- 長時間タスクcheckpointイベント → **採用**
- event_record OFF時も最小監査ログ残す → **採用**
- DispatchIntent正規化 → **採用**
- enrichment前秘匿情報マスキング → **採用**
