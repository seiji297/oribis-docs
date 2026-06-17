# Oribis 3D Asset Creator MVP 計画

最終更新: 2026-06-17

## 1. 結論

A案を採用する。

**A案: 既存Blender Hub / Blender MCP / Three.js previewを拡張し、3D Asset Creator MVPとして実装する。**

理由:

- Oribisには既に `blender_*` Tauri command、Blender Hub plugin、VRM/FBX/MMD viewer、Three.js描画基盤がある。
- 新規にUnity/Godot/Babylon.jsへ寄せるより、既存資産を使う方が初回リリースに間に合う。
- 任意Python実行や本格3D生成AIを初回から入れると、安全境界、品質、依存、テストが重くなる。
- Virtual Studioの価値は「3D生成モデルそのもの」ではなく、Anima/Worker/Plugin/Blender/Previewを同じ制作体験に接続する点にある。

初回MVPでは、プロンプトから直接任意のBlender Pythonを実行しない。
Oribis側で許可したテンプレートだけを使って、Blender内に小物・背景・簡易シーンを生成する。

## 2. 目的

ユーザーが自然文で「小さな机」「近未来の部屋」「Animaの横に置くライト」などを指定し、Oribisが3D制作の初期案を生成・プレビュー・保存できる状態を作る。

初回MVPの到達点:

- 3D生成ジョブを作成できる。
- Blender接続状態を確認できる。
- 安全なテンプレートからBlenderシーンを生成できる。
- 生成結果をGLB/Blend/VRM等の成果物としてOribisHome配下へ保存する準備ができる。
- 生成結果を既存3D previewまたはBlender側で確認できる。
- Anima/WorkerのJob/Event/Artifactへ生成履歴を接続できる。

初回MVPでやらないこと:

- 任意Pythonコードのユーザー入力実行。
- 外部3D生成AIの直接接続。
- Blender sidecarの自動spawn。
- Unity/Godot/Babylon.jsへの置き換え。
- 商用アセットマーケット連携。
- 生成物の自動公開、課金、配布。

## 3. 既存資産

| 領域 | 既存資産 | 使い方 |
|---|---|---|
| Blender接続 | `src-tauri/src/blender/*` | `blender_connect`, `blender_status`, `blender_scene_info`, `blender_execute_code` などを利用 |
| Blender UI | `plugins/blender-hub/*` | 既存Blender Hubに3D Creator導線を追加、または新規Creator panelで再利用 |
| 3D表示 | `AvatarViewer.tsx`, `VrmViewer.tsx` | Anima/VRM previewは既存維持。Asset previewは別コンポーネントで最小実装 |
| アセット読込 | `avatarLoader.ts`, `animationLoader.ts` | 既存VRM/FBX/MMD読込は壊さない |
| Internal Worker | `InternalWorkerJob/Event/Artifact` | 生成ジョブと成果物記録に使う |
| Self Improvement | `self_improvement` | 生成失敗/採用/却下をObservationへ接続可能 |

## 4. アーキテクチャ

標準フロー:

1. ユーザーが3D作成プロンプトを入力する。
2. Oribisが `AssetGenerationJob(kind=3d)` を作る。
3. AnimaまたはInternal Workerがプロンプトを安全な `SceneRecipe` に変換する。
4. `SceneRecipe` を許可済みBlenderテンプレートへ渡す。
5. Blender MCP経由でシーンを生成する。
6. 成果物をOribisHome配下へ保存する。
7. Job/Event/Artifactへ記録する。
8. UIにpreview、保存先、再生成、Observation記録導線を出す。

```
User Prompt
  -> 3D Creator UI
  -> AssetGenerationJob(kind=3d)
  -> SceneRecipe(JSON)
  -> Safe Blender Template
  -> blender_execute_code(template only)
  -> Artifact(glb/blend/png preview)
  -> Job/Event/Observation
```

## 5. SceneRecipe

初回MVPでは、自由文をそのままBlender Pythonへ渡さない。
中間表現として `SceneRecipe` を使う。

```json
{
  "title": "small desk lamp",
  "category": "prop",
  "style": "simple",
  "objects": [
    {
      "type": "cylinder",
      "name": "lamp_base",
      "location": [0, 0, 0],
      "scale": [1, 1, 0.2],
      "material": "warm_metal"
    }
  ],
  "materials": [
    {
      "name": "warm_metal",
      "baseColor": [0.9, 0.7, 0.45],
      "roughness": 0.4
    }
  ],
  "lighting": "studio_soft",
  "camera": "front_three_quarter"
}
```

許可するobject type:

- cube
- sphere
- cylinder
- cone
- plane
- bevelled_box
- text_label
- point_light
- area_light

初回で許可しないもの:

- 任意mesh import
- 任意URL download
- 任意Python expression
- file system任意path
- shell execution

## 6. 保存先

OribisHome配下に保存する。

候補:

