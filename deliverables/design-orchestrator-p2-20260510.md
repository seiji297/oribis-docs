# P2 詳細設計書: Orchestrator Editor 全画面 UI

> 対象エピック: `epic-oribis-orchestrator-p2-20260510.md`  
> 設計書参照: `anima-orchestrator-architecture.md` §Orchestrator エディター UI / §設定ファイル構成 / §実装ロードマップ  
> 作成日: 2026-05-10  
> 作成者: planner  
> 前提: P1 完了済み（commit: 5c8b0f8 + P1品質修正 4e5d6c8）

---

## 1. 概要

本設計書は、Oribis Orchestrator P2（Editor UI）の詳細設計を定義する。  
P1 で構築した左ドロワー・下部 PTY パネル・Worker 管理基盤を拡張し、**全画面 Orchestrator Editor** を実装する。

### 1.1 P2 スコープ（AC 対応）

| AC | 内容 | 対応タスク |
|----|------|-----------|
| AC-1 | Editor 全画面起動（ESC/Close で復帰） | TASK-8 |
| AC-2 | レーンパイプライン表示（部門横並び + ステージ可視化） | TASK-5 |
| AC-3 | Department 詳細パネル（5タブ編集） | TASK-6 |
| AC-4 | Department CRUD（追加・編集・削除） | TASK-7 |
| AC-5 | 設定ファイル統合（`~/.oribis/departments/*.json`） | TASK-2, TASK-3 |
| AC-6 | テスト（Rust + TS + E2E） | TASK-9 |
| AC-7 | 既存機能影響なし | 全タスク |

### 1.2 設計判断（設計書 §設計判断 準拠）

- **ノードエディタは不採用**: トポロジー固定のためレーンパイプラインで十分
- **全画面専用画面**: 420px ドロワーでは編集困難。フル幅で直感的編集を実現
- **Single Source of Truth**: `departments/*.json` を GUI が直接読み書き
- **P1 API 不変更原則**: `department_config.rs` のファイル I/O API は変更しない

---

## 2. 型定義設計

### 2.1 基本方針

P1 で Rust 側と TypeScript 側の `DepartmentConfig` に構造的差異が生じている。  
P2 では **Rust 側構造体は変更せず、TS 側を Rust 側と整合させる** 方針とする。  
差分フィールド（`env`, `tags`, `skills`, `instructions`, `review_mode`）は Rust 側の `extra`（`serde(flatten)`）に格納され、TS 側では個別フィールドとして展開する。

### 2.2 Rust ↔ TypeScript 型対応表

#### 2.2.1 コア型

| Rust（`department_config.rs`） | TypeScript（`src/plugin/types.ts`） | 備考 |
|-------------------------------|-----------------------------------|------|
| `DepartmentConfig` | `DepartmentConfig` | 構造統一（下記詳細） |
| `NarrationConfig` | `NarrationConfig` | P1 で Rust 側のみ定義。TS 側に追加 |
| `QualityGateConfig` | `QualityGateConfig` | P1 で Rust 側のみ定義。TS 側に追加 |
| `ScheduleConfig` | `ScheduleConfig` | P1 で Rust 側のみ定義。TS 側に追加 |

#### 2.2.2 DepartmentConfig フィールド詳細

| フィールド | Rust 型 | TS 型 | UI タブ | 備考 |
|-----------|---------|-------|---------|------|
| `name` | `String` | `string` | — | ファイル名から導出（読み取り専用） |
| `cli` | `String` | `string` | General | CLI 種別（claude/codex/opencode 等） |
| `model` | `Option<String>` | `string \| undefined` | General | モデル名 |
| `working_dir` | `Option<String>` | `string \| undefined` | General | 作業ディレクトリ |
| `max_workers` | `Option<u32>` | `number \| undefined` | General | 最大 Worker 数（デフォルト 1） |
| `mode` | `Option<String>` | `string \| undefined` | General | 実行モード: `"solo"` / `"lead"` |
| `constraints` | `Vec<String>` | `string[]` | General | 制約文字列一覧 |
| `capabilities` | `Vec<String>` | `string[]` | General | 能力タグ（TS の `tags` と統合） |
| `narration` | `Option<NarrationConfig>` | `NarrationConfig \| undefined` | General | ナレーション設定 |
| `quality_gate` | `Option<QualityGateConfig>` | `QualityGateConfig \| undefined` | Workflow | 品質ゲート設定 |
| `schedule` | `Option<Vec<ScheduleConfig>>` | `ScheduleConfig[] \| undefined` | Schedule | 定期実行タスク一覧 |
| `extra` | `Map<String, Value>` | `Record<string, unknown>` | — | 拡張フィールド（env/skills/instructions/review_mode 等を格納） |

#### 2.2.3 extra フィールド内の標準キー

