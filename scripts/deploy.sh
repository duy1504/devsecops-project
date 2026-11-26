#!/usr/bin/env bash
# Triển khai podinfo bằng DIGEST từ release.json lên kind (kế hoạch mục 10.4). Chạy trên WSL:
#   bash scripts/deploy.sh reports/release/<run-id>/release.json
# - Image chỉ lấy từ release.json của run thành công (không tự gõ tag); account ID trong file đã bị che
#   (<ACCOUNT_ID>, repo public) → ghép lại bằng giá trị local và đối chiếu với cấu hình (aws-env.sh).
# - kubectl chạy dưới danh tính deployer (impersonate group devsecops-deployers, Role k8s/rbac.yaml):
#   chứng minh Role tối thiểu là đủ; smoke test qua services/proxy, không port-forward.
# - Vẫn đi qua admission (Policy 1 + Policy 2); không có đường tắt.
set -euo pipefail
cd "$(dirname "$0")/.."
REL=${1:?Dùng: deploy.sh <release.json>}
source scripts/aws-env.sh
NS=$APP_NAMESPACE
AS=(--as="${DEPLOYER_USER:-ci-deployer}" --as-group="${DEPLOYER_GROUP:-devsecops-deployers}")
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/deploy/$TS; mkdir -p "$OUT"
mask() { sed -E "s/${AWS_ACCOUNT_ID}/<ACCOUNT_ID>/g; s/eyJ[A-Za-z0-9._-]{20,}/<JWT>/g"; }
k() { kubectl "${AS[@]}" "$@"; }

echo "== 1. Kiểm tra release.json"
jq -e --arg arn "${SIGNING_PROFILE_ARN/$AWS_ACCOUNT_ID/<ACCOUNT_ID>}" '
  .signing_status == "COMPLETE" and .gate_result == "pass" and .critical_count == 0
  and (.image_digest | test("^sha256:[0-9a-f]{64}$"))
  and (.image_tag | startswith("sha-"))
  and .signing_profile_arn == $arn' "$REL" > /dev/null \
  || { echo "release.json không đạt (ký/gate/digest/profile)" >&2; exit 1; }
URI=$(jq -r .image_uri "$REL"); URI=${URI/<ACCOUNT_ID>/$AWS_ACCOUNT_ID}
[ "$URI" = "$ECR_IMAGE" ] || { echo "image_uri trong release.json khác ECR_IMAGE cấu hình" >&2; exit 1; }
DIGEST=$(jq -r .image_digest "$REL")
export APP_IMAGE_REF="${ECR_IMAGE}@${DIGEST}"
cp "$REL" "$OUT/release.json"
# Digest phải có trên ECR, đúng tag phát hành, và đã ký COMPLETE bởi profile chính
aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageDigest="$DIGEST" \
  --query 'imageDetails[0].imageTags' --output json > "$OUT/ecr-tags.json"
jq -e --arg t "$(jq -r .image_tag "$REL")" 'index($t) != null' "$OUT/ecr-tags.json" > /dev/null \
  || { echo "Digest trên ECR không mang tag $(jq -r .image_tag "$REL")" >&2; exit 1; }
aws ecr describe-image-signing-status --repository-name "$ECR_REPOSITORY" --image-id imageDigest="$DIGEST" \
  --output json | mask > "$OUT/signing-status.json"
echo "Image: ${ECR_REPOSITORY}@${DIGEST} (tag $(jq -r .image_tag "$REL"), commit $(jq -r .commit_sha "$REL" | cut -c1-12))"

echo "== 2. Điều kiện cụm"
exp=$(kubectl -n kyverno-notation-aws get secret verifier-aws-credentials -o jsonpath='{.metadata.annotations.devsecops/expires}')
if [ -z "$exp" ] || [ "$(date -u -d "$exp" +%s)" -le "$(( $(date -u +%s) + 300 ))" ]; then
  echo "Credential verifier hết hạn/sắp hết ($exp) → Policy 2 sẽ chặn mọi Pod. Chạy scripts/refresh-lab-credentials.sh" >&2
  exit 1
fi
for chk in "create deployments" "patch deployments" "create services" "get services/proxy"; do
  [ "$(k auth can-i $chk -n "$NS")" = yes ] || { echo "Deployer thiếu quyền: $chk" >&2; exit 1; }
done

echo "== 3. Render manifest cuối cùng → dry-run server → apply (danh tính deployer)"
envsubst '${APP_IMAGE_REF}' < k8s/deployment.template.yaml > "$OUT/deployment.yaml"
grep -q '\${' "$OUT/deployment.yaml" && { echo "Còn placeholder chưa render" >&2; exit 1; }
k apply --dry-run=server -f k8s/service.yaml -f "$OUT/deployment.yaml" > /dev/null
date -u +%FT%TZ > "$OUT/apply.time"
k apply -f k8s/service.yaml -f "$OUT/deployment.yaml" | tee "$OUT/apply.txt"

echo "== 4. Rollout"
if ! k -n "$NS" rollout status deployment/podinfo --timeout=180s 2>&1 | tee "$OUT/rollout.txt"; then
  # Policy chỉ match Pod: apply Deployment vẫn thành công, ReplicaSet không tạo được Pod (FailedCreate)
  k -n "$NS" get events --sort-by=.lastTimestamp 2>&1 | mask > "$OUT/events.txt"
  echo "Rollout thất bại – xem $OUT/events.txt (FailedCreate = admission từ chối)" >&2
  tail -5 "$OUT/events.txt" >&2
  exit 1
fi

echo "== 5. Kiểm tra runtime + smoke test"
k -n "$NS" get pods -l app=podinfo \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}' \
  > "$OUT/pods-images.raw"
mask < "$OUT/pods-images.raw" > "$OUT/pods-images.txt"
bad=$(awk -F'\t' -v d="$DIGEST" '$2 !~ ("@" d "$") || $3 !~ ("@" d "$")' "$OUT/pods-images.raw" | wc -l)
pods=$(wc -l < "$OUT/pods-images.raw")
rm -f "$OUT/pods-images.raw"
[ "$pods" -ge 1 ] && [ "$bad" = 0 ] || { echo "Pod chạy image khác digest phát hành" >&2; exit 1; }
k get --raw "/api/v1/namespaces/$NS/services/podinfo:9898/proxy/healthz" > "$OUT/healthz.txt"
k get --raw "/api/v1/namespaces/$NS/services/podinfo:9898/proxy/version" > "$OUT/version.json"
cat "$OUT/healthz.txt"; echo; cat "$OUT/version.json"; echo
k -n "$NS" get deploy,rs,pods -o wide 2>&1 | mask > "$OUT/resources.txt"
k -n "$NS" get events --sort-by=.lastTimestamp 2>&1 | mask > "$OUT/events.txt"
k -n "$NS" logs deploy/podinfo --tail=50 2>&1 | mask > "$OUT/podinfo.log" || true
kubectl -n kyverno-notation-aws logs deploy/kyverno-notation-aws --since=10m 2>&1 | mask > "$OUT/extension.log"
for f in deployment.yaml release.json; do mask < "$OUT/$f" > "$OUT/$f.tmp" && mv "$OUT/$f.tmp" "$OUT/$f"; done
echo "TC01 trọn luồng: ĐẠT – $pods Pod chạy ${ECR_REPOSITORY}@${DIGEST}"
echo "Bằng chứng: $OUT"
