# Oribis Core Appification Plan

Date: 2026-06-30
Status: Draft for codex-adviser review
Owner: sysdev-1

## Goal

Oribis の基本機能へ、既存 App 基盤を適用する。

これは旧 Plugin 実装を継承する作業ではない。旧 Plugin 由来で整備された現行 App 基盤
（manifest/capability/sandbox/HostAPI/tool catalog）を、Oribis 本体の基本機能にも適用する作業。

最終形は次の順序を正本にする。

```text
AI intent
  -> App Tool / App Action contract
  -> permission / approval / audit
  -> core service execution
  -> artifact / state / event
  -> human UI panel
```

人間向け UI は App が提供する操作面であり、機能の正本ではない。
LLM があれば全機能を App Tool / App Action として列挙・選択・実行できる状態を目標にする。

「AI 制御が正本」の定義:

- すべての Core 操作は `AppActionDescriptor` で記述する。
- AI/UI/system/internal の呼び出しは原則 `AppActionRouter` を通る。
- 人間向け UI は `AppActionDescriptor` と state schema から手動または自動生成される surface として扱う。
- UI だけに存在する操作、AI だけに存在する操作を作らない。
- 例外が必要な内部処理は `internalOnly` として action catalog に明示し、AI/UIからは呼べない。

## Current App System Facts

現行 App 基盤は次の構成。

- `manifest_version: 2`
- `capabilities`: storage/events/ui/character/render/audio/ai/fs/net/tauriInvoke/sidecar
- `extension_points`: appLifecycle/uiSettingsPanel/uiSidebarPanel/uiCommand/character/render/audio/aiTool
- Runtime:
  - `webview`: iframe sandbox 実行
  - `sidecar`: executable runtime 入口あり
  - `wasm`: manifest 上の入口あり
- Frontend runtime:
  - `src/apps/AppSandbox.tsx`: hidden iframe で App code を実行
  - `src/apps/bootstrap.ts`: iframe 内に `oribis.*` Host API を注入
  - `src/apps/HostAPI.ts`: capability check 後に storage/events/ui/app/character/render/vrm/audio/ai/fs/net/invoke を処理
  - `src/apps/useAppSystem.ts`: scan/load/unload、builtin/external app raw import、panel/tool catalog 集約
  - `src/apps/UIRenderer.tsx`: App が返す declarative schema を React UI として描画
- Backend runtime:
  - `src-tauri/src/app_runtime/manifest.rs`: manifest/capability/extension point/app_type/trust/runtime
  - `src-tauri/src/app_runtime/lifecycle.rs`: apps dir scan/install/enable/disable/state
  - `src-tauri/src/app_runtime/permission.rs`: deny-by-default capability grant
  - `src-tauri/src/app_runtime/router.rs`: dangerous action routing skeleton
  - `src-tauri/src/app_runtime/builtin.rs`: source-controlled builtin app definitions
- AI integration:
  - App は `oribis.ai.registerTool(descriptor, handler)` で tool を登録できる。
  - `HostAPI.invokeAiTool()` が iframe App の handler を呼ぶ。
  - `RootShell` が `getDefaultWorkerCoreSession().setAppToolInvoker(...)` へ接続している。
  - `app_tool_catalog_*` に descriptor が永続化される。

## Problem

現行 App 基盤は「拡張機能を動かす」形として成立しているが、Oribis 基本機能の正本にはなっていない。

主な不足:

- App Tool が optional addon 扱いで、Oribis 全機能カタログの正本ではない。
- 既存サイドバー/Settings/各React画面が直接状態と Tauri command を持っている。
- App UI schema は描画できるが、既存設定画面全体を表現する部品・状態同期・validation が不足している。
- `tauriInvoke` は allowed_commands で個別許可されているが、基本機能向けの typed action contract が薄い。
- App action の approval/audit/artifact が Worker/Anima の実行計画と完全には統合されていない。
- Builtin App は一部だけで、Settings/Anima/Worker/Discord/Scene/Audio/Memory などの core feature inventory がない。
- 現在のサイドバーは機能の置き場として強すぎる。App 化後は App launcher / command palette / AI tool catalog が主導になる。

