# Pre-release Test Plan

## 目的

Oribisのリリース前に、AI-assisted / バイブコーディングで追加された新機能/App/capabilityが、UI・AI-native操作・権限・schema・証跡・テストの観点で出荷可能かを判断する。

この計画は「全テストケースを毎回全部回す」ためのものではない。  
機能保証単位の `test-matrix.md` と、実行対象一覧の `test-inventory.md` と、証跡indexの `manifest.json` を使い、リスクベースで実行範囲を決める。

## 開発/検証モデル

```text
Feature Intake
  -> Feature Build
  -> Feature Done Definition
  -> Risk-based Test Selection
  -> Release Gate
```

検証Levelは以下。

```text
Static -> UT -> IT -> SIT -> ST -> AT -> Release Gate
```

`Feature Intake / Feature Done Definition / Acceptance Criteria` は新機能追加プロセス。  
`Static / UT / IT / SIT / ST / AT / Release Gate` は検証Level。  
この2つを混同しない。

## 対象

- Build / Typecheck / Cargo / packaging
- Startup / GPU / Render Error / residual window
- Onboarding
- Workbench / App window / docking / tabs / default layout
- Scene App / Stage 3D / Anima / 3D terminal
- Settings / Anima設定 / TTS / VRM / Prompt / Memory / Cache
- Worker / Chat送信 / terminal / job / session
- Console / Log
- WebViewer / Web接続 / 自動操作
- AI-native App operation / tool catalog / schema / permission
- Discord relay / channel routing / queue即時送信
- Feature flags / capability flags
- Release Gate manifest/evidence照合

## 非対象

- Xvfb / CPU fallback を実GPU表示確認として扱うこと
- local-windows diagnostic をAT/Release Gate Passとして扱うこと
- WSLg/WDIOをWindowsQA Serverの代替にすること
- テスト用別導線だけで成立する確認
- secret/API key/token/cookie/PIIを含む証跡保存
- AIが生成したテストのみで完了扱いにすること

## Required Gate

リリース判断に必須の領域:

- `ORB-STATIC-001`: Build/typecheck/cargo/build
- `ORB-STATIC-002`: test harness policy
- `ORB-STATIC-003`: AI-native固定語録ルーター非復活
- `ORB-SIT-001`: Worker chat / terminal / output / input clear
- `ORB-SIT-002`: Discord relay / queue / route
- `ORB-SIT-003`: WebViewer connection
- `ORB-ST-001`: Startup/GPU/Render Error/residual window
- `ORB-ST-002`: Onboarding
- `ORB-ST-003`: Scene App / Stage / 3D terminal
- `ORB-ST-004`: Workbench App window / docking / tabs
- `ORB-ST-005`: Console/Log
- `ORB-ST-006`: WebViewer UI
- `ORB-AT-001`: AI-native App operation
- `ORB-AT-002`: Settings/Anima UX
- `ORB-AT-003`: Worker UX
- `ORB-AT-004`: WebViewer UX
- `ORB-AT-005`: Audio/TTS UX
- `ORB-GATE-001`: Release Gate evidence audit
- `ORB-GATE-002`: Release Packaging Gate

## Gate 判定ルール

