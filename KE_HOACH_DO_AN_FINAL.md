# KẾ HOẠCH & HƯỚNG DẪN THỰC HIỆN ĐỒ ÁN (BẢN CUỐI)

**Đề tài:** Xây dựng quy trình bảo mật chuỗi cung ứng phần mềm cho container image sử dụng SBOM, Amazon ECR Managed Signing và kiểm soát triển khai trên Kubernetes

**Môn học:** Công nghệ DevOps và Ứng dụng · **Cơ sở:** `Dự kiến.txt` · **Ngày soạn:** 04/11/2026
**Phiên bản:** bản cuối, hợp nhất từ `KE_HOACH_DO_AN.md` (bản nền) và các điểm mạnh của `KE_HOACH_DO_AN_DEVSECOPS.md`

> Đây là **kế hoạch và hướng dẫn**, chưa phải hệ thống đã triển khai. Các đoạn cấu hình có `<...>` hoặc phụ thuộc phiên bản là **mẫu cần hoàn thiện và kiểm chứng**. Mọi số liệu, kết quả, ảnh minh chứng trong báo cáo phải lấy từ thực nghiệm thật.

> ⚠️ **Việc cần làm ngay trong tuần này:** ghim Kyverno **1.19.x** (Helm chart với `--version` cố định) trước khi chạy spike ở mục 6. Kyverno 1.20 dự kiến phát hành khoảng 11/2026 (đã có `v1.20.0-rc.1`, gắn tag 02/11/2026) và dự kiến gỡ bỏ `ClusterPolicy` — loại policy mà extension xác minh chữ ký AWS Signer đang dùng (mục 3.3). Spike bắt đầu tuần 1 và phải đạt chậm nhất cuối tuần 2. Các quyết định công nghệ đã chốt nằm ở mục 3.4.

---

## Mục lục

