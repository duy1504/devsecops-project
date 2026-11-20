#!/usr/bin/env bash
# Xác minh chữ ký bằng Notation CLI theo trust policy CHỈ tin profile chính (kế hoạch mục 6.1 bước 4, 7; mục 8.7).
#   D_UNSIGNED, D_WRONGSIGNER  → phải THẤT BẠI (mặc định đọc reports/spike/fixtures.env)
#   D_SIGNED (nếu đặt)         → phải THÀNH CÔNG
# Đối chứng: tạm tin profile B → D_WRONGSIGNER phải THÀNH CÔNG, chứng minh lần thất bại ở trên là do sai
# danh tính ký chứ không do trust store/cấu hình hỏng. Kết thúc luôn khôi phục trust policy chính.
# Không dùng level skip/permissive; trust store chỉ chứa root AWS Signer đã ghim fingerprint.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh || exit 1
[ -f reports/spike/fixtures.env ] && source reports/spike/fixtures.env
: "${D_UNSIGNED:?Thiếu D_UNSIGNED}" "${D_WRONGSIGNER:?Thiếu D_WRONGSIGNER}"
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/spike/verify-$TS; mkdir -p "$OUT"
log() { echo "[$(date -u +%T)] $*" | tee -a "$OUT/run.log"; }

# 1. Trust store: root AWS Signer, ghim fingerprint (docs/versions.md)
ROOT_URL=https://d2hvyiie56hcat.cloudfront.net/aws-signer-notation-root.cert
ROOT_FP=90:A8:7D:05:43:C3:F0:94:DB:FF:95:89:B6:64:9A:FF:E2:F3:D6:E0:F3:08:79:9B:E2:25:84:61:C6:86:47:3F
TRUST_STORE=aws-signer-ts
curl -fsSL --retry 3 "$ROOT_URL" -o "$OUT/aws-signer-notation-root.cert" || { echo "Không tải được root cert" >&2; exit 1; }
fp=$(openssl x509 -in "$OUT/aws-signer-notation-root.cert" -noout -fingerprint -sha256 | cut -d= -f2)
openssl x509 -in "$OUT/aws-signer-notation-root.cert" -noout -subject -issuer -dates > "$OUT/root-cert.txt"
echo "sha256 fingerprint=$fp" >> "$OUT/root-cert.txt"
[ "$fp" = "$ROOT_FP" ] || { echo "Fingerprint root cert KHÔNG khớp giá trị đã ghim: $fp" >&2; exit 1; }
log "Root AWS Signer khớp fingerprint đã ghim"
if ! notation cert ls --type signingAuthority --store "$TRUST_STORE" 2>/dev/null | grep -q aws-signer-notation-root; then
  notation cert add --type signingAuthority --store "$TRUST_STORE" "$OUT/aws-signer-notation-root.cert" >> "$OUT/run.log" 2>&1
  log "Đã thêm root cert vào trust store $TRUST_STORE"
fi
notation cert ls > "$OUT/notation-cert-ls.txt" 2>&1

# 2. Trust policy: đúng repo, strict, chỉ tin profile chính
policy() {  # <tên> <identity ARN> <file>
  jq -n --arg scope "$ECR_IMAGE" --arg id "$2" --arg name "$1" --arg ts "$TRUST_STORE" \
    '{version: "1.0", trustPolicies: [{name: $name, registryScopes: [$scope],
      signatureVerification: {level: "strict"}, trustStores: ["signingAuthority:" + $ts],
      trustedIdentities: [$id]}]}' > "$3"
}
policy podinfo-aws-signer "$SIGNING_PROFILE_ARN" "$OUT/trust-policy.json"
policy control-trust-profile-b "$WRONG_SIGNING_PROFILE_ARN" "$OUT/trust-policy-control.json"
restore() { notation policy import --force "$OUT/trust-policy.json" > /dev/null 2>&1; }
trap restore EXIT
restore
notation policy show > "$OUT/notation-policy-show.json" 2>&1
log "Trust policy: chỉ tin $SIGNING_PROFILE"

export NOTATION_USERNAME=AWS
NOTATION_PASSWORD="$(aws ecr get-login-password)"; export NOTATION_PASSWORD

fail=0
check() {  # <id> <pass|fail> <digest>
  local id=$1 want=$2 ref="$ECR_IMAGE@$3" rc got ok
  # -v: ghi lý do từng chữ ký thất bại (vd. plugin báo sai danh tính), không chỉ thông báo chung
  notation verify -v "$ref" > "$OUT/$id.stdout" 2> "$OUT/$id.stderr"; rc=$?
  echo "$rc" > "$OUT/$id.exit"
  got=pass; [ $rc -ne 0 ] && got=fail
  ok=OK; [ "$got" = "$want" ] || { ok=SAI; fail=1; }
  printf '%-32s mong đợi=%-4s thực tế=%-4s exit=%-3s %s | %s\n' "$id" "$want" "$got" "$rc" "$ok" \
    "$(cat "$OUT/$id.stderr" "$OUT/$id.stdout" | grep -oE 'failed with reason "[^"]*"|no signature is associated|Successfully verified signature|Error: [^,]*' \
       | sort -u | tr '\n' ' ')" | tee -a "$OUT/summary.txt"
}
check unsigned          fail "$D_UNSIGNED"
check wrong-signer      fail "$D_WRONGSIGNER"
[ -n "${D_SIGNED:-}" ] && check signed pass "$D_SIGNED"

# 3. Đối chứng: tạm tin profile B
notation policy import --force "$OUT/trust-policy-control.json" > /dev/null 2>&1
check control-wrong-signer-trusted-b pass "$D_WRONGSIGNER"
restore
notation policy show > "$OUT/notation-policy-after.json" 2>&1
cmp -s <(jq -S . "$OUT/notation-policy-after.json") <(jq -S . "$OUT/trust-policy.json") \
  && log "Đã khôi phục trust policy chính" || { log "KHÔNG khôi phục được trust policy chính"; fail=1; }

echo "KẾT QUẢ: $([ $fail = 0 ] && echo ĐẠT || echo KHÔNG ĐẠT)" | tee -a "$OUT/summary.txt"
echo "Bằng chứng: $OUT"
exit $fail
