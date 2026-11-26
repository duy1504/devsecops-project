# Kết quả kiểm thử

Theo kế hoạch mục 12. Chỉ ghi số liệu từ lần chạy thật; bằng chứng chọn lọc nằm trong `docs/evidence/`. Thư mục bằng chứng đặt tên theo thời điểm **UTC**; giờ Việt Nam = UTC+7.

**Cập nhật:** 26/11/2026 (chiều). ECR, Managed Signing, Policy 2 và job `publish` (OIDC) đã chạy với AWS thật; **TC01 đạt trọn luồng** từ commit trên `main` tới Pod.

## 1. Tổng hợp

| Ca | Tình huống | Lớp kiểm soát | Kết luận | Bằng chứng |
|---|---|---|---|---|
| TC01 | Luồng hợp lệ end-to-end | CI + admission | **Đạt** (trọn luồng): run 45798939183 trên `main` → `publish` push + ký `COMPLETE` → `deploy.sh` → Policy 1 + Policy 2 nhận, 2 Pod `Running` đúng digest | `evidence/tc01-e2e/20261126T101455Z/` (phần admission riêng: `evidence/spike/policy2-kind/20261126T081955Z/`) |
| TC02 | Secret giả trong mã | Gitleaks (CI) | **Đạt** | `evidence/TC02/20261117T171512Z/` |
| TC03 | Image có CVE Critical | Trivy gate (CI) | **Đạt** | `evidence/TC03/20261117T172037Z/` |
| TC04 | Image chưa ký | Admission (Policy 2) | **Đạt** | `evidence/spike/policy2-kind/20261126T081955Z/` |
| TC05 | Image sai nguồn | Admission (Policy 1) | **Đạt** (ECR thật, 26/11) | `evidence/policy1-real-ecr/20261126T081845Z/` |
| TC06 | Sai người ký | Admission (trust identity) | **Đạt** | `evidence/spike/policy2-kind/20261126T081955Z/` |
| TC07 | Tag thay digest | Admission (Policy 1) | **Đạt** (ECR thật) | `evidence/policy1-real-ecr/20261126T081845Z/` |
| TC08 | Init container vi phạm | Admission (Policy 1 + 2) | **Đạt** (ECR thật; Policy 2 cũng xác minh image init container) | `evidence/policy1-real-ecr/20261126T081845Z/` |
| TC09 | Verifier không khả dụng | Fail-closed | **Đạt** | `evidence/spike/policy2-kind/20261126T081955Z/` |
| TC10 | Deployer vượt quyền | RBAC | **Đạt** trên kind (impersonation; 26/11 thêm yêu cầu thật tới Pod đang chạy: 6/6 Forbidden) | `evidence/TC10/` |
| — | Push thẳng vào `main` | Branch protection | **Đạt** | `evidence/github/20261117T170531Z/` |
| — | `notation verify` (CLI) | Trust policy Notation | **Đạt**: signed pass, unsigned/wrong-signer fail, đối chứng tin profile B pass | `evidence/spike/verify-signed/` |

Lần chạy 17/11 của TC05/07/08 dùng `ECR_IMAGE` giả `111122223333` (`evidence/policy1/`), giữ lại để so sánh.

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

**Chạy lại với ECR thật (2026-11-26 08:18:45 UTC, `scripts/test-policy1-cluster.sh`, `APP_DIGEST` = `D_signed`):** 6/6 đúng, cùng lúc Policy 2 đang bật. TC05 (223 ms), TC07 (833 ms), TC08 (1590 ms) đều deny, stderr có `Policy allowed-image failed`, đối chứng (dry-run server) và namespace ngoài phạm vi cho qua, Deployment vi phạm bị chặn khi apply. Kết luận: **Đạt**.

### TC01, TC04, TC06, TC09 — Policy 2 (chữ ký AWS Signer) trên kind

