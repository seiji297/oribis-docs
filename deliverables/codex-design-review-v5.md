## Codex Review Result

### Verdict: FAIL

### 指摘事項
1. [severity: HIGH] 事象: `computeExpressionFrame` の pulse減衰ロジックが、残時間切れフレームでも `pulse` を優先しうる
   根拠: 分岐条件は `pulse.remainSec > 0` を見ていますが、強度計算は減衰後の `newRemainSec` を使っています。`pulse.remainSec > 0` かつ `newRemainSec = 0` のケースでは、そのフレームで `targetName = pulse.name` のまま `targetIntensity = 0` となり、設計書の「pulse減衰でbaseにフォールバック」と一致しません。
   想定原因: 分岐条件と減衰後値の参照先が不一致になっている
   確認コマンド: `pnpm test -- --runInBand src/utils/expressionLoop.test.ts -t "T-12|pulse減衰"`
   放置リスク: pulse終了直後に1フレーム不正な表情名/イベントが出て、表情遷移とテスト期待値が不安定になります。

2. [severity: HIGH] 事象: `AvatarViewer` 側の `pulseRef.current.remainSec = exprResult.newRemainSec;` が `pulseRef.current === null` の場合に実行時例外になる
   根拠: `computeExpressionFrame` の入力定義では `pulse: PulseState | null` を許容しており、呼び出し例でも `pulse: pulseRef.current` をそのまま渡しています。一方、戻り値適用側では nullチェックなしで `remainSec` を更新しています。
   想定原因: 純関数化で「pulseを返す/返さない」の責務整理はされたが、null許容ケースの反映が呼び出し側に漏れている
   確認コマンド: `pnpm tsc --noEmit`
   放置リスク: pulse未発火時にレンダーループでクラッシュし、Phase 0 の最低限の表示検証自体が成立しなくなります。

3. [severity: MEDIUM] 事象: `ExpressionFrameResult.prevDisplay` の型定義と設計説明・実装例が矛盾している
   根拠: 型定義は `prevDisplay: number;` ですが、コメントでは「存在しない場合はnull」、実装例でも `let prevDisplay: number | null = null;` として返しています。このままでは設計どおりに実装すると型不整合になります。
   想定原因: R4-1 の純関数再設計時に戻り値型の更新が漏れた
   確認コマンド: `pnpm tsc --noEmit`
   放置リスク: 実装時に型逃がしや不要なダミー値導入が起き、以後のイベント条件やテストの可読性・保守性が落ちます。

4. [severity: MEDIUM] 事象: AC/完了条件に「既存挙動を壊していないこと」の検証が不足している
   根拠: 今回は `AvatarViewer.tsx` と `App.tsx` の配線変更を含みますが、完了条件は主に純関数単体と手動の配線確認に寄っており、`exprOverrides` 優先適用や既存モーフ反映ループとの統合回帰を自動で担保する項目がありません。
   想定原因: pure-function-test-pattern を優先し、統合回帰観点がテスト設計から抜けている
   確認コマンド: `pnpm test -- --runInBand src/adapters/expressionMapping.test.ts`
   放置リスク: 単体テストは通っても、実画面では override 優先順位や複数表情更新の適用順が崩れ、既存表情制御に回帰が入る可能性があります。

### 総評
純関数化の方向性自体は妥当ですが、pulse終了境界と null許容ケースに実装破綻ポイントが残っています。現状のままでは AC を満たしたつもりでもランタイム不具合や表情遷移の1フレーム不整合が起きうるため、FAIL 判定です。