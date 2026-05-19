# Lumina — 幾何学アバター設計書

**ステータス**: 設計確定・実装待ち
**バージョン**: 1.1（Codex Adviser指摘反映）
**作成日**: 2026-05-16

---

## 1. 概要

Lumina = Oribisアイコン（縦リング＋水平リング）を3D化した幾何学アバター。
光のアーチ（線）とアーチ上を移動する光の粒子で構成。
VRMアバターとの切替式（設定で選択）。

### 設計原則

- **Animaステート連動**: `AnimaState` + `affinity` + `mood` を入力。VRM側と同一入力。二重管理なし
- **スクリプトファースト**: 全変形パラメータはフロントエンド計算。LLM不要
- **GPU最小負荷**: Line2 + Points。頂点数200以下。VRM（数万頂点）と比較して誤差レベル
- **キャラ名禁止**: コード内で「Lumina」は型名・コンポーネント名としてのみ使用。人格名としてハードコードしない

---

## 2. 技術スタック

| 要素 | 技術 | 理由 |
|------|------|------|
| 光のアーチ（線） | `Line2`（`three/addons/lines`） | 太さ可変・アンチエイリアス。WebGL linewidth制限回避 |
| 光の粒子 | `Points` + `ShaderMaterial` | GPU完結でpath沿い移動。CPU負荷ゼロ |
| 発光 | `AdditiveBlending` | 線重なりで自然発光。ポストプロセス不要（Phase 1で`UnrealBloomPass`追加検討） |
| 中心核 | `Points`（1点） + `ShaderMaterial` | 脈動・発光制御 |

### 不採用技術

| 技術 | 不採用理由 |
|------|-----------|
| `THREE.LineBasicMaterial` | WebGL制限で線幅1px固定。見栄え不足 |
| `THREE.EdgesGeometry` | 面付きジオメトリの辺抽出用。リング生成には不適 |
| `MeshLine` | 外部ライブラリ依存。Line2で十分 |
| `UnrealBloomPass` | Phase 1検討。Phase 0ではAdditiveBlendingのみで軽量維持 |

---

## 3. 基本形態

Oribisアイコン準拠: **縦リング（メイン）＋ 水平リング（サブ）**の2本構成。

```
       ╭───╮
      ╱     ╲
     ║       ║    ← リングA（縦・メインリング / 大）
   ──╫───●───╫──  ← リングB（水平・サブリング / 小）
     ║       ║        ● = 中心核（光点）
      ╲     ╱
       ╰───╯
```

### リング生成

```typescript
// リングA（縦）: XZ平面に円を描き、Y軸回転で縦にする
function createRingGeometry(radius: number, segments: number = 64): Float32Array {
  const points: number[] = [];
  for (let i = 0; i <= segments; i++) {
    const theta = (i / segments) * Math.PI * 2;
    points.push(Math.cos(theta) * radius, Math.sin(theta) * radius, 0);
  }
  return new Float32Array(points);
}

// リングA: radius=1.0, rotateZ(0)   → 縦
// リングB: radius=1.3, rotateX(π/2) → 水平
```

### パーティクル

各リングの円周上を等間隔で移動する光の粒子。ShaderMaterialのuniform `uTime` で制御。

```glsl
// パーティクル vertex shader
uniform float uTime;
uniform float uSpeed;      // 周回速度
uniform float uRingRadius; // リング半径
attribute float aPhase;     // 各粒子の位相オフセット [0, 2π)

void main() {
  float theta = uTime * uSpeed + aPhase;
  vec3 pos = vec3(cos(theta) * uRingRadius, sin(theta) * uRingRadius, 0.0);

  vec4 mvPosition = modelViewMatrix * vec4(pos, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  gl_PointSize = 6.0 * (300.0 / -mvPosition.z); // 距離減衰
}
```

```glsl
// パーティクル fragment shader
uniform vec3 uColor;
void main() {
  float d = length(gl_PointCoord - vec2(0.5));
  if (d > 0.5) discard;
  float alpha = smoothstep(0.5, 0.1, d); // 中心が明るいグロー
  gl_FragColor = vec4(uColor, alpha);
}
```

