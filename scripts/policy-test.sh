#!/usr/bin/env bash
# Test offline Policy 1 bằng Kyverno CLI (kế hoạch mục 11.4). Dùng chung cho local và job policy-test.
set -euo pipefail
cd "$(dirname "$0")/.."
# Giá trị giả cố định cho test offline (account ví dụ của tài liệu AWS); chỉ ghi đè khi thật sự cần
export ECR_IMAGE="${POLICY_TEST_ECR_IMAGE:-111122223333.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo}"
src=policies/tests/allowed-image
out=policies/rendered/allowed-image
rm -rf "$out" && mkdir -p "$out"
envsubst '${ECR_IMAGE}' < policies/allowed-image.template.yaml > "$out/allowed-image.yaml"
envsubst '${ECR_IMAGE}' < "$src/resources.template.yaml"     > "$out/resources.yaml"
cp "$src/kyverno-test.yaml" "$out/"
kyverno version | sed -n 1p
kyverno test "$out"
