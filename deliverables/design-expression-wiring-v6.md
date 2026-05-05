# 設計書 v6 — 表情反映システム Phase 0（R5指摘対処済み）

## 概要

好感度Tierに基づく表情自動生成システム。バックエンド（affinity.rs 0-100範囲）とフロントエンドを統合し、アバターの表情を好感度・機嫌・パルスイベントに応じて自動制御する。

## 変更対象ファイル

| ファイル | 変更種別 |
|---------|---------|
| `src/utils/expressionSystem.ts` | 純関数群（本番コード） |
| `src/utils/expressionLoop.test.ts` | 純関数の直接テスト |
| `src/utils/expressionSystem.test.ts` | 各純関数の単体テスト |
| `src/adapters/expressionMapping.test.ts` | 連鎖テスト |
| `src/components/AvatarViewer.tsx` | 純関数呼び出し + 結果適用 |
| `src/App.tsx` | affinity/mood配線 |

**触ってはいけないファイル**: useAnima.ts, expressionMapping.ts（本体）, config.rs, lib.rs, anima/配下, plugin.rs

---

## R5指摘 4件の対処

### (R5-1) HIGH: pulse減衰境界条件 → 分岐を newRemainSec で判定

**問題**: `pulse.remainSec > 0` で分岐し、`newRemainSec` で強度計算すると、`remainSec > 0` かつ `newRemainSec = 0` のフレームで pulse.name が優先される。

**修正**: 分岐条件を `newRemainSec > 0` に変更。

```typescript
// 2. pulse減衰（破壊的更新なし）
const newRemainSec = pulse ? Math.max(0, pulse.remainSec - delta) : 0;

// 4. ブレンド判定 — newRemainSec > 0 で分岐
if (pulse && newRemainSec > 0 && pulse.intensity > 0.1) {
  const pulseT = Math.max(0, newRemainSec / 2.0);
  targetName = pulse.name;
  targetIntensity = pulse.intensity * pulseT;
} else {
  targetName = base.name;
  targetIntensity = base.intensity;
}
```

### (R5-2) HIGH: pulseRef.current === null で実行時例外 → nullチェック追加

**修正**: AvatarViewer側でnullチェックを追加。

```typescript
// AvatarViewer.tsx — useFrame内
const exprResult = computeExpressionFrame({
  affinity: affinity ?? 50,
  mood: mood ?? 0.6,
  t, delta,
  pulse: pulseRef.current,
  prevExprName: lastExprNameRef.current,
  getDisplay: (name: string) => exprDisplayRef.current.get(name) ?? 0,
});

// nullチェック付きで更新
if (pulseRef.current) {
  pulseRef.current.remainSec = exprResult.newRemainSec;
}

for (const update of exprResult.updates) {
  exprDisplayRef.current.set(update.key, update.value);
  pendingExpressions[update.key] = update.value;
}
lastExprNameRef.current = exprResult.targetName;
```

### (R5-3) MEDIUM: prevDisplayの型不一致 → `number | null` に統一

**修正**: 型定義と実装を一致させる。

```typescript
export type ExpressionFrameResult = {
  targetName: string;
  targetIntensity: number;
  currentDisplay: number;
  newDisplay: number;
  prevDisplay: number | null;  // 前表情が存在しない場合はnull
  updates: ExpressionFrameUpdate[];
  events: ExpressionFrameEvent[];
  newRemainSec: number;
};
```

### (R5-4) MEDIUM: 統合回帰テスト不足 → T-18追加

**追加**: `exprOverrides` 優先順序の統合テスト。

| ID | 確認項目 | テスト内容 | 判定基準 |
|----|---------|-----------|---------|
| T-18 | exprOverrides優先 | `computeExpressionFrame` + overrides適用後 | overrides値がupdatesより優先される |

---

## R1/R2/R3/R4指摘 18件の対処（再掲）

### (a) HIGH: context.rsへのemotion注入 → Phase 0 スコープ外に延期
### (b) HIGH: neutral例外条件（intensity>0なら追加）→ `targetName !== "neutral" || targetIntensity > 0`
### (c) MEDIUM: affinityレンジ0-100統一 → clampで保証
### (d) MEDIUM: pulse連続発火→フィールド値比較 → 既に実装済み
### (e) MEDIUM: exprOverrides順序→lerp後に最優先 → 既に実装済み
### (f) LOW: errorRate追跡単位 → Phase 0 では連続値、Phase 1 でイベント単位
### (R2-1) HIGH: pulse.remainSecの破壊的更新 → `newRemainSec` を返す
### (R2-2) HIGH: affinity=50 → neutral の根拠 → 明示済み
### (R2-3) MEDIUM: useMemoの時刻依存更新 → 固定値を useMemo 外で定義
### (R2-4) MEDIUM: jitter非決定性 → 固定tで決定論的検証
### (R3-1) MEDIUM: useMemo内の時刻再評価 → `useMemo(() => new Date().getHours(), [])`
### (R3-2) MEDIUM: 完了条件に主要テストを網羅 → 全テスト項目を反映
### (R3-3) MEDIUM: computeMoodの検証設計強化 → T-4a〜T-4e
### (R3-4) LOW: テストIDの番号対応修正 → 分離済み
### (R4-1) HIGH: computeExpressionFrameの入出力不整合 → 純関数として再設計
### (R4-2) HIGH: T-16の扱い → テストIDと完了条件を分離
### (R4-3) MEDIUM: 境界外入力に対する防御 → clampを追加
### (R4-4) MEDIUM: initialHour固定 → Phase 0の意図を明確化