```
HOME/Documents/oribis/assets/3d/
  jobs/
    <job_id>/
      recipe.json
      scene.blend
      preview.png
      export.glb
      manifest.json
```

`manifest.json` には以下を保存する。

- jobId
- prompt
- recipe hash
- generatedAt
- generatorVersion
- artifacts
- sourceProvider
- safetyDecision
- userDecision: accepted/rejected/unknown

## 7. UI

初回MVPのUIは、既存Jobsタブまたは新規Creatorタブに最小追加する。

表示項目:

- prompt入力
- Blender接続状態
- SceneRecipe preview
- 生成ボタン
- 生成状態
- preview画像またはBlender側確認リンク
- artifact一覧
- Observationへ記録

表示してはいけないもの:

- 任意Pythonコード入力欄
- shell実行ボタン
- 外部URLからの3D素材取得ボタン
- raw stdout/stderrの無制限表示
- secret/credentialRef

## 8. 安全境界

`blender_execute_code` は危険な能力を持つ。
そのため、3D Creatorは以下の制約を必須にする。

- UIから任意codeを入力させない。
- SceneRecipeをvalidateする。
- Blenderへ渡すPythonはOribis同梱テンプレートのみ。
- 出力pathはOribisHome配下に限定する。
- 生成前にpreview、生成後にartifact記録。
- 失敗時は成功UIに見せない。
- secret-like値をprompt/recipe/log/artifact manifestへ保存しない。

## 9. 実装フェーズ

### P3D-1: 計画と型

- `AssetGenerationJob` の3D用最小型を定義する。
- `SceneRecipe` 型とvalidatorを作る。
- Blender未接続時のUI状態を定義する。

完了条件:

- 型テスト。
- 危険object/path/codeを拒否するvalidatorテスト。

### P3D-2: Safe Blender Template

- `SceneRecipe` からBlender Pythonを生成するテンプレートを追加する。
- プリミティブ、マテリアル、ライト、カメラだけ対応する。
- 出力pathをOribisHome配下へ限定する。

完了条件:

- Pythonテンプレートにユーザー任意codeが混ざらない。
- unit testで生成コードの危険文字列を検査。

### P3D-3: Tauri Command

- `create_3d_asset_plan` または `asset_3d_generate_from_recipe` を追加する。
- 既存 `blender_execute_code` の直叩きではなく、高レベルcommandに寄せる。

完了条件:

- Blender未接続時はblocked状態で返す。
- 成功/失敗がJob/Event/Artifactへ記録される。

### P3D-4: UI

- Creator UIを追加する。
- prompt、recipe preview、generate、artifact表示を実装する。
- 任意Python入力欄は出さない。

完了条件:

- VitestでBlender未接続/recipe preview/危険ボタン不在を確認。
- 可能ならWDIOでCreator表示と危険ボタン不在を確認。

### P3D-5: Blender実機smoke

- Blender MCP接続済み環境で、簡易シーンを生成する。
- preview.png または Blender scene infoで生成結果を確認する。

完了条件:

- 生成結果がOribisHome配下に保存される。
- 成功/失敗がJob/Event/Artifactに残る。

## 10. 後続拡張

P3D後に実施する。

- 2D PNG Creator
- MIDI Creator
- 3D生成provider差し替え
- Poly Haven等の素材検索。ただし外部取得はapproval必須。
- VRMアクセサリ装着。
- Animaの3D空間内での生成物配置。
- Virtual Studioのシーン編集モード。

## 11. codex-adviserレビュー観点

実装前に以下を確認する。

- 既存Blender連携を壊していないか。
- `blender_execute_code` の危険性をUIから隠せているか。
- 任意Python/code injectionが入らないか。
- Blender未接続時にエラーではなくblocked/empty表示になるか。
- Job/Event/Artifact/SelfImprovementに接続できる粒度か。
- 3D生成MVPがVirtual Studio価値に接続しているか。

## 12. codex-adviserレビュー結果

レビュー結果: 採用可。ただし初回MVPはさらに絞る。

反映する指摘:

- 既存 `BlenderMcpProxy` / `blender_*` Tauri command / Blender Hub plugin を使う。
- previewは旧 `VrmViewer` 固定ではなく、VRM/FBX/MMDを吸収する `AvatarViewer` / `loadAvatar` 系を優先する。
- UI/LLM生成コードを `blender_execute_code` へ直結しない。
- `/tmp/preview.vrm` 固定出力を継続しない。Oribis管理下のjob directoryへ出力する。
- Tauri command側のBlender singletonとMCP tool側のsingletonを同一状態とみなさない。
- 初回は形状/色/サイズ/ライト等の限定プリセットだけにする。

追加テスト観点:

- Blender未接続時はblocked表示。
- 生成パラメータはenum/数値だけを通す。
- 任意Python/code injectionがvalidatorで拒否される。
- 将来のE2Eでは生成後のpreview load stateを確認する。
