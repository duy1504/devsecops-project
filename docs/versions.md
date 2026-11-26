# Bộ phiên bản của đồ án

**Ngày kiểm tra:** 04/11/2026, khoảng 21:15 giờ Việt Nam (UTC+7)
**Cách kiểm tra:** đọc trực tiếp tag trong repo Git của dự án (`git ls-remote`, `git fetch` từng tag), đọc `Chart.yaml` tại tag chart, tải asset release để đối chiếu SHA-256 và chạy thử binary. Không dựa vào kết quả công cụ tìm kiếm, vì chúng có thể chưa cập nhật các bản mới phát hành.

> Cập nhật file này mỗi khi đổi phiên bản, và kiểm tra lại toàn bộ ngay trước buổi demo/bảo vệ.

## 1. Đã xác minh

| Thành phần | Phiên bản ghim | Bằng chứng | Kiểm tra |
|---|---|---|---|
| Kyverno (app) | **v1.19.2** | Tag `v1.19.2` → commit `e63308f1e16c05cd009ac4864be6ec25c66b49be`; thời điểm build `2026-10-20T22:13:49Z`; trang Releases đánh dấu *Latest* | 04/11/2026 |
| Kyverno Helm chart | **3.9.2** | Tag `kyverno-chart-3.9.2` trỏ cùng commit `e63308f`; `charts/kyverno/Chart.yaml`: `version: 3.9.2`, `appVersion: v1.19.2` | 04/11/2026 |
| Kyverno CLI | **v1.19.2** | Asset `kyverno-cli_v1.19.2_linux_x86_64.tar.gz`, SHA-256 `357eaf1df8bc24ddd5a73979fadeaae6a032e8710f11af264229756e4956bf4a` (khớp `checksums.txt` của release; `kyverno version` báo `1.19.2`, commit `e63308f`) | 04/11/2026 |
| Syft | **v1.56.0** | Tag ổn định mới nhất; asset `syft_1.56.0_linux_amd64.tar.gz`, SHA-256 `1c2493cfcf52d3367d6cb25780d9190c111c2219c34c820574c43e8bae15c528` (khớp `syft_1.56.0_checksums.txt`) | 04/11/2026 |

Ghi chú:
- Ngày trên trang Releases là giờ UTC: v1.19.2 phát hành 20/10/2026 UTC, tức sáng 21/10/2026 giờ Việt Nam (một số trang như endoflife.date ghi 21/10).
- SHA-256 của Kyverno CLI và Syft được ghim vào workflow (`KYVERNO_CLI_SHA256`, `SYFT_SHA256`, mục 9.4 của kế hoạch). Đổi phiên bản thì đổi hash cùng lúc.

### 1b. Công cụ trên máy (WSL2 Ubuntu 24.04, x86_64) — cài bằng `scripts/install-tools.sh`

Cài vào `~/.local` (không cần sudo), kiểm tra SHA-256 trước khi cài; đã chạy thành công ngày 17/11/2026. Đổi phiên bản = sửa cả VERSION lẫn SHA256 trong script rồi cập nhật bảng này.

