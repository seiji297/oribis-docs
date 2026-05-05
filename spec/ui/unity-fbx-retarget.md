# Unity Fbx Retarget

## Overview

# 仕様書: unity-fbx-retarget

## 概要
- **名前**: Unity HumanBodyBones FBX リターゲット
- **カテゴリ**: oribis
- **目的**: ARP (Auto-Rig Pro) Unity 形式で書き出した FBX アニメーションを VRM モデルに適用できるようにする

## 仕様

- Unity HumanBodyBones 命名規則のボーン名（`Hips`, `LeftUpperArm`, `RightLowerLeg` 等）を VRM normalized bone 名（`hips`, `leftUpperArm`, `rightLowerLeg` 等）に変換するマップを追加
- 差分は頭文字の大小のみ（Pascal Case → camelCase）
- 既存の Mixamo リターゲットパイプライン（`retargetMixamoToVrm.ts`）を流用
- ボーン名の先頭が `mixamorig:` でない場合に Unity マップを試みる自動判定
- マップにないボーンはスキップ（既存挙動と同じ）
- FBX モデル自身への AnimationMixer 再生（既存）は非破壊

### ボーン名変換ルール

| Unity HumanBodyBones | VRM normalized |
|---------------------|----------------|
| `Hips` | `hips` |
| `LeftUpperArm` | `leftUpperArm` |
| `RightUpperArm` | `rightUpperArm` |
| `Head` | `head` |
| （計55骨） | （同一パターン、頭文字のみ小文字化） |

## 受入条件 (AC)

- AC-1: Given Unity HumanBodyBones FBX アニメーション、When VRM モデルにロード、Then VRM ボーンにアニメーションが適用される（手足が動く）
- AC-2: Given Mixamo FBX アニメーション（`mixamorig:` プレフィックス）、When ロード、Then 既存 Mixamo リターゲットが維持される（非破壊）
- AC-3: Given マップ未定義ボーン（カスタムボーン等）、When ロード、Then そのボーンのトラックはスキップされクラッシュしない
- AC-4: Given ボーン名自動判定、When `Hips` トラックを持つ FBX、Then Unity マップが選択される（`mixamorig:Hips` ではないことで判定）
- AC-5: Given `UNITY_HUMANOID_VRM_RIG_MAP` 定義、Then キー数が 20 以上であること（必須骨カバレッジ）

## 既存パターン参照
- **関連コード**: `src/adapters/retargetMixamoToVrm.ts`（`MIXAMO_VRM_RIG_MAP`・パイプライン）
- **類似実装**: feat/avatar-animation の Mixamo リターゲット実装

## 除外事項
- VRMA 形式のサポート（別フィーチャー）
- PMX/MMD モデルへのリターゲット
- Blender 標準 FBX（ボーン名任意のもの）
- FBX モデルのロード自体（既存対応済み）

## Implementation Notes

# unity-fbx-retarget — 実装ログ

## Log

### 2026-04-25 要件定義
- Producer指示: ARP Unity FBX → VRM リターゲット対応を追加
- 調査: Unity HumanBodyBones = VRM normalized bone（頭文字大小のみ差異）
- spec.md作成（AC-1〜AC-5）
> 状態: AC 5件定義 / バグ 0 / 次: planner→ECCチェーン開始

### 2026-04-25 テスト追加
- tdd-guide: Unity FBXリターゲットテスト15件追加（UNITY_HUMANOID_VRM_RIG_MAP×5、retargetUnityToVrm×6、retargetFbxToVrm×3）
- 計24テスト PASS (commit ce9e365, worktree: feat/avatar-animation)
> 状態: 実装+テスト完了 / バグ 0 / 次: feat/avatar-animationブランチ マージ待ち

## Known Issues / Backlog

# unity-fbx-retarget — Issues

<!-- 
タグ: [バグ] [つまづき] [判断]
バグ番号: #B001, #B002, ...
-->

## Open

## Closed

