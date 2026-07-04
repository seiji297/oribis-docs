# Test Inventory

このファイルは、既存のテスト/スクリプト/証跡を `test-matrix.md` の代表保証項目へ紐づける索引。  
人間向けのリリース判断は `test-matrix.md`、実行対象の詳細はこのファイルで追跡する。

## Static / Build

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-STATIC-001` | `pnpm run typecheck` | TypeScript static check |
| `ORB-STATIC-001` | `pnpm vite build` | frontend production build |
| `ORB-STATIC-001` | `cargo check --manifest-path src-tauri/Cargo.toml` | Rust compile check |
| `ORB-STATIC-001` | `pnpm install --frozen-lockfile` | dependency reproducibility |
| `ORB-STATIC-001` | `scripts/qa/run-windows-smoke.ps1` | Windows smoke runner |
| `ORB-STATIC-001` | `scripts/verify-wsl-build.sh` | WSL build verification, supporting only |

## Test Harness / Policy

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-STATIC-002` | `scripts/send-live-stage-chat.sh` | DOM chat送信専用ガード |
| `ORB-STATIC-002` | `scripts/run-live-stage-chat-harness.sh` | session/log reset marker and harness runner |
| `ORB-STATIC-002` | `e2e/wdio/tests/live-stage-chat-harness.spec.ts` | direct/mock command拒否、4出力確認 |
| `ORB-STATIC-002` | `scripts/live-stage-policy.cjs` | live stage policy |

## AI-native / App Runtime

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-STATIC-003` | `src/workbench/coreAppToolValidation.ts` | schema/tool validation |
| `ORB-STATIC-003` | `src/workbench/coreAppToolValidation.test.ts` | 固定語録ルーター非復活の単体確認 |
| `ORB-STATIC-003` | `src/workbench/coreAppRegistry.ts` | Core App action catalog source |
| `ORB-UT-001` | `src/apps/__tests__/toolActionSchema.test.ts` | App tool schema |
| `ORB-UT-001` | `src/apps/__tests__/HostAPI.test.ts` | Host API contract |
| `ORB-UT-001` | `src/apps/__tests__/invoke.test.ts` | App invocation |
| `ORB-UT-001` | `src/apps/__tests__/EventBus.test.ts` | App event bus |
| `ORB-IT-004` | `src-tauri/src/app_runtime/mod.rs` | App scan/install/enable/permission/tool catalog |
| `ORB-IT-004` | `src-tauri/src/app_runtime/manifest.rs` | App manifest validation |
| `ORB-IT-004` | `src-tauri/src/app_runtime/permission.rs` | App permission model |
| `ORB-IT-004` | `src/apps/useAppSystem.ts` | frontend App loading/catalog aggregation |
| `ORB-IT-006` | `src-tauri/src/app_runtime/package.rs` | App package install/export/trust |
| `ORB-IT-006` | `src-tauri/src/app_runtime/sidecar.rs` | App sidecar lifecycle |
| `ORB-IT-006` | `src-tauri/src/app_runtime/storage.rs` | App storage |
| `ORB-IT-006` | `src-tauri/src/app_runtime/fs.rs` | App filesystem boundary |
| `ORB-IT-006` | `src-tauri/src/app_runtime/net.rs` | App network boundary |
| `ORB-IT-006` | `src/apps/AppSandbox.tsx` | sandbox runtime |
| `ORB-IT-004` | `src/apps/UIRenderer.tsx` | human UI renderer |
| `ORB-IT-004` | `src/apps/stageOnlyPolicy.ts` | Stage-only App visibility policy |
| `ORB-IT-001` | `src/RootShell.chat.test.tsx` | RootShell chat/App action配線 |
| `ORB-IT-001` | `src/workbench/CoreAppWorkbench.test.tsx` | Workbench component integration |
| `ORB-IT-001` | `src/workbench/coreAppWindow.test.ts` | App window/docking state |
| `ORB-IT-003` | `e2e/wdio/tests/app-ai-native-chat.spec.ts` | AI-native UI route supporting |

## Builtin / External Apps

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-IT-005` | `apps/scene-editor/manifest.yaml`, `apps/scene-editor/index.ts` | builtin Scene Editor App |
| `ORB-IT-005` | `apps/scene-builder/manifest.yaml`, `apps/scene-builder/index.ts` | builtin Scene Builder App |
| `ORB-IT-005` | `apps/animation-creator/manifest.yaml`, `apps/animation-creator/index.ts` | builtin Animation Creator App |
| `ORB-IT-005` | `apps/discord/manifest.yaml`, `apps/discord/index.ts` | Discord Bridge App |
| `ORB-IT-005` | `apps/google-workspace/manifest.yaml`, `apps/google-workspace/index.ts` | Google Workspace App |
| `ORB-IT-005` | `apps/github-integration/manifest.yaml`, `apps/github-integration/index.ts` | GitHub Integration App |
| `ORB-IT-005` | `apps/blender-hub/manifest.yaml`, `apps/blender-hub/index.ts` | Blender Hub App |
| `ORB-IT-005` | `apps/work-report/manifest.yaml`, `apps/work-report/index.ts` | Work Report App |
| `ORB-IT-005` | `apps/debug-panel/manifest.yaml`, `apps/debug-panel/index.ts` | Debug Panel App. Release UIでは原則非表示 |
| `ORB-IT-005` | `src/apps/__tests__/useAppSystem.test.ts` | Stage-only filtering and external App registration |

