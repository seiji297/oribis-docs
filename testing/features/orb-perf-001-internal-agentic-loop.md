# ORB-PERF-001 Internal Agentic Loop Feature Intake

この文書は、内製Workerが軽量な一発生成だけでなく、探索が必要な重量級コーディングタスクをこなせるかをEAリリース条件として扱うためのFeature Intakeと実装設計概要。

実装前にsysdev-2レビューを受ける。レビュー完了までは実装へ進まない。

## Feature Intake

| Item | Decision |
|---|---|
| Feature / capability | Internal Worker bounded exploratory multi-turn loop |
| Human UI entry | 既存Workers App、Worker terminal、チャット経由のWorker dispatch表示を使う。新規UIは作らない。 |
| AI-native entry | 既存 `oribis.core.workers.dispatch` / Worker job path。AI引数から任意backendや任意workspaceRootを選ばせない。 |
| Tool catalog / schema | 内製Worker内部のagent loop schema。LLMが要求できるactionは `list_files`、`read_file`、`search`、`run_command`、`propose_plan`、`write_files` に限定する。 |
| Permission | 既存write-plan / workspace境界を維持。探索actionはread-only、書込は既存の相対path検証・write policy・validation境界を通す。 |
| Risk | Worker execution、file system read/write、test command execution、LLM tool loop暴走、secret混入、長時間実行、PERF fixture判定。 |
| Evidence | UT/IT logs、agent loop transcript JSON、per-turn tool_call evidence、workspace hash before/after、WindowsQA official PERF summary/artifact zip。 |
| Affected areas | `internal_worker_coding_agent.rs`、Worker job runner、PERF harness、PERF fixtures、release manifest/evidence。 |
| Test levels | UT: action parser/limits/path guard。IT: job runner and tool loop. AT/PERF: WindowsQA official E群3レーン比較。 |
| WindowsQA need | 必須。EA Gateのrequired evidence。 |
| Feature flags | Internal Worker mode selection flag。single-shot維持、explore modeはタスク規模/metadataで内部選択。emergency kill switchを持つ。 |

## Acceptance Criteria

- 小タスクでは既存single-shot経路を維持し、PERF A/B級で不要な遅延を増やさない。
- 大タスクではbounded explore modeへ切り替わり、LLMが必要ファイル探索、読み取り、検索、テスト実行、修正を複数turnで行える。
- ループはturn上限、総timeout、tool回数、command timeout、snapshot/token予算を持つ。
- `list_files`、`read_file`、`search`、`run_command` はworkspace内に制限され、secretや除外pathを読まない。
- `run_command` は既存 `run_safe_command` 相当のallowlistを使い、shell redirection、pipe、network、sudo、破壊コマンドを拒否する。
- ファイル書込は既存の相対path検証、最大サイズ、除外path、validation、final answer/event persistenceを再利用する。
- 既存 `step` / `tool_call` / `repair` event構造に各turnを記録し、新規フレームワークを作らない。
- 失敗時はstructured failure classを残し、単なる「Worker completed」だけで終わらない。
- PERF E群でL1-jobがL3-opencode-raw比80%以上の完遂率と2倍以内の中央値を満たす。

## Current Implementation Baseline

現行 `src-tauri/src/internal_worker_coding_agent.rs` は以下を持つ。

- workspace snapshotを一括でLLMへ渡すsingle-shot JSON plan生成。
- JSON parse失敗時のJSON repair prompt。
- plan適用後のvalidation実行。
- command/validation失敗時の1回repair prompt。
- `InternalWorkerStep.tool_call`、`InternalWorkerEventKind::ToolCallRequested/Completed` への記録。
- 相対path検証、除外path、safe command allowlist、command timeout、write size limit。

不足しているものは、LLMが自分で追加探索を要求するmulti-turn action loop。現状は初期snapshotに入らないファイル、失敗テストの原因が別ファイルにあるケース、横断refactor、API変更追跡で不利。

## Design Overview

### Mode Selection

`run_internal_worker_coding_job_in` の中でタスク規模を判定し、実行モードを選ぶ。

| Mode | 条件 | 挙動 |
|---|---|---|
| `singleShot` | 既存A/B級、metadataでsingleShot指定、または短い単一ファイル作業 | 現行JSON plan + repairを維持 |
| `explore` | C/E級、metadataでexplore指定、validation commandsあり、fixture sizeが閾値以上、またはinstructionが探索/複数ファイル/バグ修正/横断refactorを示す | bounded agentic loop |