以下のキーは P2 UI で標準的に使用する。`extra` に格納されるため、存在しない場合はデフォルト値で扱う。

| キー | 型 | デフォルト | UI タブ | 説明 |
|------|-----|-----------|---------|------|
| `env` | `Record<string, string>` | `{}` | General | 環境変数 |
| `skills` | `string[]` | `[]` | Skills | 有効スキル ID 一覧 |
| `instructions` | `string` | `""` | Prompts | プロンプトファイルパス（または内容） |
| `review_mode` | `string` | `"cross-model"` | Workflow | レビューモード |

### 2.3 TypeScript 型定義（最終版）

```typescript
// src/plugin/types.ts — P2 統合後（P1 互換性維持）

export interface NarrationConfig {
  enabled: boolean;
  batch_interval_sec: number;
}

export interface QualityGateConfig {
  design_gate: boolean;
  final_gate: boolean;
}

export interface ScheduleConfig {
  task: string;
  interval: string;
  enabled: boolean;
}

export interface DepartmentConfig {
  name: string;
  cli: string;
  model?: string;
  working_dir?: string;
  max_workers?: number;
  mode?: string;
  constraints: string[];
  capabilities: string[];
  narration?: NarrationConfig;
  quality_gate?: QualityGateConfig;
  schedule?: ScheduleConfig[];
  /** 拡張フィールド — env, skills, instructions, review_mode 等 */
  extra?: Record<string, unknown>;
}

/** extra から安全に値を取得するヘルパー型 */
export interface DepartmentExtra {
  env?: Record<string, string>;
  tags?: string[];
  skills?: string[];
  instructions?: string;
  review_mode?: string;
}
```

### 2.4 P1 互換性維持方針

- `DrawerDepartment.tsx` は `name` のみ使用 → **影響なし**
- `App.tsx` は `departments` ステートを `DepartmentConfig[]` で保持 → 構造変更しても `name` へのアクセスは維持
- 既存の Tauri コマンド `get_department_config` / `update_department_config` は既に Rust 側の `DepartmentConfig` を返す → **影響なし**
- `constraints`, `capabilities` 等のフィールド変更箇所は P2 実装時に同期修正（1ファイル `types.ts` のみ）

---

## 3. API 契約（Tauri コマンド・イベント）

### 3.1 基本方針

P1 で登録済みのコマンドを最大限流用し、P2 用に必要なコマンドのみ追加する。  
`department_config.rs` の既存関数（`list_departments`, `get_department`, `update_department`）を Tauri コマンドとして公開する。

### 3.2 既存 Tauri コマンド（P1 で登録済み・流用）

| コマンド | 引数 | 戻り値 | 用途 |
|---------|------|--------|------|
| `list_workers` | — | `WorkerInfo[]` | Worker 一覧取得 |
| `spawn_worker` | `{ department: string }` | `WorkerInfo` | Worker 手動起動 |
| `kill_worker` | `{ worker_id: string }` | — | Worker 停止 |
| `get_department_config` | `{ name: string }` | `DepartmentConfig` | 部門設定取得 |
| `update_department_config` | `{ name: string, config: DepartmentConfig }` | — | 部門設定更新 |

### 3.3 新規 Tauri コマンド（P2 で追加）

| コマンド | 引数 | 戻り値 | 用途 | AC |
|---------|------|--------|------|-----|
| `list_departments` | — | `DepartmentConfig[]` | 全部門設定一覧 | AC-2 |
| `delete_department` | `{ name: string }` | `Result<(), string>` | 部門設定削除（ファイル削除） | AC-4 |
| `validate_department_config` | `{ config: DepartmentConfig }` | `ValidationResult` | Schema バリデーション（Save 前チェック） | AC-5 |

#### `ValidationResult` 型（TypeScript）

```typescript
export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

export interface ValidationError {
  field: string;
  message: string;
}
```

### 3.4 Rust 側実装詳細（`lib.rs` 追加分）

