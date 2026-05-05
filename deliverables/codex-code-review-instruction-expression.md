# コードレビュー指示書 — 表情反映システム Phase 0

## 対象ファイル

- src/utils/expressionSystem.ts
- src/utils/expressionLoop.test.ts
- src/components/AvatarViewer.tsx
- src/App.tsx

## AC（受入条件）

1. computeExpressionFrame が完全な純関数であること（入力オブジェクトの破壊的更新がないこと）
2. AvatarViewer.tsx が純関数の結果を適用するだけであること
3. App.tsx が characterAffinity/computedMood を AvatarViewer に渡していること
4. 全expressionテストがPASSすること
5. TypeScriptエラーが増加していないこと

## レビュー観点

1. 純関数性: displayMap mutation が完全に排除されているか
2. pulse境界条件: newRemainSec > 0 で分岐しているか
3. null安全性: pulseRef.current の null チェックがあるか
4. テストの妥当性: テストが本番コードを直接呼んでいるか（再実装していないか）
5. パフォーマンス: 60fps描画ループ内で不要なオブジェクト生成がないか
