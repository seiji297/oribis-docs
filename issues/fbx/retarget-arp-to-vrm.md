# ARP → VRM リターゲット: 経緯・現状・TODO

## 対象ファイル
`src/adapters/retargetMixamoToVrm.ts` — `retargetArpToVrm()` 関数

---

## 確定済み: 数式（2026-05-21 修正）

```
Q_vrm = R * inv(rSA) * inv(R) * fN
```

- `R` = Z-up → Y-up 変換 = quaternion(-0.70710678, 0, 0, 0.70710678)（X軸 -90°回転）
- `rSA` = ARP ボーンの parent-relative rest quaternion（Blender Z-up 座標系、bone.matrix由来）
- `fN` = GLTF アニメーション frame N の local quaternion（**Y-up** 座標系）
- `R * inv(rSA) * inv(R)` = inv(rSA) を共役変換で Y-up に変換

### 座標系の違いが鍵
- rSA は Blender Z-up 空間（bone.matrix = parent-relative）
- fN は GLTF Y-up 空間（THREE.js GLTFLoader が座標変換済み）
- → rSA を Y-up に変換してから fN に適用する必要がある

### 旧公式のバグ（2026-05-21 修正前）
```
旧: Q_vrm = R * inv(rSA) * fN * inv(R)   ← inv(R) が全体に掛かる（間違い）
新: Q_vrm = R * inv(rSA) * inv(R) * fN    ← inv(rSA) だけ共役変換（正しい）
```
旧公式は腕の回転軸が Y軸（水平振り）になり、腕が下がらず前方に突き出る結果になっていた。

### 導出
```
rSA_yup = R * rSA * inv(R)              ← Z-up rest を Y-up に変換
Q_vrm   = inv(rSA_yup) * fN             ← rest 除去して animation delta のみ残す
        = inv(R * rSA * inv(R)) * fN
        = R * inv(rSA) * inv(R) * fN
```

---

## rSA ソース（2026-05-21 更新）

**ARP_BONE_REST テーブルに52ボーン全登録**（hips〜指先）。動的計算パス廃止。

```typescript
const rSA = ARP_BONE_REST[vrmName]?.restSelfArmature ?? identity;
// hips: identity（GLTFキーフレームにrest未焼き込みのため）
// 他全ボーン: Blender bone.matrix（parent-relative Z-up）
```

### restSelfArmature の定義
- `bone.matrix` = parent-relative rest quaternion（Z-up）← 名前が紛らわしいが armature-space ではない
- `bone.matrix_local` = armature-space rest quaternion ← こちらが累積
- ソース: `tools/export_arp_bone_rest.py` → `arp_bone_rest_arp.json`

### hips 特別扱いの理由
- GLTF キーフレーム: 子ボーンは `rSA_yup * pose_delta`（rest焼き込み済み）
- hips は `pure_animation`（rest未焼き込み、identity at rest）
- → hips の rSA を identity にすることで `inv(identity) * fN = fN` となり正しく動作

---

## 完了

| ボーン群 | 状態 | 備考 |
|---------|------|------|
| 全52ボーン ARP_BONE_REST | ✅ 登録済み | commit 19b794c。hips〜指先。Blender export値 |
| hips rSA = identity | ✅ 修正済み | commit a247df5。root bone GLTFキーフレームはrest未焼き込み |
| 数式 inv(R) 位置修正 | ✅ 修正済み | commit 8f6e49c。`R*inv(rSA)*inv(R)*fN` に変更 |
| 全身 | 🔧 視覚テスト待ち | 上記3修正の統合結果を要確認 |

## sysdev-2 handoff（2026-05-07, commit 28f352b, branch sysdev-2/fbx）

**到達点**: ARP リターゲット安定 baseline 復元。app 起動可能、全身立位。

**今回確定した修正**:
1. `ARP_BONE_REST` から脚4本削除（leftUpperLeg/leftLowerLeg/rightUpperLeg/rightLowerLeg）
2. `ARP_FRAME0_DELTA_BONES` に脚4本を復帰
3. non-hips position cut 維持、arm/neck の direct conjugation + frame0 delta + post offset 系は維持

**重要な学び（禁止事項）**:
- `animationLoader.ts` に `node:fs/promises` / `node:url` を混ぜると **app 起動不能** → Node 依存は本体コードに入れてはいけない
- runtime finger basis / palm-plane 補正は見た目を明確に劣化させた → **不採用**
- 全身経路をまとめて触ってはいけない

