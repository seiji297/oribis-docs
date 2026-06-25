# Scene Mode Split 計画

作成日: 2026-06-25

## 結論

推奨は、SceneRuntime正本を共通に保ち、SceneごとにRenderer Adapterを動的ロードする方式。

- ステージ: 軽量・静的キャラクター・three.js系 renderer
- スタジオ: 動的キャラクター・Babylon.js renderer
- ワールド: 将来の広域・自由世界向けscene kindとして予約

SceneRuntime / Command / Entity / Component / Audit は分けない。分けるのは projection と runtime system。

## 目的

初回リリースの負荷と実装リスクを下げる。

現状のスタジオは、NavMesh、Recast Crowd、Havok physics、Babylon projection、動的移動、3D terminalなどを含むため重い。将来性はあるが、初回リリースの標準シーンとしては風呂敷が広い。

初回リリースではステージを標準にし、常駐キャラクターは動かさず、必要な家具だけを状況に応じてインスタンス生成する。

## 名称

推奨:

- UI表示名: `ステージ` / `スタジオ` / `ワールド`
- 内部ID: `stage` / `studio` / `world`

理由:

- UI表示はProducerの呼び方に合わせる。
- 内部IDは短く `stage` / `studio` / `world` にする。
- `world` は今すぐ実装対象にせず、将来の広域・自由世界向け予約語として先に確保する。

## ステージ

内部ID: `stage`

### 仕様

- キャラクターは移動しない。
- AnimaとWorkerは常に存在する。
- 床は丸い円形ポリゴンのみ。
- 常設家具は置かない。
- 作業、就寝、休憩などの状態に応じて家具を一時生成する。
- 例:
  - 作業開始: デスクと椅子を生成。
  - 作業中: Anima/Workerが机に向かっているように見せる。
  - 作業終了: デスクと椅子を消す。
  - 就寝: ベッドを生成。
  - 起床: ベッドを消す。
- 物理演算、NavMesh、Crowd回避は初期状態では使わない。
- 軽量環境で動くことを優先する。

### Renderer

- three.jsを使う。
- ただしアプリ起動時に静的importしない。
- ステージを選択した時だけ `import()` でロードする。
- スタジオ選択時は、標準ではthree.js chunkをロードしない。
- `three` 本体だけでなく、`@pixiv/three-vrm` / `three-stdlib` / loader類もsceneKind/状況に応じてロードする。

### SceneRuntimeとの関係

ステージでもSceneRuntimeは使う。

- `anima_presence`
- `worker_presence`
- 一時家具Entity
- `surface` / `text` / `lifetime` / `metadata`
- 状況を表す lightweight component

ただし、ステージでは以下を原則使わない。

- `navigation`
- `movement`
- `path`
- `physics`
- `characterControl` のlocomotion系

必要なら `poseIntent` / `activityIntent` のような軽量componentへ寄せる。

## スタジオ

内部ID: `studio`

### 仕様

- 今作っている動的シーン。
- キャラクターはSceneRuntime Entityとして存在し、移動できる。
- Babylon.js projectionを使う。
- Recast NavMesh / Crowd / Havok physics を使える。
- Anima/Workerは `navigation` / `movement` / `path` / `characterControl` componentで制御する。
- 3D terminal、Scene Builder、Scene Editor、動的家具配置はSceneRuntime projectionとして扱う。

### Renderer

- Babylon.jsを使う。
- スタジオを選択した時だけ `import()` でロードする。
- ステージ選択時は、標準ではBabylon/Havok/Recast chunkをロードしない。

## ワールド

内部ID: `world`

### 仕様

- 将来の広い自由世界、探索、建築、複数キャラクター、長時間滞在向けscene kind。
- 初回実装では選択UIに出さない。
- Scene schema上の予約値として保持する。
- `studio` と混同しない。`studio` は現在の動的作業空間、`world` は将来の広域世界。

### Renderer

- 現時点では未実装。
- `world` sceneを読み込んだ場合は、未対応表示または `studio` 互換fallbackのどちらかを明示的に選ぶ。
- 暗黙に `studio` と同一扱いしない。

## 共通設計

### Scene kind

Scene metadataに `sceneKind` を追加する。

候補:

```json
{
  "sceneKind": "stage"
}
```

または:

