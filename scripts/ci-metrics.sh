#!/usr/bin/env bash
# Thời gian từng bước của job verify trên các run GitHub Actions (kế hoạch mục 12.5).
# Dùng: bash scripts/ci-metrics.sh [số run tối đa]   (cần gh đã đăng nhập; mặc định 30 run gần nhất)
# In CSV: run_id,sự kiện,nhánh,kết luận,bước,giây — rồi bảng min/trung bình/max cho các run verify thành công.
set -euo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="$LOCALAPPDATA/Programs/gh/bin/gh.exe"
REPO="${REPO:-duy1504/devsecops-project}"
LIMIT="${1:-30}"
STEPS='^(Unit test|Secret scan.*|Build once|SBOM.*|Vulnerability scan.*|GATE.*)$'

csv=$(mktemp); trap 'rm -f "$csv"' EXIT
echo "run_id,event,branch,verify_conclusion,step,seconds" > "$csv"
for id in $("$GH" run list --repo "$REPO" --workflow ci-cd.yml --limit "$LIMIT" --json databaseId,status \
            --jq '.[] | select(.status=="completed") | .databaseId'); do
  "$GH" run view "$id" --repo "$REPO" --json databaseId,event,headBranch,jobs --jq '
    . as $r | .jobs[] | select(.name=="verify") | . as $j
    | ([{name:"(job verify)", startedAt:$j.startedAt, completedAt:$j.completedAt}] + .steps)[]
    | select(.startedAt != null and .completedAt != null)
    | "\($r.databaseId),\($r.event),\($r.headBranch),\($j.conclusion),\(.name | gsub(",";";")),\(((.completedAt|fromdateiso8601) - (.startedAt|fromdateiso8601)))"' >> "$csv"
done
cat "$csv"
echo
echo "== Thống kê (chỉ run có job verify thành công)"
awk -F, -v re="$STEPS" 'NR>1 && $4=="success" && ($5 ~ re || $5=="(job verify)") {
    n[$5]++; s[$5]+=$6; if(!($5 in mn) || $6<mn[$5]) mn[$5]=$6; if($6>mx[$5]) mx[$5]=$6 }
  END { printf "%-45s %3s %6s %6s %6s\n","bước","n","min","tb","max";
        for (k in n) printf "%-45s %3d %6d %6.1f %6d\n", k, n[k], mn[k], s[k]/n[k], mx[k] }' "$csv" | sort
