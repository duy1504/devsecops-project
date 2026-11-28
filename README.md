# Bảo mật chuỗi cung ứng cho container image

Đồ án môn **Công nghệ DevOps và Ứng dụng**. Đề tài: *Xây dựng quy trình bảo mật chuỗi cung ứng phần mềm cho container image sử dụng SBOM, Amazon ECR Managed Signing và kiểm soát triển khai trên Kubernetes.*

```
commit → GitHub Actions: test · Gitleaks · build 1 lần · SBOM (Syft) · Trivy gate 0 Critical
       → publish (OIDC) → Amazon ECR → ECR Managed Signing (AWS Signer, Notation)
       → deploy bằng digest → Kyverno: Policy 1 (đúng repo + digest) · Policy 2 (chữ ký tin cậy) → Pod
```

## Kết quả

Mười ca kiểm thử đều đạt trên môi trường thật (GitHub Actions, ECR, AWS Signer, Kubernetes kind + Kyverno 1.19.2):

| Ca | Tình huống | Bị chặn bởi |
|---|---|---|
| TC01 | Luồng hợp lệ, commit → Pod | (được nhận) |
| TC02 | Secret trong mã | Gitleaks |
| TC03 | Image có CVE Critical | Trivy gate |
| TC04 | Image chưa ký | Policy 2 |
| TC05 | Image sai nguồn | Policy 1 |
| TC06 | Ký bởi danh tính khác | Policy 2 (trusted identity) |
| TC07 | Dùng tag thay digest | Policy 1 |
| TC08 | Init container vi phạm | Policy 1 + 2 |
| TC09 | Verifier ngừng hoạt động | Fail-closed |
| TC10 | Deployer vượt quyền | RBAC |

Chi tiết và bằng chứng: [`docs/test-results.md`](docs/test-results.md), [`docs/evidence/`](docs/evidence/).

## Tài liệu

| Tài liệu | Nội dung |
|---|---|
| [`docs/report/`](docs/report/) | Báo cáo: Chương 1–6 và phụ lục |
| [`docs/report/phu-luc-a-huong-dan-dung-lai.md`](docs/report/phu-luc-a-huong-dan-dung-lai.md) | **Hướng dẫn dựng lại từ đầu** |
| [`docs/architecture.md`](docs/architecture.md) | Kiến trúc, ranh giới tin cậy, các quyết định và lý do |
| [`docs/versions.md`](docs/versions.md) | Bộ phiên bản đã chốt, kèm SHA-256/digest |
| [`docs/test-results.md`](docs/test-results.md) | Kết quả từng ca, số liệu đo, vấn đề phát hiện |
| [`KE_HOACH_DO_AN_FINAL.md`](KE_HOACH_DO_AN_FINAL.md) | Kế hoạch chi tiết |

## Cấu trúc

```
app/                        podinfo 6.17.0 (Go), vendor từ upstream tại commit ghim
Dockerfile                  multi-stage, distroless, UID 65532, base ghim digest
.github/workflows/ci-cd.yml verify · policy-test · publish
infra/aws/                  template IAM, signing configuration, lifecycle
infra/kyverno-notation-aws/ CRD, manifest, bản vá extension
policies/                   Policy 1 (CEL), Policy 2, TrustPolicy, TrustStore, test offline
k8s/                        namespace, RBAC, Deployment, Service
scripts/                    dựng, triển khai, kiểm thử, đo đạc
```

Workload mẫu là [podinfo](https://github.com/stefanprodan/podinfo) (Apache-2.0), nguồn gốc ghi trong [`docs/upstream.md`](docs/upstream.md).