### 中心核

```typescript
// 1点のPoints。脈動はuniform制御
const coreGeometry = new THREE.BufferGeometry();
coreGeometry.setAttribute('position', new THREE.Float32BufferAttribute([0, 0, 0], 3));

const coreMaterial = new THREE.ShaderMaterial({
  uniforms: {
    uTime: { value: 0 },
    uColor: { value: new THREE.Color(0x00e5ff) },
    uBaseSize: { value: 12.0 },
    uPulseAmp: { value: 0.3 },  // 脈動振幅
    uPulsePeriod: { value: 4.0 }, // 秒
  },
  vertexShader: `
    uniform float uTime;
    uniform float uBaseSize;
    uniform float uPulseAmp;
    uniform float uPulsePeriod;
    void main() {
      vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
      float pulse = 1.0 + sin(uTime * 6.2832 / uPulsePeriod) * uPulseAmp;
      gl_PointSize = uBaseSize * pulse * (300.0 / -mvPosition.z);
      gl_Position = projectionMatrix * mvPosition;
    }
  `,
  fragmentShader: `
    uniform vec3 uColor;
    void main() {
      float d = length(gl_PointCoord - vec2(0.5));
      if (d > 0.5) discard;
      float alpha = smoothstep(0.5, 0.0, d);
      gl_FragColor = vec4(uColor, alpha * 0.9);
    }
  `,
  transparent: true,
  blending: THREE.AdditiveBlending,
  depthWrite: false,
});
```

---

## 4. AnimaState → Lumina マッピング

全ステートのパラメータ。遷移はlerp（`LUMINA_LERP_SPEED = 3.0`）で滑らかに補間。

### 4.0 マッピング中間層（Codex指摘対応）

AnimaState → RenderParameters の直結を避け、中間層 `LuminaExpressionModel` を挿入。
AnimaState定義変更や表情システム変更時の影響を描画実装から隔離する。

```
AnimaState + affinity + mood
       ↓ (1) 状態解釈
LuminaExpressionModel { energy, stability, activity, emotion }
       ↓ (2) パラメータ変換
LuminaParams { ringA_radius, rotationSpeedA, color, ... }
       ↓ (3) レンダリング
Three.js uniforms / attributes
```

```typescript
// 中間層: 抽象的な表現モデル
interface LuminaExpressionModel {
  energy: number;     // 0~1。エネルギー量（半径・明度に影響）
  stability: number;  // 0~1。安定性（破線・振動に影響）。0=不安定
  activity: number;   // 0~1。活動度（回転速度・パーティクル速度に影響）
  emotion: LuminaEmotion; // 色決定
}

type LuminaEmotion = 'neutral' | 'positive' | 'negative' | 'alert' | 'reject' | 'dormant';

// (1) AnimaState → LuminaExpressionModel
function resolveExpression(
  animaState: AnimaState,
  affinity: number,
  mood: number,
): LuminaExpressionModel {
  const base = STATE_EXPRESSION_MAP[animaState];
  return {
    energy: clamp01(base.energy + affinityToEnergy(affinity) + moodToEnergy(mood)),
    stability: clamp01(base.stability + moodToStability(mood)),
    activity: clamp01(base.activity + moodToActivity(mood)),
    emotion: base.emotion,
  };
}

// (2) LuminaExpressionModel → LuminaParams
function expressionToParams(expr: LuminaExpressionModel): LuminaParams {
  return {
    ringA_radius: 0.3 + expr.energy * 1.7,          // 0.3 ~ 2.0
    rotationSpeedA: expr.activity * 0.8,              // 0 ~ 0.8
    dashArray: expr.stability < 0.3,
    jitterAmount: Math.max(0, (0.3 - expr.stability) * 0.15),
    color: EMOTION_COLOR_MAP[expr.emotion],
    // ... 他パラメータ
  };
}

const STATE_EXPRESSION_MAP: Record<AnimaState, LuminaExpressionModel> = {
  idle:      { energy: 0.5, stability: 1.0, activity: 0.25, emotion: 'neutral' },
  working:   { energy: 0.7, stability: 0.9, activity: 0.75, emotion: 'neutral' },
  done:      { energy: 0.9, stability: 1.0, activity: 0.8,  emotion: 'positive' },
  error:     { energy: 0.5, stability: 0.2, activity: 0.4,  emotion: 'alert' },
  greeting:  { energy: 0.6, stability: 1.0, activity: 0.4,  emotion: 'positive' },
  idle_long: { energy: 0.2, stability: 1.0, activity: 0.05, emotion: 'dormant' },
  resume:    { energy: 0.3, stability: 0.8, activity: 0.2,  emotion: 'neutral' },
  lewd:      { energy: 0.1, stability: 0.7, activity: 0.0,  emotion: 'reject' },
};

const EMOTION_COLOR_MAP: Record<LuminaEmotion, THREE.Color> = {
  neutral:  new THREE.Color(0x00e5ff),  // シアン
  positive: new THREE.Color(0xffd54f),  // ゴールド
  negative: new THREE.Color(0x90a4ae),  // グレー
  alert:    new THREE.Color(0xff1744),  // 赤
  reject:   new THREE.Color(0x4a148c),  // 暗紫
  dormant:  new THREE.Color(0x004d40),  // 暗シアン
};
```

