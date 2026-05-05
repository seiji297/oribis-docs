# 記憶システム 設計書

**バージョン**: 2.0（spec-memory.md + spec-session-journal.md + spec-batch-distillation.md 統合）
**最終更新**: 2026-04-28

---

## 1. 概要

3層記憶アーキテクチャ:

```
[即時層]   セッションジャーナル — 発話ログ。揮発性（rolling 50件/7日）
[統計層]   イベントカウンタ    — 行動パターン。永続（→ spec-event-counter.md）
[印象層]   永続記憶           — 重要な個人情報・出来事
```

各層の役割:
- **ジャーナル**: チャット↔Anima橋渡し、短期文脈参照
- **カウンタ**: 慣れ化・パターン検出
- **記憶**: 長期的な個人理解

LLM判断または人間指示で保存される長期記憶システム。セッション間で永続し、関連情報をL3注入で再利用する。

---

## 2. Memory 型

```rust
pub struct Memory {
    pub id: String,                 // UUID v4
    pub content: String,            // 記憶内容
    pub category: Option<String>,   // カテゴリ
    pub source: MemorySource,       // 保存源
    pub created_at: DateTime<Utc>,
    pub access_count: u32,          // 参照回数
    pub last_accessed: Option<DateTime<Utc>>,
}

pub enum MemorySource {
    HumanInstruction,  // 人間が「覚えて」と指示
    AIDetected,        // LLMが重要と判断して保存
}
```

---

## 3. ストレージ（永続記憶）

**保存先**: `~/.config/oribis/nagiko/memories.json`（ユーザー全体共通）

```json
{
  "memories": [
    {
      "id": "uuid1",
      "content": "緑茶好き",
      "category": "food",
      "source": "AIDetected",
      "created_at": "2026-04-26T14:30:00Z",
      "access_count": 3,
      "last_accessed": "2026-04-28T09:00:00Z"
    }
  ]
}
```

---

## 4. サイズ制限と削除戦略

| 項目 | 値 |
|------|---|
| 上限 | 500件 |
| HumanInstruction | 永続保護（自動削除対象外） |
| AIDetected超過時 | access_count 昇順で削除 |

---

## 5. MEMORY_SAVE マーカーフロー

```
LLMがMEMORY_SAVEマーカー出力
  ↓
parse_response() → ParsedResponse.memory_saves
  ↓
memory_save_with_category(value, category, AIDetected)
  ↓
memories.json に追記
```

---

## 6. MEMORY_QUERY → 次ターンL3注入フロー

```
LLMがMEMORY_QUERYマーカー出力
  ↓
parse_response() → ParsedResponse.memory_queries
  ↓
memory_search(query, limit=5) → Vec<Memory>
  ↓
push_pending_memory_results(results)  ← メモリに一時保持
  ↓
[次ターン]
build_context_at() → pending results をL3に注入
  ↓
[記憶検索結果]
- 緑茶好き
- 夜型人間
```

---

## 7. API（永続記憶）

```rust
pub fn memory_save_with_category(
    value: &str,
    category: Option<&str>,
    source: MemorySource,
) -> Result<Memory>

pub fn memory_search(query: &str, limit: usize) -> Result<Vec<Memory>>

pub fn push_pending_memory_results(results: Vec<Memory>)

pub fn pop_pending_memory_results() -> Vec<Memory>  // build_context_at()内で呼出
```

---

## 8. Animaパイプラインの memory_saves gap

現状 `execute_anima_pipeline()` には記憶保存処理が未接続。

修正方針: Animaパイプラインでも `parsed.memory_saves` を処理する。

```rust
// execute_anima_pipeline内に追加
for item in &parsed.memory_saves {
    let _ = memory::memory_save_with_category(
        &item.value,
        item.category.as_deref(),
        memory::MemorySource::AIDetected,
    );
}
```

---

## 9. セッションジャーナル（即時層）

### 9.1 概要

チャット↔Anima橋渡しのための短期ログ。Animaが「自分が何を言ったか」を参照できるようにする（B-plan）。

### 9.2 保存先・フォーマット

**保存先**: `~/.config/oribis/nagiko/session_journal.txt`

**1エントリのフォーマット**:
```
{HH:MM} {category} → "{phrase}"
```

