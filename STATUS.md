<!-- AUTO-DOC-GEN:STATUS-START -->
| 項目 | 値 |
|------|-----|
| ブランチ | `integration/action-platform-foundation` |
| コミット | `b30b2aa` |
| 日時 | 2026-06-17 23:59:00 +0900 |
| サマリー | test: stabilize action platform jobs smoke |
<!-- AUTO-DOC-GEN:STATUS-END -->

# Oribis 進捗管理

## ★★★ 絶対原則: WDIO E2Eは実GUIをテスト ★★★
**WDIOテストは実GUI（ユーザーが見て触れる画面）をテストする。**
- ❌ **内部処理テスト禁止** — GUIに表示されず内部的に処理だけするテストは禁止。例：`sendMessage()`直接呼び出し、`anima_chat`内部実装調査
- ❌ **ソース改変テスト禁止** — テストを通すために `App.tsx` 等にテスト用フックを追加するな
- ✅ **実GUI表示確認必須** — テキスト入力→送信後、GUI上にメッセージが表示されることを確認
- ✅ **GUIイベントと同じ流れ** — `__setChatInput`（textarea表示確認）→ `__sendChatMessage`（送信）→ GUI応答確認

**最終更新**: 2026-06-24

---

## 運用ルール

- **全体フローが唯一の優先度管理面**。タスクの追加・完了・優先度変更はここで行う
- 下部の spec/issues テーブルは「何があるか」のレジストリ（ステータス列のみ更新）
- AIエージェントは**タスク着手前・完了後**に全体フローを確認・更新すること
- 全体フローに載っていないタスクを着手する場合は、まずここに追加してから着手

---

## 全体フロー

