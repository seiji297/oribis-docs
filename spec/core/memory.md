# 記憶システム 設計書

**バージョン**: 3.5（4レイヤー + Operational Memory + 自己進化 + self_model スキーマ修正 + 軽量エンティティリンク改訂）
**最終更新**: 2026-05-06

---

## 1. 設計思想

AIコンパニオンとして「生きた記憶」を実現する。データベースではなく、人間のパートナーとして相手を理解し続ける記憶システム。

原則:
- **即時永続化**: 意味ある体験は発生直後に記録。ロスなし
- **連続的統合**: バッチ蒸留に依存せず、継続的にエピソードを長期記憶へ昇格
- **感情的重み付け**: 重要度はエンコーディング時に判定。想起時だけではない
- **緩やかな忘却**: hard-deleteではなく強度ベースの減衰（soft forgetting）
- **関係性理解**: 単なる事実記憶ではなく、パートナーの人間像を構築

---

## 2. アーキテクチャ概要

4レイヤー構成:

```
[Layer 1]  memory_events     — append-only エピソードログ（即時永続・ロスなし）
[Layer 2]  memories          — 統合済み長期記憶（strength/salience/valence付き）
[Layer 3]  open_loops        — 未解決の関係・タスク状態（attentiveness の源泉）
[Layer 4]  relationship_model — 緩やかに変化するパートナー理解モデル
```

補助レイヤー（既存維持）:
- **event_counters** — 行動パターン統計（→ event-counter.md）

---

## 3. Layer 1: memory_events（エピソードログ）

### 3.1 概要

全ての意味ある対話・出来事を即時記録するappend-onlyストア。旧「セッションジャーナル」の代替だが、ローリングではなく永続。

### 3.2 MemoryEvent 型

```rust
pub struct MemoryEvent {
    pub id: i64,                        // auto-increment
    pub domain: Domain,                 // companion | worker_ops
    pub event_type: EventType,          // 分類
    pub actors: Vec<String>,            // "user", "anima", 第三者名
    pub topics: Vec<String>,            // タグ
    pub valence: f32,                   // -1.0（否定的）〜 +1.0（肯定的）
    pub arousal: f32,                   // 0.0（平静）〜 1.0（激しい）
    pub novelty: f32,                   // 0.0（既知）〜 1.0（新規）
    pub salience_score: f32,            // 総合重要度 0.0〜1.0
    pub raw_text: String,               // 元テキスト（要約 or 原文）
    pub metadata: Option<serde_json::Value>, // domain固有データ（worker_ops: WorkerOutcomeEvent）
    pub session_id: Option<String>,
    pub project_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub consolidated: bool,             // 統合済みフラグ
}

pub enum Domain {
    Companion,      // 会話・対人記憶
    WorkerOps,      // Worker品質パイプライン運用記録
}

pub enum EventType {
    // --- companion domain ---
    UserFact,       // ユーザーの事実情報
    Preference,     // 好み・嫌い
    Boundary,       // 境界・安全シグナル
    Emotion,        // 感情的瞬間
    Ritual,         // 繰り返される習慣・儀式
    Task,           // タスク・約束
    Repair,         // 関係修復・謝罪
    Conflict,       // 衝突・不和
    Affection,      // 愛情・感謝
    Disclosure,     // 個人的開示
    Correction,     // Animaの理解への訂正
    Smalltalk,      // 軽い雑談
    // --- worker_ops domain ---
    WorkerOutcome,  // Worker品質パイプライン結果（§11参照）
}
```

### 3.3 書き込みタイミング

毎ターン（チャット応答完了後）に即時記録される。

エンコーディング（分類・salience判定・open_loop操作）の詳細フローは **§7** を参照。

要約:
- **LLM主導パス**: oribis-meta ブロックから event_type/salience を取得（通常時）
- **Rust fallbackパス**: メタブロック欠落時にヒューリスティクスで分類
- **閾値**: final_salience >= 0.2 でイベント記録

### 3.4 salience スコアリング（ヒューリスティクス）

```rust
pub fn compute_salience(event: &MemoryEvent, context: &SalienceContext) -> f32 {
    let mut score = 0.0;

    // 明示的な好み/嫌い
    if matches!(event.event_type, EventType::Preference | EventType::Boundary) {
        score += 0.7;
    }
    // 個人的開示
    if matches!(event.event_type, EventType::Disclosure) {
        score += 0.6;
    }
    // Animaの理解への訂正
    if matches!(event.event_type, EventType::Correction) {
        score += 0.9;
    }
    // 境界・安全シグナル
    if matches!(event.event_type, EventType::Boundary) {
        score += 0.3; // 追加ブースト
    }
    // 強い感情
    if event.arousal > 0.7 {
        score += 0.3;
    }
    // affinity変動の大きさ
    score += context.affinity_delta_abs as f32 * 0.1;
    // 新規性
    score += event.novelty * 0.2;
    // 反復トピック（複数日にわたる）
    if context.topic_recurrence > 2 {
        score += 0.3;
    }
    // cross-session反復（日を跨いだ再言及）
    if context.cross_session_recurrence > 1 {
        score += 0.4;
    }
    // 将来時制・予定性（明日/来週/誕生日/面接/病院/締切）
    if context.has_future_reference {
        score += 0.5;
    }
    // 明示的記憶要求（覚えて/忘れないで/大事）
    if context.explicit_remember_request {
        score += 0.8;
    }
    // 矛盾検出（既存memoryと矛盾する発話）
    if context.contradicts_existing {
        score += 0.7;
    }
    // trust repair / attachment signal（ありがとう/安心した/傷ついた）
    if matches!(event.event_type, EventType::Repair | EventType::Affection) {
        score += 0.4;
    }

    score.min(1.0)
}

/// LLM salience と Rust heuristic salience のマージ
/// LLM主導だが、Rustが下限保証・安全網として機能
pub fn merge_salience(llm: Option<f32>, heuristic: f32) -> f32 {
    match llm {
        Some(l) => {
            // LLM存在時: 重み付き平均（LLM 0.7, Rust 0.3）
            // ただしRust側が高い場合はRust優先（安全側に倒す）
            let merged = l * 0.7 + heuristic * 0.3;
            merged.max(heuristic) // Rust下限保証
        }
        None => heuristic, // メタブロック欠落時: Rustのみ
    }
}
```

### 3.5 ストレージ

**保存先**: `~/.config/oribis/anima/memory.db`（SQLite）

```sql
CREATE TABLE memory_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL DEFAULT 'companion',  -- 'companion' | 'worker_ops'
    event_type TEXT NOT NULL,
    actors TEXT NOT NULL,        -- JSON array
    topics TEXT NOT NULL,        -- JSON array
    valence REAL NOT NULL DEFAULT 0.0,
    arousal REAL NOT NULL DEFAULT 0.0,
    novelty REAL NOT NULL DEFAULT 0.5,
    salience_score REAL NOT NULL DEFAULT 0.0,
    raw_text TEXT NOT NULL,
    metadata TEXT,               -- JSON (domain固有の詳細データ。worker_ops: §11.2参照)
    session_id TEXT,
    project_id TEXT,
    created_at TEXT NOT NULL,    -- ISO 8601
    consolidated INTEGER NOT NULL DEFAULT 0
    -- Phase 3: embedding BLOB  (sqlite-vec用、後方互換のためALTER TABLEで追加)
);

CREATE INDEX idx_events_salience ON memory_events(salience_score DESC);
CREATE INDEX idx_events_created ON memory_events(created_at DESC);
CREATE INDEX idx_events_consolidated ON memory_events(consolidated);
CREATE INDEX idx_events_type ON memory_events(event_type);
CREATE INDEX idx_events_domain ON memory_events(domain);
```

### 3.6 保持ポリシー

| 条件 | 処理 |
|------|------|
| salience >= 0.5 | 永続保持 |
| salience < 0.5 & consolidated | 90日後にアーカイブ |
| salience < 0.3 & 30日経過 | アーカイブ候補 |
| アーカイブ | 別テーブル移動（削除ではない） |

---

## 4. Layer 2: memories（長期記憶）

### 4.1 概要

統合済みの安定的な記憶。事実・好み・境界・関係性要約・パターン。

### 4.2 Memory 型

