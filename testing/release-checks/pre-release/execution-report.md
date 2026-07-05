# Pre-release Execution Report

## Release Gate 現在地

現時点の判定: **BLOCKED / Release Gate停止**。

直接原因: `ORB-PERF-001` のWindowsQA official partial runで、L2/L3 Codex laneがpreflight timeoutにより実行不能、D群route5/6が未実行であることを確認した。あわせて、L1内製Workerは測定済みだが、A+B+C 14件で `l1-instant=11/14`、`l1-job=12/14` に留まり、品質失敗が残る。

`manifest.json` は `requiredBlocked=["ORB-PERF-001"]`、`requiredNotRun=["ORB-GATE-001"]`。以前のstrict監査PASSは、`ORB-PERF-001` 追加前の歴史的証跡であり、現時点のRelease承認根拠にしない。

| 状態 | 件数 / 対象 |
|---|---|
| Required BLOCKED/FAIL | `ORB-PERF-001` |
| Required NOT_RUN | `ORB-GATE-001`（`ORB-PERF-001` 解消後に再実行） |
| 未verified release-blocking bug | なし |
| 今回scope外 | `ORB-SIT-002` / `ORB-BUG-019`: Discord環境未準備のためProducer指示で延期。waiver `WAIVER-20260704-DISCORD-ENV-NOT-PREPARED` |
| 代替不可 | Xvfb / CPU fallback / WSLg / local diagnostic は正式PASSにしない |

現時点の停止分類:

| test_id | Release Gate上の扱い | 直接原因 | 次のunblock条件 |
|---|---|---|---|
| `ORB-PERF-001` | `blocked` | WindowsQA official partial run `20260706-061348` で `l2-codex-pty` / `l3-codex-raw` がpreflight_timeoutにより全task skipped/BLOCKED。D群route5/6は第1回範囲外NOT_RUN。L1測定結果は `l1-instant=11/14`、`l1-job=12/14` で、A2/A5/B3/C2/C5/R2等に品質失敗が残る | Producer承認後にWindowsQA Codex CLI authを設定しL2/L3を再実行する。並行してL1失敗原因をプロダクト/fixture/採点に切り分け、D群route5/6を実装して第2回officialを完了する |
| `ORB-GATE-001` | `not_run` | `ORB-PERF-001` がrequired blockerになったため、以前のstrict audit PASSは現Release承認に使えない | `ORB-PERF-001` 解消後に `audit-release-manifest --require-release-pass --require-bug-evidence-sha --verify-evidence-files` を再実行する |

分類ルール:

- `requiredBlocked` はRelease Gateを止める。scope外/waived扱いではない。
- `requiredBlocked` には、製品不具合だけでなく、official条件の環境・前提未充足でrequired PASSへ到達できないものも含める。原因種別は上の表で分離して読む。
- `ORB-AT-001` は2026-07-05 official run `20260705-213712` / commit `b4601967900a4898d959b75bf4c8f78a92fdadfa` でthreshold PASSへ解消済み。deterministic mock 30件PASSに加え、real LLM代表10件で `passedCount=8/10`, `minPass=8` を満たした。
- `ORB-AT-005` は2026-07-05 official run `20260705-111317` でPASS_WITH_WARNINGSへ解消済み。desktop screenshot warnは残るが、WDIO TTS playback 6件はPASS。
- `ORB-GATE-002` は2026-07-05 official run `20260705-234741` / commit `48ea7fd64c5c59833962d6e1755d0d930d39764e` でPASSへ解消済み。release build / VOICEVOX/Kokoro bundle check / installer install / installed app startup / uninstall を確認済み。
- `ORB-PERF-001` は2026-07-06 WindowsQA official partial run `20260706-061348` でBLOCKED。L1は実測済み、L2/L3 Codex laneはpreflight_timeout、D群はNOT_RUN。これはRelease blocker。
- `ORB-GATE-001` は `ORB-PERF-001` 追加前の2026-07-05 strict auditではPASSだったが、現時点では再実行待ち。
- Discord waiverは今回scopeからの明示延期であり、Discord real relayのPASSではない。
- Release承認時は `audit-release-manifest --require-release-pass` を必須にし、`requiredBlocked` / `requiredNotRun` / 未verified blocking bugが1件でもあればFAILにする。
- Release Gate PASS証跡ではrunId固定summaryとrunId固定artifact zipを必須にする。`latest-*` はFAIL/BLOCKED診断証跡または便利用途に限り、PASS承認根拠にしない。

codex-adviser確認:

- 2026-07-05に `codex-adviser` へAT-001の扱いを確認。
- 1回目結論: deterministic mock 30件PASSだけではreal LLM代表FAILを代替してRelease Gateを通してはいけない。
- 2回目結論: WindowsQA official / real GPU / local LLM run `20260705-211538` および最終develop再実行 `20260705-213712` は事前固定 `minPass=8` に対して `passedCount=8/10` のため、`ORB-AT-001` はRelease Gate上PASS扱いで妥当。`affinity-off` / `model-off` はUnsupported planner operationのcoverage gapとしてknown limitation/follow-up管理にし、後出しblockerにしない。

追加確認:

- WindowsQA Serverへlocal LLM provisionを追加し、Ollama `qwen2.5:3b-instruct` を `OLLAMA_LLM_LIBRARY=vulkan` で起動。GPU証跡 `requestedLibrary=vulkan`, `hasVulkanLog=true`, `hasOffloadLog=true` を保存。CPU推論代替は使っていない。
- WindowsQA runnerにinteractive WDIO task startup no-output guardを追加。対話タスクがログ/evidenceを出さずに待ち続ける場合は、task状態とスクリーンショットを証跡化してFAILにする。

次に実行する順序:

1. `ORB-PERF-001` のBLOCKEDを解消する。Producer承認後、WindowsQAのCodex CLI認証を設定し、L2/L3 laneを実行する。
2. L1失敗原因をプロダクト/fixture/採点に切り分け、必要な修正を行って同じfixtureで再測定する。
3. D群route5/6の実アプリ接続を実装し、ORB-PERF-001第2回officialを完了する。
4. `ORB-GATE-001` strict auditを再実行する。

## 現状サマリ

テスト体系は新ルールへ移行済み。  
現時点では、Discord real relayを明示scope外waiverにしたうえで、Release Gate required項目はPASS済み。

| Category | Result | Gate | Notes |
|---|---|---|---|
| Feature process rules | UPDATED | required | Feature Intake / Done Definition / risk-based gateを追加 |
| Test taxonomy | UPDATED | required | Level / Runner / Environment / Route / Gate / Diagnostic を分離 |
| Test matrix | UPDATED | required | ソース棚卸し後、App runtime / external Apps / Agent collaboration / Remote / Memory / Auth系を追加 |
| Test inventory | UPDATED | required | 既存Vitest/WDIO/Cargo/Python e2e/scriptsと主要ソース領域を代表保証項目へ紐づけ |
| Bug regression ledger | UPDATED | required | Producer/QA指摘の重要不具合22件を `test_id` に紐づけ。release blockingな未検証不具合はRelease Gateを止める。2026-07-04 codex-adviser確認後、正本昇格ルール、状態遷移、AI実行のlimitations記録を追加 |
| Harness policy | PASS | required | `ORB-STATIC-002`: reset marker、direct/mock拒否、oribis-tool/operation拒否、DOM chat許可を確認 |
| AI-native static policy | PASS | required | `ORB-STATIC-003`: 固定語録ルーター禁止シンボル0件、`coreAppToolValidation.test.ts` 7件PASS |
| App Runtime / Workbench supporting | PASS | supporting | `ORB-UT-001` / `ORB-IT-001`: combined Vitest 7 files / 71 tests PASS |
| Worker Core supporting | PASS | supporting | `ORB-UT-002`: Worker Core Vitest 18 files / 109 tests PASS |
| Scene Runtime supporting | PASS | supporting | `ORB-UT-003`: Scene Runtime Vitest 10 files / 123 tests PASS |
| Anima/TTS supporting | PASS | supporting | `ORB-UT-004`: TTS Vitest 2 files / 14 tests PASS、Cargo 17 passed / 16 ignored |
| Settings/Anima App supporting | PASS | supporting | `ORB-IT-002`: Settings/Anima Vitest 4 files / 44 tests PASS |
| App Runtime integration supporting | PASS | supporting | `ORB-IT-004` / `ORB-IT-006`: App Runtime Vitest 10 files / 99 tests PASS、Cargo `app_runtime::` 204 passed |
| External Service Apps supporting | PASS | supporting | `ORB-IT-005`: manifest static audit 9 Apps PASS、Vitest 2 files / 15 tests PASS |
| Tauri/Rust bridge supporting | PASS | supporting | `ORB-SIT-004`: Cargo integration tests 2202 passed / 42 ignored |
| Agent Server / Collaboration supporting | PASS | supporting | `ORB-SIT-005`: targeted Cargo filters PASS: agent_server 50、agent_collaboration 62、agent_routing 8 |
| Remote / Web Remote / Auth supporting | PASS | supporting | `ORB-SIT-006`: targeted Cargo filters PASS: remote 5、auth 40。totp filter matched 0 |
| Anima Memory / Retrieval supporting | PASS | supporting | `ORB-SIT-007`: targeted Cargo filters PASS: memory 62、retrieval 46/1 ignored、consolidation 44 |
| Auth / License / Subscription supporting | PASS_WITH_LIMITATION | supporting | `ORB-SIT-008`: subscription 6、kimi 1 passed。GUI/secret実認証はWindowsQA/ATに残す |
| Prompt / Skills / Templates supporting | PASS | supporting | `ORB-SIT-009`: skill 6、template 9、Prompts/Skills Vitest 2 files / 26 tests PASS |
| Recording / Scheduler supporting | PASS | supporting | `ORB-SIT-010`: recording 7、scheduler 21 passed |
| AI-native UI supporting | PASS | supporting | `ORB-IT-003`: WDIO real GPU/WSLg route 1 spec / 1 test PASS |
| Anima chat metadata regression | PASS_WITH_LIMITATION | required bug regression | `ORB-BUG-017`: WindowsQA official / commit `6f08c523c045d82afc8c7a9d45305883e9dcf8ae`。実チャット送信経路で `[好感度: ...]` が表示本文へ漏れないことを確認。音声読み上げの実出力確認は `ORB-AT-005` に残す |
| AI-native App Operation official | PASS | required | `ORB-AT-001` / `ORB-BUG-018`: 決定的mock Anima応答でApp tool invoke 30件PASS。2026-07-05 WindowsQA official run `20260705-213712` / commit `b4601967900a4898d959b75bf4c8f78a92fdadfa` のreal LLM代表確認はOllama Vulkan GPU offloadで `passedCount=8/10`, `minPass=8` を満たしPASS。`affinity-off` / `model-off` はknown limitation/follow-up |
| WebViewer AI-native official | PASS | required | `ORB-SIT-003` / `ORB-AT-004`: WindowsQA official / commit `96f5943445452f5988fc7ee7cacc4eef88681150`。実チャット送信からWebViewer URL表示、localhostページ読取、automation結果取得、WDIO個別PNG/JSON保存 |
| Discord Relay surface closure | DEFERRED_BY_WAIVER | deferred | `ORB-BUG-019`: local-linuxで旧Worker Core outbox queue導線をDeveloper Console/CommandRegistry/TypingScript DSL/RootShellから削除確認。実Discord送受信/queue metricsはDiscord環境未準備のためProducer指示で今回scopeから延期。Producerのwaiver受容判断は保留 |
| Discord Relay supporting recheck | DEFERRED_BY_WAIVER | deferred | `ORB-SIT-002`: `cargo test agent_discord` 35 passed、Discord/outbox関連Vitest 9 passed。実Discord送受信とqueue metricsはwaiver `WAIVER-20260704-DISCORD-ENV-NOT-PREPARED` により今回scope外。PASS扱いにはしない |
| Static smoke | PASS | required | `ORB-STATIC-001`: WindowsQA official / run `20260704-034448`。typecheck / targeted Vitest / cargo-check / frontend-build / tauri-debug-build PASS |
| WindowsQA official smoke attempt | ABORTED | required attempt | `20260703-184522`: QA-ref `608e1258b14a04a69318a95b8ed83e74351cfbb4`で開始。clean checkout / pnpm install / typecheck / targeted Vitest通過後、cargo check中にProducer指示で中断。公式PASS扱いにしない |
| Startup/Stage WindowsQA official | PASS_WITH_WARNINGS | required | `ORB-ST-001` / `ORB-ST-003`: WindowsQA official / run `20260704-034448`。cleanChecks/processChecks/WDIO PASS。desktop screenshotのみwarn |
| Onboarding WindowsQA official | PASS_WITH_WARNINGS | required | `ORB-ST-002`: WindowsQA official / run `20260704-002031`。Anima VRM loaded、idle pose、Workbench/terminal/debug UI非表示。desktop screenshotのみwarn |
| Workbench/WebViewer UI official | PASS_WITH_WARNINGS | required | `ORB-ST-004` / `ORB-ST-006`: WindowsQA official / run `20260704-004932`。default layout、Scene resize aspect、WebViewer empty-openをWDIO PNG/JSONで確認。desktop screenshotのみwarn |
| Console/Worker Activity UI official | PASS_WITH_WARNINGS | required | `ORB-ST-005`: WindowsQA official run `20260704-202324` / commit `bb6561b3a7602304260d1dbc5cbc2757935081eb`。Console/Log default layout、Workers Activity表示、不要なJobs/Tasks/Queue分散タブなしを確認。desktop screenshotのみwarn |
| Settings/Anima UX official | PASS_WITH_WARNINGS | required | `ORB-AT-002`: WindowsQA official runs `20260704-202324`, `20260704-202948` / commit `bb6561b3a7602304260d1dbc5cbc2757935081eb`。Settings分割、白パネルなし、Prompts統合、Onboarding保存値 `characterName=anima` / `userName=User` / VRM pathを確認。desktop screenshotのみwarn |
| Worker Chat UX official | PASS_WITH_WARNINGS | required | `ORB-SIT-001` / `ORB-AT-003`: WindowsQA official run `20260704-200036` / commit `bb6561b3a7602304260d1dbc5cbc2757935081eb`。Worker terminal stream、worker_output本文、Anima入力欄非存在、送信後input空を確認。desktop screenshotのみwarn |
| TTS voice acceptance official | PASS_WITH_WARNINGS | required | `ORB-AT-005`: WindowsQA official run `20260705-111317` / commit `09c7c972f5badc4859e08a3a8b40a588b32d6321`。VOICEVOX/Kokoro資産provision、typecheck、targeted Vitest、cargo-check、frontend-build、tauri-debug-build、WDIO `tts-voice-playback.spec.ts` 6件PASS。desktop screenshotのみwarn |
| Release Packaging official | PASS | required | `ORB-GATE-002`: WindowsQA official run `20260705-234741` / commit `48ea7fd64c5c59833962d6e1755d0d930d39764e`。release build、VOICEVOX/Kokoro bundle check、MSI/NSIS生成、MSI install、installed exe startup screenshot、uninstall/cleanup PASS |
| Coding Agent Performance official | BLOCKED | required | `ORB-PERF-001`: WindowsQA official partial run `20260706-061348` / commit `4eb43ff2c2eeee001597db5f351f140e3e86bc3f`。L1-instant は11/14件成功、L1-job は12/14件成功。L2/L3 Codex laneはpreflight_timeoutでBLOCKED、D群はNOT_RUN。L1にもA2/A5/B3/C2/C5/R2等の品質失敗が残る |
| Frontend full Vitest | PASS | supporting | `vitest.config.ts` でNode専用QA testをVitest対象から除外。`rtk pnpm vitest run --reporter=dot`: 133 files / 1590 tests PASS |
| WindowsQA Server remaining AT/ST | PASS | required | Discord waiverを除く残required AT/STは解消済み。`ORB-AT-001` / `ORB-AT-005` / `ORB-GATE-002` はWindowsQA officialで解消済み |
| local-windows devUrl diagnostic | BLOCKED_DIAGNOSTIC | diagnostic | local-windowsで`localhost:1420` timeout/black screenを確認。AT/STの代替にしない |
| Release Gate | NOT_RUN | required | `ORB-GATE-001`: `ORB-PERF-001` 追加後は未再実行。現manifestは requiredBlocked=`ORB-PERF-001`、requiredNotRun=`ORB-GATE-001` |

