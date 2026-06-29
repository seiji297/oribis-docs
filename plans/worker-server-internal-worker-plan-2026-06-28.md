# Worker Server / InternalWorker Plan

Date: 2026-06-28
Status: Phase 1 partially implemented
Owner: sysdev

## Scope

This plan covers only:

- WorkerServer boundary for the current Oribis built-in Worker.
- InternalWorker job lifecycle cleanup.
- In-process WorkerClient as the first transport.
- A server-ready contract for future external Worker backends.

This plan does not implement:

- OpenCode/Codex/Claude external CLI backends.
- PTY-backed persistent TUI Workers.
- AnimaCoordinator split.
- Auto-apply file edits.
- Arbitrary shell execution.

Those features depend on this WorkerServer/InternalWorker contract being stable first.

## Current Problem

The current Worker chat path has improved from the old direct `worker.instant.run` path:

- DOM chat submit creates an `InternalWorkerJob`.
- `internal_worker_run_job` runs the WorkerServer chat lifecycle.
- WorkerServer runs readonly tool requests, `answer_generate`, `finalAnswer` persistence, and completion.
- `anima_chat` is no longer responsible for the Worker final answer.

Completed in Phase 1 so far:

- Normal main-chat and Worker-chat UI paths create and run one Worker job, then render `job.finalAnswer`.
- `finalAnswer` generation is owned by the WorkerServer chat job lifecycle in the normal path.
- Worker job lifecycle owns `answer_generate` as a step.
- AgentServer `Full` Worker Job execution uses the same `run_chat_job` lifecycle.
- `answer_generate` failure marks the job failed.

Remaining problem:

- Worker terminal evidence still centers on `workspace_plan_readonly`.
- The future external WorkerServer process boundary still needs its concrete runner/server split.
- CLI backend, PTY backend, and remote WorkerServer integration still need follow-up validation.

## Target Outcome

For the built-in InternalWorker:

```text
DOM chat submit
  -> WorkerClient
    -> InternalWorkerRuntime
      -> create_job
      -> run_job
        -> read/search/context
        -> plan
        -> answer_generate
        -> completed
      -> finalAnswer
  -> UI renders job finalAnswer
```

The UI must not call a separate answer-generation command in the normal path.

## Core Contracts

### Job Kind

Phase 1 must distinguish job intent explicitly.

Initial values:

- `chat`: user-facing Worker chat job. Must end with `finalAnswer` on success.
- `batch`: non-chat background job. Deferred in Phase 1.
- `validation`: validation-only job. Deferred in Phase 1.

Rule:

- Phase 1 implements `chat` only for the current DOM chat path.
- Do not use a boolean such as `chatFacing` as the long-term contract.
- If the existing schema cannot add `jobKind` immediately, store `metadata.jobKind = "chat"` as a temporary compatibility field and enforce it in the runtime.

### Worker Job State

Use explicit state rules:

- `queued`: job exists but has not started.
- `running`: job is executing steps.
- `waitingPermission`: job requires user approval.
- `waitingUserInput`: job requires user input.
- `completed`: all required steps completed and `finalAnswer` exists when the job is chat-facing.
- `failed`: a required step failed.
- `cancelled`: user/system cancellation completed.
- `timeout`: job exceeded deadline.
- `partial`: reserved for future non-chat batch jobs only.

Rule:

- Chat-facing Worker jobs must not be marked `completed` without `finalAnswer`.
- `answer_generate` failure should make the chat-facing job `failed`, not silently completed.
- `partial` must not be produced in Phase 1.
- Terminal states must not transition back to running in the normal path.

Initial transition table:

```text
queued -> running
running -> completed | failed | timeout | cancelled | waitingPermission | waitingUserInput
waitingPermission -> running | cancelled | failed
waitingUserInput -> running | cancelled | failed
completed -> terminal
failed -> terminal
timeout -> terminal
cancelled -> terminal
```

Retry rule:

- Phase 1 does not implement force regeneration.
- Existing `finalAnswer` returns idempotently.
- If retry is needed, create a new job unless an explicit retry contract is added later.

### Worker Step Types

Initial step names:

- `context_summary`
- `workspace_plan_readonly`
- `git_status_readonly`
- `answer_generate`

Later, but not in this phase:

- `code_proposal`
- `validation_plan`
- `dry_run`

### Event Schema Requirements

Every Worker event must be able to support streaming and replay:

- `eventId`
- `jobId`
- `sequence`
- `timestamp`
- `kind`
- `stepName`
- `status`
- `severity`

Recommended, but avoid broad schema churn if existing fields are not ready:

- `workerId`
- `stepId`
- `payloadVersion`
- `correlationId`

Existing fields can be reused where present. Missing fields should be added only as needed for this phase, without broad schema churn.

### Artifact Contract

Initial artifacts:

- tool output JSON
- inline `job.finalAnswer` for chat display

Deferred:

- final answer raw provider artifact
- prompt transcript artifact

Later:

- code proposal artifact
- validation plan artifact
- CLI transcript artifact

### Capability Contract

InternalWorker Phase 1 capabilities:

- `worker.context`
- `workspace.read`
- `git.status.read`
- `worker.answer.generate`

Explicitly not enabled in this phase:

- file write apply
- arbitrary shell run
- external network by default
- PTY
- secret read

Rule:

- Each step must pass a `CapabilityPolicy` check before execution.
- Capability declaration without enforcement is not enough.
- `answer_generate` requires `worker.answer.generate`.

### Run Job Contract

Phase 1 uses blocking `runJob`.

Rule:

- `runJob(jobId)` returns the completed terminal job for the normal UI path.
- Event streaming/replay remains available through `listEvents(jobId)`.
- Streaming token UI is not part of Phase 1.
- The UI renders `job.finalAnswer` from the returned terminal job.

## WorkerServer Boundary

`WorkerServer` is the public service boundary, but implementation should not become one large object.

Internal modules should be separable:

```text
WorkerServer
  -> WorkerRegistry
  -> JobStore
  -> EventStore
  -> ArtifactStore
  -> CapabilityPolicy
  -> WorkerRuntime
```

For Phase 1, this can stay in-process and may wrap the existing `internal_worker.rs` functions.

## WorkerClient Boundary

The UI should call a WorkerClient-shaped API even before a separate server process exists.

Minimum client methods:

```text
createJob(request)
runJob(jobId, options)
getJob(jobId)
cancelJob(jobId)
listEvents(jobId)
```

Phase 1 implementation:

- `InProcessWorkerClient` calls existing Tauri commands or Rust functions.
- UI stops orchestrating internal Worker steps directly.
- Normal chat path calls `runJob` and renders returned `job.finalAnswer`.
- `runJob` is blocking for Phase 1 and returns a terminal job.

## InternalWorkerRuntime Phase 1

### Required Change

Move answer generation into the job run lifecycle.

Current:

```text
UI
  -> internal_worker_run_job
  -> internal_worker_generate_answer
```

Target:

```text
UI
  -> workerClient.runJob
      -> internal_worker_run_job
          -> tool steps
          -> answer_generate step
          -> finalAnswer persisted
```

`internal_worker_generate_answer` can remain temporarily for compatibility or manual retry, but it must not be the normal chat path.

### answer_generate Step

Responsibilities:

- Build Worker-only answer prompt from job instruction, context refs, and completed Worker steps.
- Call provider adapter.
- Store `job.finalAnswer`.
- Emit step start/completed/failed events.
- Mark chat-facing job failed if answer generation fails.
- Enforce idempotency:
  - if `finalAnswer` exists, do not regenerate.
  - if an `answer_generate` completed event already exists, do not regenerate.
  - `force` is not implemented in Phase 1.

It must not:

- call `anima_chat`
- use Anima persona
- claim output is only in 3D terminal
- write files
- bypass job event logging

### Terminal Evidence

Worker terminal should show:

```text
$ internal-worker:chat-run worker.job.chatRun
[task] ...
[tool] workspace_plan_readonly
[step] answer_generate running
[step] answer_generate completed
```

Anima terminal should only show Worker dispatch and completion:

```text
$ worker.job.chatRun
OK Worker job completed.
```

## Failure Semantics

For chat-facing jobs:

- Tool failure: job `failed`.
- Answer generation failure: job `failed`.
- Timeout before answer: job `timeout`.
- Cancel before answer: job `cancelled`.
- Existing finalAnswer on retry: return job without regenerating unless explicit force is added later.

No silent fallback to:

```text
Details are shown in the 3D terminal.
```

The chat output should either show `finalAnswer` or a clear Worker failure message.

Failure record requirements:

- failed job stores `error.code`
- failed job stores `error.message`
- failed job stores failing `stepName`
- UI may summarize the failure, but must not hide it behind terminal-only text.

## Workspace Isolation

Even in Phase 1:

- Workspace root must be normalized.
- Worker step access must stay within workspace root.
- Artifacts must be stored under the job artifact directory.
- Inputs should be masked before event persistence.
- No `--workspace .` semantics should leak into stored Worker definitions; store resolved roots.

## Test Requirements

### Live App Test

Must use:

- real DOM chat submit
- session and log reset before test
- no direct operation injection
- no mock Anima response
- no command-file-only Worker execution path

Must verify four outputs:

- Anima terminal
- Worker terminal
- Chat output
- Chat input

Required validity checks:

- Anima terminal shows Worker dispatch, not answer generation.
- Worker terminal shows job step execution including `answer_generate`.
- Chat output is non-empty and matches the submitted task.
- Chat input is empty after submit.

