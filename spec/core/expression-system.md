# 表情反映システム設計書

**ステータス**: 設計確定・実装待ち
**バージョン**: 1.0
**対象**: Anima Anima表情制御

---

## 1. 概要

アバターの表情を「好感度（affinity）」「機嫌（mood）」「ANIMAイベント」の3軸で駆動し、
人間らしい自然な揺らぎと滑らかな遷移を実現する。

### 設計原則

- §23（nagiko-spec.md）遵守: 機嫌・疲労等の細分化パラメータを**バックエンドで永続化しない**
- mood はフロントエンド揮発値（セッション内のみ、Rust 側不要）
- §23 が拒否するのは「AI の人格を細分化パラメータで管理すること」。
  フロントエンドのレンダリング変数として使う分は適用外

---

## 2. アーキテクチャ概観

```
[Rust pipeline]
  anima_control {expression, intensity, motion, gaze}
       ↓
[useAnima.ts]
  onAvatarCommand(cmd) → avatarCommand state
       ↓
[AvatarViewer.tsx / useFrame() 30fps]
  ┌────────────────────────────────────────┐
  │  base = f(affinity, mood)              │  ← Phase 0 追加
  │  pulse = decay(anima_event)            │  ← Phase 0 追加
  │  jitter = noise(±0.03)                 │  ← Phase 0 追加
  │  target = blend(base, pulse, jitter)   │  ← Phase 0 追加
  │  display = lerp(display, target, 0.05) │  ← Phase 0 追加（lerpToward）
  │       ↓                                │
  │  av.setExpression(name, display)       │  ← 既存
  └────────────────────────────────────────┘
       ↓
[MmdAvatarAdapter.ts]
  morphTargetInfluences[idx] = value
```

---

## 3. mood（機嫌）計算仕様

### 定義

`mood` = 揮発性浮動小数 [0.0 - 1.0]。0.0=不調、1.0=良調。
セッション内のみ存在。ページリロードでリセット。

### 入力シグナル（フロントエンドで取得可能な値）

| シグナル | 取得元 | 影響 |
|----------|--------|------|
| `affinity` | Rust→State（既存） | 高いほど mood UP |
| `hour_of_day` | `new Date().getHours()` | 早朝（5-9h）UP、深夜（0-4h）DOWN |
| `session_elapsed_ms` | セッション開始からの経過 | 長すぎると（>4h）DOWN |
| `error_rate` | 直近10メッセージのエラー割合 | 高いほど DOWN |
| `anima_state` | `useAnima` の `animaState` | `error`/`lewd` → DOWN |

### 計算式

```typescript
function computeMood(
  affinity: number,         // -100 ~ +100
  hourOfDay: number,        // 0 ~ 23
  sessionElapsedHours: number,
  errorRate: number,        // 0.0 ~ 1.0
  animaState: AnimaState,
): number {
  // affinity (-100~+100) → 0~1
  const affinityFactor = (affinity + 100) / 200;

  // time-of-day: early morning boost, late night penalty
  const hourFactor = (() => {
    if (hourOfDay >= 5 && hourOfDay <= 9) return 1.0;   // 早朝
    if (hourOfDay >= 10 && hourOfDay <= 18) return 0.8; // 日中
    if (hourOfDay >= 19 && hourOfDay <= 22) return 0.65; // 夜
    return 0.45; // 深夜
  })();

  // fatigue: 4時間超で線形低下、8時間で0.5まで
  const fatigueFactor = Math.max(0.5, 1.0 - Math.max(0, sessionElapsedHours - 4) * 0.083);

  // error penalty
  const errorFactor = 1.0 - errorRate * 0.4;

  // anima state modifier
  const animaMod = (animaState === "error" || animaState === "lewd") ? -0.15 : 0;

  const raw = affinityFactor * 0.5
    + hourFactor * 0.2
    + fatigueFactor * 0.15
    + errorFactor * 0.15
    + animaMod;

  return Math.max(0, Math.min(1, raw));
}
```

---

## 4. base expression 計算仕様

好感度 + 機嫌 → ベース表情マッピング。