| Công cụ | Phiên bản | SHA-256 / bằng chứng | Kiểm tra |
|---|---|---|---|
| Go | 1.27.4 | `7226736c…dab24840` — khớp `go.dev/dl/?mode=json` | 17/11/2026 |
| AWS CLI v2 | 2.40.4 | `81f573c2…0979ae8e`; chữ ký PGP `Good signature` từ key `FB5DB77F…4672475C` (AWS CLI Team; bản key trên keyserver báo hết hạn, AWS gia hạn trong tài liệu); có `put/get-signing-configuration`, `describe-image-signing-status` | 17/11/2026 |
| Helm | v4.3.2 | `d1c0278d…daa53983` — khớp file `.sha256sum` của get.helm.sh | 17/11/2026 |
| kind | v0.33.0 | `aee61515…de8d8e0d` — khớp file `.sha256sum` của release | 17/11/2026 |
| jq | 1.8.2 | `b1c22172…1495870f` — khớp `sha256sum.txt` | 17/11/2026 |
| Trivy | 0.76.2 | `bc0fc726…54089fdbf` — khớp `trivy_0.76.2_checksums.txt`; thời điểm DB ghi khi scan | 17/11/2026 |
| Syft | 1.56.0 | như mục 1 | 17/11/2026 |
| Gitleaks | 8.30.1 | `551f6fc8…3f2470eb` — khớp `gitleaks_8.30.1_checksums.txt`. Workflow dùng đúng 8.30.1 (kế hoạch mục 9.4 ghi `v8.21.2` chỉ là ví dụ) | 17/11/2026 |
| Notation CLI | 1.3.2 | `e1a0f060…cbb6dfe5` — khớp `notation_1.3.2_checksums.txt` | 17/11/2026 |
| AWS Signer Notation plugin | 1.0.2292 | `f8efa548…1a26c7b9` (link `latest`, ghim hash lúc tải); `notation plugin ls` báo capabilities ENVELOPE, TRUSTED_IDENTITY, REVOCATION_CHECK | 17/11/2026 |
| Kyverno CLI | v1.19.2 | như mục 1 | 17/11/2026 |
| kubectl (client) | v1.36.1 | có sẵn qua Docker Desktop (`/usr/local/bin/kubectl`), không do script cài | 17/11/2026 |
| Docker / Buildx | 29.9.1 / v0.38.0 | Docker Desktop | 17/11/2026 |
| GitHub CLI (Windows) | 2.104.0 | `gh_2.104.0_windows_amd64.zip` SHA-256 `08c06d10482f12c478018cd259f64acbd5f625712cadf331aad19ba973c879e5` — khớp `gh_2.104.0_checksums.txt`; cài vào `%LOCALAPPDATA%\Programs\gh` (không qua script, máy không có winget) | 17/11/2026 |

**AWS Signer root certificate** (trust anchor cho Notation/extension, chưa cài vào trust store): tải từ `https://d2hvyiie56hcat.cloudfront.net/aws-signer-notation-root.cert`, SHA-256 file `0ccf5295…e879461c9b`; subject = issuer = `AWS Signer Code Signing Root CA G1` (O=AWS, OU=Cryptography); hiệu lực 27/10/2022 → 27/10/2122; fingerprint SHA-256 `90:A8:7D:05:43:C3:F0:94:DB:FF:95:89:B6:64:9A:FF:E2:F3:D6:E0:F3:08:79:9B:E2:25:84:61:C6:86:47:3F`. Đối chiếu lại với tài liệu AWS Signer trước khi đưa vào trust store (spike bước 4).

## 2. Đang theo dõi — không dùng

| Thành phần | Trạng thái | Ghi chú |
|---|---|---|
| Kyverno 1.20 (kiểm tra 17/11/2026) | **`v1.20.0` đã phát hành** (tag trỏ commit `f666af0`, `2026-11-11T12:42:56Z`; có rc.1–rc.5 trước đó) | Tại `v1.20.0`, `config/crds/kyverno/kyverno.io_clusterpolicies.yaml` **vẫn còn**, `deprecated: true`, cảnh báo "kyverno.io/v1 ClusterPolicy is deprecated and will be removed" → 1.20 **chưa gỡ** `ClusterPolicy`. Chưa đánh giá tương thích `kyverno-notation-aws` với 1.20 |
| Kyverno 1.20 (ghi chép 04/11/2026) | **`v1.20.0-rc.1`** (pre-release): tag annotated lúc `2026-11-02T23:38:17+02:00` (≈ 04:38 ngày 03/11/2026 giờ Việt Nam), commit `24e23f9` | Chưa có bản `v1.20.0` chính thức. rc.1 **vẫn còn** CRD `kyverno.io_clusterpolicies.yaml`, đánh dấu `deprecated: true` kèm cảnh báo "will be removed". Chưa xác định bản chính thức có thực sự gỡ `ClusterPolicy` hay lùi lịch |
| Helm chart cho 1.20 | **Chưa xác minh** | Đến 17/11/2026 vẫn không có tag `kyverno-chart-3.10.*` trong repo (`Chart.yaml` ở tag `v1.20.0` chỉ là placeholder `v0.0.0`); môi trường kiểm tra không truy cập được Helm index (`kyverno.github.io`). Kiểm tra bằng `helm search repo ... --devel` trên máy local |

