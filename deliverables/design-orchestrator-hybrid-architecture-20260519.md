# Oribis Orchestrator 改善設計書 — F案ハイブリッドアーキテクチャ v2

**作成日**: 2026-05-19
**改訂日**: 2026-05-19
**ステータス**: REVISED v4（Codex v3レビュー反映: headless 2層分離）
**Codexレビュー結果**: FAIL → CONCERN → CONCERN(v3: headless FAIL→2層分離修正、前回4件PASS)

---

## 1. 背景

現在のOribis Orchestratorは「設計ツール」止まり。Node Editor（React Flow）+ Department CRUD + JSON永続化は完成しているが、実行系がない。

**核心問題**: tmux直送 > GUI の壁を超えられていない。

## 2. 現状のシステム構成（ソースコード確認済み）

### 既存基盤一覧

- **Node Editor** ✅完成 — NodeEditorPanel.tsx, NodeCanvas.tsx, graphMapper.ts
  - 保存・読込・編集のみ。実行状態モデル・実行APIなし
- **PTY System** ✅完成 — pty_commands.rs (7cmd), WorkerPanel.tsx, XtermTerminal.tsx
  - UI表示専用ターミナル。`-c` 拒否（セキュリティ設計）
  - 10ms polling、1セッション1 reader thread
- **MCP Broker** ✅完成 — mcp/server.rs, mcp/broker.rs (Unix socket JSON-RPC)
  - DENIED_TOOLS: `pty_spawn`, `pty_write`（意図的ブロック）
- **MCP Anima Tools** ✅完成 — mcp/tools/anima.rs (4 tools, 497行)
- **MCP Resources** ✅完成 — mcp/resources.rs (7 URI, 787行)
- **Anima Pipeline** ✅完成 — anima/pipeline.rs (65KB)
  - speech queue上限5件、低・中優先度は破棄
  - カテゴリ13種（workflow系なし）
  - `error → working` 遷移禁止（state_machine.rs:15）
- **Event Feed** ✅完成 — event_feed.rs (**JSONL形式、SQLiteではない**)
  - ファイル: `{dept}-{worker_id}.jsonl`
  - append毎に `sync_all()`（fsync）
  - `single-process append only`（concurrent write未対応）
  - 全件メモリ読み込み → ソート → フィルタ（インデックスなし）
- **Anima Memory DB** ✅完成 — anima/memory_db.rs (**SQLite/rusqlite**)
  - `memory.db`: WALモード、memory_events/memories テーブル
  - MCP audit logも同DB
- **Department Config** ✅完成 — DepartmentDetail.tsx (5タブ, quality_gate, review_mode)
- **WorkerManager** ✅完成 — worker登録・状態管理・list/kill。**max_workers enforcement は未実装**（DepartmentConfig.max_workersフィールドは存在するがspawn_worker内で上限チェックしていない）
- **suppress_narration** ✅完成 — narration抑制機構

### 現状の接続状態

Anima-Orchestrator連携は **AnimaStatusBar（40行）のみ**。接続/切断表示だけ。
ワークフロー実行・ノード編集・MCP・Event Feed のいずれにも未接続。

PTYシステムはApp.tsx内でWorkerPanelとして独立稼働。Node Editorとは完全に分離。

`GraphNode.data` はTS側 discriminated union、Rust側 `serde_json::Value` パススルー。

## 3. 検討した6案

### A案: PTY直結

```
Node Editorノードクリック → pty_spawn → xterm表示 → stdout → ノード状態更新
```

- 利点: 新規技術ゼロ、portable-ptyクロスプラットフォーム、実装量最小
- 弱点: ターミナルラッパー止まり。ノード間データ受渡しがstdout parsing依存→脆弱
- **Codex指摘**: pty_spawnは`-c`拒否、DENIED_TOOLSに含まれる → セキュリティ設計と衝突

### B案: MCP Broker経由外部AIエージェント連携

```
Node Editorノード → MCP JSON-RPC → 外部Claude Code実行 → event_feed結果収集
```

- 利点: AIが「意図」を解釈して実行。broker/tools/resources全部既存
- 弱点: pty_spawn/pty_writeはDENIED_TOOLS。Unix socket→Windows対応要検討

### C案: event_feed + Anima認知レイヤー

```
実行（A/B問わず）→ event_feed記録 → Anima state遷移 → 発話・表情で報告
```

- 利点: tmux不可能な「認知」価値。event_feed部門別フィルタ済み
- 弱点: 認知層のみ、実行層ではない。A/Bとの組合せ必須
- **Codex指摘**: speech queue 5件上限 → 大量イベントでキュー溢れ。低頻度通知に限定すべき

### D案: Department Config駆動

```
DepartmentDetailの5タブ設定が実際のワークフロー制御に直結
```

- 利点: quality_gate→実DAゲート、review_mode→実レビューフロー
- 弱点: 大規模実装。Department抽象がワークフロー実行に適合するか未検証

### E案: Node Editor → AC DSL生成

```
ノード配置 → epic-*.md / ワークフローJSON自動生成 → 既存start-epic/run-epic実行
```

- 利点: 既存ECCチェーン直接統合。CLI-first互換
- 弱点: 設計止まり。リアルタイム監視は別途

### F案: ハイブリッド（推奨・改訂版）