```rust
pub struct Memory {
    pub id: String,                     // UUID v4
    pub content: String,                // 記憶内容
    pub category: Option<String>,       // カテゴリ
    pub memory_type: MemoryType,        // 記憶種別
    pub source: MemorySource,           // 保存源
    pub strength: f32,                  // 記憶強度 0.0〜1.0
    pub salience: f32,                  // 重要度 0.0〜1.0
    pub valence: f32,                   // 感情価 -1.0〜+1.0
    pub decay_rate: f32,                // 減衰速度（種別で異なる）
    pub source_event_ids: Vec<i64>,     // 元イベントID群
    pub created_at: DateTime<Utc>,
    pub last_recalled: Option<DateTime<Utc>>,
    pub recall_count: u32,              // 想起回数
    pub confidence: f32,                // 確信度 0.0〜1.0
}

pub enum MemoryType {
    CoreIdentity,    // 名前・職業・基本属性
    Preference,      // 好み・嫌い
    Boundary,        // してほしくないこと・安全シグナル
    Relationship,    // 人間関係・重要人物
    Pattern,         // 繰り返される行動パターン
    Episode,         // 特定の出来事・思い出
    Skill,           // ユーザーのスキル・能力
}

pub enum MemorySource {
    HumanInstruction,   // 人間が「覚えて」と指示
    AIDetected,         // LLMがMEMORY_SAVEで保存
    Consolidated,       // consolidationで生成
    Inferred,           // パターンから推論
}
```

### 4.3 忘却曲線

```rust
pub fn compute_current_strength(memory: &Memory, now: DateTime<Utc>) -> f32 {
    let days_since_recall = memory.last_recalled
        .map(|t| (now - t).num_hours() as f32 / 24.0)
        .unwrap_or_else(|| (now - memory.created_at).num_hours() as f32 / 24.0);

    let recall_boost = (memory.recall_count as f32).ln_1p() * 0.1;
    let decay = memory.decay_rate * days_since_recall;

    (memory.strength + recall_boost - decay).clamp(0.0, 1.0)
}
```

種別ごとのデフォルト decay_rate:

| MemoryType | decay_rate | 意味 |
|------------|-----------|------|
| CoreIdentity | 0.001 | ほぼ忘れない |
| Boundary | 0.002 | ほぼ忘れない |
| Preference | 0.005 | 非常にゆっくり減衰 |
| Relationship | 0.005 | 非常にゆっくり減衰 |
| Pattern | 0.008 | ゆっくり減衰 |
| Episode | 0.015 | 中程度の減衰 |
| Skill | 0.010 | ゆっくり減衰 |

### 4.4 強度回復（想起による強化）

```rust
pub fn on_memory_recalled(memory: &mut Memory) {
    memory.recall_count += 1;
    memory.last_recalled = Some(Utc::now());
    memory.strength = (memory.strength + 0.1).min(1.0);
}
```

### 4.5 サイズ制限

| 項目 | 値 |
|------|---|
| 上限 | 500件（active） |
| HumanInstruction source | 永続保護 |
| strength < 0.1 到達時 | archive テーブルへ移動 |
| archive 上限 | 2000件（超過時はstrength最低から削除） |

### 4.6 ストレージ

```sql
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    category TEXT,
    memory_type TEXT NOT NULL,
    source TEXT NOT NULL,
    strength REAL NOT NULL DEFAULT 1.0,
    salience REAL NOT NULL DEFAULT 0.5,
    valence REAL NOT NULL DEFAULT 0.0,
    decay_rate REAL NOT NULL DEFAULT 0.01,
    source_event_ids TEXT NOT NULL DEFAULT '[]',  -- JSON array
    created_at TEXT NOT NULL,
    last_recalled TEXT,
    recall_count INTEGER NOT NULL DEFAULT 0,
    confidence REAL NOT NULL DEFAULT 1.0
    -- Phase 3: embedding BLOB  (sqlite-vec用、後方互換のためALTER TABLEで追加)
);

CREATE TABLE memories_archive (
    -- 同一スキーマ
);

CREATE INDEX idx_memories_strength ON memories(strength DESC);
CREATE INDEX idx_memories_type ON memories(memory_type);
CREATE INDEX idx_memories_category ON memories(category);
```

---

## 5. Layer 3: open_loops（未解決状態）

### 5.1 概要

パートナーの「今気になっていること」を追跡する。これがコンパニオンの「気配り」の源泉。

例:
- 「明日面接がある」→ 翌日「面接どうでしたか？」
- 「Xをリマインドして」→ 適切なタイミングで想起
- 「最近仕事で辛い」→ 継続的な気遣い

### 5.2 OpenLoop 型

```rust
pub struct OpenLoop {
    pub id: String,                     // UUID v4
    pub content: String,                // 要約
    pub loop_type: LoopType,
    pub priority: f32,                  // 0.0〜1.0
    pub source_event_ids: Vec<i64>,
    pub created_at: DateTime<Utc>,
    pub resolved_at: Option<DateTime<Utc>>,
    pub remind_after: Option<DateTime<Utc>>,  // リマインドタイミング
    pub ttl_days: Option<u32>,          // 自動解決までの日数
    pub last_recalled_at: Option<DateTime<Utc>>,  // 最終想起日時（Cache mode再提起時に更新）
}

pub enum LoopType {
    Reminder,       // 明示的リマインド依頼
    Concern,        // ユーザーの心配事
    Anticipation,   // 今後の予定・イベント
    OngoingIssue,   // 継続的な問題
    Promise,        // Animaがした約束
}
```

### 5.3 ライフサイクル

**生成ルール**:
- イベント分類時に future_reference 検出 → Anticipation
- 「覚えておいて」「リマインドして」→ Reminder
- 問題・不安の吐露 → Concern / OngoingIssue
- Animaが「確認します」「後で報告します」→ Promise
- Level 1 consolidation 時に未解決パターン検出 → OngoingIssue

**マッチング方式（update/resolve 対象の特定）**:
- **LLM指定**: oribis-meta の `open_loops[].id` に既存loop IDを明示（最優先）
- **topic/entity overlap**: 新イベントの entities/topics と既存 open_loop の content/source_events の entities を比較。Jaccard >= 0.3 で候補
- **曖昧時**: 候補が複数 → priority最高のものを選択。候補なし → create（新規）

**解決（close）ルール**:
- ユーザーが結果報告（「面接受かった」「あれ解決した」）→ topic/entity overlap で自動マッチ → resolved
- ttl_days 経過（デフォルト: Anticipation=7日, Reminder=14日, Concern=30日, OngoingIssue=60日, Promise=7日）
- 明示的解決（「もういいよ」「気にしなくていい」）
- 矛盾イベント検出（状況が変わった場合）
- LLMが `open_loops[].op = "resolve"` + `id` を明示指定

**更新ルール**:
- 同一topic/entityの後続イベントで priority / content を更新
- LLMが `open_loops[].op = "update"` + `id` を明示指定
- 例: 「面接が心配」(priority=0.6) → 「面接明日だ」(priority=0.9に昇格)

**L3注入**: 未解決ループは毎ターン注入候補（priority上位3件）
**proactive resurfacing**: remind_after 到達時は Anima発話トリガーとして利用可能

### 5.4 ストレージ

```sql
CREATE TABLE open_loops (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    loop_type TEXT NOT NULL,
    priority REAL NOT NULL DEFAULT 0.5,
    source_event_ids TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    resolved_at TEXT,
    remind_after TEXT,
    ttl_days INTEGER,
    last_recalled_at TEXT
);

CREATE INDEX idx_loops_resolved ON open_loops(resolved_at);
CREATE INDEX idx_loops_priority ON open_loops(priority DESC);
```

---

## 6. Layer 4: relationship_model（パートナー理解）

### 6.1 概要

ユーザーの人物像を構造化して保持。ゆっくり更新される「この人はこういう人」の理解。

### 6.2 RelationshipModel 型

```rust
pub struct RelationshipModel {
    pub communication_style: Vec<TraitEntry>,   // 例: "簡潔好み", "技術用語OK"
    pub stressors: Vec<TraitEntry>,             // 例: "締め切り", "徹夜"
    pub comfort_signals: Vec<TraitEntry>,       // 例: "紅茶", "早朝作業"
    pub important_people: Vec<PersonRef>,       // 重要人物
    pub boundaries: Vec<TraitEntry>,            // 明示的な境界
    pub attachment_style: Option<String>,       // 観察から推定
    pub last_updated: DateTime<Utc>,
}

/// 推論層エントリ — 出典と確信度を持つ
pub struct TraitEntry {
    pub value: String,
    pub confidence: f32,                // 0.0〜1.0（推測=低, 明言=高）
    pub source_event_ids: Vec<i64>,     // 根拠となるイベントID
    pub last_confirmed_at: Option<DateTime<Utc>>,  // 最後に再確認された日時
}

pub struct PersonRef {
    pub name: String,
    pub relation: String,       // 例: "同僚", "友人", "家族"
    pub context: String,        // 登場文脈
    pub source_event_ids: Vec<i64>,
}
```

