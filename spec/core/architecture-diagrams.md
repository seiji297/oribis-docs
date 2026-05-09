# Anima / Oribis アーキテクチャ図

Phase 1 統合実装の全体像。

---

## 1. 全体アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                     Frontend (React/TS)                     │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐               │
│  │ ChatUI   │  │useAnima  │  │AvatarViewer  │               │
│  └────┬─────┘  └────┬─────┘  └──────────────┘               │
│       │             │                                       │
└───────┼─────────────┼───────────────────────────────────────┘
        │             │  Tauri Events
        ↓             ↓
┌─────────────────────────────────────────────────────────────┐
│                    Backend (Rust)                           │
│                                                             │
│  ┌─────────────────────────────────────────────┐            │
│  │ 統一応答パイプライン                          │            │
│  │                                             │            │
│  │  イベント → モード判定 → 発火制御 →         │            │
│  │  コンテキスト構築 → CLI Adapter →           │            │
│  │  マーカーパース → 副作用適用                │            │
│  └─────────────────────────────────────────────┘            │
│                                                             │
│  ┌─────────────────────────────────────────────┐            │
│  │ CLI Adapter Layer                           │            │
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐       │            │
│  │  │ Claude  │ │ Codex   │ │ Local    │       │            │
│  │  │ Adapter │ │ Adapter │ │ Adapter  │       │            │
│  │  └─────────┘ └─────────┘ └──────────┘       │            │
│  └─────────────────────────────────────────────┘            │
│                                                             │
│  ┌─────────────────────────────────────────────┐            │
│  │ データ層                                     │            │
│  │  好感度 / 履歴 / 記憶 / カウンタ / タスク     │            │
│  └─────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────┘
        │             │             │
        ↓             ↓             ↓
┌─────────────────────────────────────────────────────────────┐
│              ストレージ                                      │
│                                                             │
│  ~/.config/oribis/anima/   （ユーザー全体）                 │
│    CLAUDE.md                                                │
│    critical_prompt.txt                                      │
│    affinity.json                                            │
│    history.jsonl                                            │
│    memory.db (SQLite)                                       │
│    event_counters.json                                      │
│    throttle_state.json                                      │
│    anima_cache/{category}_{tier}.json                       │
│                                                             │
│  ~/.config/oribis/projects/{project_id}/  （プロジェクト別） │
│    tasks.json                                               │
│                                                             │
│  ~/.config/oribis/                                          │
│    anima_mode.toml                                          │
│    throttle.toml                                            │
│    event_counter_config.toml                                │
│    projects.toml                                            │
└─────────────────────────────────────────────────────────────┘
        │
        ↓
┌─────────────────────────────────────────────────────────────┐
│                    LLM Providers                            │
│                                                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐             │
│  │ Claude CLI │  │ Codex CLI  │  │ Local LLM  │             │
│  │ (claude)   │  │ (codex)    │  │ (Qwen等)   │             │
│  └────────────┘  └────────────┘  └────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. プロンプト三層構造

```
┌────────────────────────────────────────┐
│  L1: CLAUDE.md（システムプロンプト）    │
│                                        │
│  - キャラ基本情報                       │
│  - 性格・口調・口癖                     │
│  - 出力形式（全マーカー仕様）           │
│  - ツール使用ルール                     │
│  - 好感度段階表                        │
│                                        │
│  サイズ: 〜2000トークン                 │
│  送信: 初回1回（API キャッシュ対象）   │
└────────────────────────────────────────┘
                ↓
┌────────────────────────────────────────┐
│  L2: Critical Prompt（毎ターン）        │
│                                        │
│  - 名前・属性                          │
│  - 一人称・二人称                       │
│  - 業務分離原則                         │
│  - マーカー指示                        │
│  - ツール呼出の自然性指示               │
│                                        │
│  サイズ: 〜130トークン                  │
│  送信: 毎ターン（キャラ忘却防止）       │
└────────────────────────────────────────┘
                ↓
┌────────────────────────────────────────┐
│  L3: 動的注入（毎ターン）               │
│                                        │
│  毎ターン:                              │
│  [好感度: +63（良好）]                  │
│  [現在時刻: 2026-04-26 23:45 月曜]      │
│  [進行中タスク]                        │
│  - [in_progress] AFDバグ修正           │
│                                        │
│  該当時のみ:                            │
│  [行動カウンタ]（直近7日変動あり）      │
│  [記憶検索結果]（前ターンMEMORY_QUERY時）│
│                                        │
│  セッション開始時のみ:                   │
│  [これまでの会話]（直近30件）           │
│                                        │
│  サイズ: 100〜2000トークン             │
└────────────────────────────────────────┘
```

