#!/usr/bin/env bash
# Spike bước 2–3 (kế hoạch mục 6.1): tạo fixture D_unsigned và D_wrongsigner TRƯỚC khi bật Managed Signing.
#  - unsigned-baseline     : push, KHÔNG ký                     → TC04
#  - wrong-signer-baseline : push, ký tay bằng profile B          → TC06
# Từ chối chạy nếu registry đã có signing configuration (image push lên sẽ bị ký tự động).
# Chạy lại an toàn: tag đã có trong ECR thì không build/push lại; đã có chữ ký thì không ký lại.
# Bằng chứng: reports/spike/fixtures-<thời điểm>/ (không commit; chọn lọc + che account ID khi đưa vào docs/evidence).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/spike/fixtures-$TS; mkdir -p "$OUT"
log() { echo "[$(date -u +%T)] $*" | tee -a "$OUT/run.log"; }

# 0. Điều kiện an toàn: chưa có signing configuration
if aws ecr get-signing-configuration > "$OUT/signing-config-before.json" 2> "$OUT/signing-config-before.err"; then
  echo "DỪNG: registry đã có signing configuration → fixture push lên sẽ bị ký tự động." >&2; exit 1
fi
grep -q SigningConfigurationNotFoundException "$OUT/signing-config-before.err" \
  || { cat "$OUT/signing-config-before.err" >&2; exit 1; }
log "Registry chưa có signing configuration – đúng điều kiện tạo fixture"
# Token ECR quá dài cho Windows Credential Manager (docker-credential-desktop: "The stub received bad data")
# → dùng cấu hình Docker tạm (quyền 700, xóa khi kết thúc); token ECR tự hết hạn sau 12 giờ.
DOCKER_CONFIG="$(mktemp -d)"; export DOCKER_CONFIG; chmod 700 "$DOCKER_CONFIG"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
echo '{}' > "$DOCKER_CONFIG/config.json"
aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY" > /dev/null
log "docker login ECR: OK"

digest_of() {  # <tag> → digest, rỗng nếu chưa có
  aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageTag="$1" \
    --query 'imageDetails[0].imageDigest' --output text 2> /dev/null || true
}

build_scan_push() {  # <tag>
  local tag=$1 ref="local/podinfo-fixture:$1" d
  d=$(digest_of "$tag")
  if [ -n "$d" ]; then log "$tag đã có trong ECR ($d) – không push lại"; echo "$d" > "$OUT/$tag.digest"; return; fi
  log "Build $tag (nhãn demo.fixture=$tag)"
  docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
    --label "demo.fixture=$tag" -t "$ref" --load . > "$OUT/build-$tag.log" 2>&1
  log "Trivy gate 0 CRITICAL cho $tag"
  trivy image --quiet --db-repository ghcr.io/aquasecurity/trivy-db:2 --scanners vuln \
    --severity CRITICAL --exit-code 1 --format json -o "$OUT/trivy-$tag.json" "$ref"
  log "Trivy $tag: 0 CRITICAL"
  docker tag "$ref" "$ECR_IMAGE:$tag"
  docker push "$ECR_IMAGE:$tag" > "$OUT/push-$tag.log" 2>&1
  d=$(digest_of "$tag")
  [ -n "$d" ] || { echo "Không lấy được digest của $tag" >&2; exit 1; }
  echo "$d" > "$OUT/$tag.digest"
  log "Đã push $tag → $d"
}

build_scan_push unsigned-baseline
build_scan_push wrong-signer-baseline
D_UNSIGNED=$(cat "$OUT/unsigned-baseline.digest")
D_WRONGSIGNER=$(cat "$OUT/wrong-signer-baseline.digest")
[ "$D_UNSIGNED" != "$D_WRONGSIGNER" ] || { echo "Hai fixture trùng digest" >&2; exit 1; }
aws ecr describe-images --repository-name "$ECR_REPOSITORY" --output json \
  --query 'imageDetails[].{tags:imageTags,digest:imageDigest,mediaType:imageManifestMediaType,bytes:imageSizeInBytes}' \
  > "$OUT/ecr-images.json"

# Profile B (chỉ cho fixture TC06; không nằm trong signing rule hay trustedIdentities)
if ! aws signer get-signing-profile --profile-name "$WRONG_SIGNING_PROFILE" > /dev/null 2>&1; then
  aws signer put-signing-profile --profile-name "$WRONG_SIGNING_PROFILE" \
    --platform-id Notation-OCI-SHA384-ECDSA \
    --signature-validity-period value=12,type=MONTHS > /dev/null
  log "Đã tạo profile B $WRONG_SIGNING_PROFILE"
fi
aws signer get-signing-profile --profile-name "$WRONG_SIGNING_PROFILE" --output json \
  --query '{name:profileName,status:status,platform:platformId,validity:signatureValidityPeriod,profileVersion:profileVersion}' \
  > "$OUT/profile-b.json"

# Notation: credential ECR qua biến môi trường, không lưu xuống đĩa
export NOTATION_USERNAME=AWS
NOTATION_PASSWORD="$(aws ecr get-login-password)"; export NOTATION_PASSWORD
count_sigs() {  # <digest> → số chữ ký Notation
  notation ls "$ECR_IMAGE@$1" > "$OUT/notation-ls-$2.txt" 2>&1
  grep -cE '^ +[└├]── sha256:' "$OUT/notation-ls-$2.txt" || true
}
n=$(count_sigs "$D_WRONGSIGNER" wrong-signer-before)
if [ "$n" = 0 ]; then
  log "Ký tay D_wrongsigner bằng profile B (chỉ để tạo fixture TC06)"
  notation sign --plugin com.amazonaws.signer.notation.plugin --id "$WRONG_SIGNING_PROFILE_ARN" \
    "$ECR_IMAGE@$D_WRONGSIGNER" > "$OUT/notation-sign.log" 2>&1
else
  log "D_wrongsigner đã có $n chữ ký – không ký lại"
fi

# Kiểm chứng
fail=0
nu=$(count_sigs "$D_UNSIGNED" unsigned)
nw=$(count_sigs "$D_WRONGSIGNER" wrong-signer)
notation inspect -o json "$ECR_IMAGE@$D_WRONGSIGNER" > "$OUT/notation-inspect-wrong-signer.json" 2>&1 || true
by_b=no; grep -q "signing-profiles/$WRONG_SIGNING_PROFILE/" "$OUT/notation-inspect-wrong-signer.json" && by_b=yes
[ "$nu" = 0 ] || fail=1; [ "$nw" = 1 ] || fail=1; [ "$by_b" = yes ] || fail=1
{
  echo "D_UNSIGNED=$D_UNSIGNED"
  echo "D_WRONGSIGNER=$D_WRONGSIGNER"
} > reports/spike/fixtures.env
{
  echo "D_unsigned     $D_UNSIGNED  chữ ký: $nu (mong đợi 0)"
  echo "D_wrongsigner  $D_WRONGSIGNER  chữ ký: $nw (mong đợi 1), của profile B: $by_b"
  echo "KẾT QUẢ: $([ $fail = 0 ] && echo ĐẠT || echo KHÔNG ĐẠT)"
} | tee "$OUT/summary.txt"
echo "Bằng chứng: $OUT"
exit $fail