## Permission / Audit / State Rules

### Permission

- manifest capability は App が要求できる能力境界。
- action capability は具体操作に必要な能力境界。
- 未宣言 capability は deny。
- 宣言済みでも grant が無い危険 capability は prompt/confirm。
- `callerPolicy.internalOnly` は AI/UI から呼べない。
- `trust_level=builtin` は自動許可ではない。確認省略できる範囲を限定する分類。

Dangerous actions:

- file write
- delete
- external network send
- Discord/Google/GitHub等の外部送信
- secret参照
- sidecar/CLI起動
- scene mutation
- Worker/Anima job cancellation

これらは `approvalPolicy=confirm` 以上、または明示的な安全証明を必要とする。

### Audit

全 action 呼び出しは audit event を残す。

Required fields:

- `actionId`
- `appId`
- `caller`: `ai | ui | system | internal`
- `actor`
- `sessionId`
- `requestId`
- `idempotencyKey`
- `sideEffect`
- `approvalDecision`
- `status`: `started | succeeded | failed | rejected | cancelled | timeout`
- `errorCode`
- `latencyMs`
- `artifactId`
- `timestamp`

### State

- read action と mutation action を分離する。
- mutation action 後は state invalidation event を出す。
- UI は action 実行結果だけでなく state event を購読して更新する。
- 同時実行がある action は conflict policy を descriptor に持つ。
- optimistic UI は正本にしない。正本は service state / artifact / audit。

## Target Architecture

### Core Concepts

```text
CoreAppDefinition
  manifest
  actionCatalog
  uiSurfaces
  stateSchema
  permissionProfile
  auditProfile
  serviceBinding
```

```text
AppAction
  id
  version
  title
  description
  inputSchema
  outputSchema
  errorSchema
  sideEffect
  approvalPolicy
  requiredCapabilities
  callerPolicy
  idempotency
  dryRun
  timeoutMs
  cancel
  serviceBinding
  artifactKind
```

```text
HumanSurface
  slot: settings | dock | overlay | fullPage | launcher
  schema
  stateBinding
  actions
```

AI は `AppAction` を選ぶ。
UI は同じ `AppAction` をボタン/フォームとして呼ぶ。
手動 UI と AI 実行で別経路を作らない。

### Core App vs User App

| Item | Core App | User App |
| --- | --- | --- |
| Ownership | Oribis source-controlled built-in feature | user/third-party supplied feature |
| Trust | `trust_level=builtin` or `nativeSigned` | default `untrusted` |
| Runtime | native service binding preferred; iframe surface optional | iframe/webview/sidecar/wasm |
| Action source | source-controlled `CoreAppDefinition` | runtime `oribis.ai.registerTool` + manifest |
| Permission | capability + action policy + built-in trust constraints | capability + user grant |
| UI | App surface from action/state schema; may wrap existing UI during migration | declarative UI schema |
| Data access | typed service binding; no broad raw invoke by default | scoped storage/fs/net through HostAPI |
| Lifecycle | loaded by core registry even if UI surface is closed | enabled/loaded through App runtime |

Core App は通常 App より強い権限を持ち得るが、無制限ではない。
破壊的操作・外部送信・secret利用・sidecar/CLI起動は Core App でも action policy と audit を必須にする。

### AppActionDescriptor

`AppActionDescriptor` は AI tool descriptor ではなく、権限・監査・UI生成・テストの正本。

Minimum fields:

- `id`: `<appId>.<verb>`。例: `settings.read`, `worker.createJob`
- `version`
- `title`
- `description`
- `inputSchema`
- `outputSchema`
- `errorSchema`
- `sideEffect`: `none | read | write | network | scene | mixed`
- `approvalPolicy`: `auto | confirm | deny | systemOnly`
- `requiredCapabilities`
- `callerPolicy`: `aiAllowed | uiAllowed | systemAllowed | internalOnly`
- `idempotency`: `required | optional | notSupported`
- `dryRun`: `supported | unsupported`
- `timeoutMs`
- `cancel`: `supported | unsupported`
- `deprecated`
- `experimental`
- `artifactKind`
- `serviceBinding`