### パラメータ定義

```typescript
interface LuminaParams {
  ringA_radius: number;       // リングA半径
  ringB_radius: number;       // リングB半径
  ringB_tilt: number;         // リングB傾斜角（rad）。π/2=水平
  rotationSpeedA: number;     // リングA Y軸回転速度（rad/s）
  rotationSpeedB: number;     // リングB 回転速度（rad/s）
  particleCount: number;      // リングあたりパーティクル数
  particleSpeed: number;      // パーティクル周回速度（rad/s）
  particleTrail: boolean;     // 軌跡表示
  breathAmplitude: number;    // 呼吸膨張振幅
  breathPeriod: number;       // 呼吸周期（秒）
  dashArray: boolean;         // 破線化
  jitterAmount: number;       // 振動量
  color: THREE.Color;         // メイン色
  opacity: number;            // 全体透明度
  coreSize: number;           // 中心核サイズ
  corePulseAmp: number;       // 中心核脈動振幅
  corePulsePeriod: number;    // 中心核脈動周期（秒）
}
```

### ステート別パラメータ

| パラメータ | idle | working | done(peak) | done(end) | error | greeting(start) | greeting(end) | idle_long | resume | lewd |
|-----------|------|---------|------------|-----------|-------|-----------------|---------------|-----------|--------|------|
| ringA_radius | 1.0 | 1.3 | 2.0→0.8 | 1.0 | 1.0 | 0.0 | 1.0 | 0.5 | 0.5→1.0 | 0.3 |
| ringB_radius | 1.3 | 1.5 | 2.5→1.0 | 1.3 | 1.3 | 0.0 | 1.3 | 0.7 | 0.7→1.3 | 0.4 |
| ringB_tilt | π/2 | π/2+0.5 | π/2 | π/2 | π/2±揺れ | π/2 | π/2 | π/2 | π/2 | π/2 |
| rotationSpeedA | 0.2 | 0.6 | 0.8→0.2 | 0.2 | 不規則 | 0.0→0.2 | 0.2 | 0.05 | 0.05→0.2 | 0.0 |
| rotationSpeedB | 0.1 | 0.4 | 0.6→0.1 | 0.1 | 不規則 | 0.0→0.1 | 0.1 | 0.02 | 0.02→0.1 | 0.0 |
| particleCount | 2 | 4 | 4→0 | 2 | 2 | 0→2 | 2 | 1 | 0→2 | 0 |
| particleSpeed | 0.8 | 3.0 | 4.0→0.8 | 0.8 | 不規則 | 0→0.8 | 0.8 | 0.2 | 0.2→0.8 | 0.0 |
| particleTrail | false | true | true | false | false | true | false | false | false | false |
| breathAmplitude | 0.05 | 0.0 | 0.0 | 0.05 | 0.0 | 0.0 | 0.05 | 0.03 | 0.03→0.05 | 0.0 |
| breathPeriod | 4.0 | — | — | 4.0 | — | — | 4.0 | 8.0 | 8.0→4.0 | — |
| dashArray | false | false | false | false | true | false | false | false | false | false |
| jitterAmount | 0.0 | 0.0 | 0.0 | 0.0 | 0.05 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| color | #00e5ff | #b3e5fc | #ffd54f→#00e5ff | #00e5ff | #ff1744 | #ffab40→#00e5ff | #00e5ff | #004d40 | #004d40→#00e5ff | #4a148c |
| opacity | 0.8 | 0.9 | 1.0→0.8 | 0.8 | 0.7 | 0.0→0.8 | 0.8 | 0.3 | 0.3→0.8 | 0.5 |
| coreSize | 12 | 16 | 24→12 | 12 | 12 | 0→12 | 12 | 8 | 8→12 | 6 |
| corePulseAmp | 0.3 | 0.5 | 0.8→0.3 | 0.3 | 点滅 | 0→0.3 | 0.3 | 0.1 | 0.1→0.3 | 0.0 |
| corePulsePeriod | 4.0 | 1.0 | 0.5→4.0 | 4.0 | 0.5 | 2.0→4.0 | 4.0 | 10.0 | 10.0→4.0 | — |

