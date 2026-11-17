#!/usr/bin/env bash
# Dựng cụm kind + Kyverno đã ghim phiên bản (kế hoạch mục 10.1, 11.1). Chạy lại an toàn (idempotent).
# Phiên bản và nguồn: docs/versions.md.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."

CLUSTER_NAME="${CLUSTER_NAME:-devsecops}"
# kind v0.33.0 phát hành kèm node image này; Kyverno 1.19.2 kiểm thử conformance trên K8s 1.33–1.35
KIND_NODE_IMAGE=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
KYVERNO_CHART_VERSION=3.9.2      # appVersion v1.19.2
KYVERNO_APP_VERSION=v1.19.2
# Chart lấy qua OCI (ghcr.io): kyverno.github.io không truy cập được từ mạng lab (timeout).
# OCI manifest digest sha256:83054f30148c3cfc001087c1f5772eda7c7224e9b74b7f0e70c39c9cafe009d1; SHA-256 file .tgz dưới đây.
KYVERNO_CHART_OCI=oci://ghcr.io/kyverno/charts/kyverno
KYVERNO_CHART_SHA256=3d561086a5c457f038ad5ec01f2b8a279738c44eae0e8506e271e4599e627ae9

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "== Cụm $CLUSTER_NAME đã có"
else
  echo "== Tạo cụm kind $CLUSTER_NAME"
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null
kubectl version | grep -i '^Server'

echo "== Namespace + RBAC"
kubectl apply -f k8s/namespaces.yaml -f k8s/rbac.yaml

echo "== Kyverno chart $KYVERNO_CHART_VERSION (BẮT BUỘC có --version, không --devel)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
for i in 1 2 3; do helm pull "$KYVERNO_CHART_OCI" --version "$KYVERNO_CHART_VERSION" -d "$TMP" && break; sleep 5; done
CHART="$TMP/kyverno-$KYVERNO_CHART_VERSION.tgz"
echo "$KYVERNO_CHART_SHA256  $CHART" | sha256sum -c --quiet - || { echo "SHA-256 chart KHÔNG KHỚP — dừng." >&2; exit 1; }
# Cài từ đúng file đã kiểm tra hash (chart local nên --version chỉ để đối chiếu)
helm upgrade --install kyverno "$CHART" -n kyverno --create-namespace \
  --version "$KYVERNO_CHART_VERSION" --wait --timeout 10m

echo "== Image Kyverno đang chạy (phải là $KYVERNO_APP_VERSION)"
kubectl -n kyverno get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
bad=$(kubectl -n kyverno get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{"\n"}{end}' \
      | grep -E 'kyverno/(kyverno|background-controller|cleanup-controller|reports-controller):' | grep -vc ":$KYVERNO_APP_VERSION" || true)
[ "$bad" -eq 0 ] || { echo "Có controller không chạy $KYVERNO_APP_VERSION" >&2; exit 1; }
kubectl api-resources | grep -iE 'validatingpolic|clusterpolic'