WindowsQA connectivity latest:

- 2026-07-04 20:00 JST Worker Chat official:
  - WindowsQA host復旧後、clean clone `C:\oribis-qa\oribis-official` からRC SHA `bb6561b3a7602304260d1dbc5cbc2757935081eb` をcheckoutして実行。
  - `tests/worker-chat.spec.ts`: 4 tests PASS。
  - run `20260704-200036`: summary status `pass`, `official=true`, `sourceMode=git`, `requestedCommit=resolvedCommit=bb6561b3a7602304260d1dbc5cbc2757935081eb`, `skippedSteps=[]`。
  - `desktop-screenshot` stepのみ `warn`。WDIO個別PNG/JSONは保存済み。
  - `ORB-SIT-001` / `ORB-AT-003` は `PASS_WITH_WARNINGS`、`ORB-BUG-015/016` は `verified` に更新。

- 2026-07-04 19:54 JST recheck:
  - WSL SSH to `admin@100.64.6.42`: timeout。
  - Windows `Test-NetConnection 100.64.6.42 -Port 22`: `TcpTestSucceeded=false`, `PingSucceeded=false`, interface `Tailscale`。
  - 結論: この時点ではWindowsQA host offline。後続の20:00 Worker Chat official runで `ORB-SIT-001` / `ORB-AT-003` は解消済み。
- 2026-07-04 19:09 JST recheck:
  - WSL SSH to `admin@100.64.6.42`: timeout。
  - Windows `Test-NetConnection 100.64.6.42 -Port 22`: `TcpTestSucceeded=false`, `PingSucceeded=false`, interface `Tailscale`。
  - Windows `tailscale status --json`: peer `DESKTOP-TEST001` / `100.64.6.42` is `Online=false`, `Active=true`, `LastSeen=2026-07-03T18:59:08.1Z`。
  - 結論: この時点ではWindowsQA host offline。Discord `ORB-SIT-002` は環境未準備のため今回scopeから延期。
- 19:54時点の `ssh -i ~/.ssh/oribis_windows_qa -o BatchMode=yes -o ConnectTimeout=8 admin@100.64.6.42 "echo windowsqa-ok"`: timeout。20:00のWorker Chat official runでは接続復旧済み。
- latest QA ref for pre-RC diagnostic/supporting run: `e9c0307fc10b6d7f9fb401c89a391418bc88c09e` (`refs/qa/qa-20260704-qa-audit-script-and-blocked-status`)。required公式runはRC SHA `8a70b3ef0a61fb67889ae15b7ca068b2eff9071f` で実行する。
- RC candidate SHA: `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e` (`origin/develop`)。WindowsQA公式runはこのSHAで実行する。
- Testing docs commit: `8a99ff386c79994ef065d8881def65fad058830a` (`oribis-docs/main`)。
- `ip route get 100.64.6.42`: `dev eth0 src 100.121.14.20`。
- `ping -c 3 -W 2 100.64.6.42`: 0 received / 100% packet loss。
- 19:54時点のTCP 22 probe: timeout。20:00のWorker Chat official runでは接続復旧済み。
- 結論: WindowsQA hostへの到達性がなく、アプリ起動前にBLOCKED。Xvfb/CPU fallbackは使用していない。

Latest local gate audit:

- 2026-07-04 20:00 JST rerun after Worker Chat official evidence update:
  - `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。
  - `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: PASS。
  - `rtk pnpm run test:qa-audit`: PASS。4 Node `node:test` tests。
  - `nonVerifiedBlockingBugs=[]`。
  - `requiredBlocked=[ORB-AT-001, ORB-AT-005, ORB-GATE-002]`（当時値。2026-07-05 `ORB-AT-005` / `ORB-GATE-002` 解消後の現在値は `requiredBlocked=[ORB-AT-001]`）。
  - `requiredNotRun=[ORB-GATE-001]`。
  - 結論: Manifest/bug evidence auditは通過。Release Gateはrequired未完了項目が残るため未達。

- 2026-07-04 19:54 JST rerun after Discord waiver:
  - `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。
  - `rtk pnpm run test:qa-audit`: PASS。4 Node `node:test` tests。
  - `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: expected FAIL。
  - 当時のstrict failures: `ORB-BUG-015/016` evidence lacks `path + sha256`; `ORB-BUG-015/016` are still not `verified`。後続の20:00 Worker Chat official runで解消済み。
  - 当時の`requiredBlocked=[ORB-AT-001, ORB-SIT-001, ORB-ST-005, ORB-AT-002, ORB-AT-003, ORB-AT-005, ORB-GATE-002]`。後続の20:00 Worker Chat official run後は `ORB-SIT-001` / `ORB-AT-003` を除外。
  - Discord `ORB-SIT-002` / `ORB-BUG-019` はwaiver `WAIVER-20260704-DISCORD-ENV-NOT-PREPARED` により今回scope外。PASS扱いではない。
- 2026-07-04 19:09 JST rerun:
  - `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。
  - `rtk pnpm run test:qa-audit`: PASS。4 Node `node:test` tests。
  - `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: expected FAIL。
  - strict failures: `ORB-BUG-015/016` evidence lacks `path + sha256`; `ORB-BUG-015/016` are still not `verified`。`ORB-BUG-019` はDiscord環境未準備のwaiverで今回scope外。
  - 結論: manifest/QA監査処理は正常。Release Gateは未達。
