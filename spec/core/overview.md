# Anima — 概要・設計原則・フェーズ計画

**バージョン**: 1.1（anima-spec.md §1/§2/§23/§25 より分割。2026-04-30: history per-project化・session_id永続化・db.rs追加・ギャップ補完）
**最終更新**: 2026-04-30

---

## 1. システム概要

Anima の応答系統全体の設計仕様。

### 1.1 構成要素

- メインチャット応答（ユーザー発話への応答）
- Anima応答（状態イベントへの応答）
- 好感度システム（長期的関係性パラメータ）
- 履歴統合管理
- 永続記憶システム
- イベントカウンタ
- タスク管理
- AI推論 / キャッシュの切替機構

### 1.2 実装プロジェクト

本仕様は Oribis プロジェクト（Rust + TypeScript）に実装される。

### 1.3 対応CLI

- Claude CLI（Claude Code）
- Codex CLI（GPT系）
- ローカルLLM（将来）

CLI Adapter抽象化で複数CLI対応。

---

## 2. 設計原則

### 2.1 統一原則

Animaは1つの人格。応答系統は分けるが、**人格の源泉は共有**。

### 2.2 業務分離原則

- 業務遂行（コード・技術・実行）は好感度・状態に影響されない
- 表現層のみ状態反映

### 2.3 スクリプトファースト原則

- LLM呼出はキャラ表現が必要な時のみ
- 判定・分類・制御・永続化は全てスクリプト
- LLMは「最後の手段」として使う

### 2.4 段階移行原則

- 初期はAI推論モードでスタート
- 運用しながらカテゴリ別にキャッシュへ移行可能
- 完全キャッシュ化も可能

### 2.5 CLI非依存原則

- マーカー方式でCLI共通動作
- CLI固有機能（TodoWrite等）に依存しない
- Adapter層でCLI差異を吸収

### 2.6 ★ CLI機能抽象化必須原則（全新機能共通）

**CLIに関係するすべての機能は、Claude CLI / Codex / OpenClaw の3バックエンドで動作する抽象化設計を必須とする。**

- CLI固有の実装を `ProjectChatState` 内に直接書くことを禁止
- 新機能設計時は必ず「他バックエンドで同等動作するか？」を確認
- バックエンド分岐は `match backend_type {}` のみ許容（重複実装禁止）
- Tauri command 名は バックエンド名を含めない（例: `cancel_claude_chat` → ❌ `cancel_chat` → ✅）

対象機能例: チャット送信・キャンセル・セッション制御・ストリーミング・再接続

→ 詳細設計: `pipeline.md §CLI Adapter` / `docs/features/oribis/knowledge.md`

### 2.7 ★ キャラクター個人名の使用禁止（全ドキュメント・コード共通）

**設計書・コード・コメント・変数名・パス名に特定キャラクターの個人名（例: Nagiko）を使用することを禁止する。**

- システム内部では汎用名 `Anima` を使用すること
- ファイルパス: `~/.config/oribis/anima/`（`nagiko/` 不可）
- コード識別子: `AnimaMain`, `AnimaAutonomous`（`NagikoMain` 不可）
- enum値・型名: `MessageSource::AnimaMain`（`NagikoMain` 不可）
- 環境変数: `ANIMA_TEST_CONFIG_DIR`（`NAGIKO_*` 不可）
- **例外**: プロンプトファイル（`prompt/character/nagiko.md` 等のキャラクター定義）のみ個人名使用可
- **例外**: L2プロンプト内のキャラクター言及
- **例外**: `cache-generation-prompts.md` 内のプロンプトテンプレート（キャラクター口調定義）

理由: キャラクター名はプロンプト層で定義される設定値であり、システム層にハードコードすべきではない。

---

## 3. 不採用要素（§23）

明示的に除外する設計:

- ❌ 機嫌・疲労・興味・警戒等の細分化パラメータ（**バックエンド永続化**として）
  - → フロントエンド揮発値としての mood は `expression-system.md` Phase 0 で別途定義