`AppToolDescriptor` は外部Appが登録するAI向けツールとして残せる。
ただし Core App の正本は `AppActionDescriptor` とし、必要なら `AppActionDescriptor` から AI tool view を生成する。

### Execution Path

```text
AI / UI request
  -> AppActionRouter
  -> capability check
  -> approval check
  -> audit start
  -> service binding
  -> artifact/state/event write
  -> audit complete
  -> UI/event refresh
```

`AppActionRouter` の責務:

- descriptor lookup
- input schema validation
- caller policy check
- capability check
- approval check
- idempotency key validation
- dry-run routing
- dispatch to service binding or runtime handler
- timeout/cancel handling
- output/error normalization
- audit start/complete/fail/reject logging
- state invalidation event emission

`AppActionRouter` が持たない責務:

- UI layout decision
- LLM prompt construction
- business logic本体
- secret平文の保持

### Shell Role

RootShell は次の責務へ縮小する。

- App host
- stage/chat shell
- App launcher
- command palette
- global notification/audit viewer

RootShell が直接各機能の設定・操作ロジックを持つ状態を減らす。

## Core App Inventory

初期移行対象:

| Core App | Current Location | Primary AI Actions | Human UI Surface |
| --- | --- | --- | --- |
| Settings | `RootShell` settings modal | read/update settings, list providers, validate config | settings/fullPage |
| Anima | `RootShell`, `hooks/useAnima`, `src-tauri/src/anima` | chat, memory query/update, state inspect, journal, expression/motion | dock/settings |
| Worker | `worker-core`, `internal_worker`, `RootShell` | create job, run job, inspect events/artifacts, cancel | dock/fullPage |
| Scene | `scene-runtime`, scene apps | get snapshot, mutate scene, save/load scene, build scene | dock/overlay |
| Audio/TTS | TTS hooks/components/Rust commands | speak, stop, list voices, set voice, BGM control | settings/dock |
| Discord | `apps/discord`, routing settings | send message, configure route, poll, inspect status | settings/dock |
| Google/GitHub integrations | existing apps/components | auth status, query, sync, send/read | settings/dock |
| Appearance/Avatar | avatar material/settings panels | set appearance, load avatar, inspect model | settings/dock |
| Audit/Approvals | approval/write proposal panels | list decisions, approve/deny, inspect proposal | dock/fullPage |

## Sidebar Migration Map

初期対応表。実装前に RootShell の実項目へ合わせて詳細化する。

| Existing Area | Core App | Required Actions | Delete Condition |
| --- | --- | --- | --- |
| Settings modal general | Settings | `settings.read`, `settings.update`, `settings.validate` | AI/UI両方で全項目到達可能 |
| Settings apps tab | App Manager | `apps.list`, `apps.enable`, `apps.disable`, `apps.permissions.update` | permission UI と app list がApp surface化 |
| Anima tab | Anima | `anima.chat`, `anima.getState`, `anima.memory.search`, `anima.motion.play` | チャット/状態/記憶/モーションがAction経由 |
| Worker tab | Worker | `worker.createJob`, `worker.runJob`, `worker.listEvents`, `worker.cancel` | DOMチャット/Worker UIが同一job action経由 |
| Scene tools | Scene | `scene.snapshot`, `scene.mutate`, `scene.save`, `scene.load` | Scene UIとAI生成が同一Action経由 |
| Audio/TTS settings | Audio | `audio.listVoices`, `audio.setVoice`, `audio.speak`, `audio.stop` | 設定/発話が同一Action経由 |
| Discord routing | Discord | `discord.sendMessage`, `discord.routes.read`, `discord.routes.update` | 送信先がstateで固定されAI推定に依存しない |
| Approval panels | Audit/Approval | `approval.list`, `approval.decide`, `audit.list` | 承認/監査の表示と操作がAction経由 |

## Phased Plan

### Phase 0: Contract Audit

目的: 現行 App 基盤の事実を固定する。