Phase 1のスコープをCodexレビューに基づき大幅縮小:

1. Node Editor → ワークフロー視覚設計
2. **実行 → CommandExecutor（PTYとは分離。allowlist済みタスク定義）**
3. 監視 → event_feed → ノード状態リアルタイム更新
4. 認知 → Anima **失敗・停止・完了のみ低頻度通知**
5. 記憶 → MCP memory_save → 次回ワークフロー時活用

## 4. 評価マトリクス

- **実装コスト**: A◎最小 / B△ / C○ / D×大 / E○ / F△
- **tmux超越**: A×弱い / B○ / C◎ / D○ / E△ / F◎
- **既存基盤活用**: A◎ / B◎ / C◎ / D○ / E◎ / F◎
- **CLI-first互換**: A○ / B△ / C○ / D× / E◎ / F◎
- **クロスプラットフォーム**: A◎ / B△ / C◎ / D◎ / E◎ / F◎
- **段階導入可能性**: A◎ / B△ / C◎ / D× / E◎ / F◎

## 5. 推奨: F案 段階導入（改訂版）

### tmuxに勝てる3要素

1. **状態一覧**: 全ノードの実行状態・失敗要約・次アクション提示を一画面で確認
2. **設計→実行統合**: Node Editorで設計したフローがそのままECC実行可能
3. **記憶**: 過去ワークフロー結果蓄積 → 次回事前警告

### Phase 0（前提: 実行意味論の定義）

**Phase 1の前に必須**: ノードの実行意味論を定義する。

#### 型定義（Rust側）

```rust
/// 事前定義済みコマンドテンプレート（allowlist方式）
pub struct CommandTemplate {
    pub id: String,              // "ac-run", "cargo-test", etc.
    pub executable: String,      // "/usr/bin/bash"
    pub fixed_args: Vec<String>, // ["run-agent-chain.sh"]
    pub bind_params: Vec<String>, // ["task_file", "output_dir"]
}

/// ノード実行仕様
pub struct NodeExecutionSpec {
    pub node_id: String,
    pub template_id: String,      // CommandTemplate.id参照
    pub params: HashMap<String, String>, // bind_paramsに対応する値
    pub timeout_sec: Option<u64>,
    pub department: String,
}

/// 実行結果
pub struct ExecutionResult {
    pub node_id: String,
    pub status: ExecutionStatus,   // Pending | Running | Success | Failed | Cancelled
    pub exit_code: Option<i32>,
    pub duration_ms: u64,
    pub log_path: PathBuf,
    pub error_summary: Option<String>,
}

pub enum ExecutionStatus {
    Pending,
    Running,
    Success,
    Failed,
    Cancelled,
}
```

#### 型定義（TS側）

```typescript
interface ExecutionResult {
  nodeId: string;
  status: "pending" | "running" | "success" | "failed" | "cancelled";
  exitCode?: number;
  durationMs: number;
  logPath: string;
  errorSummary?: string;
}
```

#### CommandExecutor trait（Rust側）

```rust
#[async_trait]
pub trait CommandExecutor: Send + Sync {
    async fn execute(&self, spec: NodeExecutionSpec) -> Result<ExecutionResult>;
    async fn cancel(&self, node_id: &str) -> Result<()>;
}

/// 本番実装: std::process::Command経由（PTYとは独立）
pub struct ProcessExecutor { ... }

/// テスト用: fake executor
pub struct FakeExecutor { ... }
```

**重要**: PTYは引き続きUI表示用ターミナルとして維持。CommandExecutorは`std::process::Command`等でプロセスを起動する別レイヤー。PTYで実行制御は行わない。

#### グラフ実行意味論（Phase 0で定義必須）

```
実行順序:
- DAGのtopological orderで実行
- 同一深度のノードは並列実行可能（max_workers制限内）
- 依存エッジ = 先行ノード完了が後続ノード開始の前提条件

失敗時の後続ノード扱い:
- 先行ノードFailed → 後続ノードはSkipped（自動スキップ）
- Skippedノードは再実行対象外（先行の再実行が先）

キャンセル伝播:
- ノードキャンセル → そのノードのみCancelled
- 後続ノードはPendingのまま（Skippedにしない）
- グラフ全体キャンセル → Running全ノードにcancel送信 → 残りPending全ノードをCancelled

再実行:
- 再実行単位 = 個別ノード or 失敗ノード以降の部分グラフ
- 成功済みノードの再実行も可能（明示的な手動操作のみ）
- 再実行時は ExecutionResult をリセットしてPendingに戻す
```

### Phase 1（最小MVP・スコープ縮小版）

**定義済みタスク実行 + ExecutionResult + event_feed記録 + UI状態表示**

Codex指摘に基づき、旧Phase 1から以下を除外:
- ~~PTY spawn連携~~ → CommandExecutor経由に変更
- ~~Anima state遷移~~ → Phase 1では失敗通知のみ（低頻度）
- ~~ワークフロー専用カテゴリ追加~~ → UIでの状態表示を先に検証

#### Phase 1 実装タスク

1. **CommandTemplate定義 + CommandExecutor trait**（Rust）
   - allowlist方式。任意コマンド文字列実行を禁止
   - FakeExecutor実装（テスト用）
   - ProcessExecutor実装（`std::process::Command`、stdout/stderrをログファイルに保存）
   - MCP DENIED_TOOLSと同等の監査ログ出力

