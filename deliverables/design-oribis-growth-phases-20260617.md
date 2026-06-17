# Oribis Growth Phases: Virtual Studio / Virtual World Roadmap

最終更新: 2026-06-17

## 1. 名称方針

推奨は以下の分離。

| レイヤー | 名称 | 役割 |
|---|---|---|
| アプリ / ブランド | Oribis | ルートブランド。短く、機能追加に耐える |
| 中核体験 / 製品ライン | Oribis Virtual Studio | Anima・Worker・Plugin・3D制作空間を統合した制作環境 |
| 将来構想 | Oribis Virtual World | Animaと生活・制作・遊びを共有する常駐型バーチャル空間 |
| AI companion | Anima | 会話、観察、提案、承認、説明の主体 |
| 実行層 | Worker / Internal Worker | 実務、ツール実行、ファイル操作、ジョブ管理 |

理由:

- `Oribis` は汎用ブランドとして残す。将来、Studio以外の機能を含めても破綻しない。
- `Oribis Virtual Studio` は商用訴求に使う。単なるAIチャットやコードエディタではなく、制作環境であることが伝わる。
- `Oribis Virtual World` は最終ビジョンとして扱う。MVP名にすると期待値が重くなるため、初期リリース名にはしない。

## 2. 現在地

Oribisは当初の「CLI WorkerをUIで包む」段階から、Animaが構造化された作業状態を理解できる Action Platform へ移行している。

完了済みの主要到達点:

| Phase | 状態 | 内容 |
|---|---|---|
| P1 | 完了 | Internal Worker read-only runtime / tool registry |
| P2 | 完了 | Anima dispatch proposal / approval / read-only job closed loop |
| P3 | 完了 | Approval / policy / audit / binding |
| P4 | 完了 | WritePlan / diff preview / approval hash binding |
| P5 | 完了 | single-operation `createFile` apply / hardening / UI |
| P6 | 完了 | rollback preview / validation / rollback proposal generation |
| P7 | 完了 | rollback proposal UI接続。rollback executorは作らない方針 |
| P11-A | 完了 | 最小Router enforcement。危険なdirect invoke経路を封鎖 |
| P12 | 完了 | sidecar実spawn前のmanifest / Router / DTO安全境界固定 |

意図的に未実装のもの:

- rollback executor
- shell / network / MCP write executor
- multi-operation write apply
- plugin sidecarの本格spawn /署名検証
- 自己改善の自動適用

これらは未着手ではなく、安全境界が揃うまで実行系を出さない方針。

## 3. 設計原則

### 3.1 実行は常に段階化する

危険操作は直接実行しない。

最終形の標準経路:

1. proposal生成
2. preview
3. hash / revision / request fingerprint binding
4. approval
5. apply
6. audit / artifact / event記録
7. 必要ならrollback proposal生成

rollbackも executor として直接戻すのではなく、逆方向の write proposal として生成し、同じ preview / approval / apply 経路へ流す。

### 3.2 AnimaはCLI出力ではなく構造化状態を理解する

OpenCodeやClaude CodeのCLIは標準出力ベースの強力な作業エージェントだが、UI側から見ると状態取得が不安定になりやすい。

OribisのInternal Workerでは、以下を構造化して保持する。

- Job
- Event
- Artifact
- Tool call
- Approval decision
- Policy decision
- WritePlan
- Rollback proposal
- Audit log
- Provider reference

これにより、Animaは「何が起きたか」「なぜ止まったか」「どの承認に紐づくか」「どの成果物を参照すべきか」を会話に使える。

### 3.3 Plugin / Console / Worker / Animaを同じ安全境界へ寄せる

ActionRouter / Permission / Secrets / Audit を中核に置く。

禁止するもの:

- pluginからの危険Tauri command直叩き
- secretの平文露出
- approvalなしのwrite
- hash bindingなしのapply
- UIだけで安全に見せる実装

許可するもの:

- read-only tool
- preview / proposal生成
- approvedかつbinding一致の限定apply
- audit可能なRouter経由実行

### 3.4 自己改善は証拠駆動・承認駆動にする

Oribisの最終目標には、Anima / Worker / Plugin / Virtual Studioが使うほど改善される自己進化システムを含める。

ただし、AIがOribis本体・プロンプト・権限・Worker policyを自動で直接書き換える設計は禁止する。

標準経路:

1. 実行ログ、会話ログ、テスト結果、ユーザー訂正、承認/拒否履歴を収集する。
2. 失敗/成功パターンを分類する。
3. 改善提案を生成する。
4. 根拠、影響範囲、差分、rollback方法を表示する。
5. ユーザー承認後に限定Adapterで反映する。
6. 反映後に評価し、改善効果が弱ければ撤回または再提案する。

初回リリースでは 1〜4 までに限定する。つまり、自己改善は「自動で賢くなる」機能ではなく、「作業履歴から改善点を見つけて、次に何を直すべきかを分かりやすく提示する」機能として提供する。

ユーザー向け名称は期待値を抑える。内部名は `SelfImprovementEngine` でよいが、初回UIでは「改善候補」「作業品質メモ」「再発防止提案」のように、自己改変を連想させない表現を使う。

自己改善の反映先は段階的に制限する。

初回リリースで許可:

- 失敗/成功/ユーザー訂正/テスト結果の記録
- Workerごとの再発失敗検出
- テスト不足・手順漏れの改善提案
- Anima/Workerの使い勝手を良くする提案カード表示
- 再利用できそうなWorker手順の候補提示

初回リリースで禁止:

- Oribis本体コードの自動改変
- tool / sidecar / plugin権限の自動昇格
- approvalなしのprompt適用
- prompt / settings / worker policy の自動適用
- 失敗1回だけを根拠にした恒久変更
- 反省文を無制限にcontext投入する設計

## 4. OpenCode代替を超える価値

Oribisの価値は「OpenCodeを内製した」ことではない。OpenCode相当の作業能力を、Anima・UI・3D体験・Pluginと統合できる形へ再構成する点にある。

### 4.1 OpenCode代替としての価値

- CLI依存を減らし、標準出力パースに依存しない。
- Job/Event/Artifact単位でUI表示できる。
- approval / policy / auditを製品仕様として持てる。
- Workerごとに状態を保存し、再開・一覧・履歴確認できる。
- applyやrollbackを安全な段階実行にできる。

### 4.2 OpenCodeでは難しいOribis独自価値

- Animaが作業状態を理解し、自然な会話で説明できる。
- 3Dキャラクターの吹き出し・音声・表情・アニメーションと作業状態を接続できる。
- ユーザーの制作環境そのものをVirtual Studioとして見せられる。
- Plugin / JS-TS Console / Internal Worker / MCP / Blender連携を同じ安全境界へ統合できる。
- 失敗、承認、差分、成果物、rollback proposalまでをUI体験として扱える。
- 将来的に「Animaが隣で制作を見守り、必要なときに作業提案する」体験へ拡張できる。

## 5. 成長フェーズ

### Phase 0: CLI Worker復旧 / Anima Provider分離

目的:

- 会話はAnima Providerへ分離。
- 実務はWorker CLI / Internal Workerへ分離。
- `opencode | claude | codex` のCLI Worker選択を維持しつつ、Anima会話と混ぜない。

到達状態:

- 会話はKimi/OpenAI/local LLM等のAnima Providerで高速化。
- WorkerはPTY/CLIまたはInternal Workerで実務担当。

### Phase 1: Internal Worker read-only foundation

目的:

- CLIに頼らず、Oribis内でread-only jobを実行できる。
- Job/Event/Artifactを構造化保存する。

価値:

- Animaが安全に作業内容を参照できる。
- UIが進捗・成果物・エラーを安定表示できる。