### 現在地
- **アクティブトラック**: 商用化準備（COM）— 残P0: リリースページ公開のみ、GTM戦略（GTM）— Kawaii-Agent後出し勝利計画（新規）
- **完了トラック**: 記憶システム（G1）、MCP Server（G9）、オーケストレーター、Web Remote P1/P2、商用化P1全件、chat-mode-plugin（Task 1〜6 全完了）
- **Phase 0（表情）**: 完了
- **Phase 1（記憶基盤）**: 完了
- **商用化P0-2/P1-1〜5**: 完了（2026-05-27）— Rust 1500 / TS 822 / E2E 22 全PASS
- **オンボードTTSエンジン修正**: 完了（2026-05-31）— 外部インストール検出 + 進捗イベント + UI改善 + E2Eテスト
- **VOICEVOX Core組み込みTTS**: 完了（2026-06-01）— voicevox-dyn crate廃止→0.16.4新C APIカスタムFFI実装。n0.vvm Nemoモデル+9音声スタイル動作確認
- **KokoroTTS組み込み**: 完了（2026-06-01）— kokoro-en crate廃止→ort直接利用のカスタム実装。ONNXモデル310MB+音声ファイル。英語音声合成実動確認
- **KokoroTTS英語チャットE2E**: 完了（2026-06-02）— fake_claude英語応答→Kokoroルーティング→WAV生成→5秒以内検証→`/tmp/oribis-kokoro-test.wav`
- **Live Mode実装**: 完了（2026-06-09）— Silero VAD連続録音→自動STT→AIダイレクト送信。常時音声入力状態。テキスト入力欄バイパス
- **AIバックエンド配線**: 完了（2026-06-14）— `anthropic` / `openai_compat` を保存済みprovider設定から実HTTP providerへ接続。`cargo test --lib` 1433 PASS / `npm test` 796 PASS
- **Action Platform / Internal Worker / Self-Improvement Lite**: 初回リリース対象機能ほぼ完了（2026-06-17）— Anima提案→policy/audit評価→read-only Job→Job詳細/Event/Artifact→Anima説明、WritePlan/diff preview/hash binding、single-op `createFile`/`updateFile` safe apply、rollback proposal safe path、Router enforcement、sidecar prepared-only/preflight UI、自己改善Observation/Evaluation/Suggestion/Decision store/UI/audit gateまで到達。rollback executor、sidecar実spawn、shell/network/MCP write、multi-operation apply、自己改善の自動適用は意図的に未解禁。`integration/action-platform-foundation` commit `b30b2aa`。
- **Action Platform 最終検証**: 完了（2026-06-17）— `pnpm run typecheck` PASS、`pnpm vitest run` 1153 PASS / 3 skipped、`cargo check --manifest-path src-tauri/Cargo.toml` PASS、`cargo test --manifest-path src-tauri/Cargo.toml internal_worker_write_plan` 91 PASS、WDIO `app-launch` 5 PASS / `write-plan-apply` 3 PASS / `write-diff-proposal` 3 PASS / `action-platform` 5 PASS。`sidecar-preflight` はspec PASSだが1 skipped（マウント条件未成立）。`npx tsc -p e2e/wdio/tsconfig.json --noEmit` は既存 `BASE_URL` 再宣言でFAIL（今回変更外）。
- **SceneRuntime Foundation**: 一部実装済（2026-06-22）— Rust SceneRuntimeを正本にしたEntity/Component snapshot、Command schemaVersion/source/effect/approvalPolicy、最小Event log、`scene_runtime_tick(dt_ms)` + LifetimeSystem + LookAtSystem、`scene_runtime_get_snapshot`、`SetComponent`/`RemoveComponent` 最小実装（physics/lifetime/lookAt/surface/text）、SceneRuntime Document export/import、Archetype/Preset/Instance resolver、Scene Action resolver、Scene load resolver、Babylon projection focused test、Runtime度数法rotationからBabylonラジアンrotationへの投影まで到達。3D Terminalは `anima_terminal` Entity + `Surface`/`Text` component としてSceneRuntime正本へ登録し、Babylon projectionが3D Planeへ投影する形へ変更。Debugの `3D Terminal` トグルで待機表示でき、Debug Console内ログは `Command Journal` に改名。Extension Registry MVPとして in-memory の `extension_registry_validate/register/list/get/reset` と TS client を追加し、Component/Command/Tool/Action/System/Archetype/Preset/Editor/Policy/ImportExport 定義の登録・検証入口を用意。Scene Catalog MVPとして in-memory の `scene_authoring_register_scene/list_scenes/get_scene/resolve_registered_scene/reset_scenes` と TS client を追加し、登録済みSceneの一覧・取得・再解決の基盤を用意。Anima Presence MVPとして `anima.presence.ensure` を追加し、Animaを `character` Entity + AI avatar metadata としてSceneRuntimeへ登録する入口を用意。Anima Tool Catalog に `anima.presence.ensure` / `scene.object.createFromArchetype` / `scene.action.run` / `scene.load` / `scene.entity.lookAt` を追加し、resolver結果をCommandRegistry/App adapter経由でSceneRuntimeへ適用する最小導線を用意。Authoring継承/Presence本格実装、Extension永続化・実行、Scene永続登録GUIは後続。`pnpm exec vitest run src/scene-runtime/SceneRuntime.test.ts` 19 PASS、`cargo test --manifest-path src-tauri/Cargo.toml scene_runtime --lib` 16 PASS、`cargo test --manifest-path src-tauri/Cargo.toml scene_authoring --lib` 8 PASS、`cargo test --manifest-path src-tauri/Cargo.toml extension_registry --lib` 5 PASS、`pnpm exec vitest run src/scene-runtime/SceneRuntime.test.ts src/command/animaPlanner.test.ts src/command/CommandRegistry.test.ts` 42 PASS、`pnpm exec vitest run src/App.terminal.test.tsx` 13 PASS、WDIO `T-W-BAB-09` / `T-W-BAB-10` / `T-W-BAB-11` / `T-W-BAB-LOOK-01` / `T-W-BAB-TERM-01` PASS、証跡 `e2e/wdio/screenshots/anima-3d-terminal/anima-terminal-visible-toggle.png`、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS。
- **Babylon Mixamo FBX retarget調整**: 検証済（2026-06-23）— Mixamo 9ファイルのBabylon限定retargetで、FBX rest hierarchyからsource animated world positionsを復元し、肩/腕はsource world delta + segment direction correctionで補正。Mixamo手首/指QuaternionはVRM手指軸と合わず手先が伸びるため、Three.js/three-vrm `retargetFbxToVrm()` 変換済みhand/finger trackだけをBabylon直FBX body/arm/leg経路へ合成するハイブリッドへ変更。全身Three変換clip置換と上肢全体Three置換は `typing.fbx` の腕位置が悪化したため不採用。Windows QA `OribisBabylonMixamoRetargetProof` Last Result 0、`retarget-proof-20260623-183118` でbodyVideos=9/closeupVideos=9、最新18動画を `C:\Users\admin\Pictures\agante-projects\oribis\videos` 直下に配置。1.5s代表フレームではTポーズ/Aポーズfallbackと腰下反転は見えず、手先が棒状に伸び続ける破綻も見えない。
- **Mixamo generated VRMA intake**: 取り込み済（2026-06-25）— sysdev-2 `feature/babylon-vrm-motion-sysdev2` commit `c01ea3a22567b412954faa2401a8f898315c7daa` から、Producer訂正後の対象だけを抽出。`animations/generated-vrma/*.vrma` 9本（Typing-Stand除外）、FBX2glTFを前段に使いglTF nodesからMixamo humanBonesを名前解決して `VRMC_vrm_animation` 拡張を付与しGLBコンテナへpackして `.vrma` として扱うVRMA生成パイプライン `scripts/convert-mixamo-to-vrma.mjs`、`scripts/qa/run-babylon-generated-vrma.ps1`、`e2e/wdio/tests/babylon-generated-vrma.spec.ts` を追加。直接FBXをVRMAへ変換する機能ではない。OribisClip経路、FBX直/Three比較系、Typing-Stand、設計資料、AnimationEditor登録方針は除外。検証: `node --check scripts/convert-mixamo-to-vrma.mjs` PASS、9本VRMAのGLB/glTF magic確認、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS。注意: 取り込んだWDIO specはBabylon VRMA reference hook未接続のため、現developでは証跡再現ハーネス扱い。
- **Animation Creator generated VRMA catalog bridge**: 実装済（2026-06-25）— Animation Creator Pluginへgenerated VRMA 9本の一覧・選択・preview要求導線を追加。`animation-creator:vrma-preview` EventをApp側で受け、Babylon VRMA playback APIが未接続なら明示的に失敗結果を返す橋渡しまで実装。現時点ではVRMA本再生hookは未実装。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/plugin/__tests__/UIRenderer.test.tsx src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=25000 --reporter=verbose` 51 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/babylon-renderer.spec.ts --grep "T-W-BAB-ANIMCREATOR-01"` 1 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Worker 3D presence / Worker naming migration**: 実装済（2026-06-25）— `worker.vrm` をWorker用モデルとして追加し、SceneRuntimeの `worker_presence` Entityは暫定でモデルscale 0.5倍、`role: worker` / `presenceType: worker-avatar` / `asset: /worker.vrm` を持つ永続Worker avatarとして登録する。Babylon側はSceneRuntime asset URLが `.vrm` の場合もGLB互換loader extensionを明示して読み込む。AnimaからWorkerへ依頼した場合のWorker Virtual Terminalは固定 `ANIMA → WORKER` ではなく、実際のAnima名とWorker名を `Anima → worker` のように表示する。ユーザー向け表示と新規Tauri/TS APIは `Worker` / `list_worker_configs` / `send_to_worker` / `create_worker_config` / `update_worker_full_config` を優先し、既存 `Department` API/型/ファイル名は互換aliasとして残す。AI tool catalogには `worker.presence.ensure` を追加し、Worker avatarを明示的にSceneRuntimeへ出す導線を用意。移動はAnima専用入口だけでなく `scene.entity.navigateTo` / `scene.entity.navigateToObject` を追加し、任意のSceneRuntime Entityが `movement` / `path` componentでBabylon Recast/NavMesh経路を要求できる。`scene.object.moveTo` は即時座標編集、`scene.entity.navigate*` はランタイム移動として分離。`ensureAnimaPresence` / `ensureWorkerPresence` は作成成功後にSceneRuntime snapshotを即更新する。キャラクター同士の動的回避は `navigation` componentに `collisionQueryRange` / `pathOptimizationRange` / `separationWeight` / `maxAcceleration` / `reachRadius` を追加し、Babylon projection側の Recast Crowd System がAnima/Workerをagent化して実移動・局所回避を担当する形へ変更。NavMesh bake対象は床など静的geometryに限定し、Anima/Workerはbakeせずruntime crowd agentとして扱う。WDIO `T-W-BAB-SB-01` ではスタジオuilderのPersonal Zone生成後、`anima_presence` が作業机へ、`worker_presence` がWorker wait spotへ別々にNavMesh移動し、両方とも `movement.state=arrived` / `characterControl.activeAction.status=completed` / position・rotation変化 / Crowd enabled / Crowd agents>=2 まで確認済み。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、`rtk cargo test --manifest-path src-tauri/Cargo.toml scene_runtime --lib` 20 PASS、focused Vitest `useWorkers` / `useDepartmentChats` / `DepartmentChatPanel` / Worker presence / Anima-requested Worker terminal / SceneRuntime VRM loader / Worker onboarding 29 PASS、`animaPlanner` / Worker terminal / SceneRuntime VRM loader focused 4 PASS、`worker.presence.ensure` 追加後のplanner/terminal focused 3 PASS、role名称修正後のCommandRegistry/BabylonAvatarViewer/planner/terminal focused 5 PASS、App adapterでWorker `scene.entity.navigateToObject` が `movement` component更新へ流れるfocused test 1 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/babylon-renderer.spec.ts --grep "T-W-BAB-(WORKER-01|SB-01)"` 2 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/babylon-renderer.spec.ts --grep "T-W-BAB-SB-01"` 1 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Scene Mode Split / Stage renderer**: 一部実装済（2026-06-25）— 初回リリース向けの軽量 `stage`（ステージ）、現行の動的作業空間 `studio`（スタジオ）、将来の広域自由世界 `world`（ワールド）を分ける方針を整理し、Stageから着手。SceneRuntime正本は共通、RendererだけsceneKindでdynamic importする。`SceneViewer` を追加し、通常起動の初期値は `stage`、Vitest互換時は既存期待を維持するため `studio` fallback、WDIO/実アプリ互換toggleは `stage` / `studio` を `oribis_scene_kind` に保存する。`StageSceneViewer` はthree.jsをlazy loadし、丸い床、静止Anima/Worker、SceneRuntime上のrenderable object最小投影を行い、`anima_presence` / `worker_presence` は描画対象から除外する。`studio` は既存 `BabylonAvatarViewer` をlazy loadし、Babylon/Recast/Havok/Crowd系の既存動的世界機能を維持。`world` は予約placeholder。Vite devではStage初回ロード時のoptimize reloadを避けるため `three` をoptimizeDepsへ追加。production buildでは `StageSceneViewer-*.js` と `BabylonAvatarViewer-*.js` が別chunkとして出力されることを確認。Stage初期表示時にBabylon/Havok/Recast系resource/script URLがロードされないことをWDIOで実測する検査を追加。Babylon smokeは非表示status textではなく `data-load-state` / `data-load-message` / `data-model-policy` でVRM GLB互換ロードを検証する形へ修正。計画書: `deliverables/plan-scene-mode-split-20260625.md`。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/components/SceneViewer.test.ts src/App.vrm.test.tsx --testTimeout=25000 --reporter=verbose` 8 PASS、`rtk pnpm exec vite build` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/stage-renderer.spec.ts --grep "T-W-STAGE-01"` 1 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/babylon-renderer.spec.ts --grep "T-W-BAB-01"` 1 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Scene Mode Split / Stage activity furniture update**: 実装済（2026-06-25）— SceneRuntime document / Scene Authoring packageへ `sceneKind` を追加し、`stage` / `studio` / `world` と旧名 `static_stage` / `dynamic_world` の正規化を実装。Scene Editor sampleは `stage` の空Sceneとして保存し、Scene Builder生成は `studio` と明示。Anima Tool Catalog / CommandRegistry / App adapterに `scene.stage.activity.start` / `scene.stage.activity.end` を追加し、Stage上で作業/休憩/睡眠用の一時家具Entityをmetadata付きで生成し、該当temporary家具だけ削除できる導線を追加。Settings > General に `シーンモード` selectorを追加し、Stage/Studio選択を `oribis_scene_kind` / `oribis_avatar_render_engine` へ保存する導線を追加。Scene EditorのsceneKind表示とScene BuilderのsceneKind選択もWDIOで確認。Studio初期表示ではStage renderer DOMが存在せず、Stage/three系resource URLがロードされないこともWDIOで確認。Settingsから `stage` -> `studio` へ切り替えた時にStage renderer DOMが消え、Studio/Babylon rendererへ切り替わることも確認。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/command/CommandRegistry.test.ts src/command/animaPlanner.test.ts src/App.terminal.test.tsx src/components/SceneViewer.test.ts --testTimeout=30000 --reporter=verbose` 53 PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml scene_authoring --lib` 10 PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml scene_runtime --lib` 20 PASS、`rtk pnpm exec vite build` PASS、WDIO Stage `T-W-STAGE` 3 PASS（`T-W-STAGE-01` Stage軽量renderer、`T-W-STAGE-02` 作業家具生成/削除、`T-W-STAGE-03` Settings scene mode導線 + Stage->Studio切替）、WDIO Studio `T-W-BAB-01` 1 PASS（Studio表示時のStage/three未ロードguard含む）、WDIO Scene plugin `T-W-BAB-SE-01` / `T-W-BAB-SB-01` 2 PASS。注意: WDIOは並列実行すると `tauri-driver` / app sessionが衝突するため直列実行する。runner cleanupで既知の `ELIFECYCLE Command failed` 表示が出る場合があるが、上記Stage/Scene plugin実行はexit code 0かつspec PASS。
- **Plugins AI-native foundation flow**: Codex-Adviserレビュー済・P0実装済（2026-06-25）— 推奨順は `Core正本 → Adapter境界 → Plugin Action/Tool Schema → 権限/監査wiring → 永続設定 → 商用配布`。理由: 現状はPlugin一覧/manifest/builtin/capability/権限がフロント/Rust/HostAPIに分散し、AI tool契約も `name/description/handler` だけでは入力schema・副作用・承認・artifact契約が不足。P0として後方互換を維持した `PluginToolDescriptor` / typed `ai.registerTool`、スタジオuilder tool descriptor化、HostAPI `listAiTools` / `ai:registerTool` のdescriptor保持、descriptorから人間向けPlugin tool formを生成する `createPluginToolFormSchema`、`usePluginSystem().pluginToolCatalog` を追加。これにより、AI tool catalogと人間操作UIを同じAction Schemaから派生できる入口を作った。注意: schemaから生成できるのは最低限の操作formであり、タブ分け・情報密度・主要操作配置・危険操作の分離・文言はPluginCreator内蔵スキル/ガイドで設計補正する。PluginCreatorは一般ユーザがAIにPluginを作成/更新させるためのOribis内蔵スキルであり、Plugin新規作成、既存更新、Action Schema、AI tool catalog、人間向けUI設計、権限/承認/監査、テスト/プレビュー、配布前チェックまで含める。UI/Discord/Virtual Terminal/Plugin iframeはAdapterであり正本ではない。今やらないこと: Plugin/App名称リファクタ、native plugin/sidecar一般開放、`tauriInvoke`任意拡大、未審査Plugin導入、secret平文受け渡し。次段階: Core側Plugin registry/tool catalog正本化、権限/監査wiring、永続設定。検証: `rtk pnpm exec vitest run src/plugin/__tests__/toolActionSchema.test.ts src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/UIRenderer.test.tsx src/plugin/__tests__/usePluginSystem.test.ts src/worker-core/session.test.ts src/command/CommandRegistry.test.ts src/command/typingScriptDsl.test.ts --testTimeout=25000 --reporter=verbose` 111 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS。
- **Plugins AI-native foundation flow P1/P2 update**: 実装済（2026-06-25）— Rust Core側に `plugin::builtin` registryを追加し、`scene-editor` / `scene-builder` / `animation-creator` のbuiltin manifest/capability/default enabledをCoreから取得できるようにした。`plugin_scan` / `plugin_get_manifest` / `plugin_permission_*` / Action access判定はdisk manifestだけでなくbuiltin fallbackを参照するため、スタジオuilderのAI tool pluginもCore側権限経路で扱える。HostAPIは `ai.registerTool` / `ai.unregisterTool` / `invoke.call` の `plugin:audit` を発火し、`usePluginSystem().pluginToolCatalog` へ登録済みTool descriptorを公開する。PluginCreator内蔵スキルは一般ユーザ向けのPlugin作成/更新スキルとして更新し、Plugin Action Schema、`oribis.ai.registerTool(descriptor, handler)`、AI tool catalog、人間向けUI設計、最小権限、危険操作承認、テスト/プレビュー、配布前チェックを含む形にした。`<create-plugin>` 受け取り側の古いapp表記ログもPlugin表記へ修正。後続でplugin tool catalog永続化、permission boundary hardening、PluginCreator UI entry、package Inspect/install gate、permission viewer、audit viewer、WDIO smokeまで完了済み。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 179 PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml skill --lib` 6 PASS、`rtk pnpm exec vitest run src/plugin/__tests__/toolActionSchema.test.ts src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/worker-core/session.test.ts src/command/CommandRegistry.test.ts --testTimeout=25000 --reporter=verbose` 70 PASS、`rtk pnpm exec vitest run src/skill/executeSkill.test.ts src/plugin/__tests__/toolActionSchema.test.ts src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/App.terminal.test.tsx --testTimeout=25000 --reporter=verbose` 55 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Plugins AI-native foundation flow P2 catalog persistence**: 実装済（2026-06-25）— `plugin_tool_catalog_list/upsert/remove` をRust/Tauri commandとして追加し、OribisHome plugin storage配下へ直近Tool descriptor catalogを永続キャッシュする。tool名は `sceneBuilder.describePlan` のようにドットを含むため、ファイル名ではなくJSON map内キーとして扱う。HostAPIは `ai.registerTool` / `ai.unregisterTool` 時にbest-effortでCore側catalogを更新し、`plugin-tools.jsonl` auditへupsert/removeを記録する。`usePluginSystem` は起動時に `plugin_tool_catalog_list` を読み、live plugin再登録前でも前回catalogをUI/AI操作候補へ復元する。live registrationが正、persistent catalogは起動直後・監査・UI補助用のcacheという境界。PluginCreator専用UI、未審査Plugin install gate、permission viewer、audit viewerは後続項目で実装済み。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 181 PASS、`rtk pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/plugin/__tests__/toolActionSchema.test.ts --testTimeout=25000 --reporter=verbose` 32 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Plugin permission boundary hardening**: 実装済（2026-06-25）— Codex-AdviserレビューのP0指摘に対応。HostAPIはmanifest宣言capabilityだけでなくRust `plugin_permission_check` のdecisionを毎RPC前に確認し、`prompt/denied/未宣言/check失敗` は拒否する。builtin pluginはCore registry上でenabledかつmanifest宣言済みcapabilityならtrusted grantとして扱う。`plugin_tool_catalog_upsert/remove` はplugin enabled + `aiTool` grantを必須化し、無効/未許可pluginが永続AI tool catalogへ残す経路を塞いだ。`usePluginSystem().pluginToolCatalog` はlive/persistedを分離し、enabled pluginだけを公開する。Worker側のplugin tool invokerはHostAPI未ロード時に成功扱いせず `failed` を返す。検証: `rtk pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/plugin/__tests__/toolActionSchema.test.ts --testTimeout=25000 --reporter=verbose` 33 PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 183 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Plugins/App/Native Extension revised flow**: Codex-Adviser + Web調査済・計画更新（2026-06-25）— 旧前提の「native plugin/sidecar一般開放しない」は修正。Oribisの拡張基盤は `User Plugin / Builtin App / Native Extension` の3層に分ける。`User Plugin` はAI/一般ユーザが作るTS/JS + HostAPIの安全な拡張。`Builtin App` はOribis同梱の一級機能UIで、必要なら承認済みNative Extensionへ依存する。`Native Extension` はRust/WASM/sidecar能力を持つ低レイヤ拡張で、ユーザもRustを触れるが、P0では本体プロセスへの任意`dylib`直ロードは禁止。P0は `Native Extension Dev Mode` として sandbox workspace、manifest、capability承認、sidecar/WASM template、`cargo check/test`、dev署名/ローカルtrust、変更後再承認までを入れる。P1以降で配布署名、ABI v1、extension lifecycle、rollback、Trusted Native Extensionを扱う。参考: Tauri capabilities/permissions/sidecar、VS Code extension host/workspace trust、WASI/Wasmtime capability sandbox、Deno permissions、Unity/UE native plugin/module分離。次実装: manifestへ `plugin_type` / `trust_level` / `native_dependencies` / `dev_mode` を追加し、User Pluginからnative直依存を禁止、Builtin App/Native ExtensionだけをRust能力の入口にする。
- **Plugins/App/Native Extension manifest P0**: 実装済（2026-06-25）— manifestへ `plugin_type` / `trust_level` / `native_dependencies` / `dev_mode` を追加し、`runtime: wasm` をNative Extension Dev Mode入口として追加。`User Plugin` は `runtime: webview` のみ許可し、native依存とbuiltin/nativeSigned trust宣言を拒否。`Builtin App` はwebview UIとしてNative Extension依存を宣言可能。`Native Extension` は `runtime: sidecar|wasm` のみ許可し、release扱いでは `trust_level: nativeSigned` を必須、`dev_mode: true` ではローカル開発用unsignedを許可する。DTO/TS型も同じ分類を読めるよう更新。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 190 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension Dev Mode scaffold/check**: 実装済（2026-06-25）— Rust/WASM/sidecarを触る入口として `plugin_native_dev_scaffold` / `plugin_native_dev_check` を追加。OribisHome `plugins/{id}` 配下に `plugin_type: native_extension` + `dev_mode: true` のmanifest、`Cargo.toml`、`src/main.rs` を生成し、runtimeは `sidecar` / `wasm` のみ許可する。checkは任意shell文字列を受け取らず、対象plugin idから固定フォルダを解決して `cargo check` / 任意の `cargo test` だけを実行する。P0範囲では本体プロセスへの任意dylibロードは禁止のまま。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 193 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension Dev Mode local trust**: 実装済（2026-06-25）— `plugin_native_dev_trust` / `plugin_native_dev_trust_status` を追加し、manifest/Cargo/src/存在する実行ファイルのsha256を `.security/native-dev-trust.json` へローカル承認記録として保存する。source変更後はhash不一致で `needs_reapproval` になり、Dev Mode sidecarのprepare時に未承認/変更済みなら拒否する。local trust済みDev Modeだけ、従来の署名なしsidecar preflight拒否を `native extension dev mode local trust preflight passed` として通す。release扱いのNative Extensionは引き続き `trust_level: nativeSigned` が必要。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 194 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension Dev Mode UI entry**: 実装済（2026-06-25）— Settings > Plugins に `Native Extension Dev Mode` パネルを追加。id/name/runtimeを指定して `plugin_native_dev_scaffold`、固定 `cargo check` の `plugin_native_dev_check`、`plugin_native_dev_trust`、`plugin_native_dev_trust_status` を実行できる。UIから任意shell文字列は入力できない。`plugin-foundation.spec.ts` もNative Devパネル可視確認へ更新。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts src/plugin/__tests__/HostAPI.test.ts --testTimeout=30000 --reporter=verbose` 53 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Plugin layer visibility in scan/UI**: 実装済（2026-06-25）— `plugin_scan` DTOとTS型に `runtime` / `plugin_type` / `trust_level` / `dev_mode` を公開し、Settings > Plugins の一覧にlayer/runtime/dev mode badgeを表示。User Plugin / Builtin App / Native Extensionの分類がCore manifest validationだけでなくUI上でも確認できる。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 194 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=30000 --reporter=verbose` 29 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Plugin package layer gate / inspect**: 実装済（2026-06-25）— `.oripkg` install時に第三者packageが `plugin_type: builtin_app` を名乗る経路を拒否し、`Native Extension` はDev Mode packageとunsigned packageを拒否する。User Pluginの既存install/export互換は維持。`plugin_inspect_package` とSettings > Pluginsの `Inspect` ボタンを追加し、install前にplugin id/name/version/runtime/plugin_type/trust_level/dev_mode/signature/install可否/block reasonを確認できる。Builtin Appは同梱Core registry、Native Extension Dev Modeはローカルscaffold/trust導線、配布Native Extensionは署名付きpackage導線へ分離する。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 200 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=30000 --reporter=verbose` 29 PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension ABI v0 manifest gate**: 実装済（2026-06-25）— manifestへ任意 `native_api_version` を追加。`User Plugin` / `Builtin App` は宣言禁止、`Native Extension` は現時点で `oribis.native-extension.v0` だけを許可し、未知ABIは拒否する。Native Dev scaffoldはsidecar/wasm両方でABI v0を明示する。これは署名/配布ABI本実装の前段であり、任意dylibロードは引き続き禁止。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 199 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **PluginCreator 3-layer guidance**: 実装済（2026-06-25）— 内蔵 `plugin-creator` skillへ `User Plugin / Builtin App / Native Extension` の3層、標準は `plugin_type: user_plugin` + `runtime: webview`、Rust/WASM/OS連携が必要な場合だけ `Native Extension Dev Mode` scaffold/check/trustを使う方針を追加。生成PluginのchecklistにもUser Plugin/Native Extension境界、Native Dev案内、`.oripkg` Inspectを含めるよう更新。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml skill --lib` 6 PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 199 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension lifecycle visibility**: 実装済（2026-06-25）— sidecar lifecycleは引き続きprepare-onlyで実spawn未解禁。`plugin_sidecar_list_sessions(plugin_id?)` を追加し、prepare/status/stopで作られたsessionをCore側から一覧できるようにした。sessionはplugin_idでfilter可能で、status/stopと同じ所有者境界を維持する。Settings > Plugins のNative Extension Dev Modeパネルへ `Sessions` ボタンを追加し、指定idのprepared sidecar session数/status/verification/spawn可否を表示できる。これによりNative Extensionの実行境界をUI/AI Adapterから監査表示しやすくした。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 201 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=30000 --reporter=verbose` 29 PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension package bundle integrity gate**: 実装済（2026-06-25）— `.oripkg` の `signature.sig` にJSON形式 `schema_version:1` / `algorithm: oribis.package.sha256.v1` / `bundle_sha256: sha256:<hex>` / 任意 `signed_by` を追加し、signature自身を除外したzip内ファイル名+内容のdeterministic sha256でbundle整合性を検証する入口を追加。これは公開鍵署名による真正性ではなく、Trusted Native Extension配布署名の前段のbundle改ざん検出。User Pluginはlegacy/fake `signature.sig` を `present_unverified` として互換維持する。後続のtrusted Ed25519 gateにより、Native Extension packageのinstall可否は最終的に `trusted_signature_verified` で判定する。`plugin_inspect_package` / Settings Inspectは `signature_state` と `signed_by` を表示できる。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 204 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、プロセスexit 0）。
- **Native Extension trusted Ed25519 signature gate**: 実装済（2026-06-25）— Codex-Adviserレビューに従い `ed25519-dalek 2.2` を追加し、`.oripkg` の `signature.sig` で `bundle_sha256` に加えて `signature_algorithm: oribis.package.ed25519.v1` / `key_id` / `signature` / `package_id` / `package_version` / `package_kind` / `manifest_sha256` / `capabilities` を検証するTrusted signature pathを追加。`algorithm` はbundle hash用、`signature_algorithm` はEd25519用に分離。署名payloadは独自の改行区切りcanonical stringで、JSON生文字列の揺れには依存しない。manifest hash、manifest id/version/plugin_type/capabilityと署名payloadを照合し、Native Extension packageは `trusted_signature_verified` でなければinstall拒否する。User Pluginは互換維持。productionの公式trusted publisher keyはまだ未登録のため、現時点では配布Native Extensionは安全側で未解禁。Dev Modeは従来通りlocal trustで扱う。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 205 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension local trusted key store**: 実装済（2026-06-25）— `plugin_package_trusted_keys_list` / `plugin_package_trusted_key_add` / `plugin_package_trusted_key_remove` を追加。保存対象はEd25519公開鍵のみで、秘密鍵や署名生成は扱わない。保存先はOribisHome plugin security配下 `package-trust/trusted-ed25519-keys.json`。`plugin_package_trusted_key_add` はkey_id文字種とbase64 public key 32bytesを検証し、Native Extension package install時の `key_id` 解決に使用する。公式publisher keyが入るまでは、ユーザーが明示登録したlocal trusted keyとtest keyだけが通る。Settings > Plugins に `Native Extension Trusted Keys` パネルを追加し、公開鍵の一覧/追加/削除をUIから実行できるようにした。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 206 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension signed package export**: 実装済（2026-06-25）— `plugin_export_signed_native_extension_package` を追加。対象は `plugin_type: native_extension` / `trust_level: nativeSigned` / `dev_mode: false` の配布用Native Extensionだけで、User PluginやDev Mode packageには使わない。秘密鍵はbase64 Ed25519 seedをコマンド引数で受けるが保存しない。生成packageにはdeterministic bundle sha256、manifest sha256、package id/version/kind、capabilities、key_id、Ed25519署名を含む `signature.sig` を差し込み、trusted key storeへ公開鍵を登録した環境でinstall可能になる。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 207 PASS、`rtk cargo fmt --manifest-path src-tauri/Cargo.toml --all --check` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Native Extension package trust launch preflight**: 実装済（2026-06-25）— Codex-Adviserレビューによりactual sidecar process spawnはまだ解禁しない判断。理由: `Running` / child handle / kill / exit監視 / timeout / 同時起動制限 / package trust再確認が未完成のままspawnすると停止不能・監査不能なOSプロセスになるため。今回のP0では、Native Extension package install成功時に `.security/package-trust/installed-native-packages.json` へ plugin_id/version/key_id/signed_by/bundle_sha256/manifest_sha256/capabilities/installed_at を保存し、`plugin_prepare_sidecar` のpreflightで配布Native Extensionのtrust record存在・version・capability一致を確認するよう接続した。Dev Modeは従来通りlocal trust、配布Native Extensionはtrusted package install recordがないとprepare段階でRejectedになる。actual spawn解禁に必要な次ゲート: sidecar専用permission、Running状態、child handle保持、stop kill/wait、stdout/stderr上限、timeout、同時起動数制限、UI明示承認。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 207 PASS、`rtk cargo fmt --manifest-path src-tauri/Cargo.toml --all --check` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/sidecar-preflight.spec.ts` 1 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension sidecar dedicated capability**: 実装済（2026-06-25）— `SpawnSidecar` の要求権限を汎用 `tauriInvoke` から専用 `sidecar` capabilityへ分離。Native Dev scaffoldは `capabilities: [sidecar]` を明示し、Plugin UIの危険権限確認にも `sidecar` を追加した。これにより「Tauri invokeが許可されているからsidecarも起動できる」という広すぎる権限経路を塞ぎ、actual spawn未解禁のままpreflight/監査境界を細分化した。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 207 PASS、`rtk pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/components/PluginsTab.test.tsx --testTimeout=30000 --reporter=verbose` 37 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo fmt --manifest-path src-tauri/Cargo.toml --all --check` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension sidecar spawn plan gate**: 実装済（2026-06-25）— actual process spawnをまだ解禁せず、`plugin_sidecar_spawn_plan(plugin_id, session_id)` を追加。既存のprepared sessionに対して `allowed=false`、未充足ゲート（例: `spawn_not_enabled_in_this_build` / `process_spawn_policy_disabled` / `child_process_handle_not_allocated` / `running_lifecycle_not_started` / `verification_not_verified`）とProcess Policy（max runtime/stdout/stderr/concurrency/spawnEnabled）を返す。Department側 `PluginsTab` のSidecar Preflight表示に `Check plan` を追加し、本体Settings > Plugins のNative Extension Dev Modeにも `Spawn plan` ボタンを追加。計画は表示専用でRun/Spawn/Executeボタンは出さない。これにより「実spawnに進める条件」をCore/UI/監査に出せるが、OSプロセス起動は引き続き不可。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 209 PASS、`rtk pnpm exec vitest run src/components/PluginsTab.test.tsx src/components/__tests__/SidecarPreflight.test.tsx --testTimeout=30_000 --reporter=verbose` 26 PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/components/PluginsTab.test.tsx src/components/__tests__/SidecarPreflight.test.tsx --testTimeout=30000 --reporter=verbose` 47 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Native Extension actual spawn command hard block**: 実装済（2026-06-25）— `plugin_spawn_sidecar` が内部でprepare-onlyを返していた曖昧さを廃止し、actual spawn未解禁buildでは明示的に拒否するよう変更。preflightは `plugin_prepare_sidecar`、実行条件確認は `plugin_sidecar_spawn_plan` に分離する。これによりコマンド名だけで「spawnされた」と誤認する経路を閉じた。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 209 PASS、`rtk cargo fmt --manifest-path src-tauri/Cargo.toml --all --check` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **PluginCreator UI entry**: 実装済（2026-06-25）— Settings > Plugins にPlugin Creatorパネルを追加。一般ユーザがPlugin要望をtextareaへ入力し、`Create with AI` から内蔵 `plugin-creator` skillをAnimaへ送る。生成された `<create-plugin>` は既存の `plugin_create_from_source` 導線でOribisHomeのPluginへ保存される。パネル内で永続/ライブ統合済み `pluginToolCatalog` も表示し、AI操作候補を人間にも見えるようにした。検証: `rtk pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/App.terminal.test.tsx --testTimeout=30000 --reporter=verbose` 52 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS。
- **Plugin package install UI**: 実装済（2026-06-25）— Settings > Plugins の存在しない `plugin_import_dialog` 呼び出しをやめ、`.oripkg` path入力 + `plugin_install_package` 実行に変更。install後は一覧をrefreshし、署名状態は `missing` / `present_unverified` / `bundle_integrity_verified` / `invalid` として表示する。`bundle_integrity_verified` はbundle改ざん検出であり公開鍵署名による信頼済み認証ではない。未審査Pluginは自動enableせず、enable/permission grantは別操作に残す。ZIP展開時はNUL/絶対path/Windows drive/root/parent traversal entryを拒否する。検証: `rtk pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/App.terminal.test.tsx --testTimeout=30000 --reporter=verbose` 52 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 183 PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Plugin package install review gate UI**: 実装済（2026-06-25）— Settings > Plugins の `.oripkg` 導入をInspect必須に変更。同じpathで `plugin_inspect_package` を実行し、`install_allowed=true` の結果を得た場合だけInstallボタンを有効化する。path変更時はinspect結果を破棄し、install関数側でも未Inspect/blocked inspectを拒否するため、UIだけでなく実行経路でも未審査導入を止める。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx --testTimeout=30000 --reporter=verbose` 21 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Plugin package atomic install**: 実装済（2026-06-25）— `.oripkg` 再インストール時に既存Pluginを先に削除する実装を廃止。temp dirへ全entryを検証・展開し、成功後だけ既存dirをbackupへrenameしてtempをinstall dirへrenameする。展開失敗時はtempを削除し、既存Pluginを保持する。置換失敗時はbackupから復旧を試みる。壊れた再インストールで既存Pluginの `manifest.yaml` とsentinelが残る回帰テストを追加。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 184 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS（既存warning 23件）。
- **Plugin permission viewer**: 実装済（2026-06-25）— Settings > Plugins の各Plugin行にPermissions表示を追加。`plugin_permission_list` でmanifest宣言capabilityごとの `granted/denied/prompt` を表示し、Grant/Deny/Revokeボタンから既存 `plugin_permission_*` commandへ接続する。操作は既存 `plugin-permissions.jsonl` auditへ記録される。検証: `rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=30000 --reporter=verbose` 29 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 181 PASS。
- **Plugin audit viewer**: 実装済（2026-06-25）— Rust/Tauri `plugin_audit_recent` を追加し、`plugin-permissions.jsonl` と `plugin-tools.jsonl` の直近イベントを読み取り専用DTOへ整形。Settings > Plugins にPlugin Auditパネルを追加し、権限変更とAI tool catalog変更の直近ログを表示できるようにした。secret/API key/tokenは対象外で、summaryのみ表示。検証: `rtk cargo test --manifest-path src-tauri/Cargo.toml plugin --lib` 182 PASS、`rtk pnpm exec vitest run src/App.terminal.test.tsx src/plugin/__tests__/usePluginSystem.test.ts --testTimeout=30000 --reporter=verbose` 29 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS。
- **Plugin foundation WDIO smoke**: 実装済（2026-06-25）— Settings > Plugins のPlugin Creator / package install / permission viewer / audit viewer が実機Tauri WebDriverで開けることを確認する `e2e/wdio/tests/plugin-foundation.spec.ts` を追加。翻訳文言に依存しないようSettingsボタン・panel・Apps tabへ安定 `data-testid` を付与。検証: `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/plugin-foundation.spec.ts` 3 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **Three.js Mixamo FBX baseline確認**: 実施（2026-06-23）— Babylon比較前の基準として、Three.js/three-vrm側だけでMixamo 9ファイルを同一VRMへ割当し、`0.5s` / `1.5s` / `2.5s`、body `rotH=-90/0/90` + close-up `rotH=0` の108 PNGを取得。証跡 `C:\Users\admin\Pictures\agante-projects\oribis\three-mixamo-reference-20260623-124807`、Windows QA `Last Result: 0` / `wdioExitCode=0`。確認範囲ではT/Aポーズfallbackと腰下全反転は見えないが、腕が胸/顔前に高く出るclipがあり、袖で手指が隠れるため、Three側を完全な正解oracleとは扱わない。
- **Worker Provider onboarding**: 修正済（2026-06-22）— Department Settingsの初期作成時にも `Use Anima setting` / oribisAI / Kimi Code OAuth / Kimi API Key / OpenAI系 / Local LLM を選択可能にし、選択結果をDepartment configの `worker_provider_mode` / `anima_provider_ref` / `model` に保存。既存のDepartment編集画面のProvider/Model選択と同じConversation provider catalogを使用。`pnpm exec vitest run src/App.onboarding.test.tsx ... -t "Worker Provider"` PASS。
- **OribisWorker Core Protocol v0**: 一部実装済（2026-06-24）— Codex CLIを包まない方針を確定。OribisWorkerを独自の開発実行主体として定義し、Actor/Worker/Task/Run/Action/Event/Artifact、Permission Matrix、Discord Adapter、Virtual Terminal/CLI境界、MVP範囲を `spec/core/oribis-worker-core-protocol.md` に追加。TS側に `src/worker-core/protocol.ts` / `actions.ts` / `store.ts` / `runtime.ts` / `orchestrator.ts` / `smoke.ts` / `session.ts` / `index.ts` を追加し、v0型、Action schema、状態遷移検証、Permission Matrix、append-only EventLog、Artifact参照、Task/Run/Action/Dialogue memory Store、Runtime Adapter interface/Registry/Permission gate、Core Store + Runtime最小Orchestrator、Debug Console smoke導線、in-memory CoreSession診断導線を実装。CodexAdviserレビューで指摘された `capability` 呼び出し側指定バイパスを修正し、Core内部で `Action.type -> Capability` を導出する形に変更。CoreSessionに `sessionId/schemaVersion/createdAt` を持たせ、観測snapshotとは別に `WorkerCorePersistedSnapshot` export/import境界を追加し、復元後もID衝突なく同一Taskを継続できるようにした。Debug Consoleには `oribis.workerCore.exportPersistedSnapshot({})` を追加。CoreSession診断にscope検証付き `file.read` Runtime Adapterを追加し、実GUIではTauri `worker_core_read_file` 経由でrepo内実ファイルを読む。scope検証付き `git.diff` Runtime Adapterも追加し、Tauri `worker_core_git_diff` 経由でrepo内pathspecの差分を読み、`contentHash/contentRef` と `patch` Artifact参照だけを残す。scope検証付き `file.patch` proposal Runtime Adapterは実適用せず、Tauri `worker_core_create_patch_proposal` から既存WritePlan proposalだけを生成して `oribis://write-plans/<planId>` Artifact参照を残す。allowlist固定の `test.run` Runtime Adapterも追加し、Tauri `worker_core_run_test` 経由で `src/worker-core/actions.test.ts` 単発Vitestを実行して `log` Artifact参照を残す。WDIO/Tauri環境から漏れる `NODE_OPTIONS` / `TS_NODE_*` は子Vitest実行時に除去。Worker dialogue turnをappend-only message + EventとしてCoreSessionに記録し、Debug Console直接実行結果もSceneRuntime上のVirtual Terminal streamへ同期。`plugin.invoke` Action/capabilityとPlugin HostAPI Bridgeを追加し、ロード済みPluginの `ai.registerTool` handlerをiframe message request/responseで呼び戻せるようにした。スタジオuilder Pluginは `sceneBuilder.describePlan` / `sceneBuilder.buildWorkspaceRoom` をAI toolとして登録し、Developer Consoleの `plugin.invoke` smokeは副作用なしの `sceneBuilder.describePlan` を呼ぶ。CoreSession v0では未ロードPlugin時は診断受付として `report` Artifactと `worker.runtime.plugin_invoked` Eventを残す。本文Artifact保存ではなくメタデータと短いpreview/参照だけを記録。Taskは診断中に複数Runを積めるよう成功時に即 `done` へ閉じない。Oribis開発はdogfooding目標の1つであり、CoreはOribis専用ではなく汎用Task実行主体として維持。Discordは正本ではなくHuman Actor入出力Adapterとして扱う。`pnpm exec vitest run src/worker-core/protocol.test.ts src/worker-core/actions.test.ts src/worker-core/store.test.ts src/worker-core/runtime.test.ts src/worker-core/orchestrator.test.ts src/worker-core/smoke.test.ts src/worker-core/session.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx --testTimeout=12000 --reporter=verbose` 94 PASS、`pnpm exec vitest run src/plugin/__tests__/HostAPI.test.ts src/plugin/__tests__/usePluginSystem.test.ts src/worker-core/session.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx --testTimeout=12000 --reporter=verbose` 82 PASS、`pnpm exec vitest run src/worker-core/store.test.ts src/worker-core/session.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx --testTimeout=12000 --reporter=verbose` 67 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`pnpm exec vite build` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts --grep "T-W-ACTION-04"` 1 PASS。
- **OribisWorker Deno Script Runtime境界**: 一部実装済（2026-06-24）— Gemini案を採用し、Workerが書く実行コードはJavaScript/TypeScript、実行環境はTauri sidecar同梱のportable Denoを第一候補に固定。ただしDenoはWorker Core本体ではなくRuntime Adapter。`script.propose` はautoでコード/目的/要求権限/依存/期待成果物をreport Artifact化し、`script.run` はconfirm必須で承認済みActionだけDeno Adapterへ渡す。`npm:` importは初期自由許可せず、許可リストまたは明示承認制。ユーザー配布時にNode.js/Deno/npmの別インストールは要求しない。TS側に `script.propose` / `script.run` Action type、Capability、Permission Matrix、`scriptRuntime.ts` 診断Adapterを追加。Rust/Tauri側に `worker_core_run_deno_script` を追加し、`ORIBIS_DENO_PATH` またはPATH上の `deno` を `--quiet --no-prompt` + Worker Core permission preview由来の `--allow-*` で実行する。開発環境には `~/.deno/bin/deno` v2.8.3 を導入済みで、`start.sh` は `ORIBIS_DENO_PATH` 未指定時に `~/.deno/bin/deno` を検出してPATHへ追加する。
- **OribisWorker Interactive Script Turn**: 一部実装済（2026-06-24）— CoreSession診断に `runInteractiveScriptSmoke` を追加。DialogueMessage 2件、承認済み `script.run` Action、`worker.terminal.opened` / `worker.terminal.command` / `worker.terminal.output` Eventを同じRun/correlationIdへ集約し、Virtual Terminal UIが読むべき最小event shapeを固定。Debug Consoleから `oribis.workerCore.runInteractiveScriptSmoke({})` で実行可能。これは通常UXではなく、Worker対話セッションとDeno実行とVirtual Terminal表示を接続するための診断導線。
- **OribisWorker 実用化フロー見直し**: Codex-Adviserレビュー済（2026-06-24）— 方針は妥当。正本はWorker Coreで、Virtual Terminal / Discord / UI / Plugin(App)はAdapter。Gemini案のJS/TS + Deno sidecarはAI生成コード実行の第一候補として採用するが、Denoは完全隔離ではなくRuntime Adapterであり、権限・監査・永続化・Artifact・Event streamはRust/Tauri + Worker Core側を正本にする。OpenCode代替の最小閉路は `readFile -> gitDiff -> proposePatch -> runTest -> summarize -> human approve apply`。`apply` は初期MVPで自動実行しない。`shell.run` は未完成扱いで、初期は `previewShell` / dry-run / allowlist のみ。Smokeは内部診断名に閉じ、実用API名と混ぜない。P0として `readFile` / `gitDiff` / `proposePatch` / `runTest` / `invokePlugin` / `proposeScript` / `runDenoScript` / `runInteractiveScript` の実用API名を追加し、旧Smoke名は互換維持（2026-06-24）。P1として `src/worker-core/capabilities.ts` を追加し、Worker Core APIごとのAction type、Capability、dry-run可否、human approval要否、既定Artifact kindをCapability Registryとして固定（2026-06-24）。さらに `src/worker-core/redaction.ts` を追加し、Store保存境界でAction input / Event payload / Dialogue contentをマスクして、Adapter表示に依存しないSecret RedactionをCore側へ移動（2026-06-24）。P1継続として `contracts.ts` / `permissions.ts` を追加し、Event/Artifact contract、Permission Manifest、Permission decision audit、Runtime result auditをWorker Core境界へ追加（2026-06-24）。Runtime `ActionResult` に timeout/cancel/retry/partialOutputRef/duration/attempt の器を追加し、timeout・AbortSignal cancel・adapter明示retryableの再試行をRuntime境界で扱えるようにした（2026-06-24）。`workspace.ts` を追加し、repo-relative path正規化、NUL/絶対path/Windows drive/URL-like/parent traversal拒否、task scope内判定を共通化（2026-06-24）。Rust/Tauri側の `worker_core_validate_relative_path` もWindows drive風path/URL-like pathを明示拒否するよう修正し、Worker Core path validation testを追加（2026-06-24）。Deterministic Patch Applyは既存WritePlan apply/proposal/rollback/scope/TOCTOU/idempotencyテスト群で再検証済み（`write_plan_apply` 16 PASS、`write_plan_` 44 PASS）。P2として `context.ts` を追加し、Task/Dialog/Event/ArtifactからWorker Core context refsを再構築し、token budget超過時にcompaction summaryを残すCore API `buildContextSnapshot` を追加（2026-06-24）。さらにOribisHome配下 `worker-core/session.json` への保存/読込Tauri API、Debug Console `savePersistedSnapshot` / `loadPersistedSnapshot`、default session復元導線を追加（2026-06-24）。`continuation.ts` と `buildContinuationPlan` も追加し、復元後にactive Task / resumable Run / pending Action / 推奨next stepを抽出して `worker.resume.plan` eventを残せるようにした（2026-06-24）。Worker Core状態変更コマンド成功後はOribisHomeへ非同期best-effort自動保存するようにし、保存失敗は操作失敗にしない（2026-06-24）。P2継続として起動時にOribisHomeのpersisted snapshotを自動load/resumeし、復元時の `worker.resume.plan` summaryだけをWorker Core Virtual Terminalへ流すApp bootstrap導線を追加（2026-06-24）。古いterminal履歴の全再生は避ける。Context Snapshot生成時は `worker.context.snapshot` eventを残し、refs/tokens/dropped/compactionsをWorker Core Virtual Terminalへ要約同期するようにした（2026-06-24）。Discord AdapterはCore側の純粋境界として `discordAdapter.ts` を追加し、Discord入力をHuman Actor dialogueとしてCoreSessionへ取り込み、Continuation PlanをDiscord向け復元通知へ整形できるようにした。DiscordはHuman Actor I/O Adapterであり、Discord専用の別正本を作らない。P2残なし。実用閉路側として `summarizeCurrentWork` を追加し、現在のCoreSessionからhandoff要約Artifact参照と `worker.summary.created` eventを作成し、Debug Console/TypingScript/Virtual Terminalへ同期できるようにした。Worker UI/自律Worker運用は後続の Workbench UI Adapter / Autonomy Plan / Workbench safe continuation / Virtual Terminal Adapter で接続済み。`pnpm exec vitest run src/worker-core/session.test.ts src/worker-core/continuation.test.ts src/worker-core/context.test.ts src/App.terminal.test.tsx --testTimeout=20000 --reporter=verbose` 42 PASS、`pnpm exec vitest run src/worker-core/session.test.ts src/worker-core/context.test.ts src/App.terminal.test.tsx --testTimeout=20000 --reporter=verbose` 42 PASS、`pnpm exec vitest run src/worker-core/session.test.ts src/worker-core/context.test.ts src/worker-core/continuation.test.ts src/worker-core/discordAdapter.test.ts src/App.terminal.test.tsx --testTimeout=20000 --reporter=verbose` 46 PASS、`pnpm exec vitest run src/worker-core/session.test.ts src/worker-core/context.test.ts src/worker-core/continuation.test.ts src/worker-core/discordAdapter.test.ts src/command/CommandRegistry.test.ts src/command/typingScriptDsl.test.ts src/App.terminal.test.tsx --testTimeout=20000 --reporter=verbose` 82 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS。
- **OribisWorker Core 実用Runtime/GUI最終検証**: 実装済（2026-06-25）— 開発環境依存の `deno` PATH前提を廃止し、`deno-bin` 同梱の `node_modules/.bin/deno` / `deno.cmd` を `worker_core_run_deno_script` が優先解決するようにした。`ORIBIS_DENO_PATH` は明示overrideとして維持。Rust unitで bundled Deno解決と実Deno script実行を検証。Developer Consoleには Worker Core smoke群（file.read / git.diff / patch proposal / test.run / plugin.invoke / script.propose / script.run / interactive script）を候補として復帰し、GUIからTask→Run→Action→Event→Artifact→Virtual Terminal→Snapshotまで辿れる。WDIOは永続CoreSession復元で件数が増える前提に合わせ、固定 `tasks=1` / `artifacts=9` 依存ではなく成功内容とフィールド存在を検証する形へ修正。検証: `cargo test --manifest-path src-tauri/Cargo.toml worker_core --lib` 7 PASS、Worker Core Vitest 14 files / 83 PASS、DeveloperConsole/Command/DSL Vitest 3 files / 41 PASS、App terminal Vitest 3 files / 54 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo check --manifest-path src-tauri/Cargo.toml --bin oribis` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS。
- **OribisWorker Deno permission preview / approval境界**: 実装済（2026-06-25）— Codex-Adviserレビュー指摘に基づき、実用API名の `runDenoScript` / `runInteractiveScript` / `invokePlugin` はhuman approval境界で止め、Developer Console診断の `*Smoke` 名だけ明示承認済みActionとして実行する形へ分離。`worker.terminal.permission_preview` Eventを追加し、Deno permission preview（read/write/net/env/run）と承認状態をVirtual Terminalへ同期。App側のWorker Core command分岐もSmoke/実用APIを混同しないよう修正。Tauri `worker_core_read_file` は大きいファイルを拒否せずscope内なら上限抜粋 + `truncated=true` で返す仕様へ変更。WDIO helperはReact textarea stateへ確実に反映する入力経路に修正。検証: `pnpm exec vitest run src/worker-core/session.test.ts src/App.terminal.test.tsx src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts --testTimeout=25000 --reporter=verbose` 76 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo test --manifest-path src-tauri/Cargo.toml worker_core --lib` 7 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts --grep "T-W-ACTION-04"` 1 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **OribisWorker Repo Task Flow**: 実装済（2026-06-25）— Developer Console診断として `oribis.workerCore.runRepoTaskFlow({ path, scopeRoot })` を追加し、1 Task内で `file.read -> git.diff -> file.patch proposal -> test.run -> summarizeCurrentWork` を連続実行できるようにした。patchはproposal-onlyで適用しない。CommandRegistry、TypingScript DSL、Developer Console候補、App adapter、Worker Core Virtual Terminal連携を追加し、GUI上で `readFile/gitDiff/proposePatch/runTest/summarize` の全step成功とArtifact増加を確認できる。検証: `pnpm exec vitest run src/worker-core/session.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx src/App.terminal.test.tsx --testTimeout=25000 --reporter=verbose` 84 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo test --manifest-path src-tauri/Cargo.toml worker_core --lib` 7 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **OribisWorker Workbench UI Adapter**: 実装済（2026-06-25）— Debug Console内に `Worker Core Workbench` を追加し、TypingScript文字列を手入力しなくてもPath/Scopeを指定してRepo Task Flowを直接起動できるようにした。これはCore正本ではなくUI Adapterで、実行結果は既存のWorker Core session / Event / Artifact / Virtual Terminalへ収束する。検証: `pnpm exec vitest run src/components/DeveloperConsole.test.tsx src/worker-core/session.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts --testTimeout=25000 --reporter=verbose` 65 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo test --manifest-path src-tauri/Cargo.toml worker_core --lib` 7 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（Workbenchボタン経由でRepo Flow実行確認、runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **OribisWorker Workbench safe continuation**: 実装済（2026-06-25）— Workbenchに `Run safe next` を追加し、`buildAutonomyPlan` の結果が `approval=not-required` かつ `oribis.workerCore.*` の安全コマンドを返す場合だけ、同じTypingScript safe parser経由で次ステップを連続実行できるようにした。承認待ち/実行中/待機中Actionや `command=none` では実行しない。apply/sidecar spawn/shell writeは引き続き未解禁。検証: `rtk pnpm exec vitest run src/components/DeveloperConsole.test.tsx src/worker-core/autonomy.test.ts src/worker-core/virtualTerminalAdapter.test.ts src/App.terminal.test.tsx --testTimeout=30000 --reporter=verbose` 36 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **OribisWorker Discord Adapter status outbound**: 実装済（2026-06-25）— Core snapshotからDiscord向けstatus本文を生成する `formatWorkerCoreDiscordStatus` / `createWorkerCoreDiscordStatusMessage` を追加。既存のDiscord ingress / resume noticeと合わせて、DiscordはHuman Actor入出力Adapterであり正本ではない境界を維持。さらに `enqueueDiscordOutbound` / `acknowledgeDiscordOutbound` / `enqueueWorkerCoreDiscordStatusMessage` / `listQueuedWorkerCoreDiscordOutbox` / `listWorkerCoreDiscordOutbox` を追加し、外部送信前のDiscord OutboxをWorker Core EventLog上の `worker.discord.outbox.queued` として保持し、送信後は `sent` / `failed` ackを監査Eventとして戻せるようにした。Developer Console / Worker Core Workbenchにも `Discord Outbox` 診断UIを追加し、外部tokenなしでqueue一覧・status queue・sent/failed ackを確認できる。さらに `drainWorkerCoreDiscordOutbox` を追加し、実Discord tokenをCoreへ渡さず、注入されたsender関数でqueued outboxを送信してsent/failed ackを戻すAdapter境界を用意。実Discord token管理・bot接続は外部Adapter責務として未接続。検証: `pnpm exec vitest run src/worker-core/discordAdapter.test.ts src/worker-core/session.test.ts src/components/DeveloperConsole.test.tsx --testTimeout=25000 --reporter=verbose` 34 PASS、`rtk pnpm exec vitest run src/worker-core/discordAdapter.test.ts src/worker-core/session.test.ts --testTimeout=25000 --reporter=verbose` 29 PASS、`rtk pnpm exec vitest run src/command/typingScriptDsl.test.ts src/components/DeveloperConsole.test.tsx src/worker-core/discordAdapter.test.ts src/worker-core/session.test.ts --testTimeout=30000 --reporter=verbose` 59 PASS、`rtk pnpm exec vitest run src/worker-core/discordAdapter.test.ts src/worker-core/session.test.ts --testTimeout=30000 --reporter=verbose` 31 PASS、`rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS。
- **OribisWorker Autonomy Plan**: 実装済（2026-06-25）— Core snapshotから `idle` / `review_pending_action` / `recover_running_action` / `resume_waiting_run` / `continue_task` の自律計画を生成する `buildAutonomyPlan` を追加。承認待ち・実行中・待機中Actionがある場合はhuman approval必須として止め、承認不要で継続可能なTaskだけ次step候補を提示する。計画は `worker.autonomy.plan` EventとしてVirtual Terminalへ同期し、実行はしない。CommandRegistry、TypingScript DSL、Developer Console候補、App adapter、WDIO action-platformへ接続済み。検証: `pnpm exec vitest run src/worker-core/autonomy.test.ts src/worker-core/session.test.ts src/worker-core/discordAdapter.test.ts src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx src/App.terminal.test.tsx --testTimeout=25000 --reporter=verbose` 92 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、`cargo test --manifest-path src-tauri/Cargo.toml worker_core --lib` 7 PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **OribisWorker Virtual Terminal Adapter**: 実装済（2026-06-25）— App内に散っていたWorker Core terminal表示整形を `virtualTerminalAdapter.ts` へ切り出し、`worker.resume.plan` / `worker.context.snapshot` / `worker.summary.created` / `worker.autonomy.plan` / `worker.terminal.*` Eventをterminal frameへ整形する純粋Adapter境界にした。App/SceneRuntimeはAdapter出力を投影するだけにし、Discord Adapter同様にCore正本と表示口を分離。検証: `pnpm exec vitest run src/worker-core/virtualTerminalAdapter.test.ts src/App.terminal.test.tsx src/worker-core/session.test.ts --testTimeout=25000 --reporter=verbose` 48 PASS、`pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS、WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 bash scripts/run-wdio-tests.sh --spec tests/action-platform.spec.ts` 7 PASS（runner cleanupで既知の `ELIFECYCLE Command failed` 表示あり、spec/プロセス結果はPASS）。
- **その他**: pending-tasks.md に移動済み。Producer指示があれば復帰

### 実装フロー（codex-adviser レビュー済 2026-05-07）

```
Track 1: 記憶システム（G1） — memory.md v3.5
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: 基盤 ✅ 完了                                        │
│   G1-a: SQLite基盤 + oribis-meta パーサー + migration       │
│   G1-b: CLAUDE.md oribis-meta出力指示反映                   │
│   G1-c: Level 1/2 trigger + scheduler配線                   │
│   G1-d: telemetry（meta欠落率監視）                         │
│                                                              │
│ Phase 2: 統合 + 想起                                         │
│   G1-e: L3 4ch検索 + ContextMode ✅ 完了                     │
│   G1-f: 忘却曲線 + recency decay ✅ 完了                     │
│     ※ G1-e直後に配置（ranking基準線確立のため）             │
│                                                              │
│ Phase 3: 深化 + 進化 + 意味検索                              │
│   G1-EL: 軽量エンティティリンク（§8.6） ✅ 完了             │
│     oribis-meta topics/entities → SQLiteエンコード           │
│   G1-g: Level 2 consolidation（LLM非同期・stub→実装）✅ 完了│
│   G1-h: relationship_model ✅ 完了                           │
│     L3注入 + 即時Boundary/Correction更新                    │
│   G1-SM: self_model（§6.5）✅ 完了                           │
│     evidence蓄積+L3注入+L1 decay/promotion                 │
│   G1-i: 記憶進化（A-MEM軽量版）✅ 完了                     │
│     L1でstrengthen/supersede/promote/no-op 4操作            │
│   G1-j: Operational Memory（worker_patterns）✅ 完了        │
│   G1-k: ハイブリッドベクトル検索 ✅ 完了                     │
│     fastembed(e5-small)+cosine+Phase3ランキング             │
└─────────────────────────────────────────────────────────────┘