1. [Tổng quan & mục tiêu](#1-tổng-quan--mục-tiêu)
2. [Kiến trúc & mô hình tin cậy](#2-kiến-trúc--mô-hình-tin-cậy)
3. [Lựa chọn công nghệ & phiên bản](#3-lựa-chọn-công-nghệ--phiên-bản)
4. [Chuẩn bị môi trường](#4-chuẩn-bị-môi-trường)
5. [Cấu trúc repository](#5-cấu-trúc-repository)
6. [Giai đoạn 0 – Thử nghiệm tích hợp sớm (đường găng)](#6-giai-đoạn-0--thử-nghiệm-tích-hợp-sớm-đường-găng)
7. [Giai đoạn 1 – Workload mẫu & container hóa](#7-giai-đoạn-1--workload-mẫu--container-hóa)
8. [Giai đoạn 2 – Hạ tầng AWS & phân quyền](#8-giai-đoạn-2--hạ-tầng-aws--phân-quyền)
9. [Giai đoạn 3 – Pipeline GitHub Actions](#9-giai-đoạn-3--pipeline-github-actions)
10. [Giai đoạn 4 – Kubernetes & triển khai](#10-giai-đoạn-4--kubernetes--triển-khai)
11. [Giai đoạn 5 – Kyverno admission policy](#11-giai-đoạn-5--kyverno-admission-policy)
12. [Giai đoạn 6 – Kịch bản kiểm thử & bằng chứng](#12-giai-đoạn-6--kịch-bản-kiểm-thử--bằng-chứng)
13. [Lịch trình thực hiện](#13-lịch-trình-thực-hiện)
14. [Chi phí, rủi ro & xử lý lỗi](#14-chi-phí-rủi-ro--xử-lý-lỗi)
15. [Dàn ý báo cáo](#15-dàn-ý-báo-cáo)
16. [Demo & câu hỏi bảo vệ](#16-demo--câu-hỏi-bảo-vệ)
17. [Thu dọn tài nguyên](#17-thu-dọn-tài-nguyên)
18. [Checklist hoàn thành](#18-checklist-hoàn-thành)
19. [Tài liệu tham khảo](#19-tài-liệu-tham-khảo)

---

## 1. Tổng quan & mục tiêu

### 1.1. Vấn đề

Các cuộc tấn công chuỗi cung ứng phần mềm (SolarWinds 2020, Codecov 2021, xz-utils 2024, tj-actions/changed-files 2025…) cho thấy kẻ tấn công có thể chèn mã độc vào **mã nguồn, dependency, công cụ build hoặc registry** thay vì tấn công trực tiếp ứng dụng. Một image "chạy được" chưa đủ để kết luận image đó đáng tin cậy.

| Rủi ro | Ví dụ | Biện pháp trong đồ án |
|---|---|---|
| Lộ thông tin bí mật | Commit AWS key, token vào Git | Gitleaks quét secret trong pipeline |
| Dependency / base image có lỗ hổng | Base image cũ chứa CVE Critical | Trivy quét image, chặn nếu có Critical |
| Không biết image chứa gì | Không truy vết được thành phần khi có CVE mới | Sinh SBOM (CycloneDX) bằng Syft |
| Image bị thay thế / giả mạo | Push image lạ lên registry | ECR Managed Signing ký tự động bằng AWS Signer |
| Triển khai từ nguồn không tin cậy | `kubectl run --image=docker.io/...` | Kyverno chặn registry/repository không được phép |
| Triển khai image chưa ký | Image push tay, bỏ qua pipeline | Kyverno + Notation xác minh chữ ký trước khi tạo Pod |

**Câu hỏi nghiên cứu:** Có thể phối hợp kiểm soát trong CI và kiểm soát tại Kubernetes admission để phát hiện/ngăn chặn 4 tình huống trong đề cương, đồng thời **truy vết từ Pod về image, SBOM và commit** hay không?

### 1.2. Kết quả bắt buộc & tiêu chí nghiệm thu

| Mã | Kết quả | Tiêu chí nghiệm thu |
|---|---|---|
| KQ1 | Workload mã nguồn mở được container hóa | Chạy được trên Docker và Kubernetes, có test và health endpoint |
| KQ2 | CI có các cổng kiểm soát | Test fail / secret / Critical làm pipeline thất bại và **bỏ qua bước phát hành** |
| KQ3 | SBOM & báo cáo | Tải được artifact, JSON hợp lệ, gắn được với commit và digest image |
| KQ4 | ECR Managed Signing | Có signing rule; image phát hành có trạng thái `COMPLETE` với đúng profile; pipeline **không** gọi lệnh ký thủ công |
| KQ5 | Admission policy | Image đúng repository + digest + chữ ký tin cậy được chấp nhận; image vi phạm bị từ chối |
| KQ6 | Bộ kiểm thử | 1 ca hợp lệ + đủ 4 ca bất thường trong đề cương (+ các ca mở rộng nếu kịp) |
| KQ7 | Khả năng tái lập | Có cấu hình, bộ phiên bản, hướng dẫn dựng lại, bằng chứng và mô tả giới hạn |

### 1.3. Phạm vi

- **Bắt buộc:** 1 ứng dụng, 1 kiến trúc image (`linux/amd64`), 1 AWS account, 1 region, 1 namespace ứng dụng.
- **Mở rộng (chỉ làm sau khi KQ1–KQ7 đạt):** CD tự động hoàn toàn / GitOps (Argo CD), Terraform, ký/attest SBOM, SLSA provenance, runtime security (Falco).
- **Phạm vi kết luận:** đồ án kiểm soát **một số** rủi ro chuỗi cung ứng trong môi trường thực nghiệm. Không kết luận "image có chữ ký là an toàn", "chặn 100% tấn công" hay "đạt SLSA level X" nếu chưa đánh giá đủ yêu cầu.

---

## 2. Kiến trúc & mô hình tin cậy

### 2.1. Luồng tổng thể

```mermaid
flowchart LR
    Dev[Developer] -->|PR / push| GH[GitHub Repo]

    subgraph CI["GitHub Actions"]
        subgraph V["Job verify (không có quyền AWS)"]
            T[Unit test] --> S[Gitleaks]
            S --> B[Build 1 lần → image.tar]
            B --> SB[Syft SBOM]
            SB --> TV[Trivy scan → gate CRITICAL]
        end
        TV -->|FAIL| X[[Dừng, lưu báo cáo]]
        TV -->|PASS + nhánh main| P["Job publish (OIDC)<br/>load đúng image.tar → push"]
        P --> W[Chờ ký COMPLETE<br/>→ release.json]
    end

    GH --> T
    P --> ECR[(Amazon ECR)]
    ECR -->|Managed Signing| SIG[AWS Signer]
    SIG -->|chữ ký Notation<br/>OCI referrer| ECR

    subgraph K8S["Kubernetes"]
        API[kube-apiserver] --> KY{Kyverno}
        KY -->|đúng repo + digest| EXT[Verifier<br/>Notation + AWS Signer plugin]
        EXT -->|chữ ký hợp lệ| POD[Pod chạy]
        KY -->|vi phạm| DENY[[Từ chối]]
        EXT -->|không ký / sai signer / lỗi xác minh| DENY
    end

    W -->|image@sha256:digest| API
    EXT -.->|đọc chữ ký| ECR
    EXT -.->|kiểm tra thu hồi| SIG
```

**Nguyên tắc defense in depth:** pipeline là lớp 1 (ngăn image xấu được phát hành), admission là lớp 2 (ngăn image không đi qua pipeline được chạy, kể cả khi ai đó gọi `kubectl` trực tiếp).

### 2.2. Vai trò & giới hạn của từng lớp

| Cơ chế | Trả lời câu hỏi | Giới hạn |
|---|---|---|
| Unit test | Hành vi đã test có đúng không? | Không chứng minh bảo mật |
| Gitleaks | Có chuỗi khớp quy tắc secret không? | Có false positive / bỏ sót |
| SBOM | Image chứa những thành phần nào? | Không phải chứng nhận an toàn |
| Trivy gate | Có CVE được DB hiện tại đánh giá Critical không? | Kết quả thay đổi theo thời gian, không phát hiện zero-day |
| Chữ ký | Digest này có được ký bởi danh tính tin cậy không? | **Không** tự chứng minh rằng các bước scan đã đạt |
| Registry policy | Image có đúng account/region/repository không? | Chỉ kiểm tra nguồn là chưa đủ |
| Admission | Yêu cầu tạo Pod có đáp ứng policy không? | Không tự gỡ Pod đã chạy trước đó |

> **ECR Managed Signing không đọc kết quả Trivy hay Gitleaks.** Nó ký **mọi** image được push vào repository khớp filter. Việc "chỉ image đạt yêu cầu mới được ký" là nhờ **pipeline + phân quyền push**, cần nói rõ trong báo cáo.

### 2.3. Ranh giới tin cậy

1. **PR (chưa tin cậy):** chạy test + scan, **không** có `id-token: write`, không assume được role AWS.
2. **Nhánh `main`:** branch protection, bắt buộc PR + review + CI checks; hạn chế người sửa workflow.
3. **Publisher (role CI):** chỉ push vào repository tin cậy; không sửa signing rule, IAM, policy Kubernetes.
4. **Verifier (extension trong cụm):** chỉ đọc image/chữ ký và kiểm tra thu hồi; không ký, không push.
5. **Deployer:** chỉ quản lý workload trong namespace ứng dụng; không sửa Kyverno, trust policy, webhook, namespace ngoại lệ.

> **Giả định tin cậy cần ghi vào phần giới hạn:** bất kỳ danh tính nào có quyền push vào repo tin cậy **và** quyền `signer:SignPayload` trên profile đều tạo được image có chữ ký hợp lệ — kể cả image chưa scan. Hướng nâng cấp: ký/attest kết quả scan và kiểm tra attestation ở admission.

### 2.4. Ba đường xác thực cần tách rõ

| Đường | Mục đích | Trên EKS | Trên kind (local) |
|---|---|---|---|
| GitHub Actions → AWS | Push image, kích hoạt ký | OIDC → role publisher | OIDC → role publisher |
| Verifier → ECR/Signer | Đọc chữ ký, kiểm tra thu hồi | IRSA/Pod Identity cho ServiceAccount của extension | Credential ngắn hạn của role verifier, nạp qua Secret runtime (ngoài Git) |
| Kubelet → ECR | Pull image sau khi được chấp nhận | IAM role của node | `imagePullSecret` (token ECR hết hạn sau 12 giờ) |

`imagePullSecret` không cấp quyền cho AWS Signer plugin, và ngược lại credential của verifier không giúp kubelet pull image.

---

## 3. Lựa chọn công nghệ & phiên bản

### 3.1. Bộ công cụ

| Thành phần | Lựa chọn chính | Lý do | Thay thế |
|---|---|---|---|
| Workload | **podinfo** (Go) | Nhỏ, có sẵn test, `/healthz` `/readyz`, chạy non-root, không cần sửa code | Flaskr (tutorial Flask – có blog + test, nhưng phải tự thêm health endpoint, đọc `SECRET_KEY` từ env) |
| Container | Docker multi-stage, 1 kiến trúc `linux/amd64` | Tránh phức tạp ký/verify multi-platform index | – |
| CI | GitHub Actions | Theo đề cương | – |
| Secret scan | **Gitleaks CLI** | Exit code để chặn, quét lịch sử git, `--redact` | TruffleHog |
| SBOM | **Syft** (CycloneDX JSON) | Chuẩn, đọc trực tiếp từ `image.tar` | Trivy `--format cyclonedx` |
| Vulnerability | **Trivy** | Quét tar trước push, JSON/SARIF | Grype |
| Registry | Amazon ECR private | Theo đề cương | – |
| Ký số | **ECR Managed Signing + AWS Signer** | Ký tự động khi push, không quản lý khóa | – (không thay bằng `notation sign` trong đường phát hành) |
| Kubernetes | **kind** để phát triển; **EKS** cho demo/CD tự động nếu đủ ngân sách | Xem 3.2 | minikube |
| Admission | **Kyverno** + extension **kyverno-notation-aws** | Extension chạy Notation + AWS Signer plugin, có kiểm tra thu hồi và giới hạn theo signing profile | Ratify + OPA Gatekeeper |
| Xác minh thủ công | Notation CLI + AWS Signer plugin | Chẩn đoán độc lập trước khi tích hợp admission | – |

### 3.2. kind hay EKS?

| Tiêu chí | kind | EKS |
|---|---|---|
| Chi phí | Gần như 0 (chỉ ECR) | Control plane + node + mạng (NAT, LB) |
| Credential verifier | Credential ngắn hạn qua Secret, phải làm mới | IRSA/Pod Identity, gọn hơn |
| Pull ECR | `imagePullSecret`, làm mới mỗi 12 giờ | Node role, không cần secret |
| Job `deploy` từ GitHub-hosted runner | **Không** truy cập được cụm trên laptop → deploy bằng `scripts/deploy.sh` | Được (cần Access Entry) |

**Quyết định đề xuất:** làm spike + phát triển policy trên **kind**. Nếu ngân sách cho phép hoặc giảng viên muốn mô hình cloud, dựng **EKS** ở giai đoạn cuối để có job `deploy` tự động và IRSA. Không giả định cấu hình IRSA của EKS chạy được nguyên vẹn trên kind.

### 3.3. Quy tắc chốt phiên bản (rất quan trọng)

- **Kyverno – lộ trình gỡ `ClusterPolicy`** (theo tài liệu Kyverno):

  | Bản | Thời điểm | Trạng thái `ClusterPolicy` / `Policy` / `CleanupPolicy` |
  |---|---|---|
  | 1.17 | 02/2026 | Đánh dấu deprecated |
  | 1.18 | 04/2026 | Chỉ nhận bản vá nghiêm trọng |
  | 1.19 | 08/2026 | Deprecated chính thức — **bản cuối hỗ trợ đầy đủ**; các policy CEL đạt tương đương tính năng (kể cả xác minh image) |
  | 1.20 | ~11/2026 (dự kiến); đã có `v1.20.0-rc.1` (gắn tag 02/11/2026) | **Gỡ bỏ** (theo kế hoạch). Riêng rc.1 **vẫn còn** CRD `ClusterPolicy`, đánh dấu deprecated kèm cảnh báo "will be removed" |

  Mẫu Kyverno policy của extension `kyverno-notation-aws` dùng `ClusterPolicy` → **quyết định của đồ án: ghim Kyverno 1.19.x** (chart Helm có `--version` cố định; không cài `latest`, không để công cụ tự nâng cấp).
  - Policy allowlist (Policy 1, mục 11.2) viết dạng CEL `ValidatingPolicy` ngay từ đầu để không phải viết lại; chỉ policy gọi extension (Policy 2) dùng `ClusterPolicy` theo mẫu của release extension.
  - Từ 1.19, CRD được cài qua chart phụ thuộc `kyverno-api` → kiểm tra lệnh Helm theo đúng bản.
  - Đã kiểm tra ngày 04/11/2026: bản vá mới nhất là **Kyverno v1.19.2** ↔ **Helm chart 3.9.2** (phát hành 20/10/2026 UTC). Bằng chứng và lệnh kiểm tra lại nằm trong `docs/versions.md`. Kiểm tra lại ngay trước khi cài, vì 1.20.0 có thể ra bất cứ lúc nào.
  - Chưa rõ bản 1.20.0 chính thức có thực sự gỡ `ClusterPolicy` hay lùi lịch (rc.1 vẫn còn CRD). Khi 1.20.0 ra, đọc release notes để cập nhật phần giới hạn; quyết định ghim 1.19.x không đổi.
  - **Giới hạn phải ghi vào báo cáo:** từ 1.18, Kyverno theo mô hình hỗ trợ **N-1** ("main + 1"): chỉ bản minor hiện tại và bản ngay trước đó nhận bản vá cộng đồng, và chỉ cho CVE mức critical/high cùng các lỗi nghiêm trọng khác (bài công bố 1.18 gọi là "roughly 3 months of community patch support"). Vì vậy khi 1.20.0 phát hành, 1.19 trở thành bản N-1 và **vẫn được vá** cho tới khi 1.21 phát hành; sau đó 1.19 hết hỗ trợ cộng đồng. Đồ án ghim một nhánh đang ở cuối vòng đời vì extension AWS Signer còn phụ thuộc `ClusterPolicy`. Ghi lý do ghim và mốc hết hỗ trợ dự kiến vào `docs/versions.md` và phần "Giới hạn".
  - Chuyển toàn bộ sang CEL (kể cả xác minh chữ ký) là hướng phát triển; chỉ làm khi có release extension/hướng dẫn tương thích, và phải chạy lại TC01, TC04, TC06, TC09.
- Ghi toàn bộ phiên bản (Kubernetes, Kyverno + chart, extension, Notation, AWS Signer plugin, Trivy, Syft, Gitleaks, Docker, AWS CLI, eksctl/kind) vào `docs/versions.md` **sau khi spike ở mục 6 chạy được**.
- Pin base image theo **digest**, GitHub Actions theo **commit SHA đầy đủ**, image công cụ (gitleaks…) theo version cụ thể.

### 3.4. Các quyết định đã chốt

| Quyết định | Lựa chọn của đồ án | Chỉ đổi khi |
|---|---|---|
| Workload | **podinfo**, tự build từ source tại tag đã pin | Giảng viên yêu cầu ứng dụng có nghiệp vụ (đăng nhập, CRUD) → Flaskr: phải tự thêm health endpoint, đọc `SECRET_KEY` từ env, đường dẫn SQLite ghi được bởi user non-root |
| Tạo SBOM | **Syft** (CycloneDX JSON) | Muốn ít công cụ → `trivy image --format cyclonedx`; chỉ một SBOM là artifact phát hành |
| Quét lỗ hổng | **Trivy**, gate 0 Critical | – |
| Cụm Kubernetes | **kind** cho phát triển và demo chính | Cần job `deploy` tự động / IRSA → EKS ở giai đoạn cuối (mục 10.2) |
| Admission | **Kyverno 1.19.x** + `kyverno-notation-aws` | Spike không đạt → phương án B/C (mục 6.3) |
| Kiến trúc image | `linux/amd64` | Node là ARM → đổi platform; không làm multi-arch trong MVP |
| Triển khai | `scripts/deploy.sh` trên máy có cụm | Có EKS → job `deploy` |

Chọn một bộ và làm xuyên suốt; ghi quyết định và lý do vào `docs/architecture.md`. Không chạy song song hai workload hoặc hai bộ tạo SBOM trong MVP.

---

## 4. Chuẩn bị môi trường

### 4.1. Tài khoản

- **GitHub:** repo cá nhân (public/private).
- **AWS:** bật MFA cho root, dùng IAM Identity Center/SSO hoặc user riêng; đặt **AWS Budgets** cảnh báo ~10–20 USD. Tốt nhất dùng **account/registry riêng cho lab** vì signing configuration ở **cấp registry**.
- **Region:** đề xuất `ap-southeast-1` (Singapore). Kiểm tra region đã hỗ trợ ECR Managed Signing; signing profile và registry phải **cùng region**.

### 4.2. Công cụ (Windows 11)

Đề xuất làm việc trong **WSL2 Ubuntu** + Docker Desktop (bật WSL integration); `C:\Teo\DevOps` tương ứng `/mnt/c/Teo/DevOps`. Các lệnh nhiều dòng trong tài liệu là **Bash**, không dán vào PowerShell.

```powershell
# PowerShell – cài phần nền
winget install Docker.DockerDesktop
wsl --install -d Ubuntu
```

Trong WSL2 cài: `git`, `go`, `aws` CLI v2 (bản mới, có API Managed Signing), `kubectl`, `helm`, `kind`, `eksctl` (nếu dùng EKS), `jq`, `envsubst`, `trivy`, `syft`, `gitleaks`, `notation` + **AWS Signer plugin**, `kyverno` CLI. Tài nguyên Docker đề xuất: ≥ 4 CPU, 8 GB RAM.

Kiểm tra:

```bash
docker version; aws --version; kubectl version --client; helm version; kind version
trivy --version; syft version; gitleaks version; notation version; notation plugin ls
aws sts get-caller-identity
aws ecr put-signing-configuration help   # xác nhận CLI có API Managed Signing
```

Không lưu token, credential, kubeconfig vào repository.

### 4.3. Biến cấu hình thống nhất

```bash
export AWS_REGION=ap-southeast-1
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR_REPOSITORY=podinfo
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ECR_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}"
export SIGNING_PROFILE=podinfo_signing_profile
export SIGNING_PROFILE_ARN="arn:aws:signer:${AWS_REGION}:${AWS_ACCOUNT_ID}:/signing-profiles/${SIGNING_PROFILE}"
export WRONG_SIGNING_PROFILE=podinfo_wrong_signer        # profile B – chỉ dùng tạo fixture TC06
export WRONG_SIGNING_PROFILE_ARN="arn:aws:signer:${AWS_REGION}:${AWS_ACCOUNT_ID}:/signing-profiles/${WRONG_SIGNING_PROFILE}"
export APP_NAMESPACE=app
export TEST_NAMESPACE=demo
```

---

## 5. Cấu trúc repository

```
supply-chain-demo/
├── .github/workflows/ci-cd.yml
├── app/                         # mã nguồn podinfo (giữ LICENSE upstream)
├── Dockerfile
├── .dockerignore
├── .gitleaks.toml               # rule mặc định + rule DEMO_SECRET_ cho kiểm thử
├── infra/aws/
│   ├── signing-config.template.json
│   ├── lifecycle-policy.json        # chỉ chọn tag tiền tố sha- (mục 8.1)
│   ├── oidc-trust-publisher.template.json
│   ├── oidc-trust-deployer.template.json
│   ├── publisher-policy.template.json
│   └── verifier-policy.template.json
├── infra/eks-cluster.yaml       # nếu dùng EKS
├── k8s/                         # namespace, deployment.template.yaml, service, rbac
├── policies/
│   ├── allowed-image.template.yaml
│   ├── verify-signer.template.yaml
│   ├── trustpolicy.template.yaml
│   ├── truststore.yaml
│   └── tests/allowed-image/     # test offline Policy 1 (mục 11.4)
│       ├── kyverno-test.yaml
│       └── resources.template.yaml
├── scripts/
│   ├── wait-signature.sh
│   ├── policy-test.sh               # render + kyverno test; dùng chung cho local và CI
│   ├── refresh-lab-credentials.sh   # kind: làm mới pull secret + credential verifier
│   ├── deploy.sh
│   └── demo-tests.sh
├── tests/admission/             # manifest cho từng ca TC04–TC10
├── demo/
│   ├── Dockerfile.vulnerable    # fixture TC03 đã xác nhận có Critical
│   └── commands.md              # lệnh demo theo thứ tự, dùng biến cấu hình
└── docs/
    ├── versions.md
    ├── architecture.md          # quyết định ở mục 3.4 và lý do
    ├── upstream.md              # URL, commit, ngày lấy mã podinfo
    ├── test-results.md
    ├── demo-script.md
    └── evidence/TCxx/<timestamp>/   # bằng chứng đã che thông tin nhạy cảm
```

`.gitignore`: `.env`, `*.tar`, kubeconfig, file chứa token, `reports/`, `policies/rendered/`. Báo cáo lớn để ở GitHub artifact; chỉ commit bằng chứng chọn lọc.

---

## 6. Giai đoạn 0 – Thử nghiệm tích hợp sớm (đường găng)

**Đường găng:** `Managed Signing → notation verify → extension verify → Kyverno deny`. Đây là phần **rủi ro kỹ thuật cao nhất**; **bắt đầu ngay tuần 1** bằng một image nhỏ và phải đạt tiêu chí ở mục 6.2 **chậm nhất cuối tuần 2** (cuối tuần 1 nếu theo lịch 6 tuần), trước khi đầu tư vào pipeline.

### 6.1. Trình tự

1. Tạo ECR repo `podinfo` (immutable tag) nhưng **chưa bật signing rule**.
2. Build một image thử, scan đạt, gắn nhãn `demo.fixture=unsigned-baseline`, push bằng quyền quản trị lab với tag `unsigned-baseline` → ghi digest **`D_unsigned`**.
3. Tạo **profile B** — signing profile chỉ dùng cho fixture (vd. `podinfo_wrong_signer`, mục 8.2); profile này **không** nằm trong `trustedIdentities`. Build image thứ hai khác nội dung, gắn nhãn `demo.fixture=wrong-signer-baseline`, push tag `wrong-signer-baseline` → ghi **`D_wrongsigner`**, rồi ký thủ công bằng profile B:

   ```bash
   notation sign --plugin com.amazonaws.signer.notation.plugin \
     --id "$WRONG_SIGNING_PROFILE_ARN" "${ECR_IMAGE}@${D_WRONGSIGNER}"
   notation ls "${ECR_IMAGE}@${D_WRONGSIGNER}"        # chỉ cho biết SỐ chữ ký → phải đúng 1
   notation inspect "${ECR_IMAGE}@${D_WRONGSIGNER}"   # chi tiết chữ ký → đối chiếu là của profile B
   ```

   `notation ls` không cho biết chữ ký thuộc profile nào; với chữ ký AWS Signer, phần thuộc tính đã ký trong `notation inspect` thường có `com.amazonaws.signer.signingProfileVersion` (ARN của profile version) — đối chiếu trên output thực tế. Ký thủ công ở đây **chỉ để tạo fixture TC06**, không thuộc đường phát hành. Phải làm **trước bước 5** — sau khi bật signing rule, mọi lần push vào `podinfo` đều được ký thêm bằng profile tin cậy. Dù TC06 là ca mở rộng, vẫn nên tạo fixture ngay trong spike vì sau này không tạo lại được theo cách này.
4. `notation verify` với `D_unsigned` và `D_wrongsigner` (trust policy chỉ tin profile chính) → cả hai phải **thất bại**: một vì không có chữ ký, một vì sai danh tính ký.
5. Tạo signing profile chính, bật ECR Managed Signing cho repo `podinfo` (mục 8.2–8.3).
6. Build image thứ ba **khác nội dung** (đổi nhãn/file) → push → ghi **`D_signed`**.
7. Chờ `COMPLETE` (mục 8.6), `notation verify` `D_signed` → **thành công**.
8. Tạo kind, cài Kyverno **1.19.x đã ghim** + extension (release đã chốt), cấu hình trust + credential, namespace `app`/`demo` và pull secret (mục 10.1).
9. Pod dùng `D_signed` → **được chấp nhận**; Pod dùng `D_unsigned` (cùng repo được phép) → **bị từ chối vì thiếu chữ ký**; Pod dùng `D_wrongsigner` → **bị từ chối vì sai người ký**.
10. Lưu log, cấu hình chạy được, **chốt bộ phiên bản**.

> **Tránh làm hỏng đối chứng:** đổi tag của cùng một digest không tạo ra image unsigned mới; push lại hoặc gắn thêm tag cho fixture sau khi bật signing có thể khiến nó được ký. Lifecycle policy chỉ chọn tag tiền tố `sha-` nên không bao giờ chạm tới fixture (mục 8.1). Trước mỗi buổi demo, kiểm tra lại: `notation ls` cho thấy `D_unsigned` có 0 chữ ký và `D_wrongsigner` có đúng 1 chữ ký; `notation inspect` xác nhận chữ ký đó thuộc profile B. Dùng **cùng repository** cho ca unsigned và sai người ký để cô lập đúng nguyên nhân bị từ chối (không phải sai nguồn).

### 6.2. Tiêu chí qua spike

- `D_signed` được ký bởi Managed Signing, **không** dùng `notation sign`.
- `notation verify` pass với `D_signed`, fail với `D_unsigned` và `D_wrongsigner`.
- Kyverno thực sự **deny** (không chỉ cảnh báo Audit).
- **Fail-closed:** tạm tắt verifier → yêu cầu Pod mới bị chặn; khôi phục → pass lại.
- Giải thích được 3 đường xác thực ở mục 2.4.

### 6.3. Nếu spike không thành

Thứ tự lùi: **A** extension `kyverno-notation-aws` → **B** Kyverno native (Notary / `ImageValidatingPolicy` với chứng chỉ gốc AWS Signer) → **C** Ratify + Gatekeeper (AWS có hướng dẫn chính thức). Mỗi phương án thử tối đa 2–3 ngày. **Không** giải quyết bằng cách đổi trust level sang `skip`, tắt TLS, tin mọi signer, hay chuyển webhook sang `Ignore`. Ghi lại quá trình — đây là nội dung tốt cho mục "Khó khăn và giải pháp".

---

## 7. Giai đoạn 1 – Workload mẫu & container hóa

### 7.1. Lấy mã nguồn

```bash
git clone https://github.com/stefanprodan/podinfo.git /tmp/podinfo
cd /tmp/podinfo && git checkout <tag-đã-chọn>      # pin tag/commit
cp -r /tmp/podinfo/. ./app/
go -C app test ./...
```

Ghi URL, tag/commit, ngày lấy mã, license vào `docs/upstream.md`. Không tuyên bố tự phát triển phần mã kế thừa — đóng góp của đồ án là **quy trình bảo mật**, workload chỉ là minh họa.

### 7.2. Dockerfile (multi-stage, distroless, non-root)

```dockerfile
# <GO_VERSION>: lấy từ dòng `go`/`toolchain` trong app/go.mod của tag podinfo đã chọn
# <digest>:     docker buildx imagetools inspect golang:<GO_VERSION>-alpine
FROM golang:<GO_VERSION>-alpine@sha256:<digest> AS builder
ENV GOTOOLCHAIN=local
WORKDIR /src
COPY app/go.mod app/go.sum ./
RUN go mod download
COPY app/ .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/podinfo ./cmd/podinfo

FROM gcr.io/distroless/static-debian12:nonroot@sha256:<digest>
WORKDIR /home/app
COPY --from=builder /out/podinfo /home/app/podinfo
COPY --from=builder /src/ui /home/app/ui
EXPOSE 9898
# UID/GID dạng SỐ của user nonroot trong distroless. Không dùng `USER nonroot:nonroot`:
# với runAsNonRoot, kubelet không xác minh được user dạng tên → CreateContainerConfigError
USER 65532:65532
ENTRYPOINT ["/home/app/podinfo", "--port=9898", "--ui-path=/home/app/ui"]
```

- **Không cố định phiên bản Go theo ví dụ cũ:** đọc bằng `grep -E '^(go|toolchain) ' app/go.mod`. `GOTOOLCHAIN=local` khiến build báo lỗi rõ ràng nếu image Go cũ hơn yêu cầu, thay vì tự tải toolchain nằm ngoài phạm vi đã pin.
- Điều chỉnh đường dẫn `cmd/podinfo`, `ui` theo đúng phiên bản podinfo.
- **Tự build từ source** của tag đã pin; không kéo image podinfo có sẵn rồi gắn tag. Chữ ký Cosign của image upstream không phải bằng chứng ECR Managed Signing của đồ án.
- **User phải ở dạng số** (`65532:65532`). Manifest cũng đặt `runAsUser`/`runAsGroup: 65532` (mục 10.3) để không phụ thuộc metadata của image.
- podinfo mặc định ghi dữ liệu vào `--data-path=/data` (endpoint `/store`). Image distroless không có thư mục này và root filesystem chỉ đọc trên Kubernetes → manifest mount `emptyDir` vào `/data` (mục 10.3).
- `.dockerignore` loại `.git`, `reports/`, `*.tar`, `.env`… nhưng **không** loại nhầm source/`go.sum`.
- Không đưa secret vào Dockerfile, build arg hoặc layer.

### 7.3. Kiểm tra local

```bash
docker build --platform linux/amd64 -t podinfo:local .
docker run --rm -p 9898:9898 podinfo:local          # curl localhost:9898/healthz
docker save podinfo:local -o image.tar
syft docker-archive:image.tar -o cyclonedx-json > sbom.cdx.json
trivy image --input image.tar --severity HIGH,CRITICAL
gitleaks git . --redact -v
```

**Đầu ra:** Dockerfile, test pass, ảnh giao diện, log health check, kích thước image, số CVE ban đầu.

---

## 8. Giai đoạn 2 – Hạ tầng AWS & phân quyền

### 8.1. ECR repository

```bash
aws ecr create-repository --region "$AWS_REGION" \
  --repository-name "$ECR_REPOSITORY" \
  --image-tag-mutability IMMUTABLE \
  --encryption-configuration encryptionType=KMS
```

- `IMMUTABLE`: tag không bị ghi đè → chống thay thế image.
- **Tag phát hành phải duy nhất mỗi lần chạy**, ví dụ `sha-<commit12>-run-<run_id>-<attempt>`; nếu chỉ dùng commit SHA, chạy lại workflow sẽ lỗi do tag immutable. Deployment luôn tham chiếu **digest**.
- Tạo fixture `unsigned-baseline` và `wrong-signer-baseline` (mục 6) **trước** khi bật signing rule.

**Lifecycle policy.** Rule của ECR chỉ **chọn image để xóa**, không có cơ chế "loại trừ" một tag. Vì vậy chỉ viết rule cho tag phát hành có tiền tố `sha-`; các fixture (`unsigned-baseline`, `wrong-signer-baseline`) không khớp rule nào nên không bao giờ bị xóa.

`infra/aws/lifecycle-policy.json`:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Giu 10 image phat hanh gan nhat (tag sha-*)",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sha-"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    }
  ]
}
```

```bash
# Xem trước image nào sẽ bị chọn, rồi mới áp dụng
aws ecr start-lifecycle-policy-preview --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" \
  --lifecycle-policy-text file://infra/aws/lifecycle-policy.json
aws ecr get-lifecycle-policy-preview --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY"
aws ecr put-lifecycle-policy --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" \
  --lifecycle-policy-text file://infra/aws/lifecycle-policy.json
```

- **Không** thêm rule cho image `untagged` trong MVP: chữ ký Notation được lưu dưới dạng artifact không tag (OCI referrer), và đồ án chưa xác nhận rule `untagged` có chọn trúng chữ ký hay không. Chỉ thêm rule này sau khi preview cho thấy không có chữ ký nào bị chọn.
- Đặt `countNumber` đủ lớn để bản dùng cho rollback (mục 10.5) vẫn nằm trong vùng được giữ.

### 8.2. AWS Signer signing profile

```bash
aws signer put-signing-profile --region "$AWS_REGION" \
  --profile-name "$SIGNING_PROFILE" \
  --platform-id Notation-OCI-SHA384-ECDSA \
  --signature-validity-period value=12,type=MONTHS
```

Đây là tạo profile, không phải ký thủ công. Profile B cho fixture TC06 (mục 6.1) tạo bằng cùng lệnh với tên khác (vd. `podinfo_wrong_signer`); profile B **không** được gắn vào signing rule nào và **không** có trong `trustedIdentities`.

### 8.3. Cấu hình ECR Managed Signing

```bash
jq -n --arg profile "$SIGNING_PROFILE_ARN" --arg repo "$ECR_REPOSITORY" \
  '{rules: [{signingProfileArn: $profile,
     repositoryFilters: [{filter: $repo, filterType: "WILDCARD_MATCH"}]}]}' \
  > signing-config.json

aws ecr get-signing-configuration --region "$AWS_REGION"   # đọc cấu hình cũ TRƯỚC khi ghi
aws ecr put-signing-configuration --region "$AWS_REGION" \
  --signing-configuration file://signing-config.json
```

- Signing configuration ở **cấp registry** (tối đa 10 rule). Nếu registry đã có rule khác, **hợp nhất** thay vì ghi đè.
- Filter phải là đúng tên `podinfo`, **không** dùng `podinfo*`: wildcard sẽ khớp cả repository khác (vd. `podinfo-alt` ở phương án dự phòng của TC06) và ký nhầm bằng profile tin cậy.
- Bật rule chỉ ký các image push **sau đó**; image cũ không tự có chữ ký.
- Ký diễn ra **dưới danh tính người push** → role publisher cần `signer:SignPayload` trên profile.

### 8.4. Ma trận quyền IAM

| Danh tính | Quyền cần có | Không được cấp |
|---|---|---|
| Quản trị lab | Tạo repo, profile, signing config, role | Không dùng credential này trong CI |
| **Publisher** (GitHub OIDC, nhánh `main`) | `ecr:GetAuthorizationToken` (`*`); upload layer, `PutImage`, `DescribeImages`, `DescribeImageSigningStatus` trên ARN repo; `signer:SignPayload`, `signer:GetSigningProfile` trên ARN profile | Sửa IAM, signing rule, xóa image, quyền Kubernetes |
| **Deployer** (GitHub OIDC, environment `production`, chỉ khi dùng EKS) | `eks:DescribeCluster`; Access Entry giới hạn namespace `app` | Push/ký image, sửa Kyverno |
| **Verifier** (extension) | ECR read (manifest/layer/referrer); `signer:GetRevocationStatus` | Push, `SignPayload`, sửa profile |
| Kubelet / node | ECR read-only | Ký, quản trị ECR |

Có thể dùng policy AWS-managed read-only cho verifier trong spike, rồi thu hẹp và ghi lại khác biệt. Đối chiếu tên action với tài liệu IAM hiện hành.

`infra/aws/publisher-policy.template.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
        "ecr:DescribeImages", "ecr:DescribeImageSigningStatus"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${ECR_REPOSITORY}"
    },
    {
      "Effect": "Allow",
      "Action": ["signer:SignPayload", "signer:GetSigningProfile"],
      "Resource": "${SIGNING_PROFILE_ARN}"
    }
  ]
}
```

- Thử bỏ `signer:GetSigningProfile` trong spike; nếu push và ký vẫn `COMPLETE` thì loại khỏi policy để đúng tối thiểu quyền.
- Kiểm tra policy đã render bằng IAM policy validation. Khi gặp lỗi quyền, bổ sung đúng action còn thiếu (đối chiếu ECR Service Authorization Reference) — không chuyển sang `ecr:*`.

### 8.5. GitHub OIDC

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

Trust policy của **publisher** (chỉ đúng repo, nhánh `main`):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:<OWNER>/supply-chain-demo:ref:refs/heads/main"
      }
    }
  }]
}
```

> ⚠️ **Claim `sub` thay đổi theo ngữ cảnh:** job có `environment: production` sẽ có `sub` dạng `repo:<OWNER>/<REPO>:environment:production`, **không** khớp trust theo branch ở trên → vì vậy tách role **deployer** riêng với trust theo environment. Ngoài ra repository mới hoặc đã bật *immutable subject claims* có thể dùng `sub` chứa ID owner/repo. Hãy kiểm tra dạng `sub` thực tế của repo (theo tài liệu GitHub) rồi mới viết trust policy; không in toàn bộ JWT ra log.

### 8.6. Chờ ký và kiểm tra trạng thái

`scripts/wait-signature.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:?}" "${ECR_REPOSITORY:?}" "${IMAGE_DIGEST:?}" "${SIGNING_PROFILE_ARN:?}"
TIMEOUT=${TIMEOUT:-150}; INTERVAL=${INTERVAL:-5}; elapsed=0
mkdir -p release

while (( elapsed < TIMEOUT )); do
  aws ecr describe-image-signing-status --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" --image-id imageDigest="$IMAGE_DIGEST" \
    --output json > release/signing-status.json

  status=$(jq -r --arg arn "$SIGNING_PROFILE_ARN" \
    '[.signingStatuses[]? | select(.signingProfileArn == $arn) | .status][0] // "MISSING"' \
    release/signing-status.json)

  case "$status" in
    COMPLETE)    echo "Signed by expected profile"; exit 0 ;;
    FAILED)      jq '.signingStatuses' release/signing-status.json; exit 1 ;;
    IN_PROGRESS|MISSING) sleep "$INTERVAL"; elapsed=$((elapsed + INTERVAL)) ;;
    *)           echo "Unknown status: $status"; exit 1 ;;
  esac
done
echo "Timeout waiting for signature"; exit 1
```

- Chỉ `COMPLETE` **đúng profile mong đợi** mới đạt; `FAILED` in `failureReason` và dừng; thiếu status / lỗi API / hết giờ đều fail.
- Đối chiếu schema output với tài liệu `describe-image-signing-status` của bản AWS CLI đang dùng.
- `COMPLETE` chỉ xác nhận chữ ký đã được **tạo**; vẫn phải xác minh bằng Notation/admission theo trust policy.

### 8.7. Xác minh thủ công bằng Notation

```bash
aws ecr get-login-password --region "$AWS_REGION" \
  | notation login --username AWS --password-stdin "$ECR_REGISTRY"
notation policy import notation-trust-policy.json
notation verify "${ECR_IMAGE}@${IMAGE_DIGEST}"
```

`notation-trust-policy.json` theo schema **Notation CLI**: `registryScopes` = đúng repo, trust store `signingAuthority:aws-signer-ts` (chứa root certificate AWS Signer lấy từ nguồn AWS), `trustedIdentities` = ARN signing profile, `signatureVerification.level: strict`. Đây **không** phải YAML CRD `TrustPolicy` của extension, nhưng hai bên phải cùng scope/identity/trust store.

---

## 9. Giai đoạn 3 – Pipeline GitHub Actions

### 9.1. Luồng & nguyên tắc

| Sự kiện | Job chạy |
|---|---|
| `pull_request` | `verify` (test → Gitleaks → build → SBOM → Trivy gate → upload báo cáo) và `policy-test` (Kyverno CLI test offline). **Không phát hành.** |
| `push` vào `main` | `verify` + `policy-test` chạy lại trên chính commit đã merge → `publish` → (`deploy` nếu dùng EKS) |

`policy-test` là job riêng, không có quyền AWS và không nằm trong chuỗi `needs` của `publish`: lỗi policy không lẫn với gate CVE của image, nhưng vẫn chặn merge vì là required check.

**Nguyên tắc thiết kế:**

1. **Build một lần, scan và push cùng một artifact.** `verify` build → `docker save image.tar` → scan/SBOM trên tar đó → upload tar + checksum. `publish` tải đúng tar của **cùng workflow run**, `sha256sum -c`, `docker load`, push — **không build lại** (hai lần build có thể khác dependency/base).
2. Job `verify` **không có** `id-token: write`; chỉ `publish`/`deploy` mới có.
3. Không dùng `pull_request_target` để chạy code PR với quyền phát hành.
4. Upload báo cáo dùng `if: always()`; push/release/deploy **không bao giờ** dùng `always()`, `continue-on-error` hay `|| true` cho gate.
5. Scan Trivy **một lần** ra JSON, gate đánh giá trên chính JSON đó (tránh DB cập nhật giữa hai lần scan làm báo cáo và gate lệch nhau). Lỗi công cụ/DB = fail, không coi là "sạch".
6. Pin action theo **commit SHA** (bài học tj-actions 2025) — phần này là biện pháp bảo mật chuỗi cung ứng của chính pipeline, nên nêu trong báo cáo.
7. Mỗi run có **job summary** (`$GITHUB_STEP_SUMMARY`) hiển thị pass/fail/chưa chạy của từng cổng. Summary chỉ trình bày, không thay đổi exit code của gate, và không in giá trị secret.
8. (Tùy chọn) Gom logic vào `scripts/ci-verify.sh` để chạy giống hệt ở máy local và trên runner; workflow chỉ gọi script. Không bắt buộc trong MVP.

### 9.2. Quy tắc security gate

| Kiểm tra | Điều kiện đạt | Khi không đạt |
|---|---|---|
| Unit test | Tất cả pass | Dừng |
| Gitleaks | 0 finding chưa xử lý | Dừng, lưu report đã `--redact` |
| SBOM | JSON CycloneDX hợp lệ, `components` > 0, có dependency ứng dụng | Dừng |
| Trivy | **0 finding `CRITICAL`** (kể cả chưa có bản vá) | Dừng |
| Scanner/DB | Chạy bình thường | Dừng |
| Signing | Đúng profile `COMPLETE` | Không tạo release |

- Ngưỡng theo đề cương: chặn **mọi** Critical → **không** dùng `--ignore-unfixed` ở gate mặc định (nếu dùng, phải giải thích là đã nới lỏng). High được ghi nhận/phân tích, có thể nâng thành chặn sau MVP.
- Ngoại lệ (`.trivyignore`) phải có CVE, lý do, người duyệt, hạn — trình bày như giới hạn. Không ignore hàng loạt để pipeline xanh.

### 9.3. Thiết lập GitHub

- **Variables** (không bí mật): `AWS_REGION`, `AWS_ACCOUNT_ID`, `ECR_REPOSITORY`, `ECR_IMAGE`, `SIGNING_PROFILE_ARN`, `AWS_PUBLISH_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN`, `EKS_CLUSTER_NAME`.
- **Không** có GitHub Secret chứa AWS access key.
- **Branch protection `main`:** bắt buộc PR, review, hai check `verify` và `policy-test` pass; hạn chế người sửa `.github/workflows`.
- **Environment `production`** (nếu có job deploy): yêu cầu duyệt tay; chỉ cho nhánh `main`.
- Bật **Push Protection / Secret scanning** của GitHub như lớp bổ sung (phân biệt với gate Gitleaks khi demo).

### 9.4. Workflow `.github/workflows/ci-cd.yml`

> Khung dưới dùng tag action cho dễ đọc — **thay bằng commit SHA đầy đủ** trước khi nộp. Kiểm tra cú pháp các công cụ theo version đã pin.

```yaml
name: secure-supply-chain

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

env:
  LOCAL_IMAGE: podinfo:ci
  GITLEAKS_VERSION: v8.21.2        # ví dụ – pin bản đã kiểm tra
  # Phiên bản + SHA-256 đã đối chiếu ngày 04/11/2026 (docs/versions.md)
  SYFT_VERSION: v1.56.0
  SYFT_SHA256: 1c2493cfcf52d3367d6cb25780d9190c111c2219c34c820574c43e8bae15c528         # syft_1.56.0_linux_amd64.tar.gz
  KYVERNO_CLI_VERSION: v1.19.2     # phải trùng bản Kyverno trên cụm
  KYVERNO_CLI_SHA256: 357eaf1df8bc24ddd5a73979fadeaae6a032e8710f11af264229756e4956bf4a  # kyverno-cli_v1.19.2_linux_x86_64.tar.gz

jobs:
  verify:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write        # upload SARIF; KHÔNG có id-token
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0             # Gitleaks quét toàn lịch sử
          persist-credentials: false

      - uses: actions/setup-go@v5
        with:
          go-version-file: app/go.mod
      - name: Unit test
        id: test
        run: go -C app test ./...

      - name: Secret scan (Gitleaks)
        id: gitleaks
        run: |
          mkdir -p reports
          docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:${GITLEAKS_VERSION} \
            git /repo --config /repo/.gitleaks.toml --redact \
            --report-format json --report-path /repo/reports/gitleaks.json

      - uses: docker/setup-buildx-action@v3
      - name: Build once
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          load: true
          provenance: false
          tags: ${{ env.LOCAL_IMAGE }}

      - name: Save image artifact
        run: |
          docker save "$LOCAL_IMAGE" -o image.tar
          sha256sum image.tar > image.tar.sha256
          docker image inspect "$LOCAL_IMAGE" --format '{{.Id}}' > image.id

      - name: Install Syft (pinned version + pinned SHA-256)
        run: |
          v="${SYFT_VERSION#v}"; f="syft_${v}_linux_amd64.tar.gz"
          cd "$RUNNER_TEMP"
          curl -fsSLO "https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/$f"
          echo "${SYFT_SHA256}  $f" | sha256sum -c -      # hash ghim trong repo, không tải từ cùng nguồn
          tar -xzf "$f" syft
          sudo install syft /usr/local/bin/syft
          syft version

      - name: SBOM (Syft CLI, CycloneDX) – cùng lệnh với mục 7.3
        run: syft docker-archive:image.tar -o cyclonedx-json=reports/sbom.cdx.json

      - name: Validate SBOM
        id: sbom
        run: jq -e '.bomFormat == "CycloneDX" and ((.components | length) > 0)' reports/sbom.cdx.json

      - uses: aquasecurity/setup-trivy@v0.2.2
      - name: Vulnerability scan (một lần, JSON)
        id: trivy
        run: |
          trivy image --input image.tar --scanners vuln \
            --format json --output reports/trivy.json --exit-code 0
          trivy convert --format sarif --output reports/trivy.sarif reports/trivy.json
          trivy convert --format table --output reports/trivy.txt reports/trivy.json

      - name: Upload SARIF
        # PR từ fork chỉ có token đọc → bỏ qua; báo cáo vẫn nằm trong artifact
        if: >-
          always() && hashFiles('reports/trivy.sarif') != '' &&
          (github.event_name == 'push' ||
           github.event.pull_request.head.repo.full_name == github.repository)
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: reports/trivy.sarif

      - name: Upload security reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: security-reports-${{ github.run_id }}-${{ github.run_attempt }}
          path: reports/
          retention-days: 30

      - name: GATE – no CRITICAL
        id: gate
        run: |
          CRIT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' reports/trivy.json)
          echo "Critical vulnerabilities: $CRIT"
          test "$CRIT" -eq 0

      - name: Job summary (chỉ trình bày, không đổi kết quả gate)
        if: always()
        env:
          R_TEST: ${{ steps.test.outcome }}
          R_LEAKS: ${{ steps.gitleaks.outcome }}
          R_SBOM: ${{ steps.sbom.outcome }}
          R_SCAN: ${{ steps.trivy.outcome }}
          R_GATE: ${{ steps.gate.outcome }}
        run: |
          comps="chưa chạy"; crit="chưa chạy"; high="chưa chạy"
          [ -s reports/sbom.cdx.json ] && comps=$(jq '.components | length' reports/sbom.cdx.json)
          if [ -s reports/trivy.json ]; then
            crit=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' reports/trivy.json)
            high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' reports/trivy.json)
          fi
          {
            echo "### Supply-chain checks – \`${GITHUB_SHA::12}\` (run ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT})"
            echo "| Kiểm tra | Kết quả |"
            echo "|---|---|"
            echo "| Unit test | ${R_TEST:-skipped} |"
            echo "| Gitleaks | ${R_LEAKS:-skipped} |"
            echo "| SBOM | ${R_SBOM:-skipped} (components: $comps) |"
            echo "| Trivy scan | ${R_SCAN:-skipped} |"
            echo "| Gate CRITICAL | ${R_GATE:-skipped} (Critical: $crit, High: $high) |"
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Verification metadata
        run: |
          jq -n --arg commit "$GITHUB_SHA" --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
                --arg image_id "$(cat image.id)" --arg tar_sha "$(cut -d' ' -f1 image.tar.sha256)" \
                --arg sbom_sha "$(sha256sum reports/sbom.cdx.json | cut -d' ' -f1)" \
                --arg vuln_sha "$(sha256sum reports/trivy.json | cut -d' ' -f1)" \
                --arg trivy "$(trivy --version | head -1)" \
                '{commit_sha:$commit, workflow_run_id:$run, run_attempt:$attempt, local_image_id:$image_id,
                  image_tar_sha256:$tar_sha, sbom_sha256:$sbom_sha, vulnerability_report_sha256:$vuln_sha,
                  scanner_version:$trivy, critical_count:0, gate_result:"pass"}' > verification.json

      - name: Upload approved image (chỉ khi mọi gate đạt và sẽ publish)
        # PR không bao giờ publish → không lưu image tar của PR chưa duyệt.
        # `if` không chứa hàm trạng thái nên vẫn ngầm có success(): gate fail thì bước này bị bỏ qua.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: approved-image-${{ github.run_id }}-${{ github.run_attempt }}
          path: |
            image.tar
            image.tar.sha256
            verification.json
          retention-days: 2

  policy-test:                              # required check trong branch protection; không có quyền AWS
    runs-on: ubuntu-latest
    permissions:
      contents: read
    # Không đọc vars.ECR_IMAGE: test offline chỉ kiểm logic; scripts/policy-test.sh dùng một
    # giá trị giả cố định cho cả policy lẫn resource (mục 11.4), không phụ thuộc cấu hình repo
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: Install Kyverno CLI (pinned version + pinned SHA-256)
        run: |
          f="kyverno-cli_${KYVERNO_CLI_VERSION}_linux_x86_64.tar.gz"
          cd "$RUNNER_TEMP"
          curl -fsSLO "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_CLI_VERSION}/$f"
          echo "${KYVERNO_CLI_SHA256}  $f" | sha256sum -c -    # hash ghim trong repo
          tar -xzf "$f" kyverno
          sudo install kyverno /usr/local/bin/kyverno
          kyverno version
      - name: Render policy + resource & run offline tests
        run: bash scripts/policy-test.sh          # đúng lệnh chạy ở máy local (mục 11.4)

  publish:
    needs: verify
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    outputs:
      digest: ${{ steps.push.outputs.digest }}
    env:
      AWS_REGION: ${{ vars.AWS_REGION }}
      ECR_REPOSITORY: ${{ vars.ECR_REPOSITORY }}
      SIGNING_PROFILE_ARN: ${{ vars.SIGNING_PROFILE_ARN }}
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: actions/download-artifact@v4
        with:
          name: approved-image-${{ github.run_id }}-${{ github.run_attempt }}

      - name: Verify artifact integrity & load
        run: |
          sha256sum -c image.tar.sha256
          docker load -i image.tar
          test "$(docker image inspect podinfo:ci --format '{{.Id}}')" = "$(jq -r .local_image_id verification.json)"

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_PUBLISH_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Push (không build lại)
        id: push
        run: |
          TAG="sha-${GITHUB_SHA::12}-run-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
          REMOTE="${{ steps.ecr.outputs.registry }}/${ECR_REPOSITORY}:${TAG}"
          docker tag podinfo:ci "$REMOTE"
          docker push "$REMOTE"
          DIGEST=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY" \
            --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text)
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "digest=$DIGEST" >> "$GITHUB_OUTPUT"
          echo "Pushed \`$REMOTE\` → \`$DIGEST\`" >> "$GITHUB_STEP_SUMMARY"

      - name: Wait for ECR Managed Signing
        env:
          IMAGE_DIGEST: ${{ steps.push.outputs.digest }}
        run: bash scripts/wait-signature.sh

      - name: Release manifest
        run: |
          jq --arg uri "${{ vars.ECR_IMAGE }}" --arg tag "${{ steps.push.outputs.tag }}" \
             --arg digest "${{ steps.push.outputs.digest }}" --arg arn "$SIGNING_PROFILE_ARN" \
             '. + {image_uri:$uri, image_tag:$tag, image_digest:$digest,
                   signing_profile_arn:$arn, signing_status:"COMPLETE"}' \
             verification.json > release/release.json
          echo "Signing: \`COMPLETE\` – profile \`$SIGNING_PROFILE_ARN\`" >> "$GITHUB_STEP_SUMMARY"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: release-${{ github.run_id }}-${{ github.run_attempt }}
          path: release/
          retention-days: 30

  deploy:                                   # chỉ dùng khi chạy EKS
    needs: publish
    if: vars.EKS_CLUSTER_NAME != ''
    runs-on: ubuntu-latest
    environment: production                 # sub = repo:<OWNER>/<REPO>:environment:production
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - run: aws eks update-kubeconfig --name "${{ vars.EKS_CLUSTER_NAME }}"
      - name: Deploy by digest
        env:
          APP_IMAGE_REF: ${{ vars.ECR_IMAGE }}@${{ needs.publish.outputs.digest }}
        run: bash scripts/deploy.sh
```

**Ghi chú:**
- Cập nhật AWS CLI trên runner nếu bản có sẵn chưa có `describe-image-signing-status`.
- Kiểm tra cú pháp `gitleaks git`, `trivy convert`, `syft docker-archive:` theo version đã pin.
- Syft và Kyverno CLI được kiểm tra bằng **SHA-256 ghim sẵn trong workflow**, không phải bằng file checksum tải từ cùng trang release: nếu release bị thay thế, file checksum đi kèm cũng có thể bị thay theo. Đổi phiên bản thì cập nhật hash cùng lúc và ghi vào `docs/versions.md`.
- SBOM được tạo bằng **Syft CLI** cài theo phiên bản cố định, thay cho `anchore/sbom-action`, để tránh phụ thuộc vào cách action diễn giải tiền tố `docker-archive:`; lệnh trùng với lệnh chạy local ở mục 7.3.
- Bước upload `approved-image` chỉ chạy với `push` vào `main` — cùng điều kiện với job `publish`.
- Với **kind**, bỏ job `deploy`; tải `release.json` rồi chạy `scripts/deploy.sh` trên máy có cụm.
- Nếu run dừng trước bước build, SBOM/scan hiển thị "chưa chạy" trong summary — không tạo báo cáo sạch giả để đủ bộ artifact.
- `security-events: write` chỉ phục vụ bước SARIF. Với PR từ fork, GitHub cấp token chỉ đọc nên bước này được bỏ qua; **không** chuyển sang `pull_request_target` để có quyền ghi.

### 9.5. Gitleaks cho kịch bản demo

- Thêm rule thử nghiệm vào `.gitleaks.toml` (giữ rule mặc định bằng `[extend] useDefault = true`): nhận diện chuỗi `DEMO_SECRET_` + 32 ký tự hex; đặt tên rule ghi rõ "chỉ dùng kiểm thử". Như vậy ca demo ổn định mà **không cần secret thật**.
- **Không** commit fixture secret lên `main` rồi xóa: Gitleaks quét toàn lịch sử nên các lần chạy sau vẫn fail. Chỉ đưa vào nhánh demo, đóng PR, xóa nhánh.
- Nếu lỡ lộ secret thật: **thu hồi ngay**; xóa commit là chưa đủ.
- (Tùy chọn) Khi chạy local, quét thêm working tree (file chưa commit): `gitleaks dir app --redact --report-format json --report-path reports/gitleaks-worktree.json`. Kiểm tra cú pháp `git`/`dir` theo bản Gitleaks đã pin.

### 9.6. Truy vết & hồ sơ phát hành

`release/release.json` liên kết:

| Trường | Mục đích |
|---|---|
| `commit_sha`, `workflow_run_id`, `run_attempt` | Nguồn và lượt build |
| `local_image_id`, `image_tar_sha256` | Ràng buộc artifact đã scan với artifact được push |
| `image_uri`, `image_tag`, `image_digest` | Image trên ECR (digest lấy từ registry sau push) |
| `sbom_sha256`, `vulnerability_report_sha256` | Phát hiện thay đổi báo cáo |
| `scanner_version`, `critical_count`, `gate_result` | Quyết định của CI tại thời điểm scan |
| `signing_profile_arn`, `signing_status` | Chữ ký đúng profile |

> **Không nhầm 3 loại SHA:** image ID local (digest config), SHA-256 của `image.tar` (checksum file), digest ECR (digest manifest) — chúng **không bằng nhau**; được liên kết bằng quy trình build-một-lần → chuyển đúng tar → push → đọc digest.

Chuỗi truy vết cần trình diễn:

```
Pod spec.image (digest) → digest + chữ ký trên ECR → release.json của workflow run
→ image.tar đã kiểm tra + SBOM + báo cáo CVE → commit nguồn
```

**Mở rộng – gắn SBOM vào ECR dưới dạng OCI referrer:** chạy trong job `publish` (chỉ publisher có quyền ghi), sau khi đã có digest:

```bash
# Tải artifact security-reports của CÙNG run; đối chiếu hash với verification.json trước khi gắn
test "$(sha256sum reports/sbom.cdx.json | cut -d' ' -f1)" = "$(jq -r .sbom_sha256 verification.json)"
aws ecr get-login-password --region "$AWS_REGION" \
  | oras login --username AWS --password-stdin "$ECR_REGISTRY"
oras attach --artifact-type application/vnd.cyclonedx+json \
  "${ECR_IMAGE}@${IMAGE_DIGEST}" reports/sbom.cdx.json:application/vnd.cyclonedx+json
oras discover "${ECR_IMAGE}@${IMAGE_DIGEST}"
```

- Ghi digest của artifact SBOM vào `release.json`. Không tạo SBOM mới từ image theo tag (tag có thể đã trỏ nội dung khác).
- Phân biệt 3 mức: lưu SBOM ở GitHub artifact (MVP) → gắn SBOM với digest trong registry → ký/attest SBOM và kiểm tra ở admission. `oras attach` chỉ đạt mức 2; chữ ký image **không** ký SBOM.
- Quét lại định kỳ bằng `trivy sbom reports/sbom.cdx.json` để phát hiện CVE mới mà không build lại. Số finding có thể khác lần quét image — phân tích nguyên nhân, không sửa cho khớp.

---

## 10. Giai đoạn 4 – Kubernetes & triển khai

### 10.1. Cụm kind (phát triển)

```bash
kind create cluster --name devsecops --image kindest/node:<version-đã-pin>
kubectl create namespace app      # workload ứng dụng (deployer được quản lý)
kubectl create namespace demo     # chỉ cho các ca kiểm thử TC04–TC09 (quản trị lab chạy)
```

`scripts/refresh-lab-credentials.sh` (chạy trước mỗi buổi làm việc/demo):
- Lấy token ECR bằng danh tính **chỉ đọc** → tạo/cập nhật Secret `ecr-pull` (docker-registry) trong **cả hai** namespace `app` và `demo`; truyền qua stdin/file tạm, không in token ra log.
- Gắn Secret vào ServiceAccount `default` của cả hai namespace (chỉ cần làm một lần). `kubectl run` không tự thêm `imagePullSecrets`; nếu bỏ bước này, ca đối chứng signed chạy thật trong `demo` sẽ `ImagePullBackOff` dù đã qua admission:

  ```bash
  for ns in app demo; do
    kubectl -n "$ns" patch serviceaccount default \
      -p '{"imagePullSecrets":[{"name":"ecr-pull"}]}'
  done
  ```
- Lấy phiên ngắn hạn của role **verifier** → cập nhật Secret chứa `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION` cho extension → `kubectl rollout restart` extension. Không copy thư mục `~/.aws` vào image/Secret.
- Inject Secret này vào deployment extension bằng `env[].valueFrom.secretKeyRef`; xác nhận credential provider chain của release extension/AWS Signer plugin đọc được biến môi trường. Token ECR hết hạn sau 12 giờ, session verifier có thời hạn riêng → làm mới **cả hai** trước demo và thử một yêu cầu thật.
- Áp dụng `k8s/rbac.yaml` (mục 10.2) ngay trên kind: Role `app-deployer` gắn group `devsecops-deployers`, kiểm tra bằng impersonation (`--as=deployer --as-group=devsecops-deployers`) để làm được TC10 mà không cần EKS.

### 10.2. Cụm EKS (demo cloud / CD tự động)

`infra/eks-cluster.yaml`:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: supply-chain-demo
  region: ap-southeast-1
  version: "<version EKS còn hỗ trợ tiêu chuẩn, tương thích Kyverno 1.19>"
accessConfig:
  authenticationMode: API_AND_CONFIG_MAP   # bật EKS access entries; kiểm tra theo schema eksctl đã pin
iam:
  withOIDC: true                    # IRSA cho extension verifier
managedNodeGroups:
  - name: ng-default
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 1
    maxSize: 2
    spot: true
```

```bash
eksctl create cluster -f infra/eks-cluster.yaml
# Access entry chỉ gắn Kubernetes group; quyền thực tế do RBAC trong k8s/rbac.yaml quyết định
aws eks create-access-entry --region "$AWS_REGION" --cluster-name supply-chain-demo \
  --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/gha-deployer" \
  --type STANDARD --kubernetes-groups devsecops-deployers
kubectl apply -f k8s/rbac.yaml
```

> **Không** gắn `AmazonEKSEditPolicy` cho deployer: policy này cấp quyền rộng trong namespace (exec vào Pod, đọc/sửa Secret…), mâu thuẫn với ma trận quyền ở mục 8.4 và yêu cầu chặn ephemeral containers bằng RBAC.

`k8s/rbac.yaml` – quyền tối thiểu cho deployer (dùng chung cho kind và EKS):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-deployer
  namespace: app
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["events.k8s.io"]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services/proxy"]          # chỉ để smoke test /healthz từ job deploy
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-deployer
  namespace: app
subjects:
  - kind: Group
    name: devsecops-deployers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
```

Không cấp: `secrets`, `pods/exec`, `pods/attach`, `pods/portforward`, `pods/ephemeralcontainers`, tạo namespace, policy Kyverno, `TrustPolicy`/`TrustStore`, webhook. Kiểm tra — dòng đầu phải `yes`, các dòng còn lại phải `no`:

```bash
D="--as=deployer --as-group=devsecops-deployers"
kubectl auth can-i patch deployments -n app $D
kubectl auth can-i get secrets -n app $D
kubectl auth can-i create pods --subresource=exec -n app $D
kubectl auth can-i patch pods --subresource=ephemeralcontainers -n app $D
kubectl auth can-i update clusterpolicies.kyverno.io $D
kubectl auth can-i update validatingpolicies.policies.kyverno.io $D
kubectl auth can-i create namespaces $D
```

- EKS có 3 điều kiện độc lập: xác thực IAM (access entry), phân quyền Kubernetes (RBAC) và **đường mạng tới API server**. `aws eks update-kubeconfig` thành công chưa chứng minh runner deploy được; GitHub-hosted runner không vào được endpoint private.
- Gắn role verifier cho ServiceAccount của extension bằng IRSA/Pod Identity. Node role đã có quyền pull ECR (không cần `imagePullSecret`).
- Kết quả trên kind không thay cho bằng chứng EKS: nếu demo bằng EKS, chạy lại TC01, TC04, TC09, TC10 trên EKS.

### 10.3. Manifest ứng dụng

`k8s/deployment.template.yaml` (rút gọn):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
  namespace: app
spec:
  replicas: 2
  selector:
    matchLabels: { app: podinfo }
  template:
    metadata:
      labels: { app: podinfo }
    spec:
      automountServiceAccountToken: false
      # kind: pull secret đến từ ServiceAccount `default` (mục 10.1); EKS: node role pull ECR
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532                            # UID số – khớp USER trong Dockerfile
        runAsGroup: 65532
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: podinfo
          image: "${APP_IMAGE_REF}"                 # <ECR_IMAGE>@sha256:<digest> từ release.json
          ports: [{ containerPort: 9898 }]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
          livenessProbe:  { httpGet: { path: /healthz, port: 9898 } }
          readinessProbe: { httpGet: { path: /readyz,  port: 9898 } }
          volumeMounts:
            - { name: tmp,  mountPath: /tmp }
            - { name: data, mountPath: /data }      # --data-path mặc định của podinfo (/store)
      volumes:
        - { name: tmp,  emptyDir: {} }
        - { name: data, emptyDir: {} }
```

Service `ClusterIP` + `kubectl port-forward` khi demo (tránh chi phí LoadBalancer).

- `runAsUser`/`runAsGroup` dạng số là bắt buộc khi bật `runAsNonRoot`; thiếu chúng và image khai báo user dạng tên → Pod kẹt ở `CreateContainerConfigError`.
- `emptyDir` cho `/data` mất khi Pod bị thay thế — chấp nhận được cho demo; không dùng để đánh giá lưu trữ bền vững.

### 10.4. Quy trình triển khai (`scripts/deploy.sh`)

1. Lấy `APP_IMAGE_REF` từ `release.json` của một run **thành công** trên `main` (không tự gõ tag).
2. `envsubst '${APP_IMAGE_REF}' < k8s/deployment.template.yaml > /tmp/deploy.yaml`
3. `kubectl apply --dry-run=server -f /tmp/deploy.yaml` → `kubectl apply -f /tmp/deploy.yaml`
4. `kubectl -n app rollout status deployment/podinfo --timeout=120s`
5. Smoke test `/healthz`; lưu Pod spec, image ID runtime, event, log.

Render manifest **cuối cùng** rồi mới apply; không apply bản chứa tag/placeholder rồi `kubectl set image` (admission có thể chặn ngay bước đầu). Trên kind, smoke test qua `kubectl port-forward`; trong job `deploy` của EKS, dùng `kubectl get --raw "/api/v1/namespaces/app/services/podinfo:<port>/proxy/healthz"` (đúng quyền `services/proxy` trong Role) thay cho port-forward.

> Nếu policy chỉ match Pod, `kubectl apply` Deployment vẫn **thành công** nhưng ReplicaSet không tạo được Pod → bằng chứng là event `FailedCreate`. Đừng diễn giải là "apply phải trả lỗi".

### 10.5. Rollback

Lưu digest bản tốt trước đó trong hồ sơ phát hành; rollback = triển khai lại digest đó và **vẫn đi qua admission**. Không chuyển policy sang Audit hay tắt verifier để rollback. Nếu chữ ký bản cũ đã hết hạn/bị thu hồi thì phải phát hành lại bản đã kiểm tra.

---

## 11. Giai đoạn 5 – Kyverno admission policy

### 11.1. Cài Kyverno (ghim phiên bản)

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
helm search repo kyverno/kyverno --versions | head        # chọn chart có APP VERSION 1.19.x
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace \
  --version "$KYVERNO_CHART_VERSION" --wait                # BẮT BUỘC có --version
kubectl -n kyverno get pods
kubectl -n kyverno get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

- `KYVERNO_CHART_VERSION=3.9.2` — chart ứng với **Kyverno v1.19.2** (đã đối chiếu `Chart.yaml` tại tag `kyverno-chart-3.9.2` ngày 04/11/2026). Ghi cả số chart và số app vào `docs/versions.md`; lệnh cuối xác nhận image đang chạy đúng tag `v1.19.2`.
- **Không** dùng `--devel` (sẽ lấy bản pre-release 1.20). Khi 1.20 phát hành chính thức, mọi lệnh `helm install`/`upgrade` thiếu `--version` sẽ cài bản đã gỡ `ClusterPolicy`.
- **Kyverno CLI** (máy local và job `policy-test`) cũng ghim đúng bản 1.19.x; không cài bằng `brew`/`krew` không ghim phiên bản vì chúng tự lấy bản mới nhất.

Chỉ enforce ở namespace ứng dụng (`app`, `demo`); **không** match `kube-system`, `kyverno`, namespace của extension. Quyền tạo namespace / đưa workload vào namespace ngoại lệ phải nằm ngoài quyền deployer.

### 11.2. Policy 1 – Chỉ cho phép đúng repository **và** digest

Ràng buộc cả account + region + repository + `@sha256:` (không chỉ kiểm tra chuỗi `amazonaws.com`).

**Dạng CEL `ValidatingPolicy` — mặc định của đồ án** (chạy trên 1.19 và các bản sau; kiểm tra `apiVersion` của bản cài bằng `kubectl api-resources | grep -i validatingpolic`):

```yaml
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: allowed-image
spec:
  validationActions: [Deny]
  failurePolicy: Fail            # lỗi đánh giá policy không được cho qua; xác nhận trường theo bản cài
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: In
          values: ["app", "demo"]
  variables:
    - name: images
      expression: >-
        object.spec.containers.map(c, c.image) +
        (has(object.spec.initContainers) ? object.spec.initContainers.map(c, c.image) : [])
  validations:
    - expression: >-
        variables.images.all(i, i.startsWith('${ECR_IMAGE}@sha256:'))
      message: "Image phải thuộc ${ECR_IMAGE} và được tham chiếu bằng sha256 digest."
```

**Dạng `ClusterPolicy`** (dự phòng, chỉ chạy trên Kyverno ≤ 1.19 — dùng khi bản CEL gặp lỗi trong spike):

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: allowed-image
  annotations:
    pod-policies.kyverno.io/autogen-controllers: none
spec:
  background: false
  rules:
    - name: require-approved-repository-and-digest
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [app, demo]
              operations: [CREATE, UPDATE]
      validate:
        failureAction: Enforce
        message: "Image phải thuộc ${ECR_IMAGE} và dùng sha256 digest."
        foreach:
          - list: "request.object.spec.[containers, initContainers][]"
            pattern:
              image: "${ECR_IMAGE}@sha256:*"
```

- Render bằng `envsubst '${ECR_IMAGE}'` (chỉ định rõ biến để không phá biểu thức `{{ }}` của Kyverno), rồi `kubectl apply --dry-run=server`.
- **Ephemeral containers:** MVP chặn bằng RBAC (không cấp `pods/ephemeralcontainers` cho deployer, mục 10.2) cho tới khi có policy + test riêng.
- **Autogen:** kiểm tra policy có tự sinh rule cho Deployment/ReplicaSet hay không. Nếu có, `kubectl apply` Deployment vi phạm bị từ chối ngay; nếu không, lỗi xuất hiện ở event `FailedCreate`. Ghi đúng hành vi thực tế vào báo cáo.
- Nếu policy chữ ký có `mutateDigest` (đổi tag → digest), cần kiểm tra thứ tự mutate/validate để ca TC07 (tag-only) cho kết quả đúng như thiết kế.

### 11.3. Policy 2 – Xác minh chữ ký AWS Signer

Chữ ký từ ECR Managed Signing là chữ ký **Notation (Notary Project)**, signing scheme `notary.x509.signingAuthority`.

#### Phương án A (khuyến nghị) – Kyverno + `kyverno-notation-aws`

Extension chạy trong cụm, dùng notation-go + **AWS Signer plugin**: xác minh chữ ký, giới hạn theo `trustedIdentities` (đúng signing profile) và **kiểm tra thu hồi**. Kyverno gọi service này qua `context.apiCall.service`.

Các việc cần làm theo **release đã chốt** (không áp manifest từ nhánh `main`):

1. Cài CRD `TrustPolicy`, `TrustStore`, deployment, service, TLS, RBAC của extension.
2. TrustStore chứa root certificate AWS Signer (đúng partition, lấy từ nguồn AWS).
3. TrustPolicy:

   ```yaml
   apiVersion: notation.nirmata.io/v1alpha1      # xác nhận schema theo release
   kind: TrustPolicy
   metadata:
     name: tp-supply-chain
   spec:
     version: '1.0'
     trustPolicyName: tp-supply-chain
     trustPolicies:
       - name: trusted-podinfo
         registryScopes: ["${ECR_IMAGE}"]
         signatureVerification:
           level: strict
           override: {}
         trustStores: ["signingAuthority:aws-signer-ts"]
         trustedIdentities: ["${SIGNING_PROFILE_ARN}"]
   ```

4. Lấy **mẫu Kyverno policy của release** → hiệu chỉnh thành `policies/verify-signer.template.yaml`:

   | Trường | Yêu cầu |
   |---|---|
   | Match | Pod CREATE/UPDATE trong `app`, `demo` |
   | Background | Tắt |
   | Failure policy | `Fail` – lỗi xác minh không được cho qua |
   | TLS | CA đúng service extension; không bỏ xác thực TLS |
   | Request | Gửi danh sách image Kyverno nhận diện; trust policy `tp-supply-chain` |
   | Response | Không `verified` → deny |
   | Attestation | **Gỡ phần điều kiện SBOM attestation minh họa** trong mẫu upstream (MVP chưa phát hành attestation → image có chữ ký vẫn bị deny nếu giữ nguyên) |

5. Credential verifier: IRSA (EKS) hoặc Secret ngắn hạn (kind) – mục 2.4, 10.1.

> Mẫu extension dùng `ClusterPolicy` → đây là lý do chính để **ghim Kyverno 1.19.x** (mục 3.3).

#### Phương án B – Kyverno native (Notary / `ImageValidatingPolicy`)

Từ 1.19, `ImageValidatingPolicy` đạt tương đương tính năng với `verifyImages` cũ, nên phương án này khả thi hơn trước. Khai báo attestor kiểu Notary với chứng chỉ gốc AWS Signer. Không cần cài thêm thành phần, nhưng **phải kiểm chứng thực tế**: verifier native có thể không hỗ trợ đầy đủ scheme `signingAuthority`, **không kiểm tra thu hồi**, và nếu chỉ tin root AWS Signer thì chữ ký của **bất kỳ** profile/tài khoản nào cũng "hợp lệ" (không giới hạn được theo signing profile). Nếu dùng, phải ghi rõ các hạn chế này.

#### Phương án C – Ratify + OPA Gatekeeper

Theo hướng dẫn của AWS cho EKS; dùng khi A và B không chạy được. Policy 1 vẫn giữ ở Kyverno.

> AWS liệt kê "Kyverno + AWS Signer plugin" là một lựa chọn chính thức. **Không** giả định một rule `verifyImages` kiểu Cosign xác minh được chữ ký AWS Signer.

### 11.4. Test offline bằng Kyverno CLI

Dùng Kyverno CLI **cùng phiên bản** với cụm (v1.19.2). Test offline render **cả policy lẫn resource** bằng một **giá trị giả cố định** cho `ECR_IMAGE` (account ví dụ `111122223333` của tài liệu AWS): test chỉ kiểm logic nên không cần account thật, không phụ thuộc `vars` của GitHub, và ca "đúng repo + digest" luôn khớp với policy vừa render.

Mọi file được render vào **cùng một** thư mục, nên `kyverno-test.yaml` chỉ ghi tên file, không có đường dẫn `../`:

```
policies/tests/allowed-image/            (commit vào repo)
├── kyverno-test.yaml                    policies: [allowed-image.yaml], resources: [resources.yaml]
└── resources.template.yaml              4 Pod mẫu, dùng ${ECR_IMAGE}
            │  scripts/policy-test.sh: envsubst + cp
            ▼
policies/rendered/allowed-image/         (.gitignore, tạo lại mỗi lần chạy)
├── allowed-image.yaml
├── resources.yaml
└── kyverno-test.yaml
```

| Pod mẫu | Image | Mong đợi |
|---|---|---|
| `tc-ok` | `${ECR_IMAGE}@sha256:<64 ký tự hex>` | pass |
| `tc-wrong-account` | `999999999999.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo@sha256:<64 ký tự hex>` | fail |
| `tc-tag-only` | `${ECR_IMAGE}:v1` | fail |
| `tc-bad-init` | container chính như `tc-ok`, init container `docker.io/library/busybox@sha256:<64 ký tự hex>` | fail |

`scripts/policy-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Giá trị giả cố định cho test offline; chỉ ghi đè khi thật sự cần (POLICY_TEST_ECR_IMAGE)
export ECR_IMAGE="${POLICY_TEST_ECR_IMAGE:-111122223333.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo}"
src=policies/tests/allowed-image
out=policies/rendered/allowed-image
rm -rf "$out" && mkdir -p "$out"
envsubst '${ECR_IMAGE}' < policies/allowed-image.template.yaml > "$out/allowed-image.yaml"
envsubst '${ECR_IMAGE}' < "$src/resources.template.yaml"     > "$out/resources.yaml"
cp "$src/kyverno-test.yaml" "$out/"
kyverno test "$out"
```

Khung `policies/tests/allowed-image/kyverno-test.yaml` — đối chiếu schema với tài liệu `kyverno test` của bản 1.19.2 (với `ValidatingPolicy`, mục `results` có thể cần thêm trường đánh dấu loại policy):

```yaml
apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: allowed-image
policies: [allowed-image.yaml]
resources: [resources.yaml]
results:
  - policy: allowed-image
    kind: Pod
    resources: [tc-ok]
    result: pass
  - policy: allowed-image
    kind: Pod
    resources: [tc-wrong-account, tc-tag-only, tc-bad-init]
    result: fail
```

Chạy toàn bộ test và thử nhanh một manifest thật:

```bash
bash scripts/policy-test.sh        # toàn bộ test offline, giống hệt job policy-test
# Thử nhanh với policy vừa render (image docker.io bị từ chối với mọi giá trị ECR_IMAGE)
kyverno apply policies/rendered/allowed-image/allowed-image.yaml \
  --resource tests/admission/tc05-dockerhub.yaml
```

Bộ test chạy trong job **`policy-test`** của workflow (mục 9.4), là required check cùng `verify`; máy local chạy đúng lệnh `bash scripts/policy-test.sh`. Chỉ test offline Policy 1; Policy 2 gọi extension qua mạng nên được kiểm thử trên cụm. **Giới hạn:** test offline chỉ kiểm tra logic policy — không chứng minh TLS, quyền AWS, truy xuất chữ ký, kiểm tra thu hồi hay fail-closed. Các ca admission trên cụm (mục 12) vẫn bắt buộc.

### 11.5. Quan sát & thu bằng chứng trên cụm

```bash
kubectl get validatingpolicy,clusterpolicy
kubectl -n app get events --sort-by=.metadata.creationTimestamp
kubectl -n app get events --field-selector reason=FailedCreate
kubectl -n kyverno logs deploy/kyverno-admission-controller --since=10m
kubectl -n kyverno-notation-aws logs deploy/kyverno-notation-aws --since=10m
kubectl get validatingwebhookconfigurations -o yaml   # scope namespace, failurePolicy, sideEffects
```

- Bằng chứng cho ca **deny**: stderr + exit code của `kubectl`, event `FailedCreate`, log admission controller và extension theo mốc thời gian.
- **PolicyReport không phải lịch sử các lần từ chối:** yêu cầu bị Enforce chặn không tạo resource nên thường không xuất hiện trong `kubectl get policyreport -A`. Không đánh trượt một ca deny vì thiếu dòng trong report.
- Tên deployment/namespace của Kyverno và extension lấy theo bản cài thực tế (`kubectl get deploy -A`).

---

## 12. Giai đoạn 6 – Kịch bản kiểm thử & bằng chứng

### 12.1. Ma trận kiểm thử

| ID | Tình huống | Lớp kiểm soát | Kết quả mong đợi | Bằng chứng tối thiểu | Bắt buộc |
|---|---|---|---|---|---|
| TC01 | Image hợp lệ (đúng repo/digest/profile) | CI + admission | Pipeline xanh, ký `COMPLETE`, Pod Ready, web chạy | Run CI, SBOM/báo cáo, digest, signing status, `notation verify`, Pod, HTTP | ✅ |
| TC02 | Mã nguồn chứa secret giả | Gitleaks | `verify` fail, `publish` bị skip, không có tag mới | Finding đã redact, exit code, đồ thị job | ✅ |
| TC03 | Image có CVE Critical | Trivy gate | Gate fail, không push | CVE/package/severity, version scanner + DB, exit code, ECR đối chiếu | ✅ |
| TC04 | Image **chưa ký**, đúng repo + digest | Admission (chữ ký) | Pod bị từ chối vì thiếu chữ ký | `notation verify` fail + lỗi webhook; đối chứng signed pass | ✅ |
| TC05 | Image từ registry/repo không được phép | Admission (allowlist) | Bị từ chối | Manifest + thông báo policy | ✅ |
| TC06 | Có chữ ký nhưng từ profile **khác** (`D_wrongsigner`, cùng repo `podinfo`) | Admission (trust identity) | Bị từ chối | `notation ls` (đúng 1 chữ ký) + `notation inspect` (thuộc profile B) + lỗi danh tính ký từ `notation verify` và admission | Mở rộng (fixture tạo trong spike) |
| TC07 | Dùng tag thay vì digest | Admission (digest) | Bị từ chối (hoặc bị mutate – theo thiết kế đã chọn) | Manifest + lỗi policy | Mở rộng |
| TC08 | Container chính hợp lệ, **init container** vi phạm | Admission | Pod bị từ chối | Manifest nhiều image + kết quả xác minh | Mở rộng |
| TC09 | Verifier không khả dụng / credential hết hạn | Admission **fail-closed** | Không tạo được Pod chưa xác minh | Lỗi vận hành (khác lỗi thiếu chữ ký) + khôi phục pass | Mở rộng (ưu tiên cao) |
| TC10 | Deployer cố sửa policy / exec / dùng namespace ngoại lệ | RBAC | `Forbidden` | `auth can-i` (mục 10.2) + yêu cầu thật | Mở rộng |

Ca nào chưa làm thì ghi "chưa thực hiện" trong báo cáo, không bỏ qua im lặng.

### 12.2. Chi tiết các ca bắt buộc

**TC01 – Luồng hợp lệ (đối chứng):** PR thay đổi nhỏ → merge → pipeline xanh → tải SBOM, tìm thấy các module Go của podinfo → ECR có digest với `COMPLETE` đúng profile → `notation verify` pass → deploy digest → Pod Ready, `/healthz` OK → đối chiếu Pod ↔ `release.json` ↔ commit. *Ca này chứng minh các lần từ chối sau không phải do "mọi thứ đều bị chặn".*

**TC02 – Secret:** nhánh `demo/leak-secret`, thêm file chứa `DEMO_SECRET_<32 hex>` (khớp rule kiểm thử) → mở PR → Gitleaks báo đúng file/rule (giá trị đã redact) → `publish` không chạy, PR không merge được → đóng PR, xóa nhánh → chạy lại ca sạch. Nếu GitHub Push Protection chặn trước, đó là kiểm soát **khác**; dùng chuỗi giả theo rule lab để vẫn chứng minh được gate Gitleaks.

**TC03 – Critical:** `demo/Dockerfile.vulnerable` dùng base/dependency mà **Trivy hiện tại thực sự báo Critical** (chọn từ kết quả scan thật, không đoán) → pin digest fixture, lưu scanner version, thời điểm DB, CVE, package, installed/fixed version → chạy cùng gate → nonzero → `publish` không chạy, ECR không có tag của run đó. Không sửa JSON hay hard-code `exit 1` rồi gọi là phát hiện CVE. Kiểm tra lại fixture trước buổi bảo vệ (DB thay đổi).

**TC04 – Chưa ký:** dùng `D_unsigned` (mục 6), xác nhận vẫn pull/đọc được bằng quyền reader để loại trừ lỗi xác thực registry:

```bash
kubectl -n demo run tc04-unsigned --image="${ECR_IMAGE}@${UNSIGNED_DIGEST}" \
  --restart=Never --dry-run=server -o yaml          # mong đợi: admission deny
kubectl -n demo run tc04-signed --image="${ECR_IMAGE}@${SIGNED_DIGEST}" \
  --restart=Never --dry-run=server -o yaml          # đối chứng: chấp nhận
```

Sau đó chạy yêu cầu thật (không dry-run) để chứng minh Pod không được tạo. Webhook chỉ nhận yêu cầu dry-run khi khai báo `sideEffects` phù hợp — kiểm tra bằng `kubectl get validatingwebhookconfigurations -o yaml`; nếu không, chỉ dùng yêu cầu thật trong namespace `demo`. **Không** kết luận từ `ImagePullBackOff` (đó là lỗi pull **sau** admission); `Unauthorized`/timeout không phải bằng chứng xác minh chữ ký.

**TC05 – Nguồn không được phép:** image public **có digest thật** (vd. `docker.io/library/nginx@sha256:...`) hoặc repo ECR khác → bị Policy 1 từ chối. Không dùng registry không tồn tại rồi lấy lỗi DNS làm bằng chứng.

### 12.3. Ca mở rộng

- **TC06 sai người ký:** dùng `D_wrongsigner` đã tạo trong spike (mục 6.1, bước 3): cùng repo `podinfo`, đúng digest, chỉ có chữ ký của profile B. Policy 1 cho qua (đúng nguồn), Policy 2 từ chối vì signer không nằm trong `trustedIdentities` → cô lập đúng nguyên nhân, dùng nguyên policy thật. Trước khi chạy, `notation ls` (đúng 1 chữ ký) và `notation inspect` (chữ ký thuộc profile B) xác nhận fixture chưa bị ký thêm; bằng chứng chính là lỗi danh tính ký từ `notation verify` và từ admission. Chỉ đạt được với phương án A/C (phương án B chỉ tin root AWS Signer nên không phân biệt được profile).
  - *Không* đặt fixture ở một repo phụ bất kỳ (Policy 1 sẽ chặn trước vì sai nguồn), và *không* push fixture vào `podinfo` sau khi đã bật signing rule (Managed Signing ký thêm bằng profile tin cậy nên image lại được chấp nhận).
  - **Dự phòng** nếu lỡ bật signing rule trước khi tạo fixture: tạo repo `podinfo-alt` với signing rule riêng dùng profile B (filter đúng tên `podinfo-alt`; filter của rule chính vẫn đúng `podinfo`, mục 8.3), rồi push một image vào đó để được ký bằng profile B (người push cần `signer:SignPayload` trên profile B). Ở bước admission, chỉ cần **một** policy từ chối là request bị từ chối, nên phải sửa đủ ba chỗ (bước 1–3) — nếu chỉ thêm một allowlist cho `demo` trong khi policy chính vẫn match `demo` thì `podinfo-alt` vẫn bị chặn:
    1. **Tách allowlist theo namespace:** `allowed-image` chỉ match `app`; thêm `allowed-image-demo` chỉ match `demo`, cho phép `${ECR_IMAGE}@sha256:` **hoặc** `${ECR_REGISTRY}/podinfo-alt@sha256:`.
    2. **Policy 2 gửi cả image `podinfo-alt` sang extension.** Nếu bộ lọc image của Policy 2 chỉ có `podinfo`, image `podinfo-alt` không được xác minh chữ ký và sẽ **được chấp nhận** → TC06 hỏng.
    3. **TrustPolicy:** thêm `podinfo-alt` vào `registryScopes`; `trustedIdentities` vẫn chỉ là profile chính.
    4. **Đây là cấu hình chỉ để kiểm thử.** Sau khi thu bằng chứng: gỡ `allowed-image-demo`, trả `allowed-image` về match cả `app` và `demo`, gỡ `podinfo-alt` khỏi Policy 2 và TrustPolicy, rồi chạy lại TC04 và TC05 để chắc policy chính đã về như cũ.
- **TC08 nhiều container:** container chính signed + init container unsigned → phải bị từ chối; nếu verifier chỉ kiểm container chính thì chưa nghiệm thu.
- **TC09 fail-closed:** scale extension về 0 hoặc làm hết hạn credential → gửi yêu cầu signed **digest mới** (tránh cache) → bị chặn với lỗi vận hành (khác lỗi thiếu chữ ký) → khôi phục → pass.
- **TC10 RBAC:** chạy bộ `kubectl auth can-i ... --as=deployer --as-group=devsecops-deployers` ở mục 10.2 và ít nhất một yêu cầu thật bằng impersonation (vd. sửa policy, `exec` vào Pod) → `Forbidden`. Không chạy bằng cluster-admin rồi kết luận. Trên kind, impersonation được thực hiện từ kubeconfig quản trị — ghi rõ điều này trong báo cáo.

### 12.4. Ghi bằng chứng

Lưu tại `docs/evidence/TCxx/<timestamp>/`, che token/credential nhưng **giữ** lý do lỗi, tên policy, digest. Ưu tiên log văn bản/JSON; ảnh cho giao diện web, GitHub Actions, ECR console. Bằng chứng deny lấy theo mục 11.5, không dựa vào PolicyReport.

| Trường | Nội dung |
|---|---|
| Mã ca, thời gian | Ghi múi giờ (UTC hoặc Asia/Ho_Chi_Minh) |
| Commit, workflow run | Link thực tế |
| Input | Dockerfile/manifest, tag, digest |
| Điều kiện trước | Policy version, trust profile, credential còn hạn, Trivy DB |
| Mong đợi / Thực tế | Pass/deny/fail ở đúng lớp; exit code, thông báo lỗi |
| Kết luận | Đạt / Không đạt / Chưa thực hiện + đường dẫn bằng chứng |

### 12.5. Chỉ số đánh giá

| Chỉ số | Cách đo |
|---|---|
| Kết quả từng ca | Mong đợi vs thực tế, chặn đúng nguyên nhân |
| Thời gian CI | Timestamp từng step (test, scan, build) |
| Độ trễ ký | Từ push xong tới `COMPLETE` (phụ thuộc chu kỳ poll) |
| Độ trễ admission | Thời gian phản hồi yêu cầu Pod, lần đầu vs có cache |
| SBOM | Số component, định dạng, kích thước |
| Lỗ hổng | Critical/High/Medium tại thời điểm scan |
| Truy vết | Đối chiếu commit → artifact → digest → Pod; bước nào tự động/thủ công |

Lặp mỗi ca chính ≥ 3 lần nếu kịp, ghi min/max/trung bình; giữ cả lần lỗi mạng/cloud và phân loại. Chỉ viết kiểu "4/4 ca bất thường bị chặn trong N lượt" khi dữ liệu chứng minh.

---

## 13. Lịch trình thực hiện

Chọn một trong ba lịch theo hạn nộp. Quy tắc chung cho cả ba lịch: việc đầu tiên là ghim Kyverno 1.19.x; **spike ký → xác minh → từ chối unsigned bắt đầu ngay tuần 1** và phải đạt tiêu chí ở mục 6.2 **chậm nhất cuối tuần 2** (lịch 8 và 10 tuần) hoặc **cuối tuần 1** (lịch 6 tuần). Chưa qua spike thì chưa làm pipeline.

### 13.1. Lịch chuẩn 8 tuần (~70–100 giờ)

| Tuần | Công việc | Điều kiện kết thúc |
|---|---|---|
| 1 | Ghim Kyverno 1.19.x; tài khoản, công cụ, biến cấu hình; **bắt đầu spike** (mục 6.1, bước 1–7): ECR, fixture unsigned + wrong-signer, Signer, Managed Signing, `notation verify` | `notation verify` đúng cho cả 3 digest; `docs/versions.md` nháp |
| 2 | **Hoàn tất spike** (mục 6.1, bước 8–10): kind + Kyverno + extension, admission deny; đọc lý thuyết nền (supply chain, SBOM, Notation, admission) | Signed pass, unsigned/wrong-signer deny, fail-closed; **chốt phiên bản** |
| 3 | podinfo, Dockerfile, test, scan local | Image non-root chạy được, test pass |
| 4 | Pipeline `verify`: test, Gitleaks, build-once, SBOM, Trivy gate | PR chạy được, có artifact; secret/Critical làm fail |
| 5 | OIDC, `publish`, chờ ký, `release.json`; branch protection | Commit hợp lệ lên ECR, `COMPLETE` |
| 6 | Policy 1 + 2 hoàn chỉnh, deploy script, (EKS + job deploy nếu chọn) | TC01, TC04, TC05 đạt |
| 7 | Toàn bộ ma trận kiểm thử, lặp lại, đo đạc, thu bằng chứng | `docs/test-results.md` có số liệu thật |
| 8 | Báo cáo, slide, video dự phòng, README dựng lại, tổng duyệt | Bản nộp cuối |

### 13.2. Lịch rút gọn 6 tuần (~60–90 giờ)

| Tuần | Công việc | Điều kiện kết thúc |
|---|---|---|
| 1 | Môi trường + spike đường găng (mục 6) | Signed pass, unsigned deny, fail-closed; chốt phiên bản |
| 2 | podinfo, Dockerfile, test; job `verify` | PR có SBOM/báo cáo; secret và Critical làm fail |
| 3 | OIDC, `publish`, chờ ký, `release.json`, branch protection | Image hợp lệ trên ECR, `COMPLETE` |
| 4 | Policy 1 + 2, RBAC, deploy script | TC01, TC04, TC05 đạt |
| 5 | Ma trận kiểm thử, đo đạc, bằng chứng | `docs/test-results.md` có số liệu thật |
| 6 | Báo cáo, slide, video, dựng lại từ môi trường sạch | Bản nộp |

Lịch này bỏ EKS và các ca mở rộng, trừ TC09 (fail-closed).

### 13.3. Lịch giãn 10 tuần

| Tuần | Mốc thực hiện |
|---|---|
| 1 | Thiết kế, chuẩn bị môi trường, ghim Kyverno 1.19.x, bắt đầu spike (kể cả tạo fixture trước khi bật signing rule) |
| 2–3 | Hoàn tất spike và chốt phiên bản **trong tuần 2**; workload, Dockerfile, test |
| 4–5 | CI, SBOM, gate, OIDC, publish, Managed Signing |
| 6–7 | Policy, RBAC, triển khai trên kind; EKS/CD nếu chọn hướng cloud |
| 8 | Bộ kiểm thử, số liệu, bằng chứng |
| 9 | Báo cáo, slide, hướng dẫn dựng lại |
| 10 | Dựng lại từ môi trường sạch, tổng duyệt, video dự phòng |

### 13.4. Khi thiếu thời gian hoặc làm nhóm

**Nếu thiếu thời gian:** giữ đủ KQ1–KQ7; cắt EKS, CD tự động, ca mở rộng. **Không** cắt ca unsigned, và không thay Managed Signing bằng ký thủ công mà vẫn giữ mô tả kết quả như đề cương.

**Nếu làm nhóm:** chia App/CI – AWS/IAM – Kubernetes/policy – Thực nghiệm/báo cáo; mỗi người vẫn phải hiểu toàn bộ luồng tin cậy để bảo vệ.

---

## 14. Chi phí, rủi ro & xử lý lỗi

### 14.1. Chi phí

| Dịch vụ | Ghi chú |
|---|---|
| ECR | Lưu trữ + data transfer, rất thấp; lifecycle policy |
| AWS Signer | Theo tài liệu AWS Signer, không tính phí thêm khi dùng với ECR — **kiểm tra lại** trang Pricing |
| EKS (nếu dùng) | Control plane ~0.10 USD/giờ + node (spot) + **NAT Gateway, Load Balancer, public IP** có thể phát sinh ngoài dự kiến |
| GitHub Actions | Miễn phí trong hạn mức repo |

- Phát triển trên kind; chỉ dựng EKS khi cần và **xóa ngay sau khi dùng** (script hóa create/delete).
- Đặt AWS Budgets; không đưa mức giá cố định vào báo cáo nếu chưa đối chiếu hóa đơn thực tế.

### 14.2. Rủi ro

| Rủi ro | Mức | Phương án |
|---|---|---|
| Không xác minh được chữ ký AWS Signer trên K8s | **Cao** | Spike bắt đầu tuần 1, đạt chậm nhất cuối tuần 2; A → B → C |
| Kyverno 1.20 (dự kiến ~11/2026, đã có rc.1) gỡ `ClusterPolicy`; Helm/CLI vô tình cài bản mới; mẫu extension không chạy | **Cao** | Ghim chart và CLI 1.19.x bằng phiên bản cụ thể; Policy 1 viết CEL; chuyển CEL hoàn toàn là hướng phát triển |
| Nhánh 1.19 đang ở cuối vòng đời: theo mô hình N-1, 1.19 vẫn được vá (CVE critical/high, lỗi nghiêm trọng) khi 1.20 ra, nhưng hết hỗ trợ khi 1.21 ra | Trung bình | Dùng bản vá 1.19.x mới nhất tại thời điểm cài, theo dõi các bản 1.19.x trong suốt đồ án; ghi rõ vào phần "Giới hạn" của báo cáo |
| Lỡ bật signing rule trước khi tạo fixture TC06 | Trung bình | Dùng phương án dự phòng `podinfo-alt` (mục 12.3): tách allowlist theo namespace, thêm `podinfo-alt` vào Policy 2 và TrustPolicy; gỡ sau khi thu bằng chứng |
| ECR Managed Signing chưa có ở region / API thay đổi | Trung bình | Kiểm tra trước; cập nhật AWS CLI; đổi region |
| Sai OIDC `sub` → không assume được role | Trung bình | Kiểm tra dạng claim thực tế, tách role publisher/deployer |
| Trivy báo Critical ngay trên image chuẩn | Trung bình | Distroless, cập nhật base/dependency; ngoại lệ có giải trình |
| Credential/ECR token hết hạn trước demo | Trung bình | `refresh-lab-credentials.sh`, thử 1 yêu cầu thật trước giờ demo |
| Policy chặn nhầm system pod | Thấp | Chỉ match `app`, `demo` |
| Lộ secret thật | Thấp | Chỉ dùng `DEMO_SECRET_`; bật Push Protection |
| Extension `kyverno-notation-aws` chậm cập nhật theo Kyverno / AWS Signer | Trung bình | Kiểm tra release gần nhất, ghim commit + image digest; sẵn phương án B/C (mục 6.3) |
| Deployer có quyền rộng hơn thiết kế | Trung bình | Role tối thiểu ở `k8s/rbac.yaml`, bằng chứng `auth can-i` (TC10) |
| Mất mạng / API cloud lỗi khi bảo vệ | Trung bình | Video và log/JSON gốc có ghi thời điểm; nói rõ phần không chạy trực tiếp |

Mỗi rủi ro đang xảy ra ghi vào ghi chú triển khai kèm người phụ trách, hạn xử lý và bằng chứng đã khắc phục.

### 14.3. Xử lý lỗi thường gặp

| Hiện tượng | Nguyên nhân có thể | Xử lý |
|---|---|---|
| CLI không có `put-signing-configuration` | AWS CLI cũ | Cập nhật, ghi version |
| Push được nhưng ký `FAILED` | Filter không khớp, thiếu `SignPayload`, sai region/profile | Xem signing config + `failureReason`; không deploy |
| Fixture unsigned bỗng được chấp nhận | Push lại sau khi bật rule, policy không match, cache | Đọc chữ ký thật, kiểm tra scope/webhook; tạo fixture mới đúng quy trình |
| `notation verify` fail | Chưa login ECR, sai trust scope/profile/root, session hết hạn | Tách kiểm tra auth / trust / revocation |
| CLI verify được, admission không được | Credential/TLS/RBAC của extension | Log extension, service endpoint, TLS Secret, IAM verifier |
| Image signed vẫn bị deny | Còn điều kiện attestation mẫu | Gỡ phần attestation minh họa |
| `ImagePullBackOff` | Token ECR hết hạn / thiếu quyền pull / namespace (vd. `demo`) chưa có `ecr-pull` hoặc ServiceAccount chưa gắn `imagePullSecrets` | Chạy lại `refresh-lab-credentials.sh`, kiểm tra Secret và ServiceAccount của namespace (mục 10.1); không sửa signature policy |
| Pod kẹt ở `CreateContainerConfigError` ("non-numeric user") | Image khai báo user dạng tên trong khi Pod bật `runAsNonRoot` | `USER 65532:65532` trong Dockerfile và `runAsUser: 65532` trong manifest (mục 7.2, 10.3) |
| TC06 bất ngờ được chấp nhận | Fixture được ký thêm bằng profile tin cậy (push/gắn tag sau khi bật rule, filter wildcard); hoặc, ở phương án `podinfo-alt`, Policy 2 không gửi image `podinfo-alt` sang extension nên chữ ký không được xác minh | `notation ls` + `notation inspect` kiểm tra chữ ký; thêm `podinfo-alt` vào bộ lọc image của Policy 2; tạo lại theo phương án dự phòng (mục 12.3) |
| TC06 bị chặn với thông báo sai nguồn | Fixture nằm ở repo không có trong allowlist; hoặc đã thêm allowlist cho `demo` nhưng policy chính vẫn match `demo` | Dùng `D_wrongsigner` trong `podinfo`; nếu dùng `podinfo-alt` thì tách allowlist theo namespace (mục 12.3) |
| podinfo lỗi khi gọi `/store` | Không ghi được vào `/data` (root filesystem chỉ đọc) | Mount `emptyDir` vào `/data` (mục 10.3) |
| Mọi image đều qua | Policy ở Audit, sai namespace, failurePolicy Ignore | Kiểm tra cấu hình, chạy lại TC04 |
| Deployment có nhưng không có Pod | Pod bị chặn khi ReplicaSet tạo | Xem event `FailedCreate` |
| Pipeline xanh dù có Critical | `ignore-unfixed`/ignore file, mất exit code | Chạy fixture TC03, kiểm tra gate |
| Secret đã xóa vẫn bị báo | Gitleaks quét lịch sử | Không merge fixture vào `main` |
| Chạy lại workflow bị lỗi push | Tag immutable trùng | Tag có `run_id` + `run_attempt` |
| `go: go.mod requires go >= …` khi build | Image Go cũ hơn yêu cầu (với `GOTOOLCHAIN=local`) | Đổi `golang:<GO_VERSION>` theo `go.mod`, pin digest mới |
| CRD `ClusterPolicy` không còn / policy biến mất | Helm cài nhầm Kyverno 1.20+ | Gỡ, cài lại đúng chart 1.19.x; kiểm tra chart `kyverno-api` |
| Ca deny không có trong PolicyReport | Bình thường: request bị chặn không tạo resource | Dùng stderr, event, log (mục 11.5) |
| `auth can-i` trả `yes` cho quyền đáng lẽ bị cấm | Binding thừa, group khác, dùng nhầm kubeconfig admin | Kiểm tra RoleBinding/ClusterRoleBinding của group, chạy lại TC10 |

---

## 15. Dàn ý báo cáo

**Chương 1. Tổng quan** – lý do chọn đề tài (các vụ tấn công chuỗi cung ứng), mục tiêu, phạm vi, câu hỏi nghiên cứu, phương pháp.

**Chương 2. Cơ sở lý thuyết**
- DevOps, CI/CD, DevSecOps (shift-left)
- Bảo mật chuỗi cung ứng: threat model, SLSA, NIST SSDF
- Container/OCI image, registry, **digest vs tag**, OCI referrers
- SBOM: SPDX, CycloneDX; quét lỗ hổng (CVE, nguồn advisory, severity của scanner ≠ CVSS NVD); quét secret
- Chữ ký số: Notary Project/Notation vs Sigstore/Cosign; trust store, trust policy, trusted identity, revocation; AWS Signer; ECR Managed Signing
- Kubernetes admission control, policy-as-code; Kyverno (ClusterPolicy → CEL policies) vs Gatekeeper

**Chương 3. Phân tích & thiết kế** – yêu cầu, kiến trúc (mục 2), ranh giới tin cậy, ma trận IAM, thiết kế security gate, thiết kế policy, thiết kế truy vết.

**Chương 4. Triển khai** – container hóa, AWS (ECR/Signer/Managed Signing/OIDC), pipeline, Kubernetes, Kyverno + verifier, **khó khăn & giải pháp** (spike, phiên bản Kyverno, OIDC claim…).

**Chương 5. Thực nghiệm & đánh giá** – môi trường + bộ phiên bản, ma trận TC01–TC10 với kết quả thật, số liệu (mục 12.5), phân tích, **giới hạn** (giả định publisher, Pod cũ không bị gỡ khi thu hồi, zero-day, SBOM chưa được ký…).

**Chương 6. Kết luận & hướng phát triển** – ký/attest SBOM, scan result và provenance rồi kiểm tra ở admission; GitOps; Terraform; quét lại định kỳ từ SBOM / Dependency-Track; remediation workload đang chạy khi thu hồi; ephemeral containers, multi-arch; license compliance, VEX.

**Phụ lục** – hướng dẫn dựng lại, cấu hình, lệnh demo, link repo, video.

**Đóng góp nên nhấn mạnh:** phối hợp nhiều lớp kiểm soát; ràng buộc artifact xuyên pipeline (build-once + release manifest); thiết kế policy; bộ kiểm thử có đối chứng.

---

## 16. Demo & câu hỏi bảo vệ

### 16.1. Kịch bản 10–15 phút

| Thời lượng | Nội dung |
|---|---|
| 1–2 phút | Bài toán + sơ đồ luồng tin cậy |
| 3 phút | Workflow thành công: SBOM, báo cáo, ECR digest + chữ ký, `release.json` |
| 2 phút | Triển khai digest hợp lệ, mở ứng dụng |
| 3–4 phút | TC02 secret, TC03 Critical (mở run đã chạy), **TC04 unsigned và TC05 sai nguồn chạy trực tiếp** |
| 1–2 phút | Truy vết Pod → commit; giới hạn; hướng phát triển |

**Trước buổi demo:** kiểm tra Internet, AWS session, ECR token, controller Ready, fixture Critical theo DB hiện tại, fixture unsigned vẫn chưa ký, account/region, digest hợp lệ. **Không** nâng cấp tool hay sửa policy sát giờ. Chuẩn bị video dự phòng + log/JSON gốc. Lệnh demo để sẵn trong `demo/commands.md` theo đúng thứ tự (dùng biến account/region/digest, không gõ lại), lời dẫn trong `docs/demo-script.md`. Mở sẵn hai terminal: một cho `port-forward`, một cho các ca admission.

### 16.2. Câu hỏi cần trả lời được

| Câu hỏi | Ý chính |
|---|---|
| SBOM khác báo cáo lỗ hổng thế nào? | SBOM là danh mục thành phần; scanner đối chiếu thành phần với dữ liệu advisory |
| Vì sao vừa scan vừa ký? | Scan đánh giá rủi ro đã biết; ký ràng buộc nội dung (digest) với danh tính tin cậy |
| ECR có tự chặn image Critical không? | Không; gate CI quyết định có push; Managed Signing ký mọi image push vào repo khớp filter |
| Vì sao dùng digest? | Cố định chính xác nội dung được xác minh và triển khai; tag có thể trỏ sang image khác |
| Image có chữ ký nhưng độc hại? | Vẫn có thể được chấp nhận nếu publisher bị lạm dụng → bảo vệ CI/IAM, bổ sung attestation |
| Verifier lỗi thì sao? | Fail-closed trong phạm vi enforce (TC09) |
| Thu hồi profile thì Pod cũ có dừng không? | Không; admission chỉ kiểm tra yêu cầu mới → cần rà soát/remediation riêng |
| Có đi vòng CI bằng `kubectl` được không? | Vẫn gặp admission; nhưng phải hạn chế quyền push, sửa policy, namespace ngoại lệ |
| Sao không dùng Cosign? | Đề tài dùng AWS Signer/ECR Managed Signing → định dạng Notation; Cosign là hệ sinh thái Sigstore khác |

---

## 17. Thu dọn tài nguyên

1. Tải về SBOM, báo cáo, `release.json`, log, video; kiểm tra mở được bản sao.
2. Xóa cụm kind; nếu dùng EKS: xóa LoadBalancer/PVC trước, rồi `eksctl delete cluster`.
3. Xóa image/repository lab (chỉ phạm vi của đồ án), kể cả repo `podinfo-alt` nếu đã dùng phương án dự phòng TC06.
4. Gỡ signing rule của đồ án (kể cả rule của `podinfo-alt` nếu có) nhưng **giữ** các rule khác trong registry; xử lý **cả** profile chính và profile B (`podinfo_wrong_signer`) — revoke/cancel theo vòng đời AWS.
5. Xóa IAM role/policy/OIDC provider nếu chỉ tạo cho đồ án; xóa credential tạm, Secret runtime.
6. Kiểm tra Billing vài ngày sau.

Script cleanup (nếu có) phải kiểm tra account ID, region, tên tài nguyên cụ thể; không xóa hàng loạt trên toàn account.

---

## 18. Checklist hoàn thành

**Hạ tầng & phân quyền**
- [ ] Bộ phiên bản đã chốt sau spike, ghi trong `docs/versions.md`; Kyverno chart **và** Kyverno CLI ghim 1.19.x, Policy 1 viết CEL; giới hạn hỗ trợ N-1 của nhánh 1.19 (vẫn được vá CVE critical/high khi 1.20 ra, hết hỗ trợ khi 1.21 ra) đã ghi vào báo cáo
- [ ] Quyết định ở mục 3.4 và lý do đã ghi trong `docs/architecture.md`
- [ ] ECR repo immutable; fixture `unsigned-baseline` và `wrong-signer-baseline` tạo **trước** khi bật signing rule
- [ ] Lifecycle policy chỉ chọn tag tiền tố `sha-`, không có rule `untagged`; đã chạy lifecycle preview
- [ ] Signing rule dùng filter đúng `podinfo` (không wildcard); profile B không có trong signing rule hay `trustedIdentities`
- [ ] Signing profile + signing rule đúng repo, cùng region
- [ ] OIDC: role publisher (branch `main`) và deployer (environment) tách riêng, `sub` đúng dạng thực tế
- [ ] Publisher không sửa được IAM/signing rule/K8s policy; verifier không ký/push được

**Pipeline**
- [ ] Test, Gitleaks (+ rule `DEMO_SECRET_`), build một lần → `image.tar`
- [ ] SBOM CycloneDX hợp lệ; Trivy scan một lần + gate 0 Critical
- [ ] Job `verify` không có `id-token`; `publish` load đúng tar (checksum + image ID), không build lại
- [ ] Tag duy nhất theo run; chờ `COMPLETE` đúng profile có timeout
- [ ] `release.json` truy vết đủ trường; action pin theo SHA; branch protection
- [ ] Dockerfile dùng Go theo `go.mod` (`GOTOOLCHAIN=local`), base image pin digest, `USER 65532:65532`; tự build podinfo từ source
- [ ] SBOM tạo bằng Syft CLI đã ghim phiên bản + checksum; upload `approved-image` chỉ chạy với `push` vào `main`
- [ ] Job summary hiển thị pass/fail/chưa chạy từng cổng; bước SARIF bỏ qua đúng với PR từ fork

**Kubernetes**
- [ ] Policy repo + digest (containers + initContainers), chỉ namespace ứng dụng
- [ ] Policy chữ ký (A/B/C) enforce, failurePolicy Fail, đã gỡ attestation mẫu
- [ ] Deployer dùng Role tối thiểu (`k8s/rbac.yaml`), **không** dùng `AmazonEKSEditPolicy`; có bằng chứng `auth can-i` (Secret, exec, ephemeral containers, policy, namespace đều `no`)
- [ ] Job `policy-test` (Kyverno CLI 1.19.x qua `scripts/policy-test.sh`, render cả policy lẫn resource bằng giá trị giả cố định) đạt và là required check; bằng chứng deny lấy từ stderr/event/log, không dựa PolicyReport
- [ ] Namespace `app` và `demo` đều có `ecr-pull` và ServiceAccount `default` đã gắn `imagePullSecrets` (kind)
- [ ] Manifest có `runAsUser`/`runAsGroup: 65532` và `emptyDir` cho `/tmp`, `/data`; Pod Ready trên cụm thật
- [ ] `notation verify` CLI pass với signed, fail với unsigned

**Kiểm thử & nộp**
- [ ] TC01–TC05 đạt có bằng chứng; TC06–TC10 đạt hoặc ghi "chưa thực hiện"
- [ ] Số liệu đo thật, lặp ≥ 3 lần nếu kịp
- [ ] Báo cáo, slide, video dự phòng, README dựng lại từ môi trường sạch
- [ ] Đã loại token/access key/kubeconfig khỏi nội dung nộp
- [ ] Đã thu dọn tài nguyên AWS

---

## 19. Tài liệu tham khảo

Ưu tiên tài liệu của **đúng phiên bản đã chốt**; trang `main`/`latest` có thể thay đổi.

| Nguồn | Dùng cho |
|---|---|
| [Amazon ECR – Managed signing](https://docs.aws.amazon.com/AmazonECR/latest/userguide/managed-signing.html) | Signing rule, filter, IAM |
| [AWS CLI – put-signing-configuration](https://docs.aws.amazon.com/cli/latest/reference/ecr/put-signing-configuration.html) | Cấu hình ký |
| [AWS CLI – describe-image-signing-status](https://docs.aws.amazon.com/cli/latest/reference/ecr/describe-image-signing-status.html) | COMPLETE / FAILED / IN_PROGRESS |
| [AWS Signer – signing steps](https://docs.aws.amazon.com/signer/latest/developerguide/image-signing-steps.html) | Platform Notation, profile |
| [AWS Signer – prerequisites](https://docs.aws.amazon.com/signer/latest/developerguide/image-signing-prerequisites.html) | Plugin, root certificate |
| [AWS Signer – verify locally](https://docs.aws.amazon.com/signer/latest/developerguide/image-verification.html) | Trust store/policy, `notation verify` |
| [AWS Signer – verify on EKS/Kubernetes](https://docs.aws.amazon.com/signer/latest/developerguide/kubernetes-verification.html) | Lựa chọn admission |
| [EKS – Validate image signatures](https://docs.aws.amazon.com/eks/latest/userguide/image-verification.html) | Kyverno/Ratify với AWS Signer |
| [kyverno-notation-aws (Nirmata)](https://github.com/nirmata/kyverno-notation-aws) | Extension, TrustPolicy/TrustStore, policy mẫu |
| [Kyverno – Installation](https://kyverno.io/docs/installation/installation/) | Cài đặt, tương thích |
| [Kyverno – Policy types / ClusterPolicy deprecation](https://kyverno.io/docs/policy-types/overview/) | Chọn API theo phiên bản |
| [Kyverno 1.19 release](https://kyverno.io/blog/2026/08/20/announcing-kyverno-release-1.19) | Lộ trình gỡ ClusterPolicy |
| [Kyverno 1.17 release](https://kyverno.io/blog/2026/02/02/announcing-kyverno-release-1.17/) | Mốc bắt đầu deprecation |
| [Kyverno 1.18 release](https://kyverno.io/blog/2026/04/24/announcing-kyverno-release-1.18/) | Chính sách hỗ trợ N-1 ("main + 1"): bản nào còn được vá |
| [Kyverno CLI – test](https://kyverno.io/docs/kyverno-cli/reference/kyverno_test/) | Test policy offline |
| [Kyverno – Policy Reports](https://kyverno.io/docs/guides/reports/) | Phạm vi của report (không ghi lại request bị chặn) |
| [GitHub – OIDC với AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) | Trust subject |
| [GitHub – Job summary](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-job-summary) | Tóm tắt kết quả từng run |
| [GitHub – Upload SARIF](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/integrate-with-existing-tools/upload-sarif-file) | Code scanning, quyền với PR từ fork |
| [EKS – Access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html) | Cấp quyền cho role deployer |
| [ECR – IAM actions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ecr.html) | Tối thiểu quyền publisher |
| [Kubernetes – RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) | Role/RoleBinding cho deployer |
| [Trivy](https://trivy.dev/) · [Syft](https://github.com/anchore/syft) · [Gitleaks](https://github.com/gitleaks/gitleaks) | Công cụ scan/SBOM |
| [ORAS attach](https://oras.land/docs/commands/oras_attach/) | Gắn SBOM vào digest (mở rộng) |
| [Notary Project](https://notaryproject.dev/) · [SLSA](https://slsa.dev/) · [CycloneDX](https://cyclonedx.org/) | Lý thuyết |
| [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/) · [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | Digest/tag, cụm local |
| [podinfo](https://github.com/stefanprodan/podinfo) · [Flask tutorial](https://flask.palletsprojects.com/en/stable/tutorial/) | Workload |

**Việc nên làm ngay:** ghim Kyverno 1.19.x, rồi làm mục 4 (môi trường) và mục 6 (spike). Khi luồng *ký → xác minh → từ chối unsigned* đã chạy và được ghi lại, mới đi tiếp pipeline, triển khai và thực nghiệm.