### Phase 2: Approval / Policy / Audit

目的:

- Animaの提案を即実行せず、承認・拒否・期限切れ・policy decisionとして扱う。
- audit trailを残す。

価値:

- 商用アプリとして「なぜ実行されたか」を説明できる。
- 危険操作をdeny-by-defaultにできる。

### Phase 3: WritePlan / DiffPreview / HashBinding

目的:

- 書き込み操作を直接実行せず、WritePlanとして生成する。
- proposalHash / requestFingerprint / revisionHash で承認対象を固定する。

価値:

- 「見た差分」と「承認した差分」と「実行した差分」を一致させられる。
- stale previewや差分すり替えを防げる。

### Phase 4: Safe Apply

目的:

- 最小範囲からapply executorを解禁する。
- 現在はsingle-operation `createFile` から開始。

制約:

- `createFile` / `updateFile` 以外は禁止。
- multi-operationは禁止。
- secret / redacted / spilled / content artifactは禁止。
- approval binding一致が必須。
- TOCTOU再検証が必須。

次の拡張:

- P8-A: `updateFile` backend safety gate
- P8-B: `updateFile` UI解禁

### Phase 5: Rollback as Proposal

目的:

- rollback executorを作らない。
- rollbackRecordから逆方向WritePlan proposalを生成する。
- 生成されたrollback proposalも通常のpreview / approval / apply経路へ流す。

価値:

- rollbackだけ特別な危険実行系にしない。
- 安全境界を単一化できる。

### Phase 6: Router Enforcement / Plugin Safety

目的:

- plugin / console / HostAPI から危険Tauri commandを直叩きできないようにする。
- builtin例外やstorage例外を分離し、危険操作はRouter経由に寄せる。

到達状態:

- `plugin_*` と `internal_worker_apply_write_plan` のdirect invoke拒否。
- builtin有効状態は専用APIへ分離。
- read-only互換を維持しながら、危険経路を封鎖。

### Phase 7: Anima-aware Work OS

目的:

- AnimaがJob/Event/Artifact/Audit/WritePlanを会話の文脈として利用する。
- ユーザーの作業を理解し、提案・説明・確認を行う。

価値:

- 単なるチャットAIではなく、作業OSの案内役になる。
- エラー・差分・承認待ち・成果物を自然会話で説明できる。

### Phase 8: Oribis Virtual Studio MVP

目的:

- 3D空間・Anima・Worker・Plugin・Blender/MCP連携を制作環境として統合する。

想定機能:

- Animaの3D表示、表情、音声、吹き出し。
- Worker jobと3D空間内の状態表示。
- Blender/MCP経由の3D制作支援。
- VRMモデル、衣装、マテリアル色変更。
- Plugin/ConsoleからStudio機能を拡張。

価値:

- コード、3D、音声、キャラクターを1つの制作体験に統合する。
- 「AI coding app」ではなく「AI creative studio」として訴求できる。

### Phase 9: Oribis Virtual World

目的:

- Studioを越えて、Animaと一緒に過ごす常駐型バーチャル空間へ拡張する。

想定体験:

- 作業中の見守り。
- 困ったときの即時相談。
- ゲーム・動画・制作の共有体験。
- ユーザーごとのWorld / Room / Companion状態保存。

注意:

- 常時画面理解はトークン・プライバシー・許可設計が重い。
- 初期はイベント駆動・低頻度snapshot・ユーザー明示トリガーを基本にする。
- リアルタイム監視は後段の高付加価値機能として扱う。

### Phase 10: Self-Improvement / Self-Learning / Self-Evolution

目的:

- Oribisを「使うほど作業環境に適応するAI OS」へ進化させる。
- Anima / Worker / Plugin / Virtual Studioの失敗と成功を構造化し、改善提案へ変換する。
- 自己進化を最終目標に置くが、初回リリースは改善提案レイヤーに限定する。自動適用や本体改変は入れない。