---

## 3. 統一応答パイプライン詳細

```
[入力イベント]
       │
       ├─ chat-send → InputEvent::UserMessage
       └─ システム検知 → InputEvent::AnimaState
       │
       ↓
[スクリプト: イベント正規化]
  - 統一フォーマットに変換
       │
       ↓
[スクリプト: モード判定]
  - anima_mode.toml 参照
  - カテゴリ別 ai/cache/hybrid
       │
   ┌──┴──┐
   ↓     ↓
[Cache] [AI/Hybrid]
   │     │
   │     ↓
   │  [スクリプト: 発火制御]
   │  - throttle.toml 参照
   │  - 確率 + クールダウン
   │     ↓ pass
   │  [スクリプト: コンテキスト構築]
   │  - L1 CLAUDE.md
   │  - L2 Critical Prompt
   │  - L3 動的注入
   │  - 履歴（セッション開始時のみ）
   │     ↓
   │  [CLI Adapter経由で LLM呼出]
   │  - claude / codex / local 切替
   │  - ストリーミング: mpsc::Sender<StreamChunk> 経由
   │     ↓
   │  [フロント: ストリーミング表示]
   │  - '[' 検知でバッファ開始
   │  - 100ms以内に ']' なければ通常テキスト表示
   │  - ストリーム完了後に確定パース（マーカー除去）
   │     ↓
   │  [スクリプト: マーカーパース]
   │  - AFFINITY 抽出
   │  - ANIMA 抽出
   │  - TASK 操作リスト
   │  - MEMORY_SAVE リスト
   │  - MEMORY_QUERY リスト
   │     ↓
   │  [失敗] → Cache フォールバック
   │     ↓ 成功
[スクリプト: 副作用適用]
  - 好感度更新
  - タスク操作実行
  - 記憶保存
  - 記憶検索（次ターン用）
  - 履歴追加
  - イベントカウンタ更新
       │
       ↓
[スクリプト: 出力振り分け]
  - ANIMAマーカーあり → 3Dビュー（Anima応答）
  - ANIMAマーカーなし → チャット欄（メイン応答）
       │
       ↓
[表示・TTS・アバター制御]
```

---

## 4. CLI Adapter抽象化

```
┌─────────────────────────┐
│ Pipeline (上位)          │
│  Prompt 構築             │
│  Adapter経由で呼出       │
│  RawResponse 受信        │
└─────────────┬───────────┘
              ↓
┌─────────────────────────┐
│ CliAdapter trait         │
│  - send_message          │
│  - send_message_streaming│
└─────────────┬───────────┘
              ↓
   ┌──────────┼──────────┐
   ↓          ↓          ↓
┌──────┐  ┌──────┐  ┌──────┐
│Claude│  │Codex │  │Local │
│CLI   │  │CLI   │  │LLM   │
└──┬───┘  └──┬───┘  └──┬───┘
   ↓         ↓         ↓
[claude]  [codex]   [HTTP]
process   process   request

各Adapter:
- 固有引数の管理
- ストリーミング処理
- セッション継続管理
- エラーハンドリング
```

---

## 5. データ管理範囲

