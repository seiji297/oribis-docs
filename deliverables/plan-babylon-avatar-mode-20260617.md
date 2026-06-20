# Babylon Avatar Migration 計画

最終更新: 2026-06-17

## 1. 結論

既存Three.js表示は残し、Babylon.jsを別レンダリングモードとして追加する。

最終目標は、Anima/Virtual Studio/Virtual Worldの3D基盤をBabylon.jsへ完全移行できる状態にすること。
ただし、既存Three.jsは移行完了まで比較・退避用として残す。

## 2. 方針

- 既存 `AvatarViewer` は維持する。
- 新規 `BabylonAvatarViewer` を追加する。
- App側で `three` / `babylon` を切り替える。
- `BabylonAvatarViewer` は既存 `AvatarViewerProps` と互換のpropsを受ける。
- 初回はVRM完全対応ではなく、Babylon engine / scene / camera / light / fallback mesh / model URL状態表示を実装する。

## 3. 移行で確認すること

- Babylon CanvasをOribisの3D表示領域へ安全にマウントできるか。
- Three.js表示と切り替えても既存UIが壊れないか。
- 既存camera paramsをBabylon cameraへ概算変換できるか。
- VRM/GLB/FBX等の実ロードを後段で入れるための接続点を作れるか。
- 既存Three.js資産を残したままBabylon検証を進められるか。
- VRM表情、morph、lip sync、animation、material appearance、background、camera操作を同等化できるか。

## 4. 初回でやらないこと

- VRM表情、モーフ、MToon、springBoneの完全移植。
- 既存Three.js `AvatarViewer` の削除。
- React Three Fiberの撤去。
- Babylon physics本実装。
- Babylon VRM loaderの採用確定。

## 5. 実装対象

### P-BAB-1: Viewer skeleton

- `@babylonjs/core`
- `BabylonAvatarViewer.tsx`
- `BabylonAvatarViewer.test.tsx`

実装:

- `vrmUrl/fileExists/cameraParams/bgCutout/bgImageUrl` を受ける。
- `fileExists=false` なら既存同様 fallback。
- `canvas` を生成し、Babylon `Engine` / `Scene` / `ArcRotateCamera` / `HemisphericLight` / fallback meshを作る。
- `vrmUrl` は初回ではロードせず、URL受け取り状態を表示する。
- `BabylonAvatarViewerProps` は既存 `AvatarViewerProps` と互換にし、未対応propsは明示的にno-op扱いにする。
- `.vrm-canvas-container canvas` のDOM形状を維持し、既存E2Eセレクタを壊さない。

### P-BAB-2: App toggle

- Appの3D表示領域に `Three / Babylon` 切替を追加。
- 初期値はThree。
- Babylon選択時のみ `BabylonAvatarViewer` を描画。

### P-BAB-3: テスト

- `BabylonAvatarViewer` がfallbackを出す。
- `fileExists=true` でcanvasを出す。
- `vrmUrl` を受け取る。
- Appの初期表示はThree。
- 切替後にBabylon表示へ変わる。

### P-BAB-4: GLB/VRM load path

- これは初回実装には含めない。
- 初回Viewer skeletonが安定した後に実施する。
- Babylon `SceneLoader` でGLBを読み込む。
- この段階で `@babylonjs/loaders` を追加し、`@babylonjs/loaders/glTF` を用途限定importする。
- VRMは `babylon-vrm-loader` 採用可否を別検証する。
- load失敗時はfallback meshを残す。

### P-BAB-5: Avatar機能同等化

- camera params同期。
- background/cutout。
- material appearanceの最小対応。
- expression/morph mapping。
- lip sync。
- animation state。
- lookAt。

### P-BAB-6: default切替

- Babylon側が既存Three表示と同等になったらデフォルトをBabylonにする。
- Three.jsは少なくとも1リリースは比較用に残す。
- その後、削除判断を行う。

## 6. codex-review観点

- Babylon追加で既存Three表示が壊れていないか。
- 依存追加が過剰でないか。
- Babylonモードが実ロード未対応であることをUI上明示しているか。
- VRM完全対応しているように誤認させないか。
- 既存テストが落ちていないか。

## 8.1 CodexReview反映

反映内容:

- 初回はGLB/VRMロードを入れない。`Engine/Scene/Camera/Light/canvas/fallback mesh/未対応表示/切替UI` までに絞る。
- `@babylonjs/loaders` は初回依存から外す。GLBロード実装時に追加する。
- `BabylonAvatarViewer` は既存 `AvatarViewerProps` 互換で受け、未対応機能はno-opにする。
- `.vrm-canvas-container canvas` を維持する。
- AppテストではBabylon側をmockできるようにする。

## 7. 次フェーズ

- Babylon GLB load PoC。
- Babylon physics sandbox。
- babylon-vrm-loader検証。
- VRM表情/モーフ/リップシンク比較。
- BabylonをVirtual World本体候補にするか判断。

### P-BAB-7: SceneRuntime authoritative + Babylon physics MVP

裁定:

- Rust/Tauri側のSceneRuntimeは正本状態を持つ。object registry、revision、command validation、idempotency、diagnosticsを担当する。
- Babylon側は描画、入力、debug、local predictive/visual physicsを担当する。
- Babylon physics結果はvalidated scene commandでcommitされるまで正本状態ではない。
- per-frame全量IPCは避ける。dirty delta、tick budget、snapshot resyncで同期する。

MVP範囲:

- `SceneObject.physics` を正本schemaへ追加する。
- dynamic cube、床衝突、重力、friction/restitution、回転visualをBabylon側で確認できるようにする。
- runtime object破棄時にmesh/material/physics stateを破棄する。
- RTL/WDIOから読めるphysics diagnosticsを出す。

MVP対象外:

- Rust側の物理step。
- deterministic replay。
- network replication。
- full ECS archetype/job scheduler。
- plugin script system。
- constraint/joint/raycastを含む高度な物理。

## 8. 参考情報

Babylon.js公式/関連:

- Babylon.js Physics: Physics V2 / Havok統合。剛体、衝突、joint、raycast等を扱える。
- Babylon.js Morph Targets: morph target manager / influence animationに対応。
- Babylon.js Inspector / DebugLayer: 実行中sceneを確認・調整できる診断ツール。
- Babylon.js WebXR: VR/AR向け抽象が厚い。
- `@babylonjs/core`, `@babylonjs/loaders`: Oribisへ導入する最小依存。

VRM関連:

- `virtual-cast/babylon-vrm-loader`: Babylon.js向けcommunity VRM loader。MIT License。
- Babylon.js公式ドキュメントにもcommunity extensionとしてVRM loaderの案内がある。
- ただし、VRM/MToon/VRM 1.0/springBone/表情の商用品質はOribis側で実機検証が必要。

Three.jsとの差分:

- Three.jsは既存OribisのVRM/表情/アニメ基盤と相性が良い。
- Babylon.jsは物理・ゲーム的scene・Inspector・WebXRが強い。
- 完全移行は、VRM/表情/morph/lip sync/animation/material/background/cameraが同等化できた後に行う。
