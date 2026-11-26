# Chương 5. Thực nghiệm và đánh giá (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15. Mọi số liệu lấy từ lần chạy thật, ghi trong `docs/test-results.md`; bằng chứng gốc nằm trong `docs/evidence/` (đã che account ID AWS). Thời gian ghi theo **UTC** (giờ Việt Nam = UTC+7). Trước khi nộp: thêm ảnh chụp GitHub Actions, ECR console và terminal vào các vị trí "Hình 5.x".

## 5.1. Mục tiêu và phương pháp thực nghiệm

Thực nghiệm trả lời câu hỏi nghiên cứu ở Chương 1: **phối hợp kiểm soát trong CI và tại Kubernetes admission có phát hiện hoặc ngăn được bốn tình huống — secret trong mã, image có CVE Critical, image chưa ký, image từ nguồn không được phép — đồng thời truy vết được từ Pod về digest, SBOM và commit không?**

Phương pháp:

- **Ma trận 10 ca kiểm thử** (TC01–TC10): TC01 là luồng hợp lệ; TC02–TC05 ứng với bốn tình huống trong đề cương; TC06–TC10 là ca mở rộng nhằm thử các đường vòng (sai người ký, dùng tag thay digest, giấu image trong init container, verifier ngừng hoạt động, deployer vượt quyền).
- **Mỗi ca xác định trước lớp phải chặn** và lý do mong đợi. Một ca chỉ "Đạt" khi bị chặn **đúng lớp, đúng nguyên nhân**. Ví dụ TC04 phải bị Policy 2 từ chối vì *không có chữ ký*, không phải vì sai nguồn hay lỗi kéo image.
- **Bằng chứng từ chối** gồm bốn phần: stderr + exit code của lệnh, event Kubernetes, log của thành phần ra quyết định, và tên policy. Đồ án **không** dùng PolicyReport (sinh bất đồng bộ) hay trạng thái `ImagePullBackOff` (lỗi kéo image không chứng minh admission đã chặn).
- **Có đối chứng.** Mỗi lượt thử admission đều kèm một yêu cầu hợp lệ phải được nhận, và một namespace ngoài phạm vi policy làm mốc. Fixture chữ ký được dựng sao cho chỉ khác đúng một yếu tố: cùng repository `podinfo`, khác trạng thái chữ ký (Bảng 5.2). Với `notation verify`, có thêm ca đối chứng "tạm tin profile B" để chứng minh TC06 bị chặn vì danh tính chứ không vì lý do khác.
- **Lặp lại** các phép đo độ trễ (Policy 1: 3 lượt; Policy 2: 4 lượt; CI: toàn bộ run thành công có trong lịch sử), ghi min/trung bình/max.

## 5.2. Môi trường thực nghiệm

### 5.2.1. Hạ tầng

| Thành phần | Cấu hình |
|---|---|
| Máy lab | Intel Core i7-1360P (12 nhân/16 luồng), RAM 16 GB, Windows 11; WSL2 Ubuntu 24.04; Docker Desktop (Engine 29.9.1) |
| Kubernetes | kind v0.33.0, một node, Kubernetes **v1.35.8** |
| Admission | Kyverno **v1.19.2** (Helm chart 3.9.2); extension `kyverno-notation-aws` tự build từ `main@58b210b` + bản vá p2 |
| CI | GitHub Actions, runner `ubuntu-24.04`, repo public `duy1504/devsecops-project` |
| AWS | Region `ap-southeast-1`; ECR repo `podinfo` (tag IMMUTABLE, mã hóa KMS); ECR Managed Signing (1 rule, filter đúng `podinfo`); AWS Signer platform `Notation-OCI-SHA384-ECDSA` |
| Danh tính AWS | `devsecops-publisher` (GitHub OIDC, chỉ nhánh `main`); `devsecops-verifier` (chỉ đọc ECR + kiểm thu hồi, cho extension trên kind); quản trị lab qua IAM Identity Center |
| Workload | podinfo 6.17.0 (Go), build từ source, image distroless chạy UID 65532 |

Bộ phiên bản đầy đủ (kèm SHA-256 của công cụ, digest của image nền và commit của GitHub Actions) được chốt ngày 26/11/2026 trong `docs/versions.md` mục 4. Trạng thái môi trường được kiểm bằng `scripts/preflight.sh` (33/33 mục đạt).

### 5.2.2. Bộ công cụ trong pipeline

| Công cụ | Phiên bản | Vai trò |
|---|---|---|
| Gitleaks | 8.30.1 | Quét secret toàn lịch sử của commit đang kiểm |
| Syft | 1.56.0 | Sinh SBOM CycloneDX từ `image.tar` |
| Trivy | 0.76.2 | Quét lỗ hổng một lần ra JSON; gate 0 Critical |
| Kyverno CLI | v1.19.2 | Kiểm thử policy offline (job `policy-test`) |
| Notation CLI + AWS Signer plugin | 1.3.2 + 1.0.2292 | Xác minh chữ ký thủ công (đối chiếu với admission) |