### 遷移アニメーション

```typescript
// ステート変更時
function onAnimaStateChange(newState: AnimaState, prevState: AnimaState): void {
  const targetParams = STATE_PARAMS[newState];
  // lerp で現在値 → 目標値を補間（useFrame内）
  // 特殊遷移（done, greeting, resume）はキーフレームシーケンス
}

// 特殊遷移: done
const DONE_KEYFRAMES = [
  { time: 0.0, params: { /* peak: 展開 */ } },
  { time: 0.3, params: { /* 六芒星一致: リングA,B回転軸一致 */ } },
  { time: 1.0, params: { /* 収束 */ } },
  { time: 1.5, params: STATE_PARAMS.idle },
];

// 特殊遷移: greeting
const GREETING_KEYFRAMES = [
  { time: 0.0, params: { ringA_radius: 0, ringB_radius: 0, opacity: 0 } },
  { time: 1.0, params: { ringA_radius: 1.0, opacity: 0.6 } },
  { time: 1.5, params: { ringB_radius: 1.3, opacity: 0.8 } }, // リングB遅延出現
  { time: 2.0, params: STATE_PARAMS.idle },
];

// 特殊遷移: resume
const RESUME_KEYFRAMES = [
  { time: 0.0, params: STATE_PARAMS.idle_long },
  { time: 0.5, params: { rotationSpeedA: 0.2 } }, // リングA先に回転再開
  { time: 1.0, params: { rotationSpeedB: 0.1 } }, // リングB遅延回転再開
  { time: 1.5, params: STATE_PARAMS.idle },
];
```

### error の不規則回転

```typescript
// error ステート: 回転速度をノイズで変調
function errorRotation(time: number): { speedA: number; speedB: number } {
  const noise1 = Math.sin(time * 3.7) * Math.sin(time * 5.3);
  const noise2 = Math.sin(time * 2.1) * Math.sin(time * 4.7);
  return {
    speedA: 0.3 + noise1 * 0.5, // -0.2 ~ 0.8（逆回転含む）
    speedB: 0.2 + noise2 * 0.4,
  };
}
```

---

## 5. affinity 連続変調

`affinity`（-100〜+100）による連続的パラメータ変調。ステートパラメータに乗算。

```typescript
function applyAffinityModulation(params: LuminaParams, affinity: number): LuminaParams {
  // -100~+100 → 0~1
  const t = (affinity + 100) / 200;

  return {
    ...params,
    // リング太さ（Line2 linewidth）
    lineWidth: 1.5 + t * 2.5,           // 1.5 ~ 4.0
    // パーティクル数補正
    particleCount: Math.max(1, Math.round(params.particleCount * (0.5 + t))),
    // 明度補正
    opacity: params.opacity * (0.6 + t * 0.4),
    // 高好感度時: 虹色アクセント
    rainbowAccent: t > 0.85,            // affinity > 70 で有効
    // パーティクル軌跡（高好感度時）
    particleTrail: params.particleTrail || t > 0.85,
  };
}
```

