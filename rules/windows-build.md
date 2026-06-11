# Oribis Windowsネイティブ最小動作線定義

## 目的
Windows環境でOribisが最低限動作する条件を定義する。
これは「すべての機能が動く」ではなく、「アプリが起動し主要機能が使用可能」という最小基準。

## 最小動作線（MVP: Minimum Viable Product）

### Phase 1: 起動確認（クリティカル）
- [ ] Windowsインストーラー（.msi）またはポータブル（.exe）が実行可能
- [ ] アプリがエラーなく起動
- [ ] ローディング画面（loader.html）が表示される
- [ ] メインウィンドウが表示される
- [ ] WebView2が正常にレンダリングされる

### Phase 2: 基本UI操作（クリティカル）
- [ ] チャット画面が表示される
- [ ] メッセージ入力・送信が可能
- [ ] 設定画面が開く
- [ ] プロジェクトタブが表示される

### Phase 3: バックエンド連携（重要）
- [ ] Rustコマンド呼び出しが通る（invoke）
- [ ] SQLite DB読み書きが可能
- [ ] プロジェクトデータの読み込み・保存
- [ ] 設定ファイルの読み書き

### Phase 4: 外部連携（重要）
- [ ] LLM連携（Claude等）が動作
- [ ] PTYターミナルが起動（ConPTY使用）
- [ ] ファイルパスが正しく解決される

### Phase 5: 高度機能（オプション）
- [ ] TTS音声再生
- [ ] 音声認識（マイク入力）
- [ ] 3Dアバター表示（VRM）
- [ ] MCP Broker連携（TCPモード）

## Windows固有の制約事項

### 機能制限（当面）
1. **MCP Broker**: Unix Domain Socket非対応 → TCP localhostモードに切り替え
2. **Discord連携**: 削除済み
3. **一部CLIツール**: Windows版が必要（claude.exe, codex.exe等）

### 既知の問題
1. パス区切り文字（`/` vs `\`）
2. 大文字小文字の区別（Windowsは非区別）
3. 長パス（260文字制限）
4. ファイルロック挙動の違い

## 確認手順

### 1. クリーンインストールテスト
```powershell
# 1. インストーラー実行
.\Oribis_0.1.0_x64-setup.exe

# 2. 初回起動確認
# - ローディング画面表示（5秒以内）
# - メインウィンドウ表示（10秒以内）
```

### 2. 基本操作テスト
```powershell
# 1. チャット操作
# - メッセージ入力: "Hello"
# - 送信ボタンクリック
# - 応答表示確認（30秒以内）

# 2. 設定操作
# - Settingsアイコンクリック
# - 各タブの表示確認
```

### 3. ログ確認
```powershell
# ログファイル確認
Get-Content ~\AppData\Roaming\com.oribis.app\logs\oribis.log -Tail 50
```

## 判断基準

### ✅ GO（リリース可能）
- Phase 1-3がすべてPASS
- 重大なクラッシュがない
- 基本操作が可能

### ⚠️ CONDITIONAL（条件付きリリース）
- Phase 1-2がPASS
- Phase 3で一部制限あり（設定保存のみ等）
- ワークアラウンドがある

### ❌ NO-GO（リリース不可）
- Phase 1で失敗（起動しない）
- 重大なデータ破損リスク
- セキュリティ問題

## ★★★ Windowsビルドワークフロー規則（2026-06-12）★★★

### ソース修正の絶対ルール
- **ソースコード修正は WSL 側（`/home/mnadmin/agent-projects/sysdev/sysdev-1/oribis/`）のみ**
- Windows クローン（`C:\Users\admin\agent-projects\sysdev\sysdev-1\oribis\`）への直接修正・手動ファイル配置は絶対禁止
- WSL 側で修正 → GitHub にプッシュ → `build-windows.sh` でビルド、という一方向フローのみ

### ビルド手順
```bash
# WSL 側から実行（ブランチ指定、省略時は develop）
bash build/build-windows.sh [branch_name]
```

このスクリプトが以下を自動実行する：
1. plugins/ を Windows クローンに rsync
2. Windows クローンで `git reset --hard origin/<branch>`
3. `pnpm tauri build --no-bundle --target x86_64-pc-windows-msvc`（Vite ビルド含む）
4. `C:\Users\admin\oribis\build\windows\` に exe + resources/ を配置

### 配置物（`C:\Users\admin\oribis\build\windows\`）
```
oribis.exe
resources\
  anima.vrm
  background-1.png
  voicevox-core\
```

### 禁止事項
- Windows クローンへの手動ファイルコピー（ビルドスクリプト外での操作）
- `cargo build` 単体によるビルド（`tauri build` を必ず使う）
- Windows クローンでの直接 `git commit`

## 次のステップ
1. Windows CIビルドの修正確認
2. Windows環境での手動テスト実施
3. 問題箇所の優先順位付け修正
