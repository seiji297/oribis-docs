# Anima統合システム 設計書

**バージョン**: 2.0（spec-anima.md + spec-anima-mode.md + spec-throttle.md + spec-smart-cache.md 統合）
**最終更新**: 2026-04-28

---

## 1. 概要

内部状態変化に応じてAnimaが自発的に発話・アバター制御を行うシステム。

### 設計判断

- メインチャットと**完全分離しない**（統一パイプライン採用）
- Anima応答は `InputEvent::AnimaState` として統一パイプラインへ入力
- throttle・キャッシュ・AI生成を統一的に処理

### Cacheモードの限界（MemoryFix §1.2・重要認識）

**CacheモードではAI応答は原理的に実現不可能。**
- `build_context_at` が呼ばれない → カウンタ・ジャーナル・メモリ全て無効
- 静的文字列を返すだけ。深夜だろうと徹夜3日目だろうと同じフレーズ
- カウンタ・ジャーナル・メモリの実装はAIモード移行後に初めて機能する

### 実装優先順序（MemoryFix §1.3）

1. **AnimaMode::Ai 移行**（最優先・これがなければ何も意味ない）
2. カウンタ処理 + セッションジャーナル
3. システムプロンプト改善（パターン言及指示）
4. Animaパイプライン記憶連携

---

## 2. AnimaCategory 列挙型

```rust
pub enum AnimaCategory {
    Idle,         // アイドル（短時間）
    IdleLong,     // アイドル（長時間）
    Working,      // 作業中
    Done,         // 作業完了
    Error,        // エラー発生
    Greeting,     // 挨拶
    Resume,       // セッション再開
    Lewd,         // 不適切行動検知
    ToolBash,     // Bashツール実行
    ToolEdit,     // Editツール実行
    ToolSearch,   // 検索ツール実行
    ToolRead,     // Readツール実行
    ToolWrite,    // Writeツール実行
}
```

計13カテゴリ。

---

## 3. Anima通知書式

テキスト入力からAnimaStateへの変換:

```
[システム通知: idle]      → AnimaCategory::Idle
[システム通知:working]    → AnimaCategory::Working（スペース有無どちらでも可）
[システム通知: tool_bash] → AnimaCategory::ToolBash
```

変換関数: `parse_anima_notification(text: &str) -> Option<AnimaCategory>`

---

## 4. AnimaControl 型

LLMが `[ANIMA:...]` マーカーで出力するアバター制御指示:

```rust
pub struct AnimaControl {
    pub expression: Option<String>,  // 表情名
    pub intensity: Option<f32>,      // 強度 0.0〜1.0
    pub motion: Option<String>,      // モーション名
    pub gaze: Option<String>,        // 視線方向
}
```

---

## 5. Animaパイプライン処理

```
AnimaState受信
  ↓
throttle::should_speak_at() — 60秒デフォルト
  ↓ false → Suppressed
  ↓ true
load_affinity_at() → tier
  ↓
AnimaMode確認（anima_mode.toml）
  ↓ Cache → キャッシュ検索 → CacheHit
  ↓ Ai    → AI生成（キャッシュスキップ）
  ↓ Hybrid → キャッシュあり→CacheHit / なし→AI生成
  ↓
[AI生成の場合]
build_context_at() → Prompt
adapter.send_message()
parse_response()
→ Generated { text, anima_control, ... }
```

---

## 6. AnimaMode（AI/Cache/Hybrid）

### 6.1 モード概要

| モード | 動作 | 用途 |
|--------|------|------|
| Cache | キャッシュのみ。AI呼出なし | 低コスト・高速 |
| Ai | AI生成のみ。キャッシュ不使用 | 高品質・自然な応答 |
| Hybrid | キャッシュあり→CacheHit、なし→AI生成 | バランス（デフォルト） |

### 6.2 AnimaMode 列挙型

```rust
pub enum AnimaMode {
    Cache,
    Ai,
    Hybrid,
}
```

`PipelineConfig` に `anima_mode: AnimaMode` フィールドとして追加。

### 6.3 設定ファイル

**保存先**: `~/.config/oribis/nagiko/anima_mode.toml`

```toml
# グローバルデフォルト
default = "Hybrid"

# カテゴリ別上書き（省略時はdefault使用）
[categories]
idle = "Cache"
idle_long = "Cache"
greeting = "Ai"
lewd = "Ai"
done = "Hybrid"
error = "Hybrid"
```