- `Release Owner` はProducerを指す。Producerが明示的に委任した場合だけ、委任先をRelease Ownerとして扱う。
- `Gate=required` の項目は、`Result=PASS` かつ `manifest.json` に証跡が登録されていなければRelease Gateを通さない。
- `audit-release-manifest.mjs --verify-evidence-files` のPASSは「manifest構造・証跡参照の整合性PASS」であり、Release Gate PASSではない。requiredに `BLOCKED` / `BLOCKED_ON_WINDOWSQA` / `NOT_RUN` / 未verified release-blocking bugが残る場合、Release Gateは未達。
- `bug-regressions.md` の `release_blocking=true` は、`status=verified` かつ証跡が登録されていなければRelease Gateを通さない。
- 不具合回帰台帳の各項目は、必ず `linked_test_ids` で `test-matrix.md` の保証項目へ紐づける。紐づかない不具合は未整理として扱う。
- `Level=ST` または `Level=AT` でWindows実画面を含む項目は、`windows-qa-server + real-gpu + actual-user-operation` の証跡だけを正式PASS扱いにする。
- WindowsQA Serverの公式実行は、対象repoのclean worktree、指定commit同期、runner repo外配置、summary自己記述を開始条件にする。条件を満たさない場合は即FAIL/BLOCKEDで、後続テストへ進まない。
- `official=true` のWindowsQA summaryには `sourceMode`、`requestedCommit`、`resolvedCommit`、`cleanChecks`、`skippedSteps` を含める。official実行ではskip系フラグを使わない。
- 未コミット作業はQA用refへ一時commitをpushし、そのSHAをWindowsQAへ渡す。source snapshotはdiagnostic/supportingのみにする。
- Release Gateはdev/debug経路だけでなく、packaged release buildまたはinstallerの起動確認を必須にする。
- `local-windows`、`wslg`、`wdio`、`source-snapshot`、`diagnostic` の成功はsupportingまたはdiagnosticであり、required ST/ATの代替にしない。
- `PASS_WITH_DIAGNOSTIC_ONLY` はRelease GateのPASSではない。
- `BLOCKED`、`FAIL`、`NOT_RUN`、`ABORTED`、required項目の `PASS_WITH_LIMITATION` はRelease Gateで明示し、未記録のまま通さない。
- `BLOCKED_ON_WINDOWSQA` は `BLOCKED` の原因付きサブ表記。意味は「WindowsQA host / real-gpu / actual-user-operation routeが外部要因で実行不能」であり、required PASSとして扱わない。
- required項目の `PASS_WITH_LIMITATION` は「一部検証済み」ではあるが「出荷可のPASS」ではない。残条件を `requiredNotRun`、環境起因なら `requiredBlocked`、または期限付きwaiverへ明示する。
- WindowsQAの公式証跡参照はrunId付き不変パスとhashで行う。`latest-*` aliasは正規証跡に使わない。
- `ORB-GATE-001` 実行時は、`manifest.json` の `bugRegressions` について `release_blocking=true` 全件が `status=verified` であり、各 `verification_evidence` が再確認可能な `path + sha256` 形式でpin留めされていることを確認する。これを満たさない場合、bug台帳側の証跡は未達扱いにする。
- summaryが欠落、不完全、またはrunId付きzipと対応しないrunは無効。完走したrunだけをRelease Gate証跡として扱う。
- waiverは例外扱い。`waiver.id`、`reason`、`approver`、`expiresAt`、`affectedTestIds` がないwaiverは無効。
- secret/API key/token/cookie/PIIを含む証跡は無効。必要な場合はマスク済み証跡だけを登録する。

## Manifest 追跡ルール

`manifest.json` は機械検証向けの正に近い索引として扱う。各代表保証項目は最低限以下を持つ。

- `test_id`
- `area`
- `level`
- `gate`
- `environmentClass`
- `sourceAnchors`
- `requiredEvidence`
- `lastExecution`
- `result`
- `waiver`

不具合回帰については `bugRegressions` を持ち、最低限 `bug_id`、`status`、`release_blocking`、`linked_test_ids`、`requires_test_matrix_update`、`test_matrix_update_summary`、`verification_evidence`、`limitations` を機械可読にする。

構造検査はOribis repoで以下を実行する。

```bash
node scripts/qa/audit-release-manifest.mjs
```

Release Gate最終監査では、bug証跡のpin留めも含めて以下を実行する。

```bash
node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files
```

WindowsQAの各summaryは、登録前に以下で公式実行/commit固定/clean/skippedStepsを機械確認する。

```bash
node scripts/qa/audit-windows-qa-summary.mjs <summary.json> --official --require-pass
```