---

## 設計詳細

### 1. 純関数アーキテクチャ

```
expressionSystem.ts（純関数）
├── computeMood(affinity, hour, elapsed, errorRate, animaState) → number [0-1]
├── affinityToTier(affinity) → AffinityTier
├── computeBaseExpression(affinity, mood) → { name, intensity }
├── computeJitter(t, mood) → number
├── lerpToward(current, target, speed) → number
└── computeExpressionFrame(params) → ExpressionFrameResult
    ├── 入力: affinity, mood, t, delta, pulse, prevExprName, getDisplay
    │   ※ getDisplay: (name: string) => number — Map依存排除
    └── 出力: targetName, targetIntensity, currentDisplay, newDisplay, prevDisplay, updates, events, newRemainSec
```

### 2. computeExpressionFrame の処理フロー

```
1. computeBaseExpression(affinity, mood) → base {name, intensity}
2. newRemainSec = pulse ? Math.max(0, pulse.remainSec - delta) : 0
3. jitter 計算: computeJitter(t, mood)
4. ブレンド判定 — newRemainSec > 0 で分岐:
   - pulseアクティブ (newRemainSec > 0 && pulse.intensity > 0.1) → pulse優先
   -否則 → base使用
5. targetIntensity = clamp(base/pulse intensity + jitter, 0, 1)
6. currentDisplay = getDisplay(targetName)
7. lerp補間: newDisplay = lerpToward(currentDisplay, targetIntensity, 2.0 * delta)
8. 前表情フェードアウト: prevExprName ≠ targetName なら fadedVal 計算
9. updates 配列構築: [{key: targetName, value: newDisplay}, ...prevFadeout]
10. イベント発火: targetName ≠ prevExprName → Phase0Expression
11. フェードアウト完了: prevDisplay < 0.001 → Phase0Fadeout
12. return { targetName, targetIntensity, currentDisplay, newDisplay, prevDisplay, updates, events, newRemainSec }
```

### 3. AvatarViewer 統合

```typescript
// useFrame 内
const exprResult = computeExpressionFrame({
  affinity: affinity ?? 50,
  mood: mood ?? 0.6,
  t, delta,
  pulse: pulseRef.current,
  prevExprName: lastExprNameRef.current,
  getDisplay: (name: string) => exprDisplayRef.current.get(name) ?? 0,
});

// nullチェック付きで更新
if (pulseRef.current) {
  pulseRef.current.remainSec = exprResult.newRemainSec;
}

// 純関数の結果を適用
for (const update of exprResult.updates) {
  exprDisplayRef.current.set(update.key, update.value);
  pendingExpressions[update.key] = update.value;
}
lastExprNameRef.current = exprResult.targetName;

// exprOverrides (lerp後に最優先適用)
if (exprOverrides) {
  for (const [exprName, value] of Object.entries(exprOverrides)) {
    pendingExpressions[exprName] = value;
  }
}
```

### 4. App.tsx 配線

```typescript
import { computeMood } from "./utils/expressionSystem";

// Phase 0: 時刻は固定値（好感度のみで表情変化を検証）
const initialHour = useMemo(() => new Date().getHours(), []);

const computedMood = useMemo(() => {
  return computeMood(
    characterAffinity,
    initialHour,
    0,    // sessionElapsedHours
    0,    // errorRate
    animaState,
  );
}, [characterAffinity, animaState, initialHour]);

<AvatarViewer
  // ...
  affinity={characterAffinity}
  mood={computedMood}
/>
```

---

## テスト設計（pure-function-test-pattern準拠）

### テスト単位一覧

