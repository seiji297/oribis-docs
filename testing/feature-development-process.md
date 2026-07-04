# Feature Development Process

Oribisは、今後も新機能/App/capabilityを継続追加するAI-nativeデスクトップアプリとして扱う。ここでの目的は、機能追加の速度を落としすぎず、UI・AI操作・権限・schema・証跡・テストを抜け漏れなく揃えること。

## 結論

採用する開発フローは以下。

```text
Feature Intake
  -> Feature Build
  -> Feature Done Definition
  -> Risk-based Release Gate
```

`Static / UT / IT / SIT / ST / AT / Release Gate` は検証Levelであり、新機能追加プロセスそのものではない。新機能追加では、検証Levelの前段に `Feature Intake` と `Feature Done Definition` を置く。

## 外部調査からの前提

- DORA 2025は、AIは開発組織の強みも弱みも増幅するとしている。AIツール単体ではなく、基盤となる開発システムが重要。
  - https://dora.dev/dora-report-2025/
- GitHub Docsは、Copilot/AIの成果をautomated tests/tooling/lint/code scanning等で確認すること、生成されたテストもレビューすることを推奨している。
  - https://docs.github.com/en/copilot/get-started/best-practices
  - https://docs.github.com/en/copilot/tutorials/write-tests
- Martin FowlerのContinuous Integrationでは、頻繁な統合を自動build/testで検証し、統合エラーを早期に見つけることが重要とされる。
  - https://martinfowler.com/articles/continuousIntegration.html
- Feature Toggleは、未完成/未検証のコードパスを本線へ入れつつ、有効化を制御するために使える。
  - https://martinfowler.com/articles/feature-toggles.html
- Atlassianは、Definition of Doneは共通完了基準、Acceptance Criteriaは個別作業の完了条件として分けている。
  - https://www.atlassian.com/agile/project-management/definition-of-done
  - https://www.atlassian.com/work-management/project-management/acceptance-criteria

## Feature Intake

新機能/App/capabilityの実装前に、最低限以下を決める。

| 項目 | 内容 |
|---|---|
| Feature / App / capability名 | 何を追加するか |
| Human UI entry | 人間向けUIの入口。Workbench pane、Scene overlay、Settingsなど |
| AI-native entry | AIから呼び出すoperation/tool/capability |
| Tool catalog / schema | input/output schema、version、examples |
| Permission | App単位、operation単位、resource単位の権限 |
| Risk | user data、file system、external integration、Worker、Discord、WebViewer、GPUなど |
| Evidence | 操作ログ、audit、スクショ、動画、result JSON、環境情報 |
| Affected areas | Workbench、Scene、Anima、Worker、WebViewer、DiscordRelay、Settingsなど |
| Test levels | Static / UT / IT / SIT / ST / AT のうち必要なもの |
| WindowsQA need | WindowsQA Server実画面/実GPU証跡が必要か |
| Feature flags | UI visibility、AI catalog exposure、backend execution、kill switch |

## Feature Build

実装時は、UIだけを作って完了にしない。OribisのApp/capabilityは以下を同時に持つ。

- 人間向けUI
- AI-native operation
- tool catalog/schema
- permission mapping
- audit/evidence
- tests
- manifest/test-matrix連動
- feature/capability flag

## Feature Done Definition

Feature Done Definitionは全feature共通の完了基準。重くしすぎないため、Core DoDと種別DoDに分ける。

### Core DoD

- 関連Static/UT/ITが通っている。
- test-matrixまたはmanifestに、保証単位と証跡要件が追加されている。
- AI-assisted変更の場合、生成テストだけで完了扱いにしていない。
- secret/API key/PIIがログ、証跡、プロンプトに混入していない。
- 変更範囲とリスク分類が記録されている。
- rollbackまたは無効化手段がある。

### UI Feature DoD

- UI入口、終了、復帰、エラー表示が定義されている。
- Workbench / Scene / Settings / WebViewer等の既存導線と衝突しない。
- 操作不能、権限不足、外部連携失敗時の表示がある。
- 人間操作とAI操作で状態不整合が起きない。
- 必要ならWindowsQA Serverで実画面証跡を取る。

### AI-native Feature DoD

