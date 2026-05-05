# テスト設計パターン — 純関数抽出テスト

## 概要

React コンポーネント（useFrame, useEffect 等）の内部ロジックをテストする際、コンポーネントの「再実装」や「デバッグログ埋め込み」を避け、**本番コードそのものをテストする**パターン。

## 原則

1. **ソースを汚さない** — テストのために console.debug, emitDebug 等を処理ソースに埋め込まない
2. **再実装しない** — テスト用にロジックを書き直さない（本番コードと同じバグを共有するリスク）
3. **純関数として抽出** — コンポーネント内のロジックを純関数に切り出し、テストから直接呼ぶ

## パターン構造

### Before（悪い例）

```
┌─ Component.tsx ──────────────────┐
│  useFrame(() => {                │
│    // 50行の計算ロジック直書き   │
│    console.debug("...");  ← 汚染 │
│  })                              │
└──────────────────────────────────┘

┌─ component.test.ts ──────────────┐
│  function simulate() {           │
│    // 50行のロジック再実装 ← 危険 │
│  }                               │
└──────────────────────────────────┘
```

### After（このパターン）

```
┌─ logic.ts （純関数）─────────────┐
│  export function computeFrame(   │
│    input                         │
│  ): { result, events[] }         │  ← 本番コード
└──────────────────────────────────┘

┌─ Component.tsx ──────────────────┐
│  useFrame(() => {                │
│    const r = computeFrame(...)   │  ← 呼ぶだけ
│    apply(r.result)               │
│  })                              │
└──────────────────────────────────┘

┌─ logic.test.ts ──────────────────┐
│  const r = computeFrame(...)     │  ← 同じ関数を直接テスト
│  expect(r.result).toBe(...)      │
│  expect(r.events).toContain(...) │
└──────────────────────────────────┘
```

## 手順

### Step 1: 抽出対象の特定

コンポーネント内で以下の条件を満たすコードブロックを探す:

- フレームワーク API（useFrame, useEffect, event handler）の中に計算ロジックがある
- ロジックが外部状態（DOM, Three.js scene, WebGL）に依存しない、または依存を引数で注入できる
- テストしたい分岐・条件判定が含まれている

### Step 2: 純関数の設計

```typescript
// 入力: コンポーネントの state/ref/props から必要なものだけ
// 出力: 計算結果 + イベント（副作用なし）
export function computeXxx(params: {
  // コンポーネントの state/ref 相当
  prevState: State;
  // props 相当
  config: Config;
  // フレーム情報
  t: number;
  delta: number;
}): {
  // 計算結果（コンポーネントが適用する）
  nextState: State;
  // 副作用の記述（コンポーネントが実行する）
  sideEffects: Record<string, unknown>;
  // テスト用観測点（コンポーネントは無視してよい）
  events: { channel: string; data: Record<string, unknown> }[];
}
```

**設計のポイント**:
- 副作用は戻り値として記述し、コンポーネント側で実行する
- events はテスト用の観測点。コンポーネントは使わなくてよい
- displayMap のような可変データは引数で渡して関数内で更新してよい（パフォーマンス優先）

### Step 3: コンポーネントの書き換え

```typescript
// Before: 50行のロジック
useFrame((_, delta) => {
  const base = computeBase(...);
  const jitter = computeJitter(...);
  // ... 50行 ...
  mesh.morphTargetInfluences[i] = value;
});

// After: 関数呼び出し + 結果適用
useFrame(({ clock }, delta) => {
  const result = computeXxx({
    prevState: stateRef.current,
    config: props,
    t: clock.elapsedTime,
    delta,
  });
  stateRef.current = result.nextState;
  applyToMesh(result.sideEffects);  // Three.js 操作はここだけ
});
```

### Step 4: テスト作成

```typescript
import { computeXxx } from "./logic";

describe("computeXxx", () => {
  it("基本ケース", () => {
    const result = computeXxx({
      prevState: initialState(),
      config: defaultConfig(),
      t: 0,
      delta: 1 / 60,
    });
    expect(result.nextState.value).toBe("expected");
  });

  it("状態遷移イベント", () => {
    const r1 = computeXxx({ ... });
    const r2 = computeXxx({ prevState: r1.nextState, ... });
    // events でイベント発火を検証
    expect(r2.events).toContainEqual({
      channel: "StateChange",
      data: { from: "a", to: "b" },
    });
  });

  it("連続フレームシミュレーション", () => {
    let state = initialState();
    for (let i = 0; i < 60; i++) {
      const r = computeXxx({ prevState: state, t: i / 60, delta: 1 / 60, ... });
      state = r.nextState;
    }
    // 60フレーム後の状態を検証
    expect(state.converged).toBe(true);
  });
});
```

## vi.spyOn との使い分け

| 確認したいこと | 手法 | ソース変更 |
|--------------|------|-----------|
| 純関数の入出力（引数→戻り値） | `vi.spyOn` で呼び出し引数を監視 | なし |
| コンポーネント内部の状態遷移タイミング | 純関数抽出 → events 配列で返す | 抽出のみ（テスト用コード埋め込みなし） |
| DOM / Three.js への適用結果 | E2E テスト or スナップショット | なし |

**判断基準**: 外から `vi.spyOn` で取れるものは取る。取れないもの（ref 比較、閾値判定、内部状態遷移）だけ純関数抽出で対応する。

## 実績: 表情ループテスト

### 抽出前
- AvatarViewer.tsx の useFrame 内に56行の表情計算ロジック
- テストでは `simulateExpressionFrame` として再実装 → 本番コードと乖離するリスク
- debugBus (emitDebug/onDebug) を AvatarViewer に埋め込み → ソース汚染

### 抽出後
- `computeExpressionFrame` を `expressionSystem.ts` に追加（純関数、90行）
- AvatarViewer は呼び出し + 結果適用のみ（8行）
- テストは `computeExpressionFrame` を直接呼び出し（10件）
- AvatarViewer にテスト用コードゼロ。debugBus 削除済み

### ファイル構成

```
src/utils/expressionSystem.ts     ← 純関数（本番コード）
src/utils/expressionLoop.test.ts  ← 純関数の直接テスト
src/components/AvatarViewer.tsx   ← 呼び出し + 適用のみ（テスト用コードなし）
```

## 適用候補（Oribis 内）

| コンポーネント | 抽出候補のロジック | 複雑度 |
|--------------|------------------|--------|
| AvatarViewer | Nod/shake motion overlay | 低 |
| AvatarViewer | Blink タイミング計算 | 低 |
| AvatarViewer | LookAt 補間計算 | 中 |
| App.tsx | セッション管理ステートマシン | 高 |

## チェックリスト

新しいテストを追加する際の確認事項:

- [ ] テスト対象のロジックは純関数として抽出されているか
- [ ] テストはロジックを「再実装」していないか（本番コードを直接呼んでいるか）
- [ ] コンポーネントにテスト用コード（console.debug, emitDebug 等）が残っていないか
- [ ] events 配列で内部状態遷移を検証できているか
- [ ] vi.spyOn で取れる情報を無駄に events に含めていないか