### 6.3 更新タイミング

- Consolidation Level 2（LLM使用）実行時に更新
- 頻度: 最大1日1回
- 即時更新: source="user_chat" の Boundary/Correction イベント時のみ
  - source="anima" の Boundary/Correction は Level 2 で遅延反映（Anima推測は即時反映しない）

### 6.4 ストレージ

```sql
CREATE TABLE relationship_model (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,         -- JSON
    updated_at TEXT NOT NULL
);
```

キー例: `communication_style`, `stressors`, `comfort_signals`, `important_people`, `boundaries`

### 6.5 self_model（AI自己理解モデル）

relationship_model がユーザーの人物像を保持するのに対し、self_model は **AIコンパニオン自身の嗜好・傾向** を経験から構築する。

#### 設計原則

- **CLAUDE.md が種（seed）、self_model が成長** — 静的人格定義は不変。self_model は経験に基づく追加レイヤー
- **嗜好のみ更新可** — 倫理・口調・役割・価値観の根幹は更新不可
- **「AIがそう言った」は証拠ではない** — self_model は自分の出力文を証拠にして更新しない。更新元は interaction evidence のみ

#### SelfModel 型

```rust
pub struct SelfModel {
    pub core_preferences: Vec<SelfTrait>,       // ほぼ永続的な嗜好
    pub situational_preferences: Vec<SelfTrait>, // 中程度 decay の状況的嗜好
    pub last_updated: DateTime<Utc>,
}

pub struct SelfTrait {
    pub target: String,                  // 対象（例: "整理されたコード", "早朝作業"）
    pub target_type: SelfTraitTargetType,
    pub valence: f32,                    // -1.0（嫌い）〜 +1.0（好き）
    pub confidence: f32,                 // 0.0〜1.0（証拠量に比例）
    pub evidence_count: u32,            // 裏付け evidence 数
    pub evidence_positive: u32,         // 正の evidence 数
    pub evidence_negative: u32,         // 負の evidence 数
    pub cross_day_count: u32,           // 日跨ぎ evidence 回数（昇格判定に使用）
    pub source_event_ids: Vec<i64>,     // 根拠イベントID（直近10件）
    pub scope: TraitScope,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,               // 最終更新時刻
    pub last_confirmed_at: Option<DateTime<Utc>>, // 最終 evidence 確認時刻
}

pub enum SelfTraitTargetType {
    Topic,              // 話題（技術、趣味等）
    Style,              // スタイル（簡潔な会話、整理されたコード等）
    Activity,           // 活動（レビュー、デバッグ等）
    Constraint,         // 制約（マジックナンバー、ハードコード等）
    Tool,               // ツール（Rust、TypeScript等）
    TimePattern,        // 時間パターン（早朝、深夜等）
    InteractionPattern, // 対話パターン（丁寧な依頼、技術議論等）
}

pub enum TraitScope {
    Core,           // 永続的嗜好（会話スタイル、作業リズム、美学）
    Situational,    // 状況的嗜好（直近タスクへの好悪、最近の関心）
}
```

#### 更新ルール（人格ドリフト防止）

| ルール | 値 | 理由 |
|--------|---|------|
| valence 範囲 | [-1.0, 1.0] 有界 | 極端化防止 |
| 1回の更新量 | max delta = 0.03 | 急激な変化防止 |
| trait 化閾値 | 同種 evidence 3件以上 + 日跨ぎ2回以上 | ノイズ除外 |
| 多様性条件 | 同一セッション内 evidence のみでは trait 化しない | セッション偏り防止 |
| hysteresis | trait 反転には通常の2倍の evidence 量を要求 | 安定性確保 |
| 反証保持 | evidence_positive / evidence_negative 両方を保持 | 一方的強化防止 |
| 循環強化禁止 | source_of_evidence != prior_self_model | AIの自己言及は証拠にしない |
| evidence source 判定 | memory_events.id を source_event_ids で参照。evidence の日付・セッション多様性は memory_events テーブルから逆引きで検証 | DB参照前提 |
| 日跨ぎカウント | evidence 追加時、前回の last_confirmed_at と異なる日付なら cross_day_count++ | セッション偏り防止の定量化 |
| upsert 方針 | UNIQUE(target, target_type, scope) 制約。同一対象は既存 trait を更新（新規作成しない） | 重複防止 |

#### Decay

| scope | decay_rate | 意味 |
|-------|-----------|------|
| Core | 0.002 | ほぼ永続（会話スタイル、美学） |
| Situational | 0.012 | 中程度減衰（直近の関心） |

Core への昇格条件（全てAND）:
1. `evidence_count >= 10`
2. `confidence >= 0.7`
3. `created_at` から30日以上経過（`julianday('now') - julianday(created_at) >= 30`）
4. 日跨ぎ evidence が5回以上（`cross_day_count >= 5`）

昇格時の処理: `scope = 'core'`, `decay_rate = 0.002` に更新

#### ストレージ

```sql
CREATE TABLE self_model (
    id TEXT PRIMARY KEY,
    target TEXT NOT NULL,
    target_type TEXT NOT NULL CHECK(target_type IN ('Topic','Style','Activity','Constraint','Tool','TimePattern','InteractionPattern')),
    valence REAL NOT NULL DEFAULT 0.0 CHECK(valence >= -1.0 AND valence <= 1.0),
    confidence REAL NOT NULL DEFAULT 0.0 CHECK(confidence >= 0.0 AND confidence <= 1.0),
    evidence_count INTEGER NOT NULL DEFAULT 0 CHECK(evidence_count >= 0),
    evidence_positive INTEGER NOT NULL DEFAULT 0 CHECK(evidence_positive >= 0),
    evidence_negative INTEGER NOT NULL DEFAULT 0 CHECK(evidence_negative >= 0),
    cross_day_count INTEGER NOT NULL DEFAULT 0,    -- 日跨ぎ evidence 回数
    source_event_ids TEXT NOT NULL DEFAULT '[]',   -- JSON array（直近10件）
    scope TEXT NOT NULL DEFAULT 'situational' CHECK(scope IN ('core','situational')),
    decay_rate REAL NOT NULL DEFAULT 0.012,        -- core昇格時に0.002へ更新
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,                      -- 最終更新時刻（昇格判定・30日持続判定に使用）
    last_confirmed_at TEXT,                        -- 最終 evidence 確認時刻

    UNIQUE(target, target_type, scope)             -- 同一対象の重複 trait 防止
);

CREATE INDEX idx_self_confidence ON self_model(confidence DESC);
CREATE INDEX idx_self_scope ON self_model(scope);
```

#### サイズ制限

| 項目 | 値 |
|------|---|
| core 上限 | 30件 |
| situational 上限 | 50件 |
| confidence < 0.1 到達時 | 自動削除 |

#### relationship_model との関係

- **テーブルは独立**（schema / update rules / safety bounds は別）
- **consolidation machinery は共有可**（extraction pipeline / target normalization / evidence aggregation / confidence update / decay scheduler）
- 例: "user likes early morning work" は relationship_model、"I prefer reviewing code in early morning" は self_model

---

## 7. エンコーディング（書き込みフロー）

### 7.1 Pass A: 即時同期キャプチャ（LLM主導 + Rust guardrail）

**チャットパイプライン（LLMあり）**:

```
ユーザーメッセージ + AI応答 完了
  ↓
parse_oribis_meta() — 応答末尾の <oribis-meta> ブロックをパース
  ↓ (メタブロック存在時)
LLM判定: event_type, salience, open_loops, entities, topics
  ↓
rust_salience_guardrail() — Rust側で補正/下限保証
  ↓ final_salience = merge(llm_salience, heuristic_salience)
  ↓ (final_salience >= 閾値 0.2)
events::append_event() → memory_events テーブル
  ↓
open_loops 処理（create/update/resolve）
  ↓
memory_saves → memories テーブル直接保存（既存互換）
  ↓
self_reactions 処理（§6.5 参照）
  → 各 reaction の target を正規化
  → 既存 self_model の同一 target を検索
  → evidence 蓄積（trait 化閾値未達なら evidence のみ記録）
  → 閾値到達時: self_model に新 trait 追加 or 既存 trait 更新（max delta = 0.03）
```

**メタブロック欠落時（L1 fade / LLM未出力）**:

