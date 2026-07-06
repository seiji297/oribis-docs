# ORB-PERF-001 Coding Agent Performance

## Purpose

ORB-PERF-001 verifies whether Oribis can ship with a practical coding-agent path, not just a chat answer path. It compares Oribis internal Worker execution against Oribis PTY/CLI execution and raw CLI execution under fixed tasks, fixed scoring, and WindowsQA official evidence.

`v0.1.0` tagging is blocked until this check is complete.

## Scope

This check covers coding-agent performance and routing correctness.

It does not replace existing ST/AT checks for Scene, WebViewer, TTS, onboarding, or release packaging. It is added as a pre-release required performance/acceptance check.

Anima chat latency and conversational quality are out of scope for ORB-PERF-001. They are retained as an ORB-PERF-002 follow-up candidate, not silently dropped.

Discord relay is out of this check unless a later release includes Discord in the same required scope.

## Prerequisite

Before running ORB-PERF-001, Anima must expose `oribis.core.workers.dispatch` in the AI-native App action catalog.

Required properties:

- Schema-driven App action only. No phrase/lexicon router.
- The Anima prompt may explain responsibility split, but dispatch must happen through the tool name and schema.
- Anima handles conversation, App operation, Scene/WebViewer light tasks, and short snippets itself.
- Anima delegates repository, filesystem, source-reading, multi-file, build/test, and non-trivial coding tasks to Worker.
- AI tool arguments must not choose arbitrary `backend`, `workspaceRoot`, or `workerId`.
- `workspaceRoot` is the active project workspace. External paths are rejected by schema or by handler policy.
- `timeoutMs` may be accepted only within the schema limit. The harness may apply stricter task timeout values.
- CLI/PTY backend comparison is performed by the PERF harness, not by arbitrary Anima tool arguments.

## Lanes

| Lane | Name | Meaning | Gate Role |
|---|---|---|---|
| L1-instant | Oribis Internal Instant Worker | Oribis internal Worker through the instant path | Reported and overhead-split |
| L1-job | Oribis Internal Persistent Worker | Oribis internal Worker through the job path | Required main L1 lane |
| L2-opencode-pty | Oribis PTY/CLI OpenCode | OpenCode CLI launched through Oribis Worker PTY/CLI harness | Required main L2 lane |
| L3-opencode-raw | Raw OpenCode CLI | OpenCode CLI launched outside Oribis with equivalent workspace and prompt | Required baseline |

Gate comparison uses only:

- L1-job vs L3-opencode-raw
- L2-opencode-pty vs L3-opencode-raw

Codex and Claude lanes are not used for ORB-PERF-001 Release Gate pass/fail.

`L1-job` is the only L1 Release Gate lane. `L1-instant` may be collected as secondary latency/overhead evidence, but it must not replace `L1-job` in the Release Gate calculation.

## Model And CLI Control

- L3 main baseline is raw OpenCode CLI.
- L1 provider/model, L2 OpenCode model, and L3 OpenCode model must use Kimi with the same model id.
- Required model id for the current release candidate is `kimi-for-coding/k2p7` unless Producer explicitly changes it.
- CLI version, model id, provider id, and harness version must be recorded.
- OpenCode account/auth files and Oribis Kimi OAuth files are secret material. They may be placed only under the QA user's profile or Oribis home, outside the repository and outside evidence payloads.
- Evidence may record only presence/absence and source class such as `user_env` or `user_profile_file`; values must be masked.
- Secrets, API keys, cookies, tokens, and auth headers must not be recorded. If a command emits one, the evidence is invalid until redacted and re-run or reclassified.

## Task Set

The task set contains 18 measured tasks and 2 routing checks.

Release Gate lane thresholds use A+B+C only: 14 measured coding tasks.

D tasks are reported separately as WebViewer/search usability. They do not count toward the lane 80%/2x gate.

R tasks are mandatory routing checks. They do not count toward the 14-task performance denominator.

### A. File Operations

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| A1 | Create a file with exact requested content | File exists and content exactly matches expected bytes | 90s |
| A2 | Rename a module and update two references | Expected diff matches and test command passes | 180s |
| A3 | Convert CSV fixture to JSON | JSON parses and equals expected output | 120s |
| A4 | Create requested directory tree | Tree listing equals expected structure | 120s |
| A5 | Replace and delete specified lines | Expected diff matches | 120s |

