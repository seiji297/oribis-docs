# Oribis Testing

このディレクトリは、OribisのAI-native / バイブコーディング開発で、AIが何を実装し、何をテストし、なぜリリースできると言えるのかを人間が検証できるように残す品質台帳。

Oribisは今後も新機能/App/capabilityを継続追加する前提で運用する。したがって、テスト体系は単なるフェーズ表ではなく、**機能追加プロセス** と **検証Level** と **Release Gate** を分離して管理する。

## 最上位ルール

採用する開発/検証フロー:

```text
Feature Intake
  -> Feature Build
  -> Feature Done Definition
  -> Risk-based Test Selection
  -> Release Gate
```

`Static / UT / IT / SIT / ST / AT / Release Gate` は検証Level。  
`Feature Intake / Feature Done Definition / Acceptance Criteria` は新機能追加プロセス。  
この2つを混ぜない。

## 原則

- OribisのAppは画面単位ではなくcapability単位で管理する。
- 「画面で動く」だけでは完了にしない。
- 「AIが安全に発見し、権限内で実行し、証跡を残し、テストで保証される」までを新機能追加の完了条件にする。
- DoDは全feature共通の品質基準、Acceptance Criteriaは個別featureの成功条件として分ける。
- テスト項目表は全テストケース一覧ではなく、人間がリリース可否を判断する機能保証表にする。
- 既存の大量Vitest/WDIO/Cargo/Python e2eは、代表保証項目に紐づく実行対象として `test-inventory.md` / `manifest.json` に記録する。
- デグレ確認は独立フェーズではなく、各項目の `Regression Scope` として扱う。
- RunnerとLevelを混ぜない。WDIOはRunnerであり、Levelではない。
- WindowsQA ServerはRunner/Environment/Routeであり、正規AT/Release Gate証跡の取得経路として扱う。
- local-windowsやWSLgの確認はdiagnostic/supporting。AT本番の代替にしない。
- Xvfb / CPU fallback / mock / test-only route を実GPU・実アプリ・実操作のPassとして扱わない。
- Screenshot単体、ログ単体ではPassにしない。合格条件と証跡が対応している場合だけPassにする。
- FAIL / BLOCKED / NOT_RUNを隠さない。
- ABORTEDを隠さない。操作者中断や外部中断で完走しなかったrunは、PASS/FAILに混ぜずABORTEDとして記録する。
- secret/API key/token/cookie/PIIを証跡に含めない。
- Producer/QAが指摘した不具合は `bug-regressions.md` に記録し、必ず `test-matrix.md` の `test_id` へ紐づける。
- 不具合を大量に `test-matrix.md` へ直接追加しない。ただし不具合が示した保証不足は、該当 `test_id` の Acceptance Criteria / Required Evidence / Regression Scope へ反映する。
- 不具合修正テストは独立フェーズにしない。個別不具合は `bug-regressions.md`、製品として恒久保証すべき観点は `test-matrix.md`、実行結果と証跡は `manifest.json` / `execution-report.md` に置く。
- AIが実行したテストは、`executor`、`execution_mode`、`steps_performed`、`input_data`、`expected_result`、`actual_result`、`limitations`、`human_review_required` を証跡または実行報告に残す。

## 正規ファイル構成

```text
oribis-docs/
  testing/
    README.md
    feature-development-process.md
    test-taxonomy.md
    release-checks/
      pre-release/
        test-plan.md
        test-matrix.md
        test-inventory.md
        execution-report.md
        manifest.json
        regression-index.md
        bug-regressions.md
        evidence/
          <test_id>/
            ...
```

## ファイルの役割

- `feature-development-process.md`: 新機能/App/capability追加時のFeature Intake、Done Definition、risk score、feature flag、WindowsQA方針。
- `test-taxonomy.md`: 検証Level、Runner、Environment、Route、Gate、Result、Riskの共通定義。
- `test-plan.md`: 今回のpre-release確認目的、範囲、非対象、完了条件。
- `test-matrix.md`: 人間が見る機能保証表。代表保証項目単位。
- `test-inventory.md`: 既存テスト/スクリプト/WDIO/Cargo/Python e2eの棚卸しと、代表保証項目への紐づけ。
- `manifest.json`: 実行結果、証跡、hash、環境、build、対象test_idを紐づける機械可読index。
- `execution-report.md`: 今回の実行結果、未実行、ブロッカー、次にやること。
- `regression-index.md`: regression scopeを持つ項目の抽出ビュー。独立フェーズではない。
- `bug-regressions.md`: Producer/QAが実際に見つけた重要不具合を、正本の `test_id` に紐づける回帰台帳。独立フェーズではない。
- `evidence/<test_id>/`: スクショ、動画、JSON、ログなどの証跡実体。

## 必須カラム

`test-matrix.md` は以下を基本にする。