```rust
// src-tauri/src/lib.rs — P2 追加コマンド

#[tauri::command]
fn list_departments_cmd() -> Result<Vec<department_config::DepartmentConfig>, String> {
    let depts = department_config::list_departments()?;
    Ok(depts.into_iter().map(|(_, cfg)| cfg).collect())
}

#[tauri::command]
fn delete_department_cmd(name: String) -> Result<(), String> {
    // 操作中の Worker がいるか確認（worker_manager 経由）
    let active_workers = worker_manager::list_active_workers_for(&name)?;
    if !active_workers.is_empty() {
        return Err(format!(
            "Cannot delete department '{}' while workers are active: {:?}",
            name, active_workers
        ));
    }
    
    let path = department_config::departments_dir()?.join(format!("{}.json", name));
    if !path.is_file() {
        return Err(format!("Department '{}' not found", name));
    }
    std::fs::remove_file(&path)
        .map_err(|e| format!("Failed to delete {}: {}", path.display(), e))?;
    Ok(())
}

#[tauri::command]
fn validate_department_config_cmd(
    config: department_config::DepartmentConfig,
) -> Result<ValidationResult, String> {
    let mut errors = Vec::new();
    
    // 必須フィールドチェック
    if config.cli.is_empty() {
        errors.push(ValidationError { field: "cli".to_string(), message: "CLI is required".to_string() });
    }
    
    // Schema バリデーション（_schema.json 読み込み・オプション）
    // TODO: JSON Schema による構造検証（TASK-2 で実装）
    
    Ok(ValidationResult {
        valid: errors.is_empty(),
        errors,
    })
}

#[derive(serde::Serialize)]
struct ValidationResult {
    valid: bool,
    errors: Vec<ValidationError>,
}

#[derive(serde::Serialize)]
struct ValidationError {
    field: String,
    message: String,
}
```

### 3.5 Tauri Event（追加なし）

P2 では新規 Tauri Event は発行しない。Editor 内の状態変更は React ステートで管理し、Save 時に Tauri コマンドを呼び出す。

---

## 4. ファイル構成

### 4.1 新規ファイル（8 件）

| # | ファイルパス | 役割 | タスク |
|---|------------|------|--------|
| 1 | `src/components/OrchestratorEditor.tsx` | Editor 全画面ルート（レイアウト + 状態管理） | TASK-4 |
| 2 | `src/components/LanePipeline.tsx` | レーンパイプライン表示（部門レーン横並び） | TASK-5 |
| 3 | `src/components/DepartmentDetailPanel.tsx` | 詳細パネルルート（タブ切替 + 選択部門表示） | TASK-6 |
| 4 | `src/components/tabs/GeneralTab.tsx` | General タブ（model/cli/working_dir/mode/max_workers/constraints/env/tags） | TASK-6 |
| 5 | `src/components/tabs/WorkflowTab.tsx` | Workflow タブ（quality_gate/review_mode/パイプライン可視化） | TASK-6 |
| 6 | `src/components/tabs/ScheduleTab.tsx` | Schedule タブ（定期タスク一覧/トグル/追加削除） | TASK-6 |
| 7 | `src/components/tabs/SkillsTab.tsx` | Skills タブ（有効スキル一覧/追加削除/プレビュー） | TASK-6 |
| 8 | `src/components/tabs/PromptsTab.tsx` | Prompts タブ（instructions 一覧/プレビュー/編集） | TASK-6 |

### 4.2 修正ファイル（4 件）

| # | ファイルパス | 修正内容 | タスク |
|---|------------|---------|--------|
| 1 | `src/plugin/types.ts` | `DepartmentConfig` 統合 + `NarrationConfig`/`QualityGateConfig`/`ScheduleConfig` 追加 | TASK-2 |
| 2 | `src-tauri/src/lib.rs` | 新規 Tauri コマンド登録（`list_departments`, `delete_department`, `validate_department_config`） | TASK-3 |
| 3 | `src/App.tsx` | `[Edit]` ボタン追加 + `OrchestratorEditor` 全画面切替（Settings と同方式） | TASK-8 |
| 4 | `src/components/DrawerDepartment.tsx` | `[Edit]` ボタン配置（Editor 起動トリガー） | TASK-8 |

### 4.3 変更なし（P1 資産をそのまま使用）

| ファイル | 理由 |
|---------|------|
| `src-tauri/src/department_config.rs` | P1 で実装済み。API 変更禁止 |
| `src-tauri/src/worker_manager.rs` | P1 で実装済み。Worker 状態確認に使用 |
| `src/components/XtermTerminal.tsx` | PTY 表示は Editor スコープ外（下部パネル維持） |
| `src/components/WorkerPanel.tsx` | PTY パネルは Editor 起動中も維持 |

---

## 5. コンポーネント設計

### 5.1 コンポーネント階層

```
App.tsx
├── DrawerDepartment.tsx（修正: [Edit]ボタン追加）
│   └── [Edit] → App.tsx 経由で editorOpen=true
├── OrchestratorEditor.tsx（新規: 全画面ルート）
│   ├── LanePipeline.tsx（新規: 上部レーン）
│   │   └── 各部門レーン（インライン）
│   │       ├── ステージマーカー（Design→Impl→Review→DA→Done）
│   │       ├── 現在地マーカー（●）
│   │       ├── 完了マーカー（✓）
│   │       └── [×] 削除ボタン
│   ├── [+ Add Department] ボタン
│   └── DepartmentDetailPanel.tsx（新規: 下部詳細）
│       ├── タブバー [General][Workflow][Schedule][Skills][Prompts]
│       ├── GeneralTab.tsx
│       ├── WorkflowTab.tsx
│       ├── ScheduleTab.tsx
│       ├── SkillsTab.tsx
│       └── PromptsTab.tsx
└── （下部 PTY パネルは維持 — Editor 表示中も alive）
```