Track 2: AnimaMode（G3） — anima.md §6  ✅ 完了
┌─────────────────────────────────────────────────────────────┐
│ バックエンド: 3分岐（Cache/Ai/Hybrid）✅                    │
│ UI↔backend モード名統一 ✅ cb9db93                          │
│   フロント: off/cache/hybrid/ai（Rust AnimaMode と一致）     │
│   Tauriコマンド: anima_mode パラメータ追加・不正値エラー返却 │
│   UIトグル: off→cache→hybrid 3段切替                        │
└─────────────────────────────────────────────────────────────┘

Track 3: オーケストレーター — anima-orchestrator-architecture.md
┌─────────────────────────────────────────────────────────────┐
│ P1 ✅ 完了（Epic: epic-oribis-orchestrator-p1-20260508）    │
│   types.ts 5型定義 + Rust Worker基盤(events/dept/worker_mgr)│
│   narration.rs + MCP tools/event_feed + Speech Queue        │
│   lib.rs 8 Tauriコマンド登録                                │
│   フロントエンド5コンポーネント(WorkerPanel/DrawerAnima/     │
│     DrawerDepartment/DrawerEventFeed/XtermTerminal拡張)     │
│   App.tsx 二重タブ再編 + PTYパネル統合                       │
│   テスト20件(前端) + 796件(Rust)中新規追加分全PASS          │
│   Onboarding Step3 Department改編                           │
│                                                              │
│ P1品質修正 ✅ 完了（2026-05-08）                             │
│   タスク1: Worker kill統合(Rust) — set_worker_pid/          │
│     get_worker_pid/pty_kill統合 + 15テストPASS              │
│   タスク2: WorkerPanel kill順序(TS) — forwardRef/           │
│     useImperativeHandle kill() + xtermRefs Map管理          │
│   タスク3: narration per-worker cursor —                    │
│     get_batch_for_worker/list_event_workers追加             │
│     fetch_and_process_batch_inをper-worker独立取得に変更    │
│   タスク4: MCP session identity —                           │
│     ClientInfoにworker_id/worker_session_id追加             │
│     handle_write_event_inで実worker_id→token_prefix fallback│
│   テスト: 812PASS/1FAIL(既存・無関係)                        │
│   ブランチ: sysdev-1/oribis-orch-p1-fix (4e5d6c8)           │
│   成果物: docs/deliverables/p1-fix-20260508/                │
│                                                              │
│ P2 ✅ 実装済（Epic: epic-oribis-orchestrator-p2-20260510）   │
│   CRUD API + PipelineView/DepartmentLane UI                  │
│   OrchestratorEditor タブUI（5タブ）                         │
│   PromptsTab セキュリティ（symlink/UUID/10MB制限）           │
│   Delete/Rename hasActiveWorker UI拒否                       │
│   vitest 563 PASS / cargo test 955 PASS（2026-05-11）        │
│                                                              │
│ P2追加実装 ✅（sysdev-1/oribis-orchestrator-p2, 2026-05-12） │
│   DrawerAnima 内部タブ実装（Status/Prompt/Memory/Console/    │
│     Settings）＋ CSS テーマ対応（CSS変数・クラス使用）        │
│   Prompt タブ: L1/L2/AnimaCache 全バックエンドに表示         │
│   Deep Reasoning delegation（DelegatingAdapter + threshold） │
│   GeneralTab Orchestrator対応 + DrawerAnima設定統合          │
│   vitest 568 PASS / cargo test 1036 PASS（2026-05-12）       │
│                                                              │
│ P3 ✅ 完了（sysdev-1/oribis-orchestrator-p2, 2026-05-12）   │
│   P3-A: scheduler engine（parse_interval/should_run_now/    │
│     start_scheduler_loop/update_schedule_item）6254a02      │
│   P3-B: DELEGATE_TO 自動ルーティング（マーカーパース→        │
│     target dept channel emit）f7ab1a7                       │
│                                                              │
│ セキュリティ修正 ✅ 完了（071e92b, 2026-05-12）              │
│   assetProtocol scope制限 + Plugin icon XSS対策             │
│   + filepath traversal修正                                  │
│                                                              │
│ 起動時Anima自動接続 ✅ 完了（b6f7e5a, 2026-05-12）           │
│   プロジェクト選択後1.2秒で時刻別挨拶を自動送信             │
│   （おはよう/こんにちは/こんばんは）                         │
│                                                              │
│ open_cli_terminal WSLフォールバック修正 ✅（b87f53d）        │
│   powershell.exeフルパス(/mnt/c/Windows/System32/...)追加   │
│                                                              │
│ GUI動作確認 ✅（WSLg + スクリーンショット確認, 2026-05-12）  │
│   自動挨拶「こんばんは、プロデューサー。何かありましたか。」  │
│   表示確認済                                                 │
└─────────────────────────────────────────────────────────────┘

