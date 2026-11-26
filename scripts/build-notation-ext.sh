#!/usr/bin/env bash
# Tự build extension kyverno-notation-aws từ source (quyết định 17/11/2026, docs/versions.md mục 2b).
# Lý do: release chính thức mới nhất v1.1 có 6 CVE Critical; repo sắp archive, nhánh main đã vá nhưng không phát hành.
# Ghim: commit upstream, builder image và runtime image theo digest; vá thêm 2 module Go có CVE High.
# Gate: 0 Critical (Trivy, không --ignore-unfixed). Chạy trên WSL2 Ubuntu: bash scripts/build-notation-ext.sh
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

KNA_REPO=https://github.com/nirmata/kyverno-notation-aws
KNA_COMMIT=58b210b446590eb079b1c84245cacd4a434e8a36   # main, 06/11/2026
BUILDER_IMAGE=golang:1.26.10-alpine3.24@sha256:87c65a688975c0b1d4585d204874c45ca78354670e3a5f11368c5a492303d696
RUNTIME_IMAGE=gcr.io/distroless/static:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931
# Module vá thêm (CVE High trên main@58b210b, xem docs/versions.md mục 2b)
GO_BUMPS="golang.org/x/net@v0.62.0 github.com/go-jose/go-jose/v4@v4.1.6"
# Vá thư viện verifier (p2): TokenReview khai báo audience token của Kyverno 1.19; không ghi token ra log
VERIFIER_MOD=github.com/nirmata/kyverno-notation-verifier
VERIFIER_VER=v1.1.0
PATCH_LEVEL=p2                                        # tăng khi đổi bộ vá (p1: chỉ GO_BUMPS)
IMAGE_TAG="local/kyverno-notation-aws:${KNA_COMMIT:0:7}-${PATCH_LEVEL}"
TRIVY_DB_REPO="${TRIVY_DB_REPO:-ghcr.io/aquasecurity/trivy-db:2}"  # mirror.gcr.io hay bị ngắt trên mạng lab

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERIFIER_PATCH="$ROOT/infra/kyverno-notation-aws/patches/verifier-v1.1.0-token-review.patch"
SRC="${KNA_SRC:-$HOME/build/kyverno-notation-aws}"
OUT="$ROOT/reports/notation-ext"
mkdir -p "$OUT" "$(dirname "$SRC")"

retry() {  # retry <số lần> <lệnh...> — mạng lab chập chờn khi tải từ proxy.golang.org
  local n=$1 i; shift
  for ((i = 1; i <= n; i++)); do "$@" && return 0; echo "  lần $i thất bại, thử lại..." >&2; sleep 5; done
  return 1
}

echo "== 1. Source tại commit ghim"
[ -d "$SRC/.git" ] || retry 3 git clone -q "$KNA_REPO" "$SRC"
git -C "$SRC" cat-file -e "$KNA_COMMIT^{commit}" 2>/dev/null || retry 3 git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --force "$KNA_COMMIT"
git -C "$SRC" reset -q --hard && git -C "$SRC" clean -qfdx
[ "$(git -C "$SRC" rev-parse HEAD)" = "$KNA_COMMIT" ] || { echo "Sai commit" >&2; exit 1; }

echo "== 2. Vá module Go: $GO_BUMPS"
# Chạy trong builder image ghim; module cache dùng volume để lần thử lại không tải lại từ đầu.
# go.sum vẫn được đối chiếu với sum.golang.org (GOSUMDB mặc định).
docker volume create kna-gomod >/dev/null
retry 4 docker run --rm -v "$SRC":/src -v kna-gomod:/go/pkg/mod -w /src "$BUILDER_IMAGE" \
  sh -c "go get $GO_BUMPS && go mod tidy"
git -C "$SRC" diff --stat -- go.mod go.sum

echo "== 2b. Vá thư viện $VERIFIER_MOD@$VERIFIER_VER (p2: TokenReview audience + không ghi token ra log)"
# Lấy đúng bản module từ module cache sau khi `go mod verify` (đối chiếu go.sum), chép vào third_party,
# áp bản vá trong repo đồ án, rồi trỏ go.mod tới bản đã vá bằng replace.
retry 3 docker run --rm -v "$SRC":/src -v kna-gomod:/go/pkg/mod -w /src "$BUILDER_IMAGE" sh -c \
  "go mod verify >/dev/null && mkdir -p third_party && rm -rf third_party/kyverno-notation-verifier \
   && cp -r \$(go list -m -f '{{.Dir}}' $VERIFIER_MOD) third_party/kyverno-notation-verifier \
   && chmod -R u+w third_party && chown -R $(id -u):$(id -g) third_party \
   && [ \"\$(go list -m -f '{{.Version}}' $VERIFIER_MOD)\" = $VERIFIER_VER ]"
