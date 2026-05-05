# Three.js / VRM 知見

## AnimationClip — トラック名はノードの .name で解決

`THREE.PropertyBinding` はトラック名をシーン内ノードの `.name` で照合する。VRM normalized bone key（例: `"hips"`）とノードの実際の `.name`（例: `"J_Bip_C_Hips"`）は一致しないことがある。トラック名生成時は必ず `boneNode.name` を使う。`humanoid.getNormalizedBoneNode(key)?.name` で実ノード名取得可。

---

## URL からファイルID抽出前に query/hash 除去

`url.split('/').pop()` でファイル名取得前にクエリ文字列・ハッシュを除去すること。

```typescript
const pathname = url.split('?')[0].split('#')[0];
const basename = pathname.split('/').pop()?.replace(/\.[^.]+$/, '') ?? 'fallback';
```

キャッシュバスター付きURLで識別子抽出が壊れる典型パターン。

---

## VRM normalized bone の rest pose はランタイム取得可、FBX は不可

`vrm.humanoid.getNormalizedBoneNode(boneName).quaternion` でVRM rest pose クォータニオン取得可。invertをpremultiplyで部分的なT-pose補正が可能。FBX側のA-poseデータはFBXファイルのrange必要 → Three.js FBXLoaderのランタイムAPIからは取得不可。完全補正にはfbx2three等が必要。