Track 5: Web Remote — spec/ui/web-remote.md
┌─────────────────────────────────────────────────────────────┐
│ P1 ✅ 完了（sysdev-1/web-remote-p1, 2026-05-13）            │
│   axum HTTP+WSサーバー（standalone binary: web_remote_server)│
│   静的配信（ServeDir + SPA fallback）                        │
│   POST /api/invoke/:cmd（allowlist制）                       │
│   api-client.ts（isTauri切替）                               │
│   Bearer token認証 + CORS                                    │
│   /ws/events WS（Rust→WS broadcast）                        │
│   smoke E2E 5/5 PASS / cargo test 1016 PASS                 │
│                                                              │
│ P2 ✅ 完了（sysdev-1/web-remote-p2, 2026-05-14）            │
│   WS受信ディスパッチャ（WS→Rust dispatch_emit + callback）  │
│   AndroidタッチCSS（@media coarse / 44px / 100dvh）          │
│   Cargoワークスペース + oribis-web-remoteクレート分離        │
│   pnpmワークスペース + @oribis/web-remote外皮パッケージ      │
│   Tailscale+Android Chromeセットアップガイド                 │
│   cargo test 1022 PASS / pnpm test 360 PASS                 │
│                                                              │
│ P3 未着手                                                    │
│   WS ストリーミング/PTY/音声（WR-11〜15）                   │
│   HTTPS/WSS対応・PWA化・Android実機確認                      │
└─────────────────────────────────────────────────────────────┘