```typescript
function computeBaseExpression(
  affinity: number,   // -100 ~ +100
  mood: number,       // 0 ~ 1
): { name: string; intensity: number } {
  // 高好感度 + 良機嫌 → happy
  if (affinity >= 50 && mood >= 0.7) {
    return { name: "happy", intensity: 0.25 + mood * 0.2 };
  }
  // 低好感度 or 不調 → sad（軽微）
  if (affinity <= -30 || mood <= 0.3) {
    return { name: "sad", intensity: 0.15 + (1 - mood) * 0.15 };
  }
  // 標準 → neutral（わずかにrelaxed寄り）
  if (mood >= 0.6) {
    return { name: "relaxed", intensity: 0.1 + mood * 0.1 };
  }
  return { name: "neutral", intensity: 0 };
}
```

---

## 5. pulse（ANIMAイベントパルス）仕様

`avatarCommand` が変化した瞬間、intensity をパルスとして注入し時間減衰させる。

```typescript
// useFrame 内の状態（ref）
// pulseRef: { name: string; intensity: number; remainSec: number }

// avatarCommand 変化検出時
if (avatarCommand !== lastCommandRef.current) {
  pulseRef.current = {
    name: avatarCommand.expression,
    intensity: avatarCommand.intensity,
    remainSec: 2.0, // 2秒かけて減衰
  };
  lastCommandRef.current = avatarCommand;
}

// useFrame 内で毎フレーム減衰
if (pulseRef.current && pulseRef.current.remainSec > 0) {
  pulseRef.current.remainSec -= delta;
  const pulseIntensity = pulseRef.current.intensity
    * Math.max(0, pulseRef.current.remainSec / 2.0); // 線形減衰
}
```

---

## 6. jitter（揺らぎ）仕様

機械的な硬直感を破る小さなノイズ。

```typescript
// 低周波ノイズ（sin合成で擬似ランダム）
const jitter = Math.sin(t * 0.7 + 1.3) * Math.sin(t * 1.1 + 0.5) * 0.03;
// mood が高いほど jitter は小さく（安定）、低いほど大きく（不安定）
const jitterScale = 1.0 + (1.0 - mood) * 0.5;
const effectiveJitter = jitter * jitterScale;
```

---

## 7. ブレンド & lerp 仕様

### ブレンド

```typescript
// 優先度: pulse > base
// pulse が十分強い場合は pulse 優先
const pulse = pulseRef.current;
let targetName: string;
let targetIntensity: number;

if (pulse && pulse.remainSec > 0 && pulse.intensity > 0.1) {
  const t = Math.max(0, pulse.remainSec / 2.0);
  targetName = pulse.name;
  targetIntensity = pulse.intensity * t;
} else {
  targetName = base.name;
  targetIntensity = base.intensity;
}
targetIntensity = Math.max(0, Math.min(1, targetIntensity + effectiveJitter));
```

### inertia（慣性）

```typescript
// useFrame 内の ref
// exprDisplayRef: Map<string, number>  // 現在表示値
// EXPR_LERP_SPEED = 2.0  // bones の BLEND_SPEED=3.0 より遅く（表情は緩やか）

const currentDisplay = exprDisplayRef.current.get(targetName) ?? 0;
const newDisplay = lerpToward(currentDisplay, targetIntensity, EXPR_LERP_SPEED * delta);
exprDisplayRef.current.set(targetName, newDisplay);

// 前の表情をクリア（lerp でフェードアウト）
if (lastExprNameRef.current && lastExprNameRef.current !== targetName) {
  const prevVal = exprDisplayRef.current.get(lastExprNameRef.current) ?? 0;
  exprDisplayRef.current.set(
    lastExprNameRef.current,
    lerpToward(prevVal, 0, EXPR_LERP_SPEED * delta),
  );
}
```

`lerpToward()` は既存の `AvatarViewer.tsx:153` の実装を使用。

---

