# sysdev-4 設計書 — Phase 0 表情反映システム

## 変更対象ファイル（独占コンポーネントのみ）

| ファイル | 変更種別 |
|---------|---------|
| `src/utils/expressionSystem.ts` | 新規作成 |
| `src/utils/expressionSystem.test.ts` | 新規作成 |
| `src/components/AvatarViewer.tsx` | 修正 |

**触ってはいけないファイル**: adapters/*, controllers/*, loaders/*, hooks/*, themes/*, types/*, plugin/*, skill/*, App.tsx, src-tauri/配下の全ファイル

**重要**: AvatarViewer.tsx を分割しない。ファイルを増やさない。既存の構造を維持したまま表情システムを追加する。

---

## 変更1: 新規ファイル `src/utils/expressionSystem.ts`

```typescript
/**
 * Phase 0 表情反映システム — 純関数
 * spec: docs/projects/oribis/spec/system/expression-system.md
 */

/**
 * mood（機嫌）を計算する。
 * mood = 揮発性浮動小数 [0.0 - 1.0]。セッション内のみ。
 */
export function computeMood(
  affinity: number,              // -100 ~ +100
  hourOfDay: number,             // 0 ~ 23
  sessionElapsedHours: number,   // セッション経過時間
  errorRate: number,             // 0.0 ~ 1.0
  animaState: string,            // "error" | "lewd" | 他
): number {
  const affinityFactor = (affinity + 100) / 200;

  const hourFactor = (() => {
    if (hourOfDay >= 5 && hourOfDay <= 9) return 1.0;
    if (hourOfDay >= 10 && hourOfDay <= 18) return 0.8;
    if (hourOfDay >= 19 && hourOfDay <= 22) return 0.65;
    return 0.45;
  })();

  const fatigueFactor = Math.max(0.5, 1.0 - Math.max(0, sessionElapsedHours - 4) * 0.083);
  const errorFactor = 1.0 - errorRate * 0.4;
  const animaMod = (animaState === "error" || animaState === "lewd") ? -0.15 : 0;

  const raw = affinityFactor * 0.5
    + hourFactor * 0.2
    + fatigueFactor * 0.15
    + errorFactor * 0.15
    + animaMod;

  return Math.max(0, Math.min(1, raw));
}

/**
 * 好感度 + 機嫌 → ベース表情を決定する。
 */
export function computeBaseExpression(
  affinity: number,   // -100 ~ +100
  mood: number,       // 0 ~ 1
): { name: string; intensity: number } {
  if (affinity >= 50 && mood >= 0.7) {
    return { name: "happy", intensity: 0.25 + mood * 0.2 };
  }
  if (affinity <= -30 || mood <= 0.3) {
    return { name: "sad", intensity: 0.15 + (1 - mood) * 0.15 };
  }
  if (mood >= 0.6) {
    return { name: "relaxed", intensity: 0.1 + mood * 0.1 };
  }
  return { name: "neutral", intensity: 0 };
}

/**
 * jitter（揺らぎ）を計算する。低周波sin合成ノイズ。
 */
export function computeJitter(t: number, mood: number): number {
  const jitter = Math.sin(t * 0.7 + 1.3) * Math.sin(t * 1.1 + 0.5) * 0.03;
  const jitterScale = 1.0 + (1.0 - mood) * 0.5;
  return jitter * jitterScale;
}

/**
 * lerp補間。既存の lerpToward と同等。
 */
export function lerpToward(current: number, target: number, speed: number): number {
  const diff = target - current;
  if (Math.abs(diff) < 0.001) return target;
  return current + diff * Math.min(1, speed);
}
```

---

## 変更2: 新規ファイル `src/utils/expressionSystem.test.ts`

```typescript
import { describe, it, expect } from "vitest";
import { computeMood, computeBaseExpression, computeJitter, lerpToward } from "./expressionSystem";

