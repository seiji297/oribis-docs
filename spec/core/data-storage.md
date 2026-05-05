# データストレージ設計書

**バージョン**: 1.0（architecture-diagrams.md §1/§5 + anima-spec.md §19/§20 より分割）
**最終更新**: 2026-04-28

---

## 1. ストレージ全体マップ

### ユーザー全体共通（ユーザーグローバル）

`~/.config/oribis/anima/`

| ファイル | 内容 | 担当モジュール |
|---------|------|--------------|
| `affinity.json` | 好感度・変動履歴 | `affinity.rs` |
| `memory.db` | 記憶システム（SQLite: events/memories/open_loops/relationship_model） | `memory_db.rs` |
| `memories.json` | **レガシー**（マイグレーション後 `.bak` にリネーム） | `memory.rs` |
| `event_counters.json` | イベントカウンタ（9カテゴリ） | `counter.rs` |
| `throttle_state.json` | throttle最終発火時刻 | `throttle.rs` |
| `anima_mode.toml` | AnimaMode設定 | `cache.rs` |
| `throttle.toml` | throttle設定 | `throttle.rs` |
| `cache/` | Animaキャッシュ（78ファイル） | `cache.rs` |

### プロジェクト別

`~/.config/oribis/projects/{project_id}/`

| ファイル | 内容 | 担当モジュール |
|---------|------|--------------|
| `tasks.json` | タスク一覧 | `task.rs` |
| `history.jsonl` | 統合履歴（プロジェクト別・5000件上限） | `history.rs` |
| `.last_session_id` | Claude CLIセッションID永続化（アプリ再起動後の継続用） | Tauri commands（`lib.rs`） |
| `.last_codex_thread_id` | Codex CLIスレッドID永続化（アプリ再起動後の継続用） | Tauri commands（`lib.rs`） |

### プロジェクト内（将来）

`{project_path}/.claude/CLAUDE.md` — プロジェクト固有L1上書き

---

## 2. キャッシュディレクトリ構造

```
~/.config/oribis/anima/cache/
  idle/
    warm.json
    close.json
    intimate.json
    neutral.json
    cold.json
    hostile.json
  idle_long/
    warm.json
    ...（6ファイル）
  working/  ...
  done/     ...
  error/    ...
  greeting/ ...
  resume/   ...
  lewd/     ...
  tool_bash/    ...
  tool_edit/    ...
  tool_search/  ...
  tool_read/    ...
  tool_write/   ...
```

13ディレクトリ × 6ファイル = 78ファイル

---

## 3. base_dir

全ファイルパスは `base_dir` からの相対。

本番: `base_dir = ~/.config/oribis/anima/`
テスト: `base_dir = /tmp/test-{uuid}/`（テスト毎に一時ディレクトリ）

---

## 4. ファイルアクセスパターン

| 操作頻度 | ファイル |
|---------|---------|
| 毎ターン読込 | `affinity.json`, `event_counters.json`, `memory.db`（L3検索） |
| 毎ターン書込 | `history.jsonl`（追記）, `memory.db`（イベント記録） |
| 応答後書込 | `affinity.json`（delta時のみ）, `memory.db`（MEMORY_SAVE時） |
| Anima発火時 | `throttle_state.json`, `cache/*.json` |
| セッション開始 | `history.jsonl`（30件読込）, `memory.db`（未処理consolidation） |
| アプリ終了時 | `memory.db`（Level 1 consolidation） |

---

## 5. パフォーマンス目標（§19/§20）

### 5.1 レイテンシ目標（§20.1）

| 処理 | 目標 |
|------|------|
| メインチャット応答（既存維持） | 既存と同等 |
| Anima AI応答 | < 2秒 |
| Anima Cache応答 | < 50ms |
| 履歴アクセス | < 100ms |
| 好感度更新 | < 10ms |
| 記憶検索 | < 200ms |
| イベントカウンタ取得 | < 10ms |

### 5.2 ファイルIOパフォーマンス（§19）

| 指標 | 目標値 |
|------|--------|
| チャット応答遅延（ファイルIO除く） | < 10ms |
| キャッシュ検索 | < 1ms |
| 履歴読込（30件） | < 5ms |
| 記憶検索（全件） | < 20ms |

### 5.3 トークン消費目標（§20.2）

| 項目 | 値 |
|------|---|
| L1 サイズ | 〜2000トークン |
| L2 サイズ | 〜100トークン |
| L3 サイズ（通常時） | 〜130トークン |
| L3 サイズ（全チャネル活性時） | 〜170トークン（hard cap） |
| 履歴注入（セッション開始時） | 〜1500トークン |
| L1キャッシュ後の実コスト | 1/10程度 |

### 5.4 コスト目標（§20.3）

- 1日運用で $1以下
- 月間 $10〜$30 範囲

---

## 6. ログ・メトリクス（§20）

### ログ出力先

`~/.config/oribis/anima/anima.log`（ローテーション: 10MB × 5世代）

### ログレベル

| レベル | 内容 |
|--------|------|
| INFO | LLM呼出、好感度変動、記憶保存 |
| WARN | throttle抑制、キャッシュミス |
| ERROR | LLM呼出失敗、ファイルIO失敗 |
| DEBUG | パーサー詳細、コンテキスト構築内容 |

### デバッグ機能（§19.3）