### 5.2 OrchestratorEditor.tsx（全画面ルート）

#### 責務
- Editor 全画面レイアウト管理
- 部門一覧ステート管理（`useState<DepartmentConfig[]>`）
- 選択部門ステート管理
- ESC キー/Close ボタンで `onClose` コールバック発火
- 子コンポーネントへのデータ受け渡し

#### Props

```typescript
interface OrchestratorEditorProps {
  /** Editor を閉じるコールバック — App.tsx がメイン画面に復帰 */
  onClose: () => void;
  /** 初期選択部門名（省略時は先頭） */
  initialDepartment?: string;
}
```

#### 状態

```typescript
// Editor 内部状態
const [departments, setDepartments] = useState<DepartmentConfig[]>([]);
const [selectedDept, setSelectedDept] = useState<string | null>(null);
const [isLoading, setIsLoading] = useState(false);
const [saveError, setSaveError] = useState<string | null>(null);
```

#### 副作用

```typescript
// マウント時: 全部門一覧を読み込み
useEffect(() => {
  loadDepartments();
}, []);

// ESC キーで閉じる
useEffect(() => {
  const handleKey = (e: KeyboardEvent) => {
    if (e.key === "Escape") onClose();
  };
  window.addEventListener("keydown", handleKey);
  return () => window.removeEventListener("keydown", handleKey);
}, [onClose]);
```

#### ハンドラ

```typescript
const loadDepartments = async () => {
  setIsLoading(true);
  try {
    const list = await invoke<DepartmentConfig[]>("list_departments");
    setDepartments(list);
    if (!selectedDept && list.length > 0) {
      setSelectedDept(initialDepartment ?? list[0].name);
    }
  } finally {
    setIsLoading(false);
  }
};

const handleSaveDepartment = async (config: DepartmentConfig) => {
  setSaveError(null);
  try {
    // バリデーション
    const validation = await invoke<ValidationResult>("validate_department_config", { config });
    if (!validation.valid) {
      setSaveError(validation.errors.map(e => `${e.field}: ${e.message}`).join("; "));
      return;
    }
    // 保存
    await invoke("update_department_config", { name: config.name, config });
    await loadDepartments(); // 一覧再読み込み
  } catch (e) {
    setSaveError(String(e));
  }
};

const handleDeleteDepartment = async (name: string) => {
  if (!window.confirm(`Delete department "${name}"?`)) return;
  try {
    await invoke("delete_department", { name });
    await loadDepartments();
    if (selectedDept === name) {
      setSelectedDept(departments.find(d => d.name !== name)?.name ?? null);
    }
  } catch (e) {
    setSaveError(String(e));
  }
};

const handleAddDepartment = async () => {
  const name = window.prompt("Enter department name:");
  if (!name || name.trim() === "") return;
  
  // デフォルトテンプレート生成
  const newConfig: DepartmentConfig = {
    name: name.trim(),
    cli: "claude",
    constraints: [],
    capabilities: [],
    extra: {},
  };
  
  try {
    await invoke("update_department_config", { name: name.trim(), config: newConfig });
    await loadDepartments();
    setSelectedDept(name.trim());
  } catch (e) {
    setSaveError(String(e));
  }
};
```

### 5.3 LanePipeline.tsx（レーンパイプライン）

#### 責務
- 部門一覧を横並びレーンで表示
- 各部門のワークフローステージを可視化
- 部門クリックで選択状態を変更
- `[+ Add Department]` ボタン配置

#### Props

```typescript
interface LanePipelineProps {
  departments: DepartmentConfig[];
  selectedDept: string | null;
  onSelectDept: (name: string) => void;
  onAddDepartment: () => void;
  onDeleteDepartment: (name: string) => void;
}
```

#### ワークフローステージ定義

```typescript
const WORKFLOW_STAGES = ["Design", "Impl", "Review", "DA", "Done"] as const;

/** 部門の capabilities から表示ステージを決定 */
function getDepartmentStages(dept: DepartmentConfig): string[] {
  // Advisor: Review のみ
  if (dept.capabilities.includes("advisor") || dept.cli === "advisor") {
    return ["Review", "Done"];
  }
  // Research: 軽量パイプライン
  if (dept.capabilities.includes("research")) {
    return ["Impl", "Done"];
  }
  // デフォルト: 全ステージ
  return [...WORKFLOW_STAGES];
}
```

#### レイアウト仕様

```
┌─────────────────────────────────────────────────────┐
│  SysDev  ━[Design]━━[Impl]━━[Review]━━[DA]━━ ✓     │  ← 横並びレーン
│  AFD     ━[Design]━━[Impl]━━[Review]━━[DA]━━ ✓     │
│  Advisor ━━━━━━━━━━━[Review]━━━━━━━━━━━━━━━━ ✓     │
│  Research ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ✓     │
│                                                     │
│  [+ Add Department]                                 │
└─────────────────────────────────────────────────────┘
```