- `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。
- `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files` summary now separates `requiredNotRun=["ORB-GATE-001"]` from host-caused `requiredBlocked`。2026-07-05 `ORB-AT-005` / `ORB-GATE-002` 解消後の残required blockedは `ORB-AT-001`。`ORB-SIT-002` はwaiverにより今回scope外。
- latest rerun: `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。`tests=32`, `requiredTestIds=19`, `failures=[]`。legacy `testItems` は廃止済み。
- 注意: このPASSはmanifest整合性のPASSであり、Release Gate PASSではない。`requiredBlocked` と未verified release-blocking bugが残るため、現状態は「RC候補作成可、Release承認不可」。
- `rtk pnpm run test:qa-audit`: PASS。4 Node `node:test` QA audit tests。Vitest除外後も監査ツールの回帰テストを明示実行する。
- latest rerun: `rtk pnpm run test:qa-audit`: PASS。4 tests。
- `node --check scripts/qa/audit-release-manifest.mjs && node --check scripts/qa/audit-windows-qa-summary.mjs`: PASS。
- `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit --pretty false`: PASS。
- latest rerun: `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit --pretty false`: PASS。
- `bash -n scripts/qa/invoke-windows-qa.sh scripts/qa/push-qa-ref.sh scripts/qa/invoke-windows-interactive-qa.sh scripts/run-live-stage-chat-harness.sh scripts/run-wdio-tests.sh scripts/run-wdio-tests-onboarding.sh`: PASS。
- PowerShell parser check for `run-windows-smoke.ps1`, `run-windows-packaging.ps1`, `interactive-capture.ps1`, `register-interactive-tasks.ps1`: PASS。
- `test-plan.md`: `BLOCKED_ON_WINDOWSQA` を `BLOCKED` の原因付きサブ表記として定義済み。required PASS扱いにしない。
- `rtk pnpm vitest run src/workbench/CoreAppWorkbench.test.tsx --testNamePattern "legacy|core:project|core:remote|migrate|persisted layout" --reporter=dot`: PASS。1 file / 8 tests PASS / 7 skipped。旧 `core:project` / `core:remote` layoutがAnimaへ誤復元されずdropされることを確認。
- `rtk pnpm run typecheck`: PASS。
- `rtk pnpm vitest run --reporter=dot`: PASS。133 files / 1590 tests。既存のReact `act(...)` warningあり。
- latest targeted rerun: `rtk pnpm vitest run src/workbench/coreAppToolValidation.test.ts src/apps/__tests__/HostAPI.test.ts src/apps/__tests__/e2e.test.ts src/workbench/CoreAppWorkbench.test.tsx --reporter=dot`: PASS。4 files / 54 tests。
- `node --test scripts/qa/audit-windows-qa-summary.test.mjs`: PASS。4 tests。
- `rtk cargo check --manifest-path src-tauri/Cargo.toml`: PASS with existing warnings, 0 errors。
- `rtk cargo test --manifest-path src-tauri/Cargo.toml`: PASS。2204 passed / 42 ignored。
- `rtk pnpm vite build`: PASS。既存のlarge chunk警告あり、build exit code 0。
- `bash -n scripts/qa/invoke-windows-qa.sh scripts/qa/push-qa-ref.sh scripts/qa/invoke-windows-interactive-qa.sh scripts/run-live-stage-chat-harness.sh scripts/run-wdio-tests.sh scripts/run-wdio-tests-onboarding.sh`: PASS。
- PowerShell parser check for `run-windows-smoke.ps1`, `run-windows-packaging.ps1`, `interactive-capture.ps1`, `register-interactive-tasks.ps1`: PASS。
- `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: expected FAIL。
- latest strict rerun: `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: PASS。`ORB-BUG-015/016` はWorker Chat official evidenceでverified済み。`ORB-BUG-019` は今回scope外。
- strict failures: なし。Release Gate未達理由はrequired未完了項目のみ。
- 結論: `ORB-GATE-001` の監査処理自体は動作。Release Gateは未達。
- 19:54時点のWindowsQA reachability rerun: `ssh -i ~/.ssh/oribis_windows_qa -o BatchMode=yes -o ConnectTimeout=8 admin@100.64.6.42 "echo windowsqa-ok"`: timeout。20:00のWorker Chat official runでは接続復旧済み。
- 19:54時点のWindows host-side check: `Test-NetConnection 100.64.6.42 -Port 22` returned `TcpTestSucceeded=false`, `PingSucceeded=false`, `InterfaceAlias=Tailscale`。`tailscale status --json` では `DESKTOP-TEST001` / `100.64.6.42` が `Online=false`, `Active=true`, `LastSeen=2026-07-03T18:59:08.1Z`。
- RC SHA確定後のWorker Chat official run: WSL SSH経由でWindowsQAへ接続し、`ORB-SIT-001` / `ORB-AT-003` は実行済み。残るWindowsQA required項目は別途実行が必要。
- `ORB-STATIC-003` latest source policy check:
  - `rtk rg -n "coreAppNaturalLanguage|naturalLanguageHints|includesAny|NEGATED_ACTION_TERMS|低め|ピッチ|TTSのピッチ|exact example|語録" src e2e scripts src-tauri --glob '!node_modules'`
  - 実装側の固定語録ルーター禁止シンボルは0件。ヒットは `e2e/wdio/tests/app-ai-native-route-acceptance.spec.ts` の受け入れテスト入力文1件のみ。
  - `rtk pnpm vitest run src/workbench/coreAppToolValidation.test.ts src/apps/__tests__/HostAPI.test.ts src/apps/__tests__/e2e.test.ts --reporter=dot`: 3 files / 39 tests PASS。
  - `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit --pretty false`: PASS。
- latest supporting regression:
  - `rtk pnpm vitest run src/scene-runtime/*.test.ts src/components/BabylonAvatarViewer.test.tsx src/components/BabylonStageViewer.test.ts --reporter=dot`: 10 files / 124 tests PASS。既存のReact `act(...)` warningあり。
  - latest rerun: `rtk pnpm vitest run src/scene-runtime/*.test.ts src/components/BabylonAvatarViewer.test.tsx src/components/BabylonStageViewer.test.ts --reporter=dot`: PASS。10 files / 124 tests。既存のReact `act(...)` warningあり。
  - latest onboarding/avatar targeted rerun: `rtk pnpm vitest run src/RootShell.onboarding.test.tsx src/components/BabylonAvatarViewer.test.tsx --testNamePattern "onboarding|T-pose|idle|VRM|avatar|scene" --reporter=dot`: PASS。2 files / 22 tests PASS / 59 skipped。既存のReact `act(...)` warningあり。
  - latest Console/Worker Activity rerun: `rtk pnpm vitest run src/components/DeveloperConsole.test.tsx src/components/__tests__/TaskJobView.test.tsx src/components/__tests__/ActionAuditPanel.test.tsx --reporter=dot`: PASS。3 files / 43 tests。既存のReact `act(...)` warningと意図的なgeneric error logあり。
  - `rtk pnpm vitest run src/worker-core/*.test.ts --reporter=dot`: 18 files / 109 tests PASS。
  - `rtk pnpm vitest run src/apps/__tests__/*.test.ts src/workbench/coreAppToolValidation.test.ts --reporter=dot`: 10 files / 83 tests PASS。invoke bridgeの既存stderrログあり。
  - `rtk cargo test test_sanitize_spoken_text_removes_internal_affinity_markers --manifest-path src-tauri/Cargo.toml`: PASS。
  - latest rerun: `rtk cargo test test_sanitize_spoken_text_removes_internal_affinity_markers --manifest-path src-tauri/Cargo.toml`: PASS。1 passed / 2245 filtered out。
  - `rtk cargo test tts --manifest-path src-tauri/Cargo.toml`: 81 passed / 21 ignored。
  - `rtk pnpm vitest run src/RootShell.chat.test.tsx src/lib/readableTtsText.test.ts --testNamePattern "好感度|read|TTS|code blocks|assistant" --reporter=dot`: 2 tests PASS / 46 skipped。
  - latest rerun: `rtk pnpm vitest run src/RootShell.chat.test.tsx src/lib/readableTtsText.test.ts --testNamePattern "好感度|read|TTS|code blocks|assistant" --reporter=dot`: PASS。2 tests PASS / 46 skipped。
  - latest Worker Chat/Terminal rerun: `rtk pnpm vitest run src/hooks/useWorkerChatSessions.test.ts src/RootShell.chat.test.tsx src/RootShell.terminal.test.tsx --testNamePattern "T19b2w|T19b2|T19b3|final answer|PTY dispatch" --reporter=dot`: PASS。3 files / 8 tests PASS / 73 skipped。既存のReact `act(...)` warningあり、assertはPASS。
  - `rtk pnpm run typecheck`: PASS。
  - `rtk cargo check --manifest-path src-tauri/Cargo.toml`: PASS with existing warnings, 0 errors。
  - `rtk pnpm vite build`: PASS。既存のdynamic import / large chunk警告あり。
- WindowsQA connectivity:
  - WSL SSH to `admin@100.64.6.42`: timeout。
  - Windows `Test-NetConnection 100.64.6.42 -Port 22`: `TcpTestSucceeded=false`, `PingSucceeded=false`, interface `Tailscale`。
- Windows `tailscale status --json`: local `DESKTOP-DEV001` is `BackendState=Running`; peer `DESKTOP-TEST001` / `100.64.6.42` is `Online=false`。
- Windows `tailscale ping desktop-test001.tail68ea5e.ts.net`: timeout。
- 2026-07-04 15:43 JST recheck:
  - WSL SSH to `admin@100.64.6.42`: timeout。
  - Windows `Test-NetConnection 100.64.6.42 -Port 22`: `TcpTestSucceeded=false`, `PingSucceeded=false`, interface `Tailscale`。
  - Windows `tailscale status --json`: peer `DESKTOP-TEST001` / `100.64.6.42` is still `Online=false`。
- 結論: WindowsQA host側がTailscale offlineまたは本体停止。Xvfb/CPU/local substituteは使用していない。

## 実行済み

### Test method / bug regression governance review

2026-07-04にcodex-adviserへ、Producer/QA指摘の不具合修正テストを正本 `test-matrix.md` と分けるべきか確認した。

結論:

- `test-matrix.md` をリリース可否判断の正本、`bug-regressions.md` を個別不具合の回帰台帳にする方式は妥当。
- 不具合修正テストは独立フェーズにせず、個別不具合は `bug-regressions.md`、恒久保証すべき観点は `test-matrix.md` へ昇格する。
- Release Gateでは required `test_id` のPASSだけでなく、`release_blocking=true` の不具合が全て `verified` であり、必要な正本昇格が反映済みであることを確認する。
- AI/automation実行の証跡には、確認できた範囲と確認できなかった範囲を `limitations` として残す。

反映:

- `testing/README.md`: 不具合修正テストの位置づけ、正本昇格、AI実行証跡の必須項目を追記。
- `bug-regressions.md`: `reopened` / `waived`、`root_cause_summary`、`regression_risk`、`requires_test_matrix_update`、`test_matrix_update_summary`、`verification_evidence`、`limitations` を追加。
- `manifest.json`: `ORB-SIT-002` と `ORB-AT-001` のID取り違えを修正し、JSON parse / 件数検査を実施。
- `scripts/qa/audit-release-manifest.mjs`: Release Gate manifest構造監査を追加。通常モードで構造検査、`--require-bug-evidence-sha` でbug証跡の `path + sha256` pin留めを必須化。

sysdev-2第三者確認:

- 構造は続行可。
- must-fix 1: `bug-regressions.md` の実データが必須フィールドを持っておらず、ルールが執行不能。
- must-fix 2: `manifest.json` に機械可読なbug regressionセクションがなく、GATE-001が人力目視になる。
- must-fix 3: `ORB-BUG-018` の `verified` が、紐づく `ORB-AT-001` の `PASS_WITH_LIMITATION` と字義上矛盾。

対応:

- `bug-regressions.md` に `Required Detail Records` を追加し、22件すべてについて `root_cause_summary` / `regression_risk` / `requires_test_matrix_update` / `test_matrix_update_summary` / `verification_evidence` / `limitations` を記録。
- `manifest.json` に `bugRegressions` 22件と `requiredTestIds` を追加。
- `manifest.json` の `bugRegressionRules` を新しい必須フィールドに合わせて更新。
- `verified` の定義を、バグ自身の再現条件に対する証跡で判定できるように明確化。正本 `test_id` 全体の未達はRelease Gate上で別途残す。
- 機械検査: `manifest=json ok`, `bugRegressions=22`, `requiredTestIds=19` を確認。2026-07-04更新後は、host起因の未実行を `requiredBlocked`、Release Gate本体未実行を `requiredNotRun` として分離。
- sysdev-2再確認: must-fix 3件は解消済み。追加指摘として `ORB-BUG-015/016` の台帳要約statusとmanifest statusのドリフトを検出。これに対し、台帳要約表も `fixed_pending_verification` へ更新済み。
- `bugRegressions.verification_evidence` は、実在する既存証跡について `path + sha256` 形式へpin留め済み。`ORB-BUG-015/016` は20:00 Worker Chat official runで `verified` に更新済み。
- sysdev-2最終確認: bug台帳系のレビュー指摘はクローズ。`test-plan.md` のGATE-001判定ルールに、`bugRegressions` の `release_blocking=true` 全件について `status=verified` と `path + sha256` 証跡pin留めを確認する項目を追加。
- 2026-07-04 sysdev-2追加確認: Vitestから `scripts/qa/**/*.test.mjs` を除外し、Node専用QA監査テストを `pnpm run test:qa-audit` へ分離する判断は妥当。ただしinventory登録が必須のため、`test-inventory.md` の `ORB-GATE-001` に `pnpm run test:qa-audit` を追加済み。
- 2026-07-04 sysdev-2追加確認: WindowsQA host起因の実行不可は `NOT_RUN` ではなく `BLOCKED_ON_WINDOWSQA` として記録するのが妥当。2026-07-05 `ORB-AT-005` / `ORB-GATE-002` 解消後、`manifest.json` は `requiredNotRun=["ORB-GATE-001"]` と `requiredBlocked=[ORB-AT-001]` に分離済み。Discord `ORB-SIT-002` はwaiverで今回scope外。

