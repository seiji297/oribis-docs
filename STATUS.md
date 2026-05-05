# Oribis 進捗管理

**最終更新**: 2026-05-05

---

## 運用ルール

- **全体フローが唯一の優先度管理面**。タスクの追加・完了・優先度変更はここで行う
- 下部の spec/issues テーブルは「何があるか」のレジストリ（ステータス列のみ更新）
- AIエージェントは**タスク着手前・完了後**に全体フローを確認・更新すること
- 全体フローに載っていないタスクを着手する場合は、まずここに追加してから着手

---

## 全体フロー

### 現在地
- **Phase 1（コア機能）**: 大部分実装済。残GAP: G1(journal), G3(AnimaMode runtime配線), G5(sub_context) の3件
- **Phase 0（表情）**: 完了（純関数化 + AvatarViewer統合）
- **UI機能**: 主要機能は実装済。未着手は output-viewer, web-remote, windows-installer

### 機能追加

| 優先度 | ID | 内容 | 関連spec | 状態 | 備考 |
|--------|-----|------|----------|------|------|
| HIGH | G1 | journal.rs 新規作成 | memory.md | 未着手 | 蒸留の前提 |
| HIGH | G3 | AnimaMode runtime配線 | anima.md | 一部実装済 | 定義+3分岐ロジック済、anima_chatからwith_anima_mode未呼出 |
| MEDIUM | G5 | compute_sub_context 接続 | prompt-layers.md | 未着手 | L3注入準備 |
| MEDIUM | — | motion-anim-assign ランタイムマウント | motion-anim-assign.md | 一部実装済 | パネル実装済・組込み未 |
| LOW | — | output-viewer 実装 | output-viewer.md | 未着手 | |
| LOW | — | web-remote 実装（axum + browser UI） | web-remote.md | 未実装 | 設計確定済 |
| LOW | — | windows-installer | windows-installer.md | 未実装 | 設計案段階 |
| LOW | TASK-A | マルチタブ・マルチプロジェクト機能 | — | 未着手 | |
| LOW | TASK-I | セッション管理再設計 | — | 未着手 | セッションID表示・STARTボタン・孤立CLI検出 |
| LOW | TASK-L | OpenCode CLI 対応 | pipeline.md | 方針未確定 | 調査pending |

### バグ修正・技術的負債

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| HIGH | TASK-G | 音声入力 Codex R3 指摘対応 | voice-input.md | 一時停止中 | HIGH×2, MEDIUM×3, LOW×1 |
| MEDIUM | — | ARP→VRM FBXリターゲット修正 | issues/fbx/ | 一部対応済 | 腕完了、脊椎動作中 |
| MEDIUM | TASK-K | 入力欄に謎テキスト挿入バグ | — | 調査中 | 再現手順の特定待ち |
| LOW | TASK-B | useVoiceInput/useTTS テストTSエラー | voice-input.md | 要確認 | エラー未検出・タスク自体が古い可能性 |
| LOW | TASK-C | PoseDebugUI.tsx リファクタ検討 | — | 要確認 | App.tsxでimport使用中・削除不可 |
| LOW | TASK-E | VrmViewer expression detection 堅牢化 | vrm.md | 未着手 | |
| LOW | TASK-F | カメラ spherical↔OrbitControls 同期 | — | 未着手 | |
| LOW | TASK-J | 左ドロワー push レイアウト | — | 休止中 | R3F ResizeObserver問題 |

### テスト・品質

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| MEDIUM | TASK-M | scene プラグイン ユニットテスト追加 | scene-plugin.md | 未着手 | |
| MEDIUM | TASK-N | scene プラグイン Windowsビルド更新 | scene-plugin.md | Producer作業待ち | |
| LOW | TASK-O | scene プラグイン パフォーマンス確認 | scene-plugin.md | 未着手 | TASK-N後 |
| LOW | TASK-P | scene プラグイン 背景グラデーション色制御UI | scene-plugin.md | v2予定 | |
| LOW | TASK-D | FullBodyDebugUI 表情タブのデフォルト値 | — | 未着手 | 任意 |

### 完了済み（直近）

