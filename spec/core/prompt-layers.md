# プロンプト三層構造 設計書

**バージョン**: 1.4（L1/L2正規パス統一）
**最終更新**: 2026-05-07

---

## 1. 構造概要

| 層 | 内容 | 送信頻度 | 目的 |
|---|---|---|---|
| L1: CLAUDE.md | フル設定 | 初回1回（API キャッシュ対象） | 完全な指示書 |
| L2: Critical Prompt | 圧縮された核 | 毎ターン | キャラ忘却防止 |
| L3: 動的注入 | 状態値 | 毎ターン | リアルタイム状態伝達 |

---

## 2. L1: CLAUDE.md

- 永続的な完全定義
- システムプロンプト位置に配置
- 共通ベース + プロジェクト固有上書き対応

**保存先**:
- `~/.oribis/roles/orchestrator/prompts/ANIMA.md`（正規パス）
- `{project_path}/.claude/CLAUDE.md`（プロジェクト固有上書き）

**サイズ目標**: 〜2000トークン
**APIキャッシュ対象**: 初回1回送信後はキャッシュ → 実コスト 1/10程度

**含む内容**:
- キャラ基本情報・外見・性格・口調
- 出力形式（全マーカー仕様）
- ツール使用ルール
- 好感度段階表
- 口癖・好み・苦手
- 応答方針・禁止事項

---

## 3. L2: Critical Prompt

- L1の圧縮版（核のみ）
- 長会話でL1の影響が薄まる対策
- 内容固定（毎ターン同一文字列）

**保存先**: `~/.oribis/roles/orchestrator/prompts/l2.md`

**サイズ目標**: 〜100〜130トークン

**含む内容**:
- 名前・属性
- 一人称・二人称
- 業務分離原則
- マーカー指示
- ツール呼出の自然性指示

---

## 4. L3: 動的注入

**毎ターン注入（固定）**:
- 好感度値
- 現在時刻・曜日
- 進行中タスク一覧
- `[行動カウンタ]` — 直近7日に変動があったカテゴリ（L2注入として毎ターン注入、L3チャネルから分離）

**4チャネル記憶注入（ContextMode依存・budget制）**:

注入量は `ContextMode` と `ReinjectionReason` の組み合わせで決まる:

| ContextMode | ReinjectionReason | 注入内容 |
|-------------|-------------------|---------|
| StatefulSession | NormalTurn | episodes のみ（他チャネルは既にコンテキスト窓内） |
| StatefulSession | SessionStart / AfterCompaction | 全4チャネル + 履歴30件 |
| StatelessRequest | NormalTurn / SessionStart | 全4チャネル + 履歴30件（毎ターン） |

全4チャネル注入時の内容:
- `[あなたが覚えていること]` — profile memories（CoreIdentity/Preference/Boundary）上位5件
- `[気にかけていること]` — open_loops 未解決・priority上位3件
- `[最近の出来事]` — relevant_episodes（topic/entity重複）上位3件
- `[あなた自身のこと]` — self_model の高confidence trait（現在トピックに関連する場合のみ・2〜4件）

**token budget制（動的配分方式）**:

| チャネル | 基本 budget | 1項目あたり |
|---------|------------|-----------|
| profile | 45トークン | 1行短文（10トークン以内） |
| open_loops | 30トークン | 1行短文 |
| episodes | 25トークン | 1行短文 |
| self_context | 20トークン | 1行短文（関連時のみ。無関連時は0） |
| 固定（affinity/time/tasks/counters） | 60トークン | — |
| **合計hard cap** | **180トークン** | — |

※ counters は L2 注入（毎ターン固定）に移動。L3 budget から除外。

**動的再配分ルール**: 空チャネルの余剰 budget を他チャネルに再配分する。

```
例1: open_loops が 0件、self_context も無関連で 0件の場合
  → 余剰 50tok を profile(+25) と episodes(+25) に分配
  → profile=70, loops=0, episodes=50, self=0, 固定=60 = 180

例2: episodes も 0件の場合
  → 余剰 45tok を profile(+20) と loops(+15) と self(+10) に分配
  → profile=65, loops=45, episodes=0, self=30, 固定=60 = 180
```

再配分優先順位: profile > episodes > open_loops > self_context
合計 hard cap（180tok）は変更しない。