追加検証:

- `manifest.json` parse PASS。
- `ORB-AT-001` / `ORB-SIT-002` の出現数と未完了分類を検査しPASS。
- 固定語録ルーター禁止シンボル確認: `coreAppNaturalLanguage` / `naturalLanguageHints` / `NEGATED_ACTION_TERMS` / `includesAny(` は実装側0件。残存する自然文はWDIO/Vitestの入力文。
- `rtk pnpm run typecheck`: PASS。
- `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit --pretty false`: PASS。
- `rtk pnpm vitest run src/workbench/coreAppToolValidation.test.ts --reporter=dot`: 7 tests PASS。
- `rtk pnpm vitest run src/RootShell.chat.test.tsx --testNamePattern "T19b2w|T19b2|T19b3" --reporter=dot`: 4 tests PASS / 42 skipped。
- `rtk pnpm vitest run src/RootShell.terminal.test.tsx --testNamePattern "final answer|PTY dispatch" --reporter=dot`: 2 tests PASS / 23 skipped。既存のReact `act(...)` warningあり。
- `powershell.exe ... Parser::ParseFile("scripts/qa/run-windows-packaging.ps1")`: PASS。
- `powershell.exe ... Parser::ParseFile("scripts/qa/run-windows-smoke.ps1")`: PASS。
- `bash -n scripts/qa/invoke-windows-qa.sh scripts/qa/push-qa-ref.sh scripts/qa/invoke-windows-interactive-qa.sh`: PASS。
- `node scripts/qa/audit-release-manifest.mjs`: PASS。`bugRegressions=22`, `requiredTestIds=19`, `nonVerifiedBlockingBugs=[]`。
- `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha`: PASS。Worker Chat official証跡反映後、release-blocking bugの証跡SHA不足はなし。
- `node --check scripts/qa/audit-release-manifest.mjs`: PASS。
- `run-windows-smoke.ps1` summaryへ `mode`, `commit`, `systemSnapshot` を追加し、公式証跡の自己記述を強化。
- `run-windows-packaging.ps1` summaryへ `skippedSteps` を追加し、公式/診断実行の機械判定に必要なfieldを揃えた。
- `scripts/qa/audit-windows-qa-summary.mjs` を追加。WindowsQA summary登録前に `official`, `sourceMode`, `requestedCommit`, `resolvedCommit`, `cleanChecks`, `skippedSteps` を機械監査する。
- codex-adviser確認: summary監査方針は妥当。追加で `schemaVersion`, `qaProfile`, `runnerScriptSha256`, legacy warning, negative testを推奨。
- `run-windows-smoke.ps1` / `run-windows-packaging.ps1` summaryへ `schemaVersion`, `qaProfile`, `runnerScriptSha256` を追加。
- `audit-windows-qa-summary.mjs` は既存legacy summaryの `mode/schemaVersion/qaProfile/runnerScriptSha256` 欠落をwarning扱いにし、新規summaryではfield出力される。
- `scripts/qa/audit-windows-qa-summary.test.mjs` を追加し、BOM付きlegacy summary、skippedSteps、commit不一致、packaging必須field欠落のnegative testを追加。
- `manifest.json` の `officialSummaryFields` を新summary field定義へ更新。
- `test-plan.md` にWindowsQA SSH timeout時の復旧Runbookを追記。復旧後の順序は Worker Chat -> real LLM App操作 -> Packaging Gate -> Onboarding/Workbench。
- `audit-release-manifest.mjs` に `--verify-evidence-files` を追加。bug証跡のpath実在とsha256一致を機械確認する。
- `manifest.json` の正本は `tests` 単独。legacyの `testItems` は廃止し、残存時はschema violationとしてRelease Gate監査をFAILにする。後勝ちmergeロジックは廃止済み。
- 検証:
- `node --test scripts/qa/audit-windows-qa-summary.test.mjs`: 4 tests PASS。
- `powershell.exe ... Parser::ParseFile("scripts/qa/run-windows-smoke.ps1")`: PASS。
- `powershell.exe ... Parser::ParseFile("scripts/qa/run-windows-packaging.ps1")`: PASS。
- `node scripts/qa/audit-release-manifest.mjs`: PASS。
- `node scripts/qa/audit-release-manifest.mjs --verify-evidence-files`: PASS。
  - `node scripts/qa/audit-release-manifest.mjs --require-bug-evidence-sha --verify-evidence-files`: PASS。
  - required項目の実効状態確認: `ORB-ST-001` は `PASS_WITH_SCREENSHOT_WARN`、`ORB-ST-003` は `PASS_WITH_LIMITATION`、`ORB-SIT-001` / `ORB-AT-003` / `ORB-ST-005` / `ORB-AT-002` は `PASS_WITH_WARNINGS` として認識。`ORB-ST-003` の受容理由は、オンボードScene単体とStage/Studio境界をofficial runで保証し、Workbench Scene App全体を `ORB-ST-004` と `ORB-BUG-006/007` で別保証するため。Discord `ORB-SIT-002` real relayはwaiverで今回scope外。
- 既存公式summaryの監査:
  - `/mnt/c/Users/admin/Pictures/agante-projects/sysdev/oribis-startup-stage-guards-20260704-0345/latest-summary.json`: PASS。
  - `/mnt/c/Users/admin/Pictures/agante-projects/sysdev/oribis-core-workbench-scene-input-20260704-005006/latest-summary.json`: PASS。

### ORB-STATIC-001 diagnostic smoke

2026-07-03 16:11:29 JSTにlocal-windows source snapshot `C:\oribis-qa\oribis` で以下を実行。

- `pnpm install --frozen-lockfile`
- `pnpm run typecheck`
- targeted Vitest
- `cargo check`
- `pnpm vite build`

結果: PASS。  
ただし、`SkipWdio` / `SkipScreenshot` で実行したため、Windows実画面AT/STの証跡ではない。

証跡:

- `evidence/STATIC-BUILD-001/windows-smoke-summary.json`
- `evidence/STATIC-BUILD-001/windows-smoke.log`
- `evidence/STATIC-BUILD-001/windows-system.json`
- `evidence/STATIC-BUILD-001/windows-smoke.zip`

### ORB-DIAG-001 local-windows devUrl

local-windowsでTauri debug exeを起動し、WebViewが `localhost:1420` に接続できずtimeout/black screenになることを確認。  
これはdiagnosticであり、AT/ST/Release Gateの代替ではない。

### ORB-STATIC-001 WindowsQA official smoke attempt

2026-07-03 18:45:22 JSTにWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でQA-ref `608e1258b14a04a69318a95b8ed83e74351cfbb4` を指定して公式smokeを開始。

結果: ABORTED。  
clean checkout、`pnpm install --frozen-lockfile`、typecheck、targeted Vitestまでは通過したが、`cargo check`中にProducer指示で実行中断。完走していないため、`ORB-STATIC-001` の公式PASSには計上しない。

確認事項:

- summary runId: `20260703-184522`
- summary status: `fail`
- exit: invoke側 `255`
- latest zipは古いrunId `20260703-180952` を指していたため正規証跡として無効
- 残留していた旧repo `C:\oribis-qa\oribis` のVite/node processを停止済み

証跡:

- `evidence/ORB-STATIC-001/windowsqa-official-smoke/latest-summary.json`
- `evidence/ORB-STATIC-001/windowsqa-official-smoke/summary-20260703-184522.json`

### ORB-STATIC-001 WindowsQA official smoke pass

2026-07-04 03:44:48 JSTにWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でQA-ref `d37b7b02184b227f595bbf01af913d0b48dec4cd` を指定して公式smokeを完走。

結果: PASS。

確認事項:

- summary runId: `20260704-034448`
- `official=true`
- `sourceMode=git`
- `requestedCommit` / `resolvedCommit` 一致
- `cleanChecks`: repo-check前 / git-update後ともclean
- `skippedSteps=[]`
- typecheck / targeted-vitest / cargo-check / frontend-build / tauri-debug-build PASS
- WDIO onboarding scene-only PASS
- desktop screenshotのみWindows API警告

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\latest-summary.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\20260704-034448.zip`
- summary sha256: `ec49875b5cc467fff800333c5772c68b347be3ffd08affe05e23491abe061f56`
- artifact sha256: `6fa48ce7f0dd78b98bfb1508a2ed2ded92c20cc0c0c4d3e9070351378ae38e90`

### ORB-STATIC-002 harness policy

2026-07-03にlocal-linuxでpolicy function checkを実行。

確認内容:

- reset markerなしの通常送信を拒否
- `--worker-repo` direct pathを明示envなしで拒否
- reset marker後のDOM chat textを許可
- chat text内の `<oribis-tool>` を拒否
- command file内の `operation/request` を拒否

結果: PASS。

証跡:

- `evidence/ORB-STATIC-002/result.json`

### ORB-STATIC-003 AI-native static policy

2026-07-03にlocal-linuxで以下を実行。

- `rtk rg -n "coreAppNaturalLanguage|naturalLanguageHints|NEGATED_ACTION_TERMS|includesAny\\(" src/workbench src/RootShell.tsx src/apps`
- `rtk pnpm vitest run src/workbench/coreAppToolValidation.test.ts`

結果:

- 禁止シンボル検索: 0件
- Vitest: 1 file passed / 7 tests passed

証跡:

- `evidence/ORB-STATIC-003/result.json`

### ORB-BUG-019 Discord Relay surface closure

2026-07-04にlocal-linuxで、旧Worker Core Discord outbox queue導線が製品表面から到達不能になったことを確認。

実施内容:

- Developer ConsoleからWorker Core Discord Outbox UIを削除
- CommandRegistryから旧outbox command登録を削除
- TypingScript DSLから旧outbox methodを削除し、入力時はblockedにする
- RootShellから旧outbox command実行分岐を削除
- Agent Discord route/deliveryのRustテストを維持

実行:

- `rtk pnpm run typecheck`: PASS
- `rtk pnpm vitest run src/components/DeveloperConsole.test.tsx src/command/typingScriptDsl.test.ts src/command/CommandRegistry.test.ts --reporter=dot`: 3 files / 49 tests PASS
- `rtk cargo test agent_discord --manifest-path src-tauri/Cargo.toml`: 35 passed / 2210 filtered out
- 旧outbox command参照スキャン: 製品表面の参照なし。残存は低レベル内部実装と拒否検証テストのみ。

結果: DEFERRED_BY_WAIVER。
ただし、実Discord送受信、queue metrics、送信失敗時に旧outboxへfallbackしないことのWindowsQA/relay証跡は未取得。Discord環境未準備のため、Producer指示により今回scopeからは `WAIVER-20260704-DISCORD-ENV-NOT-PREPARED` で延期する。これはPASS扱いではない。

証跡:

- `evidence/ORB-BUG-019/result.json`

### ORB-UT-001 / ORB-IT-001 App Runtime / Workbench supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/workbench/coreAppToolValidation.test.ts src/apps/__tests__/toolActionSchema.test.ts src/apps/__tests__/HostAPI.test.ts src/apps/__tests__/invoke.test.ts src/apps/__tests__/EventBus.test.ts src/workbench/CoreAppWorkbench.test.tsx src/workbench/coreAppWindow.test.ts`

結果:

- Vitest: 7 files passed / 71 tests passed