2. **ExecutionResult型 + ExecutionStore**（Rust + TS）
   - GraphNode型にExecutionResult追加
   - `executionReducer` 純粋関数（UIとTauriから独立してテスト可能）
   - Tauri command: `execute_workflow_node(spec)`, `cancel_workflow_node(node_id)`

3. **event_feed記録**（Rust）
   - 実行開始・完了・失敗をevent_feedに記録
   - 現行JSONL形式を維持（SQLite移行はPhase 2）
   - **バッチappend対応**: `append_batch_to_jsonl(items: &[EventFeedItem])` 新設
     - 複数イベントを1回のwrite + 1回の`sync_all()`で書き込み
     - flush単位: ノード実行完了時（開始+完了を1バッチ）
     - クラッシュ時損失: 最大1バッチ分（完了イベント未flush時のみ）
     - 単発appendは既存`append_to_jsonl()`をそのまま維持（互換性）

4. **UI状態表示**（TS/React）
   - ノード状態表示: 成功=緑、失敗=赤、実行中=青アニメーション
   - useNodeExecution hook切出し（NodeEditorPanel肥大化防止）
   - 失敗ノードのエラーサマリー・ログリンク表示

5. **Anima最小連携**（失敗通知のみ）
   - **デフォルトsilent**。失敗・長時間停止・承認待ちのみ発話
   - priority=low。既存会話（chat-tool-start等）を邪魔しない
   - `suppress_narration` をworkflow実行中の標準制御に組み込む

6. **同時実行制御**
   - 既存 `WorkerManager` のworker登録・状態管理を活用
   - **max_workers enforcement を新規実装**: `spawn_worker()` 内でDepartmentConfig.max_workersを参照し上限チェック追加
   - Phase 1受入基準に「同時Nノード実行時のCPU/メモリ/遅延」含む

#### Phase 1 テスト戦略

- **Rust unit test**: CommandExecutor trait + FakeExecutor でmock差替え
  - 成功・失敗・キャンセル・タイムアウト・同時実行上限・キュー溢れ
- **TS unit test**: executionReducer 純粋関数テスト
- **統合テスト**: Tauri invoke mock + ExecutionStore + UI状態更新
- 既存42テストへの影響確認（GraphNode型変更の波及チェック）

#### Phase 1 成功基準（数値化）

旧「毎日開くか」を以下に置換:

- **失敗検知時間**: tmux巡回比で60秒以内に失敗把握
- **手動巡回回数**: 1日あたりtmux巡回回数30%減
- **文脈復帰時間**: 離席後の文脈把握に必要な手動ログ確認2回以下
- **同時実行安定性**: 3ノード同時実行でCPU使用率+20%以内、UIフリーズなし

#### Phase 1 撤退条件

- 1週間検証で上記基準未達 → 実行層だけ残してAnima接続切る
- CommandExecutor + ExecutionResult はCLI-firstツールとしても単独利用可能

### Phase 2

**AC DSL生成 + CLI-first互換 + event_feed SQLite移行**

- Node Editor → ワークフローJSON export
- JSON → start-epic/run-epic互換フォーマット変換
- CLIでも同じJSONを読める
- event_feed JSONL → SQLite移行（WALモード、インデックス追加）
  - 移行理由: ワークフロー実行イベント大量増加、履歴検索・集計・ダッシュボード用途
  - EventFeedItem型はそのまま、ストレージ層のみ差し替え
  - rusqlite依存は既にCargo.tomlに存在（memory_db.rsで使用中）

### Phase 3

**Department Config駆動 + 自動化**

- Department config の quality_gate → 実際のDAゲート制御
- skills/prompts → Anima実行コンテキスト注入
- schedule → 自動実行トリガー

## 6. アーキテクチャ図（改訂版）

```
┌─────────────────────────────────────────────┐
│                 Node Editor                  │
│              (React Flow v12)                │
│                                              │
│  [userMessage]→[contextBuilder]→[llmQuery]   │
│                     │                        │
│         実行ボタン (allowlist template選択)    │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│         CommandExecutor (Rust trait)          │
│    ProcessExecutor / FakeExecutor(test)       │
│                                              │
│  NodeExecutionSpec → std::process::Command    │
│  allowlist: CommandTemplate { id, exe, args } │
│  監査ログ出力 (MCP DENIED_TOOLS同等)          │
│  exit code + log file → ExecutionResult       │
└──────────────────────┬───────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        ▼                             ▼
┌──────────────────┐    ┌─────────────────────────┐
│   Event Feed     │    │    ExecutionStore        │
│   (JSONL)        │    │    executionReducer      │
│   {dept}-{wk}    │    │    TS純粋関数            │
│   .jsonl         │    └─────────┬───────────────┘
│   → Phase 2で    │              │
│     SQLite移行   │              ▼
└────────┬─────────┘    ┌─────────────────────────┐
         │              │   Node Editor UI         │
         │              │   状態表示 緑/赤/青       │
         │              │   エラーサマリー          │
         │              │   ログリンク              │
         ▼              └─────────────────────────┘
┌──────────────────────────────────┐
│    Anima Pipeline                │
│    失敗・停止・完了のみ (low pri) │
│    suppress_narration 標準適用   │
│    speech queue圧迫しない        │
└──────────────────────────────────┘

（PTY SystemはUI表示用ターミナルとして独立維持。
  実行制御には関与しない。WorkerPanelで引き続き使用）

Phase 2 追加:
┌─────────────────┐
│  Node Editor    │──→ ワークフローJSON export
│                 │       │
└─────────────────┘       ▼
                    ┌─────────────────┐
                    │  Agent Chain     │
                    │  start-epic      │
                    │  run-epic        │
                    └─────────────────┘
```

