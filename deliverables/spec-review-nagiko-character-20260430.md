# Nagiko Character System — Spec vs Implementation レビュー報告書

**作成日**: 2026-04-30
**対象**: `docs/spec/files/` 全12ファイル + `src-tauri/src/character/` 全14ファイル
**作成**: SysDev DIR

---

## エグゼクティブサマリー

| 評価 | 内容 |
|------|------|
| 全体カバレッジ | 約70%（コアモジュールは高く、Anima/パイプライン周辺は低い） |
| クリティカル乖離 | 3件（AnimaMode::Ai未実装・history.jsonlパス不整合・session_id未継続） |
| 設計上の欠陥候補 | 2件（ANIMA必須フィールド・spec命名/実装命名不一致） |
| 未実装Phase | session journal（Phase1）・batch distillation（Phase3） |

---

## 1. モジュール別乖離一覧

### 1.1 affinity.rs ✅ ほぼ一致

| 項目 | spec | 実装 | 判定 |
|------|------|------|------|
| 型 | `i32` | `i16` | ⚠️ 型不一致（範囲は問題なし） |
| 初期値 | +50 | +50 | ✅ |
| 最大delta | ±5 | ±5 | ✅ |
| Tier境界 | 6段階（spec定義） | 一致 | ✅ |
| パス | `~/.config/oribis/nagiko/affinity.json` | `base_dir/oribis/nagiko/affinity.json` | ✅ |
| API | `load_affinity_at` / `apply_delta_at` | 一致 | ✅ |
| 履歴上限 | 100件 | 100件 | ✅ |

**指摘**: `i32` vs `i16` は機能的に無問題だが、spec記述との不一致なので更新推奨。

---

### 1.2 anima.rs / cache.rs / throttle.rs ⚠️ 部分実装

**AnimaCategory（anima.rs）**: 13カテゴリ全実装。`parse_anima_notification()` スペース有無両対応 → ✅

**AnimaMode（cache.rs）**: 🔴 **クリティカル**

| AnimaMode | spec | 実装 | 判定 |
|-----------|------|------|------|
| Cache | キャッシュのみ返却 | ✅ `extract_with_fallback()` | ✅ |
| Ai | 全レスポンスLLM生成 | ❌ **未実装** | 🔴 |
| Hybrid | キャッシュ→なければAI | ✅ フォールバック動作あり | ✅ |

- `anima_mode.toml` 読み込み: **未実装**（PipelineConfigにanima_modeフィールドなし）
- `compute_sub_context()`: spec-anima.md §6に記載あるが**コード内に存在しない**

**Throttle（throttle.rs）**: ✅ ロジック実装済み。デフォルト設定は外部から渡す設計のため問題なし。

---

### 1.3 history.rs 🔴 パス設計不整合

**最重要問題**:

| 項目 | spec（更新後） | 実装 | 判定 |
|------|------|------|------|
| パス | `~/.config/oribis/projects/{project_id}/history.jsonl` | `base_dir/oribis/nagiko/history.jsonl`（グローバル固定） | 🔴 **不一致** |

→ spec-session-data.md がper-project化されたが、実装はグローバルのまま。
→ **波及**: context.rs の `load_recent_messages_at(base_dir, 30)` も project_id を渡していない。

**MessageSource 命名差異**:

| spec | 実装 | 判定 |
|------|------|------|
| `NagikoMain` | `CharacterMain` | ⚠️ 命名不一致 |
| `NagikoAnima` | `CharacterAnima { category: AnimaCategory }` | ⚠️ 命名+型差異 |

→ JSONLシリアライズ時のフィールド名が異なるため、spec記載のサンプルJSONと互換なし。

**UnifiedMessage フィールド差異**:

| spec | 実装 | 判定 |
|------|------|------|
| `ts: DateTime<Utc>` | `timestamp: DateTime<Utc>` | ⚠️ フィールド名不一致 |
| （なし） | `contains_code: bool` | ⚠️ spec未記載の追加フィールド |

**API命名差異**:

| spec | 実装 | 判定 |
|------|------|------|
| `recent_messages_at` | `get_recent_at` | ⚠️ |
| `history_search_at` | `search_at` | ⚠️ |
| `append_message_at` | 一致 | ✅ |
| `compress_at` | 一致 | ✅ |

---

### 1.4 pipeline.rs 🔴 2件のクリティカル乖離

**A. PipelineConfig に `anima_mode` フィールドなし**

spec §4:
```rust
pub struct PipelineConfig {
    pub base_dir: PathBuf,
    pub project_id: String,
    pub backend: String,
    pub anima_mode: AnimaMode,  // ← 実装に存在しない
}
```
→ AnimaMode::Ai ロジックが実装不可状態。

