# upload サブコマンド。エントリポイントから（common.sh の後に）source される。

# コメント textarea の値を読み取る。ページには複数の textarea があるため name で絞り込む。
_textarea_value() {
  "${pw_cli[@]}" --raw eval \
    "() => { const t = document.querySelector('textarea[name=\"comment[body]\"]'); return t ? t.value : ''; }" \
    2>/dev/null || echo ""
}

# コメント textarea を空にし、input イベントを発火して GitHub にドラフトをクリアさせる。
_clear_textarea() {
  "${pw_cli[@]}" eval \
    "() => { const t = document.querySelector('textarea[name=\"comment[body]\"]'); if (t) { t.value = ''; t.dispatchEvent(new Event('input', {bubbles: true})); } }" \
    >/dev/null 2>&1 || true
}

# textarea に現在含まれるアセット URL の数を数える。
_asset_count() {
  _textarea_value | grep -oE "$GHUA_ASSET_RE" | wc -l | tr -d ' '
}

# 新しい snapshot から「Paste, drop, or click to add files」ボタンの ref を探す。
# ref は snapshot ごとに振り直されるため、各アップロードの前に呼ぶ。
_find_drop_ref() {
  "${pw_cli[@]}" --raw snapshot 2>/dev/null |
    grep -iE 'button "Paste, drop, or click to add files"' |
    grep -oE '\[ref=[a-zA-Z0-9]+\]' |
    head -1 |
    tr -d '[]' |
    cut -d= -f2
}

# 単一ファイルをアップロードし、そのアセット URL を出力する。失敗時は非ゼロを返す。
_upload_one() {
  local file="$1"
  local before ref
  before=$(_asset_count)

  ref=$(_find_drop_ref)
  if [[ -z "$ref" ]]; then
    echo "could not find the file-attach button" >&2
    return 1
  fi

  "${pw_cli[@]}" click "$ref" >/dev/null 2>&1 || true
  "${pw_cli[@]}" upload "$file" >/dev/null 2>&1 || true

  # アセット URL が textarea に現れるまで待機する。
  local max_wait=120 waited=0 value
  while [[ $waited -lt $max_wait ]]; do
    value=$(_textarea_value)
    if echo "$value" | grep -q '<!-- Failed to upload'; then
      echo "server rejected the upload (size/type limit?)" >&2
      return 1
    fi
    [[ "$(_asset_count)" -gt "$before" ]] && break
    sleep 2
    waited=$((waited + 2))
  done

  local url
  url=$(_textarea_value | grep -oE "https://github\.com/${GHUA_ASSET_RE}" | tail -1)
  [[ -z "$url" ]] && return 1
  echo "$url"
}

ghua_upload() {
  parse_common_args "$@"
  set -- "${REMAINING_ARGS[@]:-}"

  if [[ $# -eq 0 || -z "$1" ]]; then
    echo "no files given" >&2
    exit 1
  fi

  local files=()
  local f abspath
  for f in "$@"; do
    if [[ ! -f "$f" ]]; then
      echo "file not found: $f" >&2
      exit 1
    fi
    abspath=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
    files+=("$abspath")
  done

  require_repo
  build_pw_cli
  build_target_url
  ensure_logged_in
  if ! goto_and_wait "$target_url"; then
    echo "navigation to $target_url timed out" >&2
    pw_stop
    exit 1
  fi

  # 復元されたドラフトが検知を狂わせないよう、textarea を空の状態から始める。
  # 注意: これは GitHub がこの issue/PR 用に保存していた未投稿のコメントドラフトを
  # 破棄する。これは意図的な挙動（README 参照）: アップロードで挿入されたアセット URL を
  # 一意に検知するには空の textarea が必要なため。
  _clear_textarea

  # 1 ファイルずつアップロードし、各アップロードの URL を一意にするため
  # ファイル間で textarea をクリアする。
  local failed=0 url
  for f in "${files[@]}"; do
    if url=$(_upload_one "$f"); then
      printf '%s\t%s\n' "$f" "$url"
    else
      echo "warning: failed to upload $f" >&2
      failed=$((failed + 1))
    fi
    _clear_textarea
  done

  pw_stop
  [[ "$failed" -eq "${#files[@]}" ]] && exit 1
  return 0
}
