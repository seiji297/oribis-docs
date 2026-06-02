# WDIOテスト WSLg GPU対応 修正計画

**作成日**: 2026-06-02
**対象**: `oribis/scripts/run-wdio-tests.sh` / `oribis/e2e/wdio/wdio.conf.ts`
**目的**: WSL2 WSLg環境でWDIOテストをGPU駆動で実行できるようにする

---

## 現状の問題

| 問題 | 原因箇所 |
|---|---|
| `DISPLAY=:99` に強制上書きされる | `run-wdio-tests.sh` のXvfb起動処理 |
| GPU compositingが無効 | `export WEBKIT_DISABLE_COMPOSITING_MODE=1` の無条件設定 |
| 結果: WSLg GPU未使用・ソフトウェアレンダリング | 上記2点の複合 |

**環境確認済み**:
- `DISPLAY=:0` (WSLg有効)
- `/dev/dxg` 存在（GPU DirectX利用可能）
- tauri-driver / WebKitWebDriver / Xvfb 全てインストール済み

---

## CodexAdviser推奨案（採用）

最小変更・後方互換性維持のアプローチ。

---

## 修正対象1: `run-wdio-tests.sh`

### 変更箇所A: `SKIP_XVFB=1` 分岐追加

**現状**:
```bash
XVFB_DISPLAY=":99"
# ... Xvfb起動処理 ...
Xvfb "${XVFB_DISPLAY}" -screen 0 1920x1080x24 &
XVFB_PID=$!
# ... DISPLAYを:99に上書き ...
export DISPLAY="${XVFB_DISPLAY}"
```

**修正方針**:
- `SKIP_XVFB=1` のとき Xvfb起動 + `DISPLAY` 上書きをスキップ
- スキップ時に `DISPLAY` 疎通確認（`xdpyinfo`）を実行し、利用不可なら明示エラー
- `SKIP_XVFB` 未指定時は従来フローのまま（後方互換）

### 変更箇所B: `WEBKIT_DISABLE_COMPOSITING_MODE` 条件付き化

**現状**:
```bash
export WEBKIT_DISABLE_COMPOSITING_MODE=1  # 無条件設定
```

**修正方針**:
- `SKIP_XVFB=1`（WSLg使用）時は設定しない
- Xvfb使用時は従来どおり `1` を設定（後方互換）

---

## 修正対象2: `wdio.conf.ts`

### 変更箇所: `WEBKIT_DISABLE_COMPOSITING_MODE` 固定注入削除

**現状**:
```typescript
WEBKIT_DISABLE_COMPOSITING_MODE: '1',  // 固定
```

**修正方針**:
- 固定値を削除、`process.env.WEBKIT_DISABLE_COMPOSITING_MODE` を透過的に渡す
- または環境変数が未設定なら渡さない

**変更しない箇所**:
- `const DISPLAY = process.env.DISPLAY || ':99';` → 既定値は`:99`のまま維持（後方互換）

---

## 使用方法（修正後）

**WSLg GPU駆動**:
```bash
cd ~/agent-projects/sysdev/sysdev-1/oribis
SKIP_XVFB=1 bash scripts/run-wdio-tests.sh
# DISPLAY=:0 は自動使用
```

**従来のXvfb（変更なし）**:
```bash
cd ~/agent-projects/sysdev/sysdev-1/oribis
bash scripts/run-wdio-tests.sh
```

---

## リスク・注意事項

| リスク | 対処 |
|---|---|
| GPU有効化後に描画タイミング系テストがflaky化 | `waitForDisplayed` の待機条件見直し |
| WSLgセッション状態によりDISPLAY=:0が不達 | スクリプトで疎通確認してエラー出力 |
| 他プロセスのウィンドウ干渉 | テスト実行中の他GUI操作を避ける |
| T-W-01〜T-W-05の一部が不安定化 | 初期表示・クリック・フォーカス系シナリオを要確認 |

---

## 退避方法

GPU有効化後にflakyになった場合:
```bash
# compositingを強制無効に戻す
SKIP_XVFB=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 bash scripts/run-wdio-tests.sh
```

---

## ログ追加推奨

デバッグのため以下をスクリプト出力に追加:
- 使用中の `DISPLAY` 値
- Xvfb使用有無
- `WEBKIT_DISABLE_COMPOSITING_MODE` の設定値

---

## 実装対象ファイル

| ファイル | 変更量 |
|---|---|
| `oribis/scripts/run-wdio-tests.sh` | 約20行（`SKIP_XVFB`分岐 + compositing条件付き化） |
| `oribis/e2e/wdio/wdio.conf.ts` | 約3行（compositing固定値削除） |