```
応答テキストのみ（メタブロックなし）
  ↓
classify_event_heuristic() — Rustフォールバック
  ↓ キーワード辞書 + affinity_delta + パターンマッチ
  ↓ (salience >= 閾値 0.2)
events::append_event() → memory_events テーブル
```

**Animaパイプライン（Cache mode / LLMなし）**:

```
AnimaState静的フレーズ返却
  ↓
記憶分類対象外（ユーザー記憶の主ソースではない）
  ↓ 例外: 既存open_loopの再提起のみRust処理（読み取り専用）
  - 既存open_loopの自然な再提起 → last_recalled_at 更新
  ※ Cache mode ではloop新規作成・更新・解決は行わない（LLM不在のため判断不能）
```

**Animaパイプライン（Ai/Hybrid AIフォールバック / LLMあり）**:

```
AnimaState → AI生成 → oribis-meta パース
  ↓
persist_oribis_meta_event(source="anima")
  ↓
memory_events に記録（source フィールドで user_chat と区別）
```

#### source フィールドによるイベント区分（A2）

memory_events の metadata JSON に `source` フィールドを付与し、記憶の出所を区別する。

| source 値 | 発生元 | 用途 |
|-----------|--------|------|
| `user_chat` | ユーザーとの対話パイプライン | companion 記憶の主ソース |
| `anima` | Anima AI生成パイプライン | Anima 自律発話由来の観測 |

**Consolidation への影響**:

- Level 1 統合: source を区別せず統合する（domain=companion の全イベントが対象）
- Level 2 統合: source="anima" イベントは **重み 0.5** で扱う（ユーザー直接発話より信頼性が低いため）
  - 適用ポイント: memories への merge 時に confidence を `base_confidence * 0.5` に減衰させる
- relationship_model 更新: source="anima" からの Boundary/Correction は Level 2 でのみ反映（即時反映しない）
- consolidation_state の key 体系は変更なし（domain 単位で追跡。source 単位の分離は不要）

**metadata.source 欠落時の扱い**: `user_chat` として扱う（既存データ・フォールバック書き込み互換）。

**理由**: Anima は自律発話のため、ユーザーが実際に述べたことと Anima が推測・反応したことを混同しない。
ただし Anima 観測も完全無視はせず、低重みで統合に含める。

### 7.2 Pass B: Consolidation（統合）

#### Level 1: ルールベース統合（LLM不要・安価）

```
トリガー: salientイベント5件蓄積 or 未統合20件 or 30分タイマー or アプリ終了 or 起動時未処理検出
  ↓
未統合イベント取得（consolidated = false）
  ↓
ルールベース処理:
  - 重複検出・既存memoryとのマージ
  - strength更新
  - open_loop 生成/更新/解決
  - topic clustering
  ↓
memories / open_loops 更新
  ↓
memory_events.consolidated = true
  ↓
consolidation_state 更新
```

#### Level 2: LLM統合（高品質・コスト有り）

**重要: Level 2 はチャットパスと完全非同期で実行すること。同期呼出禁止（体感レイテンシ劣化防止）。**

```
トリガー: 高salience batch蓄積 or アイドル時 or 予算許容時
  ↓ （バックグラウンドタスクとして実行）
未処理の高salienceイベント群 + 既存relationship_model
  ↓
LLM呼出:
  - イベント群 → 意味的記憶生成
  - relationship_model 更新提案
  - パターン検出
  ↓
memories 追加/更新
relationship_model 更新
```

### 7.3 Consolidation トリガー（正本）

#### companion domain

| トリガー | Level | 条件 |
|---------|-------|------|
| salientイベント5件蓄積 | Level 1 | salience >= 0.5 のイベントが5件 |
| 未統合20件 or 30分タイマー | Level 1 | バックアップ（低salience蓄積防止） |
| アプリ正常終了 | Level 1 | 未統合イベントが1件以上 |
| アプリ起動時 | Level 1 | 前回未処理イベントが存在 |
| 6時間タイマー | Level 2 | スケジューラ定期実行（companion未統合あり） |
| IdleLong | Level 2 | 前回Level 2から1時間以上経過 + 高salienceイベント存在 |
| アプリ起動時（バックログ） | Level 2 | 前回Level 2から24時間以上経過 |
| 手動トリガー | Level 2 | デバッグ/テスト用 |

#### worker_ops domain（§11.4 参照）

| トリガー | Level | 条件 |
|---------|-------|------|
| 同一department未統合5件 | Level 2 | evidence-based |
| 同一failure_reason 3回観測 | Level 2 | パターン検出 |
| 24時間タイマー | Level 2 | バックアップ（未統合 > 0） |

### 7.4 状態管理

```sql
CREATE TABLE consolidation_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- domain-aware keys:
--   companion_last_level1_event_id   -- Level 1 最終処理イベントID
--   companion_last_level2_event_id   -- Level 2 最終処理イベントID
--   companion_last_level2_at         -- Level 2 最終実行日時
--   worker_ops_last_level2_event_id  -- worker_ops Level 2 最終処理イベントID
--   worker_ops_last_level2_at        -- worker_ops Level 2 最終実行日時
```

**運用ルール**:
- companion: Level 1 完了で `memory_events.consolidated = true`。Level 2 は state key で追跡
- worker_ops: Level 2 完了（worker_patterns抽出後）で `memory_events.consolidated = true`

---

## 8. 検索・想起（L3注入フロー）

### 8.1 4チャネル検索

`build_context_at()` 実行時に以下4チャネルから取得（retrieval.rs / SQLite経由）:

| チャネル | 取得元 | 件数上限 | 条件 |
|---------|--------|---------|------|
| profile | memories (CoreIdentity/Preference/Boundary/Skill) + relationship_model要約 | 5件 | strength上位。relationship_modelはprofileに内包して注入 |
| open_loops | open_loops | 3件 | priority上位 & 未解決 |
| relevant_episodes | memory_events | 3件 | topic/entity重複 or 類似度 |
| self_context | self_model | 2〜4件 | confidence上位 & 現在の会話トピックに関連する場合のみ（G1-SM まで stub） |

※ counter_context は L2 注入（毎ターン固定）に移動。L3 チャネルから除外。

**注入条件（ContextMode依存）**:
- `StatefulSession` + `NormalTurn`: episodes チャネルのみ（他は既存コンテキスト窓に保持）
- `StatefulSession` + `SessionStart` / `AfterCompaction`: 全4チャネル
- `StatelessRequest` + any: 全4チャネル（毎ターン）

**グレースフルデグレード**: DB（memory.db）が利用不可の場合、L3は空文字列として扱い処理を継続する。

**self_context 注入ルール**:
- 高 confidence（>= 0.5）の trait のみ
- 毎ターン全件は出さない。現在の conversation topics と target が関連する場合のみ注入
- 関連なしの場合は 0件（トークン節約 + 自己暗示防止）
- **self_model から注入された内容は retrieval 用であり、次ターンの self_reactions の evidence source にしてはならない**

### 8.2 検索ランキング

```rust
pub fn rank_for_injection(items: &[RankedItem]) -> Vec<RankedItem> {
    // Phase 2 (keyword/structural + entity link):
    //   keyword_entity_overlap * 0.20
    //   + entity_link_score * 0.10  (§8.6 1-hop/2-hop)
    //   + salience * 0.25
    //   + current_strength * 0.2  (memories層のみ。events層はrecencyで代替)
    //   + recency_decay * 0.15
    //   + open_loop_boost * 0.1
    //
    // Phase 3 (hybrid vector追加後):
    //   semantic_relevance(vector) * 0.20
    //   + keyword_entity_overlap(FTS5/RRF) * 0.10
    //   + entity_link_score * 0.10  (§8.6 1-hop/2-hop)
    //   + salience * 0.20
    //   + current_strength * 0.15
    //   + recency_decay * 0.15
    //   + open_loop_boost * 0.1
}
```

**Phase 2→3 移行**: Phase 2 では topic/entity の文字列マッチのみ。Phase 3 でベクトル類似度を追加し RRF で統合。重みは Phase 3 導入時に再調整。

### 8.3 L3注入フォーマット

```
[あなたが覚えていること]
- 緑茶好き（食べ物）
- 夜型人間だが早朝作業を好む（習慣）
- TypeScript + Rust が主要スキル（スキル）

[気にかけていること]
- 明日14時に面接がある
- 最近仕事の負荷が高い

[最近の出来事]
- 昨日: 新しいプロジェクト開始を報告してくれた

[あなた自身のこと]
- 整理されたコードが好き（確信度: 0.9）
- テスト設計の議論に関心がある（確信度: 0.6）
```