対象:

- `ORB-UT-001`: App schema/tool/policy、Host API、invoke/EventBus、Workbench、App windowの単体寄り確認
- `ORB-IT-001`: Core App Workbench / App windowの結合寄り確認

証跡:

- `evidence/ORB-UT-001/result.json`
- `evidence/ORB-IT-001/result.json`

### ORB-UT-002 Worker Core supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/worker-core/*.test.ts`

結果:

- Vitest: 18 files passed / 109 tests passed

証跡:

- `evidence/ORB-UT-002/result.json`

### ORB-UT-003 Scene Runtime supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/scene-runtime/*.test.ts src/components/BabylonAvatarViewer.test.tsx src/components/BabylonStageViewer.test.ts`

結果:

- Vitest: 10 files passed / 123 tests passed

証跡:

- `evidence/ORB-UT-003/result.json`

### ORB-UT-004 Anima/TTS supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/hooks/useTTS.test.ts src/lib/readableTtsText.test.ts`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml --test tts_smoke --test tts_quality_test --test tts_e2e --test chat_tts_system --test chat_tts_e2e --test kokoro_chat_e2e --test kokoro_integration --test nemo_integration --test kokoro_integration`

結果:

- Vitest: 2 files passed / 14 tests passed
- Cargo tests: 17 passed / 16 ignored / 8 suites

証跡:

- `evidence/ORB-UT-004/result.json`

### ORB-IT-002 Settings/Anima App supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/components/GeneralTab.test.tsx src/components/PromptsTab.test.tsx src/components/AppsTab.test.tsx src/components/AnimaStatusBar.test.tsx`

結果:

- Vitest: 4 files passed / 44 tests passed

証跡:

- `evidence/ORB-IT-002/result.json`

### ORB-IT-004 / ORB-IT-006 App Runtime integration supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk pnpm vitest run src/apps/__tests__/AppSandbox.test.ts src/apps/__tests__/AppSandbox.test.tsx src/apps/__tests__/sdk.test.ts src/apps/__tests__/useAppSystem.test.ts src/apps/__tests__/e2e.test.ts src/apps/__tests__/UIRenderer.test.tsx src/apps/__tests__/toolActionSchema.test.ts src/apps/__tests__/HostAPI.test.ts src/apps/__tests__/EventBus.test.ts src/apps/__tests__/invoke.test.ts`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml app_runtime::`

結果:

- Vitest: 10 files passed / 99 tests passed
- Cargo tests: 204 passed / 2040 filtered out / 24 suites

対象:

- `ORB-IT-004`: App manifest / permission / capability discovery / tool catalog
- `ORB-IT-006`: App runtime / sandbox / package / sidecar / storage / fs / net boundary

証跡:

- `evidence/ORB-IT-004/result.json`
- `evidence/ORB-IT-006/result.json`

### ORB-IT-005 External Service Apps supporting

2026-07-03にlocal-linuxで以下を実行。

- builtin/external App manifest static audit
- `rtk pnpm vitest run src/apps/__tests__/useAppSystem.test.ts src/apps/__tests__/e2e.test.ts`

結果:

- manifest audit: 9 Apps checked / missing required keys 0 / dangerous allowed commands 0
- Vitest: 2 files passed / 15 tests passed

対象App:

- Scene Editor
- Scene Builder
- Animation Creator
- Discord Bridge
- Google Workspace
- GitHub Integration
- Blender Hub
- Work Report
- Debug Panel

証跡:

- `evidence/ORB-IT-005/result.json`

### ORB-SIT-004 Tauri/Rust bridge supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml --tests`

結果:

- Cargo tests: 2202 passed / 42 ignored / 24 suites

証跡:

- `evidence/ORB-SIT-004/result.json`

### ORB-SIT-005 Agent Server / Collaboration supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml agent_server`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml agent_collaboration`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml agent_routing`

結果:

- `agent_server`: 50 passed
- `agent_collaboration`: 62 passed
- `agent_routing`: 8 passed

証跡:

- `evidence/ORB-SIT-005/result.json`

### ORB-SIT-006 Remote / Web Remote / Auth supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml remote`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml totp`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml auth`

結果:

- `remote`: 5 passed
- `totp`: 0 matched / 0 failed
- `auth`: 40 passed

証跡:

- `evidence/ORB-SIT-006/result.json`

### ORB-SIT-007 Anima Memory / Retrieval supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml memory`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml retrieval`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml consolidation`

結果:

- `memory`: 62 passed
- `retrieval`: 46 passed / 1 ignored
- `consolidation`: 44 passed

証跡:

- `evidence/ORB-SIT-007/result.json`

### ORB-SIT-008 Auth / License / Subscription supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml license`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml subscription`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml kimi`

結果:

- `license`: 0 matched / 0 failed
- `subscription`: 6 passed
- `kimi`: 1 passed

制限:

- `commercial-license.spec.ts` / `kimi-oauth-auth.spec.ts` / `anima-openai-subscription-smoke.spec.ts` はWDIO GUI/secret依存のため、local-linux supportingでは実行しない。WindowsQA/ATで扱う。

証跡:

- `evidence/ORB-SIT-008/result.json`

### ORB-SIT-009 Prompt / Skills / Templates supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml skill`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml template`
- `rtk pnpm vitest run src/components/PromptsTab.test.tsx src/components/SkillsTab.test.tsx`

結果:

- `skill`: 6 passed
- `template`: 9 passed
- Vitest: 2 files passed / 26 tests passed

証跡:

- `evidence/ORB-SIT-009/result.json`

### ORB-SIT-010 Recording / Scheduler supporting

2026-07-03にlocal-linuxで以下を実行。

- `rtk cargo test --manifest-path src-tauri/Cargo.toml recording`
- `rtk cargo test --manifest-path src-tauri/Cargo.toml scheduler`

結果:

- `recording`: 7 passed
- `scheduler`: 21 passed

証跡:

- `evidence/ORB-SIT-010/result.json`

### ORB-IT-003 AI-native UI supporting

2026-07-03にWSLg real GPU routeで以下を実行。

- `rtk bash scripts/run-wdio-tests.sh --skip-build --spec tests/app-ai-native-chat.spec.ts`

結果:

- WDIO: 1 spec passed / 1 test passed
- `DISPLAY=:0`
- `GDK_BACKEND=wayland,x11`
- `WAYLAND_DISPLAY=wayland-0`
- `/dev/dxg=present`
- `virtual_display=disabled`

証跡:

- `evidence/ORB-IT-003/result.json`

### ORB-SIT-003 / ORB-AT-004 WebViewer AI-native official

2026-07-04にWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でQA-ref `96f5943445452f5988fc7ee7cacc4eef88681150` を指定して公式実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --official --wdio-spec tests/app-ai-native-chat.spec.ts`

結果:

- summary status: `pass`
- sourceMode: `git`
- cleanChecks: 2件とも `clean`
- WDIO: `tests/app-ai-native-chat.spec.ts` 2 tests PASS
- `web-viewer-ai-native-state.json`: `urlInput=http://localhost:1420/web-viewer-test.html`
- `web-viewer-ai-native-state.json`: `iframeReadyState=complete`
- `web-viewer-ai-native-state.json`: `iframeLocation=http://localhost:1420/web-viewer-test.html`
- `web-viewer-ai-native-state.json`: `automationText=automation: waitForText ok Oribis Preview Site`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-webviewer-app-ai-native-evidence-20260704-021712\latest-summary.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-webviewer-app-ai-native-evidence-20260704-021712\extracted\wdio-evidence\app-ai-native-chat\web-viewer-ai-native-state.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-webviewer-app-ai-native-evidence-20260704-021712\extracted\wdio-evidence\app-ai-native-chat\web-viewer-ai-native.png`

補足:

- runnerの `desktop-screenshot` はWindows側 `CopyFromScreen` handle警告でwarnだが、WDIO内のWebView screenshotと状態JSONは保存済み。Release GateのWebViewer証跡は個別PNG/JSONを正とする。

### ORB-BUG-017 Anima chat metadata regression official

2026-07-04にWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でQA-ref `6f08c523c045d82afc8c7a9d45305883e9dcf8ae` を指定して公式実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --official --wdio-spec tests/anima-chat-regression.spec.ts`

結果:

- summary status: `pass`
- sourceMode: `git`
- cleanChecks: 2件とも `clean`
- WDIO: `tests/anima-chat-regression.spec.ts` 1 test PASS
- `anima-chat-affinity-meta.json`: `assistantMessages[0]` に好感度メタなし
- `anima-chat-affinity-meta.json`: `hasAffinityMeta=false`
- `anima-chat-affinity-meta.json`: `inputValue=""`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-anima-chat-affinity-meta-20260704-022840\latest-summary.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-anima-chat-affinity-meta-20260704-022840\extracted\wdio-evidence\anima-chat-regression\anima-chat-affinity-meta.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-anima-chat-affinity-meta-20260704-022840\extracted\wdio-evidence\anima-chat-regression\anima-chat-affinity-meta.png`

補足:

- この実行は実画面チャット表示の回帰確認。音声読み上げの実出力確認は `ORB-AT-005` のrequired項目として未実行のまま残す。

### ORB-AT-001 AI-native App Operation official

2026-07-05追加: WindowsQA official run `20260705-213712` / commit `b4601967900a4898d959b75bf4c8f78a92fdadfa` でreal LLM代表10件を再実行。Ollama Vulkan GPU offload証跡あり、WDIO spec 1件PASS、`passedCount=8/10`, `minPass=8` によりthreshold PASS。`affinity-off` / `model-off` はUnsupported planner operationとしてknown limitation/follow-up管理。`codex-adviser` 確認済み。

2026-07-04にWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でQA-ref `5d5589780b0e571bc2c3038bacef76adbe60b7d4` を指定して公式実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --official --wdio-spec tests/app-ai-native-route-acceptance.spec.ts`

結果:

- summary status: `pass`
- sourceMode: `git`
- cleanChecks: 2件とも `clean`
- WDIO: `tests/app-ai-native-route-acceptance.spec.ts` 1 test PASS
- 代表30件のApp tool invoke: PASS
- `app-ai-native-route-acceptance.json`: `caseCount=30`
- `app-ai-native-route-acceptance.json`: `failures=[]`
- `app-ai-native-route-acceptance.json`: `finalState.inputValue=""`
- `app-ai-native-route-acceptance.json`: `finalState.rawToolBlockVisible=false`
- Release Gate判定: `PASS_WITH_LIMITATION`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-route-acceptance-20260704-0250\latest-summary.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-route-acceptance-20260704-0250\extracted\wdio-evidence\app-ai-native-route-acceptance\app-ai-native-route-acceptance.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-route-acceptance-20260704-0250\extracted\wdio-evidence\app-ai-native-route-acceptance\app-ai-native-route-acceptance.png`

補足:

- この証跡は決定的受け入れとして、実チャット送信からmock Anima応答の `app.tool.invoke` を通す。
- 2026-07-04 localで `RootShell.chat.test.tsx` にAnima promptへ `AI-native App Actions catalog` とtoolName/schemaが注入される検証を追加し、`T19b2/T19b3` 3件PASS。
- ただし、実LLMがこのcatalogを読んで代表App操作を生成できる公式証跡は未取得。製品上の自然言語App操作のRelease Gateとしては未達。
- runnerのdesktop-screenshotはWindows API都合でwarnだが、WDIO個別PNG/JSONは保存済み。

追加準備:

- `e2e/wdio/tests/app-ai-native-real-llm-representative.spec.ts` を追加。
  - mock Anima応答は使わない。
  - 実チャット送信からreal Anima LLM経路で10件の代表App操作を送る。
  - 8/10以上の状態変化成功を合格閾値にする。
  - evidence JSON/PNGを `app-ai-native-real-llm-representative` へ保存する。
- `rtk pnpm exec tsc -p e2e/wdio/tsconfig.json --noEmit --pretty false`: PASS
- WindowsQA host復旧後の予定:
  - `scripts/qa/invoke-windows-qa.sh --official --commit <RC_SHA> --wdio-spec tests/app-ai-native-real-llm-representative.spec.ts`

2026-07-04にreal LLM代表確認をWindowsQA official実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --official --commit 9c4062378c2be9077ca5e0b1af2eb74eb0f9f2d3 --wdio-spec e2e/wdio/tests/app-ai-native-real-llm-representative.spec.ts`