| 列 | 意味 |
|---|---|
| `test_id` | 一意の保証項目ID |
| `Area` | 機能領域 |
| `Risk` | 主な失敗リスク |
| `Level` | `Static`, `UT`, `IT`, `SIT`, `ST`, `AT`, `Release Gate`, `Diagnostic` |
| `Runner` | `TypeScript`, `Vitest`, `Cargo`, `WDIO`, `WindowsQA Server`, `manual review` |
| `Environment` | `local-linux`, `wslg`, `local-windows`, `windows-qa-server` |
| `Route` | `unit-only`, `mocked`, `real-app`, `real-gpu`, `actual-user-operation`, `diagnostic` 等 |
| `Gate` | `required`, `supporting`, `diagnostic` |
| `Regression Scope` | `smoke`, `regression`, `new-feature`, `security`, `performance`, `compatibility` 等 |
| `Required Evidence` | 必要な証跡 |
| `Linked Commands` | 紐づく実行コマンド/スクリプト |
| `Acceptance Criteria` | 合格条件 |
| `Actual Result` | 実測結果 |
| `Result` | `PASS`, `PASS_WITH_WARNINGS`, `PASS_WITH_LIMITATION`, `PASS_WITH_DIAGNOSTIC_ONLY`, `FAIL`, `BLOCKED`, `BLOCKED_ON_WINDOWSQA`, `NOT_RUN` |
| `Notes` | 補足、残リスク |

Producer/QAが見つけた不具合に紐づく正本項目は、`Notes` または関連する `regression-index.md` / `manifest.json` から `bug_id` を逆引きできる状態にする。  
正本側に紐づかない `bug_id` はRelease Gateで未整理として扱う。

## Gateの意味

| Gate | 意味 |
|---|---|
| `required` | 出荷判断に必須 |
| `supporting` | required項目の補助証跡。単独では出荷可否を決めない |
| `diagnostic` | 原因調査/ローカル再現。ST/AT/Release Gateの代替にしない |

## 不具合回帰台帳の扱い

`bug-regressions.md` は、過去に実際に起きた不具合がどの保証項目で再発防止されるかを追跡する補助台帳。  
これは新しい検証Levelや独立Regressionフェーズではない。

Release Gateでは、`Gate=required` の `test_id` がPASSであることに加え、`release_blocking=true` の不具合がすべて `verified` になっていることを確認する。  
`linked_test_ids` が空の不具合は、正本テスト体系から遊離しているためRelease Gateで警告または失敗扱いにする。

各不具合は、単に直ったかではなく、以下を判定する。

- `root_cause_summary`: 原因が何だったか。
- `regression_risk`: 再発しやすい領域か。
- `requires_test_matrix_update`: 正本の保証項目へ昇格すべき観点があるか。
- `test_matrix_update_summary`: 昇格した場合、どのAcceptance Criteria / Required Evidence / Regression Scopeへ反映したか。
- `verification_evidence`: 再確認可能なスクショ、JSON、ログ、transcript、動画。
- `limitations`: AI/automation/human reviewが確認できなかった範囲。

Release Gateでは、`release_blocking=true` かつ `requires_test_matrix_update=true` の不具合について、対応する `test_id` 側に保証観点が反映されていない場合は未解決として扱う。

## WindowsQA Serverの扱い

WindowsQA Serverは、Windows実デスクトップ・実GPU・実アプリ操作が必要なAT/Release Gateの正規証跡経路。

公式WindowsQAは、対象repoがclean worktreeで、指定commitへ同期できる状態だけで開始する。runnerや一時ファイルをrepo内へ同期してrepoを汚す運用は禁止。dirty repo、git update失敗、対象revision不一致は即FAIL/BLOCKEDにし、後続テストへ進まない。

公式WindowsQA証跡は、summary JSON内に `official`、`sourceMode`、`requestedCommit`、`resolvedCommit`、`cleanChecks`、`skippedSteps` を持つ必要がある。`official=true` の実行ではskip系フラグを使わない。開発中の未コミット作業をWindowsQAへ送る場合は、ファイルコピー式snapshotではなくQA用refへ一時commitをpushし、そのSHAを `--commit` で指定する。source snapshotはdiagnostic/supportingに限定する。

Release Gateには、dev server/debug buildだけでなく、WindowsQA上でrelease buildまたはinstallerを検証するPackaging Gateを含める。実LLM/DiscordのATはrequiredを維持し、専用テスト用API key/Discord guild/channelを使う。secretを含む証跡は無効であり、登録前にsecret scanまたはマスク確認を行う。

証跡参照は必ずrunId付きの不変パスとhashで行う。`latest-*` は人間が直近結果を見るためのaliasに限定し、manifestやRelease Gateの正規証跡参照には使わない。summaryが欠落、不完全、またはrunId付きzipと対応しないrunは無効として扱う。

| 環境 | 扱い |
|---|---|
| local-linux | 開発、UT、IT、supporting |
| WSLg/WDIO | ST補助、visual regression補助。最終実画面証跡ではない |
| local-windows | diagnostic / quick repro。AT本番にしない |
| windows-qa-server | official AT evidence / Release Gate evidence |

## 参考情報

- DORA 2025 AI-assisted Software Development: https://dora.dev/dora-report-2025/
- GitHub Copilot best practices: https://docs.github.com/en/copilot/get-started/best-practices
- GitHub Copilot testing guidance: https://docs.github.com/en/copilot/tutorials/write-tests
- Martin Fowler Continuous Integration: https://martinfowler.com/articles/continuousIntegration.html
- Martin Fowler Feature Toggles: https://martinfowler.com/articles/feature-toggles.html
- Atlassian Definition of Done: https://www.atlassian.com/agile/project-management/definition-of-done
- Atlassian Acceptance Criteria: https://www.atlassian.com/work-management/project-management/acceptance-criteria