| ID | 内容 | 完了日 |
|----|------|--------|
| G0 | CLI adapter 実装（cli_adapters.rs） | 2026-05 |
| G7 | Tauri コマンド公開（anima_chat/anima_state + useAnima接続） | 2026-05 |
| G6 | イベントカウンタ トリガー接続（pipeline increment + context注入） | 2026-05 |
| G2 | ThrottleConfig toml ロード | 2026-05 |
| G4 | Anima pipeline memory_saves 処理 | 2026-05 |
| TASK-H | 会話ログ保存 + タスクペンディング | a67e021〜c8412c5 |

---

## spec レジストリ

### spec/core/ — コアシステム

| spec | 概要 | ステータス |
|------|------|-----------|
| overview.md | 概要・設計原則・フェーズ計画 | 設計確定 |
| pipeline.md | 統一応答パイプライン + CLI Adapter | 実装済 |
| anima.md | Anima + AnimaMode + throttle + キャッシュ | 一部実装済 |
| anima-plan.md | 開発計画（GAP管理） | — |
| anima-state.md | AnimaState一覧・カテゴリ | 実装済 |
| anima-orchestrator-architecture.md | オーケストレーター + Worker PTY | 未実装 |
| affinity.md | 好感度システム | 実装済 |
| memory.md | 永続記憶 + ジャーナル + 蒸留 | 一部実装済 |
| event-counter.md | イベントカウンタ | 実装済 |
| session-data.md | 統合履歴 + タスク管理 | 実装済 |
| data-storage.md | データストレージ（db.rs） | 実装済 |
| markers.md | マーカー方式統一仕様 | 実装済 |
| prompt-layers.md | プロンプト三層構造（L1/L2/L3） | 一部実装済 |
| expression-system.md | 表情反映システム | 実装済 |
| cache-generation-prompts.md | キャッシュ生成プロンプト集 | 設計確定 |
| architecture-diagrams.md | アーキテクチャ図集 | — |
| test-requirements.md | テスト要件 | — |

### spec/ui/ — UI・フロントエンド機能

| spec | 概要 | ステータス |
|------|------|-----------|
| vrm.md | VRMアバター表示 | 実装済 |
| mmd-model.md | MMDモデル対応 | 実装済 |
| avatar-animation.md | 表情拡張/FBXリターゲット/morphMap | 一部実装済 |
| motion-anim-assign.md | モーション状態別アニメ割り当てUI | 一部実装済 |
| anima-ui.md | Anima統合UI（parser/adapter/cache等） | 実装済 |
| dual-session.md | デュアルセッション（Theater Mode） | 実装済 |
| cli-status-pane.md | CLIステータスペイン | 実装済 |
| output-viewer.md | 出力ビューア | 未着手 |
| scene-plugin.md | シーンプラグイン | 実装済 |
| plugin-api.md | プラグインAPI | 実装済 |
| theme-system.md | テーマシステム | 実装済 |
| voice-input.md | 音声入力（push-to-talk） | 実装済 |
| web-remote.md | Webリモート（axum + browser UI） | 未実装 |
| namedpipe.md | 名前付きパイプ通信 | 実装済 |
| file-attachment.md | ファイル添付 | 実装済 |
| 1mb-warning.md | 1MBコンテキスト警告 | 実装済 |
| autotest.md | 自動テスト | 実装済 |
| android-cprime.md | Android C-prime API | 実装済 |
| unity-fbx-retarget.md | ARP Unity FBX→VRM リターゲット | 一部実装済 |
| windows-installer.md | Windowsインストーラー | 未実装 |
| wsl-build-setup.md | WSLビルド環境セットアップ | — |

### issues/

| issue | 概要 | ステータス |
|-------|------|-----------|
| fbx/retarget-arp-to-vrm.md | ARP→VRM FBXリターゲット修正 | 一部対応済 |

---

## ステータス凡例

| 値 | 意味 |
|----|------|
| 未実装 | 設計書はあるが、コードが一切ない |
| 設計確定 | 設計完了、実装着手前 |
| 一部実装済 | コードはあるが未完成（stub含む、GAP残存） |
| 実装済 | 仕様どおりに動作する。バックログ（LOW）は許容 |
| 廃止 | 仕様が不要になった・別specに統合された |
| — | 進捗管理対象外（リファレンス・計画書等） |
