#!/usr/bin/env bash
# Lifecycle policy cho repo podinfo (kế hoạch mục 8.1): chỉ chọn tag phát hành tiền tố sha-.
# Fixture (unsigned-baseline, wrong-signer-baseline, signed-baseline) và chữ ký (referrer không tag) không khớp rule.
# Xem trước (preview) rồi mới áp; dừng nếu preview chọn bất kỳ image nào không có tag sha-.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
POLICY=infra/aws/lifecycle-policy.json
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/aws/lifecycle-$TS; mkdir -p "$OUT"
cp "$POLICY" "$OUT/"

jq -e '[.rules[] | .selection.tagStatus == "tagged" and .selection.tagPrefixList == ["sha-"]] | all' "$POLICY" > /dev/null \
  || { echo "Mọi rule phải là tagged + tagPrefixList [\"sha-\"] (không rule untagged/any)" >&2; exit 1; }

aws ecr start-lifecycle-policy-preview --repository-name "$ECR_REPOSITORY" \
  --lifecycle-policy-text "file://$POLICY" > /dev/null
for i in $(seq 1 30); do
  aws ecr get-lifecycle-policy-preview --repository-name "$ECR_REPOSITORY" --output json > "$OUT/preview.json"
  st=$(jq -r .status "$OUT/preview.json")
  [ "$st" = COMPLETE ] && break
  [ "$st" = FAILED ] && { echo "Preview FAILED" >&2; exit 1; }
  sleep 2
done
[ "$st" = COMPLETE ] || { echo "Preview chưa xong (status=$st)" >&2; exit 1; }
n=$(jq '.previewResults | length' "$OUT/preview.json")
bad=$(jq '[.previewResults[] | select(([.imageTags[]? | startswith("sha-")] | any) | not)] | length' "$OUT/preview.json")
echo "Preview: $n image sẽ bị expire, $bad image không có tag sha- (phải = 0)"
[ "$bad" = 0 ] || { echo "Preview chọn image ngoài tag sha- – không áp" >&2; jq .previewResults "$OUT/preview.json" >&2; exit 1; }

aws ecr put-lifecycle-policy --repository-name "$ECR_REPOSITORY" --lifecycle-policy-text "file://$POLICY" > /dev/null
aws ecr get-lifecycle-policy --repository-name "$ECR_REPOSITORY" --query lifecyclePolicyText --output text \
  | jq . > "$OUT/applied.json"
diff <(jq -S . "$POLICY") <(jq -S . "$OUT/applied.json") > /dev/null || { echo "Policy trên ECR khác file trong repo" >&2; exit 1; }
aws ecr describe-images --repository-name "$ECR_REPOSITORY" \
  --query 'imageDetails[].{tags:join(`,`,imageTags||[`<none>`]),type:artifactMediaType||imageManifestMediaType}' --output table
echo "Đã áp lifecycle policy. Bằng chứng: $OUT"
