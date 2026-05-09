# マーカー方式 設計書

**バージョン**: 1.0（anima-spec.md §6 + architecture-diagrams.md §6 より分割）
**最終更新**: 2026-04-28

---

## 1. 概要

LLM応答末尾に付与するメタ情報タグ。CLI非依存で動作する統一プロトコル。

### 設計原則

- マーカーは**応答末尾**に配置
- CLI固有機能（TodoWrite等）には依存しない
- スクリプト側がマーカーをパースして副作用を実行

---

## 2. マーカー一覧

### 2.1 AFFINITY（必須・全応答）

```
[AFFINITY:N]
```

- N: -5〜+5 の整数
- **全応答末尾に必須**（省略不可）
- 変動なし時は `[AFFINITY:0]`

### 2.2 ANIMA（アバター制御）

```
[ANIMA:expression=<名前>,intensity=<0.0-1.0>,motion=<名前>,gaze=<方向>]
```

| フィールド | 型 | 省略 | 説明 |
|-----------|---|------|------|
| expression | string | 可 | 表情名（happy/sad/angry/surprised/relaxed/neutral） |
| intensity | float | 可（省略時1.0） | 表情強度 0.0〜1.0 |
| motion | string | 可 | モーション名 |
| gaze | string | 可 | 視線方向（forward/down/up/left/right） |

### 2.3 TASK（タスク操作）

```
[TASK:add:タイトル:status]
[TASK:update:タイトル:status]
[TASK:complete:タイトル]
[TASK:remove:タイトル]
```

status: `pending` | `in_progress` | `completed`

複数タスク操作時は複数マーカーを並べる。

### 2.4 MEMORY_SAVE（記憶保存）

```
[MEMORY_SAVE:category=<キー>|<内容>]
```

カテゴリ:
- `food` — 食べ物・飲み物
- `person` — 人物・関係
- `event` — 出来事
- `preference` — 好み・趣味
- `schedule` — 習慣・スケジュール
- `health` — 健康・体調
- `work` — 業務・プロジェクト
- `other` — その他

ルール:
- 1エントリ1マーカー
- 「覚えて」明示 or 重要な個人情報検知時に出力
- 同一(category+内容)の重複出力禁止

### 2.5 MEMORY_QUERY（記憶検索）

```
[MEMORY_QUERY:検索語]
```

- 過去情報参照が必要な時に出力
- 検索結果は次ターンのL3に `[記憶検索結果]` として注入
- 1ターンに複数可

---

## 3. 応答フォーマット例

```
なるほど、そのバグ直しましょう。循環参照が原因かと。
DI挟めば解決できます。

[AFFINITY:1]
[TASK:add:循環参照バグ修正:in_progress]
[MEMORY_SAVE:category=work|循環参照バグ発見 2026-04-28]
```

---

## 4. パーサー仕様

### 4.1 パース対象

`parse_response(raw_text)` の出力:

```rust
pub struct ParsedResponse {
    pub display_text: String,        // マーカー除去後の表示テキスト
    pub affinity_delta: i8,          // AFFINITY値（デフォルト0）
    pub anima_control: Option<AnimaControl>, // ANIMAマーカー内容
    pub task_operations: Vec<TaskOperation>, // TASKマーカー操作一覧
    pub memory_saves: Vec<MemorySaveItem>,   // MEMORY_SAVEマーカー一覧
    pub memory_queries: Vec<String>,         // MEMORY_QUERYマーカー検索語
}
```

### 4.2 パース規則

- マーカーは応答末尾に出現（本文中には出現しない前提）
- `[AFFINITY:N]` — 正規表現 `\[AFFINITY:(-?\d+)\]`
- `[ANIMA:...]` — `\[ANIMA:([^\]]+)\]`、内部をカンマ分割してキー=値解析
- `[TASK:...]` — `\[TASK:(\w+):([^:\]]+)(?::(\w+))?\]`
- `[MEMORY_SAVE:...]` — `\[MEMORY_SAVE:category=(\w+)\|([^\]]+)\]`
- `[MEMORY_QUERY:...]` — `\[MEMORY_QUERY:([^\]]+)\]`

### 4.3 display_text 生成

全マーカーを取り除いたテキスト。末尾の空行も除去。

---

## 5. ストリーミング時の処理

バッファリング戦略:
1. `[` を検知 → バッファ開始
2. `]` で閉じる → バッファ内容をマーカー候補として評価
3. マーカーでなければバッファをdisplay_textに追加して継続

**推奨**: マーカー解析はストリーミング完了後に `RawResponse.text` からまとめて実施。ストリーミング中は全テキストをUIへ流し、完了後にマーカー解析+副作用実行。

---

## 6. 実装場所

- `src-tauri/src/character/parser.rs` — `parse_response()`

---

## 7. 関連ドキュメント

- `spec-pipeline.md` — パイプライン内でのマーカー処理位置
- `spec-affinity.md` — AFFINITY処理詳細
- `spec-tasks.md` — TASK処理詳細
- `spec-memory.md` — MEMORY_SAVE/MEMORY_QUERY処理詳細
- `architecture-diagrams.md` §6 — マーカー処理フロー図

*作成日: 2026-04-28*