budget超過時: priority trim（低priorityアイテムから削除）

**条件付き注入**:
- `[記憶検索結果]` — 前ターンに MEMORY_QUERY が発行された場合（既存互換・追加30トークン）

**履歴注入**（`inject_all` = true の場合のみ）:
- `[これまでの会話]`（直近30件の履歴）
- StatefulSession + NormalTurn は注入しない（CLI側のコンテキスト窓が保持）
- StatefulSession + SessionStart/AfterCompaction、または StatelessRequest では毎回注入

**CLI圧縮後の再注入**（→ pipeline.md §14 参照）:
- CLI が内部コンテキスト圧縮を実行した場合、PostCompact hook 検知後に履歴（直近30件）と全4チャネルを再注入する
- `ReinjectionReason::AfterCompaction` + `StatefulSession` で呼ばれ、全チャネル注入が行われる

**サイズ目標**:
- 通常時: 〜130トークン（全チャネルがsparseな場合）
- 全チャネル活性時: 〜180トークン（hard cap）
- セッション開始時（履歴込み）: 〜1500トークン
- CLI圧縮後再注入時: 〜1500トークン（セッション開始時と同等）

---

## 5. L3 標準フォーマット

```
[好感度: +63（良好）]
[現在時刻: 2026-04-26 23:45 月曜]

[進行中タスク]
- [in_progress] AFDバグ修正
- [pending] テスト追加

[あなたが覚えていること]
- 緑茶好き（食べ物）
- 夜型人間だが早朝作業を好む（習慣）
- TypeScript + Rust が主要スキル（スキル）

[気にかけていること]
- 明日14時に面接がある
- 最近仕事の負荷が高い

[最近の出来事]
- 昨日: 新しいプロジェクト開始を報告してくれた

[行動カウンタ]
- lewd: 12回（30日: 8、7日: 3）

[あなた自身のこと]
- 整理されたコードが好き（確信度: 0.9）
- テスト設計の議論に関心がある（確信度: 0.6）
```

`[あなた自身のこと]` は self_model（memory.md §6.5）から現在トピックに関連する trait のみ注入。関連なしの場合はチャネルごと省略する。self_model に注入された内容は次ターンの self_reactions の evidence source にしてはならない（循環強化防止）。

---

## 6. プロンプト構造例（LLM送信時）

```
[System (L1)]
（CLAUDE.md 全文、キャッシュ対象）

[User Message Prefix (L2 + L3)]
（Critical Prompt 固定文字列）

[好感度: +63（良好）]
[現在時刻: 2026-04-26 23:45 月曜]

[進行中タスク]
- [in_progress] AFDバグ修正

[あなたが覚えていること]
- 緑茶好き（食べ物）
- 夜型だが早朝作業を好む（習慣）

[気にかけていること]
- 明日14時に面接がある

[最近の出来事]
- 昨日: プロジェクト開始を報告

[行動カウンタ]
- lewd: 12回（30日: 8、7日: 3）

[あなた自身のこと]
- 整理されたコードが好き（確信度: 0.9）

（セッション開始時のみ）
[これまでの会話]
2026-04-25 14:30 ユーザー: ビルドして
...

[現在の入力]
（ユーザー発話 or [システム通知:カテゴリ]）
```

---

## 7. 設計判断

- **L2 必要性**: LLM は長い会話でシステムプロンプトを「忘れる」。毎ターン核だけ再注入することでキャラ崩壊を防ぐ
- **L3 分離**: 動的情報をL3に分離することで L1 キャッシュを最大化できる
- **履歴の条件付き注入**: セッション開始時のみにすることで通常ターンのトークン消費を抑える
- **カウンタの条件付き注入**: 変動のない日は注入しない（トークン節約）

---

## 8. 実装場所

- `src-tauri/src/anima/context.rs` — `build_context_at()` でL2/L3を組み立て。`ContextMode` / `ReinjectionReason` によって注入チャネルを制御
- `src-tauri/src/anima/retrieval.rs` — SQLite経由のL3チャネル取得（`build_l3_channels()` / `build_episodes_only()`）。DB不在時は空L3にグレースフルデグレード
- `src-tauri/.claude/CLAUDE.md` — L1 本体
- `projects.json` — per-project 設定（Critical Prompt は roles/_common/prompts/l2.md）

*作成日: 2026-04-28*