## 7. セキュリティ設計

### 7-1. 実行権限境界

- **任意コマンド文字列実行を禁止**。CommandTemplate allowlist方式のみ
- GUI内部実行もMCP DENIED_TOOLS同等の監査ログ・権限境界を持つ
- PTY（UI表示用）とCommandExecutor（実行制御）を完全分離
- MCPのDENIED_TOOLSを迂回しない

### 7-2. コマンドインジェクション対策

- `CommandTemplate.fixed_args` + `bind_params` でパラメータバインド
- bind_params値のバリデーション（パス文字列のみ許可、シェルメタ文字拒否）
- `std::process::Command` 使用（シェル経由しない直接exec）

### 7-3. 監査ログ

- **既存 `mcp_audit_log` テーブルは流用しない**（スキーマ不足: exit_code/開始終了時刻/duration なし）
- **新規テーブル `workflow_audit_log` を作成**:

```sql
CREATE TABLE IF NOT EXISTS workflow_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id TEXT NOT NULL,
    template_id TEXT NOT NULL,
    params_json TEXT,
    department TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    exit_code INTEGER,
    duration_ms INTEGER,
    status TEXT NOT NULL,       -- pending/running/success/failed/cancelled
    error_summary TEXT,
    log_path TEXT
);
CREATE INDEX IF NOT EXISTS idx_wf_audit_dept ON workflow_audit_log(department);
CREATE INDEX IF NOT EXISTS idx_wf_audit_status ON workflow_audit_log(status);
CREATE INDEX IF NOT EXISTS idx_wf_audit_started ON workflow_audit_log(started_at DESC);
```

- 既存 `memory.db` 内に同居（rusqlite共有、init_memory_db拡張）
- MCP audit_logは既存MCP用途のまま維持（変更なし）

## 8. Codexレビュー指摘対応表

### 1. アーキテクチャ整合性: FAIL → 対応済み
- ~~event_feed「SQLite」誤記~~ → JSONL明記（Phase 2でSQLite移行タスク化）
- ~~実行意味論未定義~~ → Phase 0でNodeExecutionSpec/ExecutionResult/CommandTemplate定義
- ~~Node Editorに直接実行を足す~~ → CommandExecutor trait でRust側に実行境界設置

### 2. セキュリティ: FAIL → 対応済み
- ~~PTY spawnでコマンド実行~~ → CommandExecutor（std::process::Command）に分離
- ~~任意コマンド文字列~~ → allowlist CommandTemplate + パラメータバインド
- ~~MCP DENIED_TOOLS迂回~~ → GUI実行も同等の監査ログ・権限境界
- audit log: 既存mcp_audit_log流用せず、新規`workflow_audit_log`テーブル（exit_code/duration/時刻あり）

### 3. パフォーマンス: CONCERN → 対応済み
- event_feed バッチappend対応: `append_batch_to_jsonl()` 新設、flush単位=ノード完了時、クラッシュ損失=最大1バッチ
- Phase 1受入基準に同時Nノード実行時のCPU/メモリ/遅延を追加
- PTY polling改善はPhase 1スコープ外（既存PTYは変更しない）

### 4. UX: CONCERN → 対応済み
- ~~「毎日開くか」~~ → 数値化成功基準に置換（失敗検知60秒、巡回30%減、ログ確認2回以下）
- workflow発話デフォルトsilent、失敗・停止・承認待ちのみ
- UI状態表示（ノード色・エラーサマリー・ログリンク）を主軸に

### 5. 代替案・見落とし: FAIL → 対応済み
- ~~Phase 1からDSL外し~~ → Phase 0で実行意味論を先に定義（グラフ実行意味論: topo order、失敗伝播、キャンセル、再実行）
- WorkerManager: worker登録・状態管理を活用。**max_workers enforcement は未実装 → Phase 1で新規実装**
- suppress_narration 標準組込み

### 6. 実装リスク: FAIL → 対応済み
- executionReducer + ExecutionStore を純粋関数で先にテスト
- CommandExecutor trait + FakeExecutor でmock差替え
- テストケース追加: 成功・失敗・キャンセル・同時実行上限・キュー溢れ

### 7. tmux超越の検証: FAIL → 対応済み
- 成功基準数値化（失敗検知60秒、巡回30%減、文脈復帰ログ2回以下）
- tmuxとの差は状態一覧・失敗要約・次アクション提示で測定
- Animaカテゴリ追加はUI検証後に判断

## 9. Oribis Test Platform — 汎用E2Eテスト自動化基盤

### 9-1. 課題

現状のOribisテストは2系統:
- **Rust unit/integration test**: `cargo test`（MCP broker、event_feed、graph等）
- **TS unit test**: `pnpm test`（React コンポーネント、reducer等）

