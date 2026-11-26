#!/usr/bin/env bash
# Spike bước 9 + TC01/TC04/TC06/TC09 trên kind (kế hoạch mục 6.1, 6.2, 12). Bằng chứng: stderr + exit code + event + log.
# Bằng chứng deny KHÔNG dựa vào PolicyReport hay ImagePullBackOff.
# Cần: Policy 1 (ECR_IMAGE thật) + Policy 2 + extension đã cài; credential verifier còn hạn (refresh-lab-credentials.sh).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh || exit 1
set -a; source reports/spike/fixtures.env; set +a     # export cho envsubst
: "${D_SIGNED:?}" "${D_UNSIGNED:?}" "${D_WRONGSIGNER:?}"
EXT_NS=kyverno-notation-aws
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/admission-p2/$TS; R=$OUT/rendered; mkdir -p "$R"
for f in tc01-signed tc04-unsigned tc06-wrong-signer; do
  envsubst '${ECR_IMAGE} ${D_SIGNED} ${D_UNSIGNED} ${D_WRONGSIGNER}' < "tests/admission/$f.template.yaml" > "$R/$f.yaml"
done
fail=0
summary() { printf '%-30s %-6s %-4s %s\n' "$1" "$2" "$3" "$4" | tee -a "$OUT/summary.txt"; }
run() {  # run <id> <allow|deny> <grep lý do khi deny hoặc '-'> <file>
  local id=$1 want=$2 why=$3 file=$4 rc got ok t0 ms
  kubectl -n demo delete -f "$file" --ignore-not-found --wait=true > /dev/null 2>&1
  date -u +%FT%TZ > "$OUT/$id.time"
  t0=$(date +%s%N)
  kubectl create -f "$file" > "$OUT/$id.stdout" 2> "$OUT/$id.stderr"; rc=$?
  ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  echo "$rc" > "$OUT/$id.exit"
  got=allow; [ $rc -ne 0 ] && got=deny
  ok=OK; [ "$got" = "$want" ] || { ok=SAI; fail=1; }
  if [ "$want" = deny ] && [ "$got" = deny ]; then
    grep -q 'verify-signer' "$OUT/$id.stderr" || { ok=SAI; fail=1; }
    [ "$why" = - ] || grep -qF "$why" "$OUT/$id.stderr" || { ok="SAI(lý do)"; fail=1; }
  fi
  echo "$id,$want,$got,$rc,$ms" >> "$OUT/latency.csv"
  summary "$id" "$want" "$ok" "exit=$rc ${ms}ms $(grep -oE "failed with reason \"[^\"]*\"|no signature is associated[^,]*|connection refused|no endpoints available[^\"]*|dial tcp[^\"]*" "$OUT/$id.stderr" | head -1)"
}
echo "ca,mong_doi,thuc_te,exit,ms" > "$OUT/latency.csv"
echo "Policy 2 trên kind ($TS)" | tee "$OUT/summary.txt"
kubectl get clusterpolicy verify-signer -o yaml > "$OUT/policy-verify-signer.yaml"
kubectl get validatingpolicy allowed-image -o jsonpath='{.spec.validations[0].expression}' > "$OUT/policy-allowed-image.expr"
kubectl get validatingwebhookconfigurations -o custom-columns=NAME:.metadata.name,FAIL:.webhooks[*].failurePolicy > "$OUT/webhooks.txt"

# TC01: hợp lệ → được nhận và Pod chạy thật (pull qua ecr-pull)
run tc01-signed allow - "$R/tc01-signed.yaml"
kubectl -n demo wait pod/tc01-signed --for=condition=Ready --timeout=120s > "$OUT/tc01-ready.txt" 2>&1 \
  && summary tc01-pod-ready allow OK "$(kubectl -n demo get pod tc01-signed -o jsonpath='{.status.phase} image={.status.containerStatuses[0].imageID}')" \
  || { summary tc01-pod-ready allow SAI "$(tail -1 "$OUT/tc01-ready.txt")"; fail=1; }
kubectl -n demo get pod tc01-signed -o wide > "$OUT/tc01-pod.txt" 2>&1
# TC04: chưa ký; TC06: sai người ký
run tc04-unsigned     deny 'no signature is associated'                       "$R/tc04-unsigned.yaml"
run tc06-wrong-signer deny "Signature publisher doesn't match any trusted identities" "$R/tc06-wrong-signer.yaml"

# Lưu log extension TRƯỚC TC09 (scale về 0 sẽ xóa Pod cùng log của các lần deny TC04/TC06)
kubectl -n "$EXT_NS" logs deploy/kyverno-notation-aws --since=10m 2>&1 | sed -E 's/eyJ[A-Za-z0-9._-]{20,}/<JWT>/g' > "$OUT/extension-before-tc09.log"

# TC09: fail-closed – tắt extension → Pod hợp lệ cũng bị chặn; bật lại → qua
kubectl -n demo delete pod tc01-signed --wait=true > /dev/null 2>&1
kubectl -n "$EXT_NS" scale deploy/kyverno-notation-aws --replicas=0 > /dev/null
kubectl -n "$EXT_NS" wait pod -l app=kyverno-notation-aws --for=delete --timeout=60s > /dev/null 2>&1
kubectl -n "$EXT_NS" get pods > "$OUT/tc09-ext-pods-down.txt" 2>&1
run tc09-ext-down-signed deny - "$R/tc01-signed.yaml"
kubectl -n "$EXT_NS" scale deploy/kyverno-notation-aws --replicas=1 > /dev/null
kubectl -n "$EXT_NS" rollout status deploy/kyverno-notation-aws --timeout=120s > /dev/null
sleep 3
run tc09-ext-up-signed allow - "$R/tc01-signed.yaml"
kubectl -n demo delete pod tc01-signed --ignore-not-found > /dev/null 2>&1

# Event + log (lọc phòng hờ chuỗi giống JWT)
sleep 3
kubectl get events -A --field-selector reason=PolicyViolation --sort-by=.lastTimestamp \
  -o custom-columns=TIME:.lastTimestamp,NS:.metadata.namespace,KIND:.involvedObject.kind,POLICY:.involvedObject.name,MSG:.message \
  > "$OUT/events-policyviolation.txt" 2>&1
kubectl -n "$EXT_NS" logs deploy/kyverno-notation-aws --since=10m 2>&1 | sed -E 's/eyJ[A-Za-z0-9._-]{20,}/<JWT>/g' > "$OUT/extension.log"
kubectl -n kyverno logs deploy/kyverno-admission-controller --since=10m 2>&1 | sed -E 's/eyJ[A-Za-z0-9._-]{20,}/<JWT>/g' > "$OUT/kyverno-admission.log"
cat "$OUT/extension-before-tc09.log" "$OUT/extension.log" | grep -c 'Token is authorized' > "$OUT/extension-token-authorized.count" || true
echo "KẾT QUẢ: $([ $fail = 0 ] && echo ĐẠT || echo KHÔNG ĐẠT)" | tee -a "$OUT/summary.txt"
echo "Bằng chứng: $OUT"
exit $fail