```
ユーザー全体管理
├── 好感度（affinity.json）
├── 履歴（history.jsonl）
├── 記憶システム（memory.db — SQLite: events/memories/open_loops/relationship_model）
├── イベントカウンタ（event_counters.json）
├── 発火制御状態（throttle_state.json）
├── キャラ定義（CLAUDE.md）
├── Critical Prompt
└── キャッシュ（anima_cache/）

プロジェクト別管理
├── タスク（tasks.json）
├── ProjectMeta（projects.toml内）
└── プロジェクト固有CLAUDE.md（オプション上書き）

セッション管理（CLI側）
├── セッション内コンテキスト
└── 作業中の文脈
```

---

## 6. マーカー処理フロー

```
LLM応答受信
       │
       ↓
正規表現マッチング
       │
   ┌───┴───┬───────┬───────┬───────┬───────┐
   ↓       ↓       ↓       ↓       ↓       ↓
AFFINITY ANIMA  TASK  MEMORY MEMORY  display
                       _SAVE _QUERY  _text
   │       │      │      │      │      │
   ↓       ↓      ↓      ↓      ↓      ↓
delta反映 アバター タスク 記憶  検索   ユーザー
        制御適用 操作  保存  予約   表示
   │       │      │      │      │      │
   ↓       ↓      ↓      ↓      ↓      ↓
affinity 3Dビュー task   memory  次ター 表示先
.json   制御     .json  .json  ンL3   振り分け
```

---

## 7. 好感度更新フロー

```
LLM応答受信
   │
   ↓
[AFFINITY:N] 抽出
   │
   ├─ マッチなし → delta=0
   ├─ 範囲外 → ±5にクランプ
   └─ 正常 → そのまま
        │
        ↓
apply_delta(delta, reason)
   │
   ├─ 現在値 + delta
   ├─ -100 〜 +100 でクランプ
   ├─ 履歴に記録
   └─ 永続化（アトミック書込）
        │
        ↓
   tier 変化検知
        │
        ├─ 変化なし → 終了
        └─ 変化あり
             ↓
        該当tierキャッシュ再生成（バックグラウンド）
```

---

## 8. 記憶システムフロー（v3.1 — 4レイヤー + Operational Memory）

```
[エンコーディング（毎ターン — companion domain）]
LLM応答完了
   ↓
parse_oribis_meta() — 末尾 <oribis-meta> ブロック解析
   ↓ (存在時: LLM主導)         ↓ (欠落時: Rust fallback)
event_type/salience取得        classify_event_heuristic()
   ↓                            ↓
merge_salience(llm, rust) → final_salience
   ↓ (>= 0.2)
memory_events に append（SQLite, domain='companion'）
   ↓
open_loops 処理（create/update/resolve — id or topic/entity Jaccard マッチ）
   ↓
memory_saves → memories テーブル直接保存

[Worker完了時 — worker_ops domain]
Worker品質パイプライン完了（DA PASS/FAIL）
   ↓
memory_events に append（domain='worker_ops', event_type='worker_outcome'）
   metadata: {department, role, task_type, verdict, failure_reason, ...}

[Consolidation]
companion:
  Level 1（Rust・ルールベース）: 5件蓄積/20件/30分/app終了/起動時
     → 重複マージ、strength更新、open_loop生成
     → micro-evolution: 矛盾検出、confidence調整、reinforcement
  Level 2（LLM・非同期）: 6h/IdleLong/起動時backlog
     → 意味的記憶生成、relationship_model更新
     → semantic-evolution: memory merge、pattern promote、A-MEM軽量版

worker_ops:
  Level 2（evidence-based）: 同dept 5件蓄積 / 同failure 3回 / 24hバックアップ
     → worker_patterns テーブルへ抽出
     → evidence_count >= 3 で evolution proposal 生成（Producer承認制）

[検索・L3注入（毎ターン — companion のみ）]
build_context_at() 実行
   ↓
4チャネル検索:
  - profile: memories (CoreIdentity/Preference/Boundary/Skill) + relationship_model 上位5件
  - open_loops: 未解決・priority上位3件
  - episodes: memory_events (topic/entity重複) 上位3件
  - counters: 変動カテゴリのみ
   ↓
L3に注入（token budget制: hard cap 170トークン）
※ worker_ops はL3に注入しない（Animaルーティング判断時のみ内部参照）
```

