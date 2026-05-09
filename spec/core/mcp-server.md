# Oribis MCP Server 設計書

**バージョン**: 3.1
**最終更新**: 2026-05-07
**レビュー履歴**: codex-reviewer v1 FAIL(5件)→v2 FAIL(5件)→codex-adviser 分析→v3→v3.1(実装完了後更新)
**実装ステータス**: Phase 1-A〜9 完了（コミット 3c6e86b on sysdev-1/mcp-server）。111テスト PASS。Phase 10（GUI統合）未着手

---

## 1. 背景

Oribis は Tauri + Rust 製の AI コンパニオンアプリ。内部サブシステム:
- **記憶システム**: SQLite 4レイヤー（memory_events, memories, open_loops, relationship_model）
- **Anima パイプライン**: 統一応答パイプライン（Cache/AI/Hybrid 3モード）
- **好感度**: affinity 0-100, 6 tier
- **アバター制御**: 表情・アニメーション・TTS
- **オーケストレーター**: 部門定義 + Worker PTY（設計済・未実装）

**現在の制約**: 外部 Worker（Claude Code, Codex CLI, OpenCode）および外部 MCP Client（Claude Desktop 等）は Oribis 内部の記憶・アバター・好感度・Anima 状態に一切アクセスできない。

---

## 2. 設計思想

**Capability Firewall** — Worker/外部クライアントに Oribis を「リモコン操作」させるのではなく、「Oribis の能力を借りる」ための窓口を開く。

原則:
- **書込みは隔離**: Worker 記憶は companion 主記憶と分離。品質管理後に昇格
- **状態操作は排他制御**: Broker 内の状態機械で受理判定。last-write-wins 禁止
- **読取りは制限付き**: 返却量・粒度を絞る。private raw event のそのまま返却禁止
- **コアパイプライン不変**: インプロセス呼出しは一切 MCP 化しない

---

## 3. 要件

### 3.1 機能要件

| ID | 要件 | 優先度 |
|----|------|--------|
| R1 | Worker が Oribis の記憶を読み取れる（トピック検索、人物像、未解決タスク） | HIGH |
| R2 | Worker が体験を記憶に書き込める（Worker 知見の蓄積） | HIGH |
| R3 | Worker がアバターを制御できる（発話・表情・通知） | HIGH |
| R4 | Worker が Anima 状態を制御できる（状態遷移・ナレーション制御） | HIGH |
| R5 | Worker が好感度を読み取れる（読み取り専用） | MEDIUM |
| R6 | 複数 Worker が同時接続できる | HIGH |
| R7 | コアパイプラインのパフォーマンスに影響しない | HIGH |
| R8 | 外部 MCP Client（Claude Desktop, Claude Code, Codex CLI 等）がトークン発行を経て接続できる | MEDIUM |

### 3.2 非機能要件

| ID | 要件 |
|----|------|
| NR1 | ローカルマシン内通信のみ（ネットワーク公開禁止） |
| NR2 | Worker 異常終了時にリソースリークしない |
| NR3 | 既存の Named Pipe / Tauri invoke / Plugin API に影響しない |
| NR4 | トークンがプロセス引数・ログに露出しない（**Worker 自動注入経路**）。外部クライアント経路（R8）ではローカル設定ファイルへの保存が必要であり、NR4-EXT として別脅威モデルで管理する（Phase 10 設計課題 P10-3） |

---

## 4. アーキテクチャ

### 4.1 接続モデル: per-Client プロセス方式

stdio transport は親子 1:1 接続のため、複数クライアントの同時接続には対応できない。
各クライアント接続時に Oribis が専用の MCP Server プロセスを spawn する。

```
┌──────────────────────────────────────────────────┐
│ Oribis (Tauri メインプロセス)                      │
│                                                    │
│  [パイプライン] ← 現状維持（Rust内部直接呼出し）    │
│    ↕                                               │
│  [SQLite記憶DB] [affinity.json] [cache/]           │
│    ↕                                               │
│  [MCP Broker]  ← 新規                              │
│    │  状態保護層（単なる中継ではない）               │
│    │  SharedState: Arc<RwLock>                      │
│    │  avatar操作 → Tauri event emit                 │
│    │  Anima状態 → 状態機械で受理判定                │
│    │  記憶write → command queue → pipeline API      │
│    │  記憶read → snapshot cache                     │
│    │  監査ログ → mcp_audit_log テーブル             │
└────┼─────────────────────────────────────────────────┘
     │ Unix Socket (Linux) / Named Pipe (Windows)
     │
     ├── oribis-mcp (PID 1001) ─ stdio ─ Worker A (Claude Code)
     ├── oribis-mcp (PID 1002) ─ stdio ─ Worker B (Codex CLI)
     ├── oribis-mcp (PID 1003) ─ stdio ─ Worker C (OpenCode)
     └── oribis-mcp (PID 1004) ─ stdio ─ Claude Desktop（外部）
```

