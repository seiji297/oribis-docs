# セッションデータ管理 設計書

**バージョン**: 1.0（anima-spec.md §8/§11 + architecture-diagrams.md §10 より統合）
**最終更新**: 2026-04-28

---

## 1. 概要

セッション内の2種類のデータ管理:
- **統合履歴**: ユーザー発話・メイン応答・Anima応答の時系列記録
- **タスク管理**: LLMが操作するプロジェクト別タスク

---

## 2. 統合履歴（§8）

### 2.1 設計判断

- メインチャットとAnimaの応答を**同一履歴**に統合記録
- セッション開始時のみ直近30件をL3注入（セッション中はCLI側コンテキスト窓が保持）
- JSONLフォーマットで追記（全書き換えなし）

### 2.2 MessageSource 列挙型

```rust
pub enum MessageSource {
    User,          // ユーザー発話
    AnimaMain,    // メインチャット応答
    AnimaAutonomous,   // Anima応答
}
```

### 2.3 UnifiedMessage 型

```rust
pub struct UnifiedMessage {
    pub id: String,                // UUID v4
    pub ts: DateTime<Utc>,         // タイムスタンプ
    pub source: MessageSource,     // 発話源
    pub project_id: String,        // プロジェクトID
    pub text: String,              // 発話テキスト（マーカー除去済）
    pub affinity_delta: i8,        // Anima応答時のみ使用（User時は0）
}
```

コンストラクタ:

```rust
UnifiedMessage::new_user(text: &str, project_id: &str) -> Self
UnifiedMessage::new_character(text: &str, project_id: &str, affinity_delta: i8) -> Self
UnifiedMessage::new_anima(text: &str, project_id: &str) -> Self
```

### 2.4 ストレージ

**保存先**: `~/.config/oribis/projects/{project_id}/history.jsonl`（プロジェクト別）

**フォーマット**: 1行1エントリのJSONL

```jsonl
{"id":"uuid1","ts":"2026-04-26T14:30:00Z","source":"User","project_id":"my-project","text":"ビルドして","affinity_delta":0}
{"id":"uuid2","ts":"2026-04-26T14:30:01Z","source":"AnimaMain","project_id":"my-project","text":"ビルド成功です。テスト3件 PASS。","affinity_delta":0}
```

### 2.5 API

```rust
// メッセージ追記
pub fn append_message_at(base_dir: &Path, msg: &UnifiedMessage) -> Result<()>

// 直近N件取得
pub fn recent_messages_at(base_dir: &Path, limit: usize) -> Result<Vec<UnifiedMessage>>

// 履歴圧縮
pub fn compress_at(base_dir: &Path) -> Result<()>

// 履歴検索（過去参照用）
// 用途: 「先週何話した？」等のLLMによる履歴参照
pub fn history_search_at(base_dir: &Path, query: &str, days: u32) -> Result<Vec<UnifiedMessage>>
```

### 2.6 サイズ制限

| 項目 | 値 |
|------|---|
| 保持上限 | 5000エントリ |
| 圧縮トリガー | 上限超過時 |
| 圧縮後サイズ | 3000エントリ（古いものから削除） |

### 2.7 L3注入（セッション開始時のみ）

```
[これまでの会話]
2026-04-25 14:30 ユーザー: ビルドして
2026-04-25 14:30 Anima: ビルド成功です。テスト3件 PASS。
...（直近30件）
```

セッション継続中は注入しない（CLI側のコンテキスト窓が保持するため）。

### 2.8 圧縮戦略

Phase 1: 単純な古いエントリ削除（5000 → 3000）

Phase 2: サルベージスキャン付き圧縮

圧縮前に削除対象エントリをスキャンし、memory_events に未記録の重要情報を救済する。

```rust
pub fn compress_at(base_dir: &Path, project_id: &str) -> Result<()> {
    let entries = load_all(base_dir)?;
    if entries.len() <= 5000 { return Ok(()); }

    // 削除対象（古い側 = entries.len() - 3000 件）から重要エントリを救済
    let to_remove = &entries[..entries.len() - 3000];
    for entry in to_remove {
        if looks_important(entry) && !already_in_memory_events(entry, base_dir) {
            salvage_to_memory_events(entry, base_dir, project_id)?;
        }
    }

    // 通常圧縮（3000件に切り詰め）
    truncate_to(base_dir, 3000)?;
    Ok(())
}

/// キーワード辞書によるヒューリスティクス重要度判定
fn looks_important(entry: &UnifiedMessage) -> bool {
    // 名前・日付・約束・感情語・将来参照のキーワードマッチ
    // salience >= 0.2 相当の基準
    // source == User のみ対象（Anima応答は memory_events 経由で既に記録済み）
}

/// memory_events に同一テキスト・同一タイムスタンプのイベントが存在するか
fn already_in_memory_events(entry: &UnifiedMessage, base_dir: &Path) -> bool {
    // raw_text の部分一致 + created_at の時刻近傍検索
}
```