**不足**: GUIを起動しないとテストできない領域が完全に手動。対象は広範:
- オーケストレーター実行フロー（ノード実行→状態更新→event_feed記録）
- Anima連携（発話キュー・表情・state遷移・suppress_narration）
- アニメーション（VRMポーズ遷移・表情ブレンド・リップシンク）
- プラグイン（ロード・アンロード・イベント配信）
- Department管理（CRUD→Worker生成→MCP token発行）

**目標**: Claude（AIエージェント）がOribisをheadless起動し、MCP経由で**あらゆる機能**を自動テストできる汎用プラットフォームを構築する。オーケストレーターはその最初の適用対象。

### 9-2. アーキテクチャ概要

```
┌──────────────────────────────────────────────────────────┐
│  テストドライバー（Claude Code / CI / 手動）              │
│                                                          │
│  1. Oribisをheadlessモードで起動                         │
│  2. oribis-test-client経由でMCP Brokerに接続             │
│  3. テストシナリオ実行（tool_call / resource_read）       │
│  4. アサーション検証                                      │
│  5. テスト結果収集・レポート                              │
└──────────────┬───────────────────────────────────────────┘
               │ Unix socket (newline-delimited JSON)
               ▼
┌──────────────────────────────────────────────────────────┐
│  Oribis App (headless / test mode)                       │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │               MCP Broker (Unix socket)               │ │
│  │  既存tools (memory, anima, avatar)                   │ │
│  │  + Core Test Tools (reset, snapshot, health)         │ │
│  │  + Domain Test Tools (per feature module)            │ │
│  └──────────────────────┬──────────────────────────────┘ │
│                          │                                │
│  ┌───────────┐ ┌────────┴──────┐ ┌──────────────────┐   │
│  │ Orchestr. │ │ Anima/Avatar  │ │ Department/      │   │
│  │ Engine    │ │ Pipeline      │ │ WorkerManager    │   │
│  └───────────┘ └───────────────┘ └──────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────────┐│
│  │  Test Fixture Store (domain別: orchestrator/         ││
│  │    anima/animation/department/plugin)                 ││
│  └──────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────┘
```

### 9-3. コンポーネント設計（7層）

#### C1: テスト起動モード（2層構成）

**Tier 1: Backend E2E（Rustサービス単体、GPU不要）**

```rust
/// 環境変数 ORIBIS_TEST_MODE=1 でbackend-only起動
/// - Tauriウィンドウ・WebView・R3F一切なし
/// - MCP Broker + 全Rustサービス（Orchestrator/Anima/Department等）は通常通り起動
/// - テスト用自動トークン発行（stdout に JSON出力）
/// - ORIBIS_TEST_DOMAINS="orchestrator,anima" で有効化ドメイン指定可
/// - 実装方式: test harness bin or integration test から直接サービス初期化
///
/// 起動コマンド例:
///   ORIBIS_TEST_MODE=1 cargo run --bin oribis-test-server 2>/dev/null
///   → stdout: {"socket_path":"/tmp/oribis-broker-XXXX.sock","token":"uuid","pid":12345}
```

対象: Orchestrator実行、Anima通知、Department管理、event_feed、audit_log等の**非レンダリング系全て**。
Phase 1 MVPはこの層のみで完結する。CI/CDでも利用可能。

**Tier 2: UI/Avatar E2E（WebView + GPU/Xvfb必要）**

```
対象: Animation/VRM/R3F/Canvas依存のテスト
方式: Tauri window起動 + Playwright/Xvfb（Linux CI）or 実GPU
MCPは補助制御（ポーズ指示、状態取得）に使い、描画検証はPlaywright screenshot比較
Phase 2以降で実装。V01-V04シナリオはこの層で実行
```

**全ドメイン共通**のクライアント（C2）・Core Tools（C3）は両Tier共用。

#### C2: oribis-test-client（共通基盤・Python）

```python
#!/usr/bin/env python3
"""oribis-test-client.py — MCP Broker汎用テストクライアント
外部依存なし（Python標準ライブラリのみ）"""
import socket, json, sys, time

class OribisTestClient:
    """全ドメイン共通のMCP Broker通信クライアント"""

    def __init__(self, socket_path: str, token: str):
        self.socket_path = socket_path
        self.token = token
        self.sock = None

    def connect(self) -> dict:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.socket_path)
        return self._send({"type": "authenticate", "token": self.token})

    def tool(self, name: str, params: dict = {}) -> dict:
        return self._send({
            "type": "tool_call", "token": self.token,
            "tool_name": name, "params": params,
            "correlation_id": f"test-{time.time_ns()}"
        })

    def resource(self, uri: str) -> dict:
        return self._send({
            "type": "resource_read", "token": self.token,
            "uri": uri, "correlation_id": f"res-{time.time_ns()}"
        })

    def list_tools(self) -> list:
        resp = self._send({"type": "list_tools", "token": self.token})
        return resp.get("tools", [])

    def wait_for(self, tool_name: str, params: dict,
                 path: str, expected, timeout: float = 30.0) -> dict:
        """汎用状態待機。任意tool_callの結果JSONパスを監視"""
        deadline = time.time() + timeout
        while time.time() < deadline:
            result = self.tool(tool_name, params)
            val = self._extract(result, path)
            if val == expected:
                return result
            time.sleep(0.5)
        raise TimeoutError(f"{tool_name}({params}) {path}!={expected} after {timeout}s")

    def assert_eq(self, tool_name: str, params: dict, path: str, expected):
        """ワンショットアサーション"""
        result = self.tool(tool_name, params)
        val = self._extract(result, path)
        assert val == expected, f"FAIL: {path}={val}, expected={expected}"
        return result

    def _extract(self, data: dict, path: str):
        """ドット区切りパスでJSON値を取得: 'result.status' → data['result']['status']"""
        for key in path.split("."):
            if isinstance(data, dict):
                data = data.get(key)
            elif isinstance(data, list) and key.isdigit():
                data = data[int(key)]
            else:
                return None
        return data

    def _send(self, request: dict) -> dict:
        data = json.dumps(request) + "\n"
        self.sock.sendall(data.encode())
        buf = b""
        while b"\n" not in buf:
            buf += self.sock.recv(4096)
        return json.loads(buf.decode().strip())

    def close(self):
        if self.sock: self.sock.close()

# CLI使用例:
#   python3 oribis-test-client.py /tmp/oribis-broker-XXX.sock <token> \
#     tool get_anima_state '{}'
#   python3 oribis-test-client.py ... \
#     wait get_execution_status '{"node_id":"n1"}' result.status success 30
```

