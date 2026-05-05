# theme-system.md — Oribis テーマシステム仕様

最終更新: 2026-05-04（初版）

---

## 概要

oribis デスクトップアプリの UI 全体を CSS Custom Properties（`--c-*`）で統一管理するテーマシステム。
`data-theme` 属性で切り替え可能な 12 テーマプリセットを提供する。

---

## アーキテクチャ

### CSS 変数体系（`--c-*` prefix）

`:root` に約 48 個の CSS Custom Properties を定義。全 UI 要素がこれらの変数を参照する。

| カテゴリ | 変数例 | 用途 |
|---------|--------|------|
| Accent | `--c-accent`, `--c-accent-bright`, `--c-accent-dim` | アクセントカラー |
| Background | `--c-bg-base`, `--c-bg-surface`, `--c-bg-raised`, `--c-bg-overlay` ... | 背景レイヤー（deepest → panel） |
| Border | `--c-border`, `--c-border-mid`, `--c-border-dim`, `--c-border-accent` ... | 境界線 |
| Text | `--c-text-primary`, `--c-text-secondary`, `--c-text-light`, `--c-text-dim` ... | テキスト色階層 |
| Danger | `--c-danger`, `--c-danger-bg` | エラー・警告 |
| Slider | `--c-slider-track`, `--c-slider-thumb` | スライダーコントロール |
| Separator | `--c-separator`, `--c-separator-mid` | セクション区切り |
| Bubble | `--c-bubble-user-bg`, `--c-bubble-ai-bg` ... | チャットバブル |
| v2 overlay | `--c-v2-msg-ai-bg`, `--c-v2-msg-user-bg`, `--c-v2-input-bg` | 3D 上の半透明チャット |
| Interaction | `--c-hover-overlay`, `--c-active-overlay` | ホバー/アクティブ状態 |

### テーマ切り替え機構

```
<main class="app-root" data-theme="dark-navy">
  ↓ CSS specificity
:root { --c-bg-base: #0d1520; }                 ← デフォルト値
.app-root[data-theme="midnight"] { --c-bg-base: #08081a; }  ← テーマ上書き
```

- React state: `appTheme` (localStorage key: `oribis_theme`)
- 旧キー `oribis_dock_theme` からの自動マイグレーション対応

### テーマセレクター

Settings > General > Appearance セクションに `<select>` で配置。

---

## テーマプリセット一覧

### ダーク系（8 テーマ）

| テーマ名 | data-theme 値 | ベース背景 | アクセント | 概要 |
|---------|---------------|-----------|-----------|------|
| Dark Navy | `dark-navy` | `#0d1520` | `#4fc3f7` (cyan) | デフォルト。元祖 Deep Ocean Blue |
| Dark Charcoal | `dark-charcoal` | `#1a1a1a` | `#6cb6ff` (blue) | ニュートラルグレー |
| Midnight | `midnight` | `#08081a` | `#aa88ff` (purple) | 深紫 |
| Deep Blue | `deep-blue` | `#0a1225` | `#5b9cff` (blue) | 濃紺 |
| Forest | `forest` | `#0a1810` | `#50c878` (green) | ダーク緑 |
| Rosewood | `rosewood` | `#180a0e` | `#e06070` (red) | ダーク赤 |
| Amber | `amber` | `#18120a` | `#e8a040` (orange) | ダークオレンジ |
| Light | `light` | `#f0f0f4` | `#2266bb` (blue) | ライトグレー |

### ビビッド系（4 テーマ、明るい背景・黒テキスト）

| テーマ名 | data-theme 値 | ベース背景 | アクセント | 概要 |
|---------|---------------|-----------|-----------|------|
| Emerald | `emerald` | `#7dcc9e` | `#059669` | 鮮やかな緑 |
| Tangerine | `tangerine` | `#dca070` | `#d45a00` | 鮮やかなオレンジ |
| Ocean | `ocean` | `#6c9cd4` | `#2563eb` | 鮮やかな青 |
| Sunflower | `sunflower` | `#dcbe60` | `#ca8a04` | 鮮やかな黄 |

---

## 実装ファイル

| ファイル | 変更内容 |
|---------|---------|
| `src/App.css` | `:root` に 48 変数定義。12 テーマの `.app-root[data-theme="xxx"]` ブロック。旧 `--dock-*` 変数を `--c-*` に統合 |
| `src/App.tsx` | `appTheme` state + `data-theme` 属性。テーマセレクター UI。インラインスタイルの `--c-*` 変数化（~80 箇所） |

### ハードコード色の扱い

以下はテーマ変数化**しない**（セマンティックカラー）:
- コンソールログレベル色（error=赤, warn=黄, info=青）
- affinity ティア色（5段階の固定カラー）
- ステータスインジケータ色

---

## セッションログ（2026-05-04）

1. `--dock-*` 変数体系を `--c-*` に統合（自己参照バグ 7 件修正）
2. App.tsx インラインスタイルのハードコード色を `var(--c-*)` に置換（~80 箇所）
3. v2 チャットバブル用 `--c-v2-msg-*` 変数追加
4. `--c-hover-overlay` / `--c-active-overlay` 追加
5. 左サイドバーを `backdrop-filter: blur(12px)` + `--c-bg-overlay` に変更（右パネルとの統一）
6. セクションヘッダー・Prompt タブ項目の色を `--c-text-light` に修正
7. 12 テーマプリセット追加