Công cụ CLI được cài bằng binary ghim phiên bản và SHA-256; GitHub Actions ghim theo commit SHA đầy đủ.

### 5.2.3. Dữ liệu kiểm thử (fixture)

Ba image dùng cho các ca chữ ký đều nằm trong **cùng repository** `podinfo`. Nhờ đó, khác biệt duy nhất giữa chúng là trạng thái chữ ký.

| Ký hiệu | Tag | Cách tạo | Số chữ ký |
|---|---|---|---|
| `D_unsigned` | `unsigned-baseline` | Push **trước** khi bật signing rule | 0 |
| `D_wrongsigner` | `wrong-signer-baseline` | Push trước khi bật rule, ký tay bằng **profile B** (`podinfo_wrong_signer`) — profile không nằm trong trust policy | 1 (profile B) |
| `D_signed` | `signed-baseline` | Push sau khi bật rule, Managed Signing tự ký | 1 (profile chính) |

*Bảng 5.2. Fixture cho TC01, TC04, TC06.*

Fixture không bao giờ được push lại hay gắn thêm tag: làm vậy sau khi bật signing rule sẽ khiến chúng bị ký thêm và hỏng đối chứng. Lifecycle policy chỉ chọn tag tiền tố `sha-`, nên không chạm tới fixture. Ngày 26/11, `preflight.sh` xác nhận số chữ ký vẫn là 0 / 1 (profile B) / 1.

Fixture cho TC03 là `demo/Dockerfile.vulnerable`. File này build podinfo như bản thật nhưng dùng runtime `alpine:3.14.0`. Base image được **chọn từ kết quả scan thật**, không đoán: `alpine:3.14.0` có 4 Critical, `alpine:3.16.0` có 1, `debian:11.0-slim` có 22. Fixture cho TC02 là một chuỗi giả `DEMO_SECRET_` + 32 ký tự hex, chỉ nằm trên nhánh demo và không bao giờ vào `main`.

## 5.3. Kết quả theo ca kiểm thử

### 5.3.1. Tổng hợp

| Ca | Tình huống | Lớp chặn mong đợi | Kết quả thực tế | Kết luận |
|---|---|---|---|---|
| TC01 | Luồng hợp lệ, commit → Pod | (không chặn) | Run 45798939183: `verify` → `publish` (push + ký `COMPLETE`) → `deploy.sh` → 2 Pod `Running` đúng digest | **Đạt** |
| TC02 | Secret trong mã | Gitleaks (CI) | Bước Gitleaks exit 1, rule `demo-secret`; build/scan bị bỏ qua; PR bị khóa | **Đạt** |
| TC03 | Image có CVE Critical | Trivy gate (CI) | Gate báo 4 Critical, exit 1; không có artifact `approved-image` | **Đạt** |
| TC04 | Image chưa ký | Policy 2 (admission) | exit 1, `no signature is associated with …` | **Đạt** |
| TC05 | Image sai nguồn | Policy 1 (admission) | exit 1, `Policy allowed-image failed` | **Đạt** |
| TC06 | Sai người ký | Policy 2 (trusted identity) | exit 1, `Signature publisher doesn't match any trusted identities.` | **Đạt** |
| TC07 | Tag thay cho digest | Policy 1 | exit 1, `Policy allowed-image failed` | **Đạt** |
| TC08 | Image vi phạm trong init container | Policy 1 (+ Policy 2) | exit 1; cả hai policy đều kiểm image của init container | **Đạt** |
| TC09 | Verifier ngừng hoạt động | Fail-closed | Pod **hợp lệ** cũng bị chặn (`connection refused`); bật lại → được nhận | **Đạt** |
| TC10 | Deployer vượt quyền | RBAC | `auth can-i` 14/14 đúng; yêu cầu thật 6/6 `Forbidden` | **Đạt** |
| — | Push thẳng vào `main` | Branch protection | `GH006: Protected branch update failed`, exit 1 | **Đạt** |
| — | Xác minh bằng Notation CLI | Trust policy Notation | signed pass; unsigned, wrong-signer fail; đối chứng tin profile B → pass | **Đạt** |

*Bảng 5.3. Kết quả ma trận kiểm thử (chi tiết từng ca: `docs/test-results.md` mục 2).*

Cả 10 ca và 2 kiểm tra bổ sung đều đạt, và mỗi ca bị chặn **đúng lớp, đúng nguyên nhân** đã định trước.

### 5.3.2. Lớp CI: TC02 và TC03