---

## 9. イベントカウンタフロー

```
Animaイベント発火
   │
   ↓
カテゴリ判定（lewd/all_nighter等）
   │
   ├─ 対象外 → 通常Anima処理のみ
   └─ 対象 → カウンタ更新
        │
        ↓
event_counters.json 読込
   │
   ↓
該当カテゴリの:
  - total_count++
  - recent_dates に追加
  - last_occurrence 更新
   │
   ↓
recent_30days, recent_7days 再計算
   │
   ↓
永続化
   │
   ↓
次ターンのL3構築時:
  recent_7days > 0 のカテゴリのみ注入
```

---

## 10. タスク管理フロー

```
LLM応答に [TASK:add:title:pending]
   │
   ↓
スクリプト検知
   │
   ↓
TaskOperation::Add { title, status }
   │
   ↓
tasks.json 読込
   │
   ↓
新規Task追加 / 既存更新 / 完了 / 削除
   │
   ↓
永続化
   │
   ↓
UI更新（Tauriイベント発行）
   │
   ↓
次ターンのL3構築時:
  進行中タスクをフォーマットして注入
```

---

## 11. AI/Cache/Hybrid モード切替

```
カテゴリ別モード設定
   │
   ├─ AI Mode
   │   │
   │   ├─ 発火制御チェック
   │   │   └─ 失敗 → スキップ
   │   │
   │   ├─ コンテキスト構築
   │   ├─ CLI Adapter経由でLLM呼出
   │   └─ マーカーパース → 副作用適用
   │
   ├─ Cache Mode
   │   │
   │   ├─ 現在tier取得
   │   ├─ {category}_{tier}.json 読込
   │   ├─ ランダム抽出（直前回避）
   │   └─ 履歴追加（マーカーなし）
   │
   └─ Hybrid Mode
       │
       ├─ AI Mode 試行
       │   ├─ 成功 → 使用
       │   └─ 失敗
       │       ↓
       └─ Cache Mode フォールバック
            └─ 失敗
                ↓
       既存FALLBACKテーブル（最終手段）
```

---

## 12. メインチャット応答シーケンス

```
ユーザー
   │
   │ 「ビルドして」
   ↓
Frontend (chat-send)
   │
   ↓
Backend (pipeline実行)
   │
   ├─ 1. InputEvent::UserMessage 構築
   ├─ 2. Mode判定（メインは常にAI）
   ├─ 3. コンテキスト構築
   │   - L1: CLAUDE.md（キャッシュ）
   │   - L2: Critical Prompt
   │   - L3: 好感度・時刻・タスク
   ├─ 4. CLI Adapter経由でLLM呼出
   │   ↓
   │   ストリーミング応答受信
   │   chat-stream-text-{pid} 発行
   │
   ├─ 5. 完了時
   │   - マーカー抽出
   │   - 好感度更新
   │   - タスク操作実行
   │   - 記憶保存（あれば）
   │   - 履歴追加（AnimaMain）
   │
   └─ 6. chat-stream-end-{pid} 発行
        ペイロード: {
          finalText, affinityDelta, affinityValue,
          taskUpdates, memoryOperations
        }
   ↓
Frontend
   │
   ├─ messagesByProject に追加
   ├─ UI更新（タスク・好感度等）
   └─ アバター制御（メインチャットは ANIMAマーカーなしの想定）
```

---

## 13. Anima応答シーケンス