**B. session_id 常時 None（セッション継続なし）**

spec §8.9: "継続時は前ターンのIDを渡す"

実装（chat/anima両パイプライン）:
```rust
let prompt = Prompt {
    ...
    session_id: None,  // ← ハードコード
};
```
→ CLIコンテキスト継続がなく、毎ターン新規セッション扱い。
→ これは lib.rs の `PersistentProc` が `.last_session_id` ファイルで session_id を管理しているが、pipeline.rs はそれを使っていない（pipeline.rsはstubアダプターを使う前提のため）。

**C. `event_to_llm_input` フォーマット差異**

| spec | 実装 |
|------|------|
| `[システム通知: working (処理中)]`（同行・括弧） | `[システム通知: working]\n処理中`（改行区切り） |

軽微だが一貫性上の問題。

---

### 1.5 context.rs ⚠️ spec外の追加実装あり

spec未記載だが実装に存在する機能:

| 機能 | 詳細 | 評価 |
|------|------|------|
| OpenClaw backend | `load_openclaw_agents_md()` (SOUL/agent/USER.md) | ⚠️ spec外 |
| GUIペルソナfallback | `load_persona_system_prompt()` (projects.json) | ⚠️ spec外（有用） |
| `.charactor/CHARACTOR.md` 優先 | specはCLAUDE.mdのみ記載 | ⚠️ spec外（有用） |
| `session_start.flag` | セッション初回判定ファイル | ⚠️ spec外（動作は正しい） |

→ 機能的には問題ないが、specに「実装済み拡張」として追記が必要。

---

### 1.6 memory.rs ✅（コア）+ 🔴 journal未実装

**コアメモリ**: 100%実装。`memory_save_with_category` / `memory_search` / pending results → ✅
**spec外追加**: `ClaudeMemoryBackend` / `CodexMemoryBackend` — 設計良好。

**Session Journal（journal.rs）**: 🔴 **未実装**

spec-anima.md §9（B-plan）に記載:
- ファイル: `~/.config/oribis/nagiko/session_journal.txt`
- フォーマット: `{HH:MM} {category} → "{phrase}"`
- 上限: 50件 / 7日ローリング

→ コードに `journal.rs` 自体が存在しない。pipeline.rsから呼び出し箇所もなし。

**Batch Distillation**: Phase3（明示的延期）→ 問題なし。

---

### 1.7 counter.rs ⚠️ 数値不一致

| 項目 | spec | 実装 | 判定 |
|------|------|------|------|
| `recent_dates` 上限 | 100件 | **20件** | ⚠️ 不一致 |
| カテゴリ9種 | 定義あり | 実行時に動的作成 | ✅ |
| `format_counters_for_prompt_at()` | `[行動カウンタ]`フォーマット | ✅ | ✅ |

---

### 1.8 parser.rs ⚠️ ANIMAフィールド全必須

spec-markers.md: `[ANIMA:expression=<name>,intensity=<float>,motion=<name>,gaze=<dir>]`
各フィールドは "可"（オプション）と記載。

実装 regex:
```rust
r"\[ANIMA:expression=([a-z]+),intensity=([0-9.]+),motion=([a-z]+),gaze=([a-z]+)\]"
```
→ **全4フィールド必須・固定順序**。LLMが部分マーカーを出力すると無視される。

`[ANIMA:expression=happy]` のような部分マーカー → パース失敗 → fallbackテーブル使用。
→ LLMに4フィールド全部出力を強制するL1/L2 prompt記述があれば実用上問題なし。
→ ただしspec記述との矛盾は要解消。

---

### 1.9 task.rs / db.rs / affinity.rs / throttle.rs ✅ 一致

- task.rs: パス・型・API名すべてspec通り。`execute_task_operations_at()` 追加あり（テスト用）
- db.rs: `ensure_*_dir()` / `atomic_write_json()` / プロジェクトID検証 → ✅
- throttle.rs: `should_speak_at()` / `update_throttle_state_at()` → ✅

---

## 2. 設計上の潜在的欠陥

### 2.1 history.jsonl のプロジェクト横断汚染

**現状**: グローバルパス1本 → 複数プロジェクト間でチャット履歴が混在。
**例**: project-A の会話がproject-Bのセッション開始時L3注入に混入する。
**必要修正**: `history_path(base_dir, project_id)` へ変更 + context.rs の呼び出し側修正。

### 2.2 session_id 断絶によるCLIコンテキスト損失

**現状**: pipeline.rs が `session_id: None` を毎ターン渡す → CLIは毎回コンテキストゼロから開始。
**本来**: lib.rs の `PersistentProc` が管理する session_id をpipelineに注入すべき。
**回避策の競合**: lib.rs (`character_chat` Tauriコマンド) は現状 `ClaudeCliAdapter` を経由せず直接 `PersistentProc` を呼んでいる可能性が高い → pipeline.rs は実質未使用。この設計分岐を整理する必要あり。