### affinity帯別の視覚効果

| affinity | 線太さ | パーティクル | 明度 | 特殊効果 |
|----------|--------|-------------|------|----------|
| -100〜-30 | 細い（1.5〜2.2） | 少ない | 暗い（×0.6〜0.74） | なし |
| -30〜+30 | 標準（2.2〜3.2） | 標準 | 標準（×0.74〜0.86） | なし |
| +30〜+70 | やや太い（3.2〜3.8） | やや多い | 明るい（×0.86〜0.96） | なし |
| +70〜+100 | 太い（3.8〜4.0） | 多い | 最大（×0.96〜1.0） | 虹色アクセント + 粒子trail |

---

## 6. mood 連続変調

`mood`（0.0〜1.0）による連続的パラメータ変調。

```typescript
function applyMoodModulation(params: LuminaParams, mood: number): LuminaParams {
  return {
    ...params,
    // 回転速度
    rotationSpeedA: params.rotationSpeedA * (0.5 + mood * 0.5),
    rotationSpeedB: params.rotationSpeedB * (0.5 + mood * 0.5),
    // 彩度（HSL操作）
    saturation: 0.3 + mood * 0.7,     // 0.3 ~ 1.0
    // 呼吸振幅
    breathAmplitude: params.breathAmplitude * (0.7 + mood * 0.3),
    // 中心核脈動
    corePulseAmp: params.corePulseAmp * (0.5 + mood * 0.5),
  };
}
```

---

## 6.1 数値安定性規則（Codex指摘対応）

全入力値のnormalize・全出力値のclamp・フォールバック規則。

### 入力バリデーション

```typescript
// 全入力を安全な範囲に正規化
function sanitizeInputs(
  animaState: AnimaState | undefined | null,
  affinity: number | undefined | null,
  mood: number | undefined | null,
): { state: AnimaState; affinity: number; mood: number } {
  return {
    state: animaState ?? 'idle',                           // null/undefined → idle
    affinity: clamp(-100, 100, affinity ?? 0),             // NaN/null → 0
    mood: clamp(0, 1, Number.isFinite(mood) ? mood! : 0.5), // NaN → 0.5
  };
}

function clamp(min: number, max: number, v: number): number {
  return Math.max(min, Math.min(max, Number.isFinite(v) ? v : (min + max) / 2));
}

function clamp01(v: number): number {
  return clamp(0, 1, v);
}
```

### 出力クランプ

```typescript
// LuminaParams の全数値フィールドをクランプ
function clampParams(p: LuminaParams): LuminaParams {
  return {
    ...p,
    ringA_radius: clamp(0, 3.0, p.ringA_radius),
    ringB_radius: clamp(0, 4.0, p.ringB_radius),
    ringB_tilt: clamp(0, Math.PI, p.ringB_tilt),
    rotationSpeedA: clamp(-1.0, 1.0, p.rotationSpeedA),
    rotationSpeedB: clamp(-1.0, 1.0, p.rotationSpeedB),
    particleCount: clamp(0, 8, Math.round(p.particleCount)),
    particleSpeed: clamp(0, 5.0, p.particleSpeed),
    breathAmplitude: clamp(0, 0.2, p.breathAmplitude),
    opacity: clamp(0, 1, p.opacity),
    coreSize: clamp(0, 30, p.coreSize),
    corePulseAmp: clamp(0, 1, p.corePulseAmp),
  };
}
```

### 遷移スムージング

- 全パラメータ変化は `lerpToward()` 経由（急変防止）
- affinity は長期変化（低周波）→ `AFFINITY_LERP_SPEED = 0.5`
- mood は中期変化 → `MOOD_LERP_SPEED = 1.0`
- animaState は短期変化 → `STATE_LERP_SPEED = 3.0`
- 加算合成の白飛び防止: opacity最大値を0.95にクランプ

---

## 7. アーキテクチャ統合