**検証済み**: `pnpm tsc --noEmit` PASS、`pnpm vitest run src/adapters/retargetMixamoToVrm.test.ts` PASS

---

## 未解決・要調査

### 1. 手の甲の向き・指の打鍵方向 — ~~hand/finger retarget 軸問題~~ f0 空間不一致バグ
- **根本原因特定済み（2026-05-08）**: `restSelfArmature = inv(parent_restLocal) * bone_restLocal` だが、hand/finger は `restPoseCache`（= `restLocal`）をそのまま f0 に使用していた。空間不一致。
- **修正**: `computedRestSA` マップを追加。ARP_BONE_REST 未登録ボーンは `inv(parent_restLocal) * bone_restLocal` を restPoseCache から動的計算
- **状態**: 修正コード済み、38テストPASS、**視覚テスト待ち**
- **制約**: `retargetMixamoToVrm.ts` 以外へ波及させない。全身 baseline を壊さない前提で局所修正のみ

### 2. 脚 — ~~クロスレッグ座り~~ baseline 復元で解消
- ARP_BONE_REST から脚4本を削除、ARP_FRAME0_DELTA_BONES に復帰で解消（28f352b）
  - ARP_BONE_REST 値が正しいかどうか未検証
- **確認方法**: Blender で元 FBX を開き Typing アニメのポーズを確認

### 3. デバッグログ削除 — 後で
- `[retargetArpToVrm] === All tracks in clip ===` など大量ログあり
- 全骨格の動作確認後に削除

---

## ARP_BONE_REST 登録状況

**全52ボーン登録済み**（commit 19b794c）。欠損なし。
- 体幹: hips, spine, chest, upperChest, neck, head
- 腕: shoulder/upperArm/lowerArm/hand × L/R
- 脚: upperLeg/lowerLeg/foot/toes × L/R
- 指: thumb(3)/index(3)/middle(3)/ring(3)/little(3) × L/R

---

## 次のアクション（優先順）

1. **視覚テスト**: pnpm tauri dev → Typing_Stand.glb 読み込み → 全身姿勢確認
2. OUTPUTダンプ取得 → rightUpperArm の Z軸回転が支配的か確認
3. OK → デバッグログ削除 → commit & merge
4. NG → ダンプ値から次の原因特定

**やってはいけないこと**:
- `animationLoader.ts` に Node 専用 import を戻す
- finger basis を palm-plane から runtime 再構築する系を再投入する
- 全身経路をまとめて触る

---

## sysdev-2 進捗（2026-05-21, branch sysdev-2/retarget-test）

**到達点**: 数式バグ修正済み。視覚テスト待ち。

**今回の修正**:
1. ARP_BONE_REST に52ボーン全登録（19b794c）— 動的計算パス廃止
2. hips rSA = identity に修正（a247df5）— root bone GLTF rest 未焼き込み対応
3. **inv(R) 位置修正（8f6e49c）** — `R*inv(rSA)*fN*inv(R)` → `R*inv(rSA)*inv(R)*fN`

**バグの根本原因**:
- rSA は Blender Z-up、fN は GLTF Y-up
- 旧公式は inv(R) を全体に掛けていた → fN（既にY-up）も変換されて軸がズレた
- rightUpperArm が Y軸63°回転（水平振り）になり、Z軸回転（腕を下ろす）にならなかった
- 正しくは rSA だけを共役変換 R*inv(rSA)*inv(R) して Y-up にし、fN はそのまま掛ける

**重要な知見**:
- bone.matrix = parent-relative（名前と逆）、bone.matrix_local = armature-space
- GLTF loader は座標変換済みの Y-up 値を返す → bone local quaternion に R 変換は不要
- rSA が Z-up のまま → rSA だけ共役変換が必要

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `src/adapters/retargetMixamoToVrm.ts` | リターゲット実装本体 |
| `src/loaders/animationLoader.ts` | アニメーションローダー（extractBoneRestPoses） |
| `tools/export_arp_bone_rest.py` | Blender スクリプト: ARP rest pose 取得 |
| `C:\Users\admin\Downloads\arp_bone_rest_arp.json` | Blender export 結果（handl/handr は空） |