### 4.2 oribis-mcp バイナリ

軽量 Rust バイナリ（Oribis にバンドル）。

- 起動引数: `oribis-mcp --broker-socket <path>`
- トークン受渡し: **環境変数 `ORIBIS_MCP_TOKEN`**（プロセス引数に載せない — NR4）
- MCP Client とは stdio で JSON-RPC 通信
- Broker とは内部 socket で通信
- クライアント終了時に自動終了（stdin EOF 検知）
- Heartbeat: **10 秒間隔**で Broker へ送信。Broker 側は **30 秒** 無応答でセッション削除
- MCP プロトコルバージョン: `2024-11-05`

**なぜ HTTP/SSE ではないか**:
- stdio transport は全 CLI（Claude Code, Codex, OpenCode）および Claude Desktop で確実にサポート
- per-Client プロセスはクライアント終了と同時に自動消滅し、リソースリークがない

### 4.3 接続経路: Worker（自動）

```
1. Oribis Orchestrator: Worker 起動決定
2. per-worker token 生成（UUID v4、Broker メモリ内のみ）
3. Broker に token → { department_id, client_type: "worker" } を登録
4. CLI 起動コマンドに MCP server を環境変数付きで追加:
   ORIBIS_MCP_TOKEN=<token> claude --mcp-server "oribis:oribis-mcp --broker-socket ..."
5. Worker 処理実行（MCP tool 利用可能）
6. Worker 終了 → oribis-mcp stdin EOF → プロセス自動終了
7. Broker が token を自動削除
```

**settings.json を一切編集しない**。CLI の `--mcp-server` 起動引数で注入。

### 4.4 接続経路: 外部クライアント（手動 — R8）

```
1. ユーザーが Oribis GUI → 設定 → MCP タブ → 「外部接続トークンを生成」
2. クライアント種別を選択（Claude Desktop / Claude Code / Codex CLI / Other）
3. Oribis が token 生成 + Broker に { client_type: "external" } で登録
4. GUI にクライアント別の設定スニペットを表示（コピーボタン付き）
5. ユーザーが該当クライアントの設定に貼り付け
6. クライアント起動時に oribis-mcp が spawn → Broker に接続
```

**クライアント別設定テンプレート**:

| クライアント | 設定先 | スニペット例 |
|-------------|--------|-------------|
| Claude Desktop | `claude_desktop_config.json` | `{ "mcpServers": { "oribis": { "command": "oribis-mcp", "args": ["--broker-socket", "<path>"], "env": { "ORIBIS_MCP_TOKEN": "<token>" } } } }` |
| Claude Code | `--mcp-server` フラグ | `claude --mcp-server "oribis:ORIBIS_MCP_TOKEN=<token> oribis-mcp --broker-socket <path>"` |
| Codex CLI | `--mcp-server` フラグ | `codex --mcp-server "oribis:ORIBIS_MCP_TOKEN=<token> oribis-mcp --broker-socket <path>"` |
| その他 | 手動 | `ORIBIS_MCP_TOKEN=<token> oribis-mcp --broker-socket <path>` を子プロセスとして spawn |

**トークン管理**: GUI から発行済みトークンの一覧表示・無効化が可能。Oribis 再起動時は全外部トークンが失効（再発行が必要）。

> **NR4 脅威モデル注記**: Worker 自動注入では token は環境変数のみで渡されプロセス引数・ディスクに一切残らない。外部クライアント（R8）では `claude_desktop_config.json` 等の **ローカル設定ファイルに token を保存** する必要があり、NR4 の「ディスクに露出しない」と矛盾する。Phase 10 実装時に以下を検討: (1) config ファイルの暗号化/OS keychain 保存、(2) Oribis 起動時に named pipe 経由で token を動的注入、(3) NR4 のスコープを「Worker 経路のみ」に明示限定。現時点では外部クライアント経路は **R8 = MEDIUM 優先度** かつ Phase 10 未着手のため、脅威モデルの確定を Phase 10 設計時に行う。

### 4.5 異常終了時の保証

