#!/usr/bin/env bash
# Làm mới credential trên kind (kế hoạch mục 2.4, 10.1). Chạy trước mỗi buổi làm việc/demo.
#  1. Assume role verifier (chỉ đọc ECR podinfo + signer:GetRevocationStatus) → phiên ≤ 1 giờ (role chaining từ SSO).
#  2. Secret verifier-aws-credentials cho extension → rollout restart extension (nếu đã cài).
#  3. Token ECR (lấy bằng chính role verifier, chỉ đọc) → Secret ecr-pull ở namespace app, demo; gắn vào SA default.
# Token/credential chỉ đi qua file tạm quyền 600 (xóa khi xong), không in ra log, không nằm trong Git.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
ROLE=${VERIFIER_ROLE:-devsecops-verifier}
EXT_NS=kyverno-notation-aws
TMP=$(mktemp -d); chmod 700 "$TMP"; trap 'rm -rf "$TMP"' EXIT
umask 077

aws sts assume-role --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE}" \
  --role-session-name "kind-verifier-$(date -u +%Y%m%dT%H%M%SZ)" --duration-seconds 3600 \
  --output json > "$TMP/creds.json"
jq -r '.Credentials | "AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nAWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nAWS_SESSION_TOKEN=\(.SessionToken)"' \
  "$TMP/creds.json" > "$TMP/verifier.env"
EXP=$(jq -r '.Credentials.Expiration' "$TMP/creds.json")
echo "Role $ROLE: phiên hết hạn lúc $EXP"

# Kiểm tra quyền thật của phiên verifier (không dùng credential admin)
(
  set -a; source "$TMP/verifier.env"; set +a
  unset AWS_PROFILE
  aws sts get-caller-identity --query Arn --output text | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/'
  aws ecr get-login-password > "$TMP/ecr-token"
  # Phải bị từ chối vì THIẾU QUYỀN (AccessDenied), không phải vì manifest rỗng không hợp lệ
  if aws ecr put-image --repository-name "$ECR_REPOSITORY" --image-tag deny-check --image-manifest '{}' \
       > /dev/null 2> "$TMP/put.err" || true; grep -q AccessDenied "$TMP/put.err"; then
    echo "Role verifier không có quyền ecr:PutImage (AccessDenied – đúng)"
  else
    echo "SAI: lời gọi PutImage không bị từ chối vì thiếu quyền: $(head -c 200 "$TMP/put.err")" >&2; exit 1
  fi
)

kubectl get ns "$EXT_NS" > /dev/null 2>&1 || kubectl create ns "$EXT_NS" > /dev/null
kubectl -n "$EXT_NS" create secret generic verifier-aws-credentials --from-env-file="$TMP/verifier.env" \
  --dry-run=client -o yaml | kubectl apply -f - > /dev/null
kubectl -n "$EXT_NS" annotate secret verifier-aws-credentials --overwrite "devsecops/expires=$EXP" > /dev/null
echo "Secret $EXT_NS/verifier-aws-credentials: cập nhật"

AUTH=$(printf 'AWS:%s' "$(cat "$TMP/ecr-token")" | base64 -w0)
jq -n --arg reg "$ECR_REGISTRY" --arg auth "$AUTH" '{auths: {($reg): {auth: $auth}}}' > "$TMP/dockerconfig.json"
for ns in "$APP_NAMESPACE" "$TEST_NAMESPACE"; do
  kubectl -n "$ns" create secret generic ecr-pull --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$TMP/dockerconfig.json" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
  kubectl -n "$ns" patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-pull"}]}' > /dev/null
  echo "Secret $ns/ecr-pull: cập nhật, gắn vào SA default"
done

if kubectl -n "$EXT_NS" get deploy kyverno-notation-aws > /dev/null 2>&1; then
  kubectl -n "$EXT_NS" rollout restart deploy/kyverno-notation-aws > /dev/null
  kubectl -n "$EXT_NS" rollout status deploy/kyverno-notation-aws --timeout=120s
fi