結果:

- summary status: `fail`
- sourceMode: `git`
- requestedCommit/resolvedCommit: `9c4062378c2be9077ca5e0b1af2eb74eb0f9f2d3`
- skippedSteps: `[]`
- WDIO: `tests/app-ai-native-real-llm-representative.spec.ts` FAIL
- failure: QA環境に実LLM provider/API keyまたはcommercial feature設定が無く、10件すべて `oribisAI requires commercial feature`
- Release Gate判定: `FAIL`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-real-llm-official-20260705-0025\summary-20260704-235034.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-real-llm-official-20260705-0025\20260704-235034.zip`

解釈:

- 実アプリ経路のチャット入力検出までは前回FAILから進んだが、QA環境の実LLM secret/providerが未準備で停止している。
- 決定的mock経路30件PASSは維持するが、製品上の自然言語App操作としてはこのFAILを修正して再実行する必要がある。

2026-07-05に現HEAD `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e` でreal LLM代表確認をWindowsQA official再実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --host admin@100.64.6.42 --identity-file ~/.ssh/oribis_windows_qa --repo-root 'C:\oribis-qa\oribis-official' --official --commit 1f4c86a --wdio-spec e2e/wdio/tests/app-ai-native-real-llm-representative.spec.ts`

結果:

- summary status: `fail`
- sourceMode: `git`
- requestedCommit: `1f4c86a`
- resolvedCommit: `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e`
- skippedSteps: `[]`
- WDIO: `tests/app-ai-native-real-llm-representative.spec.ts` FAIL
- evidence JSON: `minPass=8`, `total=10`, `passedCount=0`
- failure: 実アプリ起動とオンボーディングは通過したが、QA環境に実LLM provider/API keyまたはcommercial feature設定が無く、`oribisAI requires commercial feature` でApp操作が成立しない
- Release Gate判定: `FAIL`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-ai-native-real-llm-official-20260705-head-1f4c86a\summary-20260705-072206.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-ai-native-real-llm-official-20260705-head-1f4c86a\20260705-072206.zip`
- summary sha256: `aadf3c09f353900dafd36d94eccc06ab289ddefb68c7a69397856113c0405d57`
- artifact sha256: `e42db4ea44af47a77fb5e55fc5f1c464f13dc67ff55a2e01be35d4d393c29092`

解釈:

- 実アプリのチャット経路とオンボーディングは動いている。
- ただし、製品上の自然言語App操作をRelease Gate PASSにするには、QA環境へ実LLM provider/API keyまたはcommercial featureを安全に設定し、同じ代表10件で8件以上PASSさせる必要がある。
- 決定的mock経路30件PASSは維持するが、このreal LLM FAILを代替しない。

### ORB-BUG-020 Startup residual process/window runner guard

2026-07-04にWindowsQA runner側へ、起動前/終了後のOribis QAプロセス残留を検出・掃除・証跡化する処理を追加。

codex-adviser結論:

- WindowsQA runnerにpreflight cleanup、post-run cleanup、最終no residual check、summary gate用fieldを入れる方針が妥当。
- `WebView2` / `Chrome` / `node` / `pnpm` を名前だけでkillする設計は禁止。
- kill境界はRepoRoot、command line、port 1420、起動PID tree、親子関係で絞るべき。
- preflight残留は記録し、cleanup後0ならテスト開始可。post-run残留はfailが妥当。

実装:

- `scripts/qa/run-windows-smoke.ps1`
  - `Get-OribisQaProcesses`
  - `Stop-OribisQaProcesses`
  - `processChecks` summary field
  - diagnostics `oribis-process-checks.json` / `oribis-processes-final.txt`
  - `oribis-preflight-cleanup` step
  - `oribis-post-run-cleanup` step

検証:

- `powershell.exe` parserで `run-windows-smoke.ps1` 構文PASS。

証跡:

- `evidence/ORB-BUG-020/result.json`
- sha256: `81f362cef5b2744a74e89912a2234f348b6d3ced2bce9e6f386dc892741f8a51`

WindowsQA official verification:

- runId: `20260704-034448`
- commit: `d37b7b02184b227f595bbf01af913d0b48dec4cd`
- summary: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\latest-summary.json`
- artifact: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\20260704-034448.zip`
- summary sha256: `ec49875b5cc467fff800333c5772c68b347be3ffd08affe05e23491abe061f56`
- artifact sha256: `6fa48ce7f0dd78b98bfb1508a2ed2ded92c20cc0c0c4d3e9070351378ae38e90`

結果:

- `status=pass`
- `official=true`
- `sourceMode=git`
- `requestedCommit` / `resolvedCommit` 一致
- `cleanChecks`: repo-check前 / git-update後ともclean
- `processChecks`: preflight前後 / post-run前後すべてPASS、count 0
- `skippedSteps=[]`
- targeted-vitest / cargo-check / frontend-build / tauri-debug-build / WDIO PASS

補足:

- runnerのdesktop screenshotはWindows API `CopyFromScreen` のhandle警告でwarn。ただしWDIO実アプリ経路とprocessChecksはPASS。
- 全画面スクショ警告は証跡手順の改善対象として残し、起動/残留プロセスgateのFAILにはしない。

### ORB-BUG-021 Stage/Studio split supporting verification

2026-07-04にlocal-linuxで、StageにStudio用物理/重力/cube導線を露出させないための支持検証を実行。

codex-adviser結論:

- Stageはruntime/production-facing表示面、Studioはauthoring/experimental 3D編集面として分ける方針が妥当。
- Stage projectionはdeny-by-defaultが妥当。
- `projection policy`、`rendered ids`、`Stage object payload`、`command/tool catalog exposure` の4点に絞るべき。
- SceneRuntime内部とStudio authoring本体は削らない。

実行:

- `rtk pnpm vitest run src/components/BabylonStageViewer.test.ts src/command/CommandRegistry.test.ts src/components/DeveloperConsole.test.tsx src/workbench/coreAppToolValidation.test.ts --reporter=dot`
- `rtk pnpm run typecheck`
- `rtk rg -n "Scene / 3Dキューブ|Scene / 最初の3Dオブジェクト|Scene / 3Dオブジェクトを消去|projectFallbackObjects: true|stage-temporary-furniture[\s\S]{0,120}physics" src/components src/command src/scene-runtime src/workbench`

結果:

- Vitest: 4 files / 42 tests PASS
- Typecheck: PASS
- Stage projection: `runtime-cube` はStageで非投影、Studioでは投影
- Stage terminal/surface/furniture: Stageで投影
- Stage activity furniture: `physics` payloadなし
- DeveloperConsole: Studio用 `createCube` / `moveFirst` / `clear` 候補なし
- `data-stage-rendered-object-ids`: projection後のIDのみ

証跡:

- `evidence/ORB-BUG-021/result.json`
- sha256: `eefaefdd211170c0d4626efc1ed4f31720c4ca1926c7c04b0d7fafa9ec4476cc`

WindowsQA official verification:

- runId: `20260704-034448`
- commit: `d37b7b02184b227f595bbf01af913d0b48dec4cd`
- summary: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\latest-summary.json`
- artifact: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\20260704-034448.zip`
- summary sha256: `ec49875b5cc467fff800333c5772c68b347be3ffd08affe05e23491abe061f56`
- artifact sha256: `6fa48ce7f0dd78b98bfb1508a2ed2ded92c20cc0c0c4d3e9070351378ae38e90`

結果:

- WindowsQA official: PASS
- `tests/onboarding-scene-only.spec.ts`: PASS
- targeted-vitest: 121 tests PASS
- Stage projection deny-by-default: generic Studio cubeはStageで非投影、Studioでは投影
- Anima terminal command sync: Debug Console request時にAnima terminalを表示
- onboarding中はScene単体surfaceを確認

補足:

- 今回の公式runはStage/Studio境界とオンボードScene単体の回帰確認。Workbench Scene Appの全機能表示は既存 `ORB-BUG-006/007` と `ORB-ST-004` 側に分離。

### ORB-ST-004 / ORB-ST-006 Workbench and WebViewer UI official

2026-07-04にWindowsQA Server `C:\oribis-qa\oribis-develop-clean` でWorkbench UIを公式実行。

run:

- runId: `20260704-004932`
- commit: `b10263d49f1bff02e0539173ef36e44923d0bbb4`
- official: `true`
- sourceMode: `git`
- skippedSteps: `[]`
- cleanChecks: repo-check before git update / git-update after origin branch sync ともに `clean`
- summary: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\latest-summary.json`
- artifact: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\20260704-004932.zip`

結果:

- WindowsQA official: PASS
- WDIO: PASS
- desktop-screenshot: WARN (`CopyFromScreen` handle invalid)。WDIO個別PNG/JSONを正証跡とする。

`ORB-ST-004` 確認:

- `core-app-workbench-layout-rects.json`
  - Scene: left `467`, top `67`, width `780`, height `443`
  - Anima: left `0`, top `67`, width `467`, height `353`
  - Workers: left `0`, top `455`, width `467`, height `245`
  - Logs: left `467`, top `545`, width `780`, height `155`
- `core-app-workbench-default-layout.png`
- 受け入れ条件のうち、Scene右、Anima左上、Workers左下、Console/Log下はPASS。
- App選択表示が閉じる操作に誤認されない点は `ORB-BUG-008` の同一run証跡で `tabCloseButtonCount=0` として確認済み。

`ORB-ST-006` 確認:

- `core-app-workbench-web-viewer-manual.json`
  - `empty=true`
  - `iframe=false`
  - `inputValue=""`
  - `liveBanner=false`
- `core-app-workbench-web-viewer-empty.png`
- 手動Open時に前回ページ/謎ページが出ず、空状態から始まる。

証跡SHA:

- summary sha256: `29b016d4ccc837d8750a3799a6052306f8226b1a681b87f38d20dd6ab85885c5`
- artifact zip sha256: `8e35425bb23175b6771849215021c7dacca10720b24597520cf911c170ddc9d8`
- layout JSON sha256: `1cdce822d264fb767ec8ee423ff6c10a03e93e96e0ef86d13536d75c1cf55432`
- default layout PNG sha256: `4c8cc16fac86f866d41c1acbfd072acf5ade0a4194e8fce4a49fb95134eaa1e0`
- WebViewer manual JSON sha256: `d547c76713a420dca8a0aa93be9e352d14e52d91c08a7e5d3679bff1ba984647`
- WebViewer empty PNG sha256: `f6b37140d84b279bc8959bc856621d34a2faf6756465eccc0e6ac2bc5ae7218c`

### ORB-SIT-001 / ORB-AT-003 Worker Chat UX official

2026-07-04にWorker Chatのfallback本文とWDIO証跡判定を改善し、同日20:00にWindowsQA official runで確認した。

codex-adviser結論:

- fallback本文から `final answer generation was unavailable` / `Answer generation note` を消し、完了したtool結果の要約として返す方針は妥当。
- ただし、既存WindowsQA `20260704-002753` だけで `ORB-SIT-001` / `ORB-AT-003` をPASS扱いするのは弱い。
- 正式PASSには、DOMチャット送信のみの同一runで `Worker terminal` / `Chat output` / `Chat input` を確認した証跡が必要。
- `dispatchSceneRouterRequest('worker.instant.run', ...)` はsupportingに留め、正本にはしない。

実装:

- `src-tauri/src/worker_server.rs`
  - fallback final answerのユーザー向け文言を `Worker completed the requested tool steps. Summary from completed results:` に変更。
  - `final answer generation was unavailable` と `Answer generation note` はチャット本文へ出さない。
- `e2e/wdio/tests/worker-chat.spec.ts`
  - Worker terminal streamを証跡JSONへ保存。
  - `internal-worker:create-job` / `internal-worker:run-job` / `completed` を検査。
  - chat outputが旧fallback文言を含まないことを検査。
  - chat inputが送信後に空であることを検査。

検証:

- `rtk cargo test internal_worker_server_falls_back_to_tool_output_when_answer_generation_fails --manifest-path src-tauri/Cargo.toml`: PASS
- `rtk cargo test worker_server --manifest-path src-tauri/Cargo.toml`: 14 passed
- `rtk pnpm vitest run src/hooks/useWorkerChatSessions.test.ts --reporter=dot`: 10 passed
- `rtk pnpm vitest run src/RootShell.chat.test.tsx --testNamePattern "T19b2w|T19b2|T19b3" --reporter=dot`: 4 passed / 42 skipped
- `rtk pnpm vitest run src/RootShell.chat.test.tsx --reporter=dot`: 46 passed。既存act警告あり、assertはPASS。
- `rtk pnpm vitest run src/RootShell.terminal.test.tsx --testNamePattern "final answer|PTY dispatch" --reporter=dot`: 2 passed / 23 skipped。既存act警告あり、assertはPASS。
- `rtk pnpm vitest run src/RootShell.onboarding.test.tsx --reporter=dot`: 5 passed
- `rtk pnpm vitest run src/workbench/CoreAppWorkbench.test.tsx --reporter=dot`: 15 passed
- `rtk pnpm vitest run src/RootShell.chat.test.tsx --testNamePattern "T19b2w" --reporter=dot`: 1 passed / 45 skipped（Worker answer generation failure audit log追加後の再確認）
- `rtk pnpm run typecheck`: PASS

sysdev-2 third-party review:

- Release Gate記録上、AT-001を `PASS_WITH_LIMITATION` からhost起因の `BLOCKED_ON_WINDOWSQA` へ戻した扱いは妥当。
- Worker chat/terminal追加修正のmust-fix残りはなし。
- 軽微指摘として、`PASS_WITH_LIMITATION` のtaxonomy定義追加とWorker answer generation失敗理由のaudit/log記録を推奨。どちらも2026-07-04に反映済み。
- WindowsQA復旧後の推奨順序は、2026-07-04のsysdev-2再確認と今回のDiscord環境未準備waiverにより `worker-chat (ORB-SIT-001 + ORB-AT-003)` → `ST-005/AT-002/AT-005` → `app-ai-native real LLM representative` → `packaging` → `strict gate` へ更新。Discord real relayは今回scope外。
- 追加sysdev-2確認: `ORB-AT-003` はWorker Chat runに相乗り可能。ただし `ORB-SIT-001` は配線/4点表示、`ORB-AT-003` はWorker UXの進捗/状態/結果の妥当性として別判定し、同一証跡へ紐づける。
- 追加sysdev-2確認: strict gate最終証跡はQA-ref一時commitではなく、出荷候補RC SHAで実行する必要がある。WindowsQA復旧後のrequired公式run前にRC SHAを確定する。

WindowsQA official result:

- command: `scripts/qa/invoke-windows-qa.sh --official --commit bb6561b3a7602304260d1dbc5cbc2757935081eb --wdio-spec e2e/wdio/tests/worker-chat.spec.ts`
- clean repo: `C:\oribis-qa\oribis-official`
- run: `20260704-200036`
- result: `PASS_WITH_WARNINGS`
- reason for warning: runner `desktop-screenshot` step failed with `CopyFromScreen` handle warning。WDIO個別PNG/JSONは保存済み。
- summary: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-worker-chat-official-20260704-1958\latest-summary.json` sha256=`52d0a406f4012d96fd52b71f075d10783ed50c7a8654088cae2632787254ea5f`
- artifact zip: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-worker-chat-official-20260704-1958\20260704-200036.zip` sha256=`3f494925f4aa9661cfdb46010849cb2cad5ed0fad4e06073104fd5af74d43d97`
- WDIO evidence JSON: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-worker-chat-official-20260704-1958\extracted\wdio-evidence\worker-chat\worker-chat-answer.json` sha256=`4578bce784d03e17e243aab4ae1d416f89c88a7e4d6e58c8a554919257669eab`
- WDIO evidence PNG: `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-worker-chat-official-20260704-1958\extracted\wdio-evidence\worker-chat\worker-chat-answer.png` sha256=`526340d413e6ad543525194aea8fb507f481184a7e2ca2abbf011776c4781c48`

