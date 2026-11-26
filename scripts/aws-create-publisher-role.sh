#!/usr/bin/env bash
# GitHub OIDC provider + role publisher (kế hoạch mục 8.4, 8.5). Chạy trên WSL bằng phiên SSO quản trị lab.
# Publisher: push vào ECR repo podinfo + signer:SignPayload trên profile chính (Managed Signing ký dưới danh tính
# người push). Không sửa IAM, signing rule, không xóa image, không có quyền Kubernetes.
# Trust: chỉ job của repo này trên nhánh main. Repo bật "immutable subject claims" nên claim sub có dạng
#   repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main
# (kiểm tra: gh api repos/<owner>/<repo>/actions/oidc/customization/sub → sub_claim_prefix).
# Chạy lại an toàn: cập nhật trust + inline policy.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
ROLE=${PUBLISHER_ROLE:-devsecops-publisher}
# ID owner/repo GitHub là thông tin công khai của repo public, không phải bí mật
export OIDC_SUB_PREFIX=${OIDC_SUB_PREFIX:-repo:duy1504@210903593/devsecops-project@1460578199}
OIDC_HOST=token.actions.githubusercontent.com
OIDC_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/aws/publisher-$TS; mkdir -p "$OUT"
mask() { sed -E "s/${AWS_ACCOUNT_ID}/<ACCOUNT_ID>/g"; }

envsubst '${AWS_ACCOUNT_ID} ${OIDC_SUB_PREFIX}' < infra/aws/publisher-trust.template.json > "$OUT/trust.json"
envsubst '${AWS_ACCOUNT_ID} ${AWS_REGION} ${ECR_REPOSITORY} ${SIGNING_PROFILE_ARN}' \
  < infra/aws/publisher-policy.template.json > "$OUT/policy.json"

# Kiểm tra nội dung đã render trước khi gửi lên AWS
jq -e --arg sub "${OIDC_SUB_PREFIX}:ref:refs/heads/main" '
  [.Statement[] | .Condition.StringEquals["token.actions.githubusercontent.com:sub"]] == [$sub]
  and ([.Statement[] | .Condition.StringEquals["token.actions.githubusercontent.com:aud"]] == ["sts.amazonaws.com"])
  and ([.. | strings | select(test("\\*"))] | length == 0)' "$OUT/trust.json" > /dev/null \
  || { echo "Trust policy sai (sub/aud hoặc có wildcard)" >&2; exit 1; }
grep -q "$WRONG_SIGNING_PROFILE" "$OUT/policy.json" && { echo "Policy chứa profile B" >&2; exit 1; }
jq -e '[.Statement[].Action] | flatten | all(. != "ecr:*" and . != "signer:*" and (startswith("iam:") | not))' \
  "$OUT/policy.json" > /dev/null || { echo "Policy có action quá rộng" >&2; exit 1; }

# IAM Access Analyzer: không chấp nhận ERROR/SECURITY_WARNING
for p in policy:IDENTITY_POLICY trust:RESOURCE_POLICY; do
  f=${p%%:*}; t=${p##*:}
  extra=(); [ "$t" = RESOURCE_POLICY ] && extra=(--validate-policy-resource-type AWS::IAM::AssumeRolePolicyDocument)
  aws accessanalyzer validate-policy --policy-type "$t" "${extra[@]}" \
    --policy-document "file://$OUT/$f.json" --output json > "$OUT/validate-$f.json"
  bad=$(jq '[.findings[] | select(.findingType == "ERROR" or .findingType == "SECURITY_WARNING")] | length' "$OUT/validate-$f.json")
  echo "Access Analyzer $f: $(jq -r '[.findings[] | "\(.findingType):\(.issueCode)"] | join(", ")' "$OUT/validate-$f.json")"
  [ "$bad" = 0 ] || { echo "Policy $f có ERROR/SECURITY_WARNING" >&2; exit 1; }
done

# OIDC provider (cấp account, dùng chung): tạo nếu chưa có, audience sts.amazonaws.com
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" > "$OUT/oidc-provider.json" 2>/dev/null; then
  echo "OIDC provider $OIDC_HOST đã có"
else
  aws iam create-open-id-connect-provider --url "https://${OIDC_HOST}" --client-id-list sts.amazonaws.com > /dev/null
  aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" > "$OUT/oidc-provider.json"
  echo "Đã tạo OIDC provider $OIDC_HOST"
fi
jq -e '.ClientIDList == ["sts.amazonaws.com"]' "$OUT/oidc-provider.json" > /dev/null \
  || { echo "OIDC provider có client ID khác sts.amazonaws.com – kiểm tra lại" >&2; exit 1; }

if aws iam get-role --role-name "$ROLE" > /dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "file://$OUT/trust.json"
  echo "Role $ROLE đã có – cập nhật trust policy"
else
  aws iam create-role --role-name "$ROLE" \
    --description "GitHub Actions publish (main): push ECR podinfo + Managed Signing (devsecops lab)" \
    --assume-role-policy-document "file://$OUT/trust.json" --max-session-duration 3600 > /dev/null
  echo "Đã tạo role $ROLE"
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name publisher-ecr-sign --policy-document "file://$OUT/policy.json"
aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyName' --output json > "$OUT/attached.json"
[ "$(jq length "$OUT/attached.json")" = 0 ] || { echo "Role có managed policy gắn thêm – kiểm tra lại" >&2; exit 1; }
aws iam get-role --role-name "$ROLE" --query 'Role.{name:RoleName,maxSession:MaxSessionDuration,arn:Arn}' --output table | mask

# Bản che account ID để đưa vào docs/evidence
for f in trust policy oidc-provider; do mask < "$OUT/$f.json" > "$OUT/$f.masked.json"; done
echo "Bằng chứng: $OUT (dùng các file *.masked.json khi đưa vào docs/evidence)"
