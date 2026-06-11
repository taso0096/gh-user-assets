# download サブコマンド。エントリポイントから（common.sh の後に）source される。

# 認証済みセッションで単一のアセット URL を $output_dir にダウンロードする。
# 保存先パスを出力する。失敗時は非ゼロを返す。
_download_url() {
  local url="$1"

  # インデックスがこのナビゲーションだけを指すよう、過去のネットワークエントリをクリアする。
  "${pw_cli[@]}" requests --clear >/dev/null 2>&1 || true
  "${pw_cli[@]}" goto "$url" >/dev/null 2>&1 || true

  # 未認証またはアセットが存在しない場合、S3 画像へリダイレクトせず
  # 404 の「Page not found」ページが返る。
  local reqs
  reqs=$("${pw_cli[@]}" --raw requests --static --filter 'user-attachments/assets|amazonaws' 2>/dev/null || echo "")
  if echo "$reqs" | grep -q '\[404\]'; then
    echo "asset not found (404): $url" >&2
    return 1
  fi

  # 画像は S3 から static リソースとして配信されるため --static が必要。
  # アセット/S3 のリクエストに絞ることで、無関係なページアセットを拾わないようにする。
  local index
  index=$(echo "$reqs" | grep '\[200\]' | tail -1 | grep -oE '^[0-9]+' || echo "")

  if [[ -z "$index" ]]; then
    echo "could not locate a 200 response for $url" >&2
    return 1
  fi

  local saved_path
  saved_path=$("${pw_cli[@]}" --raw response-body "$index" 2>/dev/null || echo "")
  if [[ -z "$saved_path" || ! -f "$saved_path" ]]; then
    echo "could not save response body for $url" >&2
    return 1
  fi

  # playwright-cli は保存ファイルに content-type 由来の拡張子を付ける。
  # saved_path が実際に拡張子を持つときだけ付与する。そうしないと
  # ${saved_path##*.} がパス全体に展開されてしまう。
  local stripped="${url%%\?*}"
  local out_name="${stripped##*/}"
  [[ "$saved_path" == *.* ]] && out_name="${out_name}.${saved_path##*.}"
  mv "$saved_path" "$output_dir/$out_name"
  echo "$output_dir/$out_name"
}

ghua_download() {
  output_dir="."
  parse_common_args "$@"
  set -- "${REMAINING_ARGS[@]:-}"

  build_pw_cli

  local urls
  if [[ $# -gt 0 && -n "$1" ]]; then
    # URL モード: 渡されたアセット URL だけをダウンロードする。
    urls=$(printf '%s\n' "$@")
  else
    # issue/PR モード: 本文・コメント・（PR の場合は）レビューコメントと
    # レビュー本文から、すべてのアセット URL を収集する。
    require_repo
    build_target_url
    urls=$(
      {
        gh api "repos/${repo}/issues/${target_number}" --jq '.body'
        gh api "repos/${repo}/issues/${target_number}/comments" --jq '.[].body'
        # issues エンドポイントは issue / PR どちらの本文と会話コメントもカバーするが、
        # PR の差分行コメントやレビュー本文はカバーしない。
        if [[ -n "$pr" ]]; then
          gh api "repos/${repo}/pulls/${target_number}/comments" --jq '.[].body'
          gh api "repos/${repo}/pulls/${target_number}/reviews" --jq '.[].body'
        fi
      } 2>/dev/null \
        | grep -oE "https://github\.com/${GHUA_ASSET_RE}" \
        | sort -u \
        || true
    )
    if [[ -z "$urls" ]]; then
      echo "no asset URLs found on $target_url" >&2
      exit 1
    fi
  fi

  [[ -d "$output_dir" ]] || mkdir -p "$output_dir"

  # アセット URL へ遷移する前に認証済みセッションを確立する。
  # ログインしていないと、GitHub はアセット URL にリダイレクトせず 404 を返す。
  ensure_logged_in

  local url count=0
  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    if _download_url "$url"; then
      count=$((count + 1))
    fi
  done <<< "$urls"

  pw_stop

  if [[ "$count" -eq 0 ]]; then
    echo "no files downloaded" >&2
    exit 1
  fi
}