## 8. 実装場所

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/components/AvatarViewer.tsx` | メイン実装場所 |
| `src/App.tsx` | `mood` 計算・`affinity` / `animaState` → `AvatarViewer` 渡し |

### AvatarViewer.tsx への変更

**追加 refs（`AvatarModelComponent` 内）:**
```typescript
const exprDisplayRef = useRef<Map<string, number>>(new Map());
const pulseRef = useRef<{ name: string; intensity: number; remainSec: number } | null>(null);
```

**Props 追加:**
```typescript
interface AvatarModelProps {
  // 既存 ...
  affinity?: number;        // -100 ~ +100
  mood?: number;            // 0 ~ 1 (computed by App.tsx)
  animaState?: AnimaState;  // 既存 useAnima 状態
}
```

**useFrame 内の expression セクション（line 450-503）を置き換え:**
blink・aa（音声同期）は既存のまま維持し、Anima表情部分だけ差し替え。

### App.tsx への変更

mood 計算を `useMemo` で導出:
```typescript
const mood = useMemo(() => computeMood(
  characterAffinity,
  new Date().getHours(),
  sessionElapsedHours,  // セッション開始時刻から計算
  errorRate,            // 直近エラー/総メッセージ比
  animaState,
), [characterAffinity, currentHour, sessionElapsedHours, errorRate, animaState]);
```

---

## 9. 表情名マッピング（MMD対応確認済み）

`expressionMapping.ts` の `MMD_EXPRESSION_MAP`:

| VRM名 | MMD モーフ名 | 本システムでの用途 |
|-------|------------|----------------|
| `happy` | 笑い | 高好感度・良機嫌 |
| `sad` | 困る | 低好感度・不調・エラー |
| `angry` | 怒り | lewd状態（高ペナルティ） |
| `surprised` | 驚き | ANIMAパルス（surprised） |
| `relaxed` | なごみ | 標準・良機嫌 |
| `neutral` | null（skip） | デフォルト |

---

## 10. Phase 実装計画

### Phase 0（本ドキュメント対象）

フロントエンドのみ。Rust 変更なし。

- [x] 設計確定
- [ ] `computeMood()` 実装（App.tsx または hooks/useMood.ts）
- [ ] `computeBaseExpression()` 実装（AvatarViewer.tsx または独立ファイル）
- [ ] `exprDisplayRef` + lerp ループ（AvatarViewer.tsx useFrame 内）
- [ ] pulse 減衰ロジック
- [ ] jitter ノイズ追加
- [ ] Props 追加（affinity, mood, animaState → AvatarModelComponent）

### Phase 1（MemoryFix 実装後）

MemoryFix.txt の `AnimaMode::Ai` 移行完了後:
- mood 計算に counter データ（ツール呼び出し回数等）を追加
- セッションジャーナルの感情傾向を L3 コンテキストに注入

### Phase 2（将来）

LLM が `[ANIMA:...]` マーカーで直接 intensity を指定する際、
mood を考慮した intensity スケーリングを行う。
（例: mood 低い時は happy intensity を 0.7倍に）

---

## 11. §23 準拠確認

nagiko-spec.md §23「不採用要素」との整合:

> 「機嫌・疲労・興味・警戒等の細分化パラメータ」は不採用

本設計の `mood` は:
- ✅ **バックエンド永続化なし**（フロントエンドのみ）
- ✅ **AI人格への影響なし**（レンダリング変数のみ、LLMへの入力に使わない Phase 0）
- ✅ **業務品質への影響なし**（表情装飾のみ）
- ✅ **§23 が拒否した「AI人格の細分化管理」ではない**（視覚効果）

Phase 2 以降で L3 注入を行う場合は §23 との整合を再確認すること。

---

## 12. テスト方針

| テスト | 方法 |
|--------|------|
| computeMood() 単体 | vitest で各シグナル境界値テスト |
| computeBaseExpression() 単体 | vitest で affinity×mood マトリクス |
| lerp 収束確認 | 手動: avatarCommand を変更して数秒後に収束するか目視 |
| 既存表情テスト不変 | `MmdAvatarAdapter.test.ts` / `expressionMapping.test.ts` PASS 確認 |

---

*作成日: 2026-04-28 | 対象フェーズ: Phase 0*
