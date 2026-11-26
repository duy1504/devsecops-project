#!/usr/bin/env bash
# Kiểm tra trước buổi làm việc/demo + chụp bộ phiên bản đang chạy thật (kế hoạch mục 6.1 bước 10, 16.1).
# Chỉ ĐỌC: không sửa AWS, cụm hay GitHub. Chạy trên WSL: bash scripts/preflight.sh
# Kết quả: reports/preflight/<TS>/ (summary.txt + versions.json, đã che account ID). Exit ≠ 0 nếu có mục SAI.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh || exit 1
set -a; source reports/spike/fixtures.env; set +a
TS=$(date -u +%Y%m%dT%H%M%SZ); OUT=reports/preflight/$TS; mkdir -p "$OUT"
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || { echo "Account ID không hợp lệ" >&2; exit 1; }
mask() { sed -E "s/${AWS_ACCOUNT_ID}/<ACCOUNT_ID>/g; s/eyJ[A-Za-z0-9._-]{20,}/<JWT>/g"; }
fail=0
ok()  { printf 'OK   %-34s %s\n' "$1" "$2" | mask | tee -a "$OUT/summary.txt"; }
bad() { printf 'SAI  %-34s %s\n' "$1" "$2" | mask | tee -a "$OUT/summary.txt"; fail=1; }
chk() { local name=$1 got=$2 want=$3; [ "$got" = "$want" ] && ok "$name" "$got" || bad "$name" "có '$got', cần '$want'"; }
first() { head -1 | tr -d '\r'; }
echo "Preflight $TS" | tee "$OUT/summary.txt"

echo "== Công cụ (WSL)" | tee -a "$OUT/summary.txt"
declare -A T
T[aws]=$(aws --version 2>&1 | first | cut -d' ' -f1 | cut -d/ -f2)
T[kubectl]=$(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion)
T[kind]=$(kind version 2>/dev/null | awk '{print $2}')
T[helm]=$(helm version --short 2>/dev/null | cut -d+ -f1)
T[trivy]=$(trivy --version 2>/dev/null | first | awk '{print $2}')
T[syft]=$(syft version 2>/dev/null | awk '/^Version/{print $2}')
T[gitleaks]=$(gitleaks version 2>/dev/null | first)
T[notation]=$(notation version 2>/dev/null | awk '/^Version/{print $2}')
T[signer_plugin]=$(notation plugin ls 2>/dev/null | grep com.amazonaws.signer | grep -oE '\b[0-9]+\.[0-9]+\.[0-9]+\b' | first)
T[kyverno_cli]=$(kyverno version 2>/dev/null | awk '/^Version/{print $2}')
T[jq]=$(jq --version)
T[docker]=$(docker version -f '{{.Server.Version}}' 2>/dev/null)
for k in "${!T[@]}"; do printf '%s\t%s\n' "$k" "${T[$k]}"; done | sort > "$OUT/tools.tsv"
chk "Trivy" "${T[trivy]}" "0.76.2"; chk "Syft" "${T[syft]}" "1.56.0"; chk "Gitleaks" "${T[gitleaks]}" "8.30.1"
chk "Kyverno CLI" "${T[kyverno_cli]}" "1.19.2"; chk "Notation" "${T[notation]}" "1.3.2"
chk "AWS Signer plugin" "${T[signer_plugin]}" "1.0.2292"; chk "AWS CLI" "${T[aws]}" "2.40.4"
ok "kubectl / kind / helm / docker" "${T[kubectl]} / ${T[kind]} / ${T[helm]} / ${T[docker]}"

echo "== Cụm kind" | tee -a "$OUT/summary.txt"
NODE_IMG=$(docker inspect devsecops-control-plane --format '{{.Config.Image}}' 2>/dev/null)
K8S=$(kubectl version -o json 2>/dev/null | jq -r .serverVersion.gitVersion)
chk "Kubernetes server" "$K8S" "v1.35.8"
CHART=$(helm list -n kyverno -o json 2>/dev/null | jq -r '.[] | select(.name=="kyverno") | .chart + " " + .app_version')
chk "Kyverno chart / app" "$CHART" "kyverno-3.9.2 v1.19.2"
kubectl -n kyverno get pods -o jsonpath='{range .items[*]}{.metadata.labels.app\.kubernetes\.io/component}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].imageID}{"\n"}{end}' \
  > "$OUT/kyverno-images.tsv" 2>&1