| ID | 確認項目 | テスト内容 | 判定基準 |
|----|---------|-----------|---------|
| T-1 | 好感度→Tier変換 | `affinityToTier` 全6段階 + 全境界値 | 各値→正しいTier名 |
| T-2 | Tier→表情 | `computeBaseExpression` 各Tier×mood高/低 | 正しい expression 名 |
| T-3 | 表情→morph target | T-2出力を `resolveExpression("arkit", name)` | nullでない（neutral=空配列OK） |
| T-4a | mood範囲 | `computeMood` に affinity=0,25,50,75,100 | 全て0-1範囲 |
| T-4b | mood単調性 | affinity=0 < 25 < 50 < 75 < 100 | mood値が単調増加 |
| T-4c | hour影響 | `computeMood`(50, hour=0/6/12/18/23) | 時間帯でmoodが変化 |
| T-4d | errorRate影響 | `computeMood`(50, errorRate=0/0.5/1.0) | errorRate高→mood低 |
| T-4e | elapsed影響 | `computeMood`(50, elapsed=0/1/5) | 経過時間でmoodが変化 |
| T-5 | jitter決定性 | `computeJitter(t=0)`, `computeJitter(t=1)` | 固定tで固定値、sin計算と一致 |
| T-6 | lerp収束 | `lerpToward` 既存テスト | 既存テスト PASS |
| T-7 | 型整合性 | `pnpm tsc --noEmit` | エラー0 |
| T-8 | デフォルト表情 | `computeExpressionFrame`(50,0.6) | targetName="neutral", targetIntensity≈0.6 |
| T-9 | 好感度→表情変化 | `computeExpressionFrame` 各tier | 正しい expression + updates |
| T-10 | イベント発火 | `computeExpressionFrame` events配列 | 表情名変化時のみPhase0Expression発火 |
| T-11 | pulse上書き | `computeExpressionFrame` with pulse | pulseがbaseより優先 |
| T-12 | pulse減衰 | `computeExpressionFrame` pulse減衰後 | baseにフォールバック、newRemainSec検証 |
| T-13 | フェードアウト | `computeExpressionFrame` 前表情減衰 | Phase0Fadeoutイベント発火 |
| T-14 | neutral例外条件 | `computeExpressionFrame` neutral+jitter>0 | updatesに"neutral"が含まれる |
| T-15 | 純関数性 | 同一pulseで2回呼び出しても結果同一 | 破壊的更新なし |
| T-17 | 異常値clamp | `affinityToTier`(-1, 101), `computeMood`(-1, 101) | 範囲内に補正される |
| T-18 | exprOverrides優先 | `computeExpressionFrame` + overrides適用後 | overrides値がupdatesより優先される |

### テストファイル構成

```
src/utils/expressionSystem.test.ts    ← 各純関数の単体テスト（T-1〜T-7, T-4a〜T-4e, T-17）
src/utils/expressionLoop.test.ts      ← computeExpressionFrame 直接テスト（T-8〜T-15, T-18）
src/adapters/expressionMapping.test.ts ← 連鎖テスト（T-3相当）
```

---

## Phase 0 完了条件

### 自動テスト
- [ ] `pnpm test` 全 PASS（T-1〜T-15, T-17, T-18）
- [ ] `pnpm tsc --noEmit` エラー 0（T-7）
- [ ] `affinityToTier` が全6段階で正しいTierを返す（T-1）
- [ ] `computeBaseExpression` が各Tier×moodで正しいexpressionを返す（T-2）
- [ ] 全expression名が `resolveExpression("arkit", name)` で有効なmorph targetに解決（T-3）
- [ ] `computeMood` が0-100範囲で正しく動作、単調増加（T-4a, T-4b）
- [ ] `computeMood` がhour/errorRate/elapsedで正しく変化（T-4c, T-4d, T-4e）
- [ ] jitterが固定tで固定値を返す（T-5）
- [ ] lerp収束テストがPASS（T-6）
- [ ] デフォルト値(50, 0.6)→targetName="neutral", targetIntensity≈0.6（T-8）
- [ ] 各Tierで正しいexpressionがupdatesに反映（T-9）
- [ ] 表情名変化時のみイベント発火（T-10）
- [ ] pulseがbaseより優先（T-11）
- [ ] pulse減衰でbaseにフォールバック、newRemainSecが正しい（T-12）
- [ ] 前表情フェードアウトでPhase0Fadeout発火（T-13）
- [ ] neutral例外条件でupdatesに追加（T-14）
- [ ] 同一pulseで2回呼び出しても結果同一（T-15）
- [ ] 異常値が正常範囲に補正される（T-17）
- [ ] exprOverridesがupdatesより優先される（T-18）

### 手動確認
- [ ] App.tsxからAvatarViewerに `affinity`/`mood` が渡されている
- [ ] AvatarViewer.tsxの変更が純関数呼び出し+結果適用のみ（テスト用コードなし）
- [ ] useAnima.ts を変更していない
- [ ] anima/ 配下のファイルを変更していない

## Phase 1 予定（本設計書スコープ外）

- context.rs への emotion 注入（R1-a）
- errorRate の state遷移イベント単位集計（R1-f）
- `[ANIMA:...]` マーカー → pulse 変換
- 時刻によるmood変化の追跡（R2-3）
