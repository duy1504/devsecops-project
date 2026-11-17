# Kết quả kiểm thử

Theo kế hoạch mục 12. Chỉ ghi số liệu từ lần chạy thật; bằng chứng chọn lọc nằm trong `docs/evidence/`. Thư mục bằng chứng đặt tên theo thời điểm **UTC**; giờ Việt Nam = UTC+7.

**Cập nhật:** 18/11/2026. **Trạng thái AWS:** chưa có, nên ECR, Managed Signing và Policy 2 chưa chạy.

## 1. Tổng hợp

| Ca | Tình huống | Lớp kiểm soát | Kết luận | Bằng chứng |
|---|---|---|---|---|
| TC01 | Luồng hợp lệ end-to-end | CI + admission | **Chưa thực hiện** (cần ECR, Managed Signing) | — |
| TC02 | Secret giả trong mã | Gitleaks (CI) | **Đạt** | `evidence/TC02/20261117T171512Z/` |
| TC03 | Image có CVE Critical | Trivy gate (CI) | **Đạt** | `evidence/TC03/20261117T172037Z/` |
| TC04 | Image chưa ký | Admission (chữ ký) | **Chưa thực hiện** (cần spike) | — |
| TC05 | Image sai nguồn | Admission (Policy 1) | **Đạt một phần**: logic đạt trên kind với `ECR_IMAGE` giả; chạy lại với ECR thật | `evidence/policy1/` |
| TC06 | Sai người ký | Admission (trust identity) | **Chưa thực hiện** (cần spike) | — |
| TC07 | Tag thay digest | Admission (Policy 1) | **Đạt một phần** (như TC05) | `evidence/policy1/` |
| TC08 | Init container vi phạm | Admission (Policy 1) | **Đạt một phần** cho phần nguồn ảnh; phần chữ ký cần Policy 2 | `evidence/policy1/` |
| TC09 | Verifier không khả dụng | Fail-closed | **Chưa thực hiện** (cần extension + AWS) | — |
| TC10 | Deployer vượt quyền | RBAC | **Đạt** trên kind (impersonation) | `evidence/TC10/` |
| — | Push thẳng vào `main` | Branch protection | **Đạt** | `evidence/github/20261117T170531Z/` |

"Đạt một phần" nghĩa là logic policy đã được chứng minh trên cụm thật, nhưng `ECR_IMAGE` còn là account ví dụ `111122223333`. Chỉ ghi "Đạt" sau khi chạy lại với registry thật.

## 2. Chi tiết từng ca

### TC02 — Secret giả trong mã nguồn

| Trường | Nội dung |
|---|---|
| Thời gian | Run tạo 2026-11-17 17:12:37 UTC; job `verify` 17:12:40 → 17:13:09 UTC (29 s) |
| Commit, run | PR #4, head `ce1c904` (nhánh `demo/leak-secret`, đã xóa); run [44134429165](https://github.com/duy1504/devsecops-project/actions/runs/44134429165) |
| Input | File `demo/leak.env.example` chứa `DEMO_SECRET_` + 32 hex sinh ngẫu nhiên (chuỗi giả, khớp rule lab `demo-secret` trong `.gitleaks.toml`) |
| Điều kiện trước | Gitleaks 8.30.1 (binary ghim SHA-256), `--redact`, `--log-opts=HEAD` chưa có ở lần chạy này (xem mục 4) |
| Mong đợi | `verify` fail ở bước Gitleaks; PR không merge được; không có artifact phát hành |
| Thực tế | `leaks found: 1`, rule `demo-secret`, file `demo/leak.env.example` dòng 1, giá trị `REDACTED`; bước Gitleaks **exit 1**; các bước build/SBOM/scan bị skip; PR `mergeStateStatus = BLOCKED`. GitHub Push Protection **không** chặn khi push (chuỗi `DEMO_SECRET_` không thuộc mẫu của nhà cung cấp nào) → lớp chặn đúng là Gitleaks |
| Kết luận | **Đạt.** PR đã đóng, nhánh đã xóa, chuỗi giả không vào `main` |

### TC03 — Image có CVE Critical

