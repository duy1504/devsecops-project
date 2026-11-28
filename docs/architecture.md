# Kiến trúc và các quyết định thiết kế

Tài liệu ghi lại kiến trúc của đồ án và lý do của từng quyết định. Phần nền tảng lấy từ `KE_HOACH_DO_AN_FINAL.md` (mục 2, 3.4). Phần quyết định phát sinh khi triển khai ghi rõ ngày và bằng chứng. Phiên bản và hash nằm trong `docs/versions.md`; kết quả kiểm thử nằm trong `docs/test-results.md`.

**Cập nhật:** 28/11/2026. **Mọi thành phần đã triển khai và chạy thật** (ECR, Managed Signing, job `publish` qua OIDC, Policy 1 + Policy 2 trên kind); TC01–TC10 đều Đạt (`docs/test-results.md`). Báo cáo: Chương 3 (thiết kế), Chương 4 (triển khai) trong `docs/report/`.

## 1. Bài toán và câu hỏi nghiên cứu

Một image "chạy được" chưa đủ để kết luận nó đáng tin. Kẻ tấn công có thể chèn mã độc vào mã nguồn, dependency, công cụ build hoặc registry. Đồ án trả lời câu hỏi: **phối hợp kiểm soát trong CI và tại Kubernetes admission có phát hiện hoặc ngăn được bốn tình huống (secret trong mã, image có CVE Critical, image chưa ký, image từ nguồn không được phép), đồng thời truy vết được từ Pod về digest, SBOM và commit không?**

## 2. Luồng tổng thể

```mermaid
flowchart LR
    Dev[Developer] -->|PR / push| GH[GitHub repo<br/>main có branch protection]

    subgraph CI["GitHub Actions"]
        subgraph V["Job verify — không có quyền AWS"]
            T[Unit test] --> S[Gitleaks]
            S --> B[Build 1 lần → image.tar]
            B --> SB[Syft SBOM]
            SB --> TV[Trivy scan → gate 0 Critical]
        end
        PT["Job policy-test<br/>Kyverno CLI offline"]
        TV -->|FAIL| X[[Dừng, lưu báo cáo]]
        TV -->|PASS + push main| P["Job publish (OIDC)<br/>load đúng image.tar → push"]
        P --> W[Chờ ký COMPLETE<br/>→ release.json]
    end

    GH --> T
    GH --> PT
    P --> ECR[(Amazon ECR<br/>repo podinfo)]
    ECR -->|Managed Signing| SIG[AWS Signer]
    SIG -->|chữ ký Notation<br/>OCI referrer| ECR

    subgraph K8S["Kubernetes (kind)"]
        API[kube-apiserver] --> P1{Policy 1<br/>đúng repo + digest}
        P1 -->|đạt| P2{Policy 2<br/>chữ ký tin cậy}
        P2 -->|đạt| POD[Pod chạy]
        P1 -->|vi phạm| DENY[[Từ chối]]
        P2 -->|không ký / sai signer / lỗi| DENY
    end

    W -->|image@sha256:digest| API
    P2 -.->|đọc chữ ký| ECR
    P2 -.->|kiểm tra thu hồi| SIG
```

**Defense in depth.** Lớp 1 (CI) ngăn image xấu được phát hành. Lớp 2 (admission) ngăn image không đi qua pipeline được chạy, kể cả khi ai đó gọi `kubectl` trực tiếp.

| Cơ chế | Trả lời câu hỏi | Giới hạn |
|---|---|---|
| Unit test | Hành vi đã test có đúng không? | Không chứng minh bảo mật |
| Gitleaks | Có chuỗi khớp quy tắc secret không? | Có false positive và bỏ sót |
| SBOM | Image chứa những thành phần nào? | Không phải chứng nhận an toàn |
| Trivy gate | Có CVE mà DB hiện tại đánh giá Critical không? | Kết quả đổi theo thời gian; không phát hiện zero-day |
| Chữ ký | Digest này có được ký bởi danh tính tin cậy không? | Không tự chứng minh các bước scan đã đạt |
| Policy 1 (nguồn) | Image có đúng account, region, repository, digest không? | Chỉ kiểm tra nguồn là chưa đủ |
| Admission nói chung | Yêu cầu tạo Pod có đáp ứng policy không? | Không gỡ Pod đã chạy trước đó |