notready=$(awk -F'\t' '$2!="Running"' "$OUT/kyverno-images.tsv" | wc -l)
[ "$notready" = 0 ] && ok "Kyverno pods Running" "$(wc -l < "$OUT/kyverno-images.tsv") pod" || bad "Kyverno pods" "$notready pod không Running"
# Docker 29 (containerd store): image ID local f2d19986… là digest OCI index → manifest amd64 1dd83a60… → config d3c72d96….
# Trên node kind, containerd báo config digest; imageID của Pod là index "import-<ngày>@sha256:…" do kind tạo khi nạp.
EXT_CONFIG=sha256:d3c72d9677faf176022f06a88e4016c7baa257f69b54f3aa83baef1de786c435   # docs/versions.md mục 2b
EXT_ID=$(docker exec devsecops-control-plane crictl ps --name kyverno-notation-aws -o json 2>/dev/null \
  | jq -r '[.containers[] | select(.state=="CONTAINER_RUNNING") | .imageRef][0] // empty')
EXT_ID=${EXT_ID:-$(docker exec devsecops-control-plane crictl ps --name kyverno-notation-aws -o json 2>/dev/null | jq -r '.containers[0].image.image // empty')}
chk "Extension image (config p2)" "$EXT_ID" "$EXT_CONFIG"
EXT_READY=$(kubectl -n kyverno-notation-aws get deploy kyverno-notation-aws -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
chk "Extension ready replicas" "${EXT_READY:-0}" "1"
chk "Policy 1 allowed-image Ready" "$(kubectl get validatingpolicy allowed-image -o jsonpath='{.status.conditionStatus.ready}' 2>/dev/null)" "true"
chk "Policy 2 verify-signer Ready" "$(kubectl get clusterpolicy verify-signer -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
chk "Policy 2 failurePolicy" "$(kubectl get clusterpolicy verify-signer -o jsonpath='{.spec.failurePolicy}' 2>/dev/null)" "Fail"
ign=$(kubectl get validatingwebhookconfigurations -o json | jq '[.items[] | select(.metadata.name | test("kyverno")) | .webhooks[] | select(.failurePolicy=="Ignore") | select(.name | test("vpol|validate.kyverno.svc-fail|verify"))] | length')
chk "Webhook Kyverno Fail (vpol/policy)" "$ign" "0"
tp=$(kubectl get trustpolicy tp-supply-chain -o json 2>/dev/null)
chk "TrustPolicy level" "$(jq -r '.spec.trustPolicies[0].signatureVerification.level' <<< "$tp")" "strict"
chk "TrustPolicy trustedIdentities" "$(jq -r '.spec.trustPolicies[0].trustedIdentities | join(",")' <<< "$tp")" "$SIGNING_PROFILE_ARN"
EXP=$(kubectl -n kyverno-notation-aws get secret verifier-aws-credentials -o jsonpath='{.metadata.annotations.devsecops/expires}' 2>/dev/null)
if [ -n "$EXP" ] && [ "$(date -u -d "$EXP" +%s)" -gt "$(( $(date -u +%s) + 600 ))" ]; then ok "Credential verifier" "hết hạn $EXP"
else bad "Credential verifier" "hết hạn/sắp hết ($EXP) → bash scripts/refresh-lab-credentials.sh"; fi
for ns in app demo; do
  chk "SA default ($ns) imagePullSecrets" "$(kubectl -n $ns get sa default -o jsonpath='{.imagePullSecrets[0].name}' 2>/dev/null)" "ecr-pull"
done

echo "== AWS" | tee -a "$OUT/summary.txt"
repo=$(aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --query 'repositories[0]' --output json)
chk "ECR tag mutability" "$(jq -r .imageTagMutability <<< "$repo")" "IMMUTABLE"
chk "ECR encryption" "$(jq -r .encryptionConfiguration.encryptionType <<< "$repo")" "KMS"
sc=$(aws ecr get-signing-configuration --output json 2>/dev/null)
jq '.' <<< "$sc" | mask > "$OUT/signing-configuration.json"
chk "Signing rule (profile|filter)" "$(jq -r '[.signingConfiguration.rules[] | "\(.signingProfileArn)|\(.repositoryFilters[].filter)"] | join(";")' <<< "$sc")" "${SIGNING_PROFILE_ARN}|podinfo"
for p in "$SIGNING_PROFILE" "$WRONG_SIGNING_PROFILE"; do
  aws signer get-signing-profile --profile-name "$p" --query '{name:profileName,status:status,platform:platformId,version:profileVersion}' --output json > "$OUT/profile-$p.json"
  chk "Signer $p" "$(jq -r '"\(.status) \(.platform)"' "$OUT/profile-$p.json")" "Active Notation-OCI-SHA384-ECDSA"
done
lc=$(aws ecr get-lifecycle-policy --repository-name "$ECR_REPOSITORY" --query lifecyclePolicyText --output text 2>/dev/null)
[ -n "$lc" ] && diff <(jq -S . <<< "$lc") <(jq -S . infra/aws/lifecycle-policy.json) > /dev/null \
  && ok "Lifecycle policy" "khớp infra/aws/lifecycle-policy.json" || bad "Lifecycle policy" "khác file trong repo hoặc chưa áp"

echo "== Fixture (không được ký thêm)" | tee -a "$OUT/summary.txt"
export NOTATION_USERNAME=AWS NOTATION_PASSWORD; NOTATION_PASSWORD=$(aws ecr get-login-password)
nsig() { notation ls "${ECR_IMAGE}@$1" 2>&1 | grep -cE '^ +[└├]── sha256:'; }
chk "D_unsigned: số chữ ký" "$(nsig "$D_UNSIGNED")" "0"
chk "D_wrongsigner: số chữ ký" "$(nsig "$D_WRONGSIGNER")" "1"
WS=$(notation inspect "${ECR_IMAGE}@${D_WRONGSIGNER}" -o json 2>/dev/null \
  | jq -r '[.Signatures[].signedAttributes["com.amazonaws.signer.signingProfileVersion"]] | join(",")')
case "$WS" in *"/signing-profiles/${WRONG_SIGNING_PROFILE}/"*) ok "D_wrongsigner: người ký" "profile B" ;; *) bad "D_wrongsigner: người ký" "$WS" ;; esac
n=$(nsig "$D_SIGNED"); [ "$n" -ge 1 ] && ok "D_signed: số chữ ký" "$n" || bad "D_signed: số chữ ký" "$n"
unset NOTATION_PASSWORD

echo "== Trivy DB" | tee -a "$OUT/summary.txt"
DB=$(trivy version -f json 2>/dev/null | jq -r '.VulnerabilityDB.UpdatedAt // "chưa tải"')
ok "Trivy DB local (UpdatedAt)" "$DB"

jq -n --arg ts "$TS" --rawfile tools "$OUT/tools.tsv" --arg node "$NODE_IMG" --arg k8s "$K8S" --arg chart "$CHART" \
  --rawfile kyv "$OUT/kyverno-images.tsv" --arg ext "$EXT_ID" --arg db "$DB" \
  '{checked_at:$ts, tools:($tools|split("\n")|map(select(length>0)|split("\t")|{(.[0]):.[1]})|add),
    kind_node_image:$node, kubernetes:$k8s, kyverno_chart:$chart,
    kyverno_pods:($kyv|split("\n")|map(select(length>0)|split("\t")|{component:.[0],imageID:.[2]})),
    extension_imageID:$ext, trivy_db_updated:$db}' | mask > "$OUT/versions.json"
echo "KẾT QUẢ: $([ $fail = 0 ] && echo ĐẠT || echo 'CÓ MỤC SAI')" | tee -a "$OUT/summary.txt"
echo "Chi tiết: $OUT"
exit $fail
