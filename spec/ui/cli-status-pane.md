# CLI Status Pane

## Overview

タイトルバーの ⚡ ボタンで開閉する右固定ペイン。
アクティブプロジェクトの CLI 実行状態（idle / thinking / responding / error）とトークン消費・応答時間をリアルタイム表示する。
複数プロジェクト一覧（全体ビュー）にも切り替え可能。

## Requirements

### 機能要件

- FR-1: CLI 実行状態を `idle` / `thinking` / `responding` / `error` の 4 段階で追跡する。
- FR-2: リクエスト開始時（`markRequestStart`）に状態を `thinking` へ遷移し `requestStartedAt` を記録する。
- FR-3: リクエスト完了時（`markRequestEnd`）に `lastResponseMs`・`totalInputTokens`・`totalOutputTokens` を更新し状態を `idle` へ戻す。
- FR-4: エラー発生時（`markError`）に状態を `error` へ遷移し `requestStartedAt` をクリアする。
- FR-5: `thinking` / `responding` 状態で 10 秒間活動がない場合、自動的に `idle` へフォールバックする（ポーリング間隔 2 秒）。
- FR-6: プロジェクト追加時に初期ステータスエントリを自動生成する。プロジェクト名変更は既存エントリに即時反映する。
- FR-7: 詳細ビューでは `thinking` 中に経過時間タイマーを 500ms 間隔でカウントアップ表示する。
- FR-8: 最終活動時刻を相対表示する（5s 以内→"just now"、60s 以内→"Xs ago"、1h 以内→"Xm ago"、それ以上→"Xh ago"）。
- FR-9: トークン数は入力（IN）・出力（OUT）を累積加算し、どちらも 0 の場合は表示しない。
- FR-10: 応答時間（`lastResponseMs`）は直前リクエストの 1 件分のみ表示する（累積なし）。

### 非機能要件

- NFR-1: ペインの開閉アニメーションは Framer Motion の spring（bounce: 0、duration: 0.35s）で実現し、CPU 負荷を最小化する。
- NFR-2: `useCliStatus` は React 状態外参照用に `statusMapRef` を持ち、`setInterval` コールバック内でクロージャ陳腐化を防ぐ。
- NFR-3: ステータスマップは `Record<projectId, ProjectCliStatus>` で管理し、プロジェクト数に比例した O(n) 更新に留める。
- NFR-4: `markRequestStart` / `markRequestEnd` / `markError` はすべて `useCallback` でメモ化し、不要な再レンダリングを抑制する。

### UI要件

- UI-1: ペインは画面右端に固定（幅 240px）し、メインコンテンツには重ならずスライドインする。
- UI-2: タイトルバー右側の ⚡ ボタンでペインを開閉する。ペイン展開中はボタンに `active` クラスを付与する。
- UI-3: ペインヘッダーに「詳細」「全体」の 2 モードボタンと「×」閉じるボタンを配置する。アクティブなモードボタンは `active` スタイルで識別する。
- UI-4: 詳細ビューはアクティブプロジェクトの情報を表示する。未選択時は「プロジェクト未選択」を表示する。
  - プロジェクト名（見出し）
  - 状態インジケーター（8px カラードット + 状態名テキスト）
  - 最終活動時刻（相対表示）
  - 応答時間（直前リクエスト、0ms 以上のときのみ表示）
  - トークン数「IN X,XXX / OUT X,XXX」（累積、0 のとき非表示）
  - 経過タイマー（thinking 中のみ表示）
- UI-5: 全体ビューは全プロジェクトを表形式（プロジェクト名 / 状態 / 最終活動）で列挙する。プロジェクト名は overflow 時に `title` 属性でフルネームをツールチップ表示する。プロジェクト 0 件時は「プロジェクトなし」を表示する。
- UI-6: 状態カラーは以下の通り固定する。
  - idle: `#607090`（グレー）
  - thinking: `#f0c040`（黄）
  - responding: `#4caf50`（緑）
  - error: `#e05050`（赤）

## Design Notes

- **フック分離**: ステータスロジックは `useCliStatus` に集約し、`StatusPane` コンポーネントは表示のみ担当するプレゼンテーション層とした。
- **プロジェクト横断管理**: `cliStatusProjects` は `useMemo` で projects 配列から派生させ、`useCliStatus` に渡す。アクティブプロジェクト ID を別途渡すことで currentStatus を切り出す設計。
- **自動 idle フォールバック**: LLM API タイムアウトやネットワーク切断でリクエスト完了が呼ばれない場合の残留 thinking/responding 状態を 10 秒でリセットする安全策。
- **Framer Motion 採用**: `animate={{ x: isOpen ? 0 : 240 }}` でペイン幅分だけ右方向にオフセットするシンプルな実装。CSS transition では再現困難な spring 物理を利用。
- **ElapsedTimer 分離**: thinking 中の経過時間のみ 500ms ポーリングが必要なため、独立コンポーネント `ElapsedTimer` として分離し、不要な再レンダリング範囲を最小化した。

## Known Issues / Backlog

- [LOW] `responding` 状態は型定義・カラー定義に存在するが、現在 `markRequestStart` 直後は `thinking` 固定で `responding` への遷移ロジックが未実装。ストリーミング応答開始時に `responding` へ切り替える拡張が想定される。
- [LOW] トークン数はセッション内累積のみでリセット機能なし。プロジェクト切替時や会話クリア時に cumulative を初期化する仕組みが未実装。
- [LOW] 全体ビューでプロジェクトをクリックしてそのプロジェクトに切り替えるインタラクションは未実装。
- [LOW] ペイン幅 240px はハードコード。ユーザーによるリサイズ非対応。