> **ECR Managed Signing không đọc kết quả Trivy hay Gitleaks.** Nó ký mọi image push vào repository khớp filter. "Chỉ image đạt mới được ký" dựa vào pipeline và việc giới hạn quyền push.

## 3. Ranh giới tin cậy

| Vùng | Được làm | Không được làm | Cách thực thi |
|---|---|---|---|
| PR (chưa tin cậy) | Chạy test, scan, policy-test | Có `id-token`, assume role AWS | Workflow chỉ cấp `contents: read` (+ `security-events: write` để upload SARIF); không dùng `pull_request_target` |
| Nhánh `main` | Nhận thay đổi đã qua PR và 2 check | Push thẳng, force push, xóa nhánh | Branch protection, `enforce_admins` (đã kiểm: push thẳng bị GH006) |
| Publisher (role CI) | Push vào repo tin cậy | Sửa signing rule, IAM, policy Kubernetes | Role `devsecops-publisher`: trust OIDC `sub` = `repo:duy1504@210903593/devsecops-project@1460578199:ref:refs/heads/main` (immutable subject); chỉ push repo `podinfo` + `SignPayload` profile chính (26/11, run 45798939183) |
| Verifier (extension) | Đọc image, chữ ký; kiểm tra thu hồi | Ký, push | Role `devsecops-verifier`, phiên ≤ 1 giờ; `PutImage` bị `AccessDenied` (kiểm mỗi lần refresh) |
| Deployer | Quản lý Deployment/Service trong `app` | Đọc Secret, exec, ephemeral container, sửa policy/webhook, tạo namespace | `k8s/rbac.yaml` (đã kiểm: 14/14 `can-i`, 4/4 yêu cầu thật `Forbidden`; 26/11 thêm 6/6 yêu cầu thật tới Pod đang chạy `Forbidden`; triển khai TC01 bằng chính danh tính này) |

> **Giả định tin cậy (ghi vào phần giới hạn):** danh tính nào có quyền push vào repo tin cậy và quyền ký trên profile đều tạo được image có chữ ký hợp lệ, kể cả image chưa scan. Hướng nâng cấp: ký hoặc attest kết quả scan và kiểm tra attestation ở admission.

### Ba đường xác thực cần tách rõ

| Đường | Mục đích | Trên kind |
|---|---|---|
| GitHub Actions → AWS | Push image, kích hoạt ký | OIDC → role publisher |
| Verifier → ECR/Signer | Đọc chữ ký, kiểm tra thu hồi | Credential ngắn hạn của role verifier, nạp qua Secret runtime (ngoài Git) |
| Kubelet → ECR | Pull image sau khi được chấp nhận | `imagePullSecret` (token ECR hết hạn sau 12 giờ) |

`imagePullSecret` không cấp quyền cho AWS Signer plugin, và credential của verifier không giúp kubelet pull image.

## 4. Các quyết định

Mỗi mục: **bối cảnh → quyết định → lý do → thay thế đã cân nhắc → trạng thái.**

### Q1. Workload: podinfo, tự build từ source

- **Quyết định:** podinfo 6.17.0 (commit `fd3a834`), lấy bằng `scripts/vendor-podinfo.sh`, không sửa mã. Đồ án dùng `Dockerfile` riêng.
- **Lý do:** nhỏ, có sẵn test và `/healthz` `/readyz`, chạy non-root không cần sửa code. Tự build để chữ ký trên ECR là của **đồ án**, không phải chữ ký Cosign của upstream.
- **Thay thế:** Flaskr — phải tự thêm health endpoint, đọc `SECRET_KEY` từ env, đường dẫn SQLite ghi được bởi user non-root.
- **Trạng thái:** ✅ (`docs/upstream.md`).

### Q2. Image: multi-stage, distroless, UID số, một kiến trúc