describe("computeMood", () => {
  it("returns value between 0 and 1", () => {
    const result = computeMood(50, 12, 1, 0, "idle");
    expect(result).toBeGreaterThanOrEqual(0);
    expect(result).toBeLessThanOrEqual(1);
  });

  it("high affinity + morning → high mood", () => {
    const result = computeMood(100, 7, 0, 0, "idle");
    expect(result).toBeGreaterThan(0.8);
  });

  it("low affinity + error state → low mood", () => {
    const result = computeMood(-100, 2, 8, 0.8, "error");
    expect(result).toBeLessThan(0.3);
  });

  it("error/lewd animaState applies -0.15 penalty", () => {
    const normal = computeMood(50, 12, 1, 0, "idle");
    const error = computeMood(50, 12, 1, 0, "error");
    expect(normal - error).toBeCloseTo(0.15, 1);
  });

  it("clamps to 0 on extreme negative inputs", () => {
    const result = computeMood(-100, 2, 10, 1.0, "error");
    expect(result).toBe(0);
  });

  it("clamps to 1 on extreme positive inputs", () => {
    const result = computeMood(100, 7, 0, 0, "idle");
    expect(result).toBeLessThanOrEqual(1);
  });

  it("fatigue factor kicks in after 4 hours", () => {
    const fresh = computeMood(50, 12, 2, 0, "idle");
    const tired = computeMood(50, 12, 8, 0, "idle");
    expect(fresh).toBeGreaterThan(tired);
  });
});

describe("computeBaseExpression", () => {
  it("high affinity + high mood → happy", () => {
    const result = computeBaseExpression(80, 0.9);
    expect(result.name).toBe("happy");
    expect(result.intensity).toBeGreaterThan(0);
  });

  it("low affinity → sad", () => {
    const result = computeBaseExpression(-50, 0.5);
    expect(result.name).toBe("sad");
  });

  it("low mood → sad", () => {
    const result = computeBaseExpression(0, 0.2);
    expect(result.name).toBe("sad");
  });

  it("medium affinity + good mood → relaxed", () => {
    const result = computeBaseExpression(20, 0.7);
    expect(result.name).toBe("relaxed");
  });

  it("medium affinity + medium mood → neutral", () => {
    const result = computeBaseExpression(0, 0.5);
    expect(result.name).toBe("neutral");
    expect(result.intensity).toBe(0);
  });
});

describe("computeJitter", () => {
  it("returns small value (±0.05 range)", () => {
    for (let t = 0; t < 10; t += 0.1) {
      const j = computeJitter(t, 0.5);
      expect(Math.abs(j)).toBeLessThan(0.05);
    }
  });

  it("low mood → larger jitter amplitude", () => {
    const jitterHigh = Math.abs(computeJitter(1.0, 0.9));
    const jitterLow = Math.abs(computeJitter(1.0, 0.1));
    // jitterScale at mood=0.1 is 1.45, at mood=0.9 is 1.05
    expect(jitterLow).toBeGreaterThan(jitterHigh);
  });
});