`[あなた自身のこと]` は self_model の高 confidence trait から、現在の会話トピックに関連するもののみを注入。関連なしの場合はチャネルごと省略。

### 8.4 MEMORY_QUERY（既存互換）

従来の MEMORY_QUERY マーカーも引き続き機能:
- substring + topic matching で memories テーブルを検索
- 結果は次ターンの L3 に追加注入

### 8.5 想起による強化

L3注入に使用された memory は `on_memory_recalled()` で強度回復。忘却曲線に対抗する。

### 8.6 軽量エンティティリンク（GraphRAG代替）

#### 設計判断: なぜGraphRAGではないか

GraphRAG（Neo4j + LLM entity extraction + Leiden community detection）は数万〜数百万ドキュメント規模の企業ナレッジベース向け。Oribisの単一ユーザー・数千件規模では:

- **コスト超過**: エンティティ抽出・コミュニティ要約にLLM呼出が必要（$1/日目標と矛盾）
- **インフラ過剰**: Neo4j追加はTauriデスクトップアプリの配布・運用に不適
- **レイテンシ悪化**: graph traversal + community summary参照がL3の180tok軽量注入と非整合

代わりに、SQLite内で「点と点を繋ぐ推論」の80%を実現する**軽量エンティティリンク**を採用する。

#### アーキテクチャ

```
oribis-meta の topics/entities（既存）
  ↓ エンコーディング時
event_entities テーブル（正規化済み entity ↔ event 紐付け）
  ↓ Level 1 consolidation 時
entity_cooccurrence テーブル（entity 間の共起重み）
  ↓ 検索時
1-hop / 2-hop 関連記憶の取得（SQL JOIN）
```

#### テーブル定義

```sql
-- エンティティ正規化テーブル
CREATE TABLE entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,              -- 正規化済みエンティティ名
    entity_type TEXT NOT NULL DEFAULT 'concept'
        CHECK(entity_type IN ('person','technology','concept','project','place')),
    first_seen_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    mention_count INTEGER NOT NULL DEFAULT 1 CHECK(mention_count >= 0),
    last_retrieved_at TEXT                  -- 検索で使われた最終時刻（削除判定用）
);

CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_entities_type ON entities(entity_type);

-- イベント ↔ エンティティ紐付け（多対多・role別に複数行可）
CREATE TABLE event_entities (
    event_id INTEGER NOT NULL REFERENCES memory_events(id) ON DELETE CASCADE,
    entity_id INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'mention'
        CHECK(role IN ('mention','subject','object')),
    PRIMARY KEY (event_id, entity_id, role)  -- role別に複数行を許容
);

CREATE INDEX idx_event_entities_entity ON event_entities(entity_id);
CREATE INDEX idx_event_entities_event ON event_entities(event_id);

-- エンティティ共起テーブル
CREATE TABLE entity_cooccurrence (
    entity_a INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    entity_b INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    weight REAL NOT NULL DEFAULT 1.0 CHECK(weight > 0),
    last_seen_at TEXT NOT NULL,
    PRIMARY KEY (entity_a, entity_b),
    CHECK(entity_a < entity_b)             -- 順序正規化（重複防止）
);

CREATE INDEX idx_cooccurrence_weight ON entity_cooccurrence(weight DESC);
CREATE INDEX idx_cooccurrence_a ON entity_cooccurrence(entity_a);
CREATE INDEX idx_cooccurrence_b ON entity_cooccurrence(entity_b);
```

**外部キー CASCADE**: entities 削除時に event_entities / entity_cooccurrence が自動削除される。

#### 書き込みフロー

**エンコーディング時（§7.1 Pass A 内）**:

```rust
fn link_entities(event_id: i64, meta: &OrbisMeta) {
    // 1. topics + entities からエンティティ候補を抽出
    let raw_entities = meta.topics.iter()
        .chain(meta.entities.iter());

    // 2. 正規化（小文字化、同義語マージ）
    let normalized = normalize_entities(raw_entities);

    // 3. entities テーブルに upsert（mention_count++, last_seen_at 更新）
    for entity in &normalized {
        upsert_entity(entity);
    }

    // 4. event_entities に紐付け挿入
    for entity in &normalized {
        insert_event_entity(event_id, entity.id, "mention");
    }
}
```

**Level 1 consolidation 時（§7.2 内）**:

```rust
fn update_cooccurrence(event_id: i64) {
    // 1. event_id に紐づく全 entity を取得
    let entities = get_entities_for_event(event_id);

    // 2. 全ペアの共起を更新（salience で重み付け）
    let salience = get_event_salience(event_id);
    for (a, b) in entity_pairs(&entities) {
        let (lo, hi) = if a < b { (a, b) } else { (b, a) };
        // weight += salience（高重要度イベントの共起ほど強い）
        upsert_cooccurrence(lo, hi, salience);
    }
}
```

#### エンティティ正規化ルール

| ルール | 例 | 備考 |
|--------|---|------|
| 小文字統一 | "Rust" → "rust" | ASCII のみ。日本語はそのまま |
| 同義語マージ | "TS" / "TypeScript" → "typescript" | SYNONYM_MAP |
| カタカナ→英字 | "タイプスクリプト" → "typescript" | KANA_MAP（主要技術用語のみ） |
| 助詞・冠詞除去 | "のテスト" → "テスト" | 末尾助詞パターンマッチ |
| 空白トリム | " React " → "react" | 全角スペースも対象 |
| 記号除去 | "C++" → "cpp", "Node.js" → "nodejs" | SYMBOL_MAP |

**topics と entities の区別**:

oribis-meta の `topics`（概念タグ）と `entities`（固有名詞）は区別して処理する:

| ソース | entity_type 推定 | 例 |
|--------|-----------------|---|
| `entities` フィールド | LLM出力の文脈から推定（person/technology/project/place） | "Alice" → person, "React" → technology |
| `topics` フィールド | デフォルト `concept` | "テスト設計" → concept |

同義語辞書: `entities` テーブルの `name` は正規化済み。マッピングは Rust 側の `SYNONYM_MAP: HashMap<&str, &str>` + `KANA_MAP` + `SYMBOL_MAP` で管理（初期は小規模。運用で拡張）。

#### 検索への統合（§8.2 ランキング拡張）

**1-hop 検索 SQL**:

```sql
-- current_entity_ids: 現在の会話から抽出した entity の id 群
-- 自己イベント除外: 現在の会話イベント自体は除く
-- 重複集約: 同一 event が複数経路でヒットした場合は MAX(weight) を採用
SELECT ee2.event_id, MAX(ec.weight) AS link_weight
FROM event_entities ee
JOIN entity_cooccurrence ec
  ON (ee.entity_id = ec.entity_a OR ee.entity_id = ec.entity_b)
JOIN event_entities ee2
  ON ee2.entity_id = CASE
    WHEN ee.entity_id = ec.entity_a THEN ec.entity_b
    ELSE ec.entity_a
  END
WHERE ee.entity_id IN (/* current_entity_ids */)
  AND ee2.event_id NOT IN (/* current_event_ids */)  -- 自己除外
  AND ee2.entity_id != ee.entity_id                  -- 自己ループ除外
GROUP BY ee2.event_id                                -- 重複集約
ORDER BY link_weight DESC
LIMIT 10;
```

**2-hop 検索 SQL**:

```sql
-- 1-hop で得た entity_id 群を起点に、更に 1-hop を辿る
-- weight は積で減衰: hop1_weight * hop2_weight * 0.5
-- 1-hop 結果と重複するイベントは除外
WITH hop1 AS (
  -- 1-hop で到達した entity_id 群と weight
  SELECT DISTINCT
    CASE WHEN ee.entity_id = ec.entity_a THEN ec.entity_b ELSE ec.entity_a END AS mid_entity,
    ec.weight AS hop1_weight
  FROM event_entities ee
  JOIN entity_cooccurrence ec
    ON (ee.entity_id = ec.entity_a OR ee.entity_id = ec.entity_b)
  WHERE ee.entity_id IN (/* current_entity_ids */)
)
SELECT ee3.event_id, MAX(h1.hop1_weight * ec2.weight * 0.5) AS link_weight
FROM hop1 h1
JOIN entity_cooccurrence ec2
  ON (h1.mid_entity = ec2.entity_a OR h1.mid_entity = ec2.entity_b)
JOIN event_entities ee3
  ON ee3.entity_id = CASE
    WHEN h1.mid_entity = ec2.entity_a THEN ec2.entity_b
    ELSE ec2.entity_a
  END
WHERE ee3.event_id NOT IN (/* current_event_ids + hop1_event_ids */)
  AND ee3.entity_id NOT IN (/* current_entity_ids */)  -- 起点に戻らない
GROUP BY ee3.event_id
ORDER BY link_weight DESC
LIMIT 5;
```

