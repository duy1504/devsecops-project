# CLAUDE.md — Đồ án DevSecOps: bảo mật chuỗi cung ứng container image

Bộ nhớ dự án, nạp tự động mỗi phiên. Chỉ giữ thông tin cốt lõi; chi tiết nằm trong `KE_HOACH_DO_AN_FINAL.md`.

## Quy tắc làm việc

1. **Đầu phiên:** đọc `PROGRESS.md` để nắm trạng thái và việc tiếp theo.
2. **Chỉ đọc phần liên quan** tới nhiệm vụ hiện tại (tài liệu hoặc source code). Với kế hoạch (~1.800 dòng): `Grep "^#{2,3} "` để lấy mục lục kèm số dòng, rồi `Read` đúng mục bằng `offset`/`limit`. Không đọc cả file.
3. **Không tự phân tích lại toàn bộ dự án** mỗi phiên. Dựa vào `PROGRESS.md` và file này; chỉ kiểm tra lại khi thấy dấu hiệu sai lệch.
4. **Cập nhật `PROGRESS.md`** khi xong một giai đoạn hoặc có thay đổi quan trọng (quyết định, phiên bản, sự cố, bằng chứng): tick việc đã xong, thêm một dòng nhật ký.
5. **Hỏi người dùng trước** khi thay đổi kiến trúc, phạm vi, công cụ đã chốt hoặc lịch trình.
6. `KE_HOACH_DO_AN_FINAL.md` là **tài liệu gốc**: chỉ tham chiếu, chỉ sửa khi người dùng yêu cầu. Phiên bản và hash ghi vào `docs/versions.md`.
7. Trả lời bằng **tiếng Việt**. Lệnh nhiều dòng trong kế hoạch là **Bash trên WSL2 Ubuntu**, không dán vào PowerShell (`C:\Teo\DevOps` = `/mnt/c/Teo/DevOps`).
8. Không ghi token, access key, kubeconfig hay secret thật vào file/commit. Số liệu trong báo cáo chỉ lấy từ thực nghiệm thật.
9. **GitHub trên máy này:** chạy fetch/push trong PowerShell tại `C:\Teo\DevOps`. Repo đã cấu hình `credential.https://github.com.helper` dùng Git Credential Manager của Git for Windows; Git MSYS2 cũng dùng được. Nếu cần gọi trực tiếp: `& 'C:\Program Files\Git\cmd\git.exe' push origin main`. Không chạy Git remote của repo này bằng Git Linux trong WSL vì helper đang dùng đường dẫn Windows. Khi lỗi xác thực, kiểm tra `git push --dry-run origin main` trong môi trường có quyền mạng trước khi nhờ người dùng push; không đọc/in token. Đã kiểm tra dry-run thành công ngày 17/11/2026; đây không phải push thật.

## Tài liệu

| File | Vai trò |
|---|---|
| `PROGRESS.md` | Trạng thái, việc tiếp theo, quyết định đang chờ |
| `KE_HOACH_DO_AN_FINAL.md` | Kế hoạch chi tiết — tài liệu gốc |
| `docs/versions.md` | Phiên bản + SHA-256 đã xác minh, kèm ngày kiểm tra |
| `Dự kiến.txt` | Đề cương gốc của môn học |

Hai bản nháp `KE_HOACH_DO_AN.md`, `KE_HOACH_DO_AN_DEVSECOPS.md` (nhắc ở đầu kế hoạch) đã bị xóa, không cần tìm.

**Mục lục kế hoạch:** 1 mục tiêu, KQ1–KQ7 · 2 kiến trúc, ranh giới tin cậy, 3 đường xác thực · 3 công cụ, ghim phiên bản, **3.4 quyết định đã chốt** · 4 môi trường, biến cấu hình (4.3) · 5 cấu trúc repo · **6 spike đường găng** · 7 podinfo, Dockerfile · 8 ECR, lifecycle, Signer, Managed Signing, IAM, OIDC · 9 pipeline (**9.4 workflow YAML**) · 10 kind/EKS, RBAC, manifest, deploy · 11 Kyverno, Policy 1/2, test offline · 12 TC01–TC10, bằng chứng · 13 lịch 6/8/10 tuần · 14 chi phí, rủi ro, xử lý lỗi · 15 dàn ý báo cáo · 16 demo, câu hỏi bảo vệ · 17 thu dọn · 18 checklist · 19 tham khảo.

## Tóm tắt đồ án

**Đề tài:** Bảo mật chuỗi cung ứng cho container image bằng SBOM, Amazon ECR Managed Signing (AWS Signer) và kiểm soát triển khai trên Kubernetes (Kyverno). Môn Công nghệ DevOps và Ứng dụng.

**Câu hỏi nghiên cứu:** phối hợp kiểm soát ở CI và ở admission có phát hiện/ngăn được 4 tình huống (secret trong code, image có CVE Critical, image chưa ký, image từ nguồn không được phép), đồng thời truy vết được Pod → digest → SBOM → commit không?

