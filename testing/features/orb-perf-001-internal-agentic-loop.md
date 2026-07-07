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
