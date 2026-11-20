#!/usr/bin/env bash
# Chờ ECR Managed Signing ký xong ĐÚNG profile mong đợi (kế hoạch mục 8.6).
# Chỉ COMPLETE của đúng profile mới đạt; FAILED, thiếu status, lỗi API hay hết giờ đều fail.
# COMPLETE chỉ xác nhận chữ ký đã được TẠO; vẫn phải xác minh bằng Notation/admission.
set -euo pipefail
: "${AWS_REGION:?}" "${ECR_REPOSITORY:?}" "${IMAGE_DIGEST:?}" "${SIGNING_PROFILE_ARN:?}"
TIMEOUT=${TIMEOUT:-150}; INTERVAL=${INTERVAL:-5}; elapsed=0
RELEASE_DIR=${RELEASE_DIR:-release}
mkdir -p "$RELEASE_DIR"

while (( elapsed < TIMEOUT )); do
  aws ecr describe-image-signing-status --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" --image-id imageDigest="$IMAGE_DIGEST" \
    --output json > "$RELEASE_DIR/signing-status.json"

  status=$(jq -r --arg arn "$SIGNING_PROFILE_ARN" \
    '[.signingStatuses[]? | select(.signingProfileArn == $arn) | .status][0] // "MISSING"' \
    "$RELEASE_DIR/signing-status.json")

  case "$status" in
    COMPLETE)    echo "Signed by expected profile after ~${elapsed}s"; exit 0 ;;
    FAILED)      jq '.signingStatuses' "$RELEASE_DIR/signing-status.json"; exit 1 ;;
    IN_PROGRESS|MISSING) sleep "$INTERVAL"; elapsed=$((elapsed + INTERVAL)) ;;
    *)           echo "Unknown status: $status"; exit 1 ;;
  esac
done
echo "Timeout waiting for signature"; exit 1
