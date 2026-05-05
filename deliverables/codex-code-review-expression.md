## Codex Review Result

### Verdict: FAIL

### 指摘事項
1. [severity: MEDIUM] 事象: 60fps描画ループ内で未使用のオブジェクト生成が残っています。
   根拠: `computeExpressionFrame` は毎フレーム `events` と `pendingExpressions` を生成しますが、`AvatarViewer.tsx` 側では `exprResult.events` も `exprResult.pendingExpressions` も使用していません。
   想定原因: テスト容易性・互換性のために結果へ含めたが、描画ループ適用側では不要になっている。
   確認コマンド: `npx vitest run src/utils/expressionLoop.test.ts`
   放置リスク: 表情計算が常時60fpsで走るため、不要なGC圧が増え、低性能環境でフレーム落ちの原因になります。

2. [severity: MEDIUM] 事象: `AvatarViewer.tsx` が `computeExpressionFrame` の結果を「適用するだけ」ではなく、pulse状態の寿命管理も直接更新しています。
   根拠: `pulseRef.current.remainSec = exprResult.newRemainSec;` により、純関数の外側で `pulseRef.current` を破壊的更新しています。AC 1は満たしていますが、AC 2の責務分離としてはやや曖昧です。
   想定原因: 既存のrefベース状態管理へ最小差分で統合したため。
   確認コマンド: `npx vitest run src/utils/expressionLoop.test.ts`
   放置リスク: 今後pulse仕様が増えた場合、純関数側とViewer側に状態遷移責務が分散し、境界条件の回帰が起きやすくなります。

3. [severity: LOW] 事象: `affinity` の値域コメントと計算仕様が不一致です。
   根拠: `AvatarViewer.tsx` では `affinity?: number; // -100 ~ +100` とありますが、`computeMood` / `computeBaseExpression` / `affinityToTier` は `0 ~ 100` 前提です。
   想定原因: `characterAffinity` の既存仕様と新規expressionSystem側仕様の同期漏れ。
   確認コマンド: `npx vitest run src/utils/expressionLoop.test.ts`
   放置リスク: 負値が渡る運用だと常に `hostile` 側へ倒れ、意図しない表情になります。

### 総評
`computeExpressionFrame` 自体は入力pulseを破壊しておらず、pulse境界も `newRemainSec > 0` で判定されているため、純関数化の中核は概ね満たしています。ただし、描画ループで未使用データを毎フレーム生成している点と、`AvatarViewer` 側の責務境界がまだ少し濁っている点から、AC全体としてはFAIL判定です。