- ❌ 時間経過による好感度の自然減衰
- ❌ 業務遂行への状態影響
- ❌ ランダム変動による応答揺らぎ（LLM側に委ねる）
- ❌ inner_thought のJSON応答形式（マーカー方式に統一）
- ❌ メインチャットとAnimaの完全分離（統一パイプライン採用）
- ❌ プロジェクト別の好感度・記憶・カウンタ（ユーザー全体管理）
- ❌ memorableフラグ（記憶への昇格で代替）
- ❌ 行動ログの汎用記録（イベントカウンタで代替）

---

## 4. 実装フェーズ

### Phase 1（実装中）

- 好感度システム
- 統一応答パイプライン
- CLI Adapter抽象化
- 履歴統合管理
- 永続記憶システム
- イベントカウンタ
- タスク管理
- AI / Cache / Hybrid モード切替
- 発火制御

### Phase 2（予定）

- 入力ルーティング Mode A（ルールベース）
- 入力ルーティング Mode B（AI推論）
- PC状態監視・L3注入
- Greeting時 MEMORY_QUERY 自動発火（→ `spec-memory.md`）
- 複合状態インジケーター（→ `spec-event-counter.md`）

### Phase 3（予定）

- アバター制御連動強化
- 自発発話機構
- 4レイヤー記憶システム（memory_events/memories/open_loops/relationship_model）
- Consolidation Level 2（LLM統合）（→ `memory.md §7`）
- AnimaパイプラインのClaudeセッション持続（→ `spec-anima.md §6`）

### Phase 4（将来）

- マルチモーダル入力
- 関係性軸の細分化
- ユーザー個別キャリブレーション

---

## 5. 用語集

| 用語 | 説明 |
|------|------|
| L1/L2/L3 | プロンプト三層構造の各層 |
| Critical Prompt | キャラ忘却防止用の毎ターン注入文 |
| Affinity | Animaがプロデューサーに対して持つ好感度 |
| Tier | 好感度の段階区分（Hostile/Cold/Neutral/Warm/Close/Intimate） |
| Anima | 状態駆動の発話・アバター制御システム |
| 統合履歴 | ユーザー発話・メイン応答・Anima応答を時系列統合した履歴 |
| 統一パイプライン | 全応答を同一処理経路で扱う設計 |
| CLI Adapter | 複数CLI対応の抽象化レイヤー |
| マーカー | LLM応答末尾のメタ情報（[AFFINITY:N], [ANIMA:...], [TASK:...], [MEMORY_SAVE:...]） |
| 発火制御 | Anima発話の頻度抑制機構 |
| AI Mode / Cache Mode / Hybrid Mode | Anima応答の生成方式 |
| イベントカウンタ | 特定行動の累積カウント |
| 永続記憶 | LLM判断 or 人間指示で保存される長期記憶 |

---

## 6. 関連ドキュメント

**system/ 設計仕様**

| ドキュメント | 内容 |
|---|---|
| `prompt-layers.md` | プロンプト三層構造（L1/L2/L3） |
| `pipeline.md` | 統一応答パイプライン + CLI Adapter |
| `markers.md` | マーカー方式統一仕様 |
| `affinity.md` | 好感度システム |
| `session-data.md` | 統合履歴 + タスク管理 |
| `memory.md` | 永続記憶 + セッションジャーナル + バッチ蒸留 |
| `event-counter.md` | イベントカウンタ |
| `anima.md` | Anima + AnimaMode + throttle + スマートキャッシュ |
| `data-storage.md` | データストレージ設計（db.rs ユーティリティ含む） |
| `test-requirements.md` | テスト要件 |

**サポートファイル**

| ドキュメント | 内容 |
|---|---|
| `expression-system.md` | 表情反映システム（フロントエンド・Phase 0） |
| `architecture-diagrams.md` | アーキテクチャ図集 |
| `cache-generation-prompts.md` | キャッシュ生成プロンプト集 |
| `character-plan.md` | 開発計画（実装状況・残作業・フェーズ計画） |
| `src-tauri/.claude/CLAUDE.md` | Anima Anima完全定義（L1） |

*作成日: 2026-04-28*