### 7.1 AvatarRenderer 共通インターフェース（Codex指摘対応）

VRMとLuminaを「AvatarRendererの異なる実装」として扱う。
VRM固有の表情名・ボーン・blendshapeが上位層に漏れない設計。

```typescript
// 共通インターフェース
interface AvatarRenderer {
  load(): Promise<void>;
  unload(): void;
  updateAnimaState(state: AnimaState): void;
  updateExpression(affinity: number, mood: number): void;
  update(delta: number): void;
  dispose(): void;  // GPU resource完全解放
}

// 実装
class VrmAvatarRenderer implements AvatarRenderer { /* 既存VRM */ }
class LuminaAvatarRenderer implements AvatarRenderer { /* 新規 */ }
```

上位層（App.tsx）は `AvatarRenderer` を通じてのみアバターと対話。
型固有のプロパティ（VRMのblendshape、LuminaのringA_radius等）は各実装内に隠蔽。

### 7.2 データフロー

```
[Rust pipeline]
  anima_control {expression, intensity, motion, gaze}
       ↓
[useAnima.ts]
  animaState + avatarCommand
       ↓ ←── affinity（Rust→State）
       ↓ ←── mood（computeMood()）
       ↓
[AvatarRenderer interface]
  .updateAnimaState(state)
  .updateExpression(affinity, mood)
  .update(delta)
       ↓
┌──────────────────────────────────────────────┐
│ avatarType === 'lumina'                      │
│   ? <LuminaRenderer />  (LuminaAvatarRenderer) │
│   : <AvatarViewer />    (VrmAvatarRenderer)     │
└──────────────────────────────────────────────┘
```

### 7.3 コンポーネント構成

| ファイル | 役割 |
|---------|------|
| `src/components/LuminaRenderer.tsx` | メインコンポーネント。Three.js Canvas + useFrame |
| `src/components/lumina/LuminaRing.ts` | リング生成・Line2管理 |
| `src/components/lumina/LuminaParticles.ts` | パーティクル Points + ShaderMaterial |
| `src/components/lumina/LuminaCore.ts` | 中心核 |
| `src/components/lumina/luminaParams.ts` | STATE_PARAMS定義 + affinity/mood変調関数 |
| `src/components/lumina/luminaShaders.ts` | GLSL shader文字列 |

### Props

```typescript
interface LuminaRendererProps {
  animaState: AnimaState;
  affinity: number;       // -100 ~ +100
  mood: number;           // 0 ~ 1
  width?: number;
  height?: number;
}
```

### 既存コードへの変更

| ファイル | 変更内容 |
|---------|---------|
| `src/App.tsx` | `avatarType` 設定追加。`lumina` 時に `<LuminaRenderer>` 表示 |
| `src/hooks/useAnima.ts` | 変更なし（既存のanimaState/avatarCommandをそのまま使用） |
| 設定UI | アバター種別選択（VRM / Lumina）追加 |

---

## 8. 切替仕様

| 項目 | 仕様 |
|------|------|
| 切替方式 | 設定画面でアバター種別選択（VRM / Lumina） |
| 永続化 | `localStorage` の `avatarType` キー |
| デフォルト | VRM（既存動作維持） |
| 切替時 | フェードアウト → 切替 → フェードイン（0.5秒） |
| 同時表示 | Phase 1検討。Phase 0は排他切替 |

---

## 9. パフォーマンス設計

| 指標 | 目標値 |
|------|--------|
| Draw Call | 4（リング×2 + パーティクル×1 + 核×1） |
| 頂点数 | ~150（リング64×2 + パーティクル~12 + 核1） |
| GPU負荷 | VRMの1%以下 |
| CPU負荷 | useFrame内のlerp計算のみ。行列演算なし |
| メモリ | ジオメトリ~10KB + シェーダー~5KB |

### 9.1 パフォーマンス規則（Codex指摘対応）