### Unit Tests

Required:

- `answer_generate` step is part of run lifecycle. Implemented for WorkerServer and AgentServer `Full`.
- completed chat-facing job has finalAnswer. Implemented for WorkerServer and AgentServer `Full`.
- answer generation failure marks job failed. Implemented for WorkerServer and AgentServer `Full`.
- retry with existing finalAnswer is idempotent. Implemented in WorkerServer/InternalWorker tests.
- UI chat path does not call `internal_worker_generate_answer` directly. Implemented in Worker chat hook tests.

## Migration Steps

### Step 1: Contract Check

- Confirm current `InternalWorkerJobStatus` can represent required semantics.
- Confirm current event fields can carry `stepName`, `correlationId`, and `payloadVersion` or decide minimal additions.
- Confirm current job metadata can mark a job as chat-facing.
- Define `jobKind` and use `chat` for current Worker chat jobs.
- Define `runJob` as blocking in Phase 1.
- Define `CapabilityPolicy` enforcement point for each step.
- Define where `finalAnswer` lives: inline `job.finalAnswer` for Phase 1.
- Define failure record fields: `error.code`, `error.message`, `stepName`.

### Step 2: Add answer_generate to InternalWorker run lifecycle

- Add internal answer-generation function callable from WorkerServer `run_chat_job`. Done.
- Add `answer_generate` step. Done.
- Persist `finalAnswer`. Done.
- Emit start/completed/failed events. Done.
- Enforce failure semantics. Done.
- Route AgentServer `Full` Worker Job execution through the same `run_chat_job` lifecycle. Done.

### Step 3: Simplify UI normal path

- Main chat explicit Worker path calls only job create/run. Done.
- Worker chat path calls only job create/run. Done.
- Both read `job.finalAnswer`. Done.
- Keep compatibility command only if needed, not normal path.

### Step 4: Update terminal extraction and harness validity

- Worker terminal recognizes `answer_generate`.
- Harness validates actual values, not only object existence.
- Reset/session guard remains required.

### Backend Mode Matrix

Phase 1 distinguishes answer-producing backends from session dispatch backends:

| Backend | Full | ToolSteps | Session | Final answer source |
|---------|------|-----------|---------|---------------------|
| `internal` | supported | supported | deferred | WorkerServer `answer_generate` provider step |
| `codexCli` | supported | supported | deferred | CLI process output |
| `claudeCli` | supported | supported | deferred | CLI process output |
| `openCodeCli` | supported | supported | deferred | CLI process output |
| `ptyCli` | rejected | supported | planned | persistent PTY/TUI session, not `finalAnswer` |

Rules:

- CLI backends are final-answer-producing backends. They run `worker_cli_run`, persist `job.finalAnswer`, and skip WorkerServer provider `answer_generate` idempotently.
- `ptyCli` is dispatch-only in Phase 1. It sends input to a persistent CLI/TUI session and returns a running job with `worker_pty_dispatched`.
- `ptyCli` must not flow into provider `answer_generate` during `Full`, because raw PTY output is not a reliable final answer.
- OpenCode/Codex/Claude interactive TUI use requires `ptyCli`; non-interactive process execution uses the corresponding CLI backend.
- Local/Remote AgentServer configuration must allowlist backends explicitly. PTY should remain explicit opt-in.

PTY Session Control contract:

- PTY session output reads are observation only. `worker_pty_read_session` must not mark a job idle or complete.
- Job dispatch writes use `session_id + job_id` ownership. A busy session rejects another job with `WORKER_PTY_SESSION_BUSY`.
- Manual session writes are preserved for compatibility, but they are rejected while the session is busy.
- `worker_pty_release_job(session_id, job_id)` is the only normal path from `Busy` to `Idle`.
- Release with a non-owning job returns `WORKER_PTY_SESSION_JOB_MISMATCH`.
- Terminal states (`Failed`, `Exited`, `Killed`) are not converted back to `Idle` by release.
- PTY write/flush failures clear the active owner and move the session to `Failed`; this is an abnormal recovery path, not a normal release.
- Prompt parsing, auto-idle timeouts, stream completion detection, and session queues are deferred until a backend-specific adapter layer exists.

AnimaCoordinator server-boundary prep:

- `AnimaAgentServerPlan` defines the future Anima AgentServer boundary without moving `anima_chat_inner` yet.
- The plan carries `AgentRole::Anima`, invocation, placement, project/anima identity, request/session/conversation ids, collaboration session id, backend, memory scope, and side-effect policy.
- Memory, AnimaState, journal, UI, animation, Worker delegation, and agent-collaboration write capabilities are explicit plan fields.
- Normal chat remains a stateful `Session`; provider requests are read-only `Job`; slash bypass remains `Session` with memory and persistent writes blocked.
- `collaboration_session_id` remains the resident agent workspace id and must not be confused with user-visible conversation history boundaries.
- Host/server execution remains a follow-up phase after the boundary contract is stable.