**例**:
```
14:30 greeting → "おはようございます。今日もよろしくお願いします。"
14:35 working → "作業中ですね。何かあれば声をかけてください。"
15:45 error → "エラーが出てますね。確認しますか。"
```

### 9.3 ローリング仕様

| 項目 | 値 |
|------|---|
| 最大エントリ数 | 50件 |
| 最大保持期間 | 7日 |
| 超過時の処理 | 古いエントリから削除（どちらかの条件を超えたら） |

### 9.4 書き込みタイミング

Animaフレーズが生成・返却された直後（`execute_anima_pipeline()` の後処理）:

```rust
// CacheHit または Generated 時に追記
journal::append_entry(category, phrase, base_dir)?;
```

### 9.5 L3注入フォーマット（Phase 2以降）

Phase 2 から毎ターン注入（直近10件程度、トークン節約）:

```
[セッションジャーナル]
14:30 greeting → "おはようございます。"
15:45 error → "エラーが出てますね。確認しますか。"
```

### 9.6 設計判断（B-plan 採用理由）

A-plan（Animaパイプラインに独立Claudeセッション）は実装複雑度が高く、Phase 1スコープ外。

B-plan（ジャーナルファイルによる橋渡し）:
- Rust のみで完結
- セッション構造変更不要
- Phase 2でA-planへの移行も可能

---

## 10. バッチ記憶蒸留（Phase 3）

### 10.1 概要

アイドル時にカウンタ+ジャーナルをLLMに渡し、記憶として昇格させるバッチ処理。

### 10.2 蒸留フロー

```
IdleLong イベント発火
  ↓（蒸留条件チェック）
変動カウンタ あり or ジャーナル未処理エントリ あり
  ↓ true
LLMに渡すコンテキスト構築:
  - 変動したカウンタ一覧（recent_7d > 0）
  - セッションジャーナル（未処理エントリ）
  ↓
LLM呼出（特定プロンプト）
  ↓
LLMが MEMORY_SAVE マーカーで出力
  ↓
memory_save_with_category() → memories.json
  ↓
batch_state.json 更新（処理済みマーク）
```

### 10.3 蒸留条件

| 条件 | 値 |
|------|---|
| 前回蒸留からの最小間隔 | 1時間 |
| 変動カウンタ有無 | 7日以内に変動 |
| ジャーナル未処理エントリ | 1件以上 |

どちらかの条件を満たせば実行。

### 10.4 状態管理

**保存先**: `~/.config/oribis/nagiko/batch_state.json`

```json
{
  "last_distillation": "2026-04-26T14:00:00Z",
  "last_processed_journal_index": 42
}
```

### 10.5 LLMへのプロンプト構造

```
[システム]
あなたはNagikoの記憶システムです。
以下の行動データとジャーナルから、長期記憶として保存すべき情報を抽出してください。
重複・自明な情報は除外し、重要な個人情報・パターン・出来事のみ保存してください。

[行動データ]
- lewd: 直近7日 3回（stage2相当）
- all_nighter: 直近7日 2回

[ジャーナル]
14:30 greeting → "おはようございます。"
...

[指示]
MEMORY_SAVEマーカーで出力してください。
```

---

## 11. 実装場所

- `src-tauri/src/character/memory.rs` — 永続記憶 全API
- `src-tauri/src/character/journal.rs` — `append_entry()` / `read_recent()` **（未実装・Phase 1後半）**
- `src-tauri/src/character/distillation.rs` — バッチ蒸留ロジック **（未実装・Phase 3）**
- `src-tauri/src/character/pipeline.rs` — 記憶保存・検索後処理、ジャーナル書込
- `src-tauri/src/character/context.rs` — pending results のL3注入、ジャーナルL3注入（Phase 2）

---

## 12. 関連ドキュメント

- `spec-markers.md` — MEMORY_SAVE/MEMORY_QUERY マーカー仕様
- `spec-event-counter.md` — 統計層（イベントカウンタ）
- `spec-anima.md` — IdleLong トリガー元（蒸留起点）
- `spec-prompt-layers.md` — L3条件付き注入仕様
- `architecture-diagrams.md` §8 — 記憶システムフロー図

*作成日: 2026-04-28*