| 規則 | 内容 |
|------|------|
| geometry/material生成 | **初期化時のみ**。毎フレーム再生成禁止 |
| 毎フレーム更新 | uniform更新 + 既存buffer範囲更新のみ |
| Line2 resolution | リサイズ・DPR変更時に必ず更新。`window.addEventListener('resize')` で反映 |
| 非表示時 | `avatarType !== 'lumina'` 時は `useFrame` コールバック停止。CPU/GPU消費ゼロ |
| 低スペック縮退 | 設定で調整可能: `particleDensity`(0.5/1.0), `dprCap`(1/2), bloom(on/off) |
| overdraw警戒 | AdditiveBlending + 半透明の重なり面積を最小化。リング太さ上限4.0px |

### 9.2 リソースライフサイクル（Codex指摘対応）

```typescript
class LuminaAvatarRenderer implements AvatarRenderer {
  private ringA: Line2 | null = null;
  private ringB: Line2 | null = null;
  private particles: THREE.Points | null = null;
  private core: THREE.Points | null = null;
  private materials: THREE.Material[] = [];

  async load(): Promise<void> {
    // geometry + material 生成（1回のみ）
    this.ringA = createRing(/* ... */);
    this.ringB = createRing(/* ... */);
    this.particles = createParticles(/* ... */);
    this.core = createCore(/* ... */);
    this.materials = [/* 全material参照保持 */];
    scene.add(this.ringA, this.ringB, this.particles, this.core);
  }

  dispose(): void {
    // GPU resource完全解放
    [this.ringA, this.ringB, this.particles, this.core].forEach(obj => {
      if (!obj) return;
      scene.remove(obj);
      obj.geometry?.dispose();
    });
    this.materials.forEach(m => m.dispose());
    this.ringA = this.ringB = this.particles = this.core = null;
    this.materials = [];
  }

  unload(): void {
    this.dispose(); // 切替時に完全解放
  }
}
```

**切替時の安全保証:**
1. 旧アバターの `dispose()` を先に呼ぶ
2. 新アバターの `load()` を呼ぶ
3. animation loop / event listener の重複を`dispose()`で確実に解除
4. `dispose()` 後の `update()` 呼び出しは no-op（null guard）

---

## 10. テスト方針

| テスト | 方法 |
|--------|------|
| `luminaParams.ts` 単体 | vitest: STATE_PARAMS全ステート定義確認、affinity/mood変調の境界値 |
| `LuminaRing.ts` 単体 | vitest: リングジオメトリ頂点数・半径確認 |
| ステート遷移 | vitest: 全AnimaState遷移パターンでパラメータ補間確認 |
| VRM/Lumina切替 | vitest: avatarType切替でコンポーネント排他確認 |
| 視覚確認 | 手動: 各ステートの見た目目視確認（自動化対象外） |
| 既存テスト不変 | `MmdAvatarAdapter.test.ts` / `expressionMapping.test.ts` PASS確認 |

---

## 11. 実装フェーズ

### Phase 0（本設計書対象）

- [ ] `LuminaRenderer.tsx` + サブモジュール実装
- [ ] STATE_PARAMS 全ステート定義
- [ ] affinity / mood 変調
- [ ] VRM/Lumina 切替UI
- [ ] 単体テスト

### Phase 1（将来）

- [ ] `UnrealBloomPass` 追加（glow強化）
- [ ] VRM背後にLumina重畳表示モード
- [ ] パーティクルtrailのGPU最適化（instanced rendering）
- [ ] rainbowAccent実装（高好感度時の虹色効果）

---

## 12. 形状言語まとめ

| 視覚軸 | 意味 |
|--------|------|
| リング半径 | エネルギーレベル（大=高、小=低） |
| 回転速度 | 活動度（速=稼働、遅=休眠、不規則=異常） |
| 実線/破線 | 安定性（実線=安定、破線=不安定） |
| リングB傾斜 | 状態変化の強調（傾斜=変化中） |
| パーティクル数・速度 | 処理密度 |
| 色温度 | 感情（シアン=平常、暖色=ポジティブ、赤=異常、紫=拒絶） |
| 中心核サイズ・脈動 | 意識レベル（大=集中、小=休眠、点滅=異常） |

---

*作成日: 2026-05-16 | 対象フェーズ: Phase 0*