**全ドメイン共通**。`wait_for()` と `assert_eq()` は汎用メソッド。ドメイン固有ロジックを含まない。

#### C3: Core Test Tools（共通基盤・MCP拡張）

全ドメイン横断で使うテスト制御ツール:

```
core_test_reset
  params: { domains?: ["orchestrator","anima",...] }  // 省略時は全ドメイン
  → 指定ドメインの状態をクリア（event_feed, audit_log, execution_store等）
  → テストモード時のみ有効

core_test_snapshot
  params: {}
  → 全サービスの現在状態をJSONスナップショットで返却
  → デバッグ・アサーション・テスト比較用

core_test_health
  params: {}
  → Broker接続数、各サービス稼働状態、メモリ使用量を返却
  → テスト開始前のヘルスチェック用

core_test_inject_event
  params: { event_type, payload }
  → 任意イベントをシステムに注入（Tauri emit相当）
  → フロントエンド不在でもバックエンドのイベント駆動テスト可能
  → テストモード時のみ有効
```

**テストモード限定ツールは本番でDENIED_TOOLS入り**。

#### C4: Domain Test Tools（ドメイン別MCP拡張）

各機能モジュールが自分のテストツールを登録する拡張パターン:

```
━━ Orchestrator Domain ━━━━━━━━━━━━━━━━━━━━━━
execute_workflow_node    { template_id, params, department, node_id? }
cancel_workflow_node     { node_id }
get_execution_status     { node_id? }          // 本番UIからも利用
load_test_graph          { graph_json }         // テストモード限定
get_event_feed           { department?, limit?, since? }
get_audit_log            { node_id?, limit? }

━━ Anima Domain ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
get_anima_state          {}                     // 既存（そのまま活用）
set_anima_state          { mode, ... }          // 既存
get_speech_queue         {}                     // 新規: キュー内容確認
get_narration_state      {}                     // 新規: suppress状態確認
trigger_anima_event      { category, payload }  // テストモード限定
get_affinity             {}                     // 既存resource → tool化

━━ Animation/Avatar Domain ━━━━━━━━━━━━━━━━━━━
get_avatar_state         {}                     // 現在ポーズ・表情・リップシンク状態
set_avatar_pose          { pose_name, blend? }  // テスト用強制ポーズ設定
get_expression_state     {}                     // 現在の表情モーフ値
trigger_animation        { clip_name, params }  // テスト用アニメーション発火
wait_animation_complete  { clip_name, timeout }

━━ Department Domain ━━━━━━━━━━━━━━━━━━━━━━━━
list_departments         {}                     // 本番UIからも利用
get_department_config    { dept_id }
load_test_department     { config_json }        // テストモード限定
get_worker_status        { dept_id?, worker_id? }

━━ Plugin Domain（将来）━━━━━━━━━━━━━━━━━━━━━━
list_plugins             {}
load_test_plugin         { manifest_json }      // テストモード限定
get_plugin_state         { plugin_id }
emit_plugin_event        { plugin_id, event }   // テストモード限定
```

**拡張パターン**: 新ドメイン追加時は `handle_tool_call` に分岐を追加 + テストツール関数を実装するだけ。クライアント側変更不要。

#### C5: Test Fixture Store（ドメイン別）

```
src-tauri/tests/fixtures/
  orchestrator/
    graphs/
      single-node-success.json
      single-node-failure.json
      linear-3-nodes.json
      parallel-2-nodes.json
      diamond-dependency.json
    templates/
      echo-success.json
      echo-failure.json
      slow-30sec.json
  anima/
    states/
      idle-default.json          — 初期状態
      error-recovery.json        — error→working遷移テスト
      high-affinity.json         — 高好感度状態
    events/
      workflow-fail.json         — ワークフロー失敗イベント
      chat-burst.json            — 高頻度チャットイベント
  animation/
    poses/
      default-idle.json
      greeting.json
      thinking.json
    sequences/
      greet-then-idle.json       — ポーズ遷移シーケンス
      expression-blend.json      — 表情ブレンドパターン
  departments/
    test-single-worker.json
    test-max-workers-2.json
    test-with-quality-gate.json
```