```json
{
  "runtimeProfile": "lightweight_static"
}
```

推奨は `sceneKind`。

理由:

- ユーザーにもAIにも意味が明確。
- Rendererだけでなく、許可するcomponent/systemも切り替えられる。
- Scene保存/ロード/テンプレート化のキーになる。

schema:

```ts
type SceneKind = "stage" | "studio" | "world";
```

運用:

- 未指定の既存sceneは `studio` として扱う。
- 新規初期sceneは `stage` とする。
- `world` は予約値。初回リリースでは作成UIに出さない。
- unknown値は即クラッシュさせず、安全fallbackして警告Eventを記録する。
- SceneRuntime document export/importで `sceneKind` を保持する。
- 旧名が残った場合は、`static_stage` -> `stage`、`dynamic_world` -> `studio` に移行する。

### Renderer Adapter境界

App本体は直接three.js/Babylon.jsをimportしない。

```ts
type SceneRendererAdapter = {
  kind: "stage" | "studio" | "world";
  mount(container, snapshot, options): SceneRendererHandle;
  update(snapshot): void;
  resize(size): void;
  dispose(): void;
  getDiagnostics?(): SceneRendererDiagnostics;
};
```

実装候補:

- `src/scene-renderers/stage/loadStageRenderer.ts`
- `src/scene-renderers/studio/loadStudioRenderer.ts`
- `src/scene-renderers/world/loadWorldRenderer.ts`（将来予約）

ロード例:

```ts
async function loadSceneRenderer(sceneKind: SceneKind) {
  if (sceneKind === "stage") {
    return import("./scene-renderers/stage");
  }
  if (sceneKind === "studio") {
    return import("./scene-renderers/studio");
  }
  return import("./scene-renderers/world");
}
```

### 禁止事項

- App rootで `three` / `@babylonjs/*` を静的importしない。
- ステージでは標準でBabylon/Havok/Recastをロードしない。
- スタジオでは標準でthree.js互換レイヤーを常時ロードしない。
- Renderer固有objectをSceneRuntime正本にしない。
- RendererがTask/Action/家具Entityを直接生成しない。家具生成はSceneRuntime Command / Scene Router / Action側で行い、Rendererはsnapshotを投影するだけにする。
- Scene切替時にRAF、event listener、GPU resource、asset container、physics/nav runtime handleを残さない。

### 依存配置

- ステージ専用: `three`, `@pixiv/three-vrm`, `three-stdlib`, three系loader
- スタジオ専用: `@babylonjs/*`, `@babylonjs/havok`, `recast-detour`
- 共通: React UI、SceneRuntime client、Command/Scene Router、型定義

受入条件:

- root/static import禁止をテストまたはlint相当で検出する。
- Vite build outputでchunk分離を確認する。
- runtimeで読み込まれたscript URLを確認し、対象Scene以外のrenderer chunkがロードされていないことを確認する。

## 実装フェーズ

Producer指示により、実装はステージから着手する。

ただしApp rootからrendererを切り替える境界がないままthree.jsを戻すと、また常時ロード化する。したがって最小順は以下にする。

1. `sceneKind` schemaと初期値 `stage`
2. Renderer Adapter loaderの薄い境界
3. ステージrendererの最小実装
4. スタジオは既存Babylon viewerを壊さない形で後追い隔離

この順なら、ユーザーから見えるステージを先に作りつつ、three.js/Babylon.jsの常時混在を避けられる。

### 実装状況（2026-06-25）

- P1: `sceneKind` schemaをTS/Rust SceneRuntime document / Scene Authoring packageへ追加済み。`stage` / `studio` / `world` と旧名 `static_stage` / `dynamic_world` の正規化を実装。
- P2: `SceneViewer` 境界を追加し、`stage` は `StageSceneViewer`、`studio` は既存 `BabylonAvatarViewer` をdynamic importする形へ変更済み。`world` は予約placeholder。
- P3: `StageSceneViewer` を新規追加。three.jsをStage側だけでlazy loadし、円形床、静止Anima/Worker placeholder、SceneRuntime renderable Entityの最小投影を実装済み。
- P4: `scene.stage.activity.start` / `scene.stage.activity.end` をAnima Tool Catalog / CommandRegistry / App adapterへ追加済み。Stageの作業/休憩/睡眠用一時家具Entityをmetadata付きで生成し、該当temporary家具だけ削除できる。
- P5: 初期sceneKindは実アプリで `stage`、Vitest互換fallbackは `studio`。互換toggleから `stage` / `studio` を切替可能。Scene Editor / Scene Builderの詳細UIは後続。

