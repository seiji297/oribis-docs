# イベントカウンタ 設計書

**バージョン**: 1.0（nagiko-spec.md §10 + MemoryFix §2/§7 + architecture-diagrams.md §9 より分割）
**最終更新**: 2026-04-28

---

## 1. 概要

特定行動の累積カウントを管理するシステム。好感度とは別に行動パターンを追跡し、Animaのsub_contextや記憶蒸留に利用する。

---

## 2. カテゴリ一覧（MemoryFix §2確定版）

| カテゴリ | トリガー条件 | 説明 |
|---------|------------|------|
| `lewd` | ユーザーが不適切行動（パンツ視線等） | 慣れ化追跡（stage1/2/3） |
| `all_nighter` | 翌2〜5時作業開始 | 徹夜パターン |
| `early_morning` | 5〜9時作業開始 | 早朝パターン |
| `late_night` | 23〜1時作業開始 | 深夜パターン |
| `weekend_work` | 土日に作業 | 休日作業パターン |
| `long_session` | 連続稼働6時間以上 | 長時間作業 |
| `error_burst` | 5分間に3回以上エラー | エラーパターン追跡 |
| `idle_long_count` | idle_longイベント発火 | 長時間放置の頻度 |
| `consecutive_days` | 連続作業日数 | 継続性追跡 |

**廃止**: `frequent_break`（記録コスト > 価値のため削除）

---

## 3. EventCounter 型

```rust
pub struct EventCounter {
    pub category: String,           // カテゴリ名
    pub total: u64,                 // 累積総数
    pub recent_30d: u64,            // 直近30日
    pub recent_7d: u64,             // 直近7日
    pub last_occurrence: Option<DateTime<Utc>>, // 最終発生時刻
    pub recent_dates: Vec<DateTime<Utc>>,       // 最近の発生日時（最大100件）
}
```

---

## 4. ストレージ

**保存先**: `~/.config/oribis/nagiko/event_counters.json`

```json
{
  "counters": {
    "lewd": {
      "category": "lewd",
      "total": 12,
      "recent_30d": 8,
      "recent_7d": 3,
      "last_occurrence": "2026-04-26T14:30:00Z",
      "recent_dates": ["2026-04-26T14:30:00Z", "..."]
    }
  }
}
```

---

## 5. API

```rust
// カウンター増加
pub fn increment_counter_at(category: &str, base_dir: &Path) -> Result<EventCounter>

// カウンター取得
pub fn get_counter_at(category: &str, base_dir: &Path) -> Result<Option<EventCounter>>

// 全カウンター取得
pub fn get_all_counters_at(base_dir: &Path) -> Result<HashMap<String, EventCounter>>
```

---

## 6. 時間計算ヘルパー（MemoryFix §7）

```rust
// 直近N日のカウントを recent_dates から計算
fn count_within_days(dates: &[DateTime<Utc>], days: u64) -> u64 {
    let threshold = Utc::now() - Duration::days(days as i64);
    dates.iter().filter(|&&d| d >= threshold).count() as u64
}

// recent_30d / recent_7d の更新
fn refresh_recent_counts(counter: &mut EventCounter) {
    counter.recent_30d = count_within_days(&counter.recent_dates, 30);
    counter.recent_7d = count_within_days(&counter.recent_dates, 7);
}
```

increment 時に自動更新。

---

## 7. L3注入フォーマット

変動があったカテゴリのみ条件付き注入:

```
[行動カウンタ]
- lewd: 12回（30日: 8、7日: 3）
- all_nighter: 5回（30日: 3、7日: 1）
```

条件: **直近7日に変動があったカテゴリのみ**注入（トークン節約）

---

## 8. 慣れ化ロジック（habitualization）

`lewd` / `error_burst` は累積カウントによってstageが変化:

| total | lewd | error_burst |
|-------|------|-------------|
| 1〜2 | stage1 | stage1 |
| 3〜5 | stage2 | stage2 |
| 6+ | stage3 | stage3 |

→ `spec-smart-cache.md` の `compute_sub_context()` で使用

---

## 9. トリガー接続（Phase 1実装対象）

| カテゴリ | トリガー元 | 接続場所 |
|---------|-----------|---------|
| lewd | Anima lewd通知受信 | `execute_anima_pipeline()` |
| all_nighter | セッション開始時刻チェック | `session_start()` |
| early_morning | セッション開始時刻チェック | `session_start()` |
| late_night | セッション開始時刻チェック | `session_start()` |
| weekend_work | セッション開始曜日チェック | `session_start()` |
| long_session | セッション経過時間チェック | 定期チェック |
| error_burst | Error Anima通知受信 | `execute_anima_pipeline()` |
| idle_long_count | IdleLong Anima通知受信 | `execute_anima_pipeline()` |
| consecutive_days | 日付変更時 | 日付変更フック |

---

## 10. 実装場所

- `src-tauri/src/character/counter.rs` — 全API・時間計算ヘルパー
- `src-tauri/src/character/context.rs` — L3注入（`build_context_at()`内）
- `src-tauri/src/character/cache.rs` — `compute_sub_context()` で参照

---

## 11. 関連ドキュメント

- `spec-smart-cache.md` — lewd/error_burst のstage別フレーズ
- `spec-prompt-layers.md` — L3条件付き注入仕様
- `spec-batch-distillation.md` — カウンターデータの記憶蒸留
- `architecture-diagrams.md` §9 — イベントカウンターフロー図

*作成日: 2026-04-28*