summary監査ツール自体の回帰テストはVitestではなくNode `node:test` で実行する。

```bash
pnpm run test:qa-audit
```

既存のlegacy summaryで `mode` / `schemaVersion` / `qaProfile` / `runnerScriptSha256` が無いものは、`official=true`、`sourceMode=git`、commit固定、cleanChecks、skippedStepsが満たされる場合に限り、warning付きで既存証跡として扱う。新規summaryはこれらのfieldを含める。

Packaging Gateのsummaryは、installer/install/uninstall/cleanupも含めて以下で確認する。

```bash
node scripts/qa/audit-windows-qa-summary.mjs <summary.json> --official --packaging --require-pass
```

Markdownの `test-matrix.md` は人間向けの判断表、`test-inventory.md` は実テスト/ソース索引、`manifest.json` はRelease Gate照合用。

## Supporting Gate

以下はrequired項目を支える補助証跡。

- Vitest unit/integration
- Cargo check/test
- Python e2e
- WDIO/WSLg visual/e2e
- local-windows quick repro
- source inspection

## Required AT/ST 実行前基準

### ORB-AT-001 real LLM representative

`ORB-AT-001` のreal LLM代表確認は、結果を見てから合格基準を変えない。実行前に以下を固定する。

- 対象: `e2e/wdio/tests/app-ai-native-real-llm-representative.spec.ts` の代表10件。
- 合格閾値: 10件中8件以上PASS。
- 各caseの合格条件:
  - DOMチャット送信だけを入口にする。
  - 送信後の入力欄が空。
  - `<oribis-tool>` 等のraw tool blockが画面に出ない。
  - App Actions catalogから該当toolName/schemaが使われ、caseごとの期待状態へ変化する。
- 証跡:
  - `app-ai-native-real-llm-representative.json`
  - `app-ai-native-real-llm-representative.png`
  - summary JSON
  - 必要に応じてマスク済みtranscript。secret/API key/token/cookie/PIIを含むtranscriptは無効。
- retry規定:
  - 環境起因の起動失敗、WindowsQA host切断、LLM provider明示障害は `BLOCKED` として記録し、同じcommitで再実行可。
  - case失敗や期待状態未達はretryで上書きせずFAILとして記録する。再実行する場合は別runIdで残し、両方をexecution-reportに記録する。

### Secrets and external routes

`ORB-AT-001` real LLM、`ORB-SIT-002` Discord real relay、`ORB-SIT-008` visible authはsecretを扱う可能性があるため、開始条件を分ける。

- QA用LLM key / Discord token / guild / channelはrepo外に配置する。
- 証跡へsecretを出さない。summary、transcript、screenshot、console logへ出た場合、その証跡は無効。
- Start-Transcriptを使うrunnerでは、実行前にsecret echoが無いこと、実行後にsecret scanまたは目視マスク確認を行う。
- 送信先channel/guildは設定で決まり、AI推論に送信先判断を委ねない。

### Interactive Windows route

`ORB-GATE-002` packagingのinstalled app screenshotと `ORB-AT-005` audio/TTSは、SSHの非対話sessionだけでは不十分な場合がある。

- `register-interactive-tasks.ps1` / `interactive-capture.ps1` / `invoke-windows-interactive-qa.sh` を使う場合は、WindowsQA実デスクトップ・実GPU・実ユーザーsession上で動いた証跡として扱う。
- SSHだけで `CopyFromScreen` が失敗する場合は、desktop screenshotをwarnにせず、interactive routeへ切り替える。
- interactive routeでも対象commit、cleanChecks、summary自己記述、runId付きartifact、secret非露出は必須。

### ORB-AT-002 human review checklist

`ORB-AT-002` は自動テストだけで完了にしない。WindowsQA証跡に加えて、以下の人間向けchecklistを埋める。