- AIから発見可能なcapabilityとしてcatalogに登録されている。
- input/output schemaが明確。
- permission mappingがある。
- destructive operationはdry-run、preview、confirmation、policy checkの対象。
- structured errorを返し、AIが失敗理由を解釈できる。
- audit logにoperation id、schema version、flag状態、permission判定が残る。

### App / Capability DoD

Appは画面だけでは完了にしない。以下を満たす。

- manifest schemaが検証されている。
- capability discoveryができる。
- AI tool catalogへ登録される場合、tool name、schema、side effect、approval policyが明確。
- permission grant / deny / revoke の境界がある。
- 権限不足、manifest不正、runtime failure時に隔離され、他AppやCore Appへ波及しない。
- UI入口とAI-native入口が同じcapability定義から追跡できる。
- `test-inventory.md` にsource anchorがあり、`manifest.json` に対応する代表保証項目IDがある。

### External Integration DoD

- credential handling、rate limit、timeout、retry、failure modeが定義されている。
- DiscordRelay、Worker、WebViewer、browser automation、file system accessなどは高リスク扱い。
- 外部送信先はAI推論任せにしない。設定されたroute/channel/resourceで決まる。
- queueやbackground jobの滞留を検知できる。

## Acceptance Criteria

Acceptance Criteriaは個別featureごとに書く。DoDと混ぜない。

例:

- WebViewer: Web表示、入力、クリック、自動操作、スクショ、result JSONが成立する。
- Worker: Chat送信からWorkerが動き、Worker terminal、Anima terminal、Chat output、Chat inputの4点が妥当。
- Scene: Scene Appとして3D Viewが表示され、StageではStudio/物理/重力系UIが出ない。
- Settings/Anima: TTS speed/pitch、VRM、Prompt、Memory、Cacheの代表設定がUI/AI-native双方で反映される。

## Risk-based Test Selection

毎回全量テストはしない。変更リスクで実行範囲を決める。

### Low Risk

条件:

- isolated UI変更
- schema変更なし
- permission変更なし
- external integrationなし

実行目安:

- Static
- UT
- 対象IT
- 対象STまたはスクショ確認

### Medium Risk

条件:

- 新App追加
- tool catalog追加
- Worker/WebViewer/Scene等との連携追加
- 既存Appとの状態共有

実行目安:

- Static
- UT
- IT
- 対象SIT
- 対象ST
- 必要なWindowsQA対象AT

### High Risk

条件:

- 認証、認可、権限昇格
- permission model変更
- AI tool dispatcher / schema / capability routing変更
- user data、local file、storage migration
- DiscordRelay、Webhook、外部送信
- browser automation、WebViewer、Worker execution
- terminal/process/file system access
- audit/evidence/log masking/PII/secret handling
- installer、auto-update、Windows権限、署名、packaging
- GPU / WebView / native dependency / driver依存
- feature flag default、kill switch、rollout設定変更
- telemetry/diagnostic収集変更
- AI-assisted変更が共通基盤に触る

実行目安:

- 全Static
- 関連UT/IT/SIT/ST
- 主要回帰
- WindowsQA AT
- Release Gate full相当

## Risk Score

低/中/高の判断が揺れないよう、risk scoreを併用する。

| 条件 | Score |
|---|---:|
| UI isolated | +1 |
| AI tool catalog変更 | +2 |
| external integration | +2 |
| Worker/WebViewer/DiscordRelay連携 | +2 |
| user data / local file / storage | +3 |
| permission / auth / policy | +3 |
| migrationあり | +3 |
| rollback困難 | +3 |
| Windows native / GPU / WebView / installer | +3 |

目安:

- 0-2: Low
- 3-5: Medium
- 6以上: High

## Feature / Capability Flags

Oribisでは、UIだけでなくAI-native catalog/tool executionにもflagを効かせる。

必須flag:

- UI visibility flag
- AI catalog exposure flag
- permission grant flag
- backend/tool execution flag
- emergency kill switch
- experimental / beta / stable lifecycle

flagには以下を持たせる。

- owner
- default
- scope
- expiresAtまたは削除条件
- rollout対象
- kill switch
- audit log記録

