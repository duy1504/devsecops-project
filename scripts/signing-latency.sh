#!/usr/bin/env bash
# Độ trễ ký của ECR Managed Signing (kế hoạch mục 12.5), không phụ thuộc chu kỳ poll của wait-signature.sh:
#   độ trễ = imagePushedAt(artifact chữ ký) − imagePushedAt(image)   (thời điểm ECR ghi nhận, độ phân giải theo API)
# Kèm signingTime trong chữ ký Notation và profile đã ký. Chỉ đọc. Chạy trên WSL: bash scripts/signing-latency.sh
# Phạm vi: image tag sha-* (do pipeline phát hành) và signed-baseline (spike). Fixture ký tay (profile B) liệt kê để đối chiếu.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
mask() { sed -E "s/${AWS_ACCOUNT_ID}/<ACCOUNT_ID>/g"; }
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/signing-latency/$TS; mkdir -p "$OUT"
export NOTATION_USERNAME=AWS NOTATION_PASSWORD; NOTATION_PASSWORD=$(aws ecr get-login-password)
ms() { date -u -d "$1" +%s%3N; }

aws ecr describe-images --repository-name "$ECR_REPOSITORY" --filter tagStatus=TAGGED --output json \
  | jq -r '.imageDetails[] | select(any(.imageTags[]; startswith("sha-") or . == "signed-baseline" or . == "wrong-signer-baseline"))
           | [(.imageTags | map(select(startswith("sha256-") | not)) | join(";")), .imageDigest, .imagePushedAt] | @tsv' \
  | sort -t$'\t' -k3 > "$OUT/images.tsv"

echo "tag,image_digest,image_pushed_at,signature_digest,signature_pushed_at,signing_time,profile,latency_ms" > "$OUT/latency.csv"
while IFS=$'\t' read -r tag dig pushed; do
  for sig in $(notation ls "${ECR_IMAGE}@${dig}" 2>/dev/null | grep -oE '^ +[└├]── sha256:[0-9a-f]{64}' | grep -oE 'sha256:[0-9a-f]{64}'); do
    spushed=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageDigest="$sig" \
      --query 'imageDetails[0].imagePushedAt' --output text)
    info=$(notation inspect "${ECR_IMAGE}@${dig}" -o json 2>/dev/null | jq -r --arg s "$sig" '
      .Signatures[] | select(.digest == $s) | [.signedAttributes.signingTime,
        (.signedAttributes["com.amazonaws.signer.signingProfileVersion"] | split("/signing-profiles/")[1])] | @tsv')
    stime=$(cut -f1 <<< "$info"); prof=$(cut -f2 <<< "$info")
    lat=$(( $(ms "$spushed") - $(ms "$pushed") ))
    echo "$tag,$dig,$pushed,$sig,$spushed,$stime,$prof,$lat" >> "$OUT/latency.csv"
  done
done < "$OUT/images.tsv"
unset NOTATION_PASSWORD
mask < "$OUT/latency.csv" > "$OUT/latency.masked.csv" && mv "$OUT/latency.masked.csv" "$OUT/latency.csv"
column -s, -t < <(cut -d, -f1,3,5,6,7,8 "$OUT/latency.csv")
echo
awk -F, 'NR>1 && $7 ~ /^podinfo_signing_profile\// { n++; s+=$8; if(!mn||$8<mn) mn=$8; if($8>mx) mx=$8 }
  END { if (n) printf "Managed Signing (profile chính): n=%d, min=%d ms, tb=%.0f ms, max=%d ms\n", n, mn, s/n, mx }' "$OUT/latency.csv"
echo "Chi tiết: $OUT/latency.csv"