- 初回設定がLLM/Anima基本設定に集中している。
- `anima` / `User` の既定値が自然で、旧 `Idea` が露出しない。
- カード型の選択肢が、未設定ユーザーにも意味を理解できる。
- Generalへ設定が詰め込まれすぎず、Anima/Prompt/TTS/Apps等のまとまりが分かる。
- Prompt / files / cache / Anima cacheが重複タブとして見えない。
- 設定画面の白背景/テーマ不一致がない。

## WindowsQA 復旧Runbook

WindowsQA hostがSSH timeoutの場合、AT/STを代替実行せず、以下の順で復旧確認する。

1. WSL側から `ssh -i ~/.ssh/oribis_windows_qa -o BatchMode=yes -o ConnectTimeout=8 admin@100.64.6.42 "echo windowsqa-ok"` を実行する。
2. timeoutする場合は、WindowsQA側のTailscale接続、OpenSSH Server、Windows Firewall、電源/スリープ、IP変更を確認する。
3. 復旧直後に軽量host health checkを実行し、clean check、残留Oribis/Vite/node process、disk free、Tailscale/OpenSSH状態を確認する。このrunはdiagnostic/supportingであり、required AT/STの代替にしない。
4. required公式runへ入る前に、出荷候補のRC SHAを確定する。QA-ref一時commitの証跡だけでRelease Gateを通さない。
5. health check後、最初に `tests/worker-chat.spec.ts` をRC SHAのofficial commitで実行し、`ORB-SIT-001` と `ORB-AT-003` を同一runで満たせるか、かつ `ORB-BUG-015/016` をverifiedへ戻せるか確認する。`ORB-SIT-001` は配線/4点表示、`ORB-AT-003` はWorker UXの進捗/状態/結果の妥当性として別々に判定し、証跡は同一runへ紐づけてよい。
6. 次に `run-windows-packaging.ps1` を実行し、Release Packaging Gateの初回完走可否を早期に出す。
7. その後、`tests/app-ai-native-real-llm-representative.spec.ts`、Discord real relay、`tests/core-app-workbench.spec.ts`、`tests/onboarding-anima-visual.spec.ts`、`ORB-AT-005` TTS/audioの順で実行する。secret準備が未完の項目は後回しにし、WindowsQA host稼働時間を空転させない。
8. 各runのsummaryは `audit-windows-qa-summary.mjs` で監査してからmanifestへ登録する。bug証跡は `audit-release-manifest.mjs --verify-evidence-files` で実ファイルとsha256を照合する。
9. Xvfb/CPU fallback、local-windows diagnostic、WSLgは正式AT/STの代替にしない。

Escalation:

- `ssh` と `ping` が3回連続でtimeoutする場合は、WindowsQA hostがofflineまたはTailscale/Firewall/SSH層で到達不能として扱う。
- その時点でST/ATは `BLOCKED_ON_WINDOWSQA` と記録し、物理アクセス、Windows再起動、Tailscale再接続、OpenSSH Server再起動、別WindowsQA hostの準備のいずれかへエスカレーションする。
- エスカレーション中もXvfb/CPU/local-windows/WSLgでrequired ST/ATを代替しない。

## Diagnostic

Diagnosticは原因調査。Release Gateの代替にしない。

例:

- local-windowsでのdevUrl/port/black screen調査
- WSLg起動可否調査
- port、process、driver、cacheの切り分け

## 完了条件

- `test-matrix.md` が新ルールの列構成に揃っている。
- `test-inventory.md` に既存テスト/スクリプトが代表保証項目へ紐づいている。
- `manifest.json` がtest_id、environment、route、gate、evidenceを追跡できる。
- `bug-regressions.md` がProducer/QA指摘の重要不具合を `test_id` へ紐づけ、release blockingな未検証不具合を隠していない。
- required項目のPASS/BLOCKED/NOT_RUNが明示されている。
- WindowsQA Serverが必要な項目は、local-windowsやWDIOで代替していない。
- Feature flags/capability flagsのdefault/kill switch/公開範囲を確認している。
- 未解決リスクがexecution-reportに残っている。
