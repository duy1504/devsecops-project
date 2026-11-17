# PROGRESS.md — Tiến độ đồ án

Đọc file này đầu mỗi phiên. Cập nhật khi xong một giai đoạn hoặc có thay đổi quan trọng (quy tắc trong `CLAUDE.md`).

**Cập nhật lần cuối:** 17/11/2026
**Trạng thái:** ✅ Lập kế hoạch hoàn thành · 🔄 Chuẩn bị môi trường **đang làm** (repo GitHub, WSL/Docker, công cụ đã xong; AWS account đã tạo nhưng chưa đăng nhập CLI) · chưa có code ứng dụng, chưa tạo tài nguyên AWS nào
**Giai đoạn kế tiếp:** trong lúc AWS chưa dùng được: podinfo + Dockerfile (mục 7); khi có AWS: đăng nhập (mục 4) → spike (mục 6)

## ⏸ Điểm dừng (17/11/2026) — làm tiếp từ đây

Đang chờ **người dùng** làm trên AWS (Claude không xử lý credential):
1. Xác nhận: MFA cho root, AWS Budgets (~10 USD), user riêng dùng hằng ngày (không dùng root).
2. Bật IAM Identity Center → tạo user, gán permission set `AdministratorAccess` vào account lab.
3. Trong WSL: `aws configure sso` (region mặc định `ap-southeast-1`, profile gợi ý `devsecops`) → `aws sts get-caller-identity --profile devsecops`.
4. Báo lại **tên profile** cho Claude.

**Đổi thứ tự (người dùng đồng ý 17/11/2026):** account AWS tạm chưa dùng được → làm trước phần không phụ thuộc AWS, theo thứ tự: ~~(1) kiểm tra tương thích `kyverno-notation-aws` ↔ Kyverno 1.19.2~~ ✅ xong 17/11 (tự build, gate 0 Critical/0 High, `go test` đạt; chưa chạy trên cụm) → **(2) tiếp theo:** podinfo + Dockerfile + test → (3) scan local (Gitleaks, `image.tar`, Syft, Trivy) → (5) kind + Kyverno + Policy 1 + RBAC/manifest → (4) job `verify` + `policy-test`. **Chưa làm** Policy 2, `publish`, OIDC, `wait-signature.sh` cho tới khi spike đạt.

Khi AWS dùng được, Claude làm: kiểm tra region hỗ trợ ECR Managed Signing → đặt biến mục 4.3 → spike mục 6.1 bước 1–3 (repo `podinfo` **chưa** bật signing rule → `D_unsigned` → `D_wrongsigner` ký bằng profile B). Chứng chỉ gốc AWS Signer đã tải và ghi fingerprint trong `docs/versions.md` (dùng ở bước 4).

## Đã hoàn thành

- [x] Đề cương `Dự kiến.txt`.
- [x] Kế hoạch chi tiết `KE_HOACH_DO_AN_FINAL.md`: đã rà soát, sửa lỗi và chốt.
- [x] `docs/versions.md`: xác minh ngày 04/11/2026 — Kyverno v1.19.2 / chart 3.9.2, Kyverno CLI v1.19.2 và Syft v1.56.0 (kèm SHA-256); đang theo dõi `v1.20.0-rc.1`.
- [x] Thiết lập bộ nhớ dự án: `CLAUDE.md`, `PROGRESS.md`.

## Quyết định đã chốt (17/11/2026)

- Lịch: không cố định hạn theo tuần; làm tuần tự theo kế hoạch (phương án A: tạo AWS account và làm spike trước, phần local sau).
- Cụm: **kind** (phát triển + demo); EKS chỉ làm nếu còn thời gian.
- Làm **cá nhân**.
- Repo code: đặt ngay trong `C:\Teo\DevOps`.
- AWS: dùng **account lab riêng** (signing configuration ở cấp registry, dễ thu dọn).
- **Extension `kyverno-notation-aws`: tự build từ source** (người dùng chọn 17/11/2026). Lý do: release chính thức mới nhất `v1.1` có 6 CVE Critical, repo sắp archive; nhánh `main` đã vá nhưng không phát hành. Build bằng `scripts/build-notation-ext.sh`: ghim commit `58b210b`, builder `golang:1.26.10-alpine3.24` và runtime distroless theo digest, vá thêm `x/net` 0.62.0 + `go-jose/v4` 4.1.6, gate 0 Critical. Ghi vào phần "Giới hạn" của báo cáo: dùng bản không phát hành chính thức, upstream sắp ngừng bảo trì.

## Việc tiếp theo (đúng thứ tự kế hoạch)

### Chuẩn bị (mục 3.3, 4)

- [x] Kiểm tra lại Kyverno (17/11/2026): 1.19.2 vẫn là bản vá mới nhất của 1.19; **v1.20.0 đã ra nhưng chưa gỡ `ClusterPolicy`**; chưa có tag chart 3.10.x. Giữ ghim 1.19.2 / chart 3.9.2 (chi tiết trong `docs/versions.md`).
- [x] GitHub repo `duy1504/devsecops-project`; `git init -b main` trong `C:\Teo\DevOps`, remote `origin` đã thêm; có `.gitignore`, `.gitattributes` (LF cho script). Commit đầu `88cda11` đã push lên `origin/main` (17/11/2026).
- [x] WSL2 Ubuntu + Docker Desktop (engine 29.9.1) đang chạy (17/11/2026).
- [x] AWS account lab đã tạo (Paid plan, 17/11/2026). Chưa xác nhận: MFA root, user/SSO riêng, AWS Budgets.
- [x] Công cụ trong WSL: `scripts/install-tools.sh` (cài vào `~/.local`, không sudo, ghim phiên bản + SHA-256) chạy thành công 17/11/2026; bộ phiên bản ở mục 1b `docs/versions.md`. AWS CLI 2.40.4 có đủ lệnh Managed Signing.
- [ ] Cấu hình AWS CLI trong WSL (`aws configure sso` hoặc credential ngắn hạn), `aws sts get-caller-identity` thành công.
- [ ] Xác nhận region `ap-southeast-1` hỗ trợ ECR Managed Signing; AWS CLI có `put-signing-configuration`.
- [ ] Đặt biến cấu hình ở mục 4.3 (cần AWS CLI đã đăng nhập).