検証:

- `rtk pnpm exec tsc -p tsconfig.lib.json --noEmit` PASS
- `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit` PASS
- `rtk pnpm exec vitest run src/command/CommandRegistry.test.ts src/command/animaPlanner.test.ts src/App.terminal.test.tsx src/components/SceneViewer.test.ts --testTimeout=30000 --reporter=verbose` 53 PASS
- `rtk cargo test --manifest-path src-tauri/Cargo.toml scene_authoring --lib` 10 PASS
- `rtk cargo test --manifest-path src-tauri/Cargo.toml scene_runtime --lib` 20 PASS
- `rtk pnpm exec vite build` PASS。`StageSceneViewer-*.js` と `BabylonAvatarViewer-*.js` の別chunk出力を確認。
- WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/stage-renderer.spec.ts --grep "T-W-STAGE"` 2 PASS
  - `T-W-STAGE-01`: Stage rendererの軽量renderer / Babylon初期非表示確認
  - `T-W-STAGE-02`: `scene.stage.activity.start/end` で作業机・椅子を生成し、終了後に消えることを確認
- WDIO `ORIBIS_SKIP_TEST_AUTH_CLEAN=1 rtk bash scripts/run-wdio-tests.sh --spec tests/babylon-renderer.spec.ts --grep "T-W-BAB-01"` 1 PASS

注意:

- WDIOを並列実行すると `tauri-driver` / app sessionが衝突するため直列で実行する。
- runner cleanupで既知の `ELIFECYCLE Command failed` 表示が出る場合があるが、上記直列実行はexit code 0かつspec PASS。
- P4のWDIO「家具生成後に机が出て終了後消える」は `T-W-STAGE-02` で確認済み。
- RuntimeでStage表示中にBabylon/Havok/Recast script URLが未ロードであることは `T-W-STAGE-01` のresource/script URL検査で確認済み。

### P0: 現状調査

- three.js関連削除済み箇所を確認。
- 旧 `AvatarViewer` / `VrmViewer` / `Three` plugin API の残骸を確認。
- App rootでBabylonを静的にimportしている箇所を確認。
- `BabylonAvatarViewer` がどのchunkへ入っているか確認。
- Scene保存形式にmetadataを追加できる場所を確認。

成果物:

- 依存ロード表
- 削除済みthree復活候補一覧
- App root静的import一覧

### P1: Scene kind schema

- SceneRuntime document / scene catalogに `sceneKind` を追加。
- 既存sceneは未指定なら `studio` 扱いにする。
- 初期リリース用sampleは `stage` とする。
- Scene Editor / Scene Builder / Scene loadでsceneKindを読めるようにする。
- unknown値はfallback + warning Eventで扱う。

テスト:

- SceneRuntime document import/export unit
- scene catalog unit

### P2: Renderer Adapter境界

- App rootはadapter loaderだけを見る。
- まずはステージrendererを差し込める薄い境界を作る。
- 現在のBabylon viewerは壊さず、`studio` adapterへ後追いで隔離する。
- スタジオ importでBabylonをロードする形へ寄せる。
- ステージの時にBabylon chunkがロードされないことを確認する。
- App rootからBabylon静的importを段階的に除去する。

テスト:

- unit: `sceneKind=studio` でBabylon loaderが選ばれる。
- unit: `sceneKind=stage` でBabylon loaderが呼ばれない。
- WDIO: stageで最小表示が通る。
- WDIO: studioで既存Babylon smokeが通る。
- build: 最終的にスタジオchunkにBabylon/Havok/Recastがまとまり、root chunkに混ざっていない。
- runtime: stage表示中にBabylon/Havok/Recast script URLがロードされない。

### P3: three.js軽量Renderer復活

- three.jsはステージadapter内だけで復活する。
- 旧Three AvatarViewerをそのまま戻さない。
- 必要最小限:
  - canvas
  - 円形床
  - Anima/Worker VRM表示
  - 一時家具Entity投影
  - pose/activity表示
- physics/nav/IK/editorは入れない。
- VRM表示が初回リリースで重い場合は、低負荷avatar placeholderへ一時切替できる判断点を置く。

テスト:

- unit: stage adapter lazy import
- WDIO: staticで丸床、Anima、Workerが表示される。
- chunk検証: staticでBabylon/Havok/Recastがロードされない

### P4: 一時家具インスタンス

- ステージ向けの `activity furniture instance` 導線を追加。
- 作業開始/終了で家具を生成/削除。
- lifetime componentまたはactivity owner metadataで管理。

例:

```json
{
  "metadata": {
    "temporaryFor": "work",
    "owner": "anima",
    "sceneKind": "stage"
  }
}
```

テスト:

- unit: 作業開始Actionでdesk/chair生成
- unit: 作業終了Actionで該当temporary家具だけ削除
- WDIO: 作業Actionで机が出て、終了後消える

### P5: UI/設定

- 初回起動デフォルトはステージ。
- DebugまたはSettingsでスタジオを選択可能にする。
- Scene EditorにはsceneKindを表示する。
- Scene Builderは作成先sceneKindを選べるようにする。

テスト:

- onboarding後の初期sceneKindが `stage`
- Settingsで `studio` へ切替可能
- 切替時に不要rendererがdisposeされる

進捗:

- 2026-06-25: Settings > General に `シーンモード` selectorを追加し、`stage` / `studio` の選択を `oribis_scene_kind` / `oribis_avatar_render_engine` へ保存する導線を追加。
- 2026-06-25: `T-W-STAGE-03` でSettings導線が表示され、Stage状態のままStudio/BabylonをロードしないことをWDIOで確認。

## 受け入れ条件

### ステージ

- 初回リリースの標準Sceneとして起動する。
- キャラクターは移動しない。
- 丸い床のみ表示。
- Anima/Workerは常駐。
- 作業時だけデスク/椅子等を一時生成し、完了後に消える。
- three.jsはステージ選択時だけロードされる。
- Babylon/Havok/Recastはステージではロードされない。

### スタジオ

- 既存のBabylon動的シーンが壊れない。
- Anima/WorkerのNavMesh/Crowd移動が維持される。
- Babylon/Havok/Recastはスタジオ選択時だけロードされる。
- three.js/three-vrm/three-stdlibはスタジオではロードされない。

## リスク

### リスク1: ステージ/スタジオで機能分岐が増えすぎる

対策:

- 正本はSceneRuntimeに一本化。
- 差分はRenderer AdapterとSystem capabilityを境界にして切り替える。
- App全体に `if sceneKind` を散らさない。

### リスク2: three.js復活でバンドルが再び重くなる

対策:

- 静的import禁止。
- adapter単位でdynamic import。
- build artifactとruntime loaded script URLでchunk分離を確認。

### リスク3: 旧Three実装を戻して負債が復活する

対策:

- 旧 `AvatarViewer` / `VrmViewer` をそのまま復活しない。
- 新規 `ステージSceneRenderer` として最小再実装。
- ステージ要件に不要なbone/physics/debug機能は入れない。

### リスク4: スタジオの既存テストが壊れる

対策:

- P2で既存Babylon adapterを包むだけにする。
- `T-W-BAB-SB-01` / `T-W-BAB-WORKER-01` を維持。
- スタジオを明示選択して既存WDIOを走らせる。

## 推奨実装順

1. 現状調査
2. `sceneKind` schema追加
3. Renderer Adapter interface追加
4. ステージScene rendererを新規追加
5. ステージ初期scene作成
6. Babylon viewerをstudio adapterへ隔離
7. 一時家具Action追加
8. WDIOでステージ/スタジオ両方確認

## 今回まだ実装しないこと

- ステージでのNavMesh。
- ステージでの物理演算。
- ステージでの自由移動。
- ステージでの本格Animation Creator統合。
- スタジオの機能削除。
- 旧Three実装の丸ごと復元。

## 判断メモ

ステージは「低負荷で商品として成立させるための標準表示」。

スタジオは「将来の3D世界・AIキャラクター・動的ゲームエンジン方向の実験/拡張表示」。

この2つを同じ土俵で競わせない。初回リリースはステージで安定させ、スタジオは拡張機能として育てる。
