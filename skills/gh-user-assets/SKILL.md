---
name: gh-user-assets
description: >
  gh-user-assets CLI（gh extension）を使って GitHub の issue / PR に画像をアップロード・ダウンロードするスキル。
  ユーザーが「issue に画像を添付したい」「PR のスクリーンショットをアップロードしたい」「issue の画像をダウンロードしたい」
  「gh user-assets を使いたい」と言ったときは必ずこのスキルを参照すること。
  画像の添付・取得に関わる作業が発生した時点でこのスキルを参照すること。
---

# gh-user-assets スキル

`gh user-assets` コマンドで GitHub issue / PR への画像アップロード・ダウンロードを行う。
内部では `playwright-cli` でブラウザを操作するため、事前に **login** でセッションを確立しておく必要がある。

---

## 前提条件

- `gh` CLI がインストール済み・認証済みであること
- `@playwright/cli` がインストール済みであること

```bash
npm install -g @playwright/cli@latest
```

- 拡張機能がインストール済みであること

```bash
gh extension install taso0096/gh-user-assets
```

---

## コマンド一覧

### login（初回のみ）

```bash
gh user-assets login [--session <name>]
```

headed ブラウザが開くので GitHub にログインする。セッションは永続プロファイルに保存され、以後の upload / download で再利用される。

### upload

```bash
gh user-assets upload <file> [<file>...] --repo <owner/repo> (--issue <n> | --pr <n>) [--session <name>]
```

画像ファイルを issue / PR に添付し、生成されたアセット URL を標準出力に出す（コメント投稿はしない）。

出力形式（タブ区切り）:

```
<ローカルパス>\t<アセット URL>
```

> **注意:** アップロード前にコメント textarea を空にするため、**書きかけの未投稿コメントは破棄される**。

対応形式: PNG / JPG / GIF / WebP

### download

```bash
# issue / PR の全画像をダウンロード
gh user-assets download --repo <owner/repo> (--issue <n> | --pr <n>) [--output <dir>]

# アセット URL を直接指定してダウンロード
gh user-assets download <url> [<url>...] [--output <dir>]
```

---

## オプション早見表

| オプション | 説明 |
|---|---|
| `--repo <owner/repo>` | 対象リポジトリ（upload / issue-PR download で必須） |
| `--issue <n>` | 対象の issue 番号 |
| `--pr <n>` | 対象の PR 番号 |
| `--session <name>` | playwright-cli のセッション名（デフォルト: `gh-user-assets`） |
| `--output <dir>` | download の出力先ディレクトリ（デフォルト: カレント） |

---

## 典型的な手順

### issue に画像をアップロードする

```bash
# 初回のみ: ログイン
gh user-assets login

# アップロード（URL が標準出力に出る）
gh user-assets upload ./screenshot.png --repo owner/repo --issue 123
```

### PR の全画像をダウンロードする

```bash
gh user-assets download --repo owner/repo --pr 456 --output ./images
```

### body から URL を抽出してダウンロードする

```bash
gh user-assets download \
  $(gh api --method GET repos/owner/repo/issues/123 --jq '.body' \
    | grep -oE 'https://github\.com/user-attachments/assets/[a-f0-9-]+')
```

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `playwright-cli not found` | `npm install -g @playwright/cli@latest` を実行する |
| `not logged in` | `gh user-assets login` でログインし直す |
| `could not find the file-attach button` | GitHub の DOM が変更された可能性。拡張機能を最新版に更新する |
| アップロードが失敗する | ファイルサイズ・形式を確認（対応: PNG / JPG / GIF / WebP） |
| SSO 環境でセッションが切れる | login 時に「remember this device」を選択する |