### 6.4 キャッシュ構造

13カテゴリ × 6Tier = **78ファイル**

**保存先**: `~/.config/oribis/nagiko/cache/{category}/{tier}.json`

例: `cache/idle/warm.json`, `cache/error/hostile.json`

Tier: `intimate` / `close` / `warm` / `neutral` / `cold` / `hostile`

```rust
pub enum AffinityTier {
    Intimate,
    Close,
    Warm,
    Neutral,
    Cold,
    Hostile,
}
```

cache モジュール内の `AffinityTier` は affinity モジュールの同名型とは別（変換必要）。

### 6.5 キャッシュ選択ロジック

```rust
pub fn extract_with_fallback(
    category: AnimaCategory,
    tier: AffinityTier,
    sub_context_key: Option<&str>,
) -> (Phrase, Mode)
```

1. `sub_context_key` が Some → sub_contexts から選択
2. キャッシュが存在 → phrases からランダム選択
3. キャッシュなし → フォールバック文字列を返す

```rust
pub fn cache_exists(category: AnimaCategory, tier: AffinityTier) -> bool
```

ファイルが存在 かつ phrases が空でない場合に true。

### 6.6 Hybridモードのフロー

```
キャッシュファイル存在確認
  ↓ あり → extract_with_fallback() → CacheHit
  ↓ なし → AI生成（send_message）→ Generated
              ↓
              （オプション）生成フレーズをキャッシュに追記保存
```

### 6.7 段階移行原則

- 初期はAi mode（学習フェーズ）
- 運用しながらカテゴリ別にCache modeへ移行
- 最終的にはCache mode主体（コスト最適化）
- Hybrid modeでスムーズに移行できる

### 6.8 キャッシュ生成

初期キャッシュは LLM で生成。生成プロンプト → `cache-generation-prompts.md`

---

## 7. Throttle（発火制御）

### 7.1 概要

Anima発話の頻度を抑制する機構。同一カテゴリの連続発火を防ぐ。

### 7.2 ThrottleConfig 型

```rust
pub struct ThrottleConfig {
    pub min_interval_secs: u64,           // グローバルデフォルト（60秒）
    pub category_settings: HashMap<String, CategoryThrottle>,
}

pub struct CategoryThrottle {
    pub probability: f64,     // 発火確率 0.0〜1.0（1.0=必ず発火）
    pub cooldown_secs: u64,   // カテゴリ別クールダウン
}
```

### 7.3 カテゴリ別デフォルト設定

| カテゴリ | cooldown_secs | probability |
|---------|--------------|-------------|
| idle | 300 | 0.3 |
| idle_long | 600 | 0.5 |
| working | 120 | 0.4 |
| done | 30 | 1.0 |
| error | 60 | 1.0 |
| greeting | 0 | 1.0 |
| resume | 0 | 1.0 |
| lewd | 30 | 1.0 |
| tool_bash | 60 | 0.2 |
| tool_edit | 60 | 0.2 |
| tool_search | 60 | 0.2 |
| tool_read | 60 | 0.2 |
| tool_write | 60 | 0.2 |

設計判断:
- `greeting` / `resume` はクールダウン0・確率1.0（必ず発火）
- `done` / `error` / `lewd` は確率1.0（重要イベントは確実に反応）
- ツール系は確率0.2（頻繁なツール呼出でも20%のみ反応）

### 7.4 設定ファイル + 状態ファイル

**設定**: `~/.config/oribis/nagiko/throttle.toml`

```toml
min_interval_secs = 60

[categories.idle]
cooldown_secs = 300
probability = 0.3
```

**状態**: `~/.config/oribis/nagiko/throttle_state.json`

```json
{
  "last_fired": {
    "idle": "2026-04-26T14:30:00Z",
    "done": "2026-04-26T14:35:00Z"
  }
}
```

### 7.5 発火判定ロジック

```rust
pub fn should_speak_at(
    config: &ThrottleConfig,
    category: &str,
    base_dir: &Path,
) -> bool
```

判定手順:
1. カテゴリの最終発火時刻を読込（`throttle_state.json`）
2. `cooldown_secs` が未経過 → `false`
3. `probability` チェック（random < probability → `true`）
4. 発火時は最終発火時刻を更新

---

## 8. スマートキャッシュ（sub_contexts）

### 8.1 概要

Animaキャッシュにコンテキスト依存フレーズを追加し、状況に応じた細かいフレーズ選択を実現する拡張機能。

