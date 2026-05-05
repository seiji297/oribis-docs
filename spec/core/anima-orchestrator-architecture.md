# Oribis: Anima オーケストレーターアーキテクチャ設計

> 策定日: 2026-05-03
> ステータス: 設計確定（未実装・中期ロードマップ）

---

## 概要

現行oribisの「プロジェクトタブ = CLIプロセス」構成を刷新し、
**Animaを常駐指揮官・Workerを実行エージェント**とする新アーキテクチャ。

---

## 現行の課題

1. 起動のたびにCLIプロセスを立ち上げる → フットワークが重い
2. タスク分散時にプロジェクトタブを切り替える必要がある
3. 重い処理中は何も応答しない（ユーザーが暇になる）
4. プロジェクトごとに会話・記憶が分散する

---

## 新アーキテクチャ

### 役割分担

| 役割 | 説明 |
|------|------|
| **Anima** | 常駐AIAnima。ユーザーとの会話窓口・Workerの指揮官 |
| **Worker** | 実タスクを実行するCLIエージェント。Animaの管理下で起動 |
| **Project** | Workerが作業するコンテキスト（名前 + フォルダパス + Workers構成） |

### Anima

- **起動方式**: JSON stream（`--output-format stream-json`）
- **常駐**: アプリ起動中は常に起動済み
- **役割**:
  - ユーザーとの会話（軽いタスクは自ら実行）
  - 重いタスク判断 → Workerへ委譲（LLMが自動判断）
  - Worker作業中のナレーション
  - プロジェクト管理（スキル経由）
- **モデル**: ユーザーが選択（軽量モデル推奨ガイダンスつき）

### Worker

- **起動方式**: **PTY（ConPTY on Windows）** ← 重要
- **表示**: oribis内にEmbedded PTY → xterm.js（デフォルト折りたたみ、任意展開）
- **双方向**: ユーザーがxterm.jsから直接入力可能
- **フォルダ**: タスク時にAnimaが動的決定（会話の文脈・記憶から判断）
- **複数起動**: 可能（将来的に並列対応）
- **初期**: Sequential（planner→developer→testerの順）

### Project

- Animaスキル（`/new-project`等）で会話形式にセットアップ
- 設定はGUI（Settings）で後から確認・編集可能
- フォルダはWorker起動時に動的決定（事前登録不要）

---

## UIレイアウト

現行のプロジェクトタブを Workers に置き換える。Anima は現状通り右ペイン。

```
┌──────────────────────┬─────────────────┐
│ [Worker tab bar]     │  Anima          │
│ ●HORRO-Dev ○Planner │                 │
│ ────────────────────│  [会話ログ]     │
│  > git commit ...    │                 │
│  > 3 files changed   │                 │
└──────────────────────┴─────────────────┘
```

- **左メインエリア**: Workerタブバー（上部）+ 選択中WorkerのPTY（下部・全面展開）
  - タブバーは常時表示。全Workerの実行状態（●実行中 / ○待機中 / ✕終了）を確認可能
  - タブ切り替えでPTY表示が切り替わる（現行プロジェクトタブと同じ操作感）
- **右ペイン**: Anima会話（現状と同じ位置・UI）

---

## Animaナレーション方式

| 状況 | 方式 |
|------|------|
| Worker作業中 | テンプレート台詞（LLM不使用）。以下のフックイベントで発火 |
| Worker完了時 | LLMで1回だけ詳細ナレーション生成 |
| Workerエラー時 | テンプレート台詞 + エラー内容を要約 |

### ナレーション発火トリガー（フックイベント種別）

| イベント | 発火条件 | ナレーション例 |
|---------|---------|--------------|
| `session_start` | Worker起動時 | テンプレート（作業開始） |
| `pre_tool_use` (bash/edit/write) | ツール実行直前 | テンプレート（作業中） |
| `post_tool_use` (error) | ツール失敗時 | テンプレート + エラー内容要約 |
| `session_stop` (success) | Worker正常終了時 | LLM生成（詳細ナレーション） |
| `session_stop` (error) | Worker異常終了時 | テンプレート + 終了コード |

フックスクリプトが上記イベントをJSONL形式でファイル書き出し → oribisがファイル監視 → Animaへ渡す。
発火頻度制御: `pre_tool_use` は60秒クールダウン（頻繁なツール実行でも過剰発話しない）。

**ナレーション発話制御**:
- 既存の Anima ON/OFF（`animaMode="off"` または `dailyAnima=false`）に従う → Anima全停止時はナレーションも停止
- その上で Settings に `workerNarration: boolean` トグルを追加。デフォルトON
  - Anima ON だがWorkerナレーションだけ切りたい場合に使用

---

## Worker情報取得（各CLI対応）

| CLI | PTY表示 | ナレーション情報取得 | 方法 |
|-----|---------|---------|------|
| Claude CLI | ✅ | ✅ | Claude Code hooks → ファイル書き出し |
| OpenClaw CLI | ✅ | ✅ | Internal hooks → ファイル/webhook |
| OpenCode CLI | ✅ | ✅ | Plugin (.opencode/plugins/) → ファイル |
| Codex CLI | ✅ | ✅ (部分的) | `features.codex_hooks=true` → ファイル |

**Codex制約**: unified_exec・WebSearch等一部ツールはhooks対象外。
**共通パターン**: フックスクリプトがJSONLをファイルに書き出し → oribisがファイル監視 → Animaへ渡す

---

## オンボーディング（初回起動時）

`projects.json`が空のとき表示。以下を設定：

1. **Animaのモデル選択**（軽量推奨ガイダンスつき）
2. **AnimaのホームフォルダDIR**（記憶・設定・animaキャッシュの保存先）
3. **Worker初期設定**（モデル・名前など、1件以上）

全設定はSettings GUIから後で変更可能。

---

## 実装ロードマップ

| フェーズ | 内容 | 規模 |
|---------|------|------|
| 今すぐ | useAnima greeting バグ修正 | 小 |
| 近々 | オンボーディング画面（Animaモデル + Worker初期設定） | 中 |
| 中期 | アーキテクチャ刷新本体（Anima常駐 + PTY Worker + Project管理） | 大 |

---

## 技術メモ

- **ConPTY**: Windows 10 1809以降で利用可能。TauriでのPTY実装に使用。
- **VSCode実績**: xterm.js + ConPTYの組み合わせはVSCode統合ターミナルで実績あり。
- **Anima JSON stream**: TTS・好感度・inner_thoughtなど構造化データが必要なため、WorkerのPTYとは別にJSON stream継続。
- **Codex app-server**: 完全なイベント統合が必要な場合はapp-server（JSON-RPC）も選択肢。
