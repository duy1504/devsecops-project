#!/usr/bin/env bash
# Cài extension kyverno-notation-aws (bản tự build) + TrustStore/TrustPolicy + Policy 2 lên kind (spike bước 8, mục 10.1, 11.3).
# Cần: cụm kind devsecops có Kyverno 1.19.2; đã chạy scripts/refresh-lab-credentials.sh (Secret verifier).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
CLUSTER=${KIND_CLUSTER:-devsecops}
EXT_NS=kyverno-notation-aws
EXT_IMAGE=local/kyverno-notation-aws:58b210b-p2
EXT_IMAGE_ID=sha256:f2d1998698b3f583b961590dd518af0ddb5458efb1f202ff5f1fddaa8e3c05be   # docs/versions.md mục 2b
ROOT_FP=90:A8:7D:05:43:C3:F0:94:DB:FF:95:89:B6:64:9A:FF:E2:F3:D6:E0:F3:08:79:9B:E2:25:84:61:C6:86:47:3F
out=policies/rendered/cluster; mkdir -p "$out"

echo "== 1. Image extension (đúng image ID đã gate 0 Critical)"
[ "$(docker image inspect --format '{{.Id}}' "$EXT_IMAGE")" = "$EXT_IMAGE_ID" ] \
  || { echo "Image $EXT_IMAGE không khớp ID đã ghim" >&2; exit 1; }
kind load docker-image "$EXT_IMAGE" --name "$CLUSTER"

echo "== 2. CRD + deployment"
kubectl -n "$EXT_NS" get secret verifier-aws-credentials > /dev/null \
  || { echo "Thiếu Secret verifier – chạy scripts/refresh-lab-credentials.sh trước" >&2; exit 1; }
kubectl apply -f infra/kyverno-notation-aws/crds/
kubectl wait --for=condition=Established crd/trustpolicies.notation.nirmata.io crd/truststores.notation.nirmata.io --timeout=60s
kubectl apply -f infra/kyverno-notation-aws/install.yaml
kubectl -n "$EXT_NS" rollout status deploy/kyverno-notation-aws --timeout=180s

echo "== 3. TrustStore (root AWS Signer, kiểm fingerprint) + TrustPolicy"
if [ ! -f policies/truststore.yaml ]; then
  curl -fsSL --retry 3 https://d2hvyiie56hcat.cloudfront.net/aws-signer-notation-root.cert -o "$out/aws-signer-root.cert"
  {
    echo "# TrustStore cho extension: root AWS Signer (commercial). Nguồn: https://d2hvyiie56hcat.cloudfront.net/aws-signer-notation-root.cert"
    echo "# Fingerprint SHA-256 đã ghim (docs/versions.md): $ROOT_FP – scripts/install-notation-ext.sh kiểm lại mỗi lần áp."
    echo "apiVersion: notation.nirmata.io/v1alpha1"
    echo "kind: TrustStore"
    echo "metadata:"
    echo "  name: aws-signer-ts"
    echo "spec:"
    echo "  trustStoreName: aws-signer-ts"
    echo "  type: signingAuthority"
    echo "  caBundle: |-"
    sed 's/^/    /' "$out/aws-signer-root.cert"
  } > policies/truststore.yaml
fi
awk '/caBundle: \|-/{f=1;next} f{sub(/^    /,"");print}' policies/truststore.yaml > "$out/truststore-ca.pem"
fp=$(openssl x509 -in "$out/truststore-ca.pem" -noout -fingerprint -sha256 | cut -d= -f2)
[ "$fp" = "$ROOT_FP" ] || { echo "TrustStore: fingerprint không khớp ($fp)" >&2; exit 1; }
kubectl apply -f policies/truststore.yaml
envsubst '${ECR_IMAGE} ${SIGNING_PROFILE_ARN}' < policies/trustpolicy.template.yaml > "$out/trustpolicy.yaml"
grep -v '^\s*#' "$out/trustpolicy.yaml" | grep -q "$WRONG_SIGNING_PROFILE" && { echo "TrustPolicy chứa profile B" >&2; exit 1; }
kubectl apply -f "$out/trustpolicy.yaml"

echo "== 4. Policy 2 (caBundle = CA công khai của extension)"
CA_SECRET=""
for i in $(seq 1 30); do
  CA_SECRET=$(kubectl -n "$EXT_NS" get secret -o name | grep -E '\.svc\.tls-ca$' | head -1 || true)
  [ -n "$CA_SECRET" ] && break; sleep 2
done
[ -n "$CA_SECRET" ] || { echo "Chưa thấy Secret CA của extension" >&2; exit 1; }
kubectl -n "$EXT_NS" get "$CA_SECRET" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$out/ext-ca.pem"
openssl x509 -in "$out/ext-ca.pem" -noout -subject -enddate
EXT_CA_BUNDLE=$(sed 's/^/                /' "$out/ext-ca.pem") envsubst '${EXT_CA_BUNDLE}' \
  < policies/verify-signer.template.yaml > "$out/verify-signer.yaml"
kubectl apply --dry-run=server -f "$out/verify-signer.yaml" > /dev/null
kubectl apply -f "$out/verify-signer.yaml"
for i in $(seq 1 30); do
  [ "$(kubectl get clusterpolicy verify-signer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ] && break
  sleep 2
done
kubectl get clusterpolicy verify-signer
kubectl get trustpolicy,truststore