describe("lerpToward", () => {
  it("moves toward target", () => {
    const result = lerpToward(0, 1, 0.5);
    expect(result).toBeCloseTo(0.5);
  });

  it("snaps to target when close enough", () => {
    const result = lerpToward(0.9995, 1, 0.5);
    expect(result).toBe(1);
  });

  it("speed=1 reaches target immediately", () => {
    const result = lerpToward(0, 1, 1);
    expect(result).toBe(1);
  });
});
```

---

## 変更3: AvatarViewer.tsx — AvatarModelProps に props 追加

### 現状（213行目付近）
```typescript
interface AvatarModelProps {
  url: string;
  poseSet: PoseSet;
  lipSyncValue?: number;
  avatarCommand?: ControlAvatarPayload;
  motionState?: MotionState;
  motionClips?: Partial<Record<MotionState, THREE.AnimationClip>>;
  boneOverrides?: BoneOverrides;
  exprOverrides?: Record<string, number>;
  lookAtTarget?: LookAtTarget;
  onBonesLoaded?: (bones: string[]) => void;
  onExpressionsLoaded?: (exprs: string[]) => void;
  onWristPos?: (pos: { rx: number; ry: number; rz: number; lx: number; ly: number; lz: number }) => void;
  onHeadScreenPos?: (pos: { x: number; y: number }) => void;
  onControllerReady?: (controller: AvatarController | null, format: "vrm" | "fbx" | "mmd" | null, avatarModel: AvatarModel | null) => void;
  perfOverrides?: PerfOverrides;
}
```

### 変更後
```typescript
interface AvatarModelProps {
  url: string;
  poseSet: PoseSet;
  lipSyncValue?: number;
  avatarCommand?: ControlAvatarPayload;
  motionState?: MotionState;
  motionClips?: Partial<Record<MotionState, THREE.AnimationClip>>;
  boneOverrides?: BoneOverrides;
  exprOverrides?: Record<string, number>;
  lookAtTarget?: LookAtTarget;
  onBonesLoaded?: (bones: string[]) => void;
  onExpressionsLoaded?: (exprs: string[]) => void;
  onWristPos?: (pos: { rx: number; ry: number; rz: number; lx: number; ly: number; lz: number }) => void;
  onHeadScreenPos?: (pos: { x: number; y: number }) => void;
  onControllerReady?: (controller: AvatarController | null, format: "vrm" | "fbx" | "mmd" | null, avatarModel: AvatarModel | null) => void;
  perfOverrides?: PerfOverrides;
  affinity?: number;    // 追加: -100 ~ +100
  mood?: number;         // 追加: 0 ~ 1
}
```

---

## 変更4: AvatarViewerProps に props 追加

### 現状（651行目付近）の `AvatarViewerProps` に追加

```typescript
export interface AvatarViewerProps {
  // ... 既存のprops全てそのまま維持 ...
  affinity?: number;    // 追加
  mood?: number;         // 追加
}
```

---

## 変更5: AvatarModelComponent — refs 追加

`AvatarModelComponent` 関数内、既存の `const lastExprNameRef` の下に追加:

```typescript
  // Phase 0: 表情反映システム用 refs
  const exprDisplayRef = useRef<Map<string, number>>(new Map());
  const pulseRef = useRef<{ name: string; intensity: number; remainSec: number } | null>(null);
```

import も追加:
```typescript
import { computeBaseExpression, computeJitter, lerpToward } from "../utils/expressionSystem";
```

---

## 変更6: AvatarModelComponent useFrame — 表情セクション書き換え

### 書き換え対象

useFrame内の **lines 483〜521**（`// -- Expression values` から avatarCommand の表情処理まで）を以下に置き換える。

### 置き換え前のコード（そのまま削除する範囲）

```typescript
    // -- Expression values (blink driven by clip via blinkHolderRef) --
    const pendingExpressions: Record<string, number> = {
      blink: blinkHolderRef.current.value,
      aa: lipSyncValue ?? 0,
    };

    // -- Avatar command --
    if (avatarCommand && avatarCommand !== lastCommandRef.current) {
      lastCommandRef.current = avatarCommand;
      if (avatarCommand.motion !== "none" && avatarCommand.motion !== "idle") {
        motionRef.current = { type: avatarCommand.motion, startTime: t, duration: 0.6 };
      }
    }

    if (avatarCommand) {
      const exprMap: Record<string, string> = {
        happy: "happy",
        sad: "sad",
        thinking: "neutral",
        surprised: "surprised",
        angry: "angry",
        neutral: "neutral",
      };
      const expr = exprMap[avatarCommand.expression] ?? "neutral";
      if (expr === "neutral") {
        if (lastExprNameRef.current) {
          pendingExpressions[lastExprNameRef.current] = 0;
          lastExprNameRef.current = null;
        }
      } else {
        if (lastExprNameRef.current && lastExprNameRef.current !== expr) {
          pendingExpressions[lastExprNameRef.current] = 0;
        }
        pendingExpressions[expr] = avatarCommand.intensity;
        lastExprNameRef.current = expr;
      }

      if (avatarCommand.gaze === "camera" && head) {
        head.rotation.y = 0;
        head.rotation.z = 0;
      } else if (avatarCommand.gaze === "away" && head) {
        head.rotation.y = 0.3;
        head.rotation.z = 0;
      } else if (avatarCommand.gaze === "down" && head) {
        head.rotation.x = -0.2;
        head.rotation.y = 0;
      }
    }
```