**entity_link_score 正規化（0..1）**:

```rust
/// link_weight（生値）を 0..1 に正規化
/// log 正規化: 共起 weight は加算蓄積で上限なしのため、log で圧縮
fn normalize_link_score(link_weight: f32, max_weight: f32) -> f32 {
    if max_weight <= 0.0 { return 0.0; }
    // log(1 + w) / log(1 + max_w) で 0..1 に写像
    let score = (1.0 + link_weight).ln() / (1.0 + max_weight).ln();
    score.clamp(0.0, 1.0)
}

// max_weight は entity_cooccurrence の MAX(weight) を定期キャッシュ（consolidation時に更新）
```

1-hop と 2-hop のスコア統合: `entity_link_score = max(hop1_score, hop2_score)`（同一イベントが両方にヒットした場合は高い方を採用）

**ランキングへの統合（Phase 2）**:

```rust
// Phase 2 (keyword/structural + entity link):
//   keyword_entity_overlap * 0.20
//   + entity_link_score * 0.10      // ← 新規追加（0..1 正規化済み）
//   + salience * 0.25
//   + current_strength * 0.2
//   + recency_decay * 0.15
//   + open_loop_boost * 0.1
//
// Phase 3 (hybrid vector追加後):
//   semantic_relevance(vector) * 0.20
//   + keyword_entity_overlap(FTS5/RRF) * 0.10
//   + entity_link_score * 0.10      // ← 新規追加（0..1 正規化済み）
//   + salience * 0.20
//   + current_strength * 0.15
//   + recency_decay * 0.15
//   + open_loop_boost * 0.1
```

#### サイズ制限・メンテナンス

| 項目 | 値 |
|------|---|
| entities 上限 | 1000件 |
| entity_cooccurrence 上限 | 5000件 |
| 共起の最小weight閾値 | 0.5未満かつ90日未更新 → 自動削除 |
| メンテナンス実行 | Level 1 consolidation と同タイミング |

**entities 削除順位**（上限超過時、スコア最低から削除）:

```rust
/// 削除優先度スコア（低いほど削除対象）
fn entity_retention_score(e: &Entity) -> f32 {
    let mention = (e.mention_count as f32).ln_1p();      // 言及頻度（log圧縮）
    let recency = recency_score(e.last_seen_at);          // 最終言及からの新しさ 0..1
    let retrieval = if e.last_retrieved_at.is_some() {     // 検索で使われたか
        recency_score(e.last_retrieved_at.unwrap()) * 0.5
    } else { 0.0 };
    let edges = connected_edge_count(e.id) as f32 * 0.1;  // 共起エッジ数

    mention * 0.3 + recency * 0.3 + retrieval * 0.2 + edges * 0.2
}
```

**CASCADE による整合保証**: entities 削除時に `ON DELETE CASCADE` で event_entities / entity_cooccurrence が自動削除される（スキーマで定義済み）。

#### パフォーマンス目標

| 処理 | 目標 |
|------|------|
| エンティティ upsert（エンコーディング時） | < 3ms |
| 共起更新（consolidation時） | < 10ms |
| 1-hop 検索 | < 5ms |
| 2-hop 検索 | < 15ms |

#### GraphRAG との比較

| 観点 | GraphRAG | 軽量エンティティリンク |
|------|----------|---------------------|
| DB | Neo4j（別プロセス） | SQLite（memory.db内） |
| エンティティ抽出 | LLM呼出（毎ターン） | oribis-meta の topics/entities を流用（追加LLMコストなし） |
| コミュニティ検出 | Leiden（バッチLLM要約） | 共起weight（自然に形成・LLM不要） |
| 多段ホップ推論 | 任意深さのgraph traversal | 2-hop まで（実用上十分） |
| グローバル要約 | community summary | relationship_model + self_model が代替 |
| コスト | $3-10/日追加 | $0（既存oribis-metaを流用） |
| レイテンシ | 100-500ms | < 15ms |
| インフラ | Neo4j + worker process | SQLiteのみ |

---

## 9. 構造化メタブロック仕様（oribis-meta）

### 9.1 概要

LLM応答の**末尾**に付加される構造化JSONブロック。記憶分類・open_loop操作・エンティティ抽出を1箇所に集約する。

個別マーカー（MEMORY_SAVE/MEMORY_QUERY）を本文中に散在させるのではなく��末尾の固定フォーマット1ブロックに寄せることでパース安定性とメンテナンス性を確保。

### 9.2 フォーマット

```
（応答本文）

[AFFINITY:+1]

<oribis-meta>
{
  "v": 1,
  "event": {
    "type": "disclosure",
    "salience": 0.82,
    "confidence": 0.91,
    "valence": -0.3,
    "arousal": 0.7,
    "novelty": 0.6,
    "future_relevance": true,
    "contradicts_memory": false
  },
  "open_loops": [
    {"op": "create", "type": "anticipation", "content": "明日面接", "priority": 0.84},
    {"op": "update", "id": "existing-loop-uuid", "priority": 0.95},
    {"op": "resolve", "id": "existing-loop-uuid"}
  ],
  "memory_saves": [
    {"category": "work", "value": "明日14時に面接がある"}
  ],
  "memory_queries": [],
  "self_reactions": [
    {
      "target_type": "activity",
      "target": "面接対策の相談",
      "valence": 0.4,
      "confidence": 0.5,
      "reason": "相手の将来に関わる相談は意義がある",
      "evidence_kind": "experienced",
      "scope": "situational"
    }
  ],
  "entities": ["面接"],
  "topics": ["仕事", "不安"],
  "relationship_signal": "trust"
}
</oribis-meta>
```

### 9.3 フィールド仕様

**必須フィールド**:

| フィールド | 型 | 説明 |
|-----------|---|------|
| v | int | スキーマバージョン（現在1） |
| event.type | string | EventType enum値 |
| event.salience | float | 0.0〜1.0 |

**推奨フィールド**:

| フィールド | 型 | 説明 |
|-----------|---|------|
| event.confidence | float | LLMの分類確信度 0.0〜1.0 |
| event.valence | float | -1.0〜+1.0 |
| event.arousal | float | 0.0〜1.0 |
| event.novelty | float | 0.0〜1.0 |
| event.future_relevance | bool | 将来の予定に関連するか |
| event.contradicts_memory | bool | 既存記憶と矛盾するか |
| open_loops | array | op: create/update/resolve。update/resolveは`id`必須（既存loop UUID）。createは`id`不要 |
| memory_saves | array | category + value |
| memory_queries | array | 検索語リスト |
| entities | array | 固有名詞・人物 |
| topics | array | トピックタグ |
| relationship_signal | string | trust/repair/affection/boundary/null |
| self_reactions | array | AI自身の主観的評価（§6.5 self_model の evidence 源） |

**self_reactions[] 要素仕様**:

| フィールド | 型 | 説明 |
|-----------|---|------|
| target_type | string | `topic\|style\|activity\|constraint\|tool\|time_pattern\|interaction_pattern` |
| target | string | 評価対象（具体的な名称） |
| valence | float | -1.0（不快）〜 +1.0（快） |
| confidence | float | 0.0〜1.0（評価の確信度） |
| reason | string | 理由（1文） |
| evidence_kind | string | `experienced`（直接体験）\| `inferred`（推論） |
| scope | string | `core`（永続的嗜好）\| `situational`（状況的） |

1ターン = 0..N 件（対象ごとに分離）。ターン全体に1つではなく、ターン内の各対象に個別の評価を付ける。

**null/omit ルール**:
- 推奨フィールドは省略可（パーサーはデフォルト値を適用）
- `open_loops` / `memory_saves` / `memory_queries` は空配列 `[]` を許容（省略も可）
- `entities` / `topics` は省略時は空配列扱い

**event.type の文字列マッピング**:
- JSON文字列はsnake_case: `"user_fact"`, `"preference"`, `"boundary"`, `"emotion"`, `"ritual"`, `"task"`, `"repair"`, `"conflict"`, `"affection"`, `"disclosure"`, `"correction"`, `"smalltalk"`, `"worker_outcome"`
- Rust EventType enum へのマッピング: `serde(rename_all = "snake_case")`

