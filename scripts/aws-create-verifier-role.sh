#!/usr/bin/env bash
# Role verifier cho kind (kế hoạch mục 2.4, 8.4, 10.1): chỉ đọc ECR repo podinfo + signer:GetRevocationStatus.
# Chỉ phiên SSO AdministratorAccess của account lab được assume (credential ngắn hạn, role chaining ≤ 1 giờ).
# Không push, không SignPayload, không sửa profile. Chạy lại an toàn: cập nhật trust + inline policy.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
ROLE=${VERIFIER_ROLE:-devsecops-verifier}
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/aws/verifier-$TS; mkdir -p "$OUT"
envsubst '${AWS_ACCOUNT_ID}' < infra/aws/verifier-trust.template.json > "$OUT/trust.json"
envsubst '${AWS_ACCOUNT_ID} ${AWS_REGION} ${ECR_REPOSITORY}' < infra/aws/verifier-policy.template.json > "$OUT/policy.json"

# Kiểm tra policy bằng IAM Access Analyzer trước khi áp (không chấp nhận lỗi/cảnh báo bảo mật)
for p in policy:IDENTITY_POLICY trust:RESOURCE_POLICY; do
  f=${p%%:*}; t=${p##*:}
  extra=(); [ "$t" = RESOURCE_POLICY ] && extra=(--validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument)
  aws accessanalyzer validate-policy --policy-type "$t" "${extra[@]}" \
    --policy-document "file://$OUT/$f.json" --output json > "$OUT/validate-$f.json"
  bad=$(jq '[.findings[] | select(.findingType == "ERROR" or .findingType == "SECURITY_WARNING")] | length' "$OUT/validate-$f.json")
  echo "Access Analyzer $f: $(jq -r '[.findings[] | "\(.findingType):\(.issueCode)"] | join(", ")' "$OUT/validate-$f.json")"
  [ "$bad" = 0 ] || { echo "Policy $f có ERROR/SECURITY_WARNING" >&2; exit 1; }
done

if aws iam get-role --role-name "$ROLE" > /dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "file://$OUT/trust.json"
  echo "Role $ROLE đã có – cập nhật trust policy"
else
  aws iam create-role --role-name "$ROLE" --description "kind verifier: ECR read podinfo + Signer revocation (devsecops lab)" \
    --assume-role-policy-document "file://$OUT/trust.json" --max-session-duration 3600 > /dev/null
  echo "Đã tạo role $ROLE"
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name verifier-read --policy-document "file://$OUT/policy.json"
aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyName' --output json > "$OUT/attached.json"
[ "$(jq length "$OUT/attached.json")" = 0 ] || { echo "Role có managed policy gắn thêm – kiểm tra lại" >&2; exit 1; }
aws iam get-role --role-name "$ROLE" --query 'Role.{name:RoleName,maxSession:MaxSessionDuration}' --output table
echo "Bằng chứng: $OUT"