### 置き換え後のコード

```typescript
    // -- Expression values (blink driven by clip via blinkHolderRef) --
    const pendingExpressions: Record<string, number> = {
      blink: blinkHolderRef.current.value,
      aa: lipSyncValue ?? 0,
    };

    // -- Avatar command: motion + gaze（表情は Phase 0 で処理） --
    if (avatarCommand && avatarCommand !== lastCommandRef.current) {
      lastCommandRef.current = avatarCommand;
      // motion（nod/shake）
      if (avatarCommand.motion !== "none" && avatarCommand.motion !== "idle") {
        motionRef.current = { type: avatarCommand.motion, startTime: t, duration: 0.6 };
      }
      // pulse 注入（avatarCommand 変化時）
      const exprMap: Record<string, string> = {
        happy: "happy", sad: "sad", thinking: "neutral",
        surprised: "surprised", angry: "angry", neutral: "neutral",
      };
      const pulseExpr = exprMap[avatarCommand.expression] ?? "neutral";
      if (pulseExpr !== "neutral") {
        pulseRef.current = {
          name: pulseExpr,
          intensity: avatarCommand.intensity,
          remainSec: 2.0,
        };
      }
    }

    // -- gaze control（既存ロジック維持） --
    if (avatarCommand) {
      if (avatarCommand.gaze === "camera" && head) {
        head.rotation.y = 0;
        head.rotation.z = 0;
      } else if (avatarCommand.gaze === "away" && head) {
        head.rotation.y = 0.3;
        head.rotation.z = 0;
      } else if (avatarCommand.gaze === "down" && head) {
        head.rotation.x = -0.2;
        head.rotation.y = 0;
      }
    }

    // -- Phase 0: 表情反映システム --
    const EXPR_LERP_SPEED = 2.0;
    const currentAffinity = affinity ?? 50;
    const currentMood = mood ?? 0.6;

    // base expression（好感度 + mood）
    const base = computeBaseExpression(currentAffinity, currentMood);

    // pulse 減衰
    const pulse = pulseRef.current;
    if (pulse && pulse.remainSec > 0) {
      pulse.remainSec -= delta;
    }

    // jitter
    const effectiveJitter = computeJitter(t, currentMood);

    // ブレンド（pulse > base）
    let targetName: string;
    let targetIntensity: number;
    if (pulse && pulse.remainSec > 0 && pulse.intensity > 0.1) {
      const pulseT = Math.max(0, pulse.remainSec / 2.0);
      targetName = pulse.name;
      targetIntensity = pulse.intensity * pulseT;
    } else {
      targetName = base.name;
      targetIntensity = base.intensity;
    }
    targetIntensity = Math.max(0, Math.min(1, targetIntensity + effectiveJitter));

    // lerp 補間 — 現在の表示値を目標へ滑らかに遷移
    const currentDisplay = exprDisplayRef.current.get(targetName) ?? 0;
    const newDisplay = lerpToward(currentDisplay, targetIntensity, EXPR_LERP_SPEED * delta);
    exprDisplayRef.current.set(targetName, newDisplay);

    // 前の表情をフェードアウト
    if (lastExprNameRef.current && lastExprNameRef.current !== targetName) {
      const prevVal = exprDisplayRef.current.get(lastExprNameRef.current) ?? 0;
      const fadedVal = lerpToward(prevVal, 0, EXPR_LERP_SPEED * delta);
      exprDisplayRef.current.set(lastExprNameRef.current, fadedVal);
      if (fadedVal < 0.001) {
        pendingExpressions[lastExprNameRef.current] = 0;
      } else {
        pendingExpressions[lastExprNameRef.current] = fadedVal;
      }
    }
    lastExprNameRef.current = targetName;

    // Phase 0 表情を pendingExpressions に適用
    if (targetName !== "neutral") {
      pendingExpressions[targetName] = newDisplay;
    }
```