- **Quyết định:** builder `golang:1.27.4-alpine`, runtime `distroless/static-debian12:nonroot`, cả hai ghim digest; `USER 65532:65532`; chỉ `linux/amd64`.
- **Lý do:** image nhỏ, không có shell. UID phải ở dạng **số**: với `runAsNonRoot`, kubelet không xác minh được user dạng tên. Một kiến trúc tránh phải ký và xác minh index đa nền tảng.
- **Trạng thái:** ✅. Manifest đặt thêm `runAsUser/runAsGroup: 65532`, `readOnlyRootFilesystem`, `emptyDir` cho `/tmp` và `/data` (đã chạy thử: 2/2 Running, ghi `/data` thành công).

### Q3. Build một lần, scan và push cùng một artifact

- **Quyết định:** `verify` build một lần → `docker save image.tar` → SBOM và scan trên chính tar đó → (push vào `main`) upload tar + checksum + `verification.json`. `publish` sẽ tải đúng tar của cùng run, kiểm `sha256sum`, `docker load`, push — **không build lại**.
- **Lý do:** hai lần build có thể ra dependency hoặc base khác nhau, khiến image được scan không phải image được ký.
- **Trạng thái:** ✅ (26/11): `publish` kiểm checksum, `verification.json` (commit/run/attempt/gate) và image ID trước khi push; digest registry = digest push (run 45798939183).

### Q4. Gate lỗ hổng: Trivy, 0 Critical, không nới lỏng

- **Quyết định:** Trivy quét **một lần** ra JSON; gate đếm Critical trên chính JSON đó. Không `--ignore-unfixed`, không `continue-on-error`, không `|| true`. Lỗi công cụ hoặc DB làm job fail.
- **Lý do:** quét hai lần có thể dùng hai bản DB khác nhau, khiến báo cáo và gate lệch nhau. Đề cương yêu cầu chặn mọi Critical, kể cả chưa có bản vá.
- **Thay thế:** Grype.
- **Trạng thái:** ✅ TC03 đạt (4 Critical → exit 1).

### Q5. SBOM: Syft, CycloneDX

- **Quyết định:** `syft docker-archive:image.tar -o cyclonedx-json`; job kiểm định dạng, có component, có `pkg:golang/*`.
- **Thay thế:** `trivy image --format cyclonedx`. Chỉ một SBOM là artifact phát hành.
- **Trạng thái:** ✅ (1032 component).

### Q6. Secret scan: Gitleaks, toàn lịch sử của commit đang kiểm

- **Quyết định:** `gitleaks git . --log-opts=HEAD --redact`, cấu hình `.gitleaks.toml` giữ rule mặc định, thêm rule lab `DEMO_SECRET_` + 32 hex, và allowlist **cấp rule** (điều kiện AND: đúng file và đúng chuỗi) cho 3 dương tính giả trong mã podinfo.
- **Lý do của `--log-opts=HEAD`** (phát sinh 18/11): checkout `fetch-depth: 0` tải mọi nhánh, và mặc định Gitleaks quét mọi ref. Secret trên một nhánh bất kỳ đã làm fail cả PR sạch (run TC03 đầu tiên). Quét từ `HEAD` vẫn bao trọn lịch sử của code sắp merge.
- **Lý do allowlist cấp rule** (phát sinh 17/11): allowlist toàn cục với `paths` bỏ qua cả file, che mất secret khác trong cùng file.
- **Trạng thái:** ✅ TC02 đạt.

### Q7. Ký số: ECR Managed Signing + AWS Signer

- **Quyết định:** repo ECR private `podinfo` (tag IMMUTABLE), signing rule filter đúng tên `podinfo`, platform `Notation-OCI-SHA384-ECDSA`. Đường phát hành không có lệnh ký thủ công.
- **Lý do:** ký tự động khi push, không phải quản lý khóa; chữ ký dạng Notation lưu như OCI referrer.
- **Không chọn:** Cosign/Sigstore — là hệ sinh thái khác, không khớp đề tài.
- **Trạng thái:** ✅ (20/11 bật; 26/11 chạy qua pipeline): mỗi image phát hành có đúng 1 chữ ký của profile chính, độ trễ ký 1,7–2,5 s; publisher không cần `signer:GetSigningProfile`.

