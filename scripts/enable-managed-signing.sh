#!/usr/bin/env bash
# Spike bước 5 (kế hoạch mục 6.1, 8.2, 8.3): tạo signing profile chính + bật ECR Managed Signing cho đúng repo podinfo.
# - Filter là đúng tên repo, không có '*' (WILDCARD_MATCH không có '*' = khớp chính xác).
# - Profile B không được nằm trong rule.
# - Dừng nếu registry đã có signing configuration (phải hợp nhất bằng tay, không ghi đè).
# - Sau khi bật: kiểm lại hai fixture KHÔNG bị ký thêm.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/spike/signing-$TS; mkdir -p "$OUT"
log() { echo "[$(date -u +%T)] $*" | tee -a "$OUT/run.log"; }

# 1. Profile chính
if ! aws signer get-signing-profile --profile-name "$SIGNING_PROFILE" > /dev/null 2>&1; then
  aws signer put-signing-profile --profile-name "$SIGNING_PROFILE" \
    --platform-id Notation-OCI-SHA384-ECDSA \
    --signature-validity-period value=12,type=MONTHS > /dev/null
  log "Đã tạo profile chính $SIGNING_PROFILE"
fi
aws signer get-signing-profile --profile-name "$SIGNING_PROFILE" --output json \
  --query '{name:profileName,status:status,platform:platformId,validity:signatureValidityPeriod,profileVersion:profileVersion}' \
  > "$OUT/profile-main.json"

# 2. Đọc cấu hình cũ TRƯỚC khi ghi
if aws ecr get-signing-configuration > "$OUT/signing-config-before.json" 2> "$OUT/signing-config-before.err"; then
  echo "DỪNG: registry đã có signing configuration (xem $OUT/signing-config-before.json) – cần hợp nhất, không ghi đè." >&2
  exit 1
fi
grep -q SigningConfigurationNotFoundException "$OUT/signing-config-before.err" \
  || { cat "$OUT/signing-config-before.err" >&2; exit 1; }

# 3. Render + kiểm tra cấu hình trước khi ghi
envsubst '${SIGNING_PROFILE_ARN} ${ECR_REPOSITORY}' < infra/aws/signing-config.template.json > "$OUT/signing-config.json"
jq -e --arg repo "$ECR_REPOSITORY" --arg arn "$SIGNING_PROFILE_ARN" --arg wrong "$WRONG_SIGNING_PROFILE_ARN" '
  (.rules | length == 1)
  and (.rules[0].signingProfileArn == $arn and .rules[0].signingProfileArn != $wrong)
  and (.rules[0].repositoryFilters == [{filter: $repo, filterType: "WILDCARD_MATCH"}])
  and ($repo | contains("*") | not)' "$OUT/signing-config.json" > /dev/null \
  || { echo "Cấu hình ký không đúng ràng buộc (filter/profile)" >&2; exit 1; }
aws ecr put-signing-configuration --signing-configuration "file://$OUT/signing-config.json" > "$OUT/put-signing-configuration.json"
aws ecr get-signing-configuration > "$OUT/signing-config-after.json"
log "Đã bật Managed Signing: rule duy nhất, filter '$ECR_REPOSITORY', profile $SIGNING_PROFILE"

# 4. Fixture không bị ký thêm
source reports/spike/fixtures.env
export NOTATION_USERNAME=AWS
NOTATION_PASSWORD="$(aws ecr get-login-password)"; export NOTATION_PASSWORD
fail=0
for pair in "unsigned:$D_UNSIGNED:0" "wrong-signer:$D_WRONGSIGNER:1"; do
  IFS=: read -r name alg hex want <<< "$pair"
  notation ls "$ECR_IMAGE@$alg:$hex" > "$OUT/notation-ls-$name-after.txt" 2>&1
  n=$(grep -cE '^ +[└├]── sha256:' "$OUT/notation-ls-$name-after.txt" || true)
  aws ecr describe-image-signing-status --repository-name "$ECR_REPOSITORY" --image-id imageDigest="$alg:$hex" \
    --output json > "$OUT/signing-status-$name.json" 2>&1 || true
  s="OK"; [ "$n" = "$want" ] || { s="SAI"; fail=1; }
  log "Fixture $name: $n chữ ký (mong đợi $want) $s"
done
echo "KẾT QUẢ: $([ $fail = 0 ] && echo ĐẠT || echo KHÔNG ĐẠT)" | tee -a "$OUT/run.log"
echo "Bằng chứng: $OUT"
exit $fail