判定:

- `ORB-SIT-001`: `PASS_WITH_WARNINGS`。Worker terminal stream、worker_output本文、Anima入力欄非存在、送信後input空を確認。
- `ORB-AT-003`: `PASS_WITH_WARNINGS`。Worker terminalにcreate/run/completedの進捗があり、チャット出力にworker_output本文が出ることを確認。
- `ORB-BUG-015`: `verified`。queued/completedだけで終わらず、worker_output本文が出る。
- `ORB-BUG-016`: `verified`。`animaInputExists=false`, `inputValue=""`。

### ORB-ST-005 Console / Worker Activity UI preparation

2026-07-04にWorkers Appの分散UIを整理。

codex-adviser結論:

- `Workers / Activity / Tools / Assets` への4タブ化は妥当。
- `Jobs / Tasks / Queue` をトップレベルタブとして見せない整理は `ORB-ST-005` の受け入れ条件に合う。
- `core:jobs` / `core:tasks` aliasは削除せず、`Workers > Activity` へ着地させる方がデグレ防止として妥当。
- 旧タブが存在しないことだけでなく、旧aliasがActivityへ正規化されることを確認すべき。

実装:

- `src/RootShell.tsx`
  - Workers App tabsを `Workers / Activity / Tools / Assets` に整理。
  - `Tasks` と `Queue` の重複 `TaskQueue` 表示を廃止。
  - `Jobs` と pending workを `Activity` に統合。
  - `Dispatch / Diff / Improve` を `Tools` に統合。
- `src/workbench/coreAppRegistry.ts`
  - `core:jobs` / `core:tasks` aliasを `core:workers` の `activity` タブへ誘導。
- `src/components/TaskQueue.tsx`
  - title / emptyLabelを呼び出し側から指定可能にし、Workbench内では `Pending Work` / `No pending work` と表示。
- `src/i18n/en.json`
  - `TaskJobView` の見出しを `Worker Activity`、空状態を `No activity` に変更。
- `e2e/wdio/tests/core-app-workbench.spec.ts`
  - `workers-app-tab-jobs/tasks/queue` が存在しないこと、`Activity` / `Tools` が存在することを検査。
- `e2e/wdio/tests/titlebar-app-strip.spec.ts`
  - `core:jobs` aliasが `workers-app-activity` に着地することを検査。

検証:

- `rtk pnpm run typecheck`: PASS
- `rtk pnpm vitest run src/components/__tests__/TaskJobView.test.tsx src/components/TaskQueue.test.tsx src/workbench/CoreAppWorkbench.test.tsx src/workbench/coreAppWindow.test.ts --reporter=dot`: 4 files / 47 tests PASS
  - 既存のReact `act(...)` warningあり。今回の変更による失敗ではない。
- 2026-07-04追加支援確認:
  - `rtk pnpm vitest run src/components/DeveloperConsole.test.tsx src/components/__tests__/TaskJobView.test.tsx src/components/__tests__/ActionAuditPanel.test.tsx --reporter=dot`: 3 files / 43 tests PASS
  - `rtk pnpm vitest run src/workbench/CoreAppWorkbench.test.tsx --reporter=dot`: 1 file / 15 tests PASS。`core:project` / `core:remote` 旧layoutがAnimaへ誤復元されずdropされることを確認。
  - 既存のReact `act(...)` warningあり。assertはPASS。

WindowsQA:

- pre-RC QA ref: `e9c0307fc10b6d7f9fb401c89a391418bc88c09e`
- planned official command after RC SHA is fixed: `scripts/qa/invoke-windows-qa.sh --official --commit <RC_SHA> --wdio-spec tests/core-app-workbench.spec.ts`
- result: BLOCKED before app execution
- reason: WindowsQA host `100.64.6.42` / `desktop-test001.tail68ea5e.ts.net` SSH timeout

残:

- WindowsQA host復帰後、RC SHAを確定して `tests/core-app-workbench.spec.ts` を公式再実行する。
- PASS後に `ORB-ST-005` と関連bug regressionの証跡を更新する。

### ORB-AT-002 Settings / Anima UX preparation

2026-07-04にOnboardingとAnima設定まわりを点検。

確認済み:

- `src/components/Onboarding.tsx`
  - `characterName` 初期値は `anima`
  - `userName` 初期値は `User`
  - `buildLocalOnboardingPromptStack` のfallbackも `anima` / `User`
- `src/RootShell.onboarding.test.tsx`
  - `onboarding-anima-name` が `anima`
  - `onboarding-user-name` が `User`
  - `Idea` ではないことを検査済み
- `e2e/wdio/tests/core-app-workbench.spec.ts`
  - Anima Appは `Prompts` 1タブで、旧 `Files` / `Cache` タブは存在しない
  - `Critical Prompt / L2`, `Project Prompt Files`, `Anima Memory Cache` は同一Prompts画面内に統合済み

実装:

- `src-tauri/src/lib.rs`
  - `setup_anima_home` の旧 `Idea L1 prompt` コメント/ログを `Anima L1 prompt` へ修正。
  - TTS test fixture文言を `I am Anima...` へ修正。
- `e2e/wdio/tests/anima-local-llm-smoke.spec.ts`
  - `Idea` の日本語読み `アイデア` をAnima名として許容する旧aliasを削除。
  - 応答許容パターンから `アイデア` を削除。
- `e2e/wdio/tests/anima-openai-subscription-smoke.spec.ts`
  - 旧 `Idea` alias許容を削除。
- `e2e/wdio/tests/anima-kimi-api-key-smoke.spec.ts`
  - 旧 `Idea` alias許容を削除。

検証:

- `rtk pnpm vitest run src/RootShell.onboarding.test.tsx src/components/Onboarding.test.tsx --reporter=dot`: PASS
- `rtk cargo test test_fast_tts_flush_keeps_english_kokoro_chunks_long --manifest-path src-tauri/Cargo.toml`: PASS
- `rtk pnpm run typecheck`: PASS
- static search: default/LLM-smoke上の旧 `Idea` 許容は否定テスト以外なし
- 2026-07-04追加支援確認:
  - `rtk pnpm vitest run src/components/GeneralTab.test.tsx src/components/PromptsTab.test.tsx src/components/AppsTab.test.tsx src/components/Onboarding.test.tsx src/RootShell.onboarding.test.tsx --reporter=dot`: 42 tests PASS
  - 既存のReact `act(...)` warningあり。assertはPASS。

WindowsQA:

- pre-RC QA ref: `e9c0307fc10b6d7f9fb401c89a391418bc88c09e`
- planned commands:
  - `scripts/qa/invoke-windows-qa.sh --official --commit <RC_SHA> --wdio-spec tests/onboarding-anima-visual.spec.ts`
  - `scripts/qa/invoke-windows-qa.sh --official --commit <RC_SHA> --wdio-spec tests/core-app-workbench.spec.ts`
- result: BLOCKED before app execution
- reason: WindowsQA host `100.64.6.42` / `desktop-test001.tail68ea5e.ts.net` SSH timeout

### ORB-AT-005 TTS voice acceptance preparation

2026-07-04にTTS voice acceptanceのsupporting testsを再実行。