### Q8. Kubernetes: kind

- **Quyết định:** kind (node `v1.35.8`, ghim digest) cho phát triển và demo; EKS chỉ là mở rộng.
- **Lý do:** gần như không tốn chi phí. Kyverno 1.19.2 chạy conformance trên Kubernetes 1.33–1.35.
- **Hệ quả:** không có job `deploy` từ GitHub-hosted runner (runner không vào được cụm trên laptop) → triển khai bằng `scripts/deploy.sh`; credential verifier và token pull ECR phải làm mới thủ công.
- **Trạng thái:** ✅ (`scripts/cluster-up.sh`).

### Q9. Admission engine: Kyverno 1.19.2, ghim phiên bản

- **Quyết định:** Kyverno v1.19.2, chart 3.9.2, cài từ OCI `ghcr.io` và kiểm SHA-256 file chart. Helm và Kyverno CLI luôn có `--version`, không `--devel`.
- **Lý do:** extension AWS Signer còn dùng `ClusterPolicy`. 1.19 là bản cuối hỗ trợ đầy đủ loại này; 1.20.0 đã ra (11/2026), vẫn còn CRD nhưng đánh dấu "will be removed". Kho Helm `kyverno.github.io` không truy cập được từ mạng lab nên dùng OCI.
- **Giới hạn:** chính sách hỗ trợ N-1 — 1.19 hết hỗ trợ cộng đồng khi 1.21 phát hành.
- **Thay thế (phương án lùi):** B — xác minh native của Kyverno; C — Ratify + Gatekeeper.
- **Trạng thái:** ✅ cài và chạy trên kind.

### Q10. Policy 1: CEL `ValidatingPolicy`, đúng repo và digest 64 hex

- **Quyết định:** `policies/allowed-image.template.yaml` chỉ cho `<account>.dkr.ecr.<region>.amazonaws.com/podinfo@sha256:` + **đúng 64 ký tự hex**, áp cho cả container và init container, chỉ ở namespace `app` và `demo`, `failurePolicy: Fail`.
- **Lý do:** viết bằng CEL ngay từ đầu để không phải viết lại khi `ClusterPolicy` bị gỡ. Siết 64 hex (phát sinh 17/11) vì mẫu chỉ kiểm tiền tố sẽ chấp nhận `podinfo@sha256:abc`.
- **Ephemeral containers:** chặn bằng RBAC (deployer không có `pods/ephemeralcontainers`), chưa đưa vào policy.
- **Trạng thái:** ✅ test offline 6/6; trên kind TC05/TC07/TC08 bị từ chối, với `ECR_IMAGE` giả (17/11) và ECR thật (26/11).

### Q11. Policy 2: `ClusterPolicy` gọi extension `kyverno-notation-aws` tự build

- **Quyết định:** dùng extension để chạy Notation + AWS Signer plugin (xác minh chữ ký, `trustedIdentities`, thu hồi). Tự build từ `main@58b210b` bằng `scripts/build-notation-ext.sh`: builder và runtime ghim digest, vá thêm `x/net` và `go-jose`, gate 0 Critical.
- **Lý do tự build** (phát sinh 17/11): bản phát hành mới nhất `v1.1` có 6 Critical / 80 High; repo upstream sắp archive, nhánh `main` đã vá nhưng không phát hành. Bản tự build: 0 Critical / 0 High, `go test` đạt.
- **Giới hạn:** dùng bản không phát hành chính thức; upstream sắp ngừng bảo trì.
- **Phát sinh khi chạy trên cụm (26/11):** mọi Pod bị chặn `Token is not authorized` (TokenReview thiếu audience của Kyverno 1.19) và thư viện ghi bearer token ra log → **bản vá p2** cho `kyverno-notation-verifier` v1.1.0; không tắt xác thực token. `caBundle` nhúng CA công khai thay vì cho Kyverno đọc Secret TLS.
- **Trạng thái:** ✅ (26/11): TC01 nhận, TC04/TC06 từ chối đúng lý do, TC09 fail-closed; 4 lượt đều 6/6.

