# 環境分離構想: AI駆動PC + 人間操作PC

**作成日**: 2026-05-21
**ステータス**: 構想段階（未実施）

## 背景

現状、1台のPC（Windows + WSL2）でAI駆動開発（Claude Code常駐・ECC自走）と人間操作（クリエイティブ作業・Unity等）が同居。リソース競合・用途混在の課題あり。2台目PC（GPU搭載）を活用し、役割分離を検討。

## 構成案

### 現行PC → AI駆動専用機

| 項目 | 内容 |
|------|------|
| OS | Windows + WSL2 Linux |
| 主用途 | AI駆動開発（Claude Code常駐・ECC自走・CI） |
| 常駐プロセス | tmux + Claude Code（SysDev/AFD Worker）、Discord Relay |
| GPU用途 | Oribis実行（Tauri + Three.js）、ローカルLLM（将来） |
| 人間操作頻度 | 低（設定変更・緊急対応時のみ） |
| Unity | Windows側でビルド確認可能（Editor利用可） |

### 別PC → 人間操作メイン

| 項目 | 内容 |
|------|------|
| OS | Windows |
| 主用途 | クリエイティブ作業（DAW・画像編集・動画編集） |
| GPU用途 | ゲームプレイ、クリエイティブツール |
| 開発 | 必要時のみ（SourceTree確認・手動テスト等） |
| Oribis | 必要に応じてインストール可 |

## 検討事項

### Unity問題
- AI専用機をLinux化するとUnity Editor使用不可
- 現行構成（Windows + WSL2）を維持すれば問題なし
- AFD開発にUnity必須のため、AI専用機にもWindows環境を残す

### Oribis実行場所
- AI専用機に常駐推奨（開発→実行のサイクルが最短）
- 人間操作PC側にも配置可能（GPU有、デュアル運用）
- 常駐はAI専用機、人間操作PCは任意

### プロジェクト開発の所在
- Oribis開発: AI専用機（Claude Code自走）
- Horror開発: AI専用機（同上）
- AFD開発: AI専用機（Unity Editor含む）
- 全プロジェクトのソースはAI専用機に集約

### データ同期
- git経由でソースコード同期（既存フロー）
- 人間操作PCからSourceTree等で確認可能
- 大容量アセット（3Dモデル・音声等）は別途同期検討

## 結論（Producer判断待ち）

「人間操作用を別PCに移す」方向で概ね合意。具体的な移行手順・タイミングは未定。