注意: mode selectionは固定語録ルーターにしない。主判定はjob metadata、fixture/task category、workspace size、validation有無。自然言語の単語列だけで分岐しない。

製品経路ではカスケード昇格を必須にする。開始時に `singleShot` を選んだ場合でも、single-shot apply後のvalidationがFAILし、既存repair attemptでもFAILしたら、残りbudget内で `explore` modeへ昇格して再挑戦する。昇格時は新しいjobを作らず、同じjob/step/event系列に `escalatedFrom=singleShot` と `escalationReason=validation_repair_failed` を記録する。budgetはsingle-shot/repair/exploreで合算管理し、昇格でtimeoutやtool上限をリセットしない。

### Explore Loop State

追加する内部構造。

```text
AgentLoopState
  job_id
  mode
  turn_index
  deadline
  budget
  transcript
  observed_files
  changed_files
  last_validation
  pending_plan
```

`budget` は以下を持つ。

- `maxTurns`: 既定8、PERF Eではtask timeoutに応じて最大12。
- `maxToolCalls`: 既定32。
- `maxReadFiles`: 既定40。
- `maxReadBytes`: 既定300KB。
- `maxSearchResults`: 既定80。
- `maxCommands`: 既存上限を基準に、validation用途を含めて明示的に消費管理。
- `deadline`: job timeout内で強制停止。
- `maxNoProgressTurns`: 既定2。新しいfile observation、successful command、write plan、validation改善が無いturnが連続したら停止。
- `perLlmCallTimeoutMs`: 既定120000ms。1回のLLM呼び出しが固まってもjob deadlineまで待たない。

停止条件は以下。

- `deadline` 超過。
- `maxTurns` 超過。
- `maxToolCalls` 超過。
- `maxNoProgressTurns` 超過。
- LLM responseが連続2回parse不能。
- `write_files` plan適用後にvalidationがPASS。
- `write_files` plan適用後にvalidationがFAILし、repair attemptもFAIL。
- single-shotからexploreへ昇格済みで、explore側もvalidation/repairがFAIL。

停止理由は必ずtelemetry/eventへ `stopReason` として記録する。

### LLM Action Schema

LLM応答はJSONのみ。1turnごとに以下のいずれかを返す。

```json
{
  "thoughtSummary": "short non-secret rationale",
  "actions": [
    { "type": "list_files", "path": ".", "maxDepth": 3 },
    { "type": "read_file", "path": "src/example.ts", "startLine": 1, "maxLines": 160 },
    { "type": "search", "query": "functionName", "path": "src", "maxResults": 20 },
    { "type": "run_command", "command": "pnpm test" }
  ]
}
```

書込段階では既存plan schemaへ収束させる。`write_files` は直接書込ではなく、既存 `CodingAgentPlan` へ変換される plan proposal action として扱う。

```json
{
  "thoughtSummary": "ready to write",
  "actions": [
    {
      "type": "write_files",
      "summary": "...",
      "directories": ["src"],
      "files": [{ "path": "src/example.ts", "content": "..." }],
      "deletePaths": [],
      "commands": ["pnpm test"]
    }
  ]
}
```

`write_files` は既存 `CodingAgentPlan` に変換して `apply_coding_agent_plan` へ渡す。既存validation/repair/final answerを再利用する。explore loop中の `list_files` / `read_file` / `search` / `run_command` は観測phaseであり、ファイル書込を行わない。

### Tool Implementations

| Action | Implementation | Guard |
|---|---|---|
| `list_files` | workspace配下をdepth/件数上限つきで列挙 | excluded path除外、workspace外拒否 |
| `read_file` | text file excerptを返す | binary拒否、file size/read bytes上限、excluded path拒否 |
| `search` | Rust内部のliteral search。外部 `rg` には依存しない | query length上限、result count上限、text fileのみ、UTF-8 lossy decode、binary skip、case-sensitive既定、excluded path拒否 |
| `run_command` | 既存 `run_safe_command` | allowlist、timeout、network/pipe/redirect拒否。生成物・cache・lockfile副作用はworkspace hash差分として記録 |
| `write_files` | 既存 `apply_coding_agent_plan` | write-plan境界、relative path、max bytes、validation |