| Trường | Nội dung |
|---|---|
| Thời gian | 2026-11-26 08:19:55 UTC (`scripts/test-policy2-cluster.sh`); lượt trước 08:18:01 UTC cũng 6/6 |
| Môi trường | kind v1.35.8; Kyverno 1.19.2; `ClusterPolicy/verify-signer` (`failurePolicy: Fail`, chỉ `app`/`demo`); extension `local/kyverno-notation-aws:58b210b-p2`; TrustPolicy `tp-supply-chain` (strict, chỉ tin `podinfo_signing_profile`); credential role `devsecops-verifier` (chỉ đọc ECR `podinfo` + `signer:GetRevocationStatus`, phiên 1 giờ) |
| Input | `D_signed` `sha256:59c79d67…6d0035` (Managed Signing), `D_unsigned` `sha256:85b97e84…cdf6f`, `D_wrongsigner` `sha256:6452d187…82e75` (ký tay bằng profile B); manifest `tests/admission/tc0{1,4,6}-*.template.yaml` |
| TC01 | `kubectl create` exit 0 (1569 ms); Pod `Running`, imageID đúng `D_signed` (kubelet pull bằng Secret `ecr-pull`) |
| TC04 | exit 1 (1180 ms); stderr `verify-signer` … `no signature is associated with "<ECR>/podinfo@sha256:85b97e84…"` |
| TC06 | exit 1 (1225 ms); stderr `trusted identify verification by plugin "com.amazonaws.signer.notation.plugin" failed with reason "Signature publisher doesn't match any trusted identities."` |
| TC09 | Scale extension về 0 → tạo lại Pod hợp lệ: exit 1 (405 ms), `dial tcp …:443: connect: connection refused`. Scale lại 1 → Pod hợp lệ được nhận (1607 ms) |
| Event | `PolicyViolation` trên `ClusterPolicy/verify-signer`: `Pod demo/tc04-unsigned: [verify-aws-signer] error (blocked)`, tương tự TC06 và TC09 |
| Log | Extension: `Token is authorized: user="system:serviceaccount:kyverno:kyverno-admission-controller"` (10 lần), `Verfication failed no signature is associated …`, `failed with reason "Signature publisher doesn't match …"` |
| Kết luận | **Đạt** cả 4 ca. Ghi chú: extension trả HTTP 406 khi xác minh thất bại nên Kyverno xếp là `error (blocked)` thay vì `fail`; kết quả chặn như nhau |

Policy 2 dùng `imageReferences: ["*"]` nên cũng xác minh image ngoài ECR: với TC05 (ghcr.io) và TC08 (busybox) extension báo `has no applicable trust policy statement` → hai lớp cùng chặn.

### TC01 — Trọn luồng: commit → CI → ECR + chữ ký → admission → Pod

