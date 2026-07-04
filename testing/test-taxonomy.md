# Test Taxonomy

このtaxonomyは、Oribisの新機能/App/capability追加とリリース前検証を混同しないための共通語彙。

## Process Layer

| Layer | 意味 |
|---|---|
| `Feature Intake` | 何を追加するか、影響範囲、権限、AI入口、UI入口、schema、証跡、テスト方針、WindowsQA要否を決める |
| `Feature Build` | 実装とテスト追加 |
| `Feature Done Definition` | 全feature共通の完了基準。UIだけでなくAI-native、権限、schema、証跡を含む |
| `Acceptance Criteria` | 個別feature固有の成功条件 |
| `Risk-based Test Selection` | 変更リスクに応じて必要な検証Level/Runner/Environmentを選ぶ |
| `Release Gate` | 出荷可否判定。仕様確認の場ではない |

## Verification Level

LevelはRunnerではなく、何を保証するかで決める。

| Level | 意味 | 主な確認対象 |
|---|---|---|
| `Static` | 実行前検査 | typecheck、build、lint、schema、manifest、禁止経路、危険語録/固定ルーター検出 |
| `UT` | Unit Test | 純粋関数、schema、component単体、catalog validation、permission判定 |
| `IT` | Integration Test | RootShell、App catalog、AI operation、storage、UI状態、内部配線 |
| `SIT` | System Integration Test | Tauri command、Worker server、Discord relay、WebViewer接続、外部/サブシステム境界 |
| `ST` | System Test | Oribis全体の起動、画面、3D、主要ユーザーフロー |
| `AT` | Acceptance Test | ユーザー要求、代表ユースケース、人間にとって妥当な体験 |
| `Diagnostic` | 原因調査 | local repro、port調査、環境切り分け。AT/STの代替にしない |
| `Release Gate` | Release decision | 必須項目、証跡、未解決リスク、WindowsQA実画面結果を見た出荷可否判断 |

## Runner

| Runner | 意味 |
|---|---|
| `TypeScript` | `tsc` / typecheck |
| `Build` | Vite/Tauri/package build |
| `Vitest` | Node/jsdom/happy-dom等で実行する単体・結合テスト |
| `Cargo` | Rust build/check/test |
| `Python e2e` | Python clientによるbackend/e2e |
| `WDIO` | WebDriver経由の自動UIテスト。Levelは目的によりIT/SIT/ST |
| `WindowsQA Server` | Windows実デスクトップ/実GPU/実操作証跡の正規Runner |
| `manual review` | 人間による確認。自動テストとは区別 |

## Environment

| Environment | 扱い |
|---|---|
| `local-linux` | 開発、Static、UT、IT、supporting |
| `wslg` | WDIO/visual補助。Release Gate requiredにはしない |
| `local-windows` | diagnostic / quick repro。AT本番扱いにしない |
| `windows-qa-server` | official AT / Release Gate evidence |
| `ci` | deterministic regression / automated safety net |

## Route

| Route | 意味 |
|---|---|
| `unit-only` | Unit testのみ |
| `mocked` | mockを含む |
| `source-snapshot` | ソーススナップショットで実行 |
| `real-app` | 実アプリ経路 |
| `real-gpu` | 実GPU表示経路 |
| `actual-user-operation` | DOM/UI/OS操作によるユーザー相当操作 |
| `wdio` | WDIO/WebDriver経由 |
| `wslg` | WSLg表示経路 |
| `windows-qa-server` | WindowsQAサーバ経由 |
| `diagnostic` | 原因調査用。合格証跡ではない |
| `headless` | headless実行。表示品質のPass根拠にしない |

## Gate

| Gate | 意味 |
|---|---|
| `required` | 出荷判断に必須 |
| `supporting` | 早期検知・補助証跡。単独では出荷可否を決めない |
| `diagnostic` | 原因調査。AT/ST/Release Gateの代替にしない |

## Result

| Result | 意味 |
|---|---|
| `PASS` | 合格条件と証跡が一致 |
| `PASS_WITH_WARNINGS` / `PASS_WITH_SCREENSHOT_WARN` | 主判定は合格。ただし補助証跡や診断系の警告が残る。Release Gateでは警告内容と受容理由を記録する |
| `PASS_WITH_LIMITATION` | 一部の下位/補助条件は通ったが、requiredの保証条件が残っている。required gateでは未達扱いにし、`requiredNotRun` / `requiredBlocked` またはwaiverで明示する |
| `PASS_WITH_DIAGNOSTIC_ONLY` | diagnosticとしては通ったが、required gateの代替にはならない |
| `FAIL` | 合格条件未達 |
| `BLOCKED` | 環境・外部要因で実行不可 |
| `BLOCKED_ON_WINDOWSQA` | `BLOCKED` の原因付きサブ表記。WindowsQA host / real-gpu / actual-user-operation routeが外部要因で実行不能な状態。required PASSとして扱わない |
| `NOT_RUN` | 未実行 |
| `MANUAL_PASS` | 人間の目視確認でPass。自動Passとは区別 |
| `SKIPPED` | 明示的に対象外 |

## Risk Score

| 条件 | Score |
|---|---:|
| isolated UI | +1 |
| AI tool catalog/schema変更 | +2 |
| external integration | +2 |
| Worker/WebViewer/DiscordRelay連携 | +2 |
| user data/local file/storage | +3 |
| permission/auth/policy | +3 |
| migrationあり | +3 |
| rollback困難 | +3 |
| Windows native/GPU/WebView/installer | +3 |

| Score | Risk |
|---:|---|
| 0-2 | Low |
| 3-5 | Medium |
| 6+ | High |

## Regression Scope

RegressionはLevelではない。

| Scope | 意味 |
|---|---|
| `smoke` | 基本起動・基本表示 |
| `new-feature` | 新規機能確認 |
| `regression` | 既存仕様維持・過去不具合再発防止 |
| `critical` | 壊れるとリリース不可 |
| `security` | 権限、secret、外部送信、PII等 |
| `performance` | 起動、描画、queue、重い処理 |
| `compatibility` | 互換性、schema version、migration |

## Area

| Area | 意味 |
|---|---|
| `Build` | typecheck、build、cargo、packaging |
| `StartupGPU` | 起動、GPU、Render Error、残留ウィンドウ |
| `Onboarding` | 初回設定、3DView単体、Anima表示 |
| `Workbench` | App window、dock、tab、default layout |
| `Scene` | Scene App、Stage 3D、Anima、3D terminal |
| `Anima` | VRM、TTS、Prompt、Memory、Cache、AnimaState |
| `Worker` | Worker terminal、Worker chat、job/session |
| `Console` | Console/Log |
| `Settings` | Settings App、設定保存、AI-native設定 |
| `WebViewer` | Web表示、自動操作、Web接続 |
| `AI-native` | App action catalog、tool schema、permission、dispatcher |
| `DiscordRelay` | channel routing、queue即時送信、外部送信 |
| `Release` | manifest/evidence照合、出荷可否 |

## 禁止

- Runner名をLevelとして扱わない。
- local-windowsの切り分けをAT/Release Gate Passにしない。
- WSLg/WDIOをWindowsQA Server実画面証跡の代替にしない。
- screenshotだけでPassにしない。
- AI生成テストだけで完了扱いにしない。
- feature flagをUIだけに効かせ、AI catalog/tool executionから呼べる状態にしない。
- secret/API key/token/cookie/PIIを証跡へ残さない。