- 入力 → 応答 のトレース
- 好感度の手動設定・履歴閲覧
- 発火制御のドライラン
- L1/L2/L3 個別の内容確認
- キャッシュ手動再生成
- 記憶エントリ閲覧・編集
- カウンタリセット

### ログ出力詳細（§19.1）

INFO レベルの主な出力項目:
- LLM呼出時間（ms）
- 好感度変動（delta値・変動後の値）
- 記憶保存（category・content）
- タスク操作（add/update/complete/remove）
- イベントカウンタ更新（category・累計値）
- Anima発話（category・発火 or 抑制）

WARN レベル:
- throttle抑制（category・最終発火からの経過時間）
- キャッシュミス（category・tier）
- フォールバック発生（理由）
- マーカーパース失敗（raw text）

ERROR レベル:
- LLM呼出失敗（backend・エラー内容）
- ファイルIO失敗（path・操作）

### メトリクス収集（将来）

- LLMコール回数・コスト
- AI / Cache / Hybrid モード使用比率（カテゴリ別）
- キャッシュヒット率（カテゴリ別）
- 平均応答時間（AI vs Cache）
- フォールバック発生率
- 好感度トレンド
- 履歴サイズ推移
- 記憶エントリ数・アクセス頻度
- イベントカウンタ集計（直近7日）

---

## 7. 実装場所

- 全モジュールの `*_at(base_dir, ...)` API — パス構築含む
- `src-tauri/src/character/mod.rs` — `base_dir` の初期化

---

## 8. db.rs — ストレージユーティリティ

全Animaモジュールが共用するファイルIO基盤。

### 8.1 パス管理

```rust
// ~/.config/oribis/anima/ 作成・取得
pub fn ensure_character_dir() -> Result<PathBuf>

// ~/.config/oribis/projects/{project_id}/ 作成・取得
// project_id バリデーション込み（英数字・ハイフン・アンダースコア・ドットのみ）
pub fn ensure_project_dir(project_id: &str) -> Result<PathBuf>
```

テスト時は環境変数 `ANIMA_TEST_CONFIG_DIR` でベースパス上書き可能。

### 8.2 JSON I/O

```rust
// アトミック書き込み（tempfile + rename）
pub fn atomic_write_json<T: Serialize>(path: &Path, data: &T) -> Result<()>

// 読み込み（ファイルなし or 破損 → Default返却）
pub fn load_json_or_default<T: DeserializeOwned + Default>(path: &Path) -> Result<T>
```

`atomic_write_json` は tempfile → rename でクラッシュ安全。Windows fallback あり（copy + remove）。

### 8.3 project_id バリデーション

ホワイトリスト方式:
- 英数字 / ハイフン / アンダースコア / ドットのみ許可
- ドット始まり不可（`.hidden` 等）
- パストラバーサル（`../`、`/`、`\`）不可
- 空文字不可

---

## 9. Phase 3: JSON → SQLite 段階統合計画

### 9.1 背景

memory.db（SQLite）導入済みだが、affinity/counters/tasks/throttle は個別JSONファイルのまま。
耐久性セマンティクスの不統一（JSON: atomic_write_json vs SQLite: トランザクション）と毎ターン多ファイルIOが課題。

### 9.2 統合対象

| 現行ファイル | → テーブル | 備考 |
|------------|----------|------|
| `affinity.json` | `affinity_state` + `affinity_history` | history は500件上限（affinity.md §6.1） |
| `event_counters.json` | `event_counters` | recent_dates は JSON列 |
| `throttle_state.json` | `throttle_state` | key-value（カテゴリ→最終発火時刻） |
| `tasks.json` | `tasks` | project_id 列でプロジェクト分離 |

### 9.3 メリット

- 1 DB接続で全ホット状態を取得（毎ターン IO 削減）
- トランザクション保証（partial write リスク解消）
- リカバリ・デバッグ時に1ファイル（memory.db）で全状態確認可
- VACUUM / WAL mode で統一的なパフォーマンス制御

### 9.4 マイグレーション戦略

```rust
pub fn migrate_json_stores_to_db(base_dir: &Path) -> Result<()> {
    // 各 JSON ファイルが存在する場合のみ実行
    // 1. affinity.json → affinity_state + affinity_history テーブル
    // 2. event_counters.json → event_counters テーブル
    // 3. throttle_state.json → throttle_state テーブル
    // 4. tasks.json → tasks テーブル（全プロジェクト統合）
    // 完了後: 旧ファイルを .bak にリネーム（memories.json と同じパターン）
}
```

### 9.5 統合しないもの

| ファイル | 理由 |
|---------|------|
| `history.jsonl` | プロジェクト別・JSONL追記特化。SQLite化のメリットが薄い |
| `cache/*.json` | 読み取り専用の静的ファイル。DB化不要 |
| `anima_mode.toml` / `throttle.toml` | ユーザー編集可能な設定ファイル。DB化は不適切 |
| `.last_session_id` / `.last_codex_thread_id` | 単一値ファイル。DB化のオーバーヘッドが大きい |

---

## 10. 関連ドキュメント

- 各 `spec-*.md` — 個別ファイルの詳細仕様
- `architecture-diagrams.md` §1 — 全体アーキテクチャ図
- `architecture-diagrams.md` §5 — データ管理スコープ図

*作成日: 2026-04-28 / 改訂: 2026-05-06*
