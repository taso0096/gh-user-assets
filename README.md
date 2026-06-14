# gh-user-assets

GitHub の issue / PR に画像をアップロード・ダウンロードできる [gh](https://cli.github.com/) 拡張機能。

GitHub の公式 REST API には issue / PR への画像アップロードエンドポイントが存在せず、Web UI の添付機能はブラウザセッション（Cookie）認証を必要とする。
そのため [`@playwright/cli`](https://www.npmjs.com/package/@playwright/cli)（`playwright-cli` コマンド）でブラウザを操作してアップロード／ダウンロードを実現する、薄いシェルラッパーとして実装している。

---

## 必要なもの

- [`gh`](https://cli.github.com/)（認証済み）
- [`@playwright/cli`](https://www.npmjs.com/package/@playwright/cli)

```bash
npm install -g @playwright/cli@latest
playwright-cli --version
```

`playwright-cli` コマンドが見つからない場合はエラーで終了する。

---

## インストール

```bash
gh extension install taso0096/gh-user-assets
```

ローカルで開発する場合:

```bash
gh extension install .
```

### スキル

[`npx skills`](https://www.npmjs.com/package/skills) 対応のスキルも同梱している。

```bash
npx skills add taso0096/gh-user-assets
```

---

## ログイン

ブラウザのセッション（Cookie）を永続プロファイルに保存して使い回す。
upload / download を実行する前に、一度 `login` でログインしておく。

```bash
# headed ブラウザが開くので GitHub にログインする（初回のみ）
gh user-assets login
```

ログイン後はブラウザを閉じてよい。セッションは永続プロファイルに残るため、次回以降の upload / download で再利用される。
SSO / SAML 環境では "remember this device" を選んでおくとセッションが維持される。

---

## 使い方

issue / PR の指定は `gh api` と同様に `--repo` と `--issue` / `--pr` を**必ず明示**する（省略不可）。

### アップロード

画像ファイルを issue / PR に添付し、生成されたアセット URL を標準出力に出す（コメントの投稿はしない）。
複数ファイルをまとめて指定できる。

```bash
gh user-assets upload <file> [<file>...] --repo <owner/repo> (--issue <n> | --pr <n>)
```

```bash
# 1 ファイル
gh user-assets upload ./screenshot.png --repo owner/repo --issue 123

# 複数ファイル
gh user-assets upload a.png b.gif --repo owner/repo --pr 456
```

> **注意:** アップロードはアセット URL を確実に検知するため、対象 issue / PR のコメント textarea を空にしてから処理する。
> このとき GitHub がブラウザに保存していた**未投稿のコメント下書きは破棄される**（仕様）。書きかけの下書きがある issue / PR では実行しないこと。

出力例:

```
https://github.com/user-attachments/assets/xxxxxxxx-....
https://github.com/user-attachments/assets/yyyyyyyy-....
```

### ダウンロード

2 つのモードがある。

**全件モード** — issue / PR の本文・コメントに含まれる画像をすべて取得する:

```bash
gh user-assets download --repo <owner/repo> (--issue <n> | --pr <n>) [--output <dir>]
```

```bash
gh user-assets download --repo owner/repo --issue 123
gh user-assets download --repo owner/repo --pr 456 --output ./images
```

**URL 指定モード** — 指定したアセット URL だけを取得する。
URL は `gh` で取得した body から抜き出したものを渡す:

```bash
gh user-assets download <url> [<url>...] [--output <dir>]
```

```bash
# gh で body を取得し、URL を抜き出して渡す例
gh user-assets download \
  $(gh api repos/owner/repo/issues/123 --jq '.body' \
    | grep -oE 'https://github\.com/user-attachments/assets/[a-f0-9-]+')
```

### オプション

| オプション | 説明 |
|------|------|
| `--repo <owner/repo>` | 対象リポジトリ（upload / 全件 download で必須） |
| `--issue <n>` | 対象の issue 番号 |
| `--pr <n>` | 対象の PR 番号 |
| `--session <name>` | `playwright-cli` のセッション名（デフォルト: `gh-user-assets`） |
| `--output <dir>` | （download）出力先ディレクトリ（デフォルト: カレント） |

---

## 実装の概要

Node.js スクリプトや追加ライブラリは使わず、`playwright-cli` のサブコマンドを組み合わせた bash スクリプトのみで構成している。

```
gh-user-assets        # エントリポイント。サブコマンドのルーティング
lib/
├── common.sh         # 共通ヘルパー（引数パース・pw_cli ビルド・ページ待機・login）
├── upload.sh         # upload サブコマンド
└── download.sh       # download サブコマンド
```

### セッション管理（login）

`playwright-cli --session <name> open --persistent <url>` を使い、永続プロファイルに保存された Cookie を再利用する。

- `login`: `--headed` でログインページを開き、ユーザーが手動でログインする

upload / download はページを開いた後に現在の URL をポーリングし、ナビゲーションが落ち着くまで待機する。
ログインページにリダイレクトされたままなら未ログインと判断し、`gh user-assets login` を促して終了する。

### upload の流れ

1. issue / PR の URL を永続プロファイルで開く
2. `snapshot` で「Paste, drop, or click to add files」ボタンの ref を取得し `click`
3. `upload <file>...` でファイルを添付
4. コメント textarea（`textarea[name="comment[body]"]`）の値を `--raw eval` で読み取り、`user-attachments/assets/...` の URL 数が増えるまでポーリングして完了を検知
5. 新しく挿入されたアセット URL を標準出力に出力する（コメントの投稿はしない）

### download の流れ

1. URL の収集
   - 全件モード: `gh api` で本文・コメントを取得し、Markdown から `user-attachments/assets/...` の URL を抽出
     - issue: 本文（`issues/{n}`）と会話コメント（`issues/{n}/comments`）
     - PR: 上記に加えて差分行のレビューコメント（`pulls/{n}/comments`）とレビュー本文（`pulls/{n}/reviews`）
   - URL 指定モード: 引数で渡された URL をそのまま使う
2. 認証済みセッションで各 URL に `goto`（GitHub が S3 署名付き URL へ 302 リダイレクト）
3. 画像は static リソース扱いのため `requests --static` で一覧を取得し、`[200]` のレスポンスのインデックスを特定
4. `response-body <index>` でバイナリをファイルに保存（`playwright-cli` が content-type から拡張子付きのファイルとして書き出す）
5. `--output` で指定したディレクトリに移動

### 補足

- `eval` には必ず `--raw` を付け、`### Result` などのマークダウン装飾なしで値だけを取得する。
- アップロード可能な形式: PNG / JPG / GIF / WebP
- GitHub の DOM 構造変更により snapshot のセレクタが壊れるリスクがある。