- 各部門レーンは横長カード（幅: 固定 or フレキシブル）
- ステージ間は `━━` で接続
- 現在地: 黄色 ● マーカー（最終完了ステージの次）
- 完了: 緑色 ✓ マーカー（最終ステージ）
- 未完了: 灰色ステージラベル
- ホバー: 背景色変化 + カーソルポインタ
- 選択中: 青いボーダー強調

### 5.4 DepartmentDetailPanel.tsx（詳細パネルルート）

#### 責務
- 5 タブ切替 UI
- 選択部門の設定を子タブに受け渡し
- Save ボタン配置 + 保存実行
- バリデーションエラー表示

#### Props

```typescript
interface DepartmentDetailPanelProps {
  department: DepartmentConfig;
  onSave: (config: DepartmentConfig) => void;
  onChange: (config: DepartmentConfig) => void; // リアルタイム編集用（未保存）
  saveError: string | null;
}
```

#### 状態

```typescript
type TabId = "general" | "workflow" | "schedule" | "skills" | "prompts";
const [activeTab, setActiveTab] = useState<TabId>("general");
const [draftConfig, setDraftConfig] = useState<DepartmentConfig>(department);
```

#### タブ定義

```typescript
const TABS: { id: TabId; label: string }[] = [
  { id: "general", label: "General" },
  { id: "workflow", label: "Workflow" },
  { id: "schedule", label: "Schedule" },
  { id: "skills", label: "Skills" },
  { id: "prompts", label: "Prompts" },
];
```

### 5.5 GeneralTab.tsx

#### 編集フィールド

| フィールド | 型 | 入力形式 | バリデーション |
|-----------|-----|---------|-------------|
| `cli` | `string` | テキスト入力 | 空禁止 |
| `model` | `string` | テキスト入力 | — |
| `working_dir` | `string` | テキスト入力（パス） | — |
| `mode` | `string` | セレクトボックス（"solo" / "lead"） | — |
| `max_workers` | `number` | 数値入力（1-10） | 整数、最小 1 |
| `constraints` | `string[]` | タグ入力（Enter で追加、× で削除） | — |
| `capabilities` | `string[]` | タグ入力 | — |
| `env` | `Record<string, string>` | キー・バリュー行追加/削除 | — |
| `narration.enabled` | `boolean` | トグルスイッチ | — |
| `narration.batch_interval_sec` | `number` | 数値入力（秒） | 最小 10 |

#### Props

```typescript
interface GeneralTabProps {
  config: DepartmentConfig;
  onChange: (config: DepartmentConfig) => void;
  errors: ValidationError[];
}
```

### 5.6 WorkflowTab.tsx

#### 編集フィールド

| フィールド | 型 | 入力形式 |
|-----------|-----|---------|
| `quality_gate.design_gate` | `boolean` | トグルスイッチ |
| `quality_gate.final_gate` | `boolean` | トグルスイッチ |
| `review_mode` | `string` | セレクト（"cross-model" / "same-model" / "none"） |
| パイプライン可視化 | — | 読み取り専用（General の capabilities/cli から導出） |

#### パイプラインプレビュー

```typescript
function getPipelinePreview(dept: DepartmentConfig): { stages: string[]; enabled: boolean[] } {
  const stages = getDepartmentStages(dept);
  // quality_gate 設定に応じて DA ゲートの有効/無効を表示
  const enabled = stages.map(s => {
    if (s === "DA") return dept.quality_gate?.design_gate ?? true;
    return true;
  });
  return { stages, enabled };
}
```

### 5.7 ScheduleTab.tsx

#### 編集フィールド

| フィールド | 型 | 入力形式 |
|-----------|-----|---------|
| タスク一覧 | `ScheduleConfig[]` | テーブル表示（task / interval / enabled） |
| 新規追加 | — | 「+ Add」ボタン → 行追加（task 入力 + interval 入力 + enabled トグル） |
| 削除 | — | 各行の [×] ボタン |

#### Props

```typescript
interface ScheduleTabProps {
  schedule: ScheduleConfig[];
  onChange: (schedule: ScheduleConfig[]) => void;
}
```

### 5.8 SkillsTab.tsx

#### 編集フィールド

| フィールド | 型 | 入力形式 |
|-----------|-----|---------|
| 有効スキル一覧 | `string[]` | タグ入力（Enter で追加、× で削除） |
| スキルプレビュー | — | 選択したスキルの実体を読み取り専用で表示 |

#### スキル実体読み込み

