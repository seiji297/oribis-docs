# WSL2 Tauri v2 ビルド環境セットアップ

## 概要

WSL2 (Ubuntu 24.04) 上で Oribis (Tauri v2 + Rust) の `cargo build` を通すために
必要な GTK スタック開発ライブラリのインストール手順と記録。

## インストールコマンド

```bash
sudo apt-get update
sudo apt-get install -y \
  libwebkit2gtk-4.1-dev \
  libjavascriptcoregtk-4.1-dev \
  libgtk-3-dev \
  libglib2.0-dev \
  libsoup-3.0-dev \
  libcairo2-dev \
  libpango1.0-dev \
  libatk1.0-dev \
  libgdk-pixbuf-2.0-dev \
  librsvg2-dev \
  libayatana-appindicator3-dev \
  patchelf
```

## インストールパッケージ一覧

| パッケージ名 | バージョン（Ubuntu 24.04 apt） | 用途 |
|---|---|---|
| libwebkit2gtk-4.1-dev | 2.50.4-0ubuntu0.24.04.1 | WebKit2GTK 開発ヘッダ（Tauri webview 必須） |
| libjavascriptcoregtk-4.1-dev | 2.50.4-0ubuntu0.24.04.1 | JavaScriptCore ヘッダ（webkit2gtk 依存） |
| libgtk-3-dev | 3.24.x | GTK3 開発ヘッダ |
| libglib2.0-dev | 2.80.x | GLib 開発ヘッダ |
| libsoup-3.0-dev | 3.4.x | libsoup 3.0 開発ヘッダ（Tauri HTTP 層） |
| libcairo2-dev | 1.18.x | Cairo 2D グラフィクス開発ヘッダ |
| libpango1.0-dev | 1.52.x | Pango テキストレンダリング開発ヘッダ |
| libatk1.0-dev | 2.38.x | ATK アクセシビリティ開発ヘッダ |
| libgdk-pixbuf-2.0-dev | 2.42.x | GDK Pixbuf 開発ヘッダ |
| librsvg2-dev | 2.58.x | SVG レンダリング開発ヘッダ |
| libayatana-appindicator3-dev | 0.5.x | システムトレイ開発ヘッダ |
| patchelf | 0.14.x | ELF バイナリ patching（Tauri バンドル用） |

**注:** バージョン列は Ubuntu 24.04 apt リポジトリの標準値。
実際のインストール済みバージョンは `dpkg -l <pkg>` で確認。

## インストール後の確認

```bash
pkg-config --modversion webkit2gtk-4.1   # 期待: 2.x 以上
pkg-config --modversion gdk-3.0          # 期待: 3.x
pkg-config --modversion glib-2.0         # 期待: 2.x
pkg-config --modversion soup-3.0         # 期待: 3.x
```

## cargo build コマンド

```bash
cd /home/mnadmin/claude-projects/sysdev/projects/oribis
cargo build --manifest-path src-tauri/Cargo.toml
```

## cargo test コマンド（純 Rust ロジック層）

```bash
cargo test --manifest-path src-tauri/Cargo.toml --no-default-features
# 期待: 48件 PASS
```

## 自動検証

```bash
bash scripts/verify-wsl-build.sh
# exit 0 = AC-1〜5 全 PASS
```

## 制約事項

- GUI 起動（アプリ実際の動作）は対象外。DISPLAY/WAYLAND 未設定でも `cargo build` は成功する。
- apt 公式リポジトリのみ使用。PPA・手動ビルド禁止。
- `cargo test --no-default-features` 48件 PASS の維持が必須。

## 記録日

2026-04-21