## Worker

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-UT-002` | `src/worker-core/*.test.ts` | Worker core protocol/session/store/permission |
| `ORB-SIT-001` | `e2e/wdio/tests/worker-chat.spec.ts` | Worker chat supporting route |
| `ORB-SIT-001` | `e2e/wdio/tests/live-stage-chat-harness.spec.ts` | live stage 4 output supporting route |
| `ORB-SIT-001` | `src-tauri/src/worker_server.rs` | Worker server implementation area |
| `ORB-SIT-001` | `src-tauri/src/internal_worker.rs` | Internal worker implementation area |
| `ORB-SIT-001` | `src-tauri/src/worker_pty.rs` | Worker PTY/backend implementation area |

## Scene / 3D / Onboarding

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-UT-003` | `src/scene-runtime/*.test.ts` | Scene runtime unit/supporting |
| `ORB-UT-003` | `src/components/BabylonAvatarViewer.test.tsx` | Avatar viewer supporting |
| `ORB-UT-003` | `src/components/BabylonStageViewer.test.ts` | Stage viewer supporting |
| `ORB-ST-002` | `e2e/wdio/tests/onboarding-scene-only.spec.ts` | onboarding supporting ST |
| `ORB-ST-002` | `e2e/wdio/tests/onboarding.spec.ts` | onboarding supporting ST |
| `ORB-ST-003` | `e2e/wdio/tests/stage-renderer.spec.ts` | Stage renderer supporting ST |
| `ORB-ST-003` | `e2e/wdio/tests/babylon-renderer.spec.ts` | Babylon renderer supporting |
| `ORB-ST-003` | `e2e/wdio/tests/babylon-motion-state.spec.ts` | motion visual supporting |
| `ORB-ST-003` | `e2e/wdio/tests/babylon-generated-vrma.spec.ts` | generated VRMA visual supporting |
| `ORB-ST-004` | `e2e/wdio/tests/core-app-workbench.spec.ts` | Workbench layout supporting ST |
| `ORB-ST-004` | `e2e/wdio/tests/titlebar-app-strip.spec.ts` | App strip supporting |

## Settings / Anima / TTS

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-IT-002` | `src/components/GeneralTab.test.tsx` | Settings UI supporting |
| `ORB-IT-002` | `src/components/PromptsTab.test.tsx` | Prompt UI supporting |
| `ORB-IT-002` | `src/components/AppsTab.test.tsx` | Apps UI supporting |
| `ORB-IT-002` | `src/components/AnimaStatusBar.test.tsx` | Anima status supporting |
| `ORB-UT-004` | `src/hooks/useTTS.test.ts` | TTS hook |
| `ORB-UT-004` | `src/lib/readableTtsText.test.ts` | readable TTS text |
| `ORB-UT-004` | `src-tauri/tests/tts_*` | Rust TTS tests |
| `ORB-UT-004` | `src-tauri/src/tts.rs`, `src-tauri/src/tts/lifecycle.rs` | Rust TTS settings / VOICEVOX VVM detection / lifecycle env isolation |
| `ORB-AT-005` | WindowsQA TTS scenario | official UX/audio evidence |

## WebViewer / Web Remote

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-003` | `src/workbench/webViewerUrl.test.ts` | WebViewer URL logic |
| `ORB-SIT-003` | `src/workbench/webViewerLivePreview.test.ts` | live preview logic |
| `ORB-ST-006` | `src/workbench/CoreWebViewerPane.tsx` | WebViewer App window UI |
| `ORB-ST-006` | `src/workbench/webViewerUrl.ts` | WebViewer App URL state |
| `ORB-ST-006` | `e2e/wdio/tests/web-remote-e2e.spec.ts` | WebViewer UI supporting evidence |
| `ORB-SIT-003` | `e2e/wdio/tests/web-remote-e2e.spec.ts` | Web remote supporting route |
| `ORB-SIT-003` | `scripts/setup-web-remote.ps1` | Web remote setup |
| `ORB-SIT-003` | `scripts/start-web-remote.ps1` | Web remote start |
| `ORB-AT-004` | WindowsQA WebViewer scenario | official WebViewer UX evidence |
| `ORB-SIT-006` | `src-tauri/src/remote/*` | remote server/auth/session/assets/events |
| `ORB-SIT-006` | `src-tauri/tests/remote_auth_integration_test.rs` | remote auth integration |
| `ORB-SIT-006` | `scripts/teardown-web-remote.ps1` | Web remote teardown |

## Discord Relay

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-002` | `src-tauri/src/agent_discord_delivery.rs` | Discord delivery |
| `ORB-SIT-002` | `src-tauri/src/agent_discord_route_store.rs` | route store |
| `ORB-SIT-002` | `src-tauri/src/agent_discord_commands.rs` | route commands |
| `ORB-SIT-002` | `src-tauri/src/discord_bridge.rs` | Discord bridge |
| `ORB-SIT-002` | `src/worker-core/discordAdapter.test.ts` | supporting unit |
| `ORB-SIT-002` | `e2e/wdio/tests/agent-discord-routing-settings.spec.ts` | routing settings supporting |

## Console / Log

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-ST-005` | `src/components/DeveloperConsole.test.tsx` | Console UI supporting |
| `ORB-ST-005` | `src/components/TaskJobView.test.tsx` | Task/Job consolidation supporting |
| `ORB-ST-005` | `src/components/__tests__/ActionAuditPanel.test.tsx` | audit panel supporting |
| `ORB-ST-005` | `src/components/__tests__/TaskJobView.test.tsx` | Worker Activity supporting |

## Agent Server / Collaboration

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-005` | `src-tauri/src/agent_routing.rs` | AgentRole / InvocationKind / Placement routing |
| `ORB-SIT-005` | `src-tauri/src/agent_server.rs` | Agent server dispatcher/registry |
| `ORB-SIT-005` | `src-tauri/src/agent_server_http.rs` | local/remote HTTP Agent Server adapter |
| `ORB-SIT-005` | `src-tauri/src/agent_server_router.rs` | web-remote Agent Server routing |
| `ORB-SIT-005` | `src-tauri/src/agent_server_internal_worker.rs` | Internal Worker Agent Server host |
| `ORB-SIT-005` | `src-tauri/src/anima_agent_server.rs` | Anima Agent Server entry |
| `ORB-SIT-005` | `src-tauri/src/agent_collaboration.rs` | persistent agent conversation/inbox |
| `ORB-SIT-005` | `src-tauri/src/agent_collaboration_runtime.rs` | runtime collaboration bridge |

## Memory / Prompt / Skills / Templates

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-007` | `src-tauri/src/anima/memory_db.rs` | Anima memory DB |
| `ORB-SIT-007` | `src-tauri/src/anima/memory.rs` | memory command/domain logic |
| `ORB-SIT-007` | `src-tauri/src/anima/amem.rs` | associative memory |
| `ORB-SIT-007` | `src-tauri/src/anima/consolidation.rs` | L1/L2/L3 memory consolidation |
| `ORB-SIT-007` | `src-tauri/src/anima/retrieval.rs` | memory retrieval |
| `ORB-SIT-007` | `src-tauri/src/anima/cache.rs` | Anima cache |
| `ORB-SIT-007` | `src-tauri/src/anima/history.rs` | Anima history |
| `ORB-SIT-009` | `src-tauri/src/skill.rs` | skill scan/save/delete |
| `ORB-SIT-009` | `src-tauri/src/templates/*` | template list/apply |
| `ORB-SIT-009` | `src/components/PromptsTab.test.tsx` | prompt UI supporting |
| `ORB-SIT-009` | `src/components/SkillsTab.test.tsx` | skill UI supporting |

## Auth / Recording / Scheduler / Commercial

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-010` | `src-tauri/src/recording.rs` | recording start/stop |
| `ORB-SIT-010` | `src-tauri/src/scheduler.rs` | schedule loop and item update |
| `ORB-SIT-008` | `src-tauri/src/openai_subscription_auth.rs` | OpenAI subscription auth |
| `ORB-SIT-008` | `src-tauri/src/kimi_coding_auth.rs` | Kimi Coding auth |
| `ORB-SIT-008` | `src-tauri/src/license/*` | commercial license/account |
| `ORB-SIT-008` | `src-tauri/src/signal/*` | commercial Signal integration |
| `ORB-SIT-008` | `e2e/wdio/tests/commercial-license.spec.ts` | commercial license UI supporting |
| `ORB-SIT-008` | `e2e/wdio/tests/kimi-oauth-auth.spec.ts` | Kimi auth supporting |
| `ORB-SIT-008` | `e2e/wdio/tests/anima-openai-subscription-smoke.spec.ts` | OpenAI subscription supporting |

## Acceptance / UX Scenarios

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-AT-001` | `src/workbench/coreAppRegistry.ts` | AI-native App action catalog |
| `ORB-AT-001` | `src/workbench/coreAppToolValidation.ts` | schema-based validation |
| `ORB-AT-001` | `src/RootShell.tsx` | chat to app.tool.invoke route |
| `ORB-AT-001` | `e2e/wdio/tests/app-ai-native-chat.spec.ts` | supporting natural language route |
| `ORB-AT-001` | WindowsQA AI-native 30 representative operations | official acceptance evidence |
| `ORB-AT-002` | `src/components/Onboarding.tsx` | onboarding UI |
| `ORB-AT-002` | `src/components/GeneralTab.tsx` | Settings UI |
| `ORB-AT-002` | `src/components/AppsTab.tsx` | Apps management UI |
| `ORB-AT-002` | `src/components/PromptsTab.tsx` | Prompt UI |
| `ORB-AT-002` | `src/RootShell.onboarding.test.tsx`, `src/components/Onboarding.test.tsx` | onboarding defaults/supporting |
| `ORB-AT-002` | WindowsQA Settings/Anima scenario | official UX evidence |
| `ORB-AT-003` | `src/components/WorkerPanel.tsx` | Worker UI |
| `ORB-AT-003` | `src/components/TaskJobView.tsx` | Worker jobs/tasks UI |
| `ORB-AT-003` | `src/components/chat/DepartmentChatPanel.tsx` | chat panel |
| `ORB-AT-003` | `src/components/WorkerOutputInline.tsx` | Worker output UI |
| `ORB-AT-003` | `scripts/send-live-stage-chat.sh` | live stage result reporting |
| `ORB-AT-003` | `e2e/wdio/tests/worker-chat.spec.ts` | Worker chat official UX route; may share evidence with ORB-SIT-001 when AT criteria are checked separately |
| `ORB-AT-003` | WindowsQA Worker representative task | official acceptance evidence |

## Python / Rust Integration

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-SIT-004` | `tests/e2e/run-e2e-test.sh` | Python e2e runner |
| `ORB-SIT-004` | `tests/e2e/test_anima.py` | Anima backend e2e |
| `ORB-SIT-004` | `tests/e2e/test_orchestrator.py` | Orchestrator backend e2e |
| `ORB-SIT-004` | `src-tauri/tests/*` | Rust integration/e2e |

## WindowsQA

| test_id | Commands / Files | Role |
|---|---|---|
| `ORB-ST-001` | `scripts/qa/invoke-windows-qa.sh` | WindowsQA remote runner |
| `ORB-ST-001` | `scripts/qa/run-windows-smoke.ps1` | Windows smoke runner |
| `ORB-ST-001` | `scripts/qa/interactive-capture.ps1` | desktop capture |
| `ORB-ST-001` | `scripts/qa/register-interactive-tasks.ps1` | interactive task registration |
| `ORB-ST-001` | `scripts/qa/invoke-windows-interactive-qa.sh` | interactive QA wrapper |
| `ORB-GATE-001` | `test-matrix.md` | release gate source of truth |
| `ORB-GATE-001` | `manifest.json` | evidence manifest and hashes |
| `ORB-GATE-001` | `execution-report.md` | release execution report |
| `ORB-GATE-001` | `scripts/qa/audit-release-manifest.mjs` | manifest, bug regression, evidence sha audit |
| `ORB-GATE-001` | `scripts/qa/audit-windows-qa-summary.mjs` | WindowsQA summary official/commit/clean/skippedSteps audit |
| `ORB-GATE-001` | `scripts/qa/audit-windows-qa-summary.test.mjs` | summary audit negative tests |
| `ORB-GATE-001` | `pnpm run test:qa-audit` | Node `node:test` QA audit tests excluded from Vitest but covered explicitly |
| `ORB-GATE-002` | `scripts/qa/run-windows-packaging.ps1` | Windows release packaging/install/uninstall gate |
| `ORB-GATE-002` | `scripts/qa/audit-windows-qa-summary.mjs --packaging` | packaging summary audit |

## Current Diagnostic Evidence

| test_id | Evidence | Role |
|---|---|---|
| `ORB-STATIC-001` | `evidence/STATIC-BUILD-001/windows-smoke-summary.json` | local-windows diagnostic/static evidence |
| `ORB-STATIC-001` | `evidence/STATIC-BUILD-001/windows-smoke.log` | local-windows diagnostic/static evidence |
| `ORB-STATIC-001` | `evidence/STATIC-BUILD-001/windows-system.json` | local-windows environment |
| `ORB-STATIC-001` | `evidence/STATIC-BUILD-001/windows-smoke.zip` | local-windows artifact zip |
| `ORB-DIAG-001` | local-windows devUrl/localhost diagnostic observation | diagnostic only, not release evidence |