### Giai đoạn 0 — Spike đường găng (mục 6)

Làm ngay sau phần chuẩn bị. Chưa qua tiêu chí 6.2 thì chưa làm pipeline.

- [ ] Bước 1–2: repo ECR `podinfo` (chưa bật signing rule) → fixture `D_unsigned`.
- [ ] Bước 3: profile B → fixture `D_wrongsigner` ký tay — **trước** khi bật signing rule.
- [ ] Bước 4: `notation verify` thất bại với cả hai fixture.
- [ ] Bước 5–7: profile chính + bật Managed Signing → `D_signed` → `COMPLETE` → `notation verify` thành công.
- [ ] Bước 8–9: kind + Kyverno 1.19.2 + extension; signed được chấp nhận, unsigned và wrong-signer bị từ chối; thử fail-closed.
- [ ] Bước 10: lưu log, chốt bộ phiên bản vào mục 4 của `docs/versions.md`.
- Nếu không đạt: lùi theo A → B → C (mục 6.3), tối đa 2–3 ngày mỗi phương án.

### Các giai đoạn sau (chỉ bắt đầu khi spike đạt)

- [ ] Giai đoạn 1 — podinfo, Dockerfile, test, scan local (mục 7).
- [ ] Giai đoạn 2 — hoàn thiện AWS/IAM: lifecycle, ma trận quyền, OIDC, `wait-signature.sh` (mục 8).
- [ ] Giai đoạn 3 — pipeline: `verify`, `policy-test`, `publish`, branch protection (mục 9).
- [ ] Giai đoạn 4 — triển khai: namespace, pull secret, RBAC, manifest, `deploy.sh` (mục 10).
- [ ] Giai đoạn 5 — Policy 1 + Policy 2 hoàn chỉnh, test offline (mục 11).
- [ ] Giai đoạn 6 — TC01–TC05 bắt buộc, TC06–TC10 nếu kịp; đo đạc, thu bằng chứng (mục 12).
- [ ] Báo cáo, slide, video dự phòng, README dựng lại (mục 15–16); thu dọn AWS (mục 17); checklist (mục 18).

## Cần kiểm chứng khi triển khai

Các điểm kế hoạch ghi là "mẫu, cần đối chiếu":

- `apiVersion` của `ValidatingPolicy` trên bản cài; schema `kyverno-test.yaml` cho `ValidatingPolicy`.
- Schema output của `describe-image-signing-status`.
- Dạng claim `sub` OIDC thực tế của repo.
- Release `kyverno-notation-aws` tương thích Kyverno 1.19.2; gỡ phần attestation minh họa trong mẫu policy.
- Cú pháp `gitleaks git`, `trivy convert` theo bản ghim; tập IAM action tối thiểu.

## Nhật ký

| Ngày | Nội dung |
|---|---|
| 04/11/2026 | Hoàn thành kế hoạch cuối; xác minh phiên bản Kyverno/Syft; tạo `CLAUDE.md`, `PROGRESS.md`. Chưa triển khai. |
| 17/11/2026 | Chốt 4 quyết định: lịch tuần tự, kind, cá nhân, repo trong `C:\Teo\DevOps`, AWS account lab riêng. Kiểm tra Kyverno: v1.20.0 đã ra, vẫn còn CRD `ClusterPolicy`; giữ ghim 1.19.2. Repo git nối GitHub, đã push. AWS account (Paid plan) đã tạo. Cài 11 công cụ trong WSL bằng `scripts/install-tools.sh` (commit `1fd35f4`). Tạm dừng: chờ người dùng bật MFA/Budgets/SSO và chạy `aws configure sso`. |
| 17/11/2026 | Sửa xác thực GitHub cho agent: cấu hình helper riêng repo trỏ Git Credential Manager của Git for Windows. Git MSYS2 chạy `git push --dry-run origin main` thành công, dự kiến đẩy `1fd35f4..29ef59e`; chưa push thật. Ghi cách dùng PowerShell và giới hạn helper Windows trong `CLAUDE.md`. |

<!-- Mẫu một dòng nhật ký: | dd/mm/yyyy | Giai đoạn · việc đã xong · bằng chứng (đường dẫn) · vấn đề còn mở | -->
| 17/11/2026 | AWS tạm chưa dùng được → người dùng đồng ý làm trước phần không phụ thuộc AWS. Đánh giá `kyverno-notation-aws`: release `v1.1` có 6 Critical/80 High (Trivy, DB 16/11), repo sắp archive. Người dùng chọn **tự build từ `main@58b210b`**: `scripts/build-notation-ext.sh` (builder Go 1.26.10 + runtime ghim digest, vá `x/net`/`go-jose`) → 0 Critical/0 High, `go test` đạt; bằng chứng `reports/notation-ext/` (không commit). Chi tiết `docs/versions.md` mục 2b. |