| 障害 | 対処 |
|------|------|
| Worker/外部クライアント異常終了 | oribis-mcp の stdin EOF → 自動終了。Broker は heartbeat timeout (30s) で token 削除 |
| oribis-mcp 異常終了 | クライアント側で MCP disconnection として処理。本体タスクに影響なし（MCP はオプショナル） |
| Oribis 本体クラッシュ | Broker socket 消失 → 全 oribis-mcp が接続エラーで終了。クライアントは MCP なしで継続 |

---

## 5. 認可・権限制御

### 5.1 認証モデル

- **ローカル限定**: Broker socket パスは `$XDG_RUNTIME_DIR/oribis/broker-<pid>.sock`（フォールバック: `$TMPDIR/oribis-<uid>/broker-<pid>.sock`）。**専用サブディレクトリを 0700 で作成してから socket をバインド**する。`/tmp/` 直下への直接配置は禁止（symlink race / 横取り防止）。Windows では Named Pipe `\\.\pipe\oribis-broker-<pid>` を使用し、作成者 SID のみにアクセスを制限する
- **per-Client トークン**: UUID v4。Broker がメモリ内で管理。**ディスク・プロセス引数・ログに書き出さない**
- **トークン受渡し**: 環境変数 `ORIBIS_MCP_TOKEN` のみ（`ps -ef` で不可視）。**注意**: Linux では同一ユーザーの他プロセスから `/proc/<pid>/environ` 経由で読取り可能。これはローカル同一ユーザー攻撃であり、脅威モデル上は「ローカルユーザー権限を既に持つ攻撃者」として受容する（socket アクセスも同一ユーザーなら可能なため、環境変数単体のリスクではない）
- **トークン → クライアント情報マッピング**: `{ department_id, client_type: "worker"|"external" }`

### 5.2 権限スコープ

| 操作 | Worker | 外部クライアント | 備考 |
|------|--------|-----------------|------|
| memory_search (read) | ✅ | ✅ | 返却量制限あり（§6.4） |
| memory_save (write) | ✅ | ✅ | domain=worker_ops 固定。companion 直接不可 |
| speak / set_expression / notify | ✅ | ✅ | ephemeral 操作（§6.3） |
| set_anima_state / suppress/resume_narration | ✅ | ✅ | authoritative 操作（§6.3） |
| affinity read | ✅ | ✅ | — |
| affinity write | ❌ | ❌ | パイプライン経由のみ |
| AnimaMode 変更 (Cache/AI/Hybrid) | ❌ | ❌ | ユーザー設定のみ |
| pty / plugin / CLI 直接操作 | ❌ | ❌ | 禁止 |

### 5.3 監査ログ

全 MCP 操作を SQLite に記録:

```sql
CREATE TABLE mcp_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,          -- ISO 8601
    client_type TEXT NOT NULL,        -- 'worker' | 'external'
    department_id TEXT,               -- worker のみ
    token_prefix TEXT NOT NULL,       -- 先頭8文字のみ
    tool_name TEXT NOT NULL,
    params_summary TEXT,              -- 機密除外の要約
    result_status TEXT NOT NULL       -- 'ok' | 'error' | 'denied' | 'auth_failed'
);
```

---

## 6. MCP で公開する機能

### 6.1 Tools — 記憶系

| Tool | パラメータ | 説明 |
|------|-----------|------|
| `memory_search` | `query: string, limit?: int (default 10, max 50)` | 記憶検索。memory_events + memories から返却。raw_text は要約形式（private 原文は非公開） |
| `memory_save` | `raw_text: string, topics: string[], event_type?: string, idempotency_key: string` | Worker 体験を記憶に書込み |

**memory_save 詳細**:
- `domain` は `worker_ops` 固定（companion 領域に直接書込み不可）
- `salience_score` は Rust ヒューリスティクスで自動算出（クライアント指定不可）。計算式: `(raw_text.len() / 500).min(1.0) * 0.5`（範囲: 0.0〜0.5）
- `confidence` は NewMemoryEvent のデフォルト値 1.0 を使用（将来の consolidation で Worker 起源の品質評価を追加予定）
- 冪等性: `idempotency_key` 必須。同一キーの 2 回目以降は `{ result: "already_exists" }` を返却。UNIQUE 制約で競合状態にも対応

```sql
-- memory_events テーブルに列追加
ALTER TABLE memory_events ADD COLUMN idempotency_key TEXT;
CREATE UNIQUE INDEX idx_events_idempotency ON memory_events(idempotency_key) WHERE idempotency_key IS NOT NULL;
```