構成:

```text
SelfImprovementEngine
  input/
    conversation_traces
    worker_jobs
    tool_calls
    test_results
    user_feedback
    approval_reject_history

  memory/
    episodic_memory      過去の成功/失敗事例
    semantic_memory      ユーザー・プロジェクト・設定の事実
    procedural_memory    改善された手順・ルール・プロンプト候補
    skill_library        再利用可能なWorker手順

  analyzer/
    failure_classifier
    success_pattern_extractor
    regression_detector
    cost_latency_analyzer

  proposer/
    prompt_patch_proposal
    worker_policy_proposal
    test_gap_proposal
    ui_workflow_proposal
    skill_proposal

  gate/
    evidence_required
    human_approval
    diff_preview
    rollback_plan
    eval_before_apply

  applier/
    prompt_adapter
    worker_policy_adapter
    test_adapter
    settings_adapter
    skill_adapter
```

初回リリース実装:

0. `Improvement taxonomy / retention policy`
   - event kind、scope、severity、cause category、evidence、source、user visibility、retentionを定義する。
   - 却下、後で見る、手動対応済み、再表示条件、重複抑止のstate machineを固定する。
   - 初回から「再提案スパム」を防ぐ。
1. `ImprovementEventStore`
   - 成功、失敗、ユーザー訂正、テスト結果、承認/拒否をSQLiteへ保存する。
   - Anima記憶DBへ混ぜず、同じOribisHome配下の別DBまたは別schema/tableとして分離する。
   - Workerごと、Projectごと、Anima会話ごとの参照キーを持つ。
2. `ImprovementAnalyzer`
   - 再発失敗、テスト不足、手戻り、ユーザー訂正を分類する。
3. `ImprovementProposal`
   - 何を、なぜ、どの証拠で、どこへ反映するかを構造化する。
   - 根拠となったJob/Event/Artifact/Test/User feedbackを追跡できる。
   - dedupe / suppression ruleを持ち、同じ改善候補を繰り返し出さない。
4. `Improvement UI`
   - 改善提案、根拠、関連Job/Event/Artifact、再発回数、推奨アクションを表示する。
   - 初回は「提案を確認」「後で見る」「却下」「手動で対応済み」までに限定する。
5. `Context-aware retrieval (limited)`
   - 初回はfeature flagまたはconfirmed-onlyに限定する。
   - 改善ログをAnima/Worker promptへ無制限注入しない。
   - 人間確認済みの改善提案、または提案カード表示の補助だけに使う。

後段実装:

6. `Approval UI`
   - diff preview、適用先、影響範囲、rollbackを表示する。
7. `Safe Applier`
   - prompt / settings / test-plan / skill候補だけを承認後に反映可能にする。

商業価値:

- 「AIが作業する」だけでなく「作業から学ぶ」体験になる。
- Animaがユーザーごとの癖、プロジェクト固有の手順、過去の失敗を説明可能な形で扱える。
- Workerの成功手順をskill library化でき、チーム/プロジェクト単位で再利用できる。
- OpenCodeや一般的なCLI agentとの差別化として、UI・承認・記憶・自己改善が一体化する。

安全制約:

- 自己改善提案は必ず証拠を要求する。
- 初回リリースでは自動適用しない。
- 適用はAdapter経由に限定し、直接ファイル編集を禁止する。
- 反映後は評価し、効果がない場合は撤回可能にする。
- tool権限、sidecar権限、plugin権限は自己改善の自動適用対象外にする。
- 改善ログは事実として保存し、提案は説明可能にし、反映は人間承認を越えない。

## 6. 今後の優先順位

codex-adviserレビューと自己進化方針を踏まえた実装順。