---

## 変更7: AvatarViewer 関数 — props 受け取り & パススルー

### 変更箇所（692行目付近）

`AvatarViewer` 関数の引数 destructuring に `affinity`, `mood` を追加:

```typescript
export function AvatarViewer({
  // ... 既存の全props ...
  affinity,     // 追加
  mood,         // 追加
}: AvatarViewerProps) {
```

### 変更箇所（784行目付近）

`<AvatarModelComponent>` の props に追加:

```typescript
          <AvatarModelComponent
            url={vrmUrl}
            poseSet={poseSet}
            lipSyncValue={lipSyncValue}
            avatarCommand={avatarCommand}
            motionState={motionState}
            motionClips={motionClips}
            boneOverrides={boneOverrides}
            exprOverrides={exprOverrides}
            lookAtTarget={lookAtTarget}
            onBonesLoaded={onBonesLoaded}
            onExpressionsLoaded={onExpressionsLoaded}
            onWristPos={onWristPos}
            onHeadScreenPos={onHeadScreenPos}
            perfOverrides={perfOverrides}
            affinity={affinity}
            mood={mood}
          />
```

---

## 絶対に保持すべき既存機能（変更禁止チェックリスト）

以下の既存機能が変更後も **完全に同一動作** することを確認すること:

| 機能 | 行番号 | 確認方法 |
|------|--------|---------|
| boneOverrides の rotation 適用 | 551-560 | `boneOverrides` が `bone.rotation.x/y/z` に代入される |
| exprOverrides の pendingExpressions マージ | 563-567 | `exprOverrides` が `pendingExpressions` に上書きされる |
| finger curl 再適用（boneOverrides考慮） | 630-634 | `boneOverrides[fc.name]` がない場合のみ curl 適用 |
| lookAtTarget 視線制御 | 569-586 | camera/座標/null 3パターン |
| onWristPos コールバック | 588-600 | 手首回転の報告 |
| onHeadScreenPos コールバック | 602-612 | 頭部スクリーン座標の報告 |
| FpsDriver | 778 | `_presentFps ?? 30` で駆動 |
| TargetedOrbitControls | 39-173 | 全体がそのまま |
| proceduralMixer + blinkMixer | 369-418, 474-478 | data-driven idle + blink |
| motionRef nod/shake | 534-548 | モーションオーバーレイ |
| AvatarController 統合 | 614-620 | VRM/FBX コントローラー |
| updateGranular + setExpression | 622-627 | morphs は update 後に適用 |

---

## テスト実行コマンド

```bash
pnpm vitest run src/utils/expressionSystem.test.ts
pnpm tsc --noEmit
```

## 完了条件チェックリスト

- [ ] `pnpm vitest run src/utils/expressionSystem.test.ts` 全 PASS
- [ ] `pnpm tsc --noEmit` エラーなし
- [ ] `computeMood()` が 0-1 の値を返す
- [ ] `computeBaseExpression()` が affinity × mood マトリクスで正しい表情を返す
- [ ] avatarCommand 変化時に pulse が注入され 2秒で減衰する
- [ ] jitter が ±0.05 以内のノイズを生成する
- [ ] 表情が lerp で滑らかに遷移する（EXPR_LERP_SPEED=2.0）
- [ ] 前の表情がフェードアウトする（sticking 防止）
- [ ] boneOverrides が全ボーンに正しく適用される（line 551-560 不変）
- [ ] exprOverrides が pendingExpressions にマージされる（line 563-567 不変）
- [ ] finger curl が再適用される（line 630-634 不変）
- [ ] AvatarViewer.tsx を分割していないこと（ファイル数が増えていないこと、expressionSystem.ts を除く）
- [ ] adapters/, controllers/, loaders/, hooks/, types/ を変更していないこと
