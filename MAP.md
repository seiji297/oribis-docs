<!-- AUTO-DOC-GEN:TREE-START -->
```
```
<!-- AUTO-DOC-GEN:TREE-END -->

# Oribis ドキュメント構成マップ

AIエージェントがドキュメントの追加・修正先を自動判断するためのルーティングガイド。

```
docs/projects/oribis/
├── STATUS.md              # 進捗管理（単一ファイル）
├── MAP.md                 # 本ファイル（ルーティングガイド）
├── spec/                  # 機能仕様書
│   ├── core/              #   コアシステム設計
│   └── ui/                #   UI・フロントエンド機能
├── issues/                # バグ・修正要件
├── deliverables/          # 成果物・レビュー結果
├── rules/                 # 設計ルール・必守事項・テストパターン
├── knowledge/             # 実装知見・落とし穴（揮発性）
├── prompt/                # プロンプト定義
│   ├── anima/         #   キャラクター設定
│   └── system/            #   システム共通ルール（出力形式・マーカー等）
└── garbage/               # 参照用アーカイブ
```

---

## ルーティング判定順序

ドキュメントの配置先を決めるとき、以下の優先順位で上から順に判定する。最初にマッチしたフォルダに配置すること。

1. **spec/** — 機能仕様に該当するか？
2. **issues/** — バグ・不具合に該当するか？
3. **deliverables/** — ECC成果物に該当するか？
4. **prompt/** — キャラクター定義またはシステム出力ルールに該当するか？
5. **rules/** — 永続的な設計ルール・運用ルールに該当するか？
6. **knowledge/** — 上記いずれにも該当しない実装知見・ワークアラウンドか？

**フォールバック**: どのルールにも該当しない場合は `knowledge/` に仮置きし、STATUS.md の備考欄に「要分類」と記録する。

---

## ルーティングルール

### spec/core/
**条件**: バックエンド（Rust）のシステム設計・アーキテクチャに関する仕様を新規作成・修正するとき
**例**: パイプライン設計、好感度システム、記憶システム、マーカー仕様、表情制御ロジック
**命名**: `{機能名}.md`（例: `pipeline.md`, `memory.md`）

### spec/ui/
**条件**: フロントエンド（React/TypeScript）のUI機能・ユーザー向け機能の仕様を新規作成・修正するとき
**例**: アバター表示、プラグインUI、音声入力、テーマ、インストーラー
**命名**: `{機能名}.md`（例: `voice-input.md`, `scene-plugin.md`）

### issues/
**条件**: バグ報告・不具合修正の要件を記録するとき
**例**: 表示崩れ、クラッシュ、リターゲット不具合
**命名**: `{カテゴリ}/{issue名}.md`（例: `fbx/retarget-arp-to-vrm.md`）

### deliverables/
**条件**: エージェントチェーン（AC）の成果物（設計書・レビュー結果・計画書）を保存するとき
**例**: planner の設計書、codex-reviewer のレビュー結果、DA ゲート判定
**命名**: `{種別}-{内容}.md`（例: `design-expression-wiring-v5.md`, `codex-code-review-expression.md`）
**保持ルール**: バージョン付きファイル（v2, v3...）は最新版のみ残し、旧版は削除する。タスク完了後に整理すること。

### rules/
**条件**: 設計ルール・必守事項・テストパターン・運用情報を記録するとき。コードが変わっても有効な永続的ルール。
**例**: CLI抽象化ルール、純関数テストパターン、コンポーネントアーキテクチャ、チーム割り当て
**命名**: `{ルール名}.md`

### knowledge/
**条件**: 実装中にハマった落とし穴・ライブラリの癖・ワークアラウンドを記録するとき。コード修正で陳腐化しうる揮発性の知見。
**例**: プラットフォーム固有の注意点、Three.jsの挙動、React パターン
**命名**: `{トピック}.md`
**既存ファイルに該当トピックがあれば追記、なければ新規作成。**

### prompt/anima/
**条件**: キャラクターの人格・外見・声・口調・好み等のキャラクター定義を追加・更新するとき
**命名**: `{キャラクター名}.md`（例: `nagiko.md`）

### prompt/system/
**条件**: 出力形式・好感度メカニクス・マーカー仕様等のシステム共通ルールを追加・更新するとき
**命名**: `{ルール名}.md`（例: `output-rules.md`）

### STATUS.md
**条件**: 以下のいずれかが発生したとき、該当行を更新する
- spec の実装ステータスが変化した
- 個別タスク（TASK-*）のステータスが変化した
- 新しい spec や issue が追加された
- Phase GAP が解消された
**連動ルール**: spec/ または issues/ にファイルを追加・削除したら、STATUS.md の対応テーブルも必ず同時に更新する。片方だけの更新は禁止。

### MAP.md（本ファイル）
**条件**: 以下のいずれかが発生したとき、本ファイルを更新する
- フォルダ構成を変更した（ツリー図・ルーティングルールを同時更新）
- 新規コードファイルを追加した（コード↔spec対応表を更新）
- ルーティングルールの条件・例を修正する必要が生じた

**ステータス凡例**（この表記のみ使用すること）:
| 値 | 意味 |
|----|------|
| 未実装 | 設計書はあるが、コードが一切ない |
| 設計確定 | 設計完了、実装着手前 |
| 一部実装済 | コードはあるが未完成（stub含む、GAP残存） |
| 実装済 | 仕様どおりに動作する。バックログ（LOW）は許容 |
| 廃止 | 仕様が不要になった・別specに統合された |
| — | 進捗管理対象外（リファレンス・計画書等） |

---

## コード↔spec 対応表

コード変更時、対応するspecも更新が必要か確認すること。
新規ファイル追加時はこの対応表も更新すること。

### バックエンド（src-tauri/src/）

| コードパス | spec |
|-----------|------|
| anima/pipeline.rs | spec/core/pipeline.md |
| anima/cli_adapter.rs | spec/core/pipeline.md（§8 CLI Adapter） |
| anima/providers/mod.rs | spec/core/pipeline.md（§8.7 HTTP provider factory） |
| anima/providers/anthropic.rs | spec/core/pipeline.md（§8.7 Anthropic Messages API provider） |
| anima/providers/openai_compat.rs | spec/core/pipeline.md（§8.7 OpenAI互換 Chat Completions provider） |
| anima/anima_dispatch.rs | spec/core/anima-orchestrator-architecture.md（Internal Worker dispatch proposal / approval / read-only run） |
| anima/anima_explainer.rs | spec/core/anima-orchestrator-architecture.md（deterministic Anima explanation / scope check）+ spec/ui/anima-ui.md（説明表示） |
| anima/job_selector.rs | spec/core/anima-orchestrator-architecture.md（Job/Event/Artifact context selector） |
| anima/affinity.rs | spec/core/affinity.md |
| anima/memory.rs | spec/core/memory.md |
| anima/counter.rs | spec/core/event-counter.md |
| anima/throttle.rs | spec/core/anima.md（§7 throttle） |
| anima/cache.rs | spec/core/anima.md（§8 キャッシュ） |
| anima/parser.rs | spec/core/markers.md |
| anima/context.rs | spec/core/prompt-layers.md |
| anima/history.rs | spec/core/session-data.md |
| anima/task.rs | spec/core/session-data.md（§タスク管理） |
| anima/anima.rs | spec/core/anima-state.md |
| anima/db.rs | spec/core/data-storage.md |
| anima/mod.rs | spec/core/pipeline.md（公開API定義） |
| plugin.rs | spec/ui/plugin-api.md |
| config.rs | spec/ui/plugin-api.md |
| named_pipe.rs | spec/ui/namedpipe.md |
| audio_playback.rs | spec/ui/voice-input.md |
| tts.rs | spec/ui/voice-input.md（TTS基盤 + Piper/Sherpa/RHVoice CLI実装含む）+ spec/core/embedded-tts.md（組み込みTTS統合） |
| tts/router.rs | spec/core/embedded-tts.md（言語判定→エンジン選択→音声合成ルーティング） |
| tts/types.rs | spec/core/embedded-tts.md（TtsLanguage, TtsEngineChoice, TtsSynthesisRequest/Response） |
| tts/voicevox_core.rs | spec/core/embedded-tts.md（VOICEVOX Core 0.16.4 FFI実装） |
| tts/kokoro.rs | spec/core/embedded-tts.md（Kokoro ONNX自前実装） |
| tts/voice_defs.rs | spec/core/embedded-tts.md（9音声スタイル定義） |
| tts/engine_registry.rs | spec/ui/voice-input.md（TTSエンジンレジストリ・GitHub URL管理） |
| tts/install_state.rs | spec/ui/voice-input.md（EngineInstallState永続化） |
| tts/installer.rs | spec/ui/voice-input.md（ダウンロード・検証・展開・原子インストール） |
| tts/lifecycle.rs | spec/ui/voice-input.md（自動起動・PID管理・排他制御） |
| tts/license_state.rs | spec/ui/voice-input.md（ライセンス同意永続化） |
| tts/platform.rs | spec/ui/voice-input.md（アーカイブ形式判定） |
| tests/tts_manual.rs | spec/core/embedded-tts.md（手動統合テスト: VOICEVOX+Kokoro実音声合成） |
| tests/tts_e2e.rs | spec/core/embedded-tts.md（E2E定義・検証テスト） |
| tests/kokoro_chat_e2e.rs | spec/core/embedded-tts.md（英語チャット応答→KokoroTTS→WAV保存 E2Eテスト） |
| tests/tts_smoke.rs | spec/core/embedded-tts.md（Smokeテスト） |
| tests/tts_engine_integration.rs | spec/ui/voice-input.md（E2E統合テスト: mock DL→install→health→fetch WAV） |
| tests/tts_engine_real_download_test.rs | spec/ui/voice-input.md（リアルE2Eテスト: GitHub実DL→WAV合成検証） |
| resources/voicevox-core/n0.vvm | spec/core/embedded-tts.md（VOICEVOX Nemo音声モデル） |
| models/kokoro/model.onnx | spec/core/embedded-tts.md（Kokoro ONNXモデル） |
| models/kokoro/voices/*.bin | spec/core/embedded-tts.md（Kokoro音声スタイルファイル） |
| recording.rs | spec/ui/voice-input.md |
| live_mode.rs | spec/ui/voice-input.md（Live Mode連続録音+VAD） |
| skill.rs | spec/ui/plugin-api.md |
| pty_commands.rs | spec/core/anima-orchestrator-architecture.md |
| cli_adapters.rs | spec/core/pipeline.md（実アダプタ実装） |
| action_router.rs | spec/core/anima-orchestrator-architecture.md（Action Router policy/audit boundary） |
| internal_worker.rs | spec/core/anima-orchestrator-architecture.md（Internal Worker JSONL store/API/read-only runtime/tool registry） |
| internal_worker_write_plan.rs | spec/core/anima-orchestrator-architecture.md（Internal Worker write plan Store/API、pathScope/idempotency/secret-like path hardening） |
| anima/anima_dispatch.rs | spec/core/anima-orchestrator-architecture.md（Anima dispatch proposal/approval decision store/closed loop） |
| anima/anima_policy.rs | spec/core/anima-orchestrator-architecture.md（Anima intent classification / read-only policy boundary） |
| anima/anima_explainer.rs | spec/core/anima-orchestrator-architecture.md（deterministic Anima explanation / scope check） |
| anima/job_selector.rs | spec/core/anima-orchestrator-architecture.md（Job/Event/Artifact context selector） |
| lib.rs | spec/core/pipeline.md（Tauriコマンドハブ） |
| mcp/mod.rs | spec/core/mcp-server.md |
| mcp/server.rs | spec/core/mcp-server.md（§4 Broker + tool dispatch） |
| mcp/broker.rs | spec/core/mcp-server.md（§4.2 BrokerState） |
| mcp/types.rs | spec/core/mcp-server.md（§6 ツール型定義） |
| mcp/protocol.rs | spec/core/mcp-server.md（§4.1 MCP JSON-RPC） |
| mcp/state_machine.rs | spec/core/mcp-server.md（§7.5 AnimaCategory 状態遷移表） |
| mcp/audit.rs | spec/core/mcp-server.md（§5.3 監査ログ） |
| mcp/resources.rs | spec/core/mcp-server.md（§6.4 リソース） |
| mcp/tools/mod.rs | spec/core/mcp-server.md（§6 ツール） |
| mcp/tools/memory.rs | spec/core/mcp-server.md（§6.1 memory_search/save） |
| mcp/tools/avatar.rs | spec/core/mcp-server.md（§6.2 speak/set_expression/notify） |
| mcp/tools/anima.rs | spec/core/mcp-server.md（§6.3 anima制御） |
| mcp/tools/event_feed.rs | spec/core/anima-orchestrator-architecture.md（MCP write_event ツール） |
| narration.rs | spec/core/anima-orchestrator-architecture.md（ナレーション: batch取得・coalescing・dedupe・emit） |
| worker_manager.rs | spec/core/anima-orchestrator-architecture.md（Worker管理: spawn/kill/list） |
| event_feed.rs | spec/core/anima-orchestrator-architecture.md（EventFeed JSONL操作） |
| department_config.rs | spec/core/anima-orchestrator-architecture.md（Department CRUD） |
| events.rs | spec/core/anima-orchestrator-architecture.md（EventFeedItem型・変換トレイト） |
| bin/oribis_mcp.rs | spec/core/mcp-server.md（§4.1 MCP子プロセスバイナリ） |
| github/update_check.rs | —（商用化: GitHub Releases APIバージョンチェック） |
| error.rs | —（OribisError: i18nキー化済み） |
| remote/web_remote_state.rs | spec/ui/web-remote.md |
| plugin/access.rs | spec/ui/plugin-api.md（Plugin Host API access layer） |
| plugin/permission.rs | spec/ui/plugin-api.md（Permission Manager / capability policy） |
| plugin/router.rs | spec/ui/plugin-api.md（Plugin Action Router / secret placeholder boundary） |
| plugin/secrets.rs | spec/ui/plugin-api.md（Secrets Store / encrypted secret persistence） |
| plugin/manifest.rs | spec/ui/plugin-api.md（runtime=webview/sidecar manifest schema） |

### フロントエンド（src/）

| コードパス | spec |
|-----------|------|
| utils/expressionSystem.ts | spec/core/expression-system.md |
| components/AvatarViewer.tsx | spec/core/expression-system.md, spec/ui/vrm.md |
| components/VrmViewer.tsx | spec/ui/vrm.md |
| plugin/PluginManager.ts | spec/ui/plugin-api.md |
| hooks/useAnima.ts | spec/ui/anima-ui.md |
| hooks/useVoiceInput.ts | spec/ui/voice-input.md |
| hooks/useDualSession.ts | spec/ui/dual-session.md |
| hooks/useCliStatus.ts | spec/ui/cli-status-pane.md |
| hooks/useTTS.ts | spec/ui/voice-input.md |
| adapters/VrmAvatarAdapter.ts | spec/ui/vrm.md |
| adapters/FbxAvatarAdapter.ts | spec/ui/avatar-animation.md |
| adapters/MmdAvatarAdapter.ts | spec/ui/mmd-model.md |
| adapters/expressionMapping.ts | spec/core/expression-system.md |
| adapters/boneMapping.ts | spec/ui/avatar-animation.md |
| adapters/morphMapLoader.ts | spec/ui/avatar-animation.md |
| controllers/AvatarController.ts | spec/ui/vrm.md |
| loaders/avatarLoader.ts | spec/ui/vrm.md, spec/ui/mmd-model.md, spec/ui/avatar-animation.md |
| loaders/animationLoader.ts | spec/ui/avatar-animation.md |
| components/StatusPane.tsx | spec/ui/cli-status-pane.md |
| components/XtermTerminal.tsx | spec/core/anima-orchestrator-architecture.md |
| components/WorkerPanel.tsx | spec/core/anima-orchestrator-architecture.md（Worker タブバー + PTY） |
| components/DrawerAnima.tsx | spec/core/anima-orchestrator-architecture.md（Animaドロワー） |
| components/DrawerDepartment.tsx | spec/core/anima-orchestrator-architecture.md（Departmentドロワー） |
| components/DrawerEventFeed.tsx | spec/core/anima-orchestrator-architecture.md（EventFeedドロワー） |
| components/CommandPalette.tsx | spec/ui/anima-ui.md（Action Platform Commandsタブ） |
| components/DeveloperConsole.tsx | spec/ui/anima-ui.md（JS/TS Console request UI） |
| components/EventInspector.tsx | spec/core/anima-orchestrator-architecture.md（Event Feed詳細表示） |
| components/TaskJobView.tsx | spec/core/anima-orchestrator-architecture.md（Internal Worker Job一覧/詳細/Event/Artifact） |
| components/AnimaDispatchPanel.tsx | spec/ui/anima-ui.md（Anima dispatch proposal/approval/explanation UI） |
| components/ActionAuditPanel.tsx | spec/ui/anima-ui.md（Action Router audit metadata UI） |
| components/WriteProposalPreview.tsx | spec/ui/anima-ui.md（write proposal preview / unified diff安全表示） |
| components/ApprovalBinding.tsx | spec/ui/anima-ui.md（approval hash binding表示） |
| components/writeProposal.types.ts | spec/ui/anima-ui.md（write proposal preview型契約） |
| hooks/useDispatchProposal.ts | spec/ui/anima-ui.md（Anima dispatch proposal hook） |
| action-router/index.ts | spec/ui/anima-ui.md（frontend Action Router registry） |
| action-router/types.ts | spec/ui/anima-ui.md（frontend Action Router types） |
| command/CommandRegistry.ts | spec/ui/anima-ui.md（Command Registry / Command Palette foundation） |
| command/actionRouterAdapter.ts | spec/ui/anima-ui.md（Action Router adapter） |
| command/internalWorkerRouter.ts | spec/core/anima-orchestrator-architecture.md（Internal Worker frontend action types）+ spec/ui/anima-ui.md |
| command/permissions.ts | spec/ui/plugin-api.md（frontend permission action types） |
| command/types.ts | spec/ui/anima-ui.md（Command request types） |
| plugin/types.ts | spec/core/anima-orchestrator-architecture.md（WorkerInfo/DepartmentConfig/EventFeedItem/SpeechQueueItem型） |
| components/AnimationAssignPanel.tsx | spec/ui/motion-anim-assign.md, spec/ui/unity-fbx-retarget.md |
| plugin/usePluginLoader.ts | spec/ui/plugin-api.md |
| skill/SkillPicker.tsx | spec/ui/plugin-api.md |
| skill/useSkills.ts | spec/ui/plugin-api.md |
| App.tsx | spec/ui/anima-ui.md（メイン統合面）+ 商用化（update check / offline banner） |
| hooks/useNetworkStatus.ts | —（商用化: navigator.onLine監視） |
| components/ErrorRetryBanner.tsx | —（商用化: オフライン/タイムアウト通知UI） |
| utils/invokeWithTimeout.ts | —（商用化: Tauri invokeタイムアウトラッパー） |
| utils/resolveErrorMessage.ts | —（商用化: i18nキーエラーメッセージ解決） |
| themes/avatarThemes.ts | spec/ui/vrm.md（テーマ定義） |
| adapters/retargetMixamoToVrm.ts | spec/ui/avatar-animation.md, spec/ui/unity-fbx-retarget.md |
| utils/proceduralClip.ts | spec/ui/avatar-animation.md |
| components/avatarPoses.ts | spec/ui/vrm.md |
| components/LuminaRenderer.tsx | spec/ui/lumina.md |
| components/lumina/LuminaRing.ts | spec/ui/lumina.md |
| components/lumina/LuminaParticles.ts | spec/ui/lumina.md |
| components/lumina/LuminaCore.ts | spec/ui/lumina.md |
| components/lumina/luminaParams.ts | spec/ui/lumina.md |
| components/lumina/luminaShaders.ts | spec/ui/lumina.md |
| plugin-v2/usePluginSystem.ts | spec/ui/plugin-api.md |
| plugin-v2/HostAPI.ts | spec/ui/plugin-api.md |
| plugin-v2/PluginSandbox.tsx | spec/ui/plugin-api.md |
| plugin-v2/UIRenderer.tsx | spec/ui/plugin-api.md |
| plugin-v2/EventBus.ts | spec/ui/plugin-api.md |
| plugin-v2/types.ts | spec/ui/plugin-api.md |
| plugin-v2/bootstrap.ts | spec/ui/plugin-api.md |
| plugins-v2/chat-mode/manifest.yaml | spec/ui/app-system-v2.md |
| plugins-v2/chat-mode/index.ts | spec/ui/app-system-v2.md |
| plugins-v2/chat-mode/chat-logic.ts | spec/ui/app-system-v2.md |
| e2e/scenarios/t-23-chat-mode-plugin.scenario.json | spec/ui/app-system-v2.md |
| e2e/scenarios/t-25-action-smoke.scenario.json | spec/core/test-infrastructure.md（Action Platform scenario smoke） |
| e2e/wdio/tests/action-platform.spec.ts | spec/core/test-infrastructure.md（Action Platform実GUI: Commands/Console/Events/Jobs） |
| e2e/wdio/tests/anima-approval.spec.ts | spec/core/test-infrastructure.md（Anima dispatch approval read-only closed loop実GUI） |
| e2e/wdio/tests/anima-approval-policy.spec.ts | spec/core/test-infrastructure.md（Anima approval policy/audit実GUI） |
| scripts/run-wdio-tests.sh | spec/core/test-infrastructure.md（WDIO実行スクリプト / worktree別Vite誤再利用防止） |

### CI/CD（.github/workflows/）

| コードパス | spec |
|-----------|------|
| release.yml | —（Tauri Release + artifact validation） |
| smoke-install.yml | —（商用化P0-2: クリーン環境インストールテスト） |

---

## ドキュメント整理後チェックリスト

ドキュメント整理・追加・削除を行った後、以下を確認すること。

- [ ] 追加したファイルがルーティングルールの条件に合致するフォルダに配置されているか
- [ ] spec/ または issues/ を追加・削除した場合、STATUS.md の対応テーブルも更新したか
- [ ] コードファイルを追加した場合、コード↔spec対応表も更新したか
- [ ] フォルダ構成を変更した場合、MAP.md のツリー図とルーティングルールも更新したか
- [ ] deliverables/ にバージョン付きファイルを追加した場合、旧版を削除したか
- [ ] knowledge/ に「要分類」で仮置きしたファイルが残っていないか