**記憶汚染防止策**:
- Worker 記憶は `domain=worker_ops` に隔離
- companion 主記憶への昇格は Oribis 内部の consolidation スケジューラが品質判定後に実行
- `memory_search` に rate limit（10 req/min per client）
- `memory_save` は batch/debounce（同一クライアントから 1 秒以内の連続 save は結合）
- Worker が自分で注入した内容を `memory_search` で再取得することによる自己強化ループを防止: 書込み後 60 秒間は自クライアントの書込みが検索結果に含まれない

### 6.2 Tools — アバター制御系

| Tool | パラメータ | 説明 |
|------|-----------|------|
| `speak` | `text: string, priority?: "normal"\|"high"` | TTS 発話。high は割り込み |
| `set_expression` | `name: string, intensity?: float (default 1.0)` | 表情変更 |
| `notify` | `title: string, body: string` | UI トースト通知 |

### 6.3 Tools — Anima 制御系

| Tool | パラメータ | 説明 |
|------|-----------|------|
| `set_anima_state` | `category: AnimaCategory` | Anima 状態遷移（working, done, error, idle 等） |
| `get_anima_state` | — | 現在の AnimaCategory + AnimaMode を返却 |
| `suppress_narration` | `duration_sec: int (max 600)` | Anima 自動ナレーション抑制 |
| `resume_narration` | — | ナレーション抑制を即解除 |

**操作の 2 系統分類**:

| 系統 | 操作 | 特性 |
|------|------|------|
| **Authoritative**（状態変更） | set_anima_state, suppress/resume_narration | 単一キュー。状態機械で受理判定。遷移不可能な操作は拒否 |
| **Ephemeral**（一過性） | speak, set_expression, notify | 優先度付きキュー。TTL 付き（set_expression: 30秒で自動復帰）。coalesce（同一クライアントの連続 set_expression は最新のみ適用） |

**Anima 状態遷移の排他制御**:
- Broker 内に AnimaCategory の状態機械を保持
- `set_anima_state` は遷移可能表で受理判定（例: idle→working ✅、error→working ❌ → idle 経由が必要）
- 複数クライアントの同時リクエストは単一キューで直列化
- 各操作に `source`（クライアントID）、`correlation_id` を付与

**ナレーション経路の優先度**:

| 条件 | 経路 |
|------|------|
| クライアントが `speak()` を呼んだ | MCP 直接発話（Anima ナレーション不要） |
| クライアントが `suppress_narration()` 中 | Anima ナレーション抑制 |
| クライアントが MCP 未接続（フォールバック） | 従来通りフック JSONL → Anima ナレーション |

### 6.4 Resources（読み取り専用）

| URI | 内容 | 備考 |
|-----|------|------|
| `oribis://memory/events?topic={topic}&limit={n}` | トピック関連エピソード | 要約形式。raw_text 原文は非公開 |
| `oribis://memory/relationship_model` | ユーザー人物像 JSON | read-only |
| `oribis://memory/open_loops` | 未解決タスク・関心事一覧 | read-only |
| `oribis://affinity` | `{ value, tier, label }` | read-only |
| `oribis://anima/state` | `{ category, mode, narration_suppressed }` | mode は現時点で `"unknown"` 固定（AnimaMode の Broker 連携は Phase 10） |
| `oribis://anima/categories` | 利用可能な AnimaCategory 一覧 | set_anima_state に渡せる値 |

### 6.5 公開禁止

| 機能 | 理由 |
|------|------|
| pty_spawn / pty_write | 任意コマンド実行 |
| import_plugin / delete_plugin | プラグイン改竄 |
| run_claude_process / CLI 直接操作 | 二重起動・デッドロック |
| affinity 直接書込み | イベントベースの変動保証を破壊 |
| AnimaMode 変更（Cache/AI/Hybrid） | ユーザー設定のみ |
| open_loops / relationship_model 書込み | Anima 内部 consolidation の責務 |

---

## 7. SQLite 並行アクセス

### 7.1 アクセスパターン

| 書き手 | テーブル | 操作 |
|--------|---------|------|
| パイプライン（内部） | memory_events, memories, open_loops, relationship_model | read/write 全権 |
| MCP Broker | memory_events | INSERT のみ（domain=worker_ops） |
| MCP Broker | memories, open_loops, relationship_model | read のみ |
| MCP Broker | mcp_audit_log | INSERT のみ |

### 7.2 並行制御