| Trường | Nội dung |
|---|---|
| Thời gian | Run tạo 2026-11-17 17:18:33 UTC; job `verify` 17:18:36 → 17:20:01 UTC (85 s) |
| Commit, run | PR #6, head `68c4cfe` (nhánh `demo/critical-cve`, đã xóa); run [44135534522](https://github.com/duy1504/devsecops-project/actions/runs/44135534522) |
| Input | `Dockerfile` thay bằng `demo/Dockerfile.vulnerable`: build podinfo giống bản thật, runtime `alpine:3.14.0@sha256:adab3844…be67c96` |
| Chọn fixture | Từ scan thật trên máy (Trivy 0.76.2, DB 2026-11-16 18:50 UTC): `alpine:3.14.0` 4 Critical, `alpine:3.16.0` 1, `debian:11.0-slim` 22. Chọn 3.14.0 vì nhỏ và có 4 Critical ở 3 gói (còn dư khi DB thay đổi) |
| Điều kiện trước | Trivy 0.76.2, DB `UpdatedAt` 2026-11-17 13:00:16 UTC; gate không dùng `--ignore-unfixed`; Gitleaks đã sửa phạm vi (`--log-opts=HEAD`) |
| Mong đợi | Gitleaks sạch; build, SBOM, scan chạy đủ; gate fail; không có artifact `approved-image-*` |
| Thực tế | Bước `GATE – no CRITICAL` in `Critical vulnerabilities: 4` → **exit 1**. OS alpine 3.14.0 (EOSL). CVE: CVE-2021-36159 `apk-tools` 2.12.5-r1 → 2.12.6-r0; CVE-2021-3711 `libcrypto1.1`, `libssl1.1` 1.1.1k-r0 → 1.1.1l-r0; CVE-2022-37434 `zlib` 1.2.11-r3 → 1.2.12-r2. PR `BLOCKED`. Artifact của run: chỉ `security-reports-…` và bản ghi build, **không** có `approved-image-*` |
| Ghi chú | Check `Trivy` của Code Scanning vẫn "pass" ở run này → nó không phải gate, đúng lý do không đặt làm required check |
| Kết luận | **Đạt.** PR đã đóng, nhánh đã xóa |

### TC05, TC07, TC08 — Policy 1 trên kind

| Trường | Nội dung |
|---|---|
| Thời gian | 3 lượt: 2026-11-17 17:34:33, 17:34:50, 17:35:07 UTC |
| Môi trường | kind, Kubernetes v1.35.8; Kyverno v1.19.2 (chart 3.9.2); `ValidatingPolicy/allowed-image` (`policies.kyverno.io/v1`), webhook `vpol.validate.kyverno.svc-fail` |
| Input | `ECR_IMAGE` = `111122223333.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo` (**giả**); manifest trong `tests/admission/`; TC05 dùng podinfo upstream `ghcr.io/stefanprodan/podinfo@sha256:fa2f27c1…ddefb0` (digest thật) |
| Mong đợi | TC05, TC07, TC08 và Deployment vi phạm bị từ chối **do policy `allowed-image`**; đối chứng đúng repo + digest và namespace ngoài phạm vi được cho qua |
| Thực tế | Cả 3 lượt 6/6 đúng. Mỗi lần deny có `exit=1` và stderr `Policy allowed-image failed: Image phải thuộc … sha256 digest (64 ký tự hex).` Event `PolicyViolation … fail (blocked)` gắn trên `ValidatingPolicy/allowed-image` (namespace `default`). Deployment vi phạm bị chặn ngay khi apply (autogen), không có `FailedCreate` |
| Kết luận | **Đạt một phần** (logic đạt; cần chạy lại với `ECR_IMAGE` thật). TC08 mới kiểm nguồn ảnh của init container; phần chữ ký của init container thuộc Policy 2 |

Test offline (`scripts/policy-test.sh`, Kyverno CLI v1.19.2): 6/6 ca, chạy trong job `policy-test` ở mọi run. Ca đảo kỳ vọng (cho `tc-ok` phải fail) đã thử và test báo fail đúng.

### TC10 — RBAC deployer

| Trường | Nội dung |
|---|---|
| Thời gian | 2026-11-17 17:35:23 UTC |
| Cách chạy | `scripts/check-rbac.sh` với `--as=deployer --as-group=devsecops-deployers`, từ kubeconfig quản trị của kind |
| Thực tế | `auth can-i`: 14/14 đúng (chỉ `patch deployments -n app` là `yes`). Yêu cầu thật: 4/4 `Forbidden` (đọc Secret, xóa `allowed-image`, tạo namespace, tạo Pod trực tiếp) |
| Kết luận | **Đạt** trên kind. Chưa thử `exec` thật vì `app` chưa có Pod chạy image hợp lệ (cần ECR) |

### Branch protection `main`

