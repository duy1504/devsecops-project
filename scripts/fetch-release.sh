#!/usr/bin/env bash
# Tải hồ sơ phát hành (artifact release-<run>-<attempt>) của một run THÀNH CÔNG trên main (kế hoạch mục 10.4 bước 1).
# Chạy bằng Git Bash/Windows (gh + Git Credential Manager), không chạy trong WSL (CLAUDE.md quy tắc 9).
#   bash scripts/fetch-release.sh            # run thành công mới nhất của push vào main
#   bash scripts/fetch-release.sh <run-id>
# Kết quả: reports/release/<run-id>/release.json → dùng cho scripts/deploy.sh trên WSL.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${GITHUB_REPOSITORY:-duy1504/devsecops-project}
WF=ci-cd.yml
RUN=${1:-}
if [ -z "$RUN" ]; then
  RUN=$(gh run list -R "$REPO" -w "$WF" -b main -e push -s success -L 1 --json databaseId --jq '.[0].databaseId')
  [ -n "$RUN" ] && [ "$RUN" != null ] || { echo "Không có run thành công nào trên main" >&2; exit 1; }
fi
info=$(gh run view "$RUN" -R "$REPO" --json conclusion,headBranch,event,headSha,attempt,url)
[ "$(jq -r .conclusion <<< "$info")" = success ] || { echo "Run $RUN không thành công" >&2; exit 1; }
[ "$(jq -r .headBranch <<< "$info")" = main ] && [ "$(jq -r .event <<< "$info")" = push ] \
  || { echo "Run $RUN không phải push vào main" >&2; exit 1; }
ATTEMPT=$(jq -r .attempt <<< "$info")
OUT=reports/release/$RUN; rm -rf "$OUT"; mkdir -p "$OUT"
gh run download "$RUN" -R "$REPO" -n "release-$RUN-$ATTEMPT" -D "$OUT"
jq -e --arg sha "$(jq -r .headSha <<< "$info")" --arg run "$RUN" \
  '.commit_sha == $sha and .workflow_run_id == $run and .signing_status == "COMPLETE"' "$OUT/release.json" > /dev/null \
  || { echo "release.json không khớp run $RUN" >&2; exit 1; }
jq '{commit_sha, workflow_run_id, run_attempt, image_tag, image_digest, signing_status}' "$OUT/release.json"
echo "Đã lưu: $OUT/release.json ($(jq -r .url <<< "$info"))"