### B. Simple Code Generation

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| B1 | Generate FizzBuzz-level single file | Script runs and output matches expected | 180s |
| B2 | Implement known algorithm with tests | Unit tests pass | 240s |
| B3 | Add small CLI argument handling | CLI command outputs expected values for sample args | 240s |
| B4 | Explain an existing 200-line file | Rubric score passes; no file edits expected | 180s |

### C. Complex Coding

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| C1 | Fix known failing test in fixture repo | Red-to-green test passes | 420s |
| C2 | Multi-file refactor: move function and update imports | All tests pass and old import path is removed | 480s |
| C3 | Implement small feature from spec | Acceptance test passes | 540s |
| C4 | Answer source-reading question with call sites and roles | Rubric score passes; no file edits expected | 300s |
| C5 | Fix intentional build/type error | Build/typecheck command passes | 420s |

### D. Web/Search Usability

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| D1 | Extract information from local fixed test page | Route 5 Anima+WebViewer and route 6 Worker web route both run. Extracted values match expected JSON | 180s |
| D2 | Retrieve fact from real site with source URL | Route 5 Anima+WebViewer and route 6 Worker web route both run. Answer contains source URL and fact passes rubric | 300s |
| D3 | Compare multiple pages and output table | Route 5 Anima+WebViewer and route 6 Worker web route both run. Rubric score passes with source URLs | 420s |
| D4 | Fill a local form and capture result | Route 5 Anima+WebViewer only. Result text matches expected value | 240s |

D group usability floor: route 5 must pass at least 3/4, and route 6 must pass at least 2/3 for D1-D3 when that route is available. D4 is route 5 only.

Initial official sequencing:

- The first official run may execute A+B+C+R only, to answer the coding-performance risk without waiting for the WebViewer route harness.
- In that first run, all D tasks must remain in `notRunTasks` with a clear reason. They are not `BLOCKED` unless the required environment is unavailable; implementation-not-yet-wired is `NOT_RUN`.
- The first run is an intermediate official evidence run. It must not be reported as full ORB-PERF-001 PASS.
- Full ORB-PERF-001 PASS requires a later official run that includes D routes and passes the D group usability floor.
- If route 6 lacks a Worker web capability, record that as capability absence in the evidence and release report. Do not hide it as a generic test failure.

### R. Routing Checks

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| R1 | Ask Anima a C-class coding task | Anima emits `oribis.core.workers.dispatch`; direct degraded chat answer is FAIL | 120s |
| R2 | Send an A1-sized trivial task through persistent Worker | Task passes and overhead is reported separately | 120s |

R1 and R2 are required PASS checks but excluded from completion-rate denominator.

### E. Heavy Agentic Coding

E tasks are required for EA release after the 2026-07-06 scope change. They verify that Oribis Internal Worker can handle tasks that structurally require multi-turn exploration, not only small single-shot edits.

E tasks are evaluated in a separate heavy-task run after the bounded exploratory internal agent loop is implemented. They do not replace the A+B+C result; they add a new required gate.

| task_id | Summary | Acceptance | Timeout |
|---|---|---|---|
| E1 | Add a multi-file feature to a medium fixture repo with 50-100 files | Acceptance tests pass, expected files are changed, no unrelated broad rewrite | 1200s |
| E2 | Fix a symptom-only bug where the cause is in a different module | Failing regression test turns green, root-cause file is changed, symptom-only patch is rejected by scorer | 900s |
| E3 | Iterate on a failing test group until all targeted tests pass | Initial failing tests pass after at least one test command feedback loop; no validation override | 1200s |
| E4 | Perform a cross-cutting refactor across imports/call sites | Typecheck/tests pass, old API/import path is absent, new API is used consistently | 1500s |
| E5 | Change an API across package or module boundaries | Consumer and provider tests pass, compatibility shim only if explicitly required | 1500s |

E group thresholds:

- Gate denominator: E1-E5, 5 tasks.
- L1-job completion count on E must be at least 80% of L3-opencode-raw completion count on the same E tasks.
- L2-opencode-pty completion count on E must be at least 80% of L3-opencode-raw completion count on the same E tasks.
- Required completion count uses ceiling rounding. Example: if L3 passes 4/5, each compared lane must pass at least `ceil(4 * 0.8) = 4`.
- Median time ratio uses only tasks where both compared lanes pass and must be <= 2.0, same as A+B+C.
- If L3-opencode-raw cannot complete any E task, the E run is `BLOCKED` because the baseline is invalid.
- If L1 uses single-shot mode for an E task without entering explore mode, that task is a product failure unless the task still satisfies acceptance and loop telemetry shows a valid reason for single-shot selection.