| Trường | Nội dung |
|---|---|
| Cấu hình (qua API) | Bắt PR, 0 approval, required `verify` + `policy-test`, `strict` = true, `enforce_admins` = true, cấm force push và xóa nhánh. Secret scanning + push protection bật |
| Thử | Push commit rỗng thẳng vào `main` |
| Thực tế | `GH006: Protected branch update failed … Changes must be made through a pull request … 2 of 2 required status checks are expected`, exit 1; `main` trên GitHub không đổi |
| Kết luận | **Đạt** |

## 3. Chỉ số

### Thời gian CI (job `verify`, 13 run thành công, 17–18/11/2026)

Nguồn: `scripts/ci-metrics.sh`, dữ liệu `evidence/ci-metrics/ci-metrics-20261118.txt`. Độ phân giải 1 giây (timestamp của GitHub).

| Bước | min (s) | trung bình (s) | max (s) |
|---|---|---|---|
| Cả job `verify` | 84 | 117,6 | 235 |
| Unit test | 3 | 10,5 | 90 |
| Gitleaks (toàn lịch sử) | 0 | 0,6 | 2 |
| Build (một lần) | 29 | 43,5 | 86 |
| SBOM (Syft) | 0 | 1,1 | 2 |
| Trivy scan | 4 | 6,5 | 11 |
| Gate Critical | 0 | 0,0 | 0 |
| Job `policy-test` | 7 | 10,2 | 15 |

Max của job (235 s) và unit test (90 s) thuộc run đầu tiên (44024593626), khi cache Go của `setup-go` chưa tồn tại. Max của build (86 s) thuộc run 44028249982. Run TC03 fail ở gate sau 85 s; run TC02 fail ở Gitleaks sau 29 s, không tốn thời gian build/scan.

### Độ trễ admission (Policy 1, 3 lượt)

Đo thời gian end-to-end của lệnh `kubectl` (gồm khởi động client), nên chỉ dùng để so sánh tương đối. `out-of-scope-ns` không đi qua webhook policy, dùng làm mốc.

| Yêu cầu | Kết quả | ms (3 lượt) |
|---|---|---|
| TC05 sai nguồn | deny | 206, 252, 317 |
| TC07 tag thay digest | deny | 193, 195, 252 |
| TC08 init container | deny | 196, 209, 269 |
| Đối chứng (dry-run server) | allow | 193, 199, 253 |
| Namespace ngoài phạm vi (mốc) | allow | 155, 185, 244 |

### SBOM và lỗ hổng của image thật (podinfo 6.17.0)

| Chỉ số | Giá trị |
|---|---|
| SBOM | CycloneDX (spec 1.7), 1032 component, có `pkg:golang/*` |
| Trivy (máy, DB 2026-11-16; CI, DB 2026-11-17) | Critical 0, High 2 (`go-jose/v4` 4.1.5, `x/net` 0.61.0 — đều có bản vá), Medium 1, Unknown 4 |

## 4. Vấn đề phát hiện nhờ thực nghiệm

1. **Gitleaks quét lây sang nhánh khác.** Lần chạy TC03 đầu tiên (PR #3, run 44134407592) fail ở Gitleaks thay vì gate. Nguyên nhân: `actions/checkout` với `fetch-depth: 0` tải mọi nhánh, còn `gitleaks git` mặc định quét mọi ref, nên bắt commit `ce1c904` của nhánh TC02. Hệ quả: một nhánh bất kỳ có secret làm fail mọi PR. Đã sửa bằng `--log-opts=HEAD` (PR #5): kiểm tra local cho thấy nhánh sạch về 0 finding, nhánh có secret vẫn 1 finding. Lần chạy này không được tính là bằng chứng TC03.
2. **Allowlist Gitleaks toàn cục bỏ qua cả file.** Khi xử lý 3 dương tính giả trong mã podinfo upstream, allowlist toàn cục với `paths` + điều kiện AND vẫn bỏ qua mọi secret khác trong cùng file. Chuyển sang allowlist cấp rule và kiểm chứng bằng secret thử nghiệm.
3. **`.gitignore` chặn nhầm mã nguồn.** Mẫu `*token*` (để chặn file token thật) đã bỏ qua 7 file `token*.go`/`token.proto` của podinfo, khiến CI sẽ build thiếu code. Thêm ngoại lệ cho `app/`.
4. **Extension `kyverno-notation-aws` bản phát hành có 6 Critical.** Xem `docs/versions.md` mục 2b; đồ án tự build từ `main` có ghim commit.