Tasks:

- `AppAction` descriptor を現行 `AppToolDescriptor` と比較し、不足 field を列挙する。
- `uiSettingsPanel/uiSidebarPanel/uiDockPanel/uiOverlay` の現行描画可能コンポーネントを棚卸しする。
- `tauriInvoke` allowed command の利用箇所を洗い出す。
- `app_runtime/router.rs` を基本機能 action router に使えるか判断する。
- built-in app と source-imported app の二重定義を整理する。
- 旧サイドバー項目と Core App action の詳細対応表を作る。
- `AppToolDescriptor` と `AppActionDescriptor` の分離/包含方針を決める。

Acceptance:

- Core App 化で必要な schema/capability/action/audit の不足一覧がある。
- 既存 App テストが通る。
- 旧UI項目ごとに削除条件が定義されている。

### Phase 1: Core App Registry

目的: 既存基本機能を App として登録できる正本を作る。

Tasks:

- Rust 側 `builtin.rs` を core app registry として拡張する。
- Frontend 側 `BUILTIN_MANIFESTS` の raw import 固定を registry 読み出しへ寄せる。
- `app_type=builtin_app` の default enabled/state/permission を統一する。
- Core App に `category`, `owner`, `surfacePreference`, `aiNative` を追加する。

Acceptance:

- Settings/Anima/Worker/Scene/Audio/Discord が scan 結果に Core App として出る。
- 既存 App enabled/disabled が壊れない。

### Phase 2: App Action Catalog

目的: AI が全機能を選択できる action catalog を正本化する。

Tasks:

- `AppToolDescriptor` を `AppActionDescriptor` へ拡張または包含する。
- action id 命名を `<appId>.<verb>` に統一する。
- `approvalPolicy`, `sideEffect`, `artifactKind`, `requiredCapabilities`, `serviceBinding` を必須化する。
- `errorSchema`, `callerPolicy`, `idempotency`, `dryRun`, `timeoutMs`, `cancel`, `deprecated`, `experimental` を追加する。
- App 起動前でも builtin action catalog を読めるようにする。
- WorkerCore/Anima から action catalog を検索・選択・実行できる API を追加する。
- action audit を開始/成功/失敗/拒否で記録する。

Acceptance:

- AI が App UI を開かずに action catalog を取得できる。
- App iframe handler と native service binding の両方を同じ action router から呼べる。
- capability不足、schema不正、承認不足が正規化エラーで返る。
- action log が残る。

### Phase 3: Settings App

目的: Settings を最初の core app として移行する。

理由:

- side effect が限定的。
- UI/状態/validation の基本形を作りやすい。
- 既存サイドバー除去の前提になる。

Tasks:

- Settings の項目を sections/actions/state schema に分解する。
- `settings.read`, `settings.update`, `settings.validate`, `settings.resetSection` を作る。
- UI は App schema から生成する。
- 既存 Settings modal は新 Settings App surface を表示する wrapper にする。
- read-only action から始め、mutation は approval/audit/state event が揃ってから入れる。

Acceptance:

- AI から設定の読み取り・変更ができる。
- 人間UIから同じ action を呼ぶ。
- 既存設定値の保存先と挙動が変わらない。

### Phase 4: Worker / Anima Core Apps

目的: Worker と Anima の常駐/ジョブ/状態を App action で操作可能にする。

Tasks:

- Worker App:
  - `worker.createJob`
  - `worker.runJob`
  - `worker.listEvents`
  - `worker.getArtifact`
  - `worker.cancel`
- Anima App:
  - `anima.chat`
  - `anima.getState`
  - `anima.memory.search`
  - `anima.journal.append`
  - `anima.motion.play`
  - `anima.expression.set`
- UI は dock/fullPage App surface として出す。
- 既存チャット導線は action router 経由へ寄せる。

Acceptance:

- DOMチャット送信、Worker UI、Anima UI が同じ action/job/event contract を通る。
- Anima terminal / Worker terminal / Chat output の既存テスト観点を維持する。

### Phase 5: Scene / Audio / Discord / Integrations