Anima AgentServerHost thin adapter, 2026-06-29:

- `AnimaAgentServerHost` implements the common `AgentServerHost` trait for Anima `Job` and `Session` requests.
- This adapter is plan-only: it creates `anima.plan.created` events and keeps jobs `queued`; it does not call `anima_chat_inner` or execute Anima responses yet.
- `backendType` is required metadata and unsupported backends are rejected before plan creation.
- Public event metadata stores `planOnly`, `executionSupported=false`, `jobStatusReason=planOnlyQueuedNoExecution`, and a redacted `planSummary` instead of exposing the full execution plan object.
- `planSummary` excludes prompt text and request/session/conversation/collaboration ids; it only carries role, invocation, placement, backend, context mode, capabilities, and policy fields.
- Plan-only queued jobs are not counted as active sessions or running jobs in health snapshots.
- Worker requests, `Instant` invocation, and missing backend metadata are rejected at the Host boundary.

Anima web-remote route mount, 2026-06-29:

- Web-remote mounts the Worker runnable AgentServer at `/agent` and the Anima plan-only AgentServer at `/anima-agent`.
- `/anima-agent` uses the non-runnable `agent_server_router`, so `/anima-agent/jobs/:id/run` is not mounted while Anima execution is not supported.
- `/anima-agent` is under the same web-remote auth middleware as `/agent`; health, job creation, and event replay reject unauthenticated requests.
- If Oribis home resolution fails, the web-remote Anima host uses a temp fallback and logs the fallback path for observability.
- Route tests cover auth, Anima Session plan creation, provider Job plan creation, event replay, run-route absence, Worker-role rejection, and unchanged Worker `/agent` job creation.

AgentCollaboration inbox acknowledgement, 2026-06-29:

- AgentCollaboration now has in-memory per-agent/per-conversation inbox cursors for resident-agent cooperation.
- `AgentInboxCursor.last_seen_sequence` is a global message sequence acknowledged as seen for one conversation; it is not Worker execution dedupe, delivery confirmation, retry guarantee, or persistence.
- `acknowledge_inbox(agent_id, conversation_id, sequence)` validates agent existence, conversation membership, monotonic cursor movement, and that the sequence is visible to that agent through the existing inbox filter.
- `list_unread_inbox(agent_id, limit)` applies the stored per-conversation cursors, preserves existing inbox filtering, sorts by global sequence, and then applies the limit.
- `list_inbox_after` remains caller-cursor based; `list_unread_inbox` is stored-cursor based; `acknowledge_inbox` only updates seen cursor state.
- Tauri commands expose acknowledge/get-cursor/list-unread operations for trusted UI/runtime use; command-level agent ownership authorization remains a future phase.

### Step 5: Focused tests

- Rust InternalWorker tests.
- Worker chat hook tests.
- App terminal tests.
- Live-stage DOM chat harness with reset.

Minimum test assertions:

- `answer_generate` is part of `run_job`.
- `completed + jobKind=chat` implies `finalAnswer`.
- `answer_generate` failure produces `failed`.
- existing `finalAnswer` does not regenerate.
- `partial` is not produced in Phase 1.
- each executed step passes capability enforcement.
- normal UI path does not invoke `internal_worker_generate_answer`.

## Acceptance Criteria

- DOM chat submit runs one Worker job path.
- UI does not call `internal_worker_generate_answer` in normal Worker chat.
- Worker job has an `answer_generate` step.
- Completed chat-facing job has `finalAnswer`.
- `runJob` returns a terminal job in Phase 1.
- Worker terminal shows `answer_generate`.
- Chat output is `finalAnswer`.
- Chat input clears after submit.
- No test-only path is introduced.

Phase 1 implementation note, 2026-06-29:

- Normal UI paths already call `internal_worker_create_job` then `internal_worker_run_job`; the Tauri command delegates to WorkerServer `run_chat_job`.
- AgentServer `Full` now also delegates to `run_chat_job`, while `ToolSteps` remains the lower-level tool-only mode.
- The live-stage harness no longer contains `add` / `subtract` / `multiply` / `divide` special operator expectations; it validates submitted function shape generically.
- CLI backends are documented as final-answer-producing backends, so `answer_generate` is skipped when `worker_cli_run` already persisted `finalAnswer`.
- PTY backend `Full` is rejected; PTY remains dispatch/session-oriented and does not produce `finalAnswer` from raw terminal output.

## Deferred

- `code_proposal`
- `validation_plan`
- WorkerServer process split
- local HTTP/Unix socket transport
- opencode run backend
- opencode TUI PTY backend
- codex/claude backend
- AnimaCoordinator server split
- external CLI operation client
