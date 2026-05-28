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
| tts.rs | spec/ui/voice-input.md |
| recording.rs | spec/ui/voice-input.md |
| skill.rs | spec/ui/plugin-api.md |
| pty_commands.rs | spec/core/anima-orchestrator-architecture.md |
| cli_adapters.rs | spec/core/pipeline.md（実アダプタ実装） |
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
