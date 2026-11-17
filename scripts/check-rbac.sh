#!/usr/bin/env bash
# TC10 (phần auth can-i): deployer chỉ có quyền tối thiểu (k8s/rbac.yaml, kế hoạch mục 10.2).
# Dòng đầu phải "yes", mọi dòng còn lại phải "no". Thoát 1 nếu sai.
set -uo pipefail
D=(--as=deployer --as-group=devsecops-deployers)
fail=0
check() {  # check <mong đợi> <mô tả> <tham số can-i...>
  local want=$1 desc=$2; shift 2
  local got; got=$(kubectl auth can-i "$@" "${D[@]}" 2>/dev/null)
  printf '%-4s %-4s %s\n' "$got" "$([ "$got" = "$want" ] && echo OK || echo SAI)" "$desc"
  [ "$got" = "$want" ] || fail=1
}
echo "kết quả mong đợi  quyền"
check yes "patch deployments -n app"                   patch deployments -n app
check no  "get secrets -n app"                         get secrets -n app
check no  "create pods/exec -n app"                    create pods --subresource=exec -n app
check no  "create pods/attach -n app"                  create pods --subresource=attach -n app
check no  "create pods/portforward -n app"             create pods --subresource=portforward -n app
check no  "patch pods/ephemeralcontainers -n app"      patch pods --subresource=ephemeralcontainers -n app
check no  "create pods -n app (tạo Pod trực tiếp)"     create pods -n app
check no  "update clusterpolicies.kyverno.io"          update clusterpolicies.kyverno.io
check no  "update validatingpolicies.policies.kyverno.io" update validatingpolicies.policies.kyverno.io
check no  "delete validatingpolicies.policies.kyverno.io" delete validatingpolicies.policies.kyverno.io
check no  "create namespaces"                          create namespaces
check no  "patch deployments -n demo"                  patch deployments -n demo
check no  "patch deployments -n kube-system"           patch deployments -n kube-system
check no  "update validatingwebhookconfigurations"     update validatingwebhookconfigurations
exit $fail