git -C "$SRC" apply -p1 --directory=third_party/kyverno-notation-verifier "$VERIFIER_PATCH"
docker run --rm -v "$SRC":/src -v kna-gomod:/go/pkg/mod -w /src "$BUILDER_IMAGE" sh -c \
  "go mod edit -replace $VERIFIER_MOD=./third_party/kyverno-notation-verifier && go mod tidy \
   && go vet $VERIFIER_MOD/verifier && chown $(id -u):$(id -g) go.mod go.sum"
grep -q "tokenReviewAudiences()" "$SRC/third_party/kyverno-notation-verifier/verifier/client.go" \
  || { echo "Bản vá verifier chưa được áp" >&2; exit 1; }

echo "== 3. Ghim runtime image trong Dockerfile, đưa third_party vào build context trước go mod download"
sed -i "s#^FROM gcr.io/distroless/static:nonroot\$#FROM $RUNTIME_IMAGE#" "$SRC/Dockerfile"
grep -q "^FROM $RUNTIME_IMAGE\$" "$SRC/Dockerfile" || { echo "Không ghim được runtime image" >&2; exit 1; }
sed -i 's#^COPY go.mod go.sum \.$#COPY go.mod go.sum .\nCOPY third_party ./third_party#' "$SRC/Dockerfile"
grep -q '^COPY third_party ./third_party$' "$SRC/Dockerfile" || { echo "Không sửa được Dockerfile" >&2; exit 1; }
git -C "$SRC" diff > "$OUT/local.patch"   # bằng chứng: toàn bộ thay đổi so với upstream
cp "$VERIFIER_PATCH" "$OUT/verifier.patch"

echo "== 4. Build $IMAGE_TAG (linux/amd64)"
retry 4 docker buildx build -q --platform linux/amd64 --load \
  --build-arg BUILDER_IMAGE="$BUILDER_IMAGE" -t "$IMAGE_TAG" "$SRC" >/dev/null
IMAGE_ID=$(docker image inspect --format '{{.Id}}' "$IMAGE_TAG")
echo "image ID: $IMAGE_ID"

echo "== 5. Trivy scan + gate 0 Critical"
retry 3 trivy image -q --download-db-only --db-repository "$TRIVY_DB_REPO"
trivy image -q --skip-db-update --scanners vuln --format json -o "$OUT/trivy.json" "$IMAGE_TAG"
SUMMARY=$(jq -r '[.Results[]?.Vulnerabilities[]?] | unique_by(.VulnerabilityID)
  | group_by(.Severity) | map("\(.[0].Severity)=\(length)") | join(" ")' "$OUT/trivy.json")
CRIT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | unique_by(.VulnerabilityID) | length' "$OUT/trivy.json")
DB_TIME=$(trivy version -f json | jq -r '.VulnerabilityDB.UpdatedAt')

jq -n --arg commit "$KNA_COMMIT" --arg builder "$BUILDER_IMAGE" --arg runtime "$RUNTIME_IMAGE" \
  --arg bumps "$GO_BUMPS" --arg tag "$IMAGE_TAG" --arg id "$IMAGE_ID" \
  --arg summary "$SUMMARY" --arg db "$DB_TIME" --arg built "$(date -u +%FT%TZ)" \
  '{upstream_commit:$commit, builder_image:$builder, runtime_image:$runtime, go_bumps:$bumps,
    image_tag:$tag, image_id:$id, trivy_summary:$summary, trivy_db_updated:$db, built_at:$built}' \
  > "$OUT/build.json"
cat "$OUT/build.json"

if [ "$CRIT" -ne 0 ]; then echo "GATE THẤT BẠI: $CRIT CVE Critical" >&2; exit 1; fi
echo "GATE ĐẠT: 0 Critical ($SUMMARY)"
echo "Nạp vào kind khi có cụm: kind load docker-image $IMAGE_TAG --name <cluster>"
