#!/usr/bin/env bash
# Render và áp Policy 1 (allowed-image) lên cụm hiện tại (kế hoạch mục 11.2).
# Bắt buộc ECR_IMAGE (= <account>.dkr.ecr.<region>.amazonaws.com/podinfo, mục 4.3). Policy 2 thêm khi spike đạt.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
: "${ECR_IMAGE:?Cần đặt ECR_IMAGE (kế hoạch mục 4.3)}"
[[ "$ECR_IMAGE" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/podinfo$ ]] \
  || { echo "ECR_IMAGE sai định dạng: $ECR_IMAGE" >&2; exit 1; }

out=policies/rendered/cluster; rm -rf "$out"; mkdir -p "$out"
envsubst '${ECR_IMAGE}' < policies/allowed-image.template.yaml > "$out/allowed-image.yaml"
kubectl apply --dry-run=server -f "$out/allowed-image.yaml" >/dev/null
kubectl apply -f "$out/allowed-image.yaml"
# Chờ policy sẵn sàng (Kyverno cập nhật webhook)
for i in $(seq 1 30); do
  ready=$(kubectl get validatingpolicy allowed-image -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null || true)
  [ "$ready" = "true" ] && break; sleep 2
done
kubectl get validatingpolicy allowed-image -o wide