Hệ quả cho đồ án:
- Giữ nguyên quyết định ghim **Kyverno 1.19.2 / chart 3.9.2** (17/11/2026: vẫn là bản vá mới nhất của nhánh 1.19). Nâng lên 1.20 là thay đổi công cụ → phải hỏi người dùng và thử lại tương thích extension.
- Từ 1.18, Kyverno theo mô hình hỗ trợ N-1 ("main + 1"): bản minor hiện tại và bản ngay trước nhận bản vá cộng đồng, chỉ cho CVE critical/high và lỗi nghiêm trọng ([thông báo 1.18](https://kyverno.io/blog/2026/04/24/announcing-kyverno-release-1.18/), mục "Updated Support Policy"). Khi 1.20.0 phát hành, 1.19 vẫn được vá cho tới khi 1.21 ra rồi mới hết hỗ trợ → ghi vào phần "Giới hạn" của báo cáo.

### 2b. `kyverno-notation-aws` — đánh giá ngày 17/11/2026

**Đã chốt (người dùng chọn 17/11/2026): tự build từ `main`** bằng `scripts/build-notation-ext.sh`.

| Bản dùng cho đồ án | Giá trị |
|---|---|
| Upstream commit | `58b210b446590eb079b1c84245cacd4a434e8a36` |
| Builder | `golang:1.26.10-alpine3.24@sha256:87c65a688975c0b1d4585d204874c45ca78354670e3a5f11368c5a492303d696` |
| Runtime | `gcr.io/distroless/static:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931` |
| Vá cục bộ | `golang.org/x/net` 0.58.0 → 0.62.0, `go-jose/v4` 4.1.4 → 4.1.6 (kéo theo `x/crypto` 0.58.0, `x/sys` 0.49.0, `x/text` 0.43.0, `x/term` 0.47.0, `x/sync` 0.24.0, `x/mod` 0.41.0); runtime ghim digest. Diff đầy đủ: `reports/notation-ext/local.patch` |
| Kiểm tra | `go vet ./...` + `go test ./...` đạt (17/11/2026) |
| Vá cục bộ p2 (26/11/2026) | Thư viện `github.com/nirmata/kyverno-notation-verifier` v1.1.0 (lấy từ module cache sau `go mod verify`, `replace` sang `third_party/`): TokenReview khai báo audience từ biến `TOKEN_REVIEW_AUDIENCES` (Kyverno 1.19 gửi token audience `kyverno-svc.kyverno.io` → không có bản vá thì mọi yêu cầu bị `Token is not authorized`); log chỉ ghi tên user thay vì **cả token** (upstream ghi toàn bộ TokenReview, gồm bearer token của Kyverno, ở mức INFO). Bản vá: `infra/kyverno-notation-aws/patches/verifier-v1.1.0-token-review.patch` |
| Image đang dùng | `local/kyverno-notation-aws:58b210b-p2`, image ID `sha256:f2d1998698b3f583b961590dd518af0ddb5458efb1f202ff5f1fddaa8e3c05be` (26/11/2026). Bản p1 cũ: `sha256:6835bbfd…b2480`. Build có thể không tái lập từng byte; ghi lại ID mỗi lần build |
| Trivy 0.76.2 | p2, DB 26/11/2026: **CRITICAL=0, HIGH=0**, MEDIUM=3, UNKNOWN=1 — gate đạt. (p1, DB 16/11: CRITICAL=0, HIGH=0, MEDIUM=2, UNKNOWN=2) |
| Chạy trên kind (26/11/2026) | Kyverno 1.19.2 + `ClusterPolicy/verify-signer`: TC01 nhận, TC04/TC06 từ chối đúng lý do, TC09 fail-closed — xem `docs/test-results.md` |

Chi tiết đánh giá:

Nguồn: clone `github.com/nirmata/kyverno-notation-aws` (HEAD `main` = `58b210b446590eb079b1c84245cacd4a434e8a36`, 06/11/2026), GitHub Releases, PR #488/#493/#496.

| Điểm | Kết quả |
|---|---|
| Release chính thức mới nhất | **`v1.1`** (06/01/2025); trước đó `v1` (11/2023). Các bản `v1.2.0`–`v1.2.2` **đã bị gỡ** (PR #496, 21/09/2026) |
| Trạng thái repo | Chưa archive (`archived: false`, push gần nhất 14/11/2026) nhưng PR #496 ghi rõ đang chuẩn bị **archive**, khuyên dùng "successor repository" — **chưa tìm thấy tên repo kế nhiệm** (không có trong org `nirmata`) |
| Image `v1.1` | `ghcr.io/nirmata/kyverno-notation-aws@sha256:881e40db6132f2dfd58f59a344e6a115da5caa15a7aa192b4ba7f706a058634e`; Trivy 0.76.2, DB 16/11/2026: **CRITICAL=6, HIGH=80, MEDIUM=81, LOW=11, UNKNOWN=6** (CVE duy nhất). Build bằng Go 1.22.3, thư viện Kyverno v1.12.1 (theo #488) |
| Nhánh `main` | Đã vá CVE (Go 1.26.8, `kyverno v1.19.1`, `kyverno-notation-verifier v1.1.0`, build AWS Signer plugin từ source) nhưng **không có artifact phát hành** → muốn dùng phải tự build |
| Tự build `main@58b210b` (Dockerfile gốc, `linux/amd64`) | Image ID `sha256:8dfa24b108a820fb0e3d12aab6fcb5d7ccd0a5aeddab371705a80ff96a6438f4`; Trivy 0.76.2, DB 16/11/2026: **CRITICAL=0, HIGH=6**, MEDIUM=14, LOW=1, UNKNOWN=2. Cả 6 HIGH đều có bản vá: stdlib Go 1.26.8 → 1.26.10 (CVE-2026-111943, -78667, -78669, -97031; đổi được qua build-arg `BUILDER_IMAGE`), `golang.org/x/net` 0.58.0 → 0.62.0 (CVE-2026-78661, -78669), `go-jose/v4` 4.1.4 → 4.1.6 (CVE-2026-116587) |
| 6 CRITICAL của `v1.1` | CVE-2024-24790, CVE-2025-68121 (stdlib 1.22.3); CVE-2024-41110 (docker 25.0.5); CVE-2026-22039, GHSA-gg4x-fgg2-h9w9 (kyverno 1.12.1); CVE-2026-33186 (grpc 1.62.1) |
| Giao diện với Kyverno | `ClusterPolicy` + `context.apiCall` (POST tới service). **Đã chạy trên Kyverno 1.19.2 (26/11/2026)** sau bản vá p2; Kyverno in cảnh báo `ClusterPolicy is deprecated`. Mẫu upstream đọc Secret TLS (chứa private key) để lấy `caBundle` → đồ án nhúng CA công khai lúc render, không cấp quyền đọc Secret cho Kyverno. Khi xác minh thất bại extension trả **HTTP 406** (không trả `verified:false`) → Kyverno ghi `error (blocked)` |
| Yêu cầu ghi trong README | Kyverno ≥ 1.11.0 |

Ghi chú mạng: tải Trivy DB từ `mirror.gcr.io` (mặc định) bị ngắt kết nối; `--db-repository ghcr.io/aquasecurity/trivy-db:2` tải được.

## 3. Lệnh kiểm tra lại

```bash
# Tag Kyverno 1.19/1.20 và chart
git ls-remote --tags https://github.com/kyverno/kyverno \
  | grep -E 'refs/tags/(v1\.(19|20)\.|kyverno-chart-3\.(9|10)\.)' | grep -v '\^{}'

# Chart ổn định và pre-release (chỉ để xem, KHÔNG dùng --devel khi cài)
helm repo update
helm search repo kyverno/kyverno --versions | head
helm search repo kyverno/kyverno --versions --devel | head

# Đối chiếu SHA-256 của asset đã ghim
curl -fsSL https://github.com/kyverno/kyverno/releases/download/v1.19.2/checksums.txt \
  | grep 'kyverno-cli_v1.19.2_linux_x86_64.tar.gz$'
curl -fsSL https://github.com/anchore/syft/releases/download/v1.56.0/syft_1.56.0_checksums.txt \
  | grep 'syft_1.56.0_linux_amd64.tar.gz$'

# Sau khi cài lên cụm: image Kyverno đang chạy
kubectl -n kyverno get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

## 4. Chưa kiểm tra — điền sau spike

| Thành phần | Phiên bản / digest | Nguồn | Ngày kiểm tra |
|---|---|---|---|
| Kubernetes (kind node image) | `kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0` | Release notes kind v0.33.0 (image dựng sẵn cho bản này); Kyverno v1.19.2 chạy conformance trên K8s v1.33.7/v1.34.3/v1.35.1 (`.github/workflows/tests-conformance.yaml` tại tag) | 17/11/2026 |
| Kyverno chart (cài thật) | 3.9.2 qua OCI `oci://ghcr.io/kyverno/charts/kyverno`; manifest digest `sha256:83054f30148c3cfc001087c1f5772eda7c7224e9b74b7f0e70c39c9cafe009d1`; file `.tgz` SHA-256 `3d561086a5c457f038ad5ec01f2b8a279738c44eae0e8506e271e4599e627ae9` | `helm show chart`: `appVersion: v1.19.2`. Không dùng `kyverno.github.io` (timeout từ mạng lab) | 17/11/2026 |
| Kyverno image đang chạy | admission `reg.kyverno.io/kyverno/kyverno@sha256:c8c4dd09e720d2cd7fd24ca73ac28e46651001372f988e0cba3f2f612f04b955`; background `…@sha256:c46e124f21ef8a6bb4b48de57106808b1007edcd5ddd4ff7df5d23b9efa60ce2`; cleanup `…@sha256:d7340aa7c9315080c3dafa7b765d090ced37353e89e5cd7a3f9ac69e8fb532b2`; reports `…@sha256:5fb6d3e738050dbce84f60ecabaede7665fbe0578d07c1e8c912443b035e79c3` (cả 4 tag `v1.19.2`) | `kubectl get pods -o jsonpath='{..imageID}'` trên cụm kind | 17/11/2026 |
| `kyverno-notation-aws` (release/commit, image digest) | | | |
| Trivy DB (thời điểm, mỗi lần scan làm bằng chứng) | | | |
| eksctl (nếu dùng EKS) | | | |
| Base image builder | `golang:1.27.4-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280` (index) | `docker buildx imagetools inspect`; podinfo 6.17.0 yêu cầu `go 1.27.0` | 17/11/2026 |
| Base image runtime | `gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab` (index) | `docker buildx imagetools inspect` | 17/11/2026 |
| podinfo | tag `6.17.0`, commit `fd3a834ed8d14b80ea334cf8a2fddd4597924da6` | GitHub, chi tiết `docs/upstream.md` | 17/11/2026 |
| GitHub Actions dùng trong workflow (commit SHA) | `actions/checkout` v7.0.1 `3d3c42e5aac5ba805825da76410c181273ba90b1`; `actions/setup-go` v7.1.0 `d8cbb8045d7f43706b9177cceb36c1f91a6644d5`; `docker/setup-buildx-action` v4.4.1 `f87e5991a6d7451dcb8d9637bfbc97413f497069`; `docker/build-push-action` v7.4.0 `c3c9e263c25d99ce0380d002d59b67737d91b0dc`; `actions/upload-artifact` v7.0.2 `cf430e030ddbb5b0abf93d22962f4752f3646cd9`; `github/codeql-action/upload-sarif` v4.39.3 `33d7b85da1a04171e211befe2c739303b9a4c066` | `git ls-remote` tag mới nhất → commit (`^{}`) | 17/11/2026 |
| Công cụ CLI trong workflow | Gitleaks 8.30.1, Syft 1.56.0, Trivy 0.76.2, Kyverno CLI v1.19.2 — cùng SHA-256 với mục 1/1b (cài binary, không dùng action/image `latest`) | `.github/workflows/ci-cd.yml` | 17/11/2026 |