目的: 既にApp化が進んでいる領域を core app contract に揃える。

Tasks:

- Scene Editor/Builder の action catalog を native service binding 対応にする。
- Audio/TTS/BGM を Audio App として分離する。
- Discord App の送信先・routing を manifest/state schema で固定し、AI推論で channel ID を決めない。
- Google/GitHub など外部連携を permission/audit 強制にする。

Acceptance:

- 各機能が App action catalog から呼べる。
- 外部送信先は設定/state による決定で、AI が自由に推定しない。

### Phase 6: Sidebar Removal

目的: 既存サイドバーを App launcher / command palette / active app surface に置換する。

Tasks:

- 既存 sidebar tab を Core App launcher へ置換する。
- Settings は Settings App を開く。
- Scene/Worker/Anima/Discord は App surface として開く。
- old sidebar specific state を削除する。

Acceptance:

- 旧サイドバーを使わず主要機能へ到達できる。
- 旧サイドバーの全操作が Core App action 経由で到達できる。
- AI/UI双方で同じ action 結果になる。
- 権限・監査・エラー・状態更新が揃っている。
- WDIO GPU 表示テストで主要導線が壊れていない。

## Non-Goals

- テスト専用の別導線を App 内へ作らない。
- AI だけが使える隠し機能を作らない。
- 既存 UI を一括削除しない。
- `tauriInvoke` の無制限許可を増やさない。
- 既存データ破壊を前提にしない。

## Test Strategy

Unit:

- `src/apps` HostAPI/AppSandbox/UIRenderer/useAppSystem
- `src-tauri/src/app_runtime` manifest/permission/router/lifecycle
- action catalog schema validation

Integration:

- builtin app scan/enable/disable/load
- app action catalog list/invoke
- App UI event -> same action router
- Worker/Anima action execution

E2E:

- GPU表示前提の WDIO
- Settings App open/update/close
- Worker job via chat
- Anima chat/memory/state
- Scene App action
- Discord mocked transport send route

Evidence:

- terminal logs
- app action audit
- screenshots/video where display behavior is involved
- JSON result for action catalog and invoke result

## Risks

- RootShell が巨大なため、移行単位を誤るとデグレ範囲が広がる。
- App iframe handler だけに寄せると、core native 機能の信頼境界が曖昧になる。
- `tauriInvoke` allowed_commands に頼りすぎると typed action contract にならない。
- AI action と human UI action が分岐すると、同じ機能の挙動がずれる。
- 既存サイドバーを早く消すと、App surface 未移行機能へ到達不能になる。

## Recommended First Implementation Slice

推奨は Settings App ではなく、先に `AppActionDescriptor` と Core App Registry を作る。

理由:

- Settings を先に移すと、既存画面移植に引っ張られる。
- 目的は「AI が全機能を制御できる契約」なので、action catalog が先。
- action catalog が固まれば UI は自動フォーム/パネルとして後から作れる。

First slice:

1. `AppActionDescriptor` 型を追加する。
2. `CoreAppDefinition` を追加する。
3. `settings` の read-only action だけ登録する。
4. action catalog list を frontend/Rust から取得できるようにする。
5. AI/Worker から catalog を読めるテストを追加する。
6. UI変更は catalog viewer までに留める。

Acceptance:

- Core App が registry に登録される。
- `settings.read` が descriptor 付きで列挙される。
- AI経由とHost/UI経由が同じ router を通る。
- capability不足時に拒否される。
- schema validation される。
- action audit が残る。
- 既存 Settings UI はまだ壊さない。

## Open Questions for Review

- `AppToolDescriptor` を拡張して `AppActionDescriptor` にするべきか、別型として並べるべきか。
- builtin core action は iframe App handler と native service binding のどちらを正本にするべきか。
- Settings/Anima/Worker のような本体機能に `tauriInvoke` を使わせ続けるべきか、専用 service binding にするべきか。
- App UI schema の表現力を先に増やすべきか、action catalog からフォーム生成するべきか。
- 既存サイドバーを残す期間の feature flag が必要か。