**Luồng dự kiến:**
1. PR/push → job `verify` (không có quyền AWS): unit test → Gitleaks → build **một lần** ra `image.tar` → Syft SBOM (CycloneDX) → Trivy scan một lần ra JSON → gate **0 Critical**. Job `policy-test` chạy Kyverno CLI offline song song.
2. Push vào `main` → job `publish` (OIDC): load đúng `image.tar` (kiểm checksum + image ID), push tag duy nhất `sha-<12>-run-<id>-<attempt>`, chờ ký `COMPLETE` đúng profile, ghi `release.json`.
3. ECR Managed Signing tự ký bằng AWS Signer (chữ ký Notation, lưu dạng OCI referrer). Đường phát hành không có lệnh ký thủ công.
4. Triển khai bằng **digest**. Kyverno: Policy 1 (`ValidatingPolicy` CEL) chỉ cho `<account>.dkr.ecr.<region>.amazonaws.com/podinfo@sha256:`; Policy 2 (`ClusterPolicy` theo mẫu extension) gọi `kyverno-notation-aws` xác minh chữ ký, `trustedIdentities` và thu hồi.

## Quyết định đã chốt (muốn đổi phải hỏi người dùng)

| Hạng mục | Lựa chọn |
|---|---|
| Workload | podinfo (Go), tự build từ source tại tag đã pin |
| Secret / SBOM / CVE | Gitleaks / Syft CLI / Trivy |
| Registry, ký | ECR private repo `podinfo` (tag IMMUTABLE), region đề xuất `ap-southeast-1` (cần xác nhận hỗ trợ Managed Signing); AWS Signer platform `Notation-OCI-SHA384-ECDSA` |
| Kubernetes | kind cho phát triển và demo chính; EKS chỉ là mở rộng |
| Admission | Kyverno 1.19.x (hiện ghim v1.19.2 / chart 3.9.2, nguồn chuẩn là `docs/versions.md`) + `kyverno-notation-aws` **tự build từ source** (`scripts/build-notation-ext.sh`, commit ghim, gate 0 Critical; release `v1.1` có 6 Critical, repo sắp archive); phương án lùi B (Kyverno native) → C (Ratify + Gatekeeper) |
| Image | Một kiến trúc `linux/amd64` |
| Triển khai | `scripts/deploy.sh` trên máy có cụm; job `deploy` chỉ dùng khi có EKS |
| Namespace | `app` (workload), `demo` (ca kiểm thử) |

## Bất biến kỹ thuật — không được phá

- Build một lần; `publish` không build lại. Job `verify` không có `id-token`; không dùng `pull_request_target`.
- Gate Trivy không dùng `--ignore-unfixed`; không dùng `continue-on-error` hay `|| true` cho gate.
- Pin GitHub Actions theo commit SHA; Syft và Kyverno CLI kiểm tra bằng SHA-256 ghim trong workflow.
- Fixture `D_unsigned` và `D_wrongsigner` (ký tay bằng profile B) tạo **trước** khi bật signing rule, cùng repo `podinfo`; không push hay gắn tag lại. Lifecycle chỉ chọn tag tiền tố `sha-`.
- Signing filter đúng tên `podinfo`, không wildcard. Profile B không nằm trong signing rule hay `trustedIdentities`.
- OIDC tách role publisher (`ref:refs/heads/main`) và deployer (`environment:production`); kiểm tra dạng `sub` thực tế.
- Container `USER 65532:65532` + `runAsUser/runAsGroup: 65532`; `emptyDir` cho `/tmp` và `/data`.
- Policy chỉ match namespace `app`, `demo`. Deployer dùng Role tối thiểu (`k8s/rbac.yaml`), không dùng `AmazonEKSEditPolicy`.
- Helm và CLI Kyverno luôn có `--version`, không dùng `--devel`. Kyverno 1.20.0 đã ra (11/2026) nhưng vẫn giữ CRD `ClusterPolicy` (deprecated, "will be removed"); mục 3.3 của kế hoạch viết trước thời điểm này.
- Không "chữa" lỗi bằng trust level `skip`, tắt TLS, tin mọi signer, webhook `Ignore` hay chuyển sang Audit.
- Bằng chứng deny: stderr + exit code + event + log. Không dựa vào PolicyReport; `ImagePullBackOff` không phải bằng chứng.
- Secret demo chỉ dùng chuỗi giả `DEMO_SECRET_` + 32 hex, không merge vào `main`.

## Ca kiểm thử

Bắt buộc: TC01 hợp lệ · TC02 secret · TC03 CVE Critical · TC04 chưa ký · TC05 sai nguồn.
Mở rộng: TC06 sai người ký · TC07 tag thay digest · TC08 init container · TC09 fail-closed (ưu tiên) · TC10 RBAC.

## Giới hạn cần nêu trong báo cáo

- Managed Signing ký mọi image push vào repo khớp filter; "chỉ image đạt mới được ký" dựa vào pipeline và quyền push.
- Kyverno hỗ trợ N-1 (từ 1.18): 1.19 còn được vá CVE critical/high khi 1.20 ra, hết hỗ trợ khi 1.21 ra.
- Admission không gỡ Pod đã chạy; chữ ký image không ký SBOM.
- `kyverno-notation-aws` không có bản phát hành sạch CVE và upstream sắp archive → đồ án tự build từ `main` (ghim commit, có bản vá cục bộ).