Track 4: MCP Server（G9） — mcp-server.md v3.1
┌─────────────────────────────────────────────────────────────┐
│ Phase 1-9: ✅ 完了（3c6e86b on sysdev-1/mcp-server）       │
│   Broker(Unix Socket) + Token管理 + 状態機械               │
│   Tools: memory_search/save, speak/set_expression/notify    │
│   Tools: set/get_anima_state, suppress/resume_narration     │
│   Resources: 6 URI（memories/RM/open_loops/affinity/state） │
│   Auth + Audit + Rate Limiting + DENIED_TOOLS enforcement   │
│   111テスト PASS（107 unit + 4 integration）                │
│                                                              │
│ Phase 10: GUI統合 ✅ 完了（ff8efea on sysdev-1/oribis-orchestrator-p2）│
│   P10-4: narration:speak subscription（useAnima.ts）✅       │
│   P10-5: Worker MCP自動注入（pty_spawn_with_env + ORIBIS_MCP_SOCKET/TOKEN）✅ │
│   P10-6: revoke_by_prefix + token lifecycle テスト追加 ✅    │
│   GUI: mcp_list_tokens / mcp_issue_token / mcp_revoke_token  │
│        + DrawerAnima Settings MCP セクション ✅             │
│   1054テスト PASS                                            │
└─────────────────────────────────────────────────────────────┘