**TC02 (secret).** Nhánh demo chứa file có chuỗi giả `DEMO_SECRET_…` (PR #4, run 44134429165). Job `verify` dừng ngay ở bước Gitleaks sau 29 s với `leaks found: 1` (giá trị đã che `REDACTED`). Các bước build, SBOM và scan bị bỏ qua, và PR ở trạng thái `BLOCKED`. Một quan sát đáng chú ý: GitHub Push Protection **không** chặn chuỗi này lúc push, vì nó không thuộc mẫu secret của nhà cung cấp nào. Lớp chặn thực sự là Gitleaks với rule riêng của đồ án. Điều này cho thấy tính năng quét secret có sẵn của nền tảng không thay thế được gate trong pipeline.

**TC03 (CVE Critical).** PR #6 (run 44135534522) thay runtime bằng `alpine:3.14.0`. Gitleaks sạch; build, SBOM và scan chạy đủ; bước gate in `Critical vulnerabilities: 4` và trả exit 1. Các CVE gồm CVE-2021-36159 (`apk-tools`), CVE-2021-3711 (`libcrypto1.1`, `libssl1.1`) và CVE-2022-37434 (`zlib`). Run **không** sinh artifact `approved-image`, nên job `publish` không có gì để đẩy lên ECR. Check `Trivy` của Code Scanning vẫn "pass" ở run này: đó là kênh báo cáo, không phải gate. Vì vậy đồ án không đặt nó làm required check.

*(Hình 5.1: run TC02 dừng ở Gitleaks; Hình 5.2: run TC03 dừng ở gate.)*

### 5.3.3. Lớp admission — nguồn image: TC05, TC07, TC08

Policy 1 (`ValidatingPolicy` viết bằng CEL) chỉ cho phép image dạng `<registry ECR>/podinfo@sha256:<64 hex>` trong namespace `app` và `demo`. Lần chạy với ECR thật (26/11, 08:18:45 UTC, 6/6 đúng):

- **TC05:** image podinfo upstream `ghcr.io/stefanprodan/podinfo@sha256:…`. Image này dùng digest thật nhưng sai registry, và bị từ chối.
- **TC07:** đúng repository nhưng dùng tag thay cho digest, và bị từ chối.
- **TC08:** container chính hợp lệ, nhưng init container dùng `busybox`. Pod bị từ chối, cho thấy policy kiểm **mọi** container chứ không chỉ container chính.
- **Đối chứng:** image đúng repo + digest được nhận; namespace ngoài phạm vi được nhận.
- Deployment vi phạm bị chặn ngay khi `apply`. Nhờ cơ chế *autogen*, Kyverno áp policy lên cả template của Deployment, nên không phải chờ ReplicaSet báo `FailedCreate`.

Policy 2 đặt `imageReferences: ["*"]`, nên cũng xác minh chữ ký của image ngoài ECR. Với TC05 và TC08, extension báo thêm `has no applicable trust policy statement`, nghĩa là **hai lớp độc lập cùng chặn** một yêu cầu. Nếu Policy 1 bị cấu hình sai, Policy 2 vẫn từ chối image không có chữ ký tin cậy.

Policy 1 còn được kiểm offline bằng Kyverno CLI trong job `policy-test`, chạy ở mọi PR (6/6 ca, 39 run thành công). Ca "đảo kỳ vọng" đã được thử và test báo fail đúng, chứng tỏ bộ test có khả năng phát hiện sai.

### 5.3.4. Lớp admission — chữ ký: TC04, TC06 và đối chiếu Notation CLI

Policy 2 (`ClusterPolicy` `verify-signer`, `failurePolicy: Fail`) gửi danh sách image của Pod tới extension. Extension tải chữ ký Notation từ ECR (OCI referrer), kiểm tra theo TrustPolicy `tp-supply-chain`: mức `strict`, trust store là root CA của AWS Signer, `trustedIdentities` chỉ chứa ARN của profile chính.

| Ca | Image | Thông báo từ chối (trích stderr) |
|---|---|---|
| TC04 | `D_unsigned` | `no signature is associated with "<ECR>/podinfo@sha256:85b97e84…"` |
| TC06 | `D_wrongsigner` | `trusted identify verification by plugin "com.amazonaws.signer.notation.plugin" failed with reason "Signature publisher doesn't match any trusted identities."` |

Hai ca dùng cùng repository được phép, nên Policy 1 cho qua. Lý do từ chối đến đúng từ Policy 2, với hai nguyên nhân khác nhau: thiếu chữ ký, và chữ ký hợp lệ về mật mã nhưng của danh tính không được tin. Event `PolicyViolation` ghi nhận trên `ClusterPolicy/verify-signer`; log extension có dòng `Verfication failed …` tương ứng.

Kết quả admission **trùng khớp** với xác minh độc lập bằng Notation CLI trên máy lab (`scripts/notation-verify.sh`): `D_signed` pass; `D_unsigned` và `D_wrongsigner` fail đúng lý do. Ở ca đối chứng, khi tạm thêm profile B vào `trustedIdentities`, `D_wrongsigner` pass. Điều đó chứng minh chữ ký của profile B hợp lệ về mặt mật mã, và TC06 bị chặn **chỉ** vì danh tính.

Một khác biệt về cách ghi nhận: khi xác minh thất bại, extension trả HTTP 406 thay vì `verified: false`. Do đó Kyverno ghi kết quả là `error (blocked)` thay vì `fail`. Hệ quả chặn là như nhau, nhưng khi đọc event cần phân biệt "lỗi" do xác minh thất bại với "lỗi" do extension không phản hồi.

### 5.3.5. Fail-closed: TC09

Thu nhỏ deployment của extension về 0 replica rồi tạo lại Pod **hợp lệ** (`D_signed`): yêu cầu bị từ chối với `dial tcp …:443: connect: connection refused` sau 210–405 ms. Khi bật lại extension, cùng Pod đó được nhận. Kết quả lặp lại ở cả 4 lượt.

Đây là hành vi cần có của một lớp kiểm soát bảo mật: khi thành phần xác minh không khả dụng, hệ thống **từ chối** thay vì cho qua. Cái giá là tính sẵn sàng: nếu extension hoặc credential của nó gặp sự cố, mọi Pod mới trong `app` và `demo` đều không triển khai được (mục 5.6.3). Đồ án không "chữa" bằng cách đổi webhook sang `Ignore` hay chuyển policy sang Audit.

### 5.3.6. Phân quyền: TC10 và branch protection

Deployer chỉ có Role `app-deployer` trong namespace `app`. Kiểm tra bằng impersonation từ kubeconfig quản trị của kind:

- **`kubectl auth can-i`:** 14/14 kết quả đúng thiết kế.
- **Yêu cầu thật tới Pod đang chạy (26/11):** `exec`, `debug` (ephemeral container), `port-forward`, `attach`, `delete pod` và đọc Secret đều bị `Forbidden` (6/6), với thông báo nêu đúng tài nguyên con, ví dụ `cannot create resource "pods/exec"` hay `cannot patch resource "pods/ephemeralcontainers"`. Hai quyền được phép là đọc log và liệt kê Pod vẫn dùng được.
- **Cùng danh tính đó đã triển khai thành công ở TC01.** Role vừa đủ để triển khai, nhưng không đủ để vào container, đọc Secret hay sửa policy.

Branch protection của `main` chặn push trực tiếp (`GH006`). Mọi thay đổi, kể cả tài liệu, phải qua PR với hai required check `verify` và `policy-test`, áp dụng cả cho quản trị viên (`enforce_admins`).

### 5.3.7. Luồng hợp lệ trọn vẹn: TC01

TC01 là phép thử quan trọng nhất: các lớp kiểm soát phải **cho qua** đúng thứ cần cho qua. Commit merge PR #16 (`d1cd8dd`) kích hoạt run 45798939183:

1. **`verify`** (10:11:11–10:12:36): unit test, Gitleaks, build một lần ra `image.tar`, SBOM, Trivy và gate đều đạt; ghi `verification.json` (image ID, SHA-256 của `image.tar`, SBOM và báo cáo lỗ hổng).
2. **`publish`** (10:12:38–10:13:23), chạy bằng role OIDC:
   - tải đúng `image.tar` của cùng run;
   - kiểm checksum và đối chiếu `verification.json` (commit, run, attempt, kết quả gate);
   - `docker load` và so image ID;
   - push tag `sha-d1cd8dd72cd8-run-45798939183-1`;
   - đối chiếu digest do registry trả về với digest lúc push: `sha256:8d0b9dd6…c74a2f3`;
   - chờ ký `COMPLETE` đúng profile (`Signed by expected profile after ~5s`);
   - ghi `release.json`.
3. **Triển khai** (10:15:01):
   - `fetch-release.sh` tải `release.json`, chỉ chấp nhận run push `main` thành công;
   - `deploy.sh` kiểm `release.json` khớp run, digest có trên ECR với đúng tag và đã ký;
   - render manifest với digest, chạy `apply` bằng danh tính deployer.
4. **Admission:** Policy 1 nhận; Policy 2 gọi extension, log ghi `"verified": true` cho đúng digest lúc 10:15:05.
5. **Runtime:**
   - 2/2 Pod `Running`;
   - `spec.image` và `status.imageID` đều là digest phát hành;
   - `/healthz` trả `{"status":"OK"}`, `/version` trả 6.17.0 / `fd3a834` (đúng commit podinfo upstream đã ghim).

Không có bước nào build lại image hay ký thủ công. Image chạy trên cụm là **chính artifact** đã được test và scan trong `verify`, liên kết bằng chuỗi image ID → SHA-256 của `image.tar` → digest ECR.

*(Hình 5.3: run 45798939183 với ba job xanh; Hình 5.4: image `sha-d1cd8dd72cd8-…` và chữ ký trên ECR console; Hình 5.5: `kubectl get pods` và `/version`.)*

## 5.4. Số liệu đo

### 5.4.1. Thời gian pipeline

Số liệu từ toàn bộ run thành công trong lịch sử repo (`scripts/ci-metrics.sh`, độ phân giải 1 s):

| Job / bước | n | min (s) | trung bình (s) | max (s) |
|---|---|---|---|---|
| **Job `verify`** | 35 | 82 | 105,5 | 235 |
| — Unit test | 35 | 3 | 6,4 | 90 |
| — Gitleaks (toàn lịch sử) | 35 | 0 | 0,7 | 2 |
| — Build (một lần) | 35 | 29 | 37,4 | 86 |
| — SBOM (Syft) | 35 | 0 | 1,1 | 2 |
| — Trivy scan | 35 | 4 | 5,8 | 11 |
| — Gate Critical | 35 | 0 | 0,0 | 0 |
| **Job `policy-test`** | 39 | 6 | 9,6 | 15 |
| **Job `publish`** | 3 | 31 | 38,3 | 45 |
| — Push lên ECR | 3 | 17 | 19,0 | 22 |
| — Chờ ký (poll 5 s) | 3 | 1 | 5,7 | 8 |

*Bảng 5.4. Thời gian các job CI (17–26/11/2026).*

Các bước bảo mật trong `verify` (Gitleaks, SBOM, Trivy, gate) cộng lại trung bình **khoảng 7,6 s**, tức dưới 10% thời gian job. Phần lớn thời gian là build image. Trong `publish`, các bước kiểm toàn vẹn (tải artifact, checksum, so image ID) mất khoảng 3 s; phần còn lại chủ yếu là push layer. Giá trị max 235 s thuộc run đầu tiên, khi cache Go chưa tồn tại. Từ lúc tạo run tới khi image đã ký có trên ECR: **2 phút 14 giây** ở run 45798939183.

### 5.4.2. Độ trễ ký của ECR Managed Signing

Bước chờ ký trong CI phụ thuộc chu kỳ poll 5 s, nên đồ án đo trực tiếp bằng mốc thời gian của ECR (`scripts/signing-latency.sh`): `imagePushedAt` của artifact chữ ký trừ `imagePushedAt` của image, độ phân giải mili giây.

| Image | Chữ ký có trên ECR sau |
|---|---|
| `signed-baseline` (spike, 20/11) | 2164 ms |
| `sha-d1cd8dd72cd8-run-45798939183-1` | 2509 ms |
| `sha-25847499904f-run-45800377707-1` | 2454 ms |
| `sha-debc8f30999c-run-45801990148-1` | 1735 ms |

*Bảng 5.5. Độ trễ ký (n = 4): min 1735 ms, trung bình 2216 ms, max 2509 ms.*

Mỗi image có đúng một chữ ký, của `podinfo_signing_profile`; `signingTime` trong chữ ký nằm giữa hai mốc trên. Như vậy ký tự động chỉ thêm khoảng 2 s vào đường phát hành, và không cần lệnh ký hay khóa ký nào trong pipeline.

### 5.4.3. Độ trễ admission

Độ trễ đo bằng thời gian end-to-end của lệnh `kubectl` (gồm khởi động client), nên chỉ dùng để so sánh tương đối giữa các ca. Namespace ngoài phạm vi policy dùng làm mốc.

| Yêu cầu | Kết quả | Lượt | min (ms) | trung bình (ms) | max (ms) |
|---|---|---|---|---|---|
| Namespace ngoài phạm vi (mốc) | allow | 3 | 155 | 195 | 244 |
| Chỉ Policy 1: TC05 / TC07 / TC08 | deny | 3 mỗi ca | 193 | 232 | 317 |
| Policy 1 + 2: TC01 hợp lệ | allow | 4 | 1569 | 1854 | 2167 |
| Policy 1 + 2: TC04 chưa ký | deny | 4 | 587 | 765 | 1180 |
| Policy 1 + 2: TC06 sai người ký | deny | 4 | 1028 | 1166 | 1269 |
| TC09 extension tắt | deny | 4 | 210 | 291 | 405 |

*Bảng 5.6. Độ trễ admission trên kind. Hàng Policy 1 gộp 9 phép đo của 3 ca × 3 lượt ngày 17/11.*

Nhận xét:

- Policy 1 (CEL, đánh giá ngay trong Kyverno) gần như không tăng độ trễ so với mốc.
- Policy 2 thêm khoảng **1,5–2 s** cho mỗi Pod hợp lệ, vì mỗi lần phải gọi extension → ECR (manifest, referrer, chữ ký) → AWS Signer.
- Ca bị từ chối nhanh hơn ca hợp lệ. Giải thích khả dĩ theo thứ tự các bước xác minh của Notation (**chưa đo từng bước**): TC04 dừng ngay khi không tìm thấy chữ ký; ca hợp lệ còn phải kiểm thu hồi.
- Cache kết quả của extension đang tắt, nên mọi lần đều là "lần đầu". Đồ án chưa đo được chênh lệch có/không cache như mục 12.5 của kế hoạch gợi ý.
- Khi extension tắt, yêu cầu bị từ chối sau ~0,3 s (kết nối bị từ chối ngay), không phải chờ hết timeout 30 s của webhook.

Với một Deployment 2 replica, độ trễ này cộng thêm vào thời gian tạo từng Pod. Đó là mức chấp nhận được cho triển khai, nhưng đáng cân nhắc khi autoscale nhanh (mục 5.6.3).

### 5.4.4. SBOM và lỗ hổng của workload

| Chỉ số | Giá trị (run 45801990148, Trivy DB 26/11/2026) |
|---|---|
| SBOM | CycloneDX 1.7, 1032 component (76 module Go `pkg:golang/*`), 349 409 byte |
| Lỗ hổng | Critical 0, High 2, Medium 1, Unknown 4 |
| High | CVE-2026-116587 `go-jose/v4` 4.1.5 (bản vá 4.1.6); CVE-2026-78661 `golang.org/x/net` 0.61.0 (bản vá 0.62.0) |
| Gitleaks | 0 finding |

Kết quả không đổi so với lần quét ngày 16–17/11: trong 9–10 ngày không phát sinh CVE mới cho image này. Hai lỗ hổng High đến từ mã upstream podinfo 6.17.0 và đều đã có bản vá. Đồ án giữ nguyên upstream để số liệu phản ánh đúng workload thật; gate chỉ chặn Critical theo đề cương.

## 5.5. Truy vết

| Mắt xích | Liên kết bằng | Tự động / thủ công |
|---|---|---|
| Commit → run | `commit_sha`, `workflow_run_id`, `run_attempt` trong `verification.json` / `release.json` | Tự động |
| Run → artifact đã scan | `image_tar_sha256`, `local_image_id`; `sbom_sha256`, `vulnerability_report_sha256` trỏ vào artifact `security-reports-<run>-<attempt>` | Tự động (`verify`) |
| Artifact → image trên ECR | `publish` kiểm checksum + image ID trước khi push; digest registry = digest push | Tự động (`publish`) |
| Image → chữ ký | `wait-signature.sh` đòi `COMPLETE` đúng profile; `release.json` ghi profile | Tự động |
| `release.json` → Pod | `fetch-release.sh` → `deploy.sh` render đúng digest | **Thủ công** (2 lệnh trên máy có cụm kind) |
| Pod → digest | `spec.image`, `status.imageID`; log extension `"verified": true` cho đúng digest | Kiểm tự động trong `deploy.sh` |

*Bảng 5.7. Chuỗi truy vết của TC01.*

Chiều ngược, từ một Pod đang chạy về mã nguồn, thực hiện được mà không cần cơ sở dữ liệu riêng:
1. đọc digest của Pod;
2. tra tag trên ECR bằng `aws ecr describe-images --image-ids imageDigest=…`, ra `sha-d1cd8dd72cd8-run-45798939183-1`;
3. tag chứa commit (`d1cd8dd72cd8`) và run (`45798939183`);
4. SBOM và báo cáo CVE nằm trong artifact của run đó, kiểm được tính nguyên vẹn bằng SHA-256 ghi trong `release.json`.

Có hai giới hạn. Artifact trên GitHub chỉ được giữ 30 ngày, nên muốn truy vết lâu dài phải lưu SBOM ở nơi khác, ví dụ gắn vào ECR dưới dạng OCI referrer. Ngoài ra, SBOM chưa được ký, nên tính nguyên vẹn của nó dựa vào hash ghi trong `release.json` chứ không dựa vào chữ ký.

## 5.6. Phân tích và đánh giá

### 5.6.1. Trả lời câu hỏi nghiên cứu

| Tình huống | Lớp phát hiện/ngăn | Bằng chứng | Đánh giá |
|---|---|---|---|
| Secret trong mã | Gitleaks trong `verify` | TC02 | Ngăn trước khi build; không có image nào được tạo |
| Image có CVE Critical | Trivy gate trong `verify` | TC03 | Ngăn trước khi lên registry; không có artifact phát hành |
| Image chưa ký | Policy 2 (admission) | TC04, TC06, TC09 | Ngăn tại cụm, kể cả image không đi qua CI; sai người ký cũng bị chặn |
| Image từ nguồn không được phép | Policy 1 (+ Policy 2) | TC05, TC07, TC08 | Ngăn tại cụm, kể cả trong init container và khi dùng tag |
| Truy vết Pod → digest → SBOM → commit | `release.json` + tag `sha-…` | TC01 | Đủ mắt xích; một bước triển khai còn thủ công |

**Kết luận:** với phạm vi thử nghiệm, câu trả lời là **có**. Cả bốn tình huống bị ngăn ở đúng lớp được thiết kế, luồng hợp lệ đi qua trọn vẹn, và truy vết được hai chiều.

### 5.6.2. Giá trị của việc phối hợp nhiều lớp

Hai lớp bổ sung cho nhau theo đúng ranh giới tin cậy đã thiết kế ở Chương 3:

- **CI là lớp "dịch trái":** chặn sớm và rẻ (TC02 dừng sau 29 s, không tốn thời gian build), nhưng chỉ bảo vệ những gì đi qua pipeline. Một người có quyền `kubectl` có thể bỏ qua CI hoàn toàn.
- **Admission là lớp cuối trước khi chạy:** áp dụng cho mọi yêu cầu tạo Pod, bất kể nguồn gốc. TC04 và TC05 chính là mô phỏng "đi vòng CI", và đều bị chặn.
- **Chữ ký là cầu nối giữa hai lớp.** Admission không cần biết CI đã kiểm gì. Nó chỉ cần biết image được ký bởi danh tính mà chỉ pipeline mới dùng được, vì role publisher chỉ assume được từ nhánh `main` qua OIDC.
- **Chồng lớp tạo dự phòng.** Ở TC05 và TC08, cả Policy 1 lẫn Policy 2 đều chặn; sai cấu hình ở một lớp chưa làm thủng hệ thống.

Chi phí của các lớp bảo mật nhỏ so với lợi ích: dưới 10 s trong job `verify`, khoảng 2 s chờ ký, và 1,5–2 s cho mỗi Pod tại admission.

### 5.6.3. Đánh đổi về tính sẵn sàng

Fail-closed (TC09) làm Policy 2 trở thành **phụ thuộc bắt buộc** của mọi lần triển khai trong `app` và `demo`. Thực nghiệm cho thấy ba điểm có thể làm ngừng triển khai:

- Extension không chạy: Pod bị chặn ngay (TC09).
- Credential của role verifier hết hạn. Trên kind, credential lấy bằng role chaining từ phiên SSO nên sống tối đa 1 giờ. Khi hết hạn, mọi Pod mới bị chặn cho tới khi chạy lại `refresh-lab-credentials.sh`. Trên EKS, IRSA/Pod Identity sẽ tự làm mới và loại bỏ điểm yếu này.
- Mạng tới ECR/AWS Signer gián đoạn.

Pod đã chạy **không** bị ảnh hưởng, vì admission chỉ kiểm yêu cầu mới. Đó vừa là ưu điểm (dịch vụ không sập theo verifier), vừa là giới hạn (mục 5.7).

### 5.6.4. Các vấn đề chỉ lộ ra khi thực nghiệm

Nhiều lỗi không thể thấy khi chỉ đọc tài liệu. Đây là đóng góp thực tế của đồ án, ghi đầy đủ ở `docs/test-results.md` mục 4. Tiêu biểu:

1. **Mẫu trust policy OIDC trong tài liệu không khớp thực tế.** Repo bật *immutable subject claims*, nên claim `sub` có dạng `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main`. Trust policy viết theo mẫu phổ biến `repo:<owner>/<repo>:…` sẽ luôn bị từ chối. Phải kiểm dạng claim của chính repo trước khi tạo role.
2. **Extension không xác thực được token của Kyverno 1.19.** Mọi Pod, kể cả hợp lệ, bị chặn với `Token is not authorized`, vì thư viện verifier gửi TokenReview không khai báo audience. Đồ án vá thư viện (bản vá p2) để khai báo audience, thay vì tắt bước xác thực token.
3. **Extension ghi bearer token của Kyverno vào log** ở mức INFO. Bản vá p2 bỏ việc này.
4. **Bản phát hành chính thức của extension có 6 CVE Critical**, và repo upstream sắp lưu trữ. Đồ án tự build từ commit ghim, vá dependency, và đặt chính gate 0 Critical cho extension.
5. **Gitleaks quét lây sang nhánh khác** khi checkout toàn bộ lịch sử: một nhánh có secret làm fail mọi PR. Đã sửa bằng cách giới hạn phạm vi quét vào lịch sử của commit đang kiểm.
6. **"Image ID" mang nghĩa khác nhau theo image store.** Trên Docker 29 (containerd store), image ID là digest của OCI index, còn node kind báo digest của config. So nhầm hai loại sẽ cho kết luận sai về việc image đang chạy có đúng là image đã qua gate hay không.
7. **Repo public làm lộ account ID AWS qua log và artifact.** Đồ án đặt account ID ở GitHub Secret để được che tự động trong log (log job `publish`: 0 lần xuất hiện), và thay bằng `<ACCOUNT_ID>` trong `release.json` trước khi upload.
8. **Quyền tối thiểu được xác nhận bằng thực nghiệm.** Role publisher không có `signer:GetSigningProfile` mà Managed Signing vẫn ký `COMPLETE`, nên quyền này đã bị loại.

### 5.6.5. Mức độ tin cậy của kết quả

- **Môi trường là kind một node trên máy cá nhân**, không phải cụm production. Kết quả logic của policy không phụ thuộc quy mô, nhưng độ trễ tuyệt đối sẽ khác trên EKS.
- **Cỡ mẫu nhỏ.** TC02 và TC03 mỗi ca chạy một lần trên CI (có bằng chứng đầy đủ). Policy 2 chạy 4 lượt, Policy 1 chạy 3 lượt, độ trễ ký có 4 mẫu. Đủ để kết luận về hành vi chặn, nhưng chưa đủ để kết luận thống kê về hiệu năng.
- **Đo độ trễ end-to-end** của `kubectl` gồm cả thời gian khởi động client; chỉ dùng để so sánh giữa các ca.
- **Kết quả quét lỗ hổng gắn với thời điểm.** Fixture TC03 phải kiểm lại trước buổi bảo vệ vì DB thay đổi.
- **Các lần chạy bị loại đều được ghi lại.** Lần chạy TC03 đầu tiên (PR #3) bị loại vì Gitleaks quét lây sang nhánh khác (vấn đề 5 ở mục 5.6.4), chạy lại sau khi sửa. Hai phép kiểm lộ thông tin bị loại vì lỗi của chính script kiểm (biến rỗng), chạy lại có bảo vệ. Các sự cố hạ tầng (WSL dừng đột ngột khi tạo fixture, mirror Trivy DB bị ngắt) xảy ra ngoài các lần đo và được xử lý trước khi chạy lại.

## 5.7. Giới hạn

- **"Chỉ image đạt mới được ký" dựa vào pipeline và quyền push**, không dựa vào ECR. Managed Signing ký **mọi** image push vào repo khớp filter. Ai có quyền push vào `podinfo` thì image của họ cũng được ký, nên phải giới hạn chặt quyền push (chỉ role publisher).
- **Chữ ký chỉ chứng minh ai phát hành, không chứng minh nội dung lành tính.** Nếu pipeline hoặc role publisher bị lạm dụng, image độc hại vẫn có chữ ký hợp lệ.
- **Chữ ký image không ký SBOM hay kết quả scan.** Admission chưa kiểm attestation, nên không chặn được image có chữ ký mà không có SBOM/scan đạt.
- **Admission không gỡ Pod đã chạy** khi chữ ký bị thu hồi hoặc CVE mới được công bố; cần cơ chế rà soát và khắc phục riêng.
- **Trivy không phát hiện zero-day**, và chỉ chính xác theo DB tại thời điểm quét.
- **Bước triển khai trên kind còn thủ công**; không có job `deploy` tự động.
- **Credential verifier trên kind sống tối đa 1 giờ** (mục 5.6.3).
- **Policy 2 dùng `ClusterPolicy`, đã bị đánh dấu deprecated** trong Kyverno 1.19/1.20. Kyverno 1.19 chỉ còn được vá tới khi 1.21 phát hành (mô hình hỗ trợ N-1). Extension là bản tự build từ upstream sắp lưu trữ.
- **Extension trả HTTP 406 khi xác minh thất bại**, nên Kyverno ghi `error (blocked)` thay vì `fail`. Cache xác minh đang tắt.
- **Kiểm RBAC trên kind dùng impersonation** từ kubeconfig quản trị, không qua cơ chế xác thực thật của người dùng.

## 5.8. Tiểu kết

Thực nghiệm trên môi trường thật (GitHub Actions, Amazon ECR, AWS Signer, Kubernetes với Kyverno) cho thấy:

- Cả **10 ca kiểm thử** đều đạt, kèm hai kiểm tra bổ sung (branch protection, đối chiếu Notation CLI). Mỗi ca bị chặn đúng lớp, đúng nguyên nhân, có đối chứng.
- Bốn tình huống của đề cương được ngăn ở hai lớp bổ sung cho nhau. Luồng hợp lệ đi trọn từ commit tới Pod mà không build lại hay ký thủ công.
- Chi phí bảo mật nhỏ: dưới 10 s trong CI, khoảng 2 s để ký, 1,5–2 s cho mỗi Pod tại admission.
- Fail-closed bảo đảm an toàn khi verifier lỗi, nhưng đổi lại phụ thuộc vào tính sẵn sàng của verifier và credential.
- Các giới hạn chính nằm ở giả định tin cậy publisher, việc SBOM chưa được ký, và việc admission không tác động lên Pod đang chạy. Đây là hướng phát triển ở Chương 6.