**smalltalk 時の最小payload**:
```json
{"v":1,"event":{"type":"smalltalk","salience":0.1}}
```

### 9.4 パース処理

```rust
pub fn parse_oribis_meta(raw_response: &str) -> Option<OribisMeta> {
    // <oribis-meta> ... </oribis-meta> を抽出
    // JSON パース
    // バリデーション（v=1確認、必須���ィールド存在確認）
    // パース失敗時は None → Rust fallback に委譲
}
```

### 9.5 既存マーカーとの互換

| マーカー | 状態 | 扱い |
|---------|------|------|
| [MEMORY_SAVE:...] | 後方互換維持 | oribis-meta の memory_saves が優先。本文中マーカーも引き続きパース |
| [MEMORY_QUERY:...] | 後方互換維持 | 同上 |
| [AFFINITY:N] | 変更なし | oribis-metaとは独立（本文末尾に継続） |

旧マーカーと oribis-meta の両方が存在する場合、oribis-meta を正とする（重複除外）。

### 9.6 欠落率モニタリング

```rust
pub struct MetaStats {
    pub total_responses: u64,
    pub meta_present: u64,
    pub meta_parse_failures: u64,
    pub fallback_used: u64,
}
```

欠落率が閾値（20%）を超えた場合、L2 Critical Prompt のマーカー指示を強化する判断材料とする。

### 9.7 CLAUDE.md（L1）への追記内容

```
## 構造化メタブロック（毎ターン必須）

応答末尾に <oribis-meta>...</oribis-meta> を出力する。
JSONフォーマット。省略不可。出力できない場合は最低限 {"v":1,"event":{"type":"smalltalk","salience":0.1}} を出力。

含めるべき情報:
- event: 今回のやり取りの分類（type/salience/valence/arousal）
- open_loops: 未解決事項の操作（create/update/resolve）
- memory_saves: 長期記憶に保存すべき情報
- entities/topics: 会話に登場した固有名詞・トピック
- self_reactions: あなた自身が感じたこと（対象・快不快・理由）
```

---

## 10. 実装フェーズ

### Phase 1: 基盤（G1 タスク）

- SQLite初期化（memory.db）
- memory_events テーブル + append_event API
- parse_oribis_meta() + validation/telemetry（主経路）
- classify_event ヒューリスティクス（Rust fallback）
- salience scoring（heuristic + merge_salience）
- pipeline.rs からの即時キャプチャ接続
- 既存 memories.json → SQLite マイグレーション（**G1-e 完了時点で memories.json パスは削除済み**）
- Memory 型に strength/salience/valence 追加
- ContextMode / ReinjectionReason 実装（G1-e）: retrieval.rs（SQLite L3取得）+ context.rs（モード別注入制御）

### Phase 2: 統合

- Level 1 consolidation（ルールベース）
- open_loops テーブル + 基本CRUD
- トリガー実装（5件蓄積/アプリ終了/起動時 + 未統合20件 or 30分タイマー）
- L3 4チャネル検索（profile/open_loops/episodes + self_context。counters は L2 固定注入に移動）
- 忘却曲線適用
- ranking に recency decay 反映

### Phase 3: 深化 + 意味検索 + 自己進化

- Level 2 consolidation（LLM使用・非同期）
- relationship_model 構築・更新（lightweight から開始）
- **self_model 構築**（§6.5）:
  - self_reactions evidence 蓄積 + target 正規化
  - trait 化（閾値: 3件 + 日跨ぎ2回）
  - core/situational 分類 + decay 適用
  - L3 `[あなた自身のこと]` チャネル注入
  - 循環強化防止ガード
- パターン検出
- open_loop 自動解決
- **記憶進化（A-MEM軽量版）**:
  - 矛盾検出 → 古い memory の strength/confidence 低下
  - 反復 → strengthen / promote
  - 関連 memory マージ
- **Operational Memory（Worker進化）**:
  - worker_outcome 記録 + worker_patterns 抽出
  - evidence-based evolution proposal（roles/ 更新提案）
  - regression window 監視
- **軽量エンティティリンク**（§8.6）:
  - entities / event_entities / entity_cooccurrence テーブル構築
  - エンコーディング時: oribis-meta topics/entities → 正規化 → event_entities 紐付け
  - consolidation時: 共起 weight 更新
  - 検索: 1-hop / 2-hop 関連記憶取得 → ランキングに entity_link_score 統合
  - メンテナンス: entities 1000件上限、cooccurrence 5000件上限
- **ハイブリッドベクトル検索**:
  - sqlite-vec 拡張導入
  - ローカル embedding（multilingual-e5 or Ruri v3、CPU動作）
  - memory_events.raw_text + memories.content をベクトル化
  - 検索: FTS5(BM25) + vector similarity + entity_link_score + RRF 統合
  - ranking: semantic_relevance + keyword_overlap + entity_link_score + salience + current_strength + open_loop_boost + recency_decay

---

## 11. Operational Memory（Worker 自己進化）

### 11.1 概要

Workerの品質パイプライン結果を記録し、行動パターンを学習する仕組み。
会話記憶（companion domain）とは**論理分離**し、L3注入には混ぜない。

設計原則:
- **専用 subsystem は不要** — 既存の memory_events + Level 2 consolidation に載せる
- **domain 分離** — `memory_events.domain = 'worker_ops'` で会話記憶と分離
- **evidence-based** — 単発事例では進化提案しない。同パターンK回観測で初めて提案

### 11.2 worker_outcome イベントスキーマ

```rust
/// Worker品質パイプライン完了時に記録
pub struct WorkerOutcomeEvent {
    // memory_events 共通フィールド（domain = "worker_ops"）
    pub department: String,         // "sysdev", "afd", etc.
    pub role: String,               // "lead", "solo", "sub"
    pub task_type: String,          // "feature", "bugfix", "refactor", "security"
    pub verdict: Verdict,           // Pass / Fail / PartialPass
    pub failure_reason: Option<String>,   // DA/reviewer指摘の要約
    pub success_pattern: Option<String>,  // 成功時のパターン要約
    pub artifacts_changed: Vec<String>,   // 変更ファイルパス
    pub human_override: bool,       // Producer が結果を覆したか
    pub workflow_duration_secs: u64,
}

pub enum Verdict {
    Pass,
    Fail,
    PartialPass,  // 条件付き承認
}
```

保存先: `memory_events` テーブル（`domain = 'worker_ops'`, `event_type = 'worker_outcome'`）

### 11.3 worker_patterns テーブル

Level 2 consolidation で worker_outcome から抽出されたパターン記憶。
**conversational memories テーブルとは別テーブル**。

```sql
CREATE TABLE worker_patterns (
    id TEXT PRIMARY KEY,
    department TEXT NOT NULL,
    pattern_type TEXT NOT NULL,    -- 'success' | 'failure' | 'convention' | 'correction'
    content TEXT NOT NULL,         -- パターン要約
    evidence_count INTEGER NOT NULL DEFAULT 1,  -- 裏付け事例数
    source_event_ids TEXT NOT NULL DEFAULT '[]', -- JSON array of memory_events.id
    confidence REAL NOT NULL DEFAULT 0.5,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    applied INTEGER NOT NULL DEFAULT 0  -- roles/に反映済みか
);

CREATE INDEX idx_wp_department ON worker_patterns(department);
CREATE INDEX idx_wp_type ON worker_patterns(pattern_type);
CREATE INDEX idx_wp_confidence ON worker_patterns(confidence DESC);
```

### 11.4 Consolidation（worker_ops 専用パス）

Level 2 consolidation は domain で処理を分岐:

| domain | 入力 | 出力先 | トリガー |
|--------|------|--------|---------|
| companion | memory_events (companion) | memories / relationship_model | 6h + idle + startup |
| worker_ops | memory_events (worker_ops) | worker_patterns | evidence-based（下記参照） |

**worker_ops トリガー条件:**
- 同一 department の未統合 worker_outcome が **5件** 蓄積
- または同一 failure_reason パターンが **3回** 観測
- バックアップ: 24h タイマー（未統合件数 > 0 の場合）

### 11.5 Evolution Proposal（roles/ 更新提案）

worker_patterns から roles/ ファイルへの反映は**提案制**:

```
worker_patterns 蓄積
  → evidence_count >= 3 のパターンが候補
  → Level 2 LLM が diff proposal 生成
  → Anima が Producer に提示（承認待ち）
  → ���認 → Worker に roles/ 更新を委譲
  → applied = 1 にマーク
```

**Safeguards:**