### 8.2 拡張キャッシュフォーマット

```json
{
  "phrases": ["デフォルトフレーズ"],
  "sub_contexts": {
    "lewd_stage1": ["やめてください。"],
    "lewd_stage2": ["…何度言えば。"],
    "lewd_stage3": ["もう話しません。"],
    "greeting_morning": ["おはようございます。"],
    "greeting_late_night": ["まだ起きてたんですか。"],
    "greeting_all_nighter": ["…徹夜ですか。体に気をつけて。"]
  }
}
```

### 8.3 sub_context キー一覧

**lewd カテゴリ**:
- `lewd_stage1` — 1〜2回目
- `lewd_stage2` — 3〜5回目
- `lewd_stage3` — 6回以上

**greeting カテゴリ**:
- `greeting_morning` — 5〜11時
- `greeting_afternoon` — 12〜17時
- `greeting_evening` — 18〜22時
- `greeting_late_night` — 23〜1時
- `greeting_all_nighter` — 2〜4時

**resume カテゴリ**:
- `resume_short` — 離席 < 30分
- `resume_medium` — 離席 30分〜3時間
- `resume_long` — 離席 > 3時間

**error カテゴリ**:
- `error_stage1` — 1回目
- `error_stage2` — 連続2〜3回
- `error_stage3` — 連続4回以上

### 8.4 compute_sub_context ロジック

```rust
pub fn compute_sub_context(
    category: AnimaCategory,
    base_dir: &Path,
) -> Option<String>
```

```
Lewd:
  lewd_total = counter::get("lewd").total
  1〜2 → "lewd_stage1"
  3〜5 → "lewd_stage2"
  6+   → "lewd_stage3"

Greeting:
  hour = Local::now().hour()
  5〜11  → "greeting_morning"
  12〜17 → "greeting_afternoon"
  18〜22 → "greeting_evening"
  23,0,1 → "greeting_late_night"
  2〜4   → "greeting_all_nighter"

Resume:
  elapsed = session_gap_minutes（前回セッション終了からの経過）
  < 30   → "resume_short"
  < 180  → "resume_medium"
  180+   → "resume_long"

Error:
  error_recent = counter::get("error_burst").recent_7d
  1    → "error_stage1"
  2〜3 → "error_stage2"
  4+   → "error_stage3"

その他 → None（デフォルトphrasesを使用）
```

### 8.5 pick_with_context 関数

```rust
pub fn pick_with_context(
    category: AnimaCategory,
    tier: AffinityTier,
    base_dir: &Path,
) -> String
```

1. `compute_sub_context(category, base_dir)` → `key`
2. キャッシュファイル読込
3. `sub_contexts[key]` が存在 → ランダム選択
4. なし → `phrases` からランダム選択
5. どちらもなし → フォールバック文字列

---

## 9. Anima応答の履歴・ジャーナル記録

- Animaが生成したフレーズは `MessageSource::NagikoAnima` として統合履歴に記録
- Animaフレーズはセッションジャーナルにも記録（チャット↔Anima橋渡し、B-plan）

詳細 → `spec-session-data.md`（履歴）、`spec-memory.md` §9（ジャーナル）

---

## 10. 実装場所

- `src-tauri/src/character/anima.rs` — `AnimaCategory`・`parse_anima_notification()`
- `src-tauri/src/character/pipeline.rs` — `execute_anima_pipeline()`・AnimaMode分岐
- `src-tauri/src/character/cache.rs` — キャッシュ読込・選択・`compute_sub_context()`・`pick_with_context()`
- `src-tauri/src/character/throttle.rs` — `should_speak_at()` + 設定読込
- `src-tauri/src/character/parser.rs` — `AnimaControl`・ANIMAマーカー解析
- `~/.config/oribis/nagiko/anima_mode.toml` — モード設定
- `~/.config/oribis/nagiko/throttle.toml` — throttle設定
- `~/.config/oribis/nagiko/cache/` — キャッシュファイル群

---

## 11. 関連ドキュメント

- `spec-pipeline.md` — 統一パイプライン設計
- `spec-event-counter.md` — lewd/error_burst カウンター定義
- `spec-markers.md` — ANIMAマーカー仕様
- `spec-memory.md` — セッションジャーナル（§9）
- `cache-generation-prompts.md` — キャッシュ生成プロンプト
- `architecture-diagrams.md` §11/§13 — AnimaMode切替図・Anima応答シーケンス図

*作成日: 2026-04-28*
