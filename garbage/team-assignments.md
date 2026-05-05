# Oribis 開発チーム分担

> 作成: 2026-05-04
> 更新: 2026-05-05（component-architecture.md に設計原則・構造・オーナーシップを分離）

---

## sysdev-3 — Anima バックエンド

**ブランチ**: `sysdev-3/anima-pipeline`

### 担当コンポーネント（独占）

| コンポーネント | 作業内容 |
|---------------|---------|
| `src-tauri/src/anima/` 全ファイル | パイプライン統合・CLI Adapter実装・マーカー処理 |
| `src-tauri/src/lib.rs` | Tauriコマンド公開（`execute_chat` / `execute_anima` / `get_affinity`） |
| `src-tauri/src/config.rs` | 設定ロード |

### 具体タスク

- cli_adapter.rs: `send_message` 実装（Claude/Codex/OpenClaw）
- pipeline.rs: AnimaMode配線・memory_saves処理・イベントカウンタ接続
- throttle.rs: ThrottleConfig tomlロード
- context.rs: `compute_sub_context` 接続
- parser.rs: ANIMA/MOOD/AFFINITY/TASK/MEMORY_SAVEマーカー処理

### 完了条件

- `cargo test` 全 PASS
- Animaが新パイプライン経由で応答すること
- 全マーカーが正常処理されること

---

## sysdev-4 — フロントエンド体験

**ブランチ**: `sysdev-4/frontend-experience`

### 担当コンポーネント（独占）

| コンポーネント | 作業内容 |
|---------------|---------|
| `src/adapters/` | アバターモデル抽象化 |
| `src/components/` | UI実装 |
| `src/controllers/` | アバター制御ロジック |
| `src/hooks/` | 状態管理フック |
| `src/loaders/` | モデル読み込み |
| `src/themes/` | テーマ設定 |
| `src/types/` | 共有型 |
| `src/App.tsx` | ルート構成 |

### 具体タスク

- AvatarViewer: mood計算・jitter・lerp補間実装
- useAnima: Greetingバグ修正・アバター制御統合
- expressionMapping: 好感度Tierに応じた表情マッピング
- Onboarding: 初回起動セットアップ画面

### 完了条件

- 好感度Tierに応じて表情が変化すること
- 30fps lerp補間が動作すること
- Greeting時クラッシュなし
- `pnpm tsc --noEmit` PASS

---

## sysdev-5 — プラグイン・Worker・インフラ

**ブランチ**: `sysdev-5/plugin-worker`

### 担当コンポーネント（独占）

| コンポーネント | 作業内容 |
|---------------|---------|
| `src/plugin/` | プラグインシステム |
| `src/skill/` | スキルUI |
| `src/components/XtermTerminal.tsx` | xterm.js PTY表示 |
| `src-tauri/src/pty_commands.rs` | PTYプロセス管理 |
| `src-tauri/src/plugin.rs` | プラグインバックエンド |
| `src-tauri/src/skill.rs` | スキルバックエンド |
| `src-tauri/src/named_pipe.rs` | 名前付きパイプ |
| `src-tauri/src/audio_playback.rs` | 音声再生 |
| `src-tauri/src/tts.rs` | TTS |
| `src-tauri/src/recording.rs` | 録音 |
| `src-tauri/src/json_log.rs` | ログ |
| `src/utils/` | 共有ユーティリティ |

### 具体タスク

- PTY: Workerタブ表示・ConPTY制御
- PluginManager: プラグインライフサイクル管理
- audio/tts/recording: 音声パイプライン統合
- ビルド・設定ファイルの保守

### 完了条件

- WorkerタブでCLIエージェントを起動・表示できること
- プラグインのロード/アンロードが正常動作すること
- 音声再生・TTS・録音が動作すること

---

## ブランチ戦略

```
main (安定版)
└── develop
    ├── sysdev-3/anima-pipeline      (sysdev-3)
    ├── sysdev-4/frontend-experience (sysdev-4)
    └── sysdev-5/plugin-worker       (sysdev-5)
```

各エージェントは `develop` から分岐し、完了後 `develop` へ PR。