### 2.3 AnimaMode::Ai の欠如によるフィードバックループ断絶

**現状**: カウンター・ジャーナル・メモリが蓄積されても、Animaがキャッシュフォールバックのみでは活用されない。
**Spec記載**: "AnimaMode::Ai移行（最優先・これがなければ何も意味ない）"
**影響**: Phase3 batch distillation のトリガー（IdleLong→AI処理）も動作しない。

### 2.4 MessageSource 命名のJSONL下位互換問題

既にデプロイ・テスト済みのJSONLファイルが存在する場合、`CharacterMain`→`NagikoMain`へのリネームは破壊的変更。
→ マイグレーション戦略またはserde alias対応が必要。

---

## 3. spec記載漏れ・内部不整合

| 箇所 | 内容 |
|------|------|
| spec-session-data.md §2.3 | `new_anima()` コンストラクタ: spec は引数なし(category内包なし)だが実装は `category: AnimaCategory` 引数あり |
| spec-session-data.md §2.2 | `NagikoAnima` に category フィールドなし（実装にはある） |
| spec-pipeline.md §5.3 | history注入がセッション開始時のみという仕様が context.rs に `session_start.flag` 機構で実装されているが、spec-pipeline.md にフラグファイルの記述なし |
| spec-anima.md §7 | `anima_mode.toml` ファイル仕様（パス・フォーマット）の詳細記載なし |
| spec-data-storage.md | `session_start.flag` パス・ライフサイクルの記載なし |
| spec-memory.md §5 | OpenClaw/Codex Markdownバックエンドの記載なし |
| spec-overview.md | `CHARACTOR.md` / `.charactor/` ディレクトリ未記載 |

---

## 4. 優先度別対応リスト

### 🔴 Priority 1（実装整合・即対応）

| # | 内容 | ファイル |
|---|------|--------|
| P1-1 | history.jsonl パスをper-project化（`nagiko/` → `projects/{id}/`） | history.rs + context.rs |
| P1-2 | PipelineConfig に `anima_mode: AnimaMode` 追加、animaパイプラインで分岐 | pipeline.rs |
| P1-3 | AnimaMode::Ai 実装（LLM呼出フロー） | pipeline.rs + cli_adapter.rs |

### ⚠️ Priority 2（spec整合・品質向上）

| # | 内容 | ファイル |
|---|------|--------|
| P2-1 | session_id 継続設計（PipelineConfigまたは呼出元から渡す） | pipeline.rs |
| P2-2 | MessageSource命名を spec 通り `NagikoMain` / `NagikoAnima` に変更（マイグレーション要検討） | history.rs |
| P2-3 | ANIMAパーサーをオプションフィールド対応に修正 | parser.rs |
| P2-4 | event_counter recent_dates 上限 20 → 100 | counter.rs |
| P2-5 | `event_to_llm_input` フォーマット spec 通りに修正 | pipeline.rs |

### 🟠 Priority 3（spec補完・ドキュメント）

| # | 内容 | ファイル |
|---|------|--------|
| P3-1 | session journal (journal.rs) 実装 | 新規 |
| P3-2 | spec-session-data.md: `new_anima()` シグネチャ・MessageSource フィールド修正 | spec更新 |
| P3-3 | spec-pipeline.md: session_start.flag 機構を記述追加 | spec更新 |
| P3-4 | spec-data-storage.md: session_start.flag パス追記 | spec更新 |
| P3-5 | spec-overview.md / spec-memory.md: 追加実装（CHARACTOR.md・OpenClaw backend）を記述 | spec更新 |
| P3-6 | spec-anima.md: anima_mode.toml フォーマット詳細記述 | spec更新 |

### 🔵 Priority 4（将来・Phase3）

| # | 内容 |
|---|------|
| P4-1 | Batch distillation (distillation.rs) 実装 |
| P4-2 | affinity 型 `i16` → `i32` のspec更新（または実装修正） |

---

## 5. lib.rs との設計分岐について（補足）

`character_chat` Tauri コマンド（lib.rs）は `PersistentProc` を直接使用しており、
`pipeline.rs` の `execute_pipeline()` / `CliAdapter` トレイトを**現状バイパスしている**可能性が高い。
→ 将来的に pipeline.rs の `ClaudeCliAdapter` stub を実装する際、lib.rs との役割分担を
  明確化（lib.rs が pipeline.rs を呼ぶ or pipeline.rs が PersistentProc を内包）する設計決定が必要。

---

*End of Report*