**規約**: `fixtures/{domain}/{category}/{name}.json`。cargo testとE2Eテスト両方で共用。

#### C6: Test Scenario DSL（Markdown・ドメイン横断）

```markdown
## scenario: orchestrator/single-node-execution
domain: orchestrator

### setup
- reset: [orchestrator]
- fixture: orchestrator/graphs/single-node-success.json → load_test_graph
- fixture: orchestrator/templates/echo-success.json → load (implicit)

### steps
1. tool: execute_workflow_node {"template_id":"echo-success","params":{"msg":"hello"},"department":"test"}
2. wait: get_execution_status {"node_id":"node-1"} → result.status == "success" (timeout=10)

### assert
- tool: get_execution_status {"node_id":"node-1"} → result.exit_code == 0
- tool: get_event_feed {"department":"test","limit":5} → result.length >= 2
- tool: get_audit_log {"node_id":"node-1"} → result.length == 1
```

```markdown
## scenario: anima/failure-notification
domain: anima, orchestrator

### setup
- reset: [anima, orchestrator]
- fixture: anima/states/idle-default.json → set_anima_state
- fixture: orchestrator/graphs/single-node-failure.json → load_test_graph

### steps
1. tool: execute_workflow_node {"template_id":"echo-failure","department":"test"}
2. wait: get_execution_status {"node_id":"node-1"} → result.status == "failed" (timeout=10)
3. wait: get_speech_queue {} → result.length > 0 (timeout=5)

### assert
- tool: get_anima_state {} → result.mode != "error"
- tool: get_speech_queue {} → result.0.priority == "low"
- tool: get_narration_state {} → result.suppressed == false
```

```markdown
## scenario: animation/pose-transition
domain: animation

### setup
- reset: [animation]

### steps
1. tool: set_avatar_pose {"pose_name":"greeting","blend":0.5}
2. wait: get_avatar_state {} → result.current_pose == "greeting" (timeout=3)
3. tool: set_avatar_pose {"pose_name":"idle","blend":1.0}
4. wait: get_avatar_state {} → result.current_pose == "idle" (timeout=3)

### assert
- tool: get_avatar_state {} → result.blend_complete == true
```

**ドメイン横断テスト可能**: `domain: anima, orchestrator` でマルチドメインシナリオ記述。

#### C7: Test Runner（共通基盤・シェルスクリプト）

```bash
# scripts/run-e2e-test.sh
#
# 使い方:
#   bash scripts/run-e2e-test.sh                          # 全ドメイン全シナリオ
#   bash scripts/run-e2e-test.sh --domain orchestrator    # ドメイン指定
#   bash scripts/run-e2e-test.sh --scenario anima/failure  # 個別シナリオ
#   bash scripts/run-e2e-test.sh --ci                      # CI用（JSON結果+exit code）
#
# フロー:
#   1. ORIBIS_TEST_MODE=1 + ORIBIS_TEST_DOMAINS でheadless起動
#   2. socket_path/token取得
#   3. tests/e2e/scenarios/{domain}/*.md を列挙
#   4. oribis-test-client.py でシナリオ逐次実行
#   5. 結果集約 → tests/e2e-results/YYYY-MM-DD-HHMMSS.json
#   6. PASS/FAIL summary表示 + exit code

# ディレクトリ構成:
#   tests/e2e/
#     scenarios/
#       orchestrator/
#         S01-single-node-success.md
#         S02-single-node-failure.md
#         ...
#       anima/
#         A01-failure-notification.md
#         A02-suppress-narration.md
#         ...
#       animation/
#         V01-pose-transition.md
#         V02-expression-blend.md
#         ...
#     e2e-results/           ← gitignore
```

### 9-4. 新ドメイン追加手順（テンプレート）

新機能のE2Eテストを追加する際の手順:

```
1. Domain Test Tools定義
   → src-tauri/src/mcp/tools/{domain}.rs に handle関数追加
   → server.rs handle_tool_call に分岐追加

2. Fixture作成
   → src-tauri/tests/fixtures/{domain}/ にJSON配置

3. Scenario作成
   → tests/e2e/scenarios/{domain}/*.md にDSLで記述

4. 動作確認
   → python3 scripts/oribis-test-client.py ... tool {new_tool} '{...}'
   → bash scripts/run-e2e-test.sh --domain {domain}
```

クライアント（C2）・テストランナー（C7）・Headlessモード（C1）は変更不要。

### 9-5. テストシナリオ一覧