確認対象:

- `src/hooks/useTTS.test.ts`
- `src/lib/readableTtsText.test.ts`
- `src-tauri/src/tts.rs`
- `src-tauri/src/tts/lifecycle.rs`

修正:

- `src-tauri/src/tts/lifecycle.rs`
  - `ORIBIS_HOME_DIR` を変更する `voicevox_requires_vvm_before_start` を `serial_test` に参加させた。
  - 原因はTTS本体ではなく、`cargo test tts` 並列実行時に `ORIBIS_HOME_DIR` を触るテスト同士が干渉すること。

検証:

- `rtk pnpm vitest run src/hooks/useTTS.test.ts src/lib/readableTtsText.test.ts --reporter=dot`: 2 files / 14 tests PASS
- `rtk cargo test test_voicevox_has_vvm_files_true_when_vvm_exists --manifest-path src-tauri/Cargo.toml`: 1 passed
- `rtk cargo test tts --manifest-path src-tauri/Cargo.toml`: 80 passed / 21 ignored / 2144 filtered out

結果:

- TTS設定・読み上げ文字列・VOICEVOX VVM検出のsupporting testsはPASS。
- `ORB-AT-005` の正式PASSには、WindowsQA real GPU/real audio routeでチャット音声の実出力、ピッチ/速度設定反映、読み上げ本文から内部メタが除外されることを証跡化する必要がある。

2026-07-05に現HEAD `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e` でWindowsQA official再実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --host admin@100.64.6.42 --identity-file ~/.ssh/oribis_windows_qa --repo-root 'C:\oribis-qa\oribis-official' --official --commit 1f4c86a --wdio-spec e2e/wdio/tests/tts-voice-playback.spec.ts`

結果:

- summary status: `fail`
- sourceMode: `git`
- requestedCommit: `1f4c86a`
- resolvedCommit: `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e`
- skippedSteps: `[]`
- failed step: `tts-assets-provision`
- failure: VOICEVOX runtime assets未配置、かつ `ORIBIS_QA_ACCEPT_VOICEVOX_TERMS` / `ORIBIS_ACCEPT_VOICEVOX_TERMS` 未設定

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-tts-official-20260705-head-1f4c86a\summary-20260705-072123.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-tts-official-20260705-head-1f4c86a\20260705-072123.zip`
- summary sha256: `b6f819a30500c28626b4c0527e9dc52c66aada1751b98b23833342e3623bf986`
- artifact sha256: `745f8705783eda87c87601b2db0a66f5b2e7e2d1a042ed0c54fb77a39aa28b86`

解釈:

- TTS資産provisionゲートは機能している。
- VOICEVOX規約承諾は自動で代行しない。明示承諾envを設定し、runtime assetsをprovisionしてから再実行が必要。
- Supporting TTS unit/Cargoは正式ATの代替にしない。

### ORB-GATE-002 Release Packaging runner preparation

2026-07-04にRelease Packaging Gateのrunnerを見直し。

codex-adviser確認:

- official `ORB-GATE-002` はinstaller必須。
- release exe単体起動はdiagnostic/supportingとしては記録できるが、required Release GateのPASSにはしない。
- installer候補、hash、MSI ProductCode、既存インストール衝突、install/uninstall exit code、cleanup結果をsummaryへ残すべき。

実装:

- `scripts/qa/run-windows-packaging.ps1`
  - `pnpm tauri build` 後に `src-tauri\target\release\bundle` からMSI/NSIS installer候補を検出。
  - MSIを優先し、NSISは `bundle\nsis\` またはsetup/installer名に限定。
  - official modeではinstaller未検出をFAIL。
  - official modeではインストール前に既存Oribis install pathがある場合もFAIL。
  - MSIは `msiexec.exe /i ... /qn /norestart`、NSISは `/S` でinstall。
  - installer由来のinstalled exeを起動し、スクリーンショットを保存。
  - MSI ProductCodeまたはNSIS uninstallerでuninstallし、残存install pathを確認。
  - MSI uninstallは `0` / `3010` のみ成功扱い。未登録 `1605` はofficial gateでは許容しない。
  - summary JSONへ `systemSnapshot`, `installerCandidates`, `installerPath`, `installerKind`, `installerSha256`, `installerSignature`, `msiProductCode`, `installExitCode`, `installedExe`, `installedExeSha256`, `installedExeSignature`, `uninstallExitCode`, `cleanupStatus` を保存。
  - `systemSnapshot` にはOS/GPU/WebView2/Node/pnpm/rust/cargo/tauri CLI versionとelevated状態を保存。
  - `releaseExe` / `installer` / `installedExe` のAuthenticode署名状態を保存。未署名なら `NotSigned` として明示される。

検証:

- `powershell.exe -NoProfile -Command '[Parser]::ParseFile("scripts/qa/run-windows-packaging.ps1", ...)'`: PASS
- `bash -n scripts/qa/invoke-windows-qa.sh scripts/qa/push-qa-ref.sh scripts/qa/invoke-windows-interactive-qa.sh`: PASS

WindowsQA:

- pre-RC QA ref: `e9c0307fc10b6d7f9fb401c89a391418bc88c09e`
- planned command:
  - `scripts/qa/invoke-windows-qa.sh --host admin@100.64.6.42 --identity-file ~/.ssh/oribis_windows_qa --official --commit <RC_SHA> --runner 'C:\oribis-qa\artifacts\incoming\run-windows-packaging.ps1' --local-runner-file scripts/qa/run-windows-packaging.ps1 --remote-summary-name latest-packaging-summary.json --remote-zip-name 'packaging-{runId}.zip' --pull-artifacts /mnt/c/Users/admin/Pictures/agante-projects/sysdev/oribis-release-packaging-<run-id>`
2026-07-05に最新RC SHA `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e` でWindowsQA official再実行。

実行:

- `scripts/qa/invoke-windows-qa.sh --host admin@100.64.6.42 --identity-file ~/.ssh/oribis_windows_qa --repo-root 'C:\oribis-qa\oribis-official' --official --commit 1f4c86a --local-runner-file scripts/qa/run-windows-packaging.ps1 --runner 'C:\oribis-qa\artifacts\incoming\run-windows-packaging.ps1' --remote-summary-name latest-packaging-summary.json --remote-zip-name latest-windows-packaging.zip --pull-artifacts /mnt/c/Users/admin/Pictures/agante-projects/sysdev/oribis-release-packaging-official-20260705-head-1f4c86a`

結果:

- summary status: `fail`
- requestedCommit: `1f4c86a`
- resolvedCommit: `1f4c86aa8898ec338c4137eab2f8de0a1ae7b75e`
- sourceMode: `git`
- cleanChecks: 2件とも `clean`
- failed step: `interactive-desktop-precheck`
- failure: WindowsQA interactive desktop is not logged in; `query user` returned `No User exists for *`
- session diagnostics: `activeSessionCount=0`; `qwinsta` shows `console Conn` with no username; `explorerProcesses=[]`; `logonUi.lastLoggedOnUser=.\admin`
- release build / installer detection / install / uninstall: `not-run`
- Release Gate判定: `FAIL`

証跡:

- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-release-packaging-official-20260705-head-1f4c86a\summary-20260705-072021.json`
- `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-release-packaging-official-20260705-head-1f4c86a\packaging-20260705-072021.zip`
- summary sha256: `05ecddf527b4f6cc614698d6850b0a2ef7d26982a95bf048b3857851708e3a1e`
- artifact sha256: `af6f5f692b640fdc307871cc4dc08181d10d092ffab6f62cd77cc94838c87aac`

解釈:

- SSH接続、exact commit checkout、clean checkは成立している。
- ただし、official packagingは実GPU/実WebViewのinstalled app screenshotが必要なため、ログイン済み対話デスクトップsessionなしでは開始できない。
- WindowsQAへconsole/RDP等でユーザーsessionを作ってから再実行が必要。

### ORB-SIT-002 Discord Relay supporting recheck

2026-07-04にDiscord Relayのsupporting testsを再実行。

確認対象:

- `src-tauri/src/agent_discord_delivery.rs`
- `src-tauri/src/agent_discord_route_store.rs`
- `src-tauri/src/agent_discord_commands.rs`
- `src-tauri/src/discord_bridge.rs`
- `src/worker-core/discordAdapter.test.ts`
- `src/command/CommandRegistry.test.ts`
- `src/command/typingScriptDsl.test.ts`

検証:

- `rtk cargo test agent_discord --manifest-path src-tauri/Cargo.toml`: 35 passed
- `rtk pnpm vitest run src/worker-core/discordAdapter.test.ts src/command/CommandRegistry.test.ts src/command/typingScriptDsl.test.ts --testNamePattern "Discord|discord|outbox|queue" --reporter=dot`: 3 files / 9 passed / 36 skipped

結果:

- 旧Worker Core Discord outbox queue導線の回帰テストはPASS。
- Agent Discord route/deliveryの単体/統合境界テストはPASS。
- `ORB-SIT-002` の正式PASSには、設定済みテスト用Discord channelへ実送信し、即時配送/滞留なし/queue metricsをWindowsQA official evidenceとして保存する必要がある。
- 今回runではDiscord環境未準備のためProducer指示により延期する。waiver `WAIVER-20260704-DISCORD-ENV-NOT-PREPARED`。

## 残っているrequired blocker

- `ORB-AT-001`: official FAIL。実アプリ起動とオンボーディングは通過したが、QA環境に実LLM provider/API keyまたはcommercial feature設定が無く、real LLM代表10件が `passedCount=0/10`。
- `ORB-GATE-001`: `ORB-AT-001` が残っているため意図的にNOT_RUN。

解消済み:

- `ORB-AT-005`: 2026-07-05 WindowsQA official run `20260705-111317` でPASS_WITH_WARNINGS。VOICEVOX/Kokoro資産provisionとWDIO TTS playback 6件を確認。
- `ORB-GATE-002`: 2026-07-05 WindowsQA official run `20260705-234741` でPASS。release build / VOICEVOX/Kokoro bundle check / installer install / installed app startup / uninstallを確認。

## 未実行のsupporting項目

なし。

## ソース棚卸しで追加した対象

- Core App / Workbench / App action catalog
- App runtime: scan / install / enable / permission / package / sidecar / storage / fs / net / tool catalog / sandbox
- Builtin and external Apps: Scene Editor / Scene Builder / Animation Creator / Discord Bridge / Google Workspace / GitHub Integration / Blender Hub / Work Report / Debug Panel
- Worker / Worker server / Internal Worker / Worker PTY / Worker answer
- Agent routing / Agent Server / Anima Agent Server / Agent collaboration
- Discord relay / Discord bridge / route store / delivery
- Remote / Web Remote / TOTP / auth / rate limit / assets
- Anima memory / retrieval / prompt / skills / templates
- Recording / Scheduler / OpenAI subscription auth / Kimi auth / commercial license / Signal
- Google / GitHub / Blender command surfaces

## 次に必要な作業

1. WindowsQA host `100.64.6.42` はSSH到達済み。`ORB-GATE-002` のため、ログイン済み対話desktop sessionを作ってから公式packagingを再実行する。
2. `ORB-AT-005` はVOICEVOX runtime assetsと明示承諾envが無いため停止中。規約承諾を代行せず、正式な承諾・資産配置後に再実行する。
3. `ORB-AT-001` は実LLM provider/API keyまたはcommercial feature未設定で `passedCount=0/10`。secretを証跡へ漏らさない保管手順でQA環境を設定して再実行する。
4. Discord real relayは今回scope外のwaiverのまま。今回release scopeに戻すなら `ORB-SIT-002` を別途WindowsQA/Discord-ready環境で実行する。
5. 上記required blocker解消後、`ORB-GATE-001` strict auditを再実行し、requiredBlocked / requiredNotRun / nonVerifiedBlockingBugs が0になったことを確認する。