`run_command` はテスト/検証目的に限定する。command実行で生成・変更されたファイルはworkspace hash差分で検知し、意図しないlockfileやbuild artifactが残る場合はfailureまたはwarningとして記録する。

`read_file` の同一ファイル再読み込みは `maxReadFiles` を追加消費しない。ただし `maxReadBytes` は毎回消費する。これにより同一ファイルの別範囲確認は許可しつつ、無限再読みによるcontext肥大を防ぐ。

### Protected Test / Validation Files

agentはテスト/検証ファイルを書き換えてPASSを偽装してはならない。以下を両方で防ぐ。

- write guard: PERF task metadataでprotected paths/globsを指定し、`write_files` / delete / command side effectで変更されたら拒否する。
- scorer: workspace hash/diffでprotected filesの変更を検出し、変更があれば即FAILにする。

初期対象はE群必須。可能ならA-Cにも同じmetadataを入れ、既存taskでテスト/検証ファイル改変が不要なものは保護する。

### Event / Evidence

既存stepを増やしすぎず、`worker_coding_agent` stepのtool_call outputにloop summaryを持たせる。詳細はevent payloadへ出す。

- `worker_coding_agent.loop.started`
- `worker_coding_agent.turn.requested`
- `worker_coding_agent.tool.completed`
- `worker_coding_agent.write.applied`
- `worker_coding_agent.validation.completed`
- `worker_coding_agent.loop.completed`
- `worker_coding_agent.loop.failed`
- `worker_coding_agent.mode.selected`
- `worker_coding_agent.mode.escalated`

各eventはsecretを含まないexcerptのみ。full file contentは証跡へ入れず、path/hash/byte count中心にする。

secret対策:

- transcript/eventへfull file contentを保存しない。
- command stdout/stderrはtruncateし、token/API key/passwordらしい値をmaskする。
- hidden filesは既定ではsnapshot/search対象外。ただしfixtureで明示許可された安全ファイルだけ読む。
- symlinkはcanonicalize後にworkspace外なら拒否する。
- binary fileはread/search対象外。

### Failure Classes

- `budget_exhausted`
- `timeout`
- `json_parse_failed`
- `planning_failed`
- `invalid_action_json`
- `tool_denied`
- `path_denied`
- `command_denied`
- `command_timeout`
- `command_failed`
- `read_limit_exceeded`
- `search_limit_exceeded`
- `write_guard_rejected`
- `apply_failed`
- `validation_failed`
- `repair_failed`
- `provider_error`
- `no_write_plan`
- `iteration_limit_exceeded`
- `context_limit_exceeded`
- `no_progress_detected`
- `escalation_failed`
- `unsafe_action_requested`
- `internal_error`

PERF harness側は、これらをrunner_errorではなくagent failureとして扱う。ただしtask定義・fixture破損・scorer crashはrunner_error。

## Implementation Steps

1. Add loop state/action types and parsers next to existing `CodingAgentPlan`.
2. Add guarded tool functions for list/read/search using existing workspace path validation.
3. Add `run_coding_agent_explore_loop` that calls provider repeatedly until `write_files` or budget exhausted.
4. Route mode selection inside `run_internal_worker_coding_job_in`.
5. Convert `write_files` action to existing `CodingAgentPlan` and reuse apply/validation/repair.
6. Extend telemetry with mode, turn count, tool count, budget exhaustion, and failure class.
7. Add UT for schema parsing, budget, path guard, command guard, and mode selection.
8. Add IT for one explore task where initial snapshot omits relevant file and search/read is needed.
9. Extend PERF fixture/harness for E群.
10. Run local tests, then WindowsQA official E群.

## PERF Fixture Reset Strategy

E群fixtureは50-100ファイル規模になるため、毎attemptで依存ディレクトリを削除しない。resetは以下を標準にする。

- git管理ファイルは `git reset --hard` 相当で戻す。
- untracked generated artifactsはscorer対象外の既知artifactだけ削除する。
- `node_modules` / package manager cache / CLI auth cacheは維持し、warm cache状態をsummaryへ記録する。
- protected test/validation filesはreset後hashを記録し、attempt後に再照合する。

## Internal Agent v3 Phase Machine