推奨実行順:
  ① G1-e ✅ + G3(UI) ✅ 並列
  ② G1-f
  ③ G1-EL
  ④ G1-g ✅
  ⑤ G1-h ✅
  ⑥ G1-SM ✅
  ⑦ G1-i / G1-j ✅
  ⑧ G1-k ✅
  ⑨ Track 3 + Track 4 Phase 10
```

**並行作業**: バグ修正（TASK-G等）・FBXリターゲット（Producer実施中）はトラックと独立して進行可。

---

### 機能追加

| 優先度 | ID | 内容 | 関連spec | 状態 | 備考 |
|--------|-----|------|----------|------|------|
| HIGH | G5 | compute_sub_context スマートキャッシュ選択 | anima.md §8 | 実装済 | cache.rs + pipeline.rs 接続完了 |
| HIGH | G1 | 4レイヤー記憶システム + 自己進化 | memory.md v3.5 | 実装済 | Phase 1-3完了。G1-a〜G1-k 全タスク完了 |
| HIGH | G1-a | └ SQLite基盤 + oribis-meta パーサー + migration | memory.md §9/§13 | 実装済 | e110c74 (2026-05-05) |
| HIGH | G1-b | └ CLAUDE.md oribis-meta出力指示反映 | memory.md §9.7 | 実装済 | L1(ANIMA.md)+L2(l2.md)に指示追加済 (2026-05-05) |
| HIGH | G1-c | └ Level 1/2 trigger + scheduler配線 | memory.md §7.3 | 実装済 | 8a3c264 (2026-05-06) consolidation.rs+pipeline+scheduler+exit flush |
| MEDIUM | G1-d | └ telemetry（meta欠落率監視）+ テスト | memory.md §9.6 | 実装済 | 0096799 (2026-05-06) MetaStats+3状態パース+22テストPASS |
| HIGH | G1-e | └ L3 4チャネル検索 + ContextMode（context.rs 改修） | memory.md §8 / prompt-layers.md §4 | 実装済 | ContextMode(StatefulSession/StatelessRequest) + SQLite L3 retrieval。2026-06-22: Core/Recall/Refresh分割、StatelessRequest履歴6件化、入力連動`[思い出した会話]`追加 |
| HIGH | G1-f | └ 忘却曲線 + recency decay | memory.md §4.3/§8.2 | 実装済 | compute_current_strength + on_memory_recalled + recall reinforcement。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-EL | └ 軽量エンティティリンク | memory.md §8.6 | 実装済 | entity_link.rs + pipeline/consolidation接続。codex-adviser PASS (2026-05-07) |
| HIGH | G1-g | └ Level 2 consolidation | memory.md §7.2 | 実装済 | LLM-based companion + rule-based worker_ops。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-h | └ relationship_model L3注入 | memory.md §6.2-§6.4 | 実装済 | RM→ProfileItem変換+統合ランキング+即時Boundary/Correction。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-SM | └ self_model | memory.md §6.5 | 実装済 | b9aaf6d (2026-05-07) evidence蓄積+L3注入+L1 decay/promotion。codex-adviser PASS |
| HIGH | G1-i | └ A-MEM 軽量記憶進化 | memory.md §7.1 | 実装済 | L1でstrengthen/supersede/promote/no-op。codex-adviser PASS (2026-05-07) |
| HIGH | G1-j | └ Operational Memory | memory.md §11 | 実装済 | worker_patterns L1/L2。codex-adviser PASS (2026-05-07) |
| HIGH | G1-k | └ ハイブリッドベクトル検索 | memory.md §10.3 | 実装済 | 423a668。fastembed e5-small 384d + cosine + Phase3ランキング。2026-06-22: messages_fts + messages_ngram の会話検索補助Recallを追加 |
| MEDIUM | G3 | AnimaMode UI↔backend統一 | anima.md §6 | 実装済 | cb9db93 (2026-05-07) フロント off/cache/hybrid/ai → Rust Cache/Ai/Hybrid。codex-reviewer 3回PASS |
| HIGH | G9 | MCP Server（外部Worker/Client接続基盤） | mcp-server.md v3.1 | 一部実装済 | Phase 1-9完了（3c6e86b）。111テストPASS。Phase 10（GUI統合）一部実装（P1 write_event+events/feed） |
| HIGH | WR-P1 | web-remote P1（axum HTTP+WS / api-client.ts / Bearer認証）| spec/ui/web-remote.md | 実装済 | sysdev-1/web-remote-p1。smoke 5/5 PASS / cargo test 1016 PASS（2026-05-13） |
| HIGH | WR-P2 | web-remote P2（WS双方向 / Android CSS / クレート分離）| spec/ui/web-remote.md | 実装済 | sysdev-1/web-remote-p2。cargo test 1022 PASS / pnpm 360 PASS（2026-05-14） |
| MEDIUM | WR-P3 | web-remote P3（HTTPS/WS ストリーミング / PTY / PWA）| spec/ui/web-remote.md | 未着手 | Producer指示待ち |
| HIGH | ORCH-P1 | オーケストレーター P1 | anima-orchestrator-architecture.md | 実装済 | 9タスク完了。types.ts/Rust基盤/narration/MCP統合/Tauriコマンド/フロントエンド5コンポ/App.tsx統合/テスト/Onboarding |
| HIGH | ORCH-P2 | オーケストレーター P2 | anima-orchestrator-architecture.md | 実装済 | 12タスク完了+追加実装。CRUD API/PipelineView+DepartmentLane/OrchestratorEditor 5タブ/PromptsTabセキュリティ/Delete&Rename制御 + DrawerAnima内部タブ(Status/Prompt/Memory/Console/Settings) + Deep Reasoning delegation。vitest 568/cargo test 1036 PASS（2026-05-12） |
| HIGH | ORCH-P3 | オーケストレーター P3 | anima-orchestrator-architecture.md | 実装済 | P3-A: scheduler engine / P3-B: DELEGATE_TO自動ルーティング。commits 6254a02, f7ab1a7（2026-05-12） |
| HIGH | ACT-P2 | Action Platform / Internal Worker read-only closed loop + write diff proposal preview | anima-orchestrator-architecture.md / anima-ui.md | 一部実装済 | Phase 0-4 P2完了。Command Palette/JS-TS Console/Permission-Secrets土台/Internal Worker JSONL Store/API/read-only runtime/Anima dispatch proposal/approval UI/Job detail/Event/Artifact/Anima explanation、policy/audit boundary、approval decision JSONL永続化/idempotency/expiry/deny終端化、write plan Store/API、write diff proposal生成API、実WritePlan preview UI、approval hash binding。write適用/shell/MCP-writeは未実装。commit 9a91b55（2026-06-16） |
| HIGH | ORW-P0 | OribisWorker Core Protocol v0 | oribis-worker-core-protocol.md | 一部実装済 | Codex CLI非依存。Worker Core/Protocol/Runtime/Permission/Artifactを正本化。Discord/Virtual Terminal/CLI/3D UIはAdapter。TS v0型/Action schema/状態遷移/Permission Matrix/EventLog/Artifact/Dialogue/Store/Runtime Adapter interface/Orchestrator/CoreSession/Debug Console smoke実装。CapabilityはAction.typeからCore内部導出。scope検証付き `file.read` / `git.diff` / `file.patch` proposal / allowlist `test.run` / `plugin.invoke` 診断Adapterを追加。Debug Console結果をVirtual Terminalへ同期。ロード済みPluginのAI toolはHostAPI Bridge経由で呼び出し可能。CodexAdviserレビュー済み（2026-06-24）。P0実用API名追加済み。P1 Capability Registry / Secret Redaction / Event・Artifact contract / Permission Manifest / Audit Trail / timeout/cancel/retry/partialOutputRef / repo-relative workspace path境界 / Rust側Windows drive・URL-like path拒否 / Deterministic Patch Apply再検証済み。P2 context再構築・圧縮Core API、OribisHome `worker-core/session.json` 保存/読込、default session復元導線、Continuation Plan、状態変更後best-effort自動保存、起動時自動load/resume、Context Snapshot event/Virtual Terminal同期、Discord Adapter純粋境界、Discord Outbox EventLog queue/ack追加済み。P2残なし。実用閉路側の `summarizeCurrentWork` / `runRepoTaskFlow`、Worker Core Workbench UI、Autonomy Plan、Virtual Terminal Adapter v0まで接続済み。外部Discord実送信はtoken/権限管理が必要なため未接続 |
| LOW | G8 | AI応答の軽重モード（一言/詳細 切替） | anima.md | 未着手 | 現状はモデル選択で軽量化のみ。応答自体の簡潔さ制御なし。Producer判断で優先度変更 |

| MEDIUM | — | motion-anim-assign ランタイムマウント | motion-anim-assign.md | 不要 | Animation Editorプラグインで実現済・revert 2b727d4 |

### GTM戦略 — Kawaii-Agent 後出し勝利計画（2026-06-14 新規）

> 詳細: `oribis/docs/gtm/kawaii-agent-counterstrategy.md`
> ポジショニング: 「可愛いのに、ちゃんと仕事する。」— Creator/Developer向け常駐AI相棒

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| HIGH | GTM-P0-1 | 看板キャラ発注・納品 | gtm/kawaii-agent-counterstrategy.md | 未着手 | Producer判断必須（外部イラストレーター or VRoid改修）。一目惚れされる設計が前提 |
| HIGH | GTM-P0-2 | BOOTH商品ページ刷新 | gtm/kawaii-agent-counterstrategy.md | 未着手 | 体験訴求順「可愛い→常駐→覚える→見守る→仕事する→報告」に再設計。スクショ・文言ともに |
| HIGH | GTM-P0-3 | ダウンロードリンク開通 | gtm/kawaii-agent-counterstrategy.md | 未着手 | GitHub Releases自動デプロイ整備。「Coming soon」を「Download」に変更 |
| HIGH | GTM-P0-4 | 初回起動体験の完成 | gtm/kawaii-agent-counterstrategy.md | 未着手 | Onboarding完了→キャラが出迎えるまで一気通貫で体験できる状態に |
| MEDIUM | GTM-P0-5 | Onboarding文言の体験化 | gtm/kawaii-agent-counterstrategy.md | 未着手 | 「APIキーを入力してください」→「一緒に設定しよう」等の体験的な言葉に変更 |
| MEDIUM | GTM-P0-6 | README.ja.md 体験中心に書き直し | gtm/kawaii-agent-counterstrategy.md | 未着手 | 技術スペック比較先行 → 「どんな体験か」先行に変更 |
| MEDIUM | GTM-P1-1 | 記憶の可視化強化 | gtm/kawaii-agent-counterstrategy.md | 未着手 | 「〇〇が得意なんだね」「昨日の続きやる？」等の気づきUIカードを表示 |
| MEDIUM | GTM-P1-2 | 今日のレポートUI | gtm/kawaii-agent-counterstrategy.md | 未着手 | 作業終了時「今日は〇〇できたね、お疲れ様」の自動サマリー生成 |
| MEDIUM | GTM-P1-3 | 常駐通知強化 | gtm/kawaii-agent-counterstrategy.md | 未着手 | タスクバー常駐 + 通知バブル（「タスク完了したよ」） |
| LOW | GTM-P2-1 | Multi-Worker可視化UI | gtm/kawaii-agent-counterstrategy.md | 未着手 | 複数Workerが並列実行する様子をアニメーションで可視化（デモ映え） |
| LOW | GTM-P2-2 | Discord連携デモ動画 | gtm/kawaii-agent-counterstrategy.md | 未着手 | 「自動Discord報告」のシーンを動画化してBOOTH掲載 |
| LOW | GTM-P2-3 | Scheduler GUI簡易化 | gtm/kawaii-agent-counterstrategy.md | 未着手 | 「毎朝9時に予定を教えてくれる」をGUIで簡単設定できるように |

**Producer確認待ち（これが決まれば実装に落とせる）:**
1. 看板キャラ: 外部発注か / 既存VRoid改修か
2. リリース: 0.1.0 を公開版にするか / バージョン番号
3. BOOTH価格モデル: 無料＋有料版の構成 / 単品 / サブスク

### バグ修正・技術的負債

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| HIGH | TASK-G | 音声入力 Codex R3 指摘対応 | voice-input.md | 一時停止中 | HIGH×2, MEDIUM×3, LOW×1 |
| MEDIUM | — | ARP→VRM FBXアニメーションリターゲット | issues/fbx/ | 実施中 | 腕完了、脊椎動作中、Producer作業中 |
| MEDIUM | TASK-K | 入力欄に謎テキスト挿入バグ | — | 調査中 | 再現手順の特定待ち |
| LOW | TASK-B | useVoiceInput/useTTS テストTSエラー | voice-input.md | 要確認 | エラー未検出・タスク自体が古い可能性 |
| LOW | TASK-C | PoseDebugUI.tsx リファクタ検討 | — | 要確認 | App.tsxでimport使用中・削除不可 |
| LOW | TASK-E | VrmViewer expression detection 堅牢化 | vrm.md | 未着手 | |
| LOW | TASK-F | カメラ spherical↔OrbitControls 同期 | — | 未着手 | |
| LOW | TASK-J | 左ドロワー push レイアウト | — | 休止中 | R3F ResizeObserver問題 |
| HIGH | — | Force-close後チャット入力スタック | lib.rs, App.tsx | 修正済 | bbd0ec2。session IDクリア+orphan検知+state reset |
| MEDIUM | — | L1/L2プロンプトパス不一致 | context.rs, lib.rs | 修正済 | 786fd8b。_common→orchestrator統一 |
| HIGH | — | AIバックエンド配線未接続 | pipeline.md | 修正済 | f942c61。`anthropic`/`openai_compat` がClaude CLIへフォールスルーする問題を修正。provider_wiring_smoke PASS、cargo test --lib 1433 PASS、npm test 796 PASS |

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
| G1-a | SQLite記憶基盤 + oribis-meta���ーサー + migration（memory_db.rs, events.rs, parser.rs, pipeline.rs） | 2026-05-05 |
| G5 | compute_sub_context スマートキャッシュ選択（cache.rs + pipeline接続） | 2026-05-05 |
| G0 | CLI adapter 実装（cli_adapters.rs） | 2026-05 |
| G7 | Tauri コマンド公開（anima_chat/anima_state + useAnima接続） | 2026-05 |
| G6 | イベントカウンタ トリガー接続（pipeline increment + context注入） | 2026-05 |
| G2 | ThrottleConfig toml ロード | 2026-05 |
| G4 | Anima pipeline memory_saves 処理 | 2026-05 |
| TASK-H | 会話ログ保存 + タスクペンディング | a67e021〜c8412c5 |
| G1-e | L3 4ch検索 + ContextMode（retrieval/context/pipeline/lib） | 2026-05-07 |
| G1-f | 忘却曲線 + recency decay（compute_current_strength + on_memory_recalled） | 2026-05-07 |
| G1-EL | 軽量エンティティリンク（entity_link.rs + pipeline/consolidation接続） | 2026-05-07 |
| G1-g | Level 2 consolidation（LLM companion + rule-based worker_ops） | 2026-05-07 |
| G1-h | relationship_model L3注入 + 即時Boundary/Correction更新 | 2026-05-07 |
| G1-SM | self_model — AI自己理解 (evidence蓄積+L3 Ch4注入+L1 decay/promotion) | 2026-05-07 |
| G1-i | A-MEM 軽量記憶進化（L1: strengthen/supersede/promote/no-op） | 2026-05-07 |
| G1-j | Operational Memory（worker_patterns L1/L2） | 2026-05-07 |
| G1-k | ハイブリッドベクトル検索（fastembed e5-small + cosine + Phase 3ランキング）423a668 | 2026-05-07 |
| G9 | MCP Server Phase 1-9（Broker+Tools+Resources+Auth+Audit+StateMachine。111テストPASS） | 2026-05-07 |
| G3 | AnimaMode UI↔backend統一（FromStr impl + Tauriコマンド anima_mode配線 + UIトグル3段切替） | 2026-05-07 |
| — | L1/L2プロンプトパス統一（_common→orchestrator + oribis_prompts_dir + テストbase_dir対応）786fd8b | 2026-05-07 |
| — | Force-close後チャット入力スタック修正（session IDクリア + orphan検知 + state reset）bbd0ec2 | 2026-05-07 |
| — | コンテキストテストhome fallback修正（setup_prompts_dir追加）11cf7dc | 2026-05-07 |
| — | GUIテスト全項目PASS（AnimaMode, Prompt編集, Memory E2E, ベクトル検索）393テスト+スクショ確認 | 2026-05-07 |
| ORCH-P1 | オーケストレーターP1 Epic全9タスク完了（types/Rust基盤/narration/MCP統合/Tauri cmd/フロントエンド/App.tsx統合/テスト/Onboarding） | 2026-05-08 |
| ORCH-P2 | オーケストレーターP2 Epic全12タスク完了（CRUD API/PipelineView/DepartmentLane/OrchestratorEditor 5タブ/PromptsTabセキュリティ/Delete&Rename制御。vitest 563/cargo test 955 PASS） | 2026-05-11 |
| ORCH-P2追加 | DrawerAnima内部タブ実装（Status/Prompt/Memory/Console/Settings）+ CSSテーマ対応 + Deep Reasoning delegation + GeneralTab統合。vitest 568/cargo test 1036 PASS（commits c7f224e〜0432867） | 2026-05-12 |
| ORCH-P3 | P3-A scheduler engine + P3-B DELEGATE_TO自動ルーティング（6254a02, f7ab1a7） | 2026-05-12 |
| — | セキュリティ修正: assetProtocol scope/Plugin icon XSS/filepath traversal（071e92b） | 2026-05-12 |
| — | 起動時Anima自動接続: プロジェクト選択後1.2秒で時刻別挨拶自動送信（b6f7e5a） | 2026-05-12 |
| — | open_cli_terminal WSL修正: powershell.exeフルパスフォールバック追加（b87f53d） | 2026-05-12 |
| G9-P10 | MCP Phase 10 GUI統合: Worker token injection + GUI token UI + revoke_by_prefix（ff8efea）| 2026-05-12 |
| WR-P1 | web-remote P1: axum HTTP+WSサーバー / api-client.ts / Bearer認証 / SPA fallback / smoke 5/5 PASS（sysdev-1/web-remote-p1） | 2026-05-13 |
| WR-P2 | web-remote P2: WS双方向dispatch / AndroidタッチCSS / Cargoワークスペース / pnpmワークスペース / Tailscaleガイド（sysdev-1/web-remote-p2, ab5ab99） | 2026-05-14 |
| E2E-FW | シナリオ駆動型E2Eテストフレームワーク（engine 22ファイル + scenarios 6 JSON + bone regression） | 2026-05-08 |
| COM-P0-2 | 配布物クリーン環境テストCI: release.yml artifact validation + smoke-install.yml（Windows MSI/Linux DEB/AppImage）| 2026-05-27 |
| COM-P1-1 | VOICEVOXクレジット表示: About画面にVOICEVOX利用表記+ライセンスリンク追加 | 2026-05-27 |
| COM-P1-2 | コスト警告Settings UI: 閾値カスタマイズUI実装 | 2026-05-27 |
| COM-P1-3 | 自動アップデート軽量版: GitHub Releases API起動時チェック+toast通知（update_check.rs） | 2026-05-27 |
| COM-P1-4 | エラーメッセージi18n: OribisError Serialize→i18nキー化（error.io/internal/network/command/database） | 2026-05-27 |
| COM-P1-5 | ネットワークエラーUX: useNetworkStatus hook + ErrorRetryBanner + invokeWithTimeout | 2026-05-27 |
| chat-mode T1 | App System v2 実行経路確立: usePluginSystem互換/PluginSandbox統合/App.tsxレンダリング/HostAPI堅牢化/テスト792PASS | 2026-05-29 |
| chat-mode T2 | UIRenderer チャット用コンポーネント追加: scrollable-list/message/markdown-text + autoScrollBottom + 7テスト追加/テスト799PASS | 2026-05-29 |
| chat-mode T3 | ai.sendToAnima/sendToDepartment 実動経路確立: Promise/timeout/PTY収集/ai:response単一登録/テスト805PASS | 2026-05-29 |
| chat-mode T4 | チャットモードプラグイン骨格+Animaチャット画面: Enter送信安定化/data-testid対応/TTS表示改善/テスト807PASS | 2026-05-29 |
| chat-mode FIX | builtin plugin discovery fix: plugin_v2_scan結果にBUILTINマニフェストをマージ、enable/disableをローカルstate+storageで永続化 | 2026-05-29 |
| TTS-ONB-T1 | TTS Engine Onboarding Task 1: 型定義・レジストリ・永続化・DTO/Command・Preset拡張。Rust 1508 PASS（新規15テスト含む） | 2026-05-29 |
| TTS-ONB-T5 | TTS Engine Onboarding Task 5: E2E統合テスト `tests/tts_engine_integration.rs`。mock DL→install→health→fetch WAV→amplitude フルフロー。Rust 1441 PASS + 統合1 PASS | 2026-05-29 |
| TTS-CLI | Piper fetch_tts_wav_for_preset CLI実装: model_path追加・GitHub実URL・tar.gz symlink許可・リアルE2Eテスト(26MB DL+WAV合成)。Rust 91 PASS | 2026-05-30 |
| TTS-Sherpa | Sherpa ONNX + RHVoice CLI合成実装: sherpa-onnx-offline-tts / rhvoice-test 自動検出。レジストリに実URL+SHA256。Rust 91 PASS | 2026-05-30 |
| オンボードUI修正 | デフォルトホームフォルダ/レイアウト/モデル表示/完了フロー/チャットモード/タイトルバー/オーケストレータ統合 | 2026-05-31 |
| TTS-ONB-UI | TTSエンジン選択をオンボードStep 2に追加: list_tts_engines+install+localStorage+ProjectMeta保存 | 2026-05-31 |
| TTS-VOICEVOX-FFI | VOICEVOX Core 0.16.4 カスタムFFI実装: voicevox-dyn廃止→libloading+新C API。n0.vvm+9スタイル。/tmp/test_japanese.wav生成 | 2026-06-01 |
| TTS-KOKORO | KokoroTTS 自前実装: kokoro-en廃止→ort直接利用。ONNXモデル310MB+音声ファイル。/tmp/test_english.wav生成 | 2026-06-01 |
| CI-Windows | WindowsビルドCI修正: tsc type checkスキップ(`pnpm vite build`)、未使用import削除 | 2026-05-30 |
| launcher | エージェントランチャー `default-agent`: 部門起動のデフォルトAIエージェント切替（claude/codex/opencode/openclaw + モデル指定） | 2026-05-30 |
| AI-BACKEND-WIRING | Anima AIバックエンド配線: provider_config.json→ResolvedModelConfig→BackendProviderAdapter→Anthropic/OpenAI互換HTTP provider接続。Anthropic 100-delta SSEデッドロック回帰テスト追加。cargo test --lib 1433 PASS / npm test 796 PASS | 2026-06-14 |

---

## spec レジストリ

### spec/core/ — コアシステム

| spec | 概要 | ステータス |
|------|------|-----------|
| overview.md | 概要・設計原則・フェーズ計画 | 設計確定 |
| pipeline.md | 統一応答パイプライン + CLI Adapter + HTTP provider配線 | 実装済 |
| anima.md | Anima + AnimaMode + throttle + キャッシュ | 一部実装済 |
| anima-plan.md | 開発計画（GAP管理） | — |
| anima-state.md | AnimaState一覧・カテゴリ | 実装済 |
| anima-orchestrator-architecture.md | オーケストレーター + Worker PTY + Internal Worker read-only closed loop + write diff proposal preview | 一部実装済（P1/P2/P3 + Action Platform Phase 0-4 P2完了、write適用/shell/MCP-write未実装） |
| test-infrastructure.md | Unit/Vitest/WDIO/Rust テスト基盤 | 実装済 |
| affinity.md | 好感度システム | 実装済 |
| memory.md | 4レイヤー記憶 + 自己進化 + entity linking + self_model | 実装済（Phase 1-3完了、v3.5） |
| event-counter.md | イベントカウンタ | 実装済 |
| session-data.md | 統合履歴 + タスク管理 | 実装済 |
| data-storage.md | データストレージ（db.rs） | 実装済 |
| markers.md | マーカー方式統一仕様 | 実装済 |
| prompt-layers.md | プロンプト三層構造（L1/L2/L3） | 実装済（v1.4: L1/L2正規パス統一） |
| expression-system.md | 表情反映システム | 実装済 |
| cache-generation-prompts.md | キャッシュ生成プロンプト集 | 設計確定 |
| mcp-server.md | MCP Server（外部Worker/Client接続） | 実装済（Phase 1-10完了） |
| architecture-diagrams.md | アーキテクチャ図集 | — |
| test-requirements.md | テスト要件 | — |
| embedded-tts.md | 組み込みTTSエンジン（VOICEVOX Core + Kokoro） | 実装済 |
| scene-runtime-foundation.md | AI-native SceneRuntime基盤（Rust正本 / Command / Event / Snapshot / Systems / Babylon projection） | 設計確定 |
| oribis-worker-core-protocol.md | Codex非依存OribisWorker Core/Protocol/Runtime/Permission/Artifact設計 | 一部実装済（TS v0型/Action schema/状態遷移/Permission Matrix/EventLog/Artifact/Dialogue/Store/Runtime Adapter interface/Orchestrator/CoreSession/Debug Console/Virtual Terminal/plugin.invoke smoke） |

### spec/ui/ — UI・フロントエンド機能

| spec | 概要 | ステータス |
|------|------|-----------|
| vrm.md | VRMアバター表示 | 実装済 |
| mmd-model.md | MMDモデル対応 | 実装済 |
| avatar-animation.md | 表情拡張/FBXリターゲット/morphMap | 一部実装済 |
| motion-anim-assign.md | モーション状態別アニメ割り当てUI | 一部実装済 |
| babylon-vrma-retarget.md | Babylon VRMA比較QA / FBXリターゲット移行 | 実装中（Mixamo FBX Babylon側9ファイルbody/close-up QA証跡、generated VRMA 9本取り込みまで反映） |
| anima-ui.md | Anima統合UI（parser/adapter/cache/dispatch approval UI等） | 一部実装済（Anima dispatch approval UI完了、後続orchestration UI未実装） |
| dual-session.md | デュアルセッション（Theater Mode） | 実装済 |
| cli-status-pane.md | CLIステータスペイン | 実装済 |
| output-viewer.md | 出力ビューア | 未着手 |
| scene-plugin.md | シーンプラグイン | 実装済 |
| plugin-api.md | プラグインAPI（v1廃止） | 廃止 |
| app-system-v2.md | App System v2（iframe sandbox + Host API + 宣言的UI） | 一部実装済 |
| theme-system.md | テーマシステム | 実装済 |
| voice-input.md | 音声入力（push-to-talk） | 実装済 |
| web-remote.md | Webリモート（axum + browser UI） | 実装済（P1/P2完了、P3未着手） |
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