```typescript
// スキルファイルパス: ~/.oribis/roles/{orchestrator|worker}/skills/{skill_id}.md
// または ~/.oribis/roles/_common/skills/{skill_id}.md

async function loadSkillPreview(skillId: string): Promise<string> {
  // Tauri コマンドでファイル読み込み（または fs API）
  // TODO: スキル読み込み用 Tauri コマンドが必要な場合は TASK-3 で追加検討
  return "Skill content preview...";
}
```

### 5.9 PromptsTab.tsx

#### 編集フィールド

| フィールド | 型 | 入力形式 |
|-----------|-----|---------|
| instructions パス | `string` | テキスト入力（ファイルパス） |
| プレビュー | — | ファイル内容読み取り専用表示 |
| 編集 | — | テキストエリア（直接編集可能） |
| 保存 | — | [Save to File] ボタン |

#### ファイル読み書き

```typescript
async function loadPromptFile(path: string): Promise<string> {
  // Tauri fs API またはコマンド経由
  return await invoke<string>("read_text_file", { path });
}

async function savePromptFile(path: string, content: string): Promise<void> {
  await invoke("write_text_file", { path, content });
}
```

**注意**: `read_text_file` / `write_text_file` は Tauri の `fs` プラグインで提供される。`tauri.conf.json` で権限を確認すること。

### 5.10 App.tsx 統合（TASK-8）

#### 変更点

```typescript
// App.tsx — 追加ステート
const [editorOpen, setEditorOpen] = useState(false);

// 左ドロワー [Edit] ボタン（DrawerDepartment.tsx 内）
// → onClick={() => setEditorOpen(true)}

// 全画面 Editor 表示（Settings と同じ方式）
{editorOpen && (
  <OrchestratorEditor
    onClose={() => setEditorOpen(false)}
    initialDepartment={selectedDepartment ?? undefined}
  />
)}
```

Settings 画面と同様に、`editorOpen === true` の場合はメイン画面（3D Avatar + 下部パネル）を非表示し、Editor コンポーネントをフルスクリーンでレンダリングする。

---

## 6. タスク詳細設計

### TASK-2: Rust — DepartmentConfig 型拡張 + Schema 更新

#### 方針
- **Rust 側 `DepartmentConfig` は変更しない**（禁止事項準拠）
- `_schema.json` の更新（`env`, `tags`, `skills`, `instructions`, `review_mode` を extra 許可プロパティとして追加）
- バリデーションヘルパー追加（`validate_department_config_cmd` 内で使用）

#### AC
- [ ] `_schema.json` が `env`（object）、`tags`（string[]）、`skills`（string[]）、`instructions`（string）、`review_mode`（string）を許可
- [ ] `_schema.json` が `constraints`（string[]）を正しく定義
- [ ] `_schema.json` が `capabilities`（string[]）を正しく定義

#### テスト方針
- `department_config.rs` 既存テストが全 PASS
- `_schema.json` 読み込みテスト（JSON 構造検証）

### TASK-3: Rust — Tauri コマンド追加（editor 用）

#### 実装内容
- `list_departments_cmd` — `department_config::list_departments()` をラップ
- `delete_department_cmd` — ファイル削除 + 活動中 Worker チェック
- `validate_department_config_cmd` — 必須フィールド + Schema 検証
- `lib.rs` の `invoke_handler` に登録

#### AC
- [ ] `list_departments` が全部门設定を返す（name 昇順）
- [ ] `delete_department` がファイルを削除し、活動中 Worker がある場合はエラー
- [ ] `validate_department_config` が空 cli を拒否
- [ ] コマンドが `lib.rs` に正しく登録されている

#### テスト方針
- Rust ユニットテスト（`#[tauri::command]` 関数の直接呼び出し）
- 削除時の Worker チェック（`worker_manager` mock）

### TASK-4: TS — OrchestratorEditor コンポーネント設計

#### 実装内容
- `OrchestratorEditor.tsx` — 全画面ルート（本設計書 §5.2 準拠）
- `LanePipeline.tsx` — レーンパイプライン（本設計書 §5.3 準拠）
- `DepartmentDetailPanel.tsx` — 詳細パネルルート（本設計書 §5.4 準拠）

#### AC
- [ ] Editor が全画面で表示される
- [ ] ESC キーで閉じる
- [ ] [Close] ボタンで閉じる
- [ ] マウント時に `list_departments` を読み込む

#### テスト方針
- Vitest + React Testing Library
- マウント時の `list_departments` 呼び出し確認（`invoke` mock）
- ESC キーでの `onClose` 発火確認
- スナップショットテスト（レイアウト構造）

### TASK-5: TS — レーンパイプライン表示

#### 実装内容
- `LanePipeline.tsx` の実装（本設計書 §5.3 準拠）
- ワークフローステージ可視化（Design → Impl → Review → DA → Done）
- 現在地マーカー（●）と完了マーカー（✓）
- 部門クリックで選択
- `[+ Add Department]` ボタン

