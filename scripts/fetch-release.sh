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
# Git Bash trên Windows không có jq → chỉ dùng gh --jq; deploy.sh (WSL) đối chiếu release.json với run.json
q() { gh run view "$RUN" -R "$REPO" --json conclusion,headBranch,event,headSha,attempt,url,databaseId --jq "$1"; }
[ "$(q .conclusion)" = success ] || { echo "Run $RUN không thành công" >&2; exit 1; }
[ "$(q .headBranch)" = main ] && [ "$(q .event)" = push ] || { echo "Run $RUN không phải push vào main" >&2; exit 1; }
ATTEMPT=$(q .attempt)
OUT=reports/release/$RUN; rm -rf "$OUT"; mkdir -p "$OUT"
gh run download "$RUN" -R "$REPO" -n "release-$RUN-$ATTEMPT" -D "$OUT"
[ -s "$OUT/release.json" ] || { echo "Artifact không có release.json" >&2; exit 1; }
q '{run_id: (.databaseId|tostring), attempt: (.attempt|tostring), head_sha: .headSha, branch: .headBranch, event, conclusion, url}' > "$OUT/run.json"
cat "$OUT/run.json"; echo
echo "Đã lưu: $OUT/release.json – triển khai trên WSL: bash scripts/deploy.sh $OUT/release.json"