E group evidence must additionally include:

- agent mode per task: `singleShot` or `explore`.
- mode selection reason and threshold values.
- escalation events when `singleShot` validation+repair fails and the same job continues in `explore`.
- turn count, tool call count, command count, and budget exhaustion flag.
- per-turn action transcript with secret-safe excerpts.
- workspace hash before/after.
- failure class if not passed.
- timeout rate and worst-case duration, in addition to median ratio.
- unsafe command/path guard bypass count. This must be 0.
- validation false-positive known cases. This must be 0.

E group fixture scoring must define a task-specific success oracle. Validation PASS alone is not enough when a task can pass through a superficial or symptom-only patch. Each E task must declare:

- required test/typecheck/build command.
- expected changed area or forbidden broad rewrite area.
- forbidden shortcut or symptom-only patch when applicable.
- protected test/validation paths or globs. If the agent changes them, the task is immediate FAIL.
- rubric only when deterministic scoring is insufficient.

The harness should apply protected test/validation file checks to A-C tasks as well when the task does not explicitly require test edits. This prevents a general cheat path where an agent modifies tests instead of product code.

E workspace reset strategy:

- reset tracked fixture files between attempts.
- keep dependency cache and `node_modules` warm when safe, and record cache state.
- record protected file hashes before and after each attempt.

Full EA release gate for ORB-PERF-001 now requires:

- first Kimi unified A+B+C official result accepted.
- E group official result passes thresholds.
- D/R waived items remain explicitly recorded until their expiry condition.

## Fixture Rules

- A dedicated fixed fixture repo is used.
- Each task starts from a fresh workspace reset.
- Fixture version/hash is recorded.
- Dependency cache is warmed once before measured runs and the warmup is recorded.
- `node_modules`, pnpm store, and relevant CLI cache state are recorded as present/absent and warm/cold.
- The harness must not change scoring criteria after seeing results.
- All measured tasks run serially. The QA machine must be kept free of unrelated heavy workload during the run.
- Each task allows one initial attempt plus one retry.
- Retry is allowed only after failure or timeout.
- Both attempts are recorded.
- A task may pass through retry success.
- Median time calculations use the duration of the passed attempt for tasks that pass. Failed/timeout attempts are reported in descriptive statistics but are not used for the successful-pair median ratio.
- Task evidence is written incrementally after every attempt. A final summary alone is not sufficient; aborted runs must preserve partial evidence.
- The same task prompt hash must match across all lanes. If a lane needs CLI-specific wrapper text, the canonical task prompt is still hashed and recorded separately from wrapper text.

## Scoring

Primary scoring must be deterministic where possible:

- command exit code
- unit test result
- typecheck/build result
- exact diff
- exact file tree
- exact JSON output

Rubric scoring is allowed only for B4, C4, D2, and D3. Rubric output must include the rubric version, score, and reason.

Fallback answer generation is not an automatic failure if the task acceptance check passes. It must be recorded as `fallback_used=true`.

If fallback usage exceeds 30% in a lane, the release report must mark it as a quality concern even if the lane passes thresholds.

`error` status counts as failure. `skipped` is not allowed for required lanes; any skipped required lane task with a missing or unsupported environment makes ORB-PERF-001 `BLOCKED`.

`runner_error` is reserved for cases where the harness did not provide a valid attempt opportunity, such as broken task definitions, scoring crashes, workspace creation failures, required command installation failures, or evidence-write failures. Agent-produced missing files, wrong content, failed unit tests, invalid JSON, and timeouts are agent failures, not `runner_error`.

## Gate Thresholds

Gate denominator:

- A+B+C only: 14 tasks.
- R and D are excluded from lane performance denominator.

Completion threshold:

- L1-job completion count on A+B+C must be at least 80% of the L3-opencode-raw completion count on the same 14 tasks.
- L2-opencode-pty completion count on A+B+C must be at least 80% of the L3-opencode-raw completion count on the same 14 tasks.
- Required completion count uses ceiling rounding. Example: if L3 passes 13/14, each compared lane must pass at least `ceil(13 * 0.8) = 11`.
- If L3-opencode-raw is blocked or cannot complete any A+B+C task, ORB-PERF-001 is `BLOCKED` because the baseline is invalid.