| Trường | Nội dung |
|---|---|
| Thời gian | Run 45798939183/1 (merge PR #16, commit `d1cd8dd72cd8`): `verify` 10:11:11–10:12:36, `policy-test` 10:11:11–10:11:22, `publish` 10:12:38–10:13:23 UTC; triển khai 10:15:01 UTC |
| Môi trường | GitHub Actions `ubuntu-24.04`; role `devsecops-publisher` qua OIDC (trust `sub` = `…:ref:refs/heads/main`, dạng immutable subject); ECR `podinfo` + Managed Signing; kind như ca Policy 2 ở trên; `scripts/deploy.sh` chạy dưới danh tính deployer (impersonate group `devsecops-deployers`) |
| Input | Commit trên `main`; artifact `approved-image-45798939183-1` (`image.tar` của job `verify`, image ID `sha256:242fd799…b48e`) |
| Các bước & kết quả | `publish`: `sha256sum -c` + `verification.json` khớp commit/run/attempt + image ID khớp → push tag `sha-d1cd8dd72cd8-run-45798939183-1` → digest `sha256:8d0b9dd6a7e794df46671cc9b9c8f99c5f9e0d1265685eede11e20761c74a2f3` (digest registry = digest push) → `wait-signature.sh`: `Signed by expected profile after ~5s` → `release.json`. Máy lab: `fetch-release.sh` (chỉ run push `main` thành công) → `deploy.sh`: kiểm `release.json`↔`run.json`, tag trên ECR, ký `COMPLETE` → dry-run server → apply → rollout 2/2 |
| Bằng chứng admission | Extension: `"verified": true` cho đúng digest lúc 10:15:05; event `SuccessfulCreate` ×2, `Pulled` đúng digest; không có `FailedCreate` |
| Runtime | 2 Pod: `spec.image` và `status.imageID` đều `…/podinfo@sha256:8d0b9dd6…`; `/healthz` `{"status":"OK"}`, `/version` = 6.17.0 / `fd3a834` (qua `services/proxy`, không port-forward) |
| Truy vết | Pod → digest `8d0b9dd6…` → `release.json` (run 45798939183, commit `d1cd8dd`, `local_image_id`, `image_tar_sha256`, `sbom_sha256`, `vulnerability_report_sha256`) → artifact `security-reports-45798939183-1` (SBOM, Trivy) → commit nguồn |
| Quyền tối thiểu | Publisher **không** có `signer:GetSigningProfile` mà ký vẫn `COMPLETE` → loại khỏi policy (mục 8.4) |
| Lộ thông tin | Log job `publish` (repo public): 0 lần xuất hiện account ID, 63 dòng bị GitHub che `***`; `release.json` trong artifact đã thay bằng `<ACCOUNT_ID>`; Gitleaks quét `docs/evidence/` sạch |
| Kết luận | **Đạt** |

### TC10 — RBAC deployer

| Trường | Nội dung |
|---|---|
| Thời gian | 2026-11-17 17:35:23 UTC |
| Cách chạy | `scripts/check-rbac.sh` với `--as=deployer --as-group=devsecops-deployers`, từ kubeconfig quản trị của kind |
| Thực tế | `auth can-i`: 14/14 đúng (chỉ `patch deployments -n app` là `yes`). Yêu cầu thật: 4/4 `Forbidden` (đọc Secret, xóa `allowed-image`, tạo namespace, tạo Pod trực tiếp) |
| Bổ sung 26/11 (Pod thật) | Sau TC01, `app` có 2 Pod podinfo chạy image đã ký. Yêu cầu thật bằng danh tính deployer: `exec`, `debug` (ephemeral container), `port-forward`, `attach`, `delete pod`, `get secret` → **6/6 Forbidden**, đúng động từ (`create pods/exec`, `patch pods/ephemeralcontainers`, `create pods/portforward`, …); `logs`, `get pods` → được phép (2/2). Bằng chứng `evidence/TC10/20261126T*/` |
| Kết luận | **Đạt** trên kind. Deployer triển khai được (TC01) nhưng không vào được container, không đọc Secret, không xóa Pod |

### Branch protection `main`

| Trường | Nội dung |
|---|---|
| Cấu hình (qua API) | Bắt PR, 0 approval, required `verify` + `policy-test`, `strict` = true, `enforce_admins` = true, cấm force push và xóa nhánh. Secret scanning + push protection bật |
| Thử | Push commit rỗng thẳng vào `main` |
| Thực tế | `GH006: Protected branch update failed … Changes must be made through a pull request … 2 of 2 required status checks are expected`, exit 1; `main` trên GitHub không đổi |
| Kết luận | **Đạt** |

## 3. Chỉ số

### Thời gian CI (17–26/11/2026)

Nguồn: `scripts/ci-metrics.sh` (đã mở rộng cho job `publish`), dữ liệu `evidence/ci-metrics/ci-metrics-20261126.txt` (bản 18/11: `ci-metrics-20261118.txt`). Chỉ tính job thành công. Độ phân giải 1 giây (timestamp của GitHub).

| Job / bước | n | min (s) | trung bình (s) | max (s) |
|---|---|---|---|---|
| **Job `verify`** | 35 | 82 | 105,5 | 235 |
| Unit test | 35 | 3 | 6,4 | 90 |
| Gitleaks (toàn lịch sử) | 35 | 0 | 0,7 | 2 |
| Build (một lần) | 35 | 29 | 37,4 | 86 |
| SBOM (Syft) | 35 | 0 | 1,1 | 2 |
| Trivy scan | 35 | 4 | 5,8 | 11 |
| Gate Critical | 35 | 0 | 0,0 | 0 |
| **Job `policy-test`** | 39 | 6 | 9,6 | 15 |
| **Job `publish`** | 3 | 31 | 38,3 | 45 |
| Tải `approved-image` | 3 | 1 | 2,0 | 3 |
| Kiểm checksum + `docker load` | 3 | 0 | 1,3 | 2 |
| Push lên ECR | 3 | 17 | 19,0 | 22 |
| Chờ ký (`wait-signature.sh`, poll 5 s) | 3 | 1 | 5,7 | 8 |
| `release.json` | 3 | 0 | 0,0 | 0 |

Max của job `verify` (235 s) và unit test (90 s) thuộc run đầu tiên (44024593626), khi cache Go của `setup-go` chưa tồn tại. Max của build (86 s) thuộc run 44028249982. Run TC03 fail ở gate sau 85 s; run TC02 fail ở Gitleaks sau 29 s, không tốn thời gian build/scan. Từ lúc run bắt đầu tới image đã ký trên ECR: 2 phút 14 giây ở run 45798939183 (tạo run 10:11:09, `publish` xong 10:13:23 UTC; `verify` và `publish` nối tiếp). Phần lớn thời gian `publish` là push layer; phần bảo mật thêm vào (kiểm checksum, đối chiếu image ID, chờ ký) chỉ vài giây.

### Độ trễ ký của ECR Managed Signing

Nguồn: `scripts/signing-latency.sh`, dữ liệu `evidence/signing-latency/20261126T103608Z/latency.csv`. Đo bằng mốc của ECR — `imagePushedAt` của artifact chữ ký trừ `imagePushedAt` của image (độ phân giải ms) — nên **không** phụ thuộc chu kỳ poll 5 s của `wait-signature.sh`.

| Image | Push lên ECR (UTC) | Chữ ký có trên ECR sau |
|---|---|---|
| `signed-baseline` (spike, 20/11) | 10:41:59.701 | 2164 ms |
| `sha-d1cd8dd72cd8-run-45798939183-1` | 10:13:11.582 | 2509 ms |
| `sha-25847499904f-run-45800377707-1` | 10:22:38.467 | 2454 ms |
| `sha-debc8f30999c-run-45801990148-1` | 10:32:41.206 | 1735 ms |

Managed Signing (profile chính): **n = 4, min 1735 ms, trung bình 2216 ms, max 2509 ms**. Mỗi image có đúng 1 chữ ký, của `podinfo_signing_profile/gwTPmh8tPO`; `signingTime` trong chữ ký nằm giữa hai mốc. Bảng không tính `wrong-signer-baseline` (13 338 ms): đó là thời gian ký tay bằng `notation sign` khi tạo fixture, không phải độ trễ của Managed Signing. Bước chờ ký trong CI (1–8 s) lớn hơn do gồm chu kỳ poll.

### Độ trễ admission (Policy 1, 3 lượt)

Đo thời gian end-to-end của lệnh `kubectl` (gồm khởi động client), nên chỉ dùng để so sánh tương đối. `out-of-scope-ns` không đi qua webhook policy, dùng làm mốc.

| Yêu cầu | Kết quả | ms (3 lượt) |
|---|---|---|
| TC05 sai nguồn | deny | 206, 252, 317 |
| TC07 tag thay digest | deny | 193, 195, 252 |
| TC08 init container | deny | 196, 209, 269 |
| Đối chứng (dry-run server) | allow | 193, 199, 253 |
| Namespace ngoài phạm vi (mốc) | allow | 155, 185, 244 |

### Độ trễ admission có Policy 2 (4 lượt, 26/11)

Mỗi yêu cầu hợp lệ phải qua cả Policy 1 và Policy 2; Policy 2 gọi extension → ECR (manifest, referrer, chữ ký) → AWS Signer (thu hồi). Cache kết quả của extension đang **tắt** (`--cacheEnabled=false`), nên mọi lần đều là "lần đầu" — không đo được chênh lệch có/không cache như mục 12.5 gợi ý. Đo end-to-end lệnh `kubectl create` như bảng Policy 1. Bốn lượt (08:18, 08:19, 10:32, 10:33 UTC) đều 6/6 đúng mong đợi; bằng chứng `evidence/spike/policy2-kind/`.

| Yêu cầu | Kết quả | ms (4 lượt) | min | trung bình | max |
|---|---|---|---|---|---|
| TC01 signed (tạo thật) | allow | 2167, 1569, 1879, 1799 | 1569 | 1854 | 2167 |
| TC04 unsigned | deny | 587, 1180, 607, 686 | 587 | 765 | 1180 |
| TC06 wrong-signer | deny | 1269, 1225, 1028, 1143 | 1028 | 1166 | 1269 |
| TC09 extension tắt | deny | 210, 405, 249, 298 | 210 | 291 | 405 |
| TC09 bật lại, signed | allow | 2283, 1607, 2594, 2589 | 1607 | 2268 | 2594 |

So với Policy 1 (~200–300 ms), xác minh chữ ký thêm khoảng 1,5–2 s cho Pod hợp lệ. Ca bị từ chối nhanh hơn ca hợp lệ. Giải thích khả dĩ theo thứ tự xác minh của Notation (**chưa đo từng bước**): TC04 dừng ngay khi không tìm thấy chữ ký; TC06 phải tải và kiểm chữ ký rồi mới so danh tính; ca hợp lệ còn kiểm thu hồi qua AWS Signer. TC09 khi extension tắt bị chặn sau ~0,3 s (kết nối bị từ chối), không phải chờ timeout 30 s.

### Truy vết (TC01, run 45798939183)

| Mắt xích | Liên kết bằng | Tự động / thủ công |
|---|---|---|
| Commit → run | `commit_sha`, `workflow_run_id`, `run_attempt` trong `verification.json`/`release.json` | Tự động (GitHub Actions) |
| Run → artifact đã scan | `image_tar_sha256`, `local_image_id`; `sbom_sha256`, `vulnerability_report_sha256` trỏ vào artifact `security-reports-<run>-<attempt>` | Tự động (`verify`) |
| Artifact → image trên ECR | `publish` kiểm checksum + image ID trước khi push; digest registry = digest push | Tự động (`publish`) |
| Image → chữ ký | `wait-signature.sh` đòi `COMPLETE` đúng profile; `release.json` ghi profile | Tự động (Managed Signing + `publish`) |
| `release.json` → Pod | `fetch-release.sh` (chỉ run push `main` thành công) → `deploy.sh` render digest | **Thủ công** (chạy 2 lệnh trên máy có cụm kind; không có job `deploy`) |
| Pod → digest | `spec.image` và `status.imageID` = digest phát hành; extension log `"verified": true` cho đúng digest | Kiểm tự động trong `deploy.sh` |

Chiều ngược (từ Pod đang chạy về commit): đọc digest của Pod → tìm tag `sha-<commit12>-run-<id>-<attempt>` trên ECR (`aws ecr describe-images --image-ids imageDigest=…`) → run và commit nằm ngay trong tag; SBOM và báo cáo CVE lấy từ artifact của run đó.

### SBOM và lỗ hổng của image thật (podinfo 6.17.0)

| Chỉ số | Giá trị |
|---|---|
| SBOM | CycloneDX (spec 1.7), 1032 component (76 `pkg:golang/*`), 349 409 byte (run 45801990148) |
| Trivy (máy, DB 2026-11-16; CI, DB 2026-11-17) | Critical 0, High 2 (`go-jose/v4` 4.1.5, `x/net` 0.61.0 — đều có bản vá), Medium 1, Unknown 4 |
| Trivy 0.76.2, CI run 45801990148 (DB 2026-11-26T07:04Z) | **Không đổi:** Critical 0, High 2 (CVE-2026-116587 `go-jose/v4` 4.1.5 → 4.1.6; CVE-2026-78661 `x/net` 0.61.0 → 0.62.0), Medium 1, Unknown 4; Gitleaks 0 finding. Bằng chứng `evidence/ci-reports/45801990148/` |

Hai lỗ hổng High đến từ mã upstream podinfo 6.17.0 và đều có bản vá; đồ án giữ nguyên upstream để số liệu phản ánh workload thật (gate chỉ chặn Critical theo đề cương, mục 9.2). Trong 9 ngày (DB 16/11 → 26/11) không phát sinh CVE mới cho image này.

## 4. Vấn đề phát hiện nhờ thực nghiệm

1. **Gitleaks quét lây sang nhánh khác.** Lần chạy TC03 đầu tiên (PR #3, run 44134407592) fail ở Gitleaks thay vì gate. Nguyên nhân: `actions/checkout` với `fetch-depth: 0` tải mọi nhánh, còn `gitleaks git` mặc định quét mọi ref, nên bắt commit `ce1c904` của nhánh TC02. Hệ quả: một nhánh bất kỳ có secret làm fail mọi PR. Đã sửa bằng `--log-opts=HEAD` (PR #5): kiểm tra local cho thấy nhánh sạch về 0 finding, nhánh có secret vẫn 1 finding. Lần chạy này không được tính là bằng chứng TC03.
2. **Allowlist Gitleaks toàn cục bỏ qua cả file.** Khi xử lý 3 dương tính giả trong mã podinfo upstream, allowlist toàn cục với `paths` + điều kiện AND vẫn bỏ qua mọi secret khác trong cùng file. Chuyển sang allowlist cấp rule và kiểm chứng bằng secret thử nghiệm.
3. **`.gitignore` chặn nhầm mã nguồn.** Mẫu `*token*` (để chặn file token thật) đã bỏ qua 7 file `token*.go`/`token.proto` của podinfo, khiến CI sẽ build thiếu code. Thêm ngoại lệ cho `app/`.
4. **Extension `kyverno-notation-aws` bản phát hành có 6 Critical.** Xem `docs/versions.md` mục 2b; đồ án tự build từ `main` có ghim commit.
5. **Extension không xác thực được token của Kyverno 1.19.** Lần chạy đầu mọi Pod (kể cả hợp lệ) bị chặn với `HTTP 406 Not Acceptable: Token is not authorized` — fail-closed nên an toàn, nhưng hệ thống không dùng được. Log cho thấy token Kyverno có audience `kyverno-svc.kyverno.io` còn TokenReview của thư viện verifier không khai báo audience. Sửa bằng bản vá p2 (`TOKEN_REVIEW_AUDIENCES`), **không** tắt `--reviewKyvernoToken`.
6. **Extension ghi bearer token của Kyverno vào log.** Thư viện verifier v1.1.0 in nguyên đối tượng TokenReview (gồm token) ở mức INFO. Bản vá p2 chỉ ghi tên user; script thu bằng chứng vẫn lọc chuỗi dạng JWT.
7. **Mẫu policy upstream cần quyền đọc Secret chứa private key.** Mẫu lấy `caBundle` bằng cách để Kyverno đọc Secret TLS của extension. Đồ án nhúng chứng chỉ CA công khai lúc render, nên Kyverno không cần thêm quyền.
8. **`envsubst` thay cả biến trong chú thích.** Chú thích nhắc `${EXT_CA_BUNDLE}` bị thay bằng PEM, làm hỏng YAML. Đổi cách viết chú thích.
9. **Ổ C: đầy khi build lại extension** (26/11): `Bus error` ở `docker run`; còn khoảng 7 GB sau build. Ổ đĩa ảo của Docker Desktop chỉ tăng, không tự co lại.
10. **Claim `sub` OIDC khác mẫu trong tài liệu.** Repo bật *immutable subject claims* nên `sub` là `repo:duy1504@210903593/devsecops-project@1460578199:ref:refs/heads/main`, không phải `repo:<OWNER>/<REPO>:ref:…`. Trust policy viết theo mẫu sẽ luôn bị từ chối `AssumeRoleWithWebIdentity`. Kiểm bằng `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` trước khi tạo role.
11. **Repo public làm lộ account ID qua log và artifact.** GitHub Variables không được che trong log. Đặt account ID ở Secret (GitHub tự che mọi chuỗi chứa nó), ghép ARN trong job, và thay bằng `<ACCOUNT_ID>` trong `release.json` trước khi upload artifact.
12. **Script kiểm lộ account ID chạy với biến rỗng.** Hai lần lấy account ID thất bại âm thầm (Git Bash tự đổi đường dẫn `/mnt/c/...`; WSL thiếu `~/.local/bin` trong `PATH`), `grep ""` khớp mọi dòng nên báo "có lộ" ở mọi file — báo động giả, nhưng cùng lỗi này ở một phép kiểm dạng "đếm = 0 thì đạt" hoặc ở bước `sed` che sẽ cho kết quả sai. Hai kết quả đó bị loại; script kiểm và job `publish` đều bắt buộc account ID khớp `^[0-9]{12}$` trước khi dùng.
13. **"Image ID" mang nghĩa khác nhau tùy image store.** Docker 29 (containerd store) báo image ID của extension là `f2d19986…` = digest **OCI index**, còn containerd trên node kind báo `d3c72d96…` = digest **config** (qua manifest amd64 `1dd83a60…`); `imageID` của Pod lại là index `import-…` do `kind load` tạo. Lần kiểm đầu so nhầm hai loại và báo sai; đã lần chuỗi index → manifest → config trong `docker save` rồi sửa `preflight.sh` so config. Bổ sung cho lưu ý "không nhầm 3 loại SHA" ở mục 9.6 kế hoạch: trên runner CI (`docker save`/`load`) cả hai job dùng cùng loại store nên phép so image ID trong `publish` vẫn đúng.