| 優先 | 内容 | 理由 |
|---|---|---|
| 1 | P13 sidecar executor threat model / skeleton | plugin runtimeを実spawn前に安全化する |
| 2 | P14 Anima/Worker context compaction | token消費と長期会話の制御 |
| 3 | P15a Improvement taxonomy / retention policy | 保存前に分類・保持・削除・重複抑止を固定する |
| 4 | P15 SelfImprovementEventStore | 自己改善の観測基盤。SQLite分離storeで記録する |
| 5 | P16a Proposal evidence / dedupe / feedback state | 提案根拠と却下/後回し/手動対応済みの状態遷移を固定する |
| 6 | P16 ImprovementProposal Lite / UI | 初回リリース向け。改善提案表示までで自動適用しない |
| 7 | P17 Context-aware Improvement Retrieval | feature flagまたはconfirmed-onlyで限定導入する |
| 8 | P18 WDIO実GUI gate安定化 | 商用品質の自動検証 |
| 9 | P19 Virtual Studio MVP連携 | Anima/Worker/Plugin/3D空間を体験として統合 |
| 10 | P20 Safe Applier adapters | 初回リリース後。prompt/settings/test-plan/skill候補だけ承認適用 |
| 11 | P21 docsまとめ更新 | 実装完了後にSTATUS/MAP/specをまとめて同期 |

## 7. 商業価値の見立て

### 初期市場

- 個人開発者
- AIコーディング利用者
- ゲーム制作・3D制作・VRM/VTuber制作ユーザー
- キャラクターAI / デスクトップマスコット志向のユーザー
- Blender / Unity / Godot / Web制作を横断する小規模クリエイター

### 差別化軸

- 「会話AI」ではなく「作業を理解するキャラクターAI」。
- 「コードエディタ」ではなく「制作環境」。
- 「CLIラッパー」ではなく「安全境界を持つ作業OS」。
- 「3Dマスコット」ではなく「実務と接続したAnima」。

### 成功条件

- Animaの応答が速い。
- TTS/表情/吹き出しが作業テンポを邪魔しない。
- Worker jobが安定して見える。
- 危険操作が常にpreview/approval経由になる。
- WDIOで実GUIの主要体験が継続的にPASSする。
- Plugin/Consoleが「Oribis内で何でも作れる」方向へ伸びる。

## 8. リスク

| リスク | 対策 |
|---|---|
| 器用貧乏化 | MVPはVirtual Studioに絞る。Worldは後段 |
| 安全境界の抜け | Router enforcement / Permission / Audit / secret redactionを先に固める |
| UIが複雑化 | Job / Proposal / Approval / Apply / Rollback proposalの状態語彙を統一 |
| テスト不能化 | WDIO実GUIを主要ゲート化。手動前提を禁止 |
| CLI依存の復活 | CLI Workerは互換層。中核はInternal Workerへ寄せる |
| 常時監視のプライバシー問題 | 明示許可・範囲指定・イベント駆動・低頻度snapshotから開始 |
| 自己改善の暴走 | 証拠必須、人間承認必須、Adapter限定、自動権限昇格禁止 |
| プロンプト肥大化 | episodic/semantic/procedural memoryを分離し、必要分だけ検索注入 |
| 改善効果不明 | 適用前後のテスト結果、手戻り回数、遅延、成功率を記録 |

## 9. 結論

アプリ名は `Oribis` を維持する。製品体験として `Oribis Virtual Studio` を前面に出し、将来構想として `Oribis Virtual World` を掲げる。

OpenCode代替は中間地点であり、最終価値ではない。最終価値は、Animaがユーザーの作業・制作・承認・成果物を理解し、3D/音声/UI/Plugin/Workerを通じて一緒に作業し、さらにその作業結果から改善提案を出してOribis自身を進化させられることにある。

直近は sidecar/plugin runtimeの安全化、Anima/Worker context compaction、SelfImprovementEventStoreの順で進める。自己進化は最終目標だが、初回リリースでは「証拠に基づく改善提案」と「改善storeをAnima/Workerが参照できること」までに留める。承認適用や自動適用は初回リリース後に段階導入する。
