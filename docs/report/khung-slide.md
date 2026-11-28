# Khung slide bảo vệ (12–15 phút)

> Khung nội dung cho bộ slide, khớp kịch bản ở Phụ lục B. Mỗi slide ghi tiêu đề, nội dung chính (tối đa 4–5 ý, chữ ít), hình dùng và mốc thời gian. Số liệu lấy từ Chương 5 / `docs/test-results.md`. Hình ở `docs/report/figures/` (bản PNG để chèn). Phần demo chạy trên terminal, slide chỉ làm mốc chuyển.

| # | Mốc | Tiêu đề | Nội dung chính | Hình / ghi chú |
|---|---|---|---|---|
| 1 | 0:00 | **Bảo mật chuỗi cung ứng cho container image** | Tên đề tài đầy đủ · môn Công nghệ DevOps và Ứng dụng · họ tên, MSSV · ngày bảo vệ | — |
| 2 | 0:20 | Image "chạy được" chưa chắc đáng tin | 4 sự cố: SolarWinds (build), Codecov (công cụ CI), xz-utils (dependency), tj-actions (GitHub Action) · Kẻ tấn công nhắm vào mắt xích, không phải ứng dụng | Bảng 4 sự cố (Chương 1) |
| 3 | 0:50 | Mục tiêu và câu hỏi nghiên cứu | Câu hỏi: phối hợp CI + admission có chặn được 4 tình huống và truy vết được Pod → commit không? · 4 tình huống: secret, CVE Critical, chưa ký, sai nguồn | 4 biểu tượng cho 4 tình huống |
| 4 | 1:20 | Kiến trúc: hai lớp, nối bằng chữ ký | CI chặn trước khi **phát hành** · Admission chặn trước khi **chạy** · Chữ ký số do ECR Managed Signing tạo: chỉ pipeline trên `main` mới tạo được | **Hình 3.1** (toàn slide) |
| 5 | 2:00 | Ai được làm gì | Ba danh tính AWS, mỗi danh tính một việc · Không có access key dài hạn (GitHub OIDC) · Deployer không exec, không đọc Secret | **Hình 4.1** |
| 6 | 2:40 | Pipeline: build một lần, quét một lần | `verify` (không quyền AWS): test → Gitleaks → build → SBOM → Trivy gate 0 Critical · `publish` (chỉ `main`): push **đúng** `image.tar` đã quét (kiểm SHA-256 + image ID) · Action ghim SHA, branch protection | Sơ đồ 3 job (cắt từ Hình 3.1) |
| 7 | 3:20 | Ký tự động, không quản lý khóa | ECR Managed Signing + AWS Signer (Notation) · Ký ~**2,2 s** sau push (n=4) · Pipeline chỉ chờ `COMPLETE` đúng profile, không có lệnh ký | Ảnh ECR console: image + chữ ký |
| 8 | 3:50 | Admission: hai policy, mặc định từ chối | Policy 1 (CEL): đúng repo + digest 64 hex, kể cả init container · Policy 2: chữ ký của **đúng profile**, kiểm thu hồi · Extension tự build (bản phát hành có 6 Critical) + vá 2 lỗi | Bảng 2 policy (Chương 3 mục 3.7.1) |
| 9 | 4:30 | **DEMO** | (1) run thành công + `release.json` · (2) `demo.sh tc01` · (3) TC02/TC03 (run cũ) · (4) `demo.sh tc04`, `tc05` · (5) `demo.sh trace` | Chuyển sang trình duyệt + terminal (Phụ lục B, 4:30–13:00) |
| 10 | 13:00 | Kết quả: 10/10 ca đạt | Bảng TC01–TC10: tình huống · lớp chặn · lý do · Mỗi ca bị chặn **đúng lớp, đúng nguyên nhân**, có đối chứng | Bảng 5.3 (rút gọn) |
| 11 | 13:20 | Chi phí bảo mật nhỏ | Các bước quét < 10 s / job `verify` 105,5 s · Ký ~2,2 s · Xác minh chữ ký +1,5–2 s mỗi Pod · Verifier tắt → chặn sau ~0,3 s | Biểu đồ cột độ trễ admission (Bảng 5.6) |
| 12 | 13:40 | Truy vết hai chiều | Pod → digest → tag `sha-<commit>-run-<id>-<attempt>` → chữ ký → run, SBOM, commit · Không cần cơ sở dữ liệu riêng | **Hình 3.2** |
| 13 | 14:00 | Phát hiện khi chạy thật | Extension không xác thực được token Kyverno 1.19 và **ghi token vào log** → vá · Claim OIDC thực tế khác mẫu tài liệu · Repo public làm lộ account ID → che · "Image ID" khác nghĩa tùy image store | 4 ý, mỗi ý 1 dòng |
| 14 | 14:20 | Giới hạn | ECR ký **mọi** image push vào repo → niềm tin dựa vào phân quyền · Chữ ký ≠ nội dung lành tính · SBOM chưa được ký · Admission không gỡ Pod đã chạy | — |
| 15 | 14:40 | Kết luận và hướng phát triển | Trả lời câu hỏi nghiên cứu: **có** · Ưu tiên: ký attestation kết quả quét + kiểm ở admission · EKS + IRSA, GitOps, quét lại định kỳ từ SBOM | — |
| 16 | 15:00 | Cảm ơn — Hỏi đáp | Link repo `github.com/duy1504/devsecops-project` · Bằng chứng: `docs/evidence/` | Mã QR tới repo (tùy chọn) |

## Gợi ý trình bày

- **Một ý chính một slide.** Tiêu đề slide là một câu kết luận (như cột "Tiêu đề"), không phải tên chủ đề.
- **Số liệu phải khớp báo cáo.** Mọi con số trên slide lấy từ Chương 5, không làm tròn khác đi.
- **Không hiển thị account ID.** Ảnh chụp ECR/AWS console phải che account ID; `demo.sh` đã tự che trên terminal.
- **Slide dự phòng** (để sau slide 16, chỉ mở khi được hỏi):
  - TC09 fail-closed: số liệu và bằng chứng;
  - ma trận quyền IAM;
  - bộ phiên bản đã chốt;
  - bảng "khó khăn và giải pháp" (Chương 4 mục 4.8).