```
━━ Orchestrator（Phase 1）━━━━━━━━━━━━━━━━━━━
S01: 1ノード成功実行 → status=success, exit_code=0, event_feed記録, audit_log記録
S02: 1ノード失敗実行 → status=failed, error_summary存在, Anima通知発火
S03: 1ノードタイムアウト → status=failed, error="timeout"
S04: 1ノードキャンセル → status=cancelled
S05: 直列3ノード → topo order実行, 全success
S06: 直列3ノード（2番目失敗）→ node-2=failed, node-3=skipped
S07: 並列2ノード → 同時実行, 両方success
S08: ダイヤモンド依存 → 依存解決正常, merge node実行
S09: max_workers=2で3ノード → 2並列 + 1待機
S10: 全体キャンセル → Running全cancel, Pending全cancelled
S11: 未登録template_id → 拒否, audit_log記録
S12: シェルメタ文字パラメータ → バリデーション拒否

━━ Anima連携（Phase 1）━━━━━━━━━━━━━━━━━━━━━
A01: 失敗時Anima通知 → speech_queue確認, priority=low
A02: suppress_narration中 → 通知抑制確認
A03: 高頻度イベント → queue上限5件、低優先度破棄確認
A04: state遷移 → idle→working→idle正常遷移

━━ Animation/Avatar（Phase 2予定）━━━━━━━━━━━━
V01: ポーズ遷移 → greeting→idle、blend_complete確認
V02: 表情ブレンド → happy 0.8→neutral 0.0、モーフ値確認
V03: リップシンク → speak→lip morph発火→speak終了→lip reset
V04: 連続ポーズ → goTo+speakOrFallback二重発火問題の回帰テスト

━━ Department（Phase 2予定）━━━━━━━━━━━━━━━━━
D01: 部門CRUD → 作成→読取→更新→削除
D02: Worker生成 → 部門設定からWorker起動→MCP token発行確認
D03: max_workers制約 → 上限超過時の拒否確認
```

### 9-6. Claude駆動テストのフロー例

```bash
# Step 1: Oribis headless起動
ORIBIS_TEST_MODE=1 cargo run --features tauri-backend &
# stdoutからJSON読み取り
read APP_INFO < /proc/$!/fd/1
SOCKET=$(echo $APP_INFO | jq -r .socket_path)
TOKEN=$(echo $APP_INFO | jq -r .token)

# Step 2: 接続 + ヘルスチェック
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool core_test_health '{}'

# Step 3: オーケストレーターテスト
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool core_test_reset '{"domains":["orchestrator"]}'
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool load_test_graph \
  "$(cat src-tauri/tests/fixtures/orchestrator/graphs/single-node-success.json)"
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool execute_workflow_node \
  '{"template_id":"echo-success","params":{"msg":"test"},"department":"test"}'
python3 scripts/oribis-test-client.py $SOCKET $TOKEN \
  wait get_execution_status '{"node_id":"node-1"}' result.status success 10

# Step 4: Animaテスト（同一セッションで続行）
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool core_test_reset '{"domains":["anima"]}'
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool get_anima_state '{}'
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool trigger_anima_event \
  '{"category":"workflow_fail","payload":{"node_id":"n1","error":"test error"}}'
python3 scripts/oribis-test-client.py $SOCKET $TOKEN \
  wait get_speech_queue '{}' result.length 1 5

# Step 5: スナップショット取得（デバッグ用）
python3 scripts/oribis-test-client.py $SOCKET $TOKEN tool core_test_snapshot '{}'

# Step 6: クリーンアップ
kill $(echo $APP_INFO | jq -r .pid)
```

### 9-7. 既存テスト基盤との統合

```
レイヤー               テスト手法                     コンポーネント
──────────────────────────────────────────────────────────────
L1: Rust unit         cargo test                     FakeExecutor, fixtures(共用)
L2: Rust integration  cargo test (mcp_integration)   start_test_broker(), roundtrip()
L3: TS unit           pnpm test                      executionReducer pure fn
L4: E2E interactive   oribis-test-client (Claude)    C1+C2+C3+C4+C5
L5: E2E batch         run-e2e-test.sh (CI)           C1+C2+C3+C4+C5+C6+C7
```

### 9-8. 実装優先順位

```
Phase 1 MVP:
  1. C1: Headless起動モード
  2. C2: oribis-test-client.py（汎用クライアント）
  3. C3: Core Test Tools（reset, snapshot, health）
  4. C4 orchestrator: execute_workflow_node, get_execution_status等
  5. C5 orchestrator: fixtures + S01-S04シナリオ
  6. C4 anima: get_speech_queue, get_narration_state
  7. A01-A02シナリオ

Phase 1 完了時:
  8. C4 orchestrator残り + S05-S12シナリオ
  9. A03-A04シナリオ
  10. C7: Test Runner基本版

Phase 2:
  11. C4 animation: get_avatar_state, set_avatar_pose等
  12. C4 department: list_departments, get_worker_status等
  13. V01-V04, D01-D03シナリオ
  14. C6: Scenario DSL正式パーサー
  15. C7拡張: CI/CD統合
```

## 10. 判断

A案（PTY直結のみ）は最善ではない。tmuxに勝てない。

**F案Phase0+Phase1（実行意味論定義 → 定義済みタスク実行 + ExecutionResult + event_feed記録 + UI状態表示 + Anima低頻度通知）が最善の起点。**

理由:
- セキュリティ: allowlist CommandTemplate。PTYとの責務分離明確
- テスト容易: trait/純粋関数で切り出し、fake/mockでテスト可能
- tmux超越: 状態一覧・失敗検知・文脈復帰で測定可能な価値
- 既存基盤活用: WorkerManager/suppress_narration/event_feed/MCP audit
- 撤退可能: CommandExecutor + ExecutionResultはCLI-firstでも単独利用可能
