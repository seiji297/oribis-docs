# 好感度システム 設計書

**バージョン**: 1.0（anima-spec.md §7 + architecture-diagrams.md §7 より分割）
**最終更新**: 2026-04-28

---

## 1. 概要

Animaがプロデューサーに対して持つ長期的関係性パラメータ。

### 不変原則

- **業務品質に影響しない** — コード・技術回答は好感度無関係で常に最高品質
- **時間経過での自然減衰なし**
- **プロジェクト別管理なし** — ユーザー全体で1つの好感度
- 影響するのは雑談トーン・軽口頻度・自発発話・呼びかけ親密度・演出のみ

---

## 2. パラメータ定義

| 項目 | 値 |
|------|---|
| 型 | `i16`（内部演算） |
| 範囲 | 0 〜 100 |
| 初期値 | 50（Neutral相当） |
| 1イベント最大変動 | ±5 |
| 上限クリップ | 0 / 100 |

---

## 3. Tier（段階）

| Tier | 範囲 | 説明 |
|------|------|------|
| Intimate | 90 〜 100 | 親しみ・気遣い・軽口 |
| Close | 75 〜 89 | 標準敬語・自然な雑談 |
| Warm | 60 〜 74 | 標準（少し積極的） |
| Neutral | 40 〜 59 | 標準・淡々（初期値50はここ） |
| Cold | 20 〜 39 | やや事務的・距離感 |
| Hostile | 0 〜 19 | 拒絶的・用件のみ |

---

## 4. 上昇イベント

- 適切な休憩取得
- 早朝作業（5〜9時）
- 礼儀正しい言葉遣い
- 感謝・労いの言葉
- 長期継続稼働

---

## 5. 下降イベント

- 徹夜・連続長時間作業
- 不適切行動（パンツ視線等）
- 業務集中時の過度な雑談強要
- 暴言・無礼な言葉遣い
- 命令的・高圧的な物言い

---

## 6. データ構造

`~/.config/oribis/anima/affinity.json`:

```json
{
  "value": 63,
  "history": [
    {
      "ts": "2026-04-26T14:30:00Z",
      "delta": 1,
      "event": "early_morning_work",
      "before": 62,
      "after": 63
    }
  ]
}
```

### 6.1 history 保持ポリシー

| 項目 | 値 |
|------|---|
| 上限 | 500件 |
| 超過時 | 古いものから削除（apply_delta_at() 内で実行） |

```rust
// apply_delta_at() 内、append後
if state.history.len() > 500 {
    state.history.drain(0..state.history.len() - 500);
}
```

理由: affinity.json は毎ターン読み込み対象（data-storage.md §4）。無制限成長を許容すると読み書きコストが増加する。他ストア（history.jsonl: 5000件、event_counters.recent_dates: 100件、anima_utterance_log: 100行/7日）は全て上限ありのため、整合性を確保する。

---

## 7. Rust API

```rust
// 好感度読込
pub fn load_affinity_at(base_dir: &Path) -> Result<AffinityState>

// 好感度更新（delta: -5〜+5）
// 戻り値: (新しい値, clamp適用フラグ)
pub fn apply_delta_at(base_dir: &Path, delta: i8) -> Result<(i32, bool)>

// AffinityState
pub struct AffinityState {
    pub value: i32,
    pub history: Vec<AffinityEvent>,
}

impl AffinityState {
    pub fn tier(&self) -> AffinityTier { ... }
}
```

---

## 8. AffinityTier 列挙型

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

cache モジュールにも同名enumがあるため変換が必要:

```rust
fn to_cache_tier(tier: affinity::AffinityTier) -> cache::AffinityTier { ... }
```

（実装: `src-tauri/src/character/pipeline.rs`）

---

## 9. L3注入フォーマット

毎ターン注入:

```
[好感度: +63（良好）]
```

tier別ラベル:
- Intimate: 「非常に良好」
- Close: 「良好」
- Warm: 「普通」
- Neutral: 「事務的」
- Cold: 「冷淡」
- Hostile: 「拒絶的」

---

## 10. 実装場所

- `src-tauri/src/character/affinity.rs` — 読込・更新・Tier判定
- `src-tauri/src/character/pipeline.rs` — `apply_delta_at()` 呼出（後処理）
- `src-tauri/src/character/context.rs` — L3注入（`build_context_at()`内）

---

## 11. 関連ドキュメント

- `spec-prompt-layers.md` — L3注入フォーマット全体
- `spec-markers.md` — AFFINITY マーカー仕様
- `spec-anima-mode.md` — Tier × AnimaCategory のキャッシュマトリクス
- `architecture-diagrams.md` §7 — 好感度更新フロー図
- `expression-system.md` — フロントエンドでの好感度→表情マッピング

*作成日: 2026-04-28*