| ルール | 内容 |
|--------|------|
| Evidence threshold | 同種パターン 3回以上でないと提案しない |
| Scope制限 | 1回の提案で変更可能: 1ファイル・10行以内 |
| Protected sections | セキュリティ・権限境界・承認ルールは自動提案対象外 |
| Rollback | roles/ 更新に revision 番号を付与。regression 検出時に自動ロールバック |
| Regression window | 適用後 7日間は同 department の verdict を監視。Fail率上昇で警告 |

### 11.6 L3 注入との関係

- **worker_ops domain のイベントは L3 会話注入に含めない**
- worker_patterns は Anima の Worker ルーティング判断時にのみ参照（内部用）
- ユーザーとの会話に worker 運用情報が漏れることを防ぐ

### 11.7 記憶進化（companion domain 側）

companion domain の自己進化は Level 1/2 consolidation に内包:

**Level 1（micro-evolution, inline）:**
- 矛盾検出 → 古い memory の strength 低下
- confidence 調整（反復確認で上昇）
- open_loop resolve/update
- 反復 preference の reinforcement（strength 上昇）

**Level 2（semantic evolution, background）:**
- 関連 memory のマージ（同一エンティティ・重複内容）
- Pattern → Relationship summary 昇格
- 長期矛盾の解決（複数セッションにまたがる矛盾）
- relationship_model の精緻化

**A-MEM 軽量版:**
新イベント保存時に少数の関連 memories を検索し、以下のいずれかを適用:
- strengthen（同内容の再確認 → strength 上昇）
- supersede（新情報が古い情報を上書き → 古い方の confidence 低下）
- promote（反復 episode → stable pattern/preference に昇格）
- no-op（関連なし）

---

## 11.8 Anima 自己発話ログ（anima_utterance_log）

### 概要

Anima が「自分が何を言ったか」をセッション横断で想起するためのサイドカー運用ログ。
**4レイヤー記憶システムの外側**に位置し、記憶統合パイプラインとは完全に独立。

### 目的

- Cache mode 発話はセッション内 history のみに記録され、セッション終了後に消失する
- AI 生成発話は memory_events に観測記録（oribis-meta）があるが、発話テキスト自体の想起用ではない
- 本テーブルは「Anima が最近何を言ったか」の統一クエリを提供する

### スキーマ

```sql
CREATE TABLE anima_utterance_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,          -- AnimaCategory (greeting, idle, done, etc.)
    phrase TEXT NOT NULL,             -- 発話テキスト
    tier TEXT NOT NULL,              -- AffinityTier (warm, neutral, etc.)
    sub_context_key TEXT,            -- sub_context キー (greeting_morning, etc.)
    source TEXT NOT NULL DEFAULT 'cache',  -- 'cache' | 'ai'（他の値は不正として拒否）
    project_id TEXT,                 -- プロジェクトID（クロスプロジェクト汚染防止）
    session_id TEXT,                 -- セッションID（スコープ絞り込み用）
    created_at TEXT NOT NULL
);
CREATE INDEX idx_utterance_created ON anima_utterance_log(created_at DESC);
CREATE INDEX idx_utterance_source_created ON anima_utterance_log(source, created_at DESC);
```

### 記録対象

| source | 記録タイミング | 備考 |
|--------|--------------|------|
| `cache` | Cache-hit フレーズ返却時 | 全カテゴリ対象 |
| `ai` | AI 生成フレーズ返却時 | memory_events への二重書き込みになるが、記録対象が異なる（下記参照） |

**二重書き込みの整理（AI 生成時）**:
- `memory_events`: ユーザーについて観測したこと（oribis-meta 由来のイベント分類・salience）
- `anima_utterance_log`: Anima が喋ったテキスト（発話想起用）
- 異なる成果物の記録であり、重複ではない
- 書き込みは best-effort（utterance_log 失敗時も memory_events 処理は続行）

### 保持ポリシー

- **上限**: 100 行 or 7 日（古い方から自動削除）
- **削除タイミング**: 新規 INSERT 時に `DELETE FROM anima_utterance_log WHERE created_at < datetime('now', '-7 days') OR id NOT IN (SELECT id FROM anima_utterance_log ORDER BY created_at DESC LIMIT 100)`

### 除外ルール（明示・厳守）

**anima_utterance_log は現時点（Phase 2/3）で以下に一切使用しない:**
- Level 1 / Level 2 consolidation
- build_context_at() / L3 注入（※将来の専用チャネル追加は下記参照）
- rank_for_injection() / 検索ランキング
- ベクトル化 / 意味検索インデックス
- relationship_model / open_loop の推論

参照は「Anima の直近発話一覧」取得のみに限定する。

### 参照方法

```sql
-- 直近5件の自己発話を取得
SELECT phrase, category, source, created_at
FROM anima_utterance_log
ORDER BY created_at DESC
LIMIT 5;
```

**将来拡張（Phase 3 以降の検討事項）**: build_context_at() に専用チャネル（例: `self_utterance_context`）を追加し、直近の自己発話を注入することを検討。上記の除外ルールはこの専用チャネル以外での使用を禁止するものであり、専用チャネル追加時に除外ルールを改訂する。Phase 2 では未実装。

---

## 12. 実装場所

| ファイル | 責務 | ステータス |
|---------|------|-----------|
| `src-tauri/src/anima/memory.rs` | memories CRUD, 忘却曲線, 強度管理 | 既存改修 |
| `src-tauri/src/anima/events.rs` | memory_events append/query, classify_event | 新規 |
| `src-tauri/src/anima/consolidation.rs` | Level 1/2 統合, open_loops管理, worker_ops統合 | 新規 |
| `src-tauri/src/anima/worker_patterns.rs` | worker_patterns CRUD, evolution proposal生成 | 新規 |
| `src-tauri/src/anima/memory_db.rs` | SQLite接続, マイグレーション, スキーマ | 新規 |
| `src-tauri/src/anima/pipeline.rs` | イベントキャプチャ接続 + utterance_log 書き込み | 既存改修 |
| `src-tauri/src/anima/context.rs` | L3 5チャネル検索・注入 | 既存改修 |
| `src-tauri/src/anima/self_model.rs` | self_model CRUD, evidence蓄積, trait化, 循環強化防止 | 新規 |
| `src-tauri/src/anima/entity_link.rs` | entities/event_entities/entity_cooccurrence CRUD, 正規化, 1-hop/2-hop検索 | 新規 |
| `src-tauri/src/anima/utterance_log.rs` | anima_utterance_log CRUD, 自動クリーンアップ | 新規 |

---

## 13. マイグレーション戦略

既存ユーザーデータ（memories.json）からの移行:

> **G1-e 実装ノート**: memories.json への参照パスはコードから削除済み。L3取得は retrieval.rs / SQLite のみ経由。既存の memories.json がある場合は以下の migrate_from_json で一度だけ移行し、以降は memory.db が唯一のストアとなる。

```rust
pub fn migrate_from_json(base_dir: &Path) -> Result<()> {
    let json_path = base_dir.join("memories.json");
    if !json_path.exists() { return Ok(()); }

    let old_memories = load_json::<OldMemoryStore>(&json_path)?;
    for mem in old_memories.memories {
        // Memory型にマッピング（strength=1.0, salience推定, decay_rate=種別判定）
        insert_memory_to_db(&mem)?;
    }
    // 旧ファイルを .bak にリネーム
    rename(json_path, json_path.with_extension("json.bak"))?;
    Ok(())
}
```

---

## 14. パフォーマンス目標

| 処理 | 目標 |
|------|------|
| イベント記録（append） | < 5ms |
| 記憶検索（5チャネル + entity link） | < 50ms |
| エンティティ upsert（エンコーディング時） | < 3ms |
| 1-hop / 2-hop 検索 | < 15ms |
| 共起更新（consolidation時） | < 10ms |
| Level 1 consolidation | < 200ms |
| 忘却曲線計算（全件） | < 100ms |
| L3注入構築 | < 30ms |

---

## 15. 関連ドキュメント

- `markers.md` — MEMORY_SAVE/MEMORY_QUERY マーカー仕様
- `event-counter.md` — 補助レイヤー（イベントカウンタ）
- `anima.md` — IdleLong トリガー元（Level 2 consolidation起点）
- `anima-orchestrator-architecture.md` — Worker品質パイプライン・スケジューラ・roles/構造
- `prompt-layers.md` — L3注入仕様
- `data-storage.md` — ストレージ全体マップ
- `architecture-diagrams.md` §8 — 記憶システムフロー図

*作成日: 2026-04-28 / 改訂: 2026-05-06*