- SQLite WAL モード（既存設定）
- `busy_timeout = 5000ms`（既存設定）
- MCP 側の INSERT 失敗時: JSON-RPC error `{ code: -32000, message: "database busy, retry later" }`
- **Broker は既存の Rust pub 関数（`append_event()`, `query_events_by_topics()`, `query_profile_memories()` 等）を経由して DB アクセス**。直接 SQL は書かない。これにより既存のバリデーション・ドメインロジックを再利用し、SQLite contention は WAL + busy_timeout で対処

### 7.3 L1→L2 昇格責務

MCP 経由で書き込まれた memory_events の昇格は **Oribis パイプラインの既存 consolidation スケジューラが担当**。MCP は event 投入のみ。

```
Client → MCP → memory_events INSERT (domain=worker_ops, confidence=1.0)
                    ↓ （既存スケジューラが定期スキャン — Domain::WorkerOps 対応済み）
              consolidation → 品質判定 → memories テーブルへ昇格
```

### 7.4 memories テーブルの domain 分離（前提作業）

現在の `memories` テーブルには `domain` 列がない。consolidation で worker_ops → memories に昇格すると、`retrieval.rs` の `query_profile_memories()` が domain を区別できず companion 記憶と混在する。

**対処**: memories テーブルに `domain TEXT NOT NULL DEFAULT 'companion'` 列を追加。retrieval.rs の検索クエリで `WHERE domain = 'companion'` をデフォルトフィルタに追加。Worker 知見を意図的に含めたい場合のみ domain フィルタを外す。

```sql
ALTER TABLE memories ADD COLUMN domain TEXT NOT NULL DEFAULT 'companion';
CREATE INDEX idx_memories_domain ON memories(domain);
```

### 7.5 Anima 状態遷移 API のリファクタ（実装済み）

`anima_state()` のロジック（category → PipelineConfig → execute_pipeline）を pub async 関数として `pipeline.rs` に抽出済み。lib.rs の Tauri コマンドも委任形式にリファクタ済み。

```rust
// pipeline.rs
pub async fn trigger_anima_state(
    base_dir: PathBuf,
    project_id: &str,
    category: &str,
    backend: &str,
    adapter: Arc<dyn CliAdapter>,
) -> Result<PipelineResponse>
```

MCP Broker からは `NoOpAdapter`（TTS/UI 出力を行わないスタブ）で呼び出し。アバター制御は別途 `speak` / `set_expression` tool で行う。

---

## 8. コアパイプラインを MCP 化しない理由

- パイプライン内の操作は μs 級。MCP（JSON-RPC over stdio）は ~5-20ms/call
- Cache/Hybrid モードは「LLM を呼ばない」仕組み。MCP tool は LLM 判断依存のため原理的に矛盾
- パイプラインの確定的動作（毎ターン必ず affinity 更新・記憶保存）が LLM tool call では保証されない
- Broker が直接 DB を触かず service API 経由にすることで、パイプライン側の SQLite contention を最小化

---

## 9. 受入条件（AC）

