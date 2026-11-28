#!/usr/bin/env bash
# Lệnh demo buổi bảo vệ (kế hoạch mục 16.1; lời dẫn: docs/report/phu-luc-b-kich-ban-demo.md). Chạy trên WSL.
#   bash scripts/demo.sh check         # điều kiện trước demo (credential, extension, policy)
#   bash scripts/demo.sh tc01          # Pod đang chạy đúng digest + /version + release.json
#   bash scripts/demo.sh tc04          # Pod dùng image CHƯA KÝ (đúng repo + digest) → Policy 2 từ chối
#   bash scripts/demo.sh tc05          # Pod dùng image SAI NGUỒN (ghcr.io, digest thật) → Policy 1 từ chối
#   bash scripts/demo.sh tc06          # Pod dùng image ký bởi PROFILE B → Policy 2 từ chối (sai danh tính)
#   bash scripts/demo.sh trace [pod]   # truy vết ngược: Pod → digest → tag ECR + chữ ký → run, commit
# Chỉ tạo/xóa Pod thử trong namespace demo; không sửa policy, AWS hay GitHub.
# Account ID được che trên màn hình (đặt DEMO_MASK=0 để tắt).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh > /dev/null || exit 1
set -a; source reports/spike/fixtures.env; set +a
REPO_URL=https://github.com/duy1504/devsecops-project
R=reports/demo/rendered; mkdir -p "$R"
mask() { if [ "${DEMO_MASK:-1}" = 1 ]; then sed -u -E "s/${AWS_ACCOUNT_ID}/<ACCOUNT_ID>/g"; else cat; fi; }
say()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
render() { envsubst '${ECR_IMAGE} ${D_SIGNED} ${D_UNSIGNED} ${D_WRONGSIGNER}' \
  < "tests/admission/$1.template.yaml" > "$R/$1.yaml"; echo "$R/$1.yaml"; }

creds_ok() {  # credential verifier còn ≥ 5 phút; nếu không, deny của TC04/TC06 sẽ do lỗi vận hành chứ không do chữ ký
  local exp; exp=$(kubectl -n kyverno-notation-aws get secret verifier-aws-credentials \
    -o jsonpath='{.metadata.annotations.devsecops/expires}' 2>/dev/null)
  [ -n "$exp" ] && [ "$(date -u -d "$exp" +%s)" -gt "$(( $(date -u +%s) + 300 ))" ] && return 0
  echo "Credential verifier hết hạn/sắp hết ($exp) → chạy: bash scripts/refresh-lab-credentials.sh" >&2
  return 1
}

try_create() {  # try_create <tên manifest>: in image, chạy kubectl create, in stderr + exit code
  local f; f=$(render "$1")
  kubectl -n demo delete pod "$1" --ignore-not-found --wait=true > /dev/null 2>&1
  echo "\$ kubectl create -f $f"
  grep -E '^\s+image:' "$f" | sed 's/^ */  /' | mask
  kubectl create -f "$f" 2>&1 | mask
  local rc=${PIPESTATUS[0]}
  echo "exit code: $rc"
  [ "$rc" = 0 ] && kubectl -n demo delete pod "$1" --wait=false > /dev/null 2>&1
  return 0
}

case "${1:-}" in
  check)
    say "Credential verifier"; creds_ok && echo "còn hạn: $(kubectl -n kyverno-notation-aws get secret verifier-aws-credentials -o jsonpath='{.metadata.annotations.devsecops/expires}')"
    say "Extension + policy"
    kubectl -n kyverno-notation-aws get deploy kyverno-notation-aws
    kubectl get validatingpolicy allowed-image 2>/dev/null
    kubectl get clusterpolicy verify-signer 2>/dev/null
    say "Workload"; kubectl -n app get deploy podinfo
    echo; echo "Kiểm tra đầy đủ: bash scripts/preflight.sh" ;;
  tc01)
    say "TC01 · Pod trong namespace app chạy image phát hành (theo digest)"
    kubectl -n app get pods -l app=podinfo \
      -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,IMAGE:.spec.containers[0].image' | mask
    say "Ứng dụng trả lời (qua API server, không port-forward)"
    kubectl get --raw /api/v1/namespaces/app/services/podinfo:9898/proxy/version; echo
    rel=$(ls -t reports/release/*/release.json 2>/dev/null | head -1)
    if [ -n "$rel" ]; then
      say "Hồ sơ phát hành: $rel"
      jq '{commit_sha, workflow_run_id, run_attempt, image_tag, image_digest, signing_status,
           critical_count, gate_result, sbom_sha256}' "$rel"
    fi ;;
  tc04)
    creds_ok || exit 1
    say "TC04 · image CHƯA KÝ, đúng repository + digest → Policy 1 cho qua, Policy 2 phải từ chối"
    try_create tc04-unsigned ;;
  tc05)
    say "TC05 · image podinfo UPSTREAM (ghcr.io), digest thật → Policy 1 phải từ chối vì sai nguồn"
    try_create tc05-wrong-source ;;
  tc06)
    creds_ok || exit 1
    say "TC06 · image CÓ chữ ký nhưng của profile B (không được tin) → Policy 2 phải từ chối"
    try_create tc06-wrong-signer ;;
  trace)
    pod=${2:-$(kubectl -n app get pods -l app=podinfo -o jsonpath='{.items[0].metadata.name}')}
    img=$(kubectl -n app get pod "$pod" -o jsonpath='{.status.containerStatuses[0].imageID}')
    dig=${img##*@}
    [[ "$dig" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "Không đọc được digest của Pod $pod ($img)" >&2; exit 1; }
    say "1. Pod $pod đang chạy"; echo "$img" | mask
    say "2. ECR: tag của digest này"
    tags=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" --image-ids imageDigest="$dig" \
      --query 'imageDetails[0].imageTags' --output text)
    echo "$tags"
    tag=$(tr '\t' '\n' <<< "$tags" | grep '^sha-' | head -1)
    [[ "$tag" =~ ^sha-([0-9a-f]{12})-run-([0-9]+)-([0-9]+)$ ]] || { echo "Digest không mang tag phát hành sha-…" >&2; exit 1; }
    c=${BASH_REMATCH[1]} run=${BASH_REMATCH[2]} att=${BASH_REMATCH[3]}
    say "3. Chữ ký của digest"
    aws ecr describe-image-signing-status --repository-name "$ECR_REPOSITORY" --image-id imageDigest="$dig" \
      --query 'signingStatuses[].{status:status,profile:signingProfileArn}' --output table | mask
    say "4. Run và commit nguồn"
    echo "commit : $c   → $REPO_URL/commit/$c"
    echo "run    : $run (attempt $att) → $REPO_URL/actions/runs/$run"
    echo "SBOM + báo cáo CVE: artifact security-reports-$run-$att của run đó"
    rel=reports/release/$run/release.json
    if [ -f "$rel" ]; then
      say "5. Đối chiếu với release.json của run"
      jq --arg d "$dig" '{digest_khop: (.image_digest == $d), commit_sha, sbom_sha256, vulnerability_report_sha256}' "$rel"
    fi ;;
  *)
    sed -n '2,9p' "$0"; exit 2 ;;
esac