Time threshold:

- Compare only tasks where both compared lanes passed.
- L1-job median duration divided by L3-opencode-raw median duration must be <= 2.0.
- L2-opencode-pty median duration divided by L3-opencode-raw median duration must be <= 2.0.
- p90 ratio and failure-including attempt statistics are reported but do not replace the median gate.

Timeout:

- Timeout is a task failure.
- For descriptive statistics that include failures, timeout duration is recorded as the task timeout value.

## Partial Rerun

`--only-tasks` may be used to avoid re-running every task during failure triage.

Rules:

- The first full official run remains immutable.
- A partial rerun must have its own run id and must record `partialRun.onlyTasks`.
- It may replace a task result in Release Gate interpretation only when the original failure was a harness defect or environment defect that prevented a valid attempt.
- Agent failures recovered by partial rerun are reported as recovery evidence, not as first-pass success.
- Partial reruns must use the same commit, docs commit, task definitions, model id, and lane definitions as the full run unless explicitly marked diagnostic.

## Required Summary Fields

The official summary JSON must include:

- `schemaVersion`
- `testId`: `ORB-PERF-001`
- `official`
- `sourceMode`
- `requestedCommit`
- `resolvedCommit`
- `docsCommit`
- `runId`
- `startedAt`
- `endedAt`
- `platform`
- `cpu`
- `gpu`
- `ram`
- `osVersion`
- `nodeVersion`
- `pnpmVersion`
- `rustVersion`
- `webView2Version` when available
- `harnessSha256`
- `fixtureVersion`
- `fixtureHash`
- `cacheState`
- `lanes`
- `tasks`
- `routingChecks`
- `aggregates`
- `thresholds`
- `thresholdResult`
- `fallbackRate`
- `notRunTasks`
- `dGroup`
- `dGroupThreshold`
- `evidencePaths`
- `secretScan`

Each task attempt must include:

- `lane`
- `taskId`
- `category`
- `attempt`
- `workspacePath`
- `workspaceHashBefore`
- `workspaceHashAfter`
- `promptHash`
- `timeoutMs`
- `startedAt`
- `endedAt`
- `durationMs`
- `status`: `pass`, `fail`, `timeout`, `error`, or `skipped`
- `agentExitCode`: process exit code when available; otherwise `null`
- `failureClass`
- `fallbackUsed`
- `tokenUsage`: input/output/total token counts when available; otherwise `null` with `tokenUsageUnavailableReason`
- `costEstimate`: provider currency estimate when available; otherwise `null` with `costUnavailableReason`
- `retryCount`
- `filesChangedCount`
- `scoreMethod`
- `scoreEvidence`
- `stdoutLogPath`
- `stderrLogPath`
- `transcriptPath`

Each lane entry must include:

- `lane`
- `backend`
- `providerId`
- `modelId`
- `cliName`
- `cliVersion`
- `backendCommandHash`
- `environment`
- `officialGateRole`

## Evidence

Official WindowsQA evidence must contain:

- summary JSON
- lane/task transcript logs
- scoring logs
- fixture hash file
- harness hash file
- environment snapshot
- secret-scan result
- result table in Markdown or JSON
- per-attempt evidence files written during the run, not only the final summary

Evidence aliases such as `latest-*` are not accepted for Release Gate. Manifest entries must use run-id-specific immutable paths and hashes.

## Result Classes

| Result | Meaning |
|---|---|
| PASS | All required thresholds and routing checks pass |
| FAIL | One or more required thresholds or routing checks fail |
| BLOCKED | Required lane cannot run because environment is missing or broken |
| PASS_WITH_DIAGNOSTIC_ONLY | Existing taxonomy value for diagnostic/supporting runs only. It is never a Release Gate PASS |

Mock LLM evidence is not accepted for ORB-PERF-001 official pass.

## Reporting Format

The report to sysdev-2 must include:

- commit SHA under test
- harness commit/SHA
- docs commit/SHA when available
- lane x category completion table
- lane x category median/p90 time table
- L1/L3 and L2/L3 ratio table
- R1/R2 routing result
- D group usability result
- fallback rate per lane
- top failure modes
- evidence paths and hashes
- release decision: PASS, FAIL, BLOCKED, or DIAGNOSTIC_ONLY

If thresholds fail, report Producer decision options:

- improve internal agent path and re-run
- change default backend for coding tasks
- ship internal path as experimental only
- defer v0.1.0 tag