| AC | 要件 | 条件 | 検証方法 | 実装状況 |
|----|------|------|---------|---------|
| AC-1 | R1 | 単一 Worker が `memory_search` で結果を取得できる | 単体テスト | ✅ Phase 1-9 |
| AC-2 | R2 | `memory_save` で書込み後、`domain=worker_ops` の MCP 内検索でヒットする（companion L3 検索では domain フィルタにより除外。昇格時の domain 変換ポリシーは memory.md consolidation 設計で管理） | 統合テスト | ✅ Phase 1-9 |
| AC-3 | R3 | `speak` / `set_expression` でアバターが反応する | 統合テスト | ⚠️ Backend完了（Tauri event emit実装済）。フロント受信＝Phase 10 |
| AC-4 | R4 | `set_anima_state` で Anima 状態遷移 + 表情・モーション自動変化 | 統合テスト | ⚠️ Backend完了（trigger_anima_state実装済）。GUI連動＝Phase 10 |
| AC-5 | R6 | 2 クライアント同時接続で独立に tool 利用可能 | 統合テスト | ✅ Phase 1-9 |
| AC-6 | NR2 | クライアント kill -9 後 30 秒以内に oribis-mcp 消滅 + token 削除 | 異常系テスト | ✅ Phase 1-9（cleanup interval + disconnect時token revoke） |
| AC-7 | — | 全 tool 呼出しが mcp_audit_log に記録される | 単体テスト | ✅ Phase 1-9 |
| AC-8 | — | 禁止操作（affinity write, pty_spawn 等）が denied で拒否 | 単体テスト | ✅ Phase 1-9 |
| AC-9 | — | MCP Server 利用不可でも Worker 本体タスクが正常完了する | 統合テスト | ✅ Phase 1-9 |
| AC-10 | R4 | `suppress_narration` / `resume_narration` が ON/OFF 制御する | 統合テスト | ✅ Phase 1-9 |
| AC-11 | R5 | `oribis://affinity` で value/tier/label を取得 + write 拒否確認 | 単体テスト | ✅ Phase 1-9 |
| AC-12 | R7 | パイプライン応答レイテンシが MCP 有無で ±5% 以内 | ベンチマーク | ⏳ Phase 10（実アプリ起動が必要） |
| AC-13 | NR3 | Named Pipe / Plugin API の回帰テスト PASS | 回帰テスト | ⏳ Phase 10（実アプリ起動が必要） |
| AC-14 | NR4 | token がプロセス引数・ログに露出しない | `ps -ef` + ログ grep + `/proc/<pid>/environ` 脅威受容確認 | ✅ Phase 1-9 |
| AC-15 | R8 | GUI からトークン発行 → 外部クライアント（Claude Desktop/Code/Codex）から接続成功 | E2E テスト | ⏳ Phase 10（GUI実装が必要） |
| AC-16 | R4 | 不正な状態遷移（error→working）が拒否される | 単体テスト | ✅ Phase 1-9 |
| AC-17 | — | `memory_save` 同一 idempotency_key の 2 回目が `already_exists` を返却 | 単体テスト | ✅ Phase 1-9 |
| AC-18 | NR1 | Broker が TCP listen せず、socket directory が 0700 で保護されている | `ss -ltnp` + `stat` 検証 | ⏳ Phase 10（実アプリ起動が必要） |

---

## 10. 工数見積もり

| 作業項目 | 工数 |
|---------|------|
| oribis-mcp バイナリ scaffold + stdio JSON-RPC handler | 8h |
| Broker（Unix Socket / Named Pipe）+ token 管理 + 状態機械 | 16h |
| Tool 実装 — 記憶系（memory_search, memory_save + 汚染防止策） | 12h |
| Tool 実装 — アバター系（speak, set_expression, notify） | 6h |
| Tool 実装 — Anima 制御系（set_anima_state, suppress/resume + 排他制御） | 10h |
| Resource 実装（6 URI） | 6h |
| 権限チェック + 監査ログ | 6h |
| Worker 起動時 MCP 引数注入（Orchestrator 連携） | 4h |
| 外部クライアント — トークン発行 GUI + config JSON エクスポート | 4h |
| 単体テスト + 統合テスト（AC-1〜AC-17） | 14h |
| **合計** | **86h** |

---

## 10.5 Phase 10 バックログ（codex-adviser v3.1 指摘由来）

| ID | 指摘元 | 内容 |
|----|--------|------|
| P10-1 | #5 | 外部クライアント（R8）再起動後の token stale 問題。persistent token or 自動再接続の設計 |
| P10-2 | #6 | クライアント別（Claude Desktop / Code / Codex CLI / OpenCode）の起動フラグ・プロトコル互換性検証を AC-15 に組み込む |
| P10-3 | #1 | 外部クライアント経路の NR4 脅威モデル確定（config 暗号化 / keychain / 動的注入） |
| P10-4 | — | フロントエンド Tauri event subscription（AC-3/AC-4 GUI完了） |
| P10-5 | — | Worker MCP 自動注入（Orchestrator 連携） |
| P10-6 | — | プロセスライフサイクル E2E テスト |

---

## 11. 既存機構との関係

### 共存（変更なし）

| 機構 | 理由 |
|------|------|
| Named Pipe IPC | 内部ツール間の軽量通信。用途が異なる |
| Tauri invoke | フロント↔バック内部通信。MCP は外部→Oribis |
| JSONL ログ | 内部記録用 |
| Plugin API | JS sandbox プラグイン用。MCP は外部 CLI/アプリ用。入口は異なるが内部で同じ関数を呼ぶ |

---

## 12. 関連ドキュメント

- `pipeline.md` — 統一応答パイプライン（MCP 化しない部分）
- `memory.md` — 4レイヤー記憶システム（MCP 公開対象）
- `affinity.md` — 好感度システム（read-only 公開）
- `anima.md` — AnimaMode・AnimaCategory（状態制御公開）
- `anima-orchestrator-architecture.md` — オーケストレーター（Worker 起動・MCP 注入）

*作成日: 2026-05-07*