#### AC
- [ ] 部門が横並びに表示される
- [ ] ステージが横線で接続される
- [ ] クリックで選択状態が変化
- [ ] `[+ Add Department]` で新規部門追加フローが開始

#### テスト方針
- Vitest: 部門データからのレーンレンダリング確認
- クリックイベントの `onSelectDept` 発火確認
- 空の場合の表示確認

### TASK-6: TS — 詳細パネル（5タブ）

#### 実装内容
- `GeneralTab.tsx`（本設計書 §5.5）
- `WorkflowTab.tsx`（本設計書 §5.6）
- `ScheduleTab.tsx`（本設計書 §5.7）
- `SkillsTab.tsx`（本設計書 §5.8）
- `PromptsTab.tsx`（本設計書 §5.9）

#### AC
- [ ] 5 タブが切替可能
- [ ] General: 全フィールドが編集可能
- [ ] Workflow: quality_gate トグル + パイプラインプレビュー
- [ ] Schedule: タスク追加/削除/トグル
- [ ] Skills: スキル追加/削除
- [ ] Prompts: ファイルパス設定 + プレビュー

#### テスト方針
- Vitest: 各タブのレンダリング + フィールド変更イベント
- `onChange` コールバックの呼び出し確認（変更値の検証）
- タブ切替の表示/非表示確認

### TASK-7: TS — Department CRUD（追加・編集・削除）

#### 実装内容
- `OrchestratorEditor.tsx` 内の `handleAddDepartment`（本設計書 §5.2 準拠）
- `LanePipeline.tsx` 内の `[×]` 削除ボタン
- `DepartmentDetailPanel.tsx` 内の `[Save]` ボタン
- バリデーションエラー表示

#### AC
- [ ] `[+ Add Department]` → 名前入力 → デフォルトテンプレート生成 → 詳細パネルで編集
- [ ] `[Save]` で `~/.oribis/departments/{name}.json` に書き出し
- [ ] バリデーションエラー時はフィールド横にエラーメッセージ
- [ ] `[×]` 削除 → 確認ダイアログ → ファイル削除
- [ ] 活動中 Worker がある部門は削除不可（Rust 側で拒否）

#### テスト方針
- Vitest: Save ボタンクリックでの `update_department_config` 呼び出し確認
- 削除確認ダイアログのモック（`window.confirm` mock）
- バリデーションエラー時の UI 表示確認

### TASK-8: TS — App.tsx 統合（[Edit] ボタン + 全画面切替）

#### 実装内容
- `App.tsx` に `editorOpen` ステート追加
- `DrawerDepartment.tsx` に `[Edit]` ボタン追加
- Settings と同じ全画面切替方式（メイン画面非表示）

#### AC
- [ ] 左ドロワーの `[Edit]` ボタンで Editor 起動
- [ ] Editor 表示中はメイン画面（3D Avatar + PTY パネル）が非表示
- [ ] ESC または [Close] でメイン画面に復帰
- [ ] PTY プロセスは Editor 表示中も継続

#### テスト方針
- Vitest: `[Edit]` ボタンクリックで `OrchestratorEditor` がレンダリングされることを確認
- `[Close]` クリックでメイン画面に復帰

### TASK-9: テスト（Rust + TS + E2E）

#### Rust テスト
- `department_config.rs` 既存テスト全 PASS（`cargo test`）
- `delete_department_cmd` ユニットテスト（正常系 + 活動中 Worker 拒否）
- `validate_department_config_cmd` テスト（空 cli 拒否 + 正常系）

#### TypeScript テスト
- `OrchestratorEditor.test.tsx` — マウント/読み込み/ESC/クローズ
- `LanePipeline.test.tsx` — レーン表示/クリック
- `DepartmentDetailPanel.test.tsx` — タブ切替
- `GeneralTab.test.tsx` — フィールド編集
- `ScheduleTab.test.tsx` — タスク追加/削除

#### E2E テスト
- 手動確認シナリオ（`./start.sh --cpu`）:
  1. アプリ起動
  2. `[Edit]` クリック → Editor 表示
  3. `[+ Add Department]` → 名前入力 → 作成
  4. General タブで model/cli 編集
  5. `[Save]` クリック
  6. `~/.oribis/departments/{name}.json` を確認（内容が保存されている）
  7. `[×]` で削除 → 確認
  8. ファイルが削除されていることを確認

---

## 7. テスト自動化方針

### 7.1 自動化必須テスト