未検証のhigh-risk capabilityはdefault offにする。

## WindowsQA Server

WindowsQA Serverは、最終AT/Release Gateの正規証跡経路。

公式WindowsQAの前提:

- 対象repoはclean worktreeである。
- runnerや一時ファイルはartifact領域へ置き、repo内へ同期しない。
- git fetch/checkout/resetが失敗したら即FAIL/BLOCKEDにし、後続テストへ進まない。
- 公式実行は対象commitを明示し、branch先端の暗黙追従だけで実行しない。
- 証跡には `official`、`sourceMode`、対象commit、resolved commit、clean確認結果、skip step一覧を含める。
- 未コミット作業のWindowsQAは、QA用refへ一時commitをpushして、そのSHAを指定する。source snapshotはdiagnostic/supportingに限定する。
- release候補では、debug/dev経路だけでなくpackaged release buildまたはinstallerの起動確認を行う。
- 実LLM/Discord ATに使うsecretはrepo外・証跡外に置き、証跡登録前にsecret混入を確認する。

| 環境 | 扱い |
|---|---|
| local-linux | 開発/UT/IT/supporting |
| WSLg/WDIO | supporting。ST補助には使えるが、最終実画面証跡ではない |
| local-windows | diagnostic / quick repro。AT本番扱いにしない |
| windows-qa-server | official AT evidence / Release Gate evidence |

WindowsQA証跡には以下を含める。

- OS version
- GPU/driver
- app build hash
- test scenario id
- operator/automation identity
- timestamp
- screenshots/video
- logs
- input/output evidence
- pass/fail judgment
- known deviations

## AI-assisted Change Rules

AIバイブコーディングでは以下を恒久ルールにする。

- 小さい差分で進める。
- AI生成コードの責任者を明確にする。
- AIが生成したテストだけで完了扱いにしない。
- 意図、権限、データ境界、失敗時挙動をレビューする。
- tool schemaとpermission mappingの差分レビューを必須にする。
- secret/API key/PII混入を確認する。
- 破壊的変更にはmigration/rollback planを必須にする。
- flaky testを放置しない。
- 依存ライブラリ追加時はlicense/security/maintainer activityを確認する。
- manifest/test-matrix/evidenceの更新漏れを検出する。

## Release Gate

Release Gateは「新機能仕様確認の場」ではない。出荷可否を判断する場。

Release Gateで見るもの:

- required項目がPASSしている。
- WindowsQA Server証跡が必要な項目に実画面/実GPU証跡がある。
- local diagnosticをAT/ST/Release Gateの代替にしていない。
- manifestとevidenceのsha256/パスが一致している。
- NOT_RUN / FAIL / BLOCKEDが隠されていない。
- feature flagのdefault、公開範囲、kill switchが妥当。
- high-risk変更の追加テストが実行されている。
- 未解決リスクが明示され、許容判断がある。

## Source Inventory Diff

以下のソースに追加・変更が入った場合、`test-inventory.md` と `manifest.json` の未分類差分を確認する。

- `apps/*/manifest.yaml`
- `src/workbench/coreAppRegistry.ts`
- `src/apps/useAppSystem.ts`
- `src/apps/types.ts`
- `src-tauri/src/lib.rs` の Tauri command登録
- `src-tauri/src/app_runtime/*`
- `src-tauri/src/agent_server*.rs`
- `src-tauri/src/agent_collaboration*.rs`
- `src-tauri/src/remote/*`
- `src-tauri/src/discord_bridge.rs`
- `src-tauri/src/agent_discord*.rs`
- `src-tauri/src/google/*`
- `src-tauri/src/github/*`
- `src-tauri/src/blender/*`
- `src-tauri/src/anima/*`
- `src-tauri/src/tts*`
- `src-tauri/src/license/*`
- `src-tauri/src/signal/*`

新しいcommand、App manifest、AI tool、permission、external integrationが未分類のままならRelease Gateを通さない。

## 最終方針

OribisのAppは画面単位ではなくcapability単位で管理する。

「ユーザーが画面で使える」だけでは完了ではない。  
「AIが安全に発見し、権限内で実行し、証跡を残し、テストで保証される」ことまでを新機能追加の完了条件にする。
