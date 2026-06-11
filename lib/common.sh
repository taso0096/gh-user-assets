# gh-user-assets の共通ヘルパー。エントリポイントから source される。
# 対応するのは github.com のみ。GitHub Enterprise は対象外。

# GitHub の user-attachment アセット URL のパス部分（スキーム/ホストを除く）にマッチする。
GHUA_ASSET_RE='user-attachments/assets/[a-f0-9-]+'

# デフォルト値。parse_common_args で上書きされる。
session_name="gh-user-assets"
repo=""
issue=""
pr=""

# playwright-cli の呼び出しコマンドを組み立てる。playwright-cli が PATH 上にある必要がある。
pw_cli=()
build_pw_cli() {
  if ! command -v playwright-cli >/dev/null 2>&1; then
    echo "playwright-cli not found. install it with 'npm install -g @playwright/cli@latest'." >&2
    exit 1
  fi
  # Pin the output dir for artifacts (snapshots, response bodies, etc.).
  # Without this, playwright-cli creates a .playwright-cli dir under the
  # current working directory. Override with GHUA_OUTPUT_DIR if needed.
  export PLAYWRIGHT_MCP_OUTPUT_DIR="${GHUA_OUTPUT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gh-user-assets}"
  mkdir -p "$PLAYWRIGHT_MCP_OUTPUT_DIR"
  pw_cli=(playwright-cli)
  [[ -n "$session_name" ]] && pw_cli+=(--session "$session_name")
}

# オプションに値が指定されていなければエラー終了する。require_value "$@" の形で
# 各オプションの case 分岐内から呼ぶ（$1 がフラグ、$2 がその値になる）。
require_value() {
  if [[ $# -lt 2 ]]; then
    echo "$1 requires a value" >&2
    exit 1
  fi
}

# 全サブコマンド共通のオプションをパースする。位置引数は REMAINING_ARGS に残す。
REMAINING_ARGS=()
parse_common_args() {
  REMAINING_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue) require_value "$@"; issue="$2"; shift 2 ;;
      --pr) require_value "$@"; pr="$2"; shift 2 ;;
      --repo) require_value "$@"; repo="$2"; shift 2 ;;
      --session) require_value "$@"; session_name="$2"; shift 2 ;;
      --output) require_value "$@"; output_dir="$2"; shift 2 ;;
      --) shift; REMAINING_ARGS+=("$@"); break ;;
      -*) echo "unknown option: $1" >&2; exit 1 ;;
      *) REMAINING_ARGS+=("$1"); shift ;;
    esac
  done
}

# --repo を必須にする（カレントリポジトリへのフォールバックはしない: gh api と同様、対象を明示させる）。
require_repo() {
  if [[ -z "$repo" ]]; then
    echo "--repo <owner/repo> is required" >&2
    exit 1
  fi
}

# issue/PR の URL を組み立てる。--issue / --pr のどちらか一方が必須。
target_number=""
target_kind=""
target_url=""
build_target_url() {
  if [[ -n "$issue" && -n "$pr" ]]; then
    echo "specify only one of --issue or --pr" >&2
    exit 1
  fi
  if [[ -n "$issue" ]]; then
    target_kind="issues"; target_number="$issue"
  elif [[ -n "$pr" ]]; then
    target_kind="pull"; target_number="$pr"
  else
    echo "specify --issue <n> or --pr <n>" >&2
    exit 1
  fi
  target_url="https://github.com/${repo}/${target_kind}/${target_number}"
}

# 現在のページが GitHub にログイン済みのセッションを示していれば 0 を返す。
# GitHub は認証済みのときだけ <meta name="user-login"> を埋め込む。未認証の
# セッションではこの meta タグなしでサインインページ（アセット URL の場合は 404）が
# 表示されるため、URL やリダイレクトでの判定は信頼できない。
_is_logged_in() {
  [[ "$("${pw_cli[@]}" --raw eval "() => !!document.querySelector('meta[name=\"user-login\"]')" 2>/dev/null)" == "true" ]]
}

# GitHub のトップページを開いて認証済みかどうかを確認し、ログイン状態を保証する。
# 未ログインならヒントを表示して終了する。
ensure_logged_in() {
  "${pw_cli[@]}" open --persistent "https://github.com" >/dev/null 2>&1 || true

  local max_wait=30 waited=0
  while :; do
    _is_logged_in && return 0
    [[ $waited -ge $max_wait ]] && break
    sleep 2; waited=$((waited + 2))
  done

  echo "not logged in. run 'gh user-assets login' first." >&2
  pw_stop
  exit 1
}

# 指定 URL へ遷移し、ナビゲーションが落ち着くまで待機する。
# タイムアウト内に落ち着かなければ非ゼロを返す。
goto_and_wait() {
  local url="$1"
  "${pw_cli[@]}" goto "$url" >/dev/null 2>&1 || true
  local max_wait=30 waited=0 current_url=""
  while [[ $waited -lt $max_wait ]]; do
    sleep 1; waited=$((waited + 1))
    current_url=$("${pw_cli[@]}" --raw eval "() => window.location.href" 2>/dev/null || echo "")
    [[ -n "$current_url" && "$current_url" != "about:blank" ]] && return 0
  done
  return 1
}

# login: 手動サインイン用に、ログインページを headed ブラウザで開く。
ghua_login() {
  parse_common_args "$@"
  build_pw_cli
  echo "opening browser to log in to github.com..." >&2
  echo "after logging in, you can close this browser. then run upload/download." >&2
  "${pw_cli[@]}" open --persistent --headed "https://github.com/login"
}

# この実行で開いたブラウザを閉じる。ログイン状態は永続プロファイルに残るため、
# 次回の実行では再ログインせずに再利用できる。
pw_stop() {
  "${pw_cli[@]}" close >/dev/null 2>&1 || true
}
