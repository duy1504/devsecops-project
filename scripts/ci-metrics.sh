#!/usr/bin/env bash
# Thời gian từng bước của job verify và publish trên các run GitHub Actions (kế hoạch mục 12.5).
# Dùng: bash scripts/ci-metrics.sh [số run tối đa]   (cần gh đã đăng nhập; mặc định 30 run gần nhất)
# In CSV: run_id,sự kiện,nhánh,job,kết luận job,bước,giây — rồi bảng n/min/trung bình/max cho các job thành công.
# Chạy được trên Git Bash (không cần jq: dùng gh --jq).
set -euo pipefail
GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="$LOCALAPPDATA/Programs/gh/bin/gh.exe"
REPO="${REPO:-duy1504/devsecops-project}"
LIMIT="${1:-30}"
STEPS='^(Unit test|Secret scan.*|Build once|SBOM.*|Vulnerability scan.*|GATE.*|Download approved image.*|Verify artifact integrity.*|Push .*|Wait for ECR Managed Signing.*|Release manifest)$'

csv=$(mktemp); trap 'rm -f "$csv"' EXIT
echo "run_id,event,branch,job,job_conclusion,step,seconds" > "$csv"
for id in $("$GH" run list --repo "$REPO" --workflow ci-cd.yml --limit "$LIMIT" --json databaseId,status \
            --jq '.[] | select(.status=="completed") | .databaseId'); do
  "$GH" run view "$id" --repo "$REPO" --json databaseId,event,headBranch,jobs --jq '
    . as $r | .jobs[] | select(.name=="verify" or .name=="publish" or .name=="policy-test") | . as $j
    | ([{name:"(job \($j.name))", startedAt:$j.startedAt, completedAt:$j.completedAt}] + .steps)[]
    | select(.startedAt != null and .completedAt != null)
    | "\($r.databaseId),\($r.event),\($r.headBranch),\($j.name),\($j.conclusion),\(.name | gsub(",";";")),\(((.completedAt|fromdateiso8601) - (.startedAt|fromdateiso8601)))"' >> "$csv"
done
cat "$csv"
echo
echo "== Thống kê (chỉ job thành công)"
awk -F, -v re="$STEPS" 'NR>1 && $5=="success" && ($6 ~ re || $6 ~ /^\(job /) {
    k=$4 " | " $6; n[k]++; s[k]+=$7; if(!(k in mn) || $7<mn[k]) mn[k]=$7; if($7>mx[k]) mx[k]=$7 }
  END { printf "%-62s %3s %6s %6s %6s\n","job | bước","n","min","tb","max";
        for (k in n) printf "%-62s %3d %6d %6.1f %6d\n", k, n[k], mn[k], s[k]/n[k], mx[k] }' "$csv" | sort