`internal-agent-v3` の最初の実装スコープは、常駐repo indexやWorker記憶ではなく、大規模タスクでv2.1が失敗した「探索はできるが収束できない」問題に対するphase machineとする。実装済み範囲は、`Investigate -> Reproduce -> Fix -> Validate` の4フェーズ、仮説lock、answer-only脱出、reproUnavailable脱出、reverse patch warning、PERF証跡へのphase/repro/reverse telemetry出力である。

実装commit:

- `db8899d` phase telemetry
- `beed91e` hypothesis lock
- `b93065c` Reproduce gate
- `3090374` reverse patch warning
- `2e45845` PERF evidence extraction
- `c99bf50` reproduce gate evidence
- `ad8ac9b` repro red後のFix誘導
- `f94f6d5` repro red後のprewrite related test skip

P6診断:

- 証跡: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-v3-p6-diagnostic-fix2-20260707-095627/summary.json`
- lane: `l1-job`
- tasks: `F2,F5`
- result: `PASS_WITH_DIAGNOSTIC_ONLY`
- 判定: v3.0 P6はgating診断として完了。F5はPASSし、F2 attempt-1は`Investigate -> Reproduce -> Fix -> Validate`へ到達した。F2品質FAILとF2 attempt-2のReproduce停滞は、v3.0完了条件ではなく次フェーズの改善対象として扱う。

次の改善候補は、F2/F5個別調整ではなく、`reproRedObserved` 後の遷移条件とロック例外の一般化である。現在はred後に`list/search/run`を拒否し、`read_file`はlocked targetのみ許可する。これはFix誘導には有効だが、locked targetが誤った場合や依存ファイル/型定義が必要な場合に品質を落とすため、v3.1では「理由付きの限定例外」を設計する。

### Internal Agent v3.1 Candidate: Red後の限定読取例外

v3.1の目的は、v3.0で確認したFix誘導を崩さず、red後の修正品質だけを上げることである。F2/F5専用の語録・ファイル名分岐・oracle専用処理は入れない。

方針:

- `reproRedObserved=true` 後も、`list_files` / `search` / `run_command` は原則拒否を維持する。
- `read_file` はlocked targetに加えて、locked targetから1-hopの静的相対依存ファイルだけを限定許可する。
- 1-hop静的相対依存は、locked target本文中の `import ... from "./x"` / `export ... from "./x"` / `require("./x")` / `import("./x")` から抽出する。package import、alias import、tsconfig pathsはv3.1対象外。
- 許可対象はcanonicalize後にworkspace root配下へ残る実ファイルに限定する。symlinkや `../` によりroot外へ出る場合は拒否する。
- 許可対象の拡張子は `.ts` / `.tsx` / `.js` / `.jsx` / `.mjs` / `.cjs` / `.json` / `.d.ts` とする。extensionless importは候補順に解決する。
- 許可数はattemptあたり小さく制限する（例: `redDependencyReadCount <= 3`）。無制限な探索へ戻さない。
- locked target自体の再読取は上限カウント対象外。1-hop依存読取だけをattempt単位でカウントする。
- 許可/拒否はtelemetryに `redDependencyReadCount` / `redDependencyReadLimit` / `redReadDenialReason` として残す。denial reasonは安定enumとし、`not_direct_dependency` / `unsupported_extension` / `outside_workspace` / `symlink_escape` / `limit_exceeded` / `resolution_failed` / `tool_denied_after_red` を使う。
- telemetryにファイル内容は残さない。必要ならpath/reason/countだけ記録する。
- locked targetが誤っているケースは、v3.1では完全解決しない。別仮説への戻りはv3.2以降の「hypothesis relock」候補に分離する。

期待効果:

- red後にFixへ進む流れは維持する。
- Fixに必要な近接helper/type情報を読む余地ができ、局所的に壊れたfull replacementを減らす。
- F2/F5のような個別タスクへの過学習ではなく、TS/JS repo全般で使える小さい例外になる。

P6.1 acceptance:

- UT: red後のlocked target readは許可。
- UT: red後の直接import dependency readは上限内で許可。
- UT: extensionless importと`./foo/index.ts`を解決できる。
- UT: `../`またはsymlinkでworkspace外へ出る依存は拒否。
- UT: direct importでない同一ディレクトリファイルは拒否。
- UT: red後の非依存read/list/search/runは拒否。
- UT: red dependency read上限超過は拒否し、telemetryに理由を残す。
- Static: `cargo fmt` / targeted Rust UT / `git diff --check` PASS。
- Diagnostic: `ORB-PERF-002` の `l1-job` `F2,F5` 部分runで、telemetryにred後の許可/拒否が記録されること。品質PASSはP6.1の必須条件にしない。

P6.1診断:

- 実装: `src-tauri/src/internal_worker_coding_agent.rs` にRed後のdirect relative dependency read例外、`scripts/qa/orb-perf-002.mjs` にtelemetry集約を追加。
- UT: `cargo test --manifest-path src-tauri/Cargo.toml --features web-remote internal_worker_coding_agent::tests` は35件PASS。locked target/direct dependency/index/root escape/2-hop拒否/symlink escape/上限拒否を含む。
- Static: `cargo fmt` / `node --check scripts/qa/orb-perf-002.mjs` / `git diff --check` PASS。
- Review: codex-adviserで実装レビュー。方針は妥当、コミット前確認として2-hop拒否・canonical/symlink escape・attempt上限の明示テストが推奨されたため、UTへ反映済み。
- Diagnostic: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-orb-perf-002-v31-p6-diagnostic-20260707-104100/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F5 attempt-1: PASS。`redDependencyReadCount=1`, `redDependencyReadLimit=3`, `redReadDenialReason=null`。Red後の限定依存readが実際に発火した。
  - F2 attempt-1/2: FAIL（品質課題継続）。attempt-1は `redReadDenialReason=resolution_failed` を記録。P6.1の目的である許可/拒否telemetryの記録は成立。

### Internal Agent v3.2 Candidate: Red後の仮説relock

P6.1診断のF2では、注入バグが `packages/vite/src/node/publicDir.ts` に残ったまま、Workerは `packages/vite/src/node/server/middlewares/static.ts` をlocked targetとしてFixへ進んだ。これはdirect dependency readの不足というより、誤ったlocked hypothesisがred後に固定され続ける問題である。

v3.2の目的は、red確認後のFix誘導を維持しつつ、限定条件で別仮説へ戻れる脱出路を作ることである。探索を全面再開しない。F2専用のファイル名分岐・語録は禁止する。

codex-adviserレビューにより、通常の `Investigate` へ戻す表現は危険と判断した。v3.2では `RelockHypothesis` 専用phaseとして扱い、通常Investigateのtool policyを継承しない。

方針:

- `reproRedObserved=true` 後も、原則はFix継続。
- ただし、Red後readが `resolution_failed` / `not_direct_dependency` で詰まり、現在のlocked targetだけではfull replacementが成立しない場合のみ、1回だけ `RelockHypothesis` phaseへ遷移する。
- relock回数はattemptあたり1回まで。`relockCount` / `relockReason` / `previousLockedHypothesisId` をtelemetryへ記録する。
- relock入力は、previous locked hypothesis、locked target、既読ファイル、direct dependency map、read denial reason、observed red evidence、現在までの観測に固定する。
- relock phaseでは `list_files` / `search` / `run_command` / arbitrary readは禁止。LLMには新しいhypothesis 1件と `lockedHypothesisId` だけを要求する。
- relockで同じhypothesis idまたは同じtarget filesを返した場合は拒否し、`deniedRelockReason=same_locked_hypothesis|same_locked_target` を記録する。
- proposed writeがlocked target外へ広がっただけではrelock triggerにしない。これはwrite逸脱として扱う。relock triggerにする場合は、既存証拠が別targetを支持していることが必要だが、v3.2最小実装では扱わない。
- validation/oracle失敗一般やchanged files不一致だけではrelock triggerにしない。これは広すぎるためv3.2最小実装から除外する。
- telemetryは `relockCount` / `relockReason` / `previousLockedHypothesisId` / `newLockedHypothesisId` / `previousLockedTargetFiles` / `newLockedTargetFiles` / `deniedRelockReason` を持つ。
- relock後に再度redを確認できた場合のみFixへ進む。redが取れない場合は既存の `reproUnavailable` 経路へ落とす。
- reverse patch guard、protected paths、write-plan境界は維持する。

P6.2 acceptance候補:

- UT: red後に `resolution_failed` / `not_direct_dependency` が出ても、relock未使用なら1回だけ `RelockHypothesis` phaseへ入る。
- UT: relockはattemptあたり1回まで。2回目は拒否してFix/stopへ向かう。
- UT: relock時にprevious/current locked hypothesisをtelemetryへ残す。
- UT: relockで同じtargetへ戻る場合は拒否する。
- UT: relock phaseでは list/search/run/read/write_files を拒否し、新hypothesis lockだけを受け付ける。
- UT: relock後の新hypothesisではred再確認が必須。
- Diagnostic: `ORB-PERF-002` の `l1-job` `F2,F5` 部分run。F2でrelockが発火するかを確認し、品質PASSは必須にしない。F5が悪化しないことを確認する。

P6.2診断:

- 実装: `RelockHypothesis` phaseを追加。通常 `Investigate` へ戻さず、Red後のread denialから1回だけ限定relockできるようにした。
- UT: `cargo test --manifest-path src-tauri/Cargo.toml --features web-remote internal_worker_coding_agent::tests` は38件PASS。relock 1回制限、relock後red再確認、同一target拒否を含む。
- Static: `cargo fmt` / `node --check scripts/qa/orb-perf-002.mjs` / `git diff --check` PASS。
- Review: codex-adviserで設計レビュー。`Investigate`へ戻さず専用 `RelockHypothesis` phaseにすること、triggerを `resolution_failed` / `not_direct_dependency` 起点へ絞ること、同一target relock拒否を反映。
- Diagnostic 1: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-orb-perf-002-v32-relock-diagnostic-20260707-110949/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F2: relock発火。ただし新hypothesisが同じ `static.ts` へ戻り、品質FAIL。これを受けて同一target relock拒否を追加。
  - F5: provider `HTTP error 500` によりagent_error。ロジック判定不能。
- Diagnostic 2: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-orb-perf-002-v32-relock2-diagnostic-20260707-112830/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F2 attempt-1: 品質FAIL、relock未発火。attempt-2: provider `HTTP error 500` によりagent_error。
  - F5: provider `HTTP error 500` によりagent_error。
- Diagnostic 3: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-orb-perf-002-v32-f5-diagnostic-20260707-114440/summary.json`
  - F5単体再実行もprovider `HTTP error 500` でagent_error。P6.2のF5非劣化診断はprovider障害により未確定。

