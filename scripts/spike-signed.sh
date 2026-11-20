#!/usr/bin/env bash
# Spike bước 6–7 (kế hoạch mục 6.1): build image thứ ba khác nội dung → push → Managed Signing tự ký
# → chờ COMPLETE đúng profile → notation verify phải thành công (và 2 fixture vẫn bị từ chối).
# Không có lệnh ký thủ công trong script này.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
TAG=${TAG:-signed-baseline}
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/spike/signed-$TS; mkdir -p "$OUT"
log() { echo "[$(date -u +%T)] $*" | tee -a "$OUT/run.log"; }

# Chỉ chạy khi Managed Signing đã bật với đúng profile
aws ecr get-signing-configuration > "$OUT/signing-config.json"
jq -e --arg arn "$SIGNING_PROFILE_ARN" '[.signingConfiguration.rules[].signingProfileArn] | index($arn) != null' \
  "$OUT/signing-config.json" > /dev/null || { echo "Managed Signing chưa bật với $SIGNING_PROFILE" >&2; exit 1; }

DOCKER_CONFIG="$(mktemp -d)"; export DOCKER_CONFIG; chmod 700 "$DOCKER_CONFIG"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
echo '{}' > "$DOCKER_CONFIG/config.json"
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null 2>&1

REF="local/podinfo-fixture:$TAG"
if [ -z "$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$TAG" \
          --query 'imageDetails[0].imageDigest' --output text 2> /dev/null || true)" ]; then
  log "Build $TAG (nhãn demo.fixture=$TAG)"
  docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
    --label "demo.fixture=$TAG" -t "$REF" --load . > "$OUT/build.log" 2>&1
  trivy image --quiet --db-repository ghcr.io/aquasecurity/trivy-db:2 --scanners vuln \
    --severity CRITICAL --exit-code 1 --format json -o "$OUT/trivy.json" "$REF"
  log "Trivy: 0 CRITICAL"
  docker tag "$REF" "$ECR_IMAGE:$TAG"
  t0=$(date +%s)
  docker push "$ECR_IMAGE:$TAG" > "$OUT/push.log" 2>&1
  log "Đã push $TAG"
else
  log "$TAG đã có trong ECR – không push lại"; t0=$(date +%s)
fi
D_SIGNED=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$TAG" \
  --query 'imageDetails[0].imageDigest' --output text)
log "D_signed = $D_SIGNED"

IMAGE_DIGEST="$D_SIGNED" RELEASE_DIR="$OUT" bash scripts/wait-signature.sh | tee -a "$OUT/run.log"
log "Thời gian từ lúc push xong tới COMPLETE: $(( $(date +%s) - t0 ))s (gồm chu kỳ poll 5s)"

export NOTATION_USERNAME=AWS
NOTATION_PASSWORD="$(aws ecr get-login-password)"; export NOTATION_PASSWORD
notation ls "$ECR_IMAGE@$D_SIGNED" > "$OUT/notation-ls-signed.txt" 2>&1
notation inspect -o json "$ECR_IMAGE@$D_SIGNED" > "$OUT/notation-inspect-signed.json" 2>&1
grep -q "signing-profiles/$SIGNING_PROFILE/" "$OUT/notation-inspect-signed.json" \
  && log "Chữ ký thuộc profile chính $SIGNING_PROFILE" \
  || { log "Không thấy chữ ký của profile chính"; exit 1; }
unset NOTATION_PASSWORD

grep -v '^D_SIGNED=' reports/spike/fixtures.env > "$OUT/fixtures.env.tmp" || true
echo "D_SIGNED=$D_SIGNED" >> "$OUT/fixtures.env.tmp"
mv "$OUT/fixtures.env.tmp" reports/spike/fixtures.env

log "Notation verify: signed phải pass, 2 fixture phải fail"
D_SIGNED="$D_SIGNED" bash scripts/notation-verify.sh | tee -a "$OUT/run.log"
echo "Bằng chứng: $OUT"