目的: oribis-meta が欠落した会話（LLMが未出力 or Rust fallback でも salience < 0.2 だった場合）を、圧縮時に最終救済する。

Phase 3以降（予定）:
- 重要エントリのマーキング・保護
- セッション単位での圧縮
- バッチ蒸留による記憶への昇格

---

## 3. タスク管理（§11）

### 3.1 設計判断

- タスクはプロジェクト単位で管理（ユーザー全体ではない）
- LLMのマーカー指示のみで操作（手動APIなし）
- 進行中タスクは毎ターンL3に注入してLLMに可視化

### 3.2 Task 型

```rust
pub struct Task {
    pub id: String,           // UUID v4
    pub title: String,        // タスクタイトル
    pub status: TaskStatus,   // ステータス
    pub project_id: String,   // プロジェクトID
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
```

### 3.3 TaskStatus / TaskOperation 列挙型

```rust
pub enum TaskStatus {
    Pending,      // 未着手
    InProgress,   // 進行中
    Completed,    // 完了
}

pub enum TaskOperation {
    Add { title: String, status: TaskStatus },
    Update { title: String, status: TaskStatus },
    Complete { title: String },
    Remove { title: String },
}
```

### 3.4 TASK マーカー仕様

```
[TASK:add:タイトル:pending]
[TASK:add:タイトル:in_progress]
[TASK:update:タイトル:completed]
[TASK:complete:タイトル]
[TASK:remove:タイトル]
```

status 文字列: `pending` → Pending, `in_progress` → InProgress, `completed` → Completed, 不明 → Pending

### 3.5 ストレージ

**保存先**: `~/.config/oribis/projects/{project_id}/tasks.json`

```json
{
  "tasks": [
    {
      "id": "uuid1",
      "title": "循環参照バグ修正",
      "status": "in_progress",
      "project_id": "my-project",
      "created_at": "2026-04-26T14:30:00Z",
      "updated_at": "2026-04-26T14:31:00Z"
    }
  ]
}
```

### 3.6 API

```rust
// タスク操作実行（複数まとめて）
pub fn execute_task_operations(
    project_id: &str,
    ops: Vec<TaskOperation>,
) -> Result<()>

// タスク一覧取得
pub fn list_tasks(project_id: &str) -> Result<Vec<Task>>

// 進行中タスク取得（L3注入用）
pub fn list_active_tasks(project_id: &str) -> Result<Vec<Task>>
```

### 3.7 L3注入フォーマット

毎ターン注入（pending + in_progress のみ）:

```
[進行中タスク]
- [in_progress] AFDバグ修正
- [pending] テスト追加
```

完了タスクは注入しない（コンテキスト節約）。

### 3.8 UI連携

フロントエンド側タスク表示の仕様:

- pending / in_progress / completed を色分け表示
- LLM由来（マーカー経由）と将来的なユーザー手動追加を区別表示
- タスク一覧は Tauri コマンド経由で取得（`list_tasks(project_id)`）

### 3.9 Claude Code TodoWrite との関係

Claude CLI 使用時に TodoWrite ツールが使われる場合がある:

- 推奨: `[TASK:...]` マーカー統一（CLI非依存原則）
- TodoWrite は CLI固有機能 → Adapter内で透過処理（マーカーに変換は不要、LLMがマーカー使用するよう L1 で指示済み）
- TodoWrite結果の取り込みは Phase 2以降の検討事項

---

## 4. 実装場所

- `src-tauri/src/character/history.rs` — 履歴API
- `src-tauri/src/character/task.rs` — タスクAPI
- `src-tauri/src/character/parser.rs` — TASKマーカー解析
- `src-tauri/src/character/pipeline.rs` — 履歴追記・圧縮・`execute_task_operations()` 呼出
- `src-tauri/src/character/context.rs` — L3注入（履歴・タスク）

---

## 5. 関連ドキュメント

- `spec-markers.md` — TASKマーカー仕様
- `spec-prompt-layers.md` — L3注入フォーマット全体
- `spec-pipeline.md` — パイプライン内での処理位置
- `spec-memory.md` — バッチ蒸留（履歴→記憶昇格）
- `architecture-diagrams.md` §10 — タスク管理フロー図

*作成日: 2026-04-28*