```
状態変化検知（カメラ・プレゼンス・ツール実行）
   │
   ↓
useAnima → Backend
   │
   ↓
Backend (pipeline実行)
   │
   ├─ 1. InputEvent::AnimaState 構築
   ├─ 2. Mode判定（カテゴリ別）
   │
   ├─ 3. 発火制御チェック
   │   - クールダウン確認
   │   - 確率判定
   │   ↓ pass
   │
   ├─ 4. コンテキスト構築（メインと同じ）
   │
   ├─ 5. AI: CLI Adapter経由でLLM呼出
   │   Cache: キャッシュから抽出
   │   ↓
   │   応答: 「品がないですよ\n\n[ANIMA:...]\n[AFFINITY:-1]」
   │
   ├─ 6. マーカー抽出
   │   - ANIMA → ControlAvatarPayload
   │   - AFFINITY → delta=-1
   │   - text → 「品がないですよ」
   │
   ├─ 7. 履歴追加（AnimaAutonomous(Lewd)）
   ├─ 8. イベントカウンタ更新（lewd: +1）
   │
   └─ 9. Tauriイベント発行
        - control-avatar
        - anima-speech-text
   ↓
Frontend
   │
   ├─ AvatarViewer 表情・モーション更新
   └─ TTS再生（必要時）
```

---

## 14. データフロー全体図

```
[Project Settings]               [Runtime State]
projects.toml                    ~/.config/oribis/anima/
  - critical_prompt              ~/.config/oribis/projects/
  - persona/avatar/tts           ~/.config/oribis/anima_*

         ↓                              ↓
         │                              │
         └──────────┬───────────────────┘
                    ↓
          ┌──────────────────────┐
          │  Context Builder     │
          │  - L1 + L2 + L3      │
          │  - 履歴整形          │
          │  - カウンタ抽出      │
          └──────────┬───────────┘
                     ↓
          ┌──────────────────────┐
          │  Pipeline Executor   │
          │  - Mode判定          │
          │  - 発火制御          │
          │  - LLM/Cache実行     │
          │  - パース            │
          └──────────┬───────────┘
                     ↓
          ┌──────────────────────┐
          │  Output Dispatcher   │
          │  - 表示              │
          │  - アバター制御      │
          │  - TTS              │
          │  - 履歴追加          │
          │  - 好感度更新        │
          │  - タスク更新        │
          │  - 記憶操作          │
          │  - カウンタ更新      │
          └──────────────────────┘
```

---

## 15. レイヤー責任分離

```
┌─────────────────────────────────────────┐
│ 表現層（LLM）                            │
│  - セリフ生成                            │
│  - アバター制御選択                      │
│  - トーン調整                            │
│  - 記憶判断・タスク判断                  │
└─────────────────────────────────────────┘
              ↑ 結果のみ
┌─────────────────────────────────────────┐
│ 制御層（スクリプト）                      │
│  - モード判定                            │
│  - 発火制御                              │
│  - フォールバック                         │
│  - リトライ                              │
│  - マーカーパース・副作用適用              │
└─────────────────────────────────────────┘
              ↑ 状態取得・更新
┌─────────────────────────────────────────┐
│ データ層（スクリプト）                    │
│  - 好感度永続化                          │
│  - 履歴永続化                            │
│  - 記憶永続化                            │
│  - カウンタ管理                          │
│  - タスク管理                            │
│  - キャッシュ管理                         │
└─────────────────────────────────────────┘
              ↑
┌─────────────────────────────────────────┐
│ アダプタ層（CLI抽象化）                   │
│  - Claude / Codex / Local                │
└─────────────────────────────────────────┘
```

業務分離原則: 全層で「業務応答品質」は状態に依存しない。

---

## 16. Phase 拡張時の追加ポイント

```
Phase 2: 入力ルーティング
  追加位置: 「イベント正規化」と「モード判定」の間
  既存への影響: 最小（intent等を追加情報として渡す）

Phase 2: PC状態
  追加位置: 「コンテキスト構築」内のL3生成時
  既存への影響: 最小（L3に項目追加）

Phase 3: 自発発話
  追加位置: 「Anima応答」と並列、新規イベントタイプ
  既存への影響: 最小（イベント追加）
```

---

**改訂履歴**

| バージョン | 日付 | 変更内容 |
|---|---|---|
| 1.0 | 2026-04-26 | 初版 |
| 2.0 | 2026-04-26 | 統一パイプライン版 |
| 3.0 | 2026-04-26 | CLI Adapter・記憶・カウンタ・タスク追加 |
| 3.1 | 2026-04-26 | §3: ストリーミングバッファリング注記追加（C-3対応） |