### Q12. Pipeline tự bảo vệ

- **Quyết định:**
  - Action ghim **commit SHA**; Gitleaks, Syft, Trivy, Kyverno CLI cài từ binary ghim phiên bản + SHA-256 (không dùng image hay action `latest`).
  - Job `verify` không có `id-token`; không `pull_request_target`.
  - Upload báo cáo luôn chạy (`if: always()`), còn bước lưu image đã duyệt chỉ chạy khi mọi gate đạt và là push vào `main`.
  - Repo **public** (người dùng chọn 17/11) để dùng branch protection và Code Scanning miễn phí; đã rà không có secret hay account thật trước khi công khai.
- **Lý do:** bài học tj-actions/changed-files (2025) — chính pipeline là một phần của chuỗi cung ứng.
- **Trạng thái:** ✅ (branch protection kiểm qua API; secret scanning + push protection bật).

### Q13. Triển khai bằng digest

- **Quyết định:** `scripts/deploy.sh` lấy `APP_IMAGE_REF` (`<ECR_IMAGE>@sha256:…`) từ `release.json` của run thành công trên `main`, render manifest cuối cùng rồi mới apply. Không apply bản có tag rồi `kubectl set image`.
- **Lý do:** digest cố định chính xác nội dung đã scan, đã ký và được xác minh; tag có thể bị trỏ sang image khác.
- **Trạng thái:** ✅ (26/11): `fetch-release.sh` + `deploy.sh`, chạy dưới danh tính deployer; 2 Pod `Running`, `spec.image` và `status.imageID` đúng digest phát hành (TC01).

## 5. Truy vết

| Mắt xích | Liên kết bằng | Tự động / thủ công |
|---|---|---|
| Commit → run CI | `GITHUB_SHA`, run ID | Tự động |
| Run → image | `verification.json`: image ID, SHA-256 của `image.tar` | Tự động |
| Image → SBOM, báo cáo lỗ hổng | SHA-256 của `sbom.cdx.json`, `trivy.json` trong `verification.json` | Tự động |
| Image → digest trên ECR → chữ ký | `release.json` (job `publish`): digest, tag `sha-<commit12>-run-<id>-<attempt>`, profile, `COMPLETE` | Tự động |
| `release.json` → Pod | `fetch-release.sh` → `deploy.sh` render digest | Thủ công (2 lệnh; không có job `deploy` trên kind) |
| Pod → digest | `spec.image`, `status.imageID` đối chiếu `release.json` | Kiểm tự động trong `deploy.sh` |

## 6. Giới hạn

- Managed Signing ký mọi image push vào repo khớp filter; "chỉ image đạt mới được ký" dựa vào pipeline và quyền push.
- Chữ ký ràng buộc digest với danh tính, nhưng không ký SBOM hay kết quả scan.
- Admission không gỡ Pod đã chạy khi chữ ký bị thu hồi hoặc CVE mới được công bố.
- Kết quả Trivy phụ thuộc DB tại thời điểm quét; không phát hiện zero-day.
- Kyverno 1.19 hết hỗ trợ cộng đồng khi 1.21 phát hành; extension là bản tự build từ upstream sắp archive.
- Trên kind, impersonation để kiểm RBAC chạy từ kubeconfig quản trị.
- Trên kind, credential verifier sống tối đa 1 giờ (role chaining từ SSO): hết hạn thì mọi Pod mới trong `app`/`demo` bị chặn tới khi chạy `refresh-lab-credentials.sh` (fail-closed). EKS dùng IRSA/Pod Identity sẽ tự làm mới.
- Extension trả HTTP 406 khi xác minh thất bại → Kyverno ghi `error (blocked)` thay vì `fail`; cache xác minh đang tắt.
- Bước `release.json` → Pod trên kind là thủ công (`deploy.sh`), không có job `deploy`.