P6.2時点の判断:

- 制御ロジックのUTは成立。
- 実LLM診断はKimi provider 500が連続し、品質評価としては不成立。再実行はprovider回復後に行う。以後、PERF harnessではHTTP 500 / provider api_errorを `provider_unavailable` として分類し、agent品質FAILと分離する。
- Provider分類確認: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-orb-perf-002-provider-classifier-check-20260707-115252/summary.json` でF5 attempt-1が `failureClass=provider_unavailable` となり、retryせず停止することを確認。
- OAuth refresh / credential failure分類: `invalid_grant` / OAuth未設定 / OAuth refresh失敗は `auth_unavailable` として分類し、agent品質FAILと分離する。これはKimi専用設計ではなく、今回の評価環境でKimiが使える前提を維持したまま、認証状態の問題を性能・品質判定から分離するための分類である。
- F2品質改善はまだ未成立。次候補は、relock候補生成が同じtargetへ戻らないだけでなく、既読/changed/evidenceから別targetを選べる材料をどう渡すかの改善。

### Internal Agent v3.3 Candidate: evidence-aware relock

v3.3の目的は、v3.2で追加した `RelockHypothesis` phaseを探索再開にせず、既存証拠の再解釈として強化することである。Kimi依存の実LLM評価はprovider状態に左右されるため、まず静的実装とUTでphase境界を固定する。

codex-adviserレビューでは、v3.3のevidence-aware relockは妥当と判断された。推奨は、same target後に再プロンプトしないこと、deterministic candidate hintsを既存observationだけから生成すること、relockを「探索」ではなく「既存証拠の構造化」に限定することである。

方針:

- `RelockHypothesis` promptに、previous locked hypothesis、previous locked target、read denial、red evidence、既読ファイルから抽出した相対import hintを明示する。
- hint生成は既存observation文字列だけを入力にし、filesystem read/list/search/path existence checkは行わない。
- repo-wide search、追加read、追加run、再プロンプトは行わない。
- 同一hypothesis id / 同一target files拒否は維持する。
- F2固有のファイル名、oracle固有の語彙、テスト用分岐は入れない。

P6.3実装:

- 実装: `Relock evidence` blockをexplore promptへ追加。`phase=relockHypothesis` 以外では無効。
- 実装: `read_file path=...` の既存observation本文から `import/export/require/import()` の相対specifierを抽出し、candidate hintとして提示する。
- 実装: read denialとred command outputのexcerptをRelock evidenceへ含める。
- UT: Relock evidenceが既存read/import、read denial、red evidenceを含むことを確認。
- UT: Relock phase外ではRelock evidenceが無効化されることを確認。
- UT: `cargo test --manifest-path src-tauri/Cargo.toml --features tauri-backend,web-remote internal_worker_coding_agent -- --nocapture` は40件PASS。

P6.4実装:

- 実装: `Relock evidence` に、既存hypothesis listから前回locked target以外の代替仮説を `alternativeHypothesesFromExistingEvidence` として提示する。
- 制約: 追加のfilesystem read/list/search/path existence checkは行わず、既存LLM応答と既存observationだけを再構造化する。
- 目的: same target拒否後に、LLMが既存証拠内の別target候補を選びやすくする。F2固有ファイル名・oracle語彙・テスト用分岐は入れない。
- UT: Relock evidenceに代替仮説が含まれることを確認。
- UT: `cargo test --manifest-path src-tauri/Cargo.toml --features tauri-backend,web-remote internal_worker_coding_agent -- --nocapture` は40件PASS。
- Diagnostic: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-v34-l1-f2f5-diagnostic-20260707-123633/orb-perf-002-orb-perf-002-v34-l1-f2f5-diagnostic-20260707-123633/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F2: attempt-1は品質FAIL、attempt-2はPASS。retry成功時は `currentExplorePhase=validate` / `runCommandCount=1`。
  - F5: attempt-1でPASS。`relockCount=1` かつ `deniedRelockReason=same_locked_target` を記録しつつ、最終的にValidate到達。
  - 備考: L1単独診断のためL3比thresholdは比較不能。品質効果確認として扱う。
- Diagnostic: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-v34-l1-f1f3f4-diagnostic-20260707-125714/orb-perf-002-orb-perf-002-v34-l1-f1f3f4-diagnostic-20260707-125714/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F1/F3/F4はいずれも品質FAIL。F1/F3はrelock後もReproduce周辺で収束できず、F4は `answer_only` として探索するが回答品質が足りない。
  - v3.4時点のL1 F群診断は、F2/F5 PASS、F1/F3/F4 FAILの2/5相当。v2.1の0/5からは改善したが、opencode超えには未達。

P6.5実装:

- 実装: `answer_only` のrequired actionを「final answer response」ではなく、validation `presentPaths` の回答ファイル作成へ修正。
- 実装: `answer_only` で一定量の探索後は追加のlist/search/read/runを拒否し、回答ファイルへの `write_files` を促す。
- UT: answer_onlyが回答ファイル作成を要求すること、探索予算後にwriteへ誘導されることを確認。
- UT: `cargo test --manifest-path src-tauri/Cargo.toml --features tauri-backend,web-remote internal_worker_coding_agent -- --nocapture` は42件PASS。
- Diagnostic: `/home/mnadmin/agent-projects/sysdev/qa-artifacts/orb-perf-002-v36-l1-f4-diagnostic-20260707-132519/orb-perf-002-orb-perf-002-v36-l1-f4-diagnostic-20260707-132519/summary.json`
  - status: `PASS_WITH_DIAGNOSTIC_ONLY`
  - F4: attempt-1は品質FAIL、attempt-2はPASS。`answer/F4.md` が生成され、rubricを満たした。
  - v3.6時点のL1 F群は、F2/F4/F5 PASS、F1/F3 FAILの3/5相当。

P6.6 / v3.7設計:

- 対象: v3.6後も残るF1/F3の「red/repro確認後、十分な証拠があるのに `write_files` へ進まずReproduce周辺で停滞する」問題。
- codex-adviser判断: red後に即 `write_files` を強制する案は危険。主方針は、locked hypothesisと既存observationを材料にした one-time `patch draft request` を挟み、LLMへ「これ以上探索せずpatch planを出す」ことを明示する。relock上限到達時のFix強制は、locked hypothesis・候補path・red観測が揃う場合だけの限定fallbackにする。
- 入れないもの: F1/F3固有ファイル名、oracle語彙、タスク別語録、red後の無条件write強制、reverse warning発生中の強制Fix。
- 必須telemetry: `patchDraftRequestIssued`, `patchDraftInputs`, `writeFilesPlanProducedAfterDraft`, `fixForcedAfterRelockLimit`, `noProgressExitPrevented`, `fixForcedAfterRed`, `relockDeniedReason`。
- UT観点: red観測済みかつlocked hypothesisありで `patch draft request` が1回だけ発火すること、発火後は追加探索ではなくFix/write_filesへ進むこと、locked hypothesisや候補pathが無い場合は強制しないこと、`answer_only` にはコードwrite誘導を適用しないこと、reverse warning中は強制Fixを抑止すること、F2/F5の既存PASS経路を壊さないこと。
- 実装方針: v3.7は設計固定まで。v3.8で小さく実装し、F1/F3 narrow diagnosticで効果を確認する。

P6.7 / v3.8実装:

- 実装commit: `bce1a69`
- 実装: red/repro確認後に観測actionが拒否され続ける場合、locked hypothesisと既存observationを入力にした one-time `patch_draft_request` を発火し、次turnで `write_files` へ収束させる。
- 制約: 発火条件は、`reproRedObserved=true`、locked hypothesisあり、targetFilesあり、`answer_only` ではない、reverse patch warningなし。F1/F3固有ファイル名・oracle語彙・タスク別分岐は入れない。
- telemetry: `patchDraftRequestIssued`, `patchDraftInputs`, `writeFilesPlanProducedAfterDraft`, `fixForcedAfterRelockLimit`, `noProgressExitPrevented`, `fixForcedAfterRed` を追加。
- UT: `patch_draft` 3件PASS、`answer_only` 3件PASS、`internal_worker_coding_agent` 45件PASS。
- 次: F1/F3 narrow diagnosticで品質効果を確認する。v3.8は制御改善であり、品質PASSを保証するものではないため、失敗時は証跡をそのままv3.9/v4設計材料にする。

長期目標はopencode同水準の模倣ではなく、常駐アプリ構造の優位でopencodeを超えること。候補要素は、タスク到着前に構築済みの常駐repoインデックス（symbol/import graph/test map）、1ターン複数actionの一括探索による往復数圧縮、Anima記憶基盤を使ったdispatch経験の蓄積、複数Workerによる並列仮説探索。詳細設計はv3.1以降で扱う。

記憶の責務は分離する。Anima記憶は案配層に限定し、Worker実績（誰に何を頼んで結果がどうだったか）、ユーザー好み、dispatch判断の学習を扱う。repo内部知識はAnima記憶へ保存しない。Worker記憶は専門層として、repoインデックス、コード知識、workspaceごとの過去タスクパターン、テスト対応表をworkspaceスコープに紐付けて保持し、ユーザー/会話文脈は保存しない。AnimaはWorker記憶の要約だけを参照できる。実装候補はworkspace内store（`.oribis-worker-store` 系の既存パターン）の延長にWorker側永続記憶として置く。

現状は、Anima側に4層記憶と会話/関係性の永続基盤が既にあり、Worker側にはjobs/events/artifacts/write-plan等の実行記録はあるが、repo構造・コード知識・過去タスクパターンを学習する専門記憶は未実装。したがってv3の主開発対象はWorker側専門記憶であり、Anima側はWorker委任結果を案配判断へ使う接続確認を中心に扱う。

## Out of Scope

- 任意shell実行。
- 任意workspaceRoot指定。
- LLMにbackend選択を任せること。
- 新しいWorker frameworkや別プロセスサーバー化。
- GUIの大幅追加。
- D群WebViewer routeの同時実装。

## Open Review Points for sysdev-2

1. `explore` mode selectionはmetadata/fixture category/workspace size/validation有無ベースでよいか。
2. E群のtimeoutは既存C群より長く、各タスク900-1500s程度を上限にする方針でよいか。
3. `search` はRust内部実装にして、`rg` など外部コマンド依存にしない方針でよいか。
4. transcriptにfile contentを残さず、excerpt/hash中心にする証跡粒度で足りるか。
5. E群PASSまでは `ORB-PERF-001` 全体をRelease blocker継続、D群/R1 waiverとは別枠で扱う方針でよいか。