| 種別 | テスト内容 | 自動化方法 |
|------|-----------|-----------|
| Rust | `delete_department_cmd` | `#[test]` ユニットテスト（tempdir + mock worker） |
| Rust | `validate_department_config_cmd` | `#[test]` ユニットテスト |
| Rust | `department_config.rs` 既存テスト | `cargo test`（回帰テスト） |
| TS | Editor マウント + 読み込み | Vitest + `@testing-library/react` + `invoke` mock |
| TS | レーンパイプライン表示 | Vitest + スナップショット/イベント検証 |
| TS | 5タブ切替 + フィールド編集 | Vitest + ユーザイベントシミュレーション |
| TS | CRUD 操作（Save/Delete） | Vitest + `invoke` mock + コールバック検証 |
| TS | App.tsx 統合（全画面切替） | Vitest + 条件付きレンダリング検証 |

### 7.2 手動確認項目（E2E）

以下は `./start.sh --cpu` 起動後の手動確認（自動化困難な UI 統合部分）:

1. **Editor 全画面表示**: 3D Avatar/PTY パネルが非表示になり、Editor が画面全体を占める
2. **PTY 継続確認**: Editor 表示中に Worker PTY が継続している（`ps` コマンド等で確認）
3. **ESC 復帰**: ESC キーでメイン画面に戻り、PTY パネルの内容が維持されている
4. **実ファイル書き込み**: Save 後に `cat ~/.oribis/departments/{name}.json` で内容確認

---

## 8. リスク・注意事項

### 8.1 既存コード影響リスク

| リスク | 対策 |
|--------|------|
| `types.ts` の `DepartmentConfig` 変更が P1 コードに影響 | `name` プロパティは維持。`DrawerDepartment.tsx` は `name` のみ使用 → 影響なし |
| `App.tsx` の `departments` ステート型変更 | 初期値 `[]` は維持。フィールドアクセス箇所を確認後修正 |
| `department_config.rs` API 変更 | **変更禁止**。`extra` フィールドを活用 |

### 8.2 技術的制約

| 制約 | 対応 |
|------|------|
| `extra` フィールドの型安全性 | TS 側で `DepartmentExtra` インターフェースを定義し、ヘルパー関数で型安全にアクセス |
| スキルファイル読み込み | Tauri `fs` プラグイン権限要確認。`tauri.conf.json` に `~/.oribis/roles/**` 読み取り権限を追加必要あり |
| プロンプトファイル編集 | 同上。書き込み権限も必要 |
| JSON Schema バリデーション | P2 では必須フィールドチェックのみ。完全な Schema 検証は `_schema.json` 整備後に拡張 |

### 8.3 パフォーマンス要件

| 要件 | 設計上の対応 |
|------|-------------|
| レーンパイプライン表示 < 100ms | `list_departments` はファイル読み込み（通常 < 10件）→ 即座に完了 |
| Department 切替 < 50ms | React ステート更新のみ（ファイル読み込みなし）→ 即座 |
| Editor 表示中の PTY 継続 | Editor は React コンポーネント切替のみ。PTY プロセスは維持 |

---

## 9. 設計書追跡・更新履歴

| 日付 | 更新者 | 内容 |
|------|--------|------|
| 2026-05-10 | planner | 初版作成。型定義、API契約、コンポーネント構成、タスク詳細設計を定義 |

---

## 付録 A: 既存 P1 資産の詳細

### A.1 `department_config.rs`（P1 実装済み）

- `DepartmentConfig` 構造体（`name`, `cli`, `model`, `working_dir`, `max_workers`, `mode`, `constraints`, `capabilities`, `narration`, `quality_gate`, `schedule`, `extra`）
- `NarrationConfig`, `QualityGateConfig`, `ScheduleConfig`
- `list_departments_in()`, `get_department_in()`, `update_department_in()` — ファイル I/O + バリデーション
- `validate_name()` — パストラバーサル防止
- 公開ラッパー: `list_departments()`, `get_department()`, `update_department()`
- テスト: 14 ケース（空ディレクトリ、ソート、ラウンドトリップ、serde、extra フィールド保持等）

### A.2 `src/plugin/types.ts`（P1 実装済み）

- `WorkerInfo`, `DepartmentConfig`, `EventFeedItem`, `SpeechQueueItem`, `NarrationCursor`
- `DepartmentConfig` は P1 時点で Rust 側と非整合（`constraints: Record`, `narration: boolean` 等）
- P2 で統合修正（本設計書 §2.3 準拠）

### A.3 `src-tauri/src/lib.rs`（P1 実装済み）

- `invoke_handler` に P1 コマンド登録済み
- `department_config`, `worker_manager`, `event_feed`, `narration` モジュール登録済み
- P2 コマンド追加位置: `invoke_handler` のコマンドリストに追記

### A.4 `src/App.tsx`（P1 実装済み）

- 二重タブ再編 + 下部 PTY パネル統合済み
- `departments` ステート（`DepartmentConfig[]`）定義済み（L666 付近）
- Settings 画面との全画面切替方式が実装済み → 同方式で Editor 切替を実装
