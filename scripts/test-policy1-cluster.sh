#!/usr/bin/env bash
# Chạy các ca Policy 1 trên cụm, lưu bằng chứng (stderr + exit code + event + log) vào reports/admission/<thời điểm>/.
# Kế hoạch mục 11.5, 12. Bằng chứng deny KHÔNG dựa vào PolicyReport hay ImagePullBackOff.
# Cần: ECR_IMAGE, APP_DIGEST (sha256:<64 hex>). Trước khi có ECR thật có thể dùng giá trị giả cho logic admission.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
: "${ECR_IMAGE:?Cần ECR_IMAGE}"; : "${APP_DIGEST:?Cần APP_DIGEST=sha256:<64 hex>}"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=reports/admission/$TS; mkdir -p "$OUT"
R=$OUT/rendered; mkdir -p "$R"
for f in tests/admission/*.template.yaml; do
  envsubst '${ECR_IMAGE} ${APP_DIGEST}' < "$f" > "$R/$(basename "${f%.template.yaml}").yaml"
done
fail=0
summary() { printf '%-28s %-8s %-6s %s\n' "$1" "$2" "$3" "$4" | tee -a "$OUT/summary.txt"; }
run() {  # run <id> <mong đợi: deny|allow> <kubectl args...>
  local id=$1 want=$2; shift 2
  local start; start=$(date -u +%FT%TZ)
  kubectl "$@" > "$OUT/$id.stdout" 2> "$OUT/$id.stderr"; local rc=$?
  echo "$rc" > "$OUT/$id.exit"
  local got=allow; [ $rc -ne 0 ] && got=deny
  local ok=OK; [ "$got" = "$want" ] || { ok=SAI; fail=1; }
  summary "$id" "$want" "$ok" "exit=$rc $(head -c 160 "$OUT/$id.stderr" | tr '\n' ' ')"
  echo "$start" > "$OUT/$id.time"
}
echo "ECR_IMAGE=$ECR_IMAGE  APP_DIGEST=$APP_DIGEST  ($TS)" | tee "$OUT/summary.txt"
printf '%-28s %-8s %-6s %s\n' "CA" "MONG ĐỢI" "KQ" "CHI TIẾT" | tee -a "$OUT/summary.txt"

run tc05-wrong-source   deny  create -f "$R/tc05-wrong-source.yaml"
run tc07-tag-only       deny  create -f "$R/tc07-tag-only.yaml"
run tc08-bad-init       deny  create -f "$R/tc08-bad-init.yaml"
run control-allowed     allow create --dry-run=server -f "$R/control-allowed.yaml"
# Ngoài phạm vi policy (namespace default) → không bị policy chặn
run out-of-scope-ns     allow run out-of-scope --image=ghcr.io/stefanprodan/podinfo:6.17.0 -n default --dry-run=server
# Deployment vi phạm: autogen của ValidatingPolicy quyết định chặn ngay ở Deployment hay ở event FailedCreate
kubectl -n demo delete deploy tc-deploy-wrong --ignore-not-found >/dev/null 2>&1
kubectl -n demo create deployment tc-deploy-wrong --image=ghcr.io/stefanprodan/podinfo:6.17.0 \
  > "$OUT/deploy-wrong.stdout" 2> "$OUT/deploy-wrong.stderr"; echo $? > "$OUT/deploy-wrong.exit"
sleep 8
kubectl -n demo get events --field-selector reason=FailedCreate -o custom-columns=TIME:.lastTimestamp,OBJ:.involvedObject.name,MSG:.message \
  > "$OUT/deploy-wrong.events" 2>&1
kubectl -n demo get pods -l app=tc-deploy-wrong -o name > "$OUT/deploy-wrong.pods" 2>&1
# Autogen: nếu policy tự sinh rule cho Deployment thì apply bị từ chối ngay (exit≠0), không có FailedCreate
dexit=$(cat "$OUT/deploy-wrong.exit"); dok=OK; [ "$dexit" -ne 0 ] || { dok=SAI; fail=1; }
summary "deployment-vi-pham" "deny" "$dok" "apply exit=$dexit; FailedCreate=$(grep -c tc-deploy-wrong "$OUT/deploy-wrong.events"); pods=$(wc -l < "$OUT/deploy-wrong.pods")"
kubectl -n demo delete deploy tc-deploy-wrong --ignore-not-found >/dev/null 2>&1

# Kyverno ghi event PolicyViolation "fail (blocked)" lên đối tượng policy (namespace default), không lên namespace của Pod
sleep 3
kubectl get events -A --field-selector reason=PolicyViolation --sort-by=.lastTimestamp \
  -o custom-columns=TIME:.lastTimestamp,NS:.metadata.namespace,KIND:.involvedObject.kind,POLICY:.involvedObject.name,MSG:.message \
  > "$OUT/events-policyviolation.txt" 2>&1
kubectl -n demo get events --sort-by=.lastTimestamp > "$OUT/events-demo.txt" 2>&1
# Log mức --v=2 mặc định không ghi từng lần deny; vẫn lưu để đối chiếu mốc thời gian
kubectl -n kyverno logs deploy/kyverno-admission-controller --since=5m > "$OUT/kyverno-admission.log" 2>&1
kubectl get validatingpolicy allowed-image -o yaml > "$OUT/policy.yaml" 2>&1
kubectl get validatingwebhookconfigurations -o yaml > "$OUT/webhooks.yaml" 2>&1
echo "Bằng chứng: $OUT"
exit $fail
