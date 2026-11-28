# PROGRESS.md — Tiến độ đồ án

Đọc file này đầu mỗi phiên. Cập nhật khi xong một giai đoạn hoặc có thay đổi quan trọng (quy tắc trong `CLAUDE.md`).

**Cập nhật lần cuối:** 28/11/2026
**Trạng thái:** ✅ Lập kế hoạch · ✅ Giai đoạn 1 (podinfo, Dockerfile, test, scan local) · ✅ kind + Kyverno 1.19.2 + Policy 1 + RBAC/manifest (phần không cần AWS của giai đoạn 4–5) · ✅ CI `verify` + `policy-test` xanh (push và PR) · ✅ branch protection `main` (18/11) · ✅ TC02 + TC03 trên CI (18/11) · ✅ `docs/test-results.md` + `docs/evidence/` (18/11) · ✅ `docs/architecture.md` + nháp Chương 2 (20/11) · ✅ AWS sẵn sàng (SSO profile `devsecops`, 20/11) · ✅ Spike bước 1–7 (20/11): fixture `D_unsigned`/`D_wrongsigner`, **Managed Signing đã bật**, `D_signed` ký tự động `COMPLETE`, `notation verify` signed pass / 2 fixture fail · ✅ **Spike đạt (26/11): bước 8–9 trên kind** — role verifier, extension p2, Policy 2; TC01 nhận, TC04/TC06 từ chối, TC09 fail-closed; Policy 1 chạy lại với ECR thật (TC05/07/08 Đạt) · ✅ **Giai đoạn 2–4 (26/11): OIDC + `publish` + `deploy.sh`, TC01 trọn luồng** · ✅ Spike bước 10 (chốt phiên bản, `preflight.sh`) · ✅ Đo đạc mục 12.5 · ✅ **TC01–TC10 đều Đạt** · ✅ Nháp Chương 5 · ✅ Nháp Chương 1, 3, 4, 6 (28/11)
**Giai đoạn kế tiếp:** **báo cáo** — ~~Chương 4, 3, 1, 6~~ ✅, ~~Phụ lục A + README~~ ✅ (28/11) → phụ lục B (demo); rà lại Chương 2 → kịch bản demo (`docs/demo-script.md`, cập nhật `demo/commands.md` cho TC01/TC04/TC05 chạy trực tiếp) → slide, video dự phòng, README dựng lại từ môi trường sạch (mục 15–16) → thu dọn AWS sau bảo vệ (mục 17). Tùy chọn: gắn SBOM vào ECR bằng `oras attach` (mục 9.6). Ước tính còn ~30–40 giờ (≈ 1,5–2 tuần nếu 3–4 giờ/ngày); **chưa biết hạn nộp** — hỏi người dùng để xếp lịch.

## ⏸ Điểm dừng (26/11/2026, tối) — làm tiếp từ đây

**Phần kỹ thuật cốt lõi đã xong; còn lại chủ yếu là báo cáo, demo, slide.**

**Đã làm trong ngày 26/11 (PR #15–#20, `main` = `e45ab14`):**
- Spike bước 8–9 (Policy 2 trên kind, bản vá p2 extension) → **spike đạt 6.2**; bước 10: chốt `docs/versions.md` mục 4, thêm `scripts/preflight.sh` (chỉ đọc, 33/33 ĐẠT).
- Giai đoạn 2–4: OIDC + role `devsecops-publisher`, lifecycle `sha-`, job `publish`, `fetch-release.sh` + `deploy.sh` → **TC01 trọn luồng** (run 45798939183).
- Đo đạc (`docs/test-results.md` mục 3): độ trễ ký 1735–2509 ms (tb 2216, n=4, `scripts/signing-latency.sh`); `publish` tb 38 s (n=3), `verify` tb 106 s (n=35); admission Policy 2 4 lượt; SBOM/Trivy không đổi (0 Critical, 2 High).
- TC10 bổ sung yêu cầu thật tới Pod đang chạy: 6/6 Forbidden.
- Nháp **Chương 5** `docs/report/chuong-5-thuc-nghiem-danh-gia.md` — **còn thiếu ảnh Hình 5.1–5.5** (người dùng chụp: run TC02/TC03/TC01 trên Actions, ECR console image + chữ ký, `kubectl get pods` + `/version`). Hình 5.5 cần cụm đang chạy.

**Bắt đầu phiên sau:**
1. Viết báo cáo **không cần** Docker/AWS. Chỉ bật khi cần chụp ảnh, demo hoặc chạy lại kiểm thử.
2. Khi cần môi trường: mở Docker Desktop (lỗi `0x80072746` → tắt Docker Desktop, `wsl --shutdown`, mở lại) → cụm kind `devsecops` tự lên (Kyverno, extension, Policy 1+2, Deployment `app/podinfo` 2 replica vẫn còn) → WSL: `aws sso login --profile devsecops` → `bash scripts/refresh-lab-credentials.sh` (credential verifier ≤ 1 giờ) → `bash scripts/preflight.sh` phải ĐẠT.
3. Mỗi lần merge vào `main` sẽ chạy `publish` → thêm 1 image `sha-…` lên ECR (đúng thiết kế; lifecycle giữ 10).

**Trạng thái lúc dừng (26/11, ~10:50 UTC):**
- AWS (không có tài nguyên tính phí theo giờ): ECR `podinfo` 16 mục ~93 MB (3 fixture, 5 image `sha-…`, 7 chữ ký, 1 tag referrer); 2 signing profile; signing configuration; lifecycle; OIDC provider; role `devsecops-publisher`, `devsecops-verifier`. Budget 15 USD.
- GitHub: Secret `AWS_ACCOUNT_ID`, Variables `AWS_REGION`, `ECR_REPOSITORY`, `SIGNING_PROFILE_NAME`, `AWS_PUBLISH_ROLE_NAME`.
- Máy: đã tắt Docker Desktop + WSL. Ổ C: còn ~19 GB (người dùng đã dọn 26/11).
- Credential verifier đã hết hạn (11:11 UTC) → khi bật lại cụm, Pod **mới** trong `app`/`demo` bị chặn tới khi refresh (fail-closed, đúng thiết kế).

## ✅ Giai đoạn 2–3 (26/11/2026, chiều) — xong, **TC01 trọn luồng ĐẠT**

- PR #16 merge (`d1cd8dd`) → run **45798939183**: `verify` 85 s, `policy-test` 11 s, `publish` 45 s (ký `COMPLETE` sau ~5 s). Digest `sha256:8d0b9dd6a7e794df46671cc9b9c8f99c5f9e0d1265685eede11e20761c74a2f3`, tag `sha-d1cd8dd72cd8-run-45798939183-1`.
- `fetch-release.sh` → `deploy.sh`: extension `"verified": true`, 2 Pod `Running` đúng digest, `/healthz` OK, `/version` 6.17.0. Bằng chứng `docs/evidence/tc01-e2e/20261126T101455Z/`; chi tiết `docs/test-results.md`.
- Publisher **không** cần `signer:GetSigningProfile` (đã loại). Log job `publish` không chứa account ID (0 lần, 63 chỗ `***`).
- Deployment `podinfo` đang chạy ở namespace `app` trên kind (credential verifier hết hạn 11:11 UTC; Pod đã chạy không bị ảnh hưởng, Pod mới sẽ bị chặn tới khi refresh).
- Secret `AWS_ACCOUNT_ID` + Variables `AWS_REGION`, `ECR_REPOSITORY`, `SIGNING_PROFILE_NAME`, `AWS_PUBLISH_ROLE_NAME` đã đặt (người dùng, 26/11 10:10 UTC).

**Chi tiết thiết kế:**

- **AWS (đã tạo, `scripts/aws-create-publisher-role.sh`):** OIDC provider `token.actions.githubusercontent.com` (audience `sts.amazonaws.com`); role **`devsecops-publisher`** (inline `publisher-ecr-sign`: `ecr:GetAuthorizationToken`; push/đọc/`DescribeImageSigningStatus` chỉ repo `podinfo`; `signer:SignPayload` chỉ profile chính — **bỏ `signer:GetSigningProfile`** theo mục 8.4, chờ run đầu xác nhận ký vẫn `COMPLETE`). Trust: `aud` + `sub` = `repo:duy1504@210903593/devsecops-project@1460578199:ref:refs/heads/main` (repo bật *immutable subject claims*, khác mẫu mục 8.5). Access Analyzer: chỉ 1 SUGGESTION `CONFIRM_AUDIENCE_CLAIM_TYPE`. Bằng chứng `docs/evidence/aws/publisher-role/`.
- **Lifecycle (`scripts/aws-lifecycle.sh`, `infra/aws/lifecycle-policy.json`):** chỉ tag tiền tố `sha-`, giữ 10; preview 0 image bị chọn (fixture, chữ ký và tag referrer `sha256-6452…` của Notation không khớp `sha-`). Bằng chứng `docs/evidence/aws/lifecycle/`.
- **Workflow:** job `publish` (needs `verify`, chỉ push `main`, `id-token: write` chỉ ở job này): tải `approved-image` cùng run → `sha256sum -c` + đối chiếu `verification.json` (commit/run/attempt/gate) + image ID → OIDC (`configure-aws-credentials` v6.3.0, `allowed-account-ids`, mask account ID, phiên 900 s) → push tag `sha-<12>-run-<id>-<attempt>` → digest registry = digest push → `wait-signature.sh` → `release.json` → che account ID → upload `release-<run>-<attempt>`. Không job `deploy` (kind).
- **Repo public → account ID để ở GitHub Secret `AWS_ACCOUNT_ID`** (GitHub tự che trong log); ARN ghép trong job; `release.json` trong artifact đã thay bằng `<ACCOUNT_ID>`, `deploy.sh` ghép lại từ `aws-env.sh`. Lệch so với mục 9.3 (biến `*_ARN`, `ECR_IMAGE`): dùng `SIGNING_PROFILE_NAME`, `AWS_PUBLISH_ROLE_NAME`.
- **Triển khai:** `scripts/fetch-release.sh` (Git Bash, `gh`: chỉ run push `main` thành công) → `scripts/deploy.sh <release.json>` (WSL): kiểm release/ECR tag/ký, chặn nếu credential verifier sắp hết hạn, apply bằng **danh tính deployer** (impersonate group `devsecops-deployers`), rollout, kiểm imageID runtime = digest, smoke test qua `services/proxy`.
- Agent không được ghi GitHub Secret (auto mode chặn) → người dùng tự đặt. Đổi account/role thì đặt lại cùng tên.
- `fetch-release.sh` chạy Git Bash (không có `jq` → chỉ `gh --jq`, ghi `run.json`); `deploy.sh` đối chiếu `release.json` với `run.json`.

## Spike (26/11/2026, sáng) — ghi chép

**Spike đường găng ĐẠT** (tiêu chí 6.2): `D_signed` do Managed Signing ký (không `notation sign`); `notation verify` pass/fail đúng; Kyverno **deny thật** (Enforce); fail-closed đã thử. Chi tiết số liệu trong `docs/test-results.md`.

**Spike bước 8–9 (26/11, người dùng đồng ý tạo role verifier):**
- `scripts/aws-create-verifier-role.sh`: role **`devsecops-verifier`** (inline `verifier-read`: `ecr:GetAuthorizationToken`; đọc repo `podinfo`; `signer:GetRevocationStatus`), chỉ phiên SSO `AdministratorAccess` assume được; IAM Access Analyzer 0 finding. Template `infra/aws/verifier-{trust,policy}.template.json`.
- `scripts/refresh-lab-credentials.sh`: assume role (phiên **≤ 1 giờ** do role chaining) → Secret `kyverno-notation-aws/verifier-aws-credentials` + Secret `ecr-pull` (namespace `app`, `demo`, gắn SA `default`), kiểm `PutImage` bị AccessDenied, rollout restart extension. **Chạy lại trước mỗi buổi làm việc/demo.**
- `scripts/install-notation-ext.sh` + `infra/kyverno-notation-aws/` (CRD + `install.yaml` chỉnh từ upstream): image `local/kyverno-notation-aws:58b210b-p2`, TrustStore `policies/truststore.yaml` (kiểm fingerprint), TrustPolicy `policies/trustpolicy.template.yaml`, Policy 2 `policies/verify-signer.template.yaml` (`ClusterPolicy`, Fail, `imageReferences: ["*"]`, caBundle = CA công khai nhúng lúc render).
- **Bản vá p2** cho thư viện `kyverno-notation-verifier` v1.1.0 (`infra/kyverno-notation-aws/patches/`, `scripts/build-notation-ext.sh`): TokenReview khai báo audience `kyverno-svc.kyverno.io` (không có thì mọi yêu cầu bị `Token is not authorized`), không ghi token ra log. Gate 0 Critical/0 High. Chi tiết `docs/versions.md` mục 2b.
- `scripts/test-policy2-cluster.sh` (TC01/04/06/09) và `scripts/test-policy1-cluster.sh` (ECR thật) đều ĐẠT. Bằng chứng: `docs/evidence/spike/policy2-kind/`, `docs/evidence/policy1-real-ecr/`, `docs/evidence/spike/verifier-role/`.

**Ổ C:** sáng 26/11 có lúc 0 MB (`Bus error` khi build); chiều người dùng đã dọn, còn ~19 GB. Docker vhdx chỉ tăng — build nhiều thì theo dõi lại. **Hỏi người dùng trước khi xóa/thu gọn** (`docker builder prune`, compact vhdx, `Downloads` là dữ liệu cá nhân).

**Thông tin chung về repo/máy:**
- Kết quả kiểm thử tổng hợp ở `docs/test-results.md` (đã cập nhật 26/11), bằng chứng chọn lọc ở `docs/evidence/` (bản đầy đủ ở `reports/`, không commit).
- Repo **public**; `gh` 2.104.0 đã đăng nhập (`%LOCALAPPDATA%\Programs\gh\bin\gh.exe`; trong Bash gọi `"$LOCALAPPDATA/Programs/gh/bin/gh.exe"`).
- **Branch protection `main`** (bật 18/11, kiểm qua API): bắt PR, 0 approval, required `verify` + `policy-test`, strict, `enforce_admins`, cấm force push/xóa; secret scanning + push protection bật. **Mọi thay đổi (kể cả `PROGRESS.md`) phải qua PR**: tạo nhánh → commit (tác giả `Duy Phan`, không ghi công Claude) → `gh pr create` → chờ 2 check → `gh pr merge --merge --delete-branch`.
- Ca đã có bằng chứng: **TC01–TC10 đều Đạt** (TC02 PR #4, TC03 PR #6 trên CI; TC04–TC09 trên kind với ECR thật; TC01 trọn luồng run 45798939183; TC10 kind) + branch protection + `notation verify`. Chi tiết trong `docs/test-results.md`.
- Lỗi tìm ra nhờ thực nghiệm (đưa vào báo cáo): Gitleaks quét lây sang nhánh khác → sửa `--log-opts=HEAD` (PR #5); allowlist Gitleaks toàn cục bỏ qua cả file; `.gitignore` `*token*` chặn nhầm mã podinfo; extension bản phát hành có 6 Critical.
- Nhánh sao lưu **chỉ ở local**: `backup/main-before-rewrite`, `backup/sarif-before-rewrite` — chờ người dùng xác nhận rồi xóa.
- Cụm kind `devsecops` (Kyverno 1.19.2 + Policy 1 với ECR_IMAGE giả) vẫn tồn tại. Docker Desktop phải chạy trước (WSL báo "docker could not be found" khi Docker Desktop tắt); cụm tự lên lại khi Docker chạy. Dựng mới: `bash scripts/cluster-up.sh` rồi `ECR_IMAGE=... bash scripts/apply-policies.sh`.
- Lệnh demo TC02/TC03/Policy 1: `demo/commands.md`. Fixture TC03 cần kiểm lại trước buổi bảo vệ (DB Trivy thay đổi).

**AWS (20/11, chiều) — đã dùng được:**
- Account **PAID/ACTIVE** (credit 0 USD), Budget `devsecops-lab` 15 USD, MFA root. IAM Identity Center + AWS Organizations; user SSO `duy-admin`, permission set `AdministratorAccess` (8 giờ).
- WSL: profile **`devsecops`** (SSO, region `ap-southeast-1`). Hết hạn → `aws sso login --profile devsecops` (WSL không tự mở trình duyệt, mở link bằng tay). `~/.aws` là symlink tới `C:\Users\ZenBook\.aws`.
- Biến mục 4.3: `source scripts/aws-env.sh` (lấy account ID từ STS, **không ghi account ID vào repo**).
- Kiểm tra chỉ đọc: `ap-southeast-1` có ECR Managed Signing (`get-signing-configuration` → `SigningConfigurationNotFoundException`) và nền tảng Signer `Notation-OCI-SHA384-ECDSA`.
- **Spike bước 1–3 xong:** `scripts/aws-create-repo.sh` (repo `podinfo`, IMMUTABLE, KMS) và `scripts/create-fixtures.sh` (từ chối chạy nếu registry đã có signing configuration). Kết quả:
  - `D_unsigned` = `sha256:85b97e849174ed1d56fed8629ecb7cdb2bfd2a10bd9fe9f3110a6e97068cdf6f` (tag `unsigned-baseline`) — 0 chữ ký.
  - `D_wrongsigner` = `sha256:6452d1877aeb082b63b02e742fd04a30496f2acf9e2b135eccf2f8b776782e75` (tag `wrong-signer-baseline`) — đúng 1 chữ ký, `signingProfileVersion` = `podinfo_wrong_signer/uG2yIHkItJ`, hạn 20/11/2027.
  - Cả hai: manifest OCI đơn (`application/vnd.oci.image.manifest.v1+json`), Trivy 0 Critical. Bằng chứng: `docs/evidence/spike/fixtures/20261120T101155Z/` (đã che account ID).
  - **Không push lại, không gắn thêm tag cho hai fixture.** Giá trị local: `reports/spike/fixtures.env` (`D_UNSIGNED`, `D_WRONGSIGNER`, `D_SIGNED`).
- **Spike bước 4 xong:** `scripts/notation-verify.sh` — root AWS Signer tải lại, khớp fingerprint đã ghim → trust store `aws-signer-ts`; trust policy `strict`, đúng repo, chỉ tin `podinfo_signing_profile`. `D_unsigned` → exit 1 "no signature is associated"; `D_wrongsigner` → exit 1, plugin báo "Signature publisher doesn't match any trusted identities."; đối chứng (tạm tin profile B) → `D_wrongsigner` pass, rồi khôi phục policy chính. Bằng chứng `docs/evidence/spike/verify-fixtures/20261120T102136Z/`. Trust policy Notation nằm ở `~/.config/notation` trong WSL.
- **Spike bước 5–7 xong (người dùng đồng ý bật Managed Signing):**
  - `scripts/enable-managed-signing.sh`: profile chính `podinfo_signing_profile` (version `gwTPmh8tPO`), signing configuration 1 rule, filter đúng `podinfo` (`WILDCARD_MATCH`, không `*`), template `infra/aws/signing-config.template.json`. Sau khi bật: `D_unsigned` vẫn 0 chữ ký, `D_wrongsigner` vẫn 1.
  - `scripts/spike-signed.sh` + `scripts/wait-signature.sh` (mục 8.6, thêm `RELEASE_DIR`): `D_signed` = `sha256:59c79d672187539c33b7da543c70360fd55a0963eaa780da44e3cad3db6d0035` (tag `signed-baseline`), `COMPLETE` ngay lần poll đầu; `signingTime` trùng giây push (10:42:00Z). Không có lệnh ký thủ công.
  - `notation verify`: signed pass; unsigned, wrong-signer fail đúng lý do; đối chứng profile B pass.
  - Bằng chứng: `docs/evidence/spike/{managed-signing,signed,verify-signed}/`.
  - **Từ giờ mọi image push vào `podinfo` đều được ký bằng profile chính.**
- Sự cố: `docker login` ECR lỗi `The stub received bad data` (token ECR quá dài cho Windows Credential Manager) → script dùng `DOCKER_CONFIG` tạm, xóa khi xong. Docker Desktop khởi động lỗi `Wsl/Service/CreateInstance/0x80072746` → tắt Docker Desktop, `wsl --shutdown`, mở lại.
- Tài nguyên AWS đang có (không tính phí theo giờ): repo ECR `podinfo` (3 image ~12 MB + 2 chữ ký), signing profile `podinfo_signing_profile` và `podinfo_wrong_signer`, signing configuration registry. Từ 26/11: role `devsecops-verifier`, OIDC provider GitHub, role `devsecops-publisher`, lifecycle policy repo `podinfo` (đều miễn phí).

**Đã viết trong lúc chờ AWS (20/11):** `docs/architecture.md` (luồng, ranh giới tin cậy, 13 quyết định kèm lý do và trạng thái, truy vết, giới hạn); `docs/report/chuong-2-co-so-ly-thuyet.md` (bản nháp Chương 2 theo mục 15, cần đối chiếu trích dẫn trước khi nộp).

**Việc tùy chọn còn lại (không cần AWS):** nháp Chương 1, 3 của báo cáo; xóa nhánh `backup/*` (chờ người dùng xác nhận).

**Đổi thứ tự (người dùng đồng ý 17/11/2026):** account AWS tạm chưa dùng được → làm trước phần không phụ thuộc AWS, theo thứ tự: ~~(1) kiểm tra tương thích `kyverno-notation-aws` ↔ Kyverno 1.19.2~~ ✅ xong 17/11 (tự build, gate 0 Critical/0 High, `go test` đạt; chưa chạy trên cụm) → ~~(2) podinfo + Dockerfile + test~~ ✅ → ~~(3) scan local (Gitleaks, `image.tar`, Syft, Trivy)~~ ✅ xong 17/11 → ~~(5) kind + Kyverno + Policy 1 + RBAC/manifest~~ ✅ xong 17/11 → (4) job `verify` + `policy-test`: `.github/workflows/ci-cd.yml` ✅ run đầu xanh 17/11 (run 44024593626, attempt 2). **Chưa làm** Policy 2, `publish`, OIDC cho tới khi spike đạt.

## Đã hoàn thành

- [x] Đề cương `Dự kiến.txt`.
- [x] Kế hoạch chi tiết `KE_HOACH_DO_AN_FINAL.md`: đã rà soát, sửa lỗi và chốt.
- [x] `docs/versions.md`: xác minh ngày 04/11/2026 — Kyverno v1.19.2 / chart 3.9.2, Kyverno CLI v1.19.2 và Syft v1.56.0 (kèm SHA-256); kiểm lại 17/11: `v1.20.0` đã phát hành, vẫn giữ ghim 1.19.2.
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
- [x] GitHub repo `duy1504/devsecops-project`; `git init -b main` trong `C:\Teo\DevOps`, remote `origin` đã thêm; có `.gitignore`, `.gitattributes` (LF cho script). Commit đầu `b5be5d5` đã push lên `origin/main` (17/11/2026).
- [x] WSL2 Ubuntu + Docker Desktop (engine 29.9.1) đang chạy (17/11/2026).
- [x] AWS account lab (Paid plan). 20/11: MFA root, Budget 15 USD, SSO user `duy-admin` qua IAM Identity Center.
- [x] Công cụ trong WSL: `scripts/install-tools.sh` (cài vào `~/.local`, không sudo, ghim phiên bản + SHA-256) chạy thành công 17/11/2026; bộ phiên bản ở mục 1b `docs/versions.md`. AWS CLI 2.40.4 có đủ lệnh Managed Signing.
- [x] AWS CLI trong WSL: profile SSO `devsecops`, `aws sts get-caller-identity` thành công (20/11).
- [x] `ap-southeast-1` hỗ trợ ECR Managed Signing + Signer `Notation-OCI-SHA384-ECDSA` (20/11, kiểm tra chỉ đọc).
- [x] Biến mục 4.3: `scripts/aws-env.sh` (20/11).

### Giai đoạn 0 — Spike đường găng (mục 6)

Làm ngay sau phần chuẩn bị. Chưa qua tiêu chí 6.2 thì chưa làm pipeline.

- [x] Bước 1–2: repo ECR `podinfo` (chưa bật signing rule) → fixture `D_unsigned` (20/11).
- [x] Bước 3: profile B → fixture `D_wrongsigner` ký tay — **trước** khi bật signing rule (20/11).
- [x] Bước 4: `notation verify` thất bại với cả hai fixture, đúng lý do; đối chứng tin profile B thì pass (20/11).
- [x] Bước 5–7: profile chính + bật Managed Signing → `D_signed` → `COMPLETE` → `notation verify` thành công (20/11).
- [x] Bước 8–9: kind + Kyverno 1.19.2 + extension; signed được chấp nhận, unsigned và wrong-signer bị từ chối; thử fail-closed (26/11).
- [x] Bước 10: lưu log, chốt bộ phiên bản vào mục 4 của `docs/versions.md` (26/11): upstream không có bản mới; `scripts/preflight.sh` 33/33 ĐẠT; bằng chứng `docs/evidence/spike/final-versions/`.
- Nếu không đạt: lùi theo A → B → C (mục 6.3), tối đa 2–3 ngày mỗi phương án.

### Các giai đoạn sau (chỉ bắt đầu khi spike đạt)

- [x] Giai đoạn 1 — podinfo, Dockerfile, test, scan local (mục 7). Làm trước spike vì AWS chưa dùng được (17/11/2026). podinfo 6.17.0 `fd3a834` → `app/` (`scripts/vendor-podinfo.sh`, nguồn gốc `docs/upstream.md`); `go test` đạt; image distroless `USER 65532:65532`, 50,6 MB (`image.tar` 12 MB); `/healthz` `/readyz` `/` HTTP 200, `/version` = 6.17.0/`fd3a834`, tiến trình chạy UID 65532; SBOM CycloneDX 1.7 (1032 component); Trivy (DB 16/11): **0 Critical**, HIGH=2 (`go-jose/v4` 4.1.5, `x/net` 0.61.0 — đều có bản vá, giữ nguyên upstream làm số liệu ban đầu), MEDIUM=1, UNKNOWN=4; Gitleaks sạch với `.gitleaks.toml` (3 dương tính giả upstream allowlist cấp rule, đã kiểm chứng không che secret khác). Bằng chứng: `reports/podinfo/` (không commit).
- [ ] Giai đoạn 2 — hoàn thiện AWS/IAM: lifecycle, ma trận quyền, OIDC, `wait-signature.sh` (mục 8). **26/11:** ✅ lifecycle, ✅ OIDC + role publisher, ✅ role verifier, ✅ tập quyền publisher tối thiểu xác nhận qua run `publish` thật (không cần `GetSigningProfile`).
- [x] Giai đoạn 3 — pipeline: `verify`, `policy-test`, `publish`, branch protection (mục 9). **26/11:** ✅ `publish` (PR #16, run 45798939183 xanh). **17/11:** `.github/workflows/ci-cd.yml` có `verify` (test → Gitleaks toàn lịch sử → build một lần → `image.tar` + checksum + image ID → Syft SBOM + kiểm có `pkg:golang` → Trivy một lần JSON → upload báo cáo `always()` → gate 0 Critical → summary → `verification.json` → upload approved image chỉ khi push `main`) và `policy-test` (Kyverno CLI ghim SHA-256 → `scripts/policy-test.sh`). Action ghim commit SHA; Gitleaks/Syft/Trivy/Kyverno cài binary ghim SHA-256; không `id-token`. Repo chuyển **public** 17/11 (người dùng chọn, để có branch protection miễn phí; đã rà: không secret, không account thật; email tác giả commit lộ trong lịch sử — đã báo người dùng) → thêm lại upload SARIF lên Code Scanning (`security-events: write`, bỏ qua PR từ fork) qua PR nhánh `ci/sarif-upload`. **Run đầu 17/11 (commit `e66dca7` — SHA lúc chạy `7aa3cba`, run 44024593626/2): `verify` 3m55s + `policy-test` 9s đều xanh; unit test, Gitleaks 0 finding, build, SBOM 1032 component, Trivy DB 2026-11-17T01:05:25Z, gate Critical 0 / High 2 — khớp số liệu local.** **Còn:** branch protection + required checks, `publish` (sau spike).
- [x] Giai đoạn 4 — triển khai: namespace, pull secret, RBAC, manifest, `deploy.sh` (mục 10). **26/11:** ✅ pull secret (`refresh-lab-credentials.sh`), ✅ `deploy.sh` + `fetch-release.sh` (TC01 trọn luồng). **Đã xong 17/11:** `scripts/cluster-up.sh` (kind v1.35.8 + Kyverno chart 3.9.2 qua OCI, kiểm SHA-256), `k8s/namespaces.yaml`, `k8s/rbac.yaml` (`scripts/check-rbac.sh`: 14/14 đúng), `k8s/deployment.template.yaml` + `service.yaml` (thử với image local ở namespace tạm: 2/2 Running, UID 65532, roFS, `/healthz` 200, ghi `/data` 202). **Còn:** pull secret ECR (`refresh-lab-credentials.sh`), `deploy.sh` (cần `release.json`).
- [ ] Giai đoạn 5 — Policy 1 + Policy 2 hoàn chỉnh, test offline (mục 11). **Policy 1 xong 17/11:** `policies/allowed-image.template.yaml` (CEL, siết thêm 64 hex sau `@sha256:`), test offline 6/6 (`scripts/policy-test.sh`, đã thử đảo kỳ vọng → fail đúng); trên cụm (`scripts/test-policy1-cluster.sh`, ECR_IMAGE giả `111122223333`): TC05/TC07/TC08 bị từ chối, đối chứng + namespace ngoài phạm vi cho qua, Deployment vi phạm bị từ chối ngay khi apply (autogen). **Còn:** chạy lại với ECR_IMAGE thật; Policy 2 (sau spike).
- [ ] Giai đoạn 6 — TC01–TC05 bắt buộc, TC06–TC10 nếu kịp; đo đạc, thu bằng chứng (mục 12). **18/11:** ✅ TC02 (Gitleaks, PR #4) và ✅ TC03 (Trivy gate, PR #6) có bằng chứng thật trên CI. TC05/TC07/TC08 và TC10 (`auth can-i`) đã đạt trên kind với ECR_IMAGE giả → chạy lại với ECR thật. TC01, TC04, TC06, TC09 cần AWS (spike). **26/11:** ✅ TC04, TC06, TC09; ✅ TC05/07/08 với ECR thật; TC01 đạt phần admission. **26/11 chiều:** ✅ **TC01 trọn luồng** (run 45798939183 → `deploy.sh`). Còn: TC02–TC10 đều đã có bằng chứng; đo đạc tổng hợp mục 12.5, demo.
- [ ] Báo cáo, slide, video dự phòng, README dựng lại (mục 15–16); thu dọn AWS (mục 17); checklist (mục 18).

## Cần kiểm chứng khi triển khai

Các điểm kế hoạch ghi là "mẫu, cần đối chiếu":

- ~~`apiVersion` của `ValidatingPolicy` trên bản cài; schema `kyverno-test.yaml` cho `ValidatingPolicy`~~ ✅ 17/11: `policies.kyverno.io/v1`; `results[]` cần `isValidatingPolicy: true`.
- Ghi nhận hành vi thật (cho báo cáo, 17/11): webhook `vpol.validate.kyverno.svc-fail` (failurePolicy Fail); bằng chứng deny = stderr + exit code + event `PolicyViolation … fail (blocked)` gắn trên `ValidatingPolicy/allowed-image` ở namespace `default` (không nằm ở namespace của Pod); log admission mức `--v=2` mặc định **không** ghi từng lần deny; Deployment vi phạm bị chặn ngay (autogen), không có `FailedCreate`.
- Schema output của `describe-image-signing-status`.
- ~~Dạng claim `sub` OIDC thực tế của repo.~~ ✅ 26/11: immutable subject — `repo:duy1504@210903593/devsecops-project@1460578199:ref:refs/heads/main`.
- Release `kyverno-notation-aws` tương thích Kyverno 1.19.2; gỡ phần attestation minh họa trong mẫu policy.
- Cú pháp `gitleaks git`, `trivy convert` theo bản ghim; tập IAM action tối thiểu.

## Nhật ký

| Ngày | Nội dung |
|---|---|
| 04/11/2026 | Hoàn thành kế hoạch cuối; xác minh phiên bản Kyverno/Syft; tạo `CLAUDE.md`, `PROGRESS.md`. Chưa triển khai. |
| 17/11/2026 | Chốt 4 quyết định: lịch tuần tự, kind, cá nhân, repo trong `C:\Teo\DevOps`, AWS account lab riêng. Kiểm tra Kyverno: v1.20.0 đã ra, vẫn còn CRD `ClusterPolicy`; giữ ghim 1.19.2. Repo git nối GitHub, đã push. AWS account (Paid plan) đã tạo. Cài 11 công cụ trong WSL bằng `scripts/install-tools.sh` (commit `590e8f6`). Tạm dừng: chờ người dùng bật MFA/Budgets/SSO và chạy `aws configure sso`. |
| 17/11/2026 | Sửa xác thực GitHub cho agent: cấu hình helper riêng repo trỏ Git Credential Manager của Git for Windows. Git MSYS2 chạy `git push --dry-run origin main` thành công, dự kiến đẩy `590e8f6..e2387fd`; chưa push thật. Ghi cách dùng PowerShell và giới hạn helper Windows trong `CLAUDE.md`. |
| 17/11/2026 | AWS tạm chưa dùng được → người dùng đồng ý làm trước phần không phụ thuộc AWS. Đánh giá `kyverno-notation-aws`: release `v1.1` có 6 Critical/80 High (Trivy, DB 16/11), repo sắp archive. Người dùng chọn **tự build từ `main@58b210b`**: `scripts/build-notation-ext.sh` (builder Go 1.26.10 + runtime ghim digest, vá `x/net`/`go-jose`) → 0 Critical/0 High, `go test` đạt; bằng chứng `reports/notation-ext/` (không commit). Chi tiết `docs/versions.md` mục 2b. |
| 17/11/2026 | Giai đoạn 1 xong (trước spike): podinfo 6.17.0 vào `app/`, `Dockerfile` (builder Go 1.27.4 + distroless ghim digest, UID 65532), `.dockerignore`, `.gitleaks.toml` (rule `DEMO_SECRET_`, allowlist cấp rule cho 3 dương tính giả upstream — allowlist toàn cục bị loại vì bỏ qua cả file). Sửa `.gitignore`: `*token*` đã chặn nhầm 7 file nguồn podinfo → thêm ngoại lệ `!app/**/*token*`. Số liệu ban đầu: 0 Critical, 2 High. |
| 17/11/2026 | Giai đoạn 4–5 phần không cần AWS: cụm kind `devsecops` (K8s v1.35.8) + Kyverno 1.19.2 (chart 3.9.2 qua OCI ghcr.io vì `kyverno.github.io` timeout; kiểm SHA-256 chart). Policy 1 CEL: test offline 6/6, trên cụm TC05/TC07/TC08 deny + đối chứng allow (ECR_IMAGE giả, chưa có AWS). RBAC deployer 14/14. Manifest chạy được với image local. Bằng chứng `reports/admission/20261117T042150Z/` (không commit). |
| 17/11/2026 | Viết workflow `ci-cd.yml` (job `verify` + `policy-test`, chưa có `publish`). Action ghim SHA (checkout v7.0.1, setup-go v7.1.0, setup-buildx v4.4.1, build-push v7.4.0, upload-artifact v7.0.2); CLI cài binary ghim SHA-256. Bỏ upload SARIF vì repo private. YAML hợp lệ; chưa có actionlint (chạy image ngoài bị chặn). `Dockerfile` đặt mặc định `REVISION` = commit podinfo. |
| 17/11/2026 | Run CI đầu tiên xanh (run 44024593626/2, commit `e66dca7` — SHA lúc chạy `7aa3cba`): verify + policy-test đạt, Critical 0 / High 2, SBOM 1032 component. Branch protection chưa bật: repo private trên GitHub Free không hỗ trợ — chờ người dùng chọn cách. |
| 17/11/2026 | Repo chuyển public (người dùng). Cài GitHub CLI 2.104.0 trên Windows (zip chính thức, kiểm SHA-256). Nhánh `ci/sarif-upload`: thêm lại upload SARIF (codeql-action v4.39.3 ghim SHA). Chờ người dùng `gh auth login` để mở PR. |
| 17/11/2026 | **Viết lại lịch sử commit** (người dùng yêu cầu bỏ Claude khỏi đồng tác giả): xóa trailer `Co-Authored-By: Claude` ở cả 10 commit bằng `git filter-branch --msg-filter`, nội dung file không đổi (diff rỗng so với bản sao lưu), force push `main` + `ci/sarif-upload` có `--force-with-lease`, trước khi bật branch protection. Mã commit đổi (cũ → mới): 88cda11→b5be5d5, dd33de8→d4ae7c1, 1fd35f4→590e8f6, 29ef59e→e2387fd, 115c9d0→2d69b17, 349667c→2518828, a7b9573→ed2dc0a, 7aa3cba→e66dca7, 7911581→9840b23, 1e47c84→dbe546f; đã thay trong file này. Run 44024593626 vẫn gắn với SHA cũ `7aa3cba` trên tab Actions. Từ nay commit/PR không ghi công Claude. |
| 17/11/2026 | Tạm dừng theo yêu cầu người dùng. PR #1 xanh lại sau khi viết lại lịch sử (verify 1m25s, policy-test 15s, Trivy Code Scanning), `main` run 44032306665 xanh. Branch protection chưa bật. Trạng thái chi tiết ở mục "Điểm dừng". |
| 18/11/2026 | Người dùng bật branch protection `main`; kiểm qua API khớp cấu hình thống nhất (enforce_admins, required `verify` + `policy-test`, strict). Merge PR #1 (`a3a3b5c`). Push thẳng `main` bị từ chối GH006 — bằng chứng `reports/github/20261117T170531Z/`. TC03: chọn base từ scan thật (alpine 3.14.0: 4 Critical; 3.16.0: 1; debian 11.0-slim: 22) → `demo/Dockerfile.vulnerable`, gate local exit 1. Viết `demo/commands.md` cho TC02/TC03. Sửa 2 lỗi trình bày trong file này (ghi chú rc.1 cũ, bảng nhật ký bị tách). |
| 18/11/2026 | TC02 đạt trên CI (PR #4): Gitleaks chặn secret giả, PR BLOCKED; đóng PR, xóa nhánh. TC03 lần 1 (PR #3) không hợp lệ vì Gitleaks quét lây sang nhánh TC02 → sửa `--log-opts=HEAD` trong `ci-cd.yml` (nhánh `fix/gitleaks-scope`). Xóa nhánh đã merge trên remote. |
| 18/11/2026 | Merge PR #5 (Gitleaks `--log-opts=HEAD`). TC03 đạt trên CI (PR #6): gate Trivy fail với 4 Critical, exit 1, PR BLOCKED, không có artifact approved-image; đóng PR, xóa nhánh. Hai ca CI bắt buộc (TC02, TC03) đã có bằng chứng thật. |
| 18/11/2026 | Viết `docs/test-results.md` (kết luận từng ca TC01–TC10 theo trường mục 12.4, chỉ số mục 12.5) và chép bằng chứng chọn lọc vào `docs/evidence/` (90 file, 280 KB; Gitleaks quét sạch). Chạy lại Policy 1 trên kind 3 lượt (6/6 mỗi lượt, kiểm deny đúng do `allowed-image`, đo độ trễ). `check-rbac.sh` thêm 4 yêu cầu thật bằng impersonation → 4/4 Forbidden. Thêm `scripts/ci-metrics.sh`: 13 run verify thành công, job tb 117,6 s. |
| 18/11/2026 | Merge PR #8 (`docs/test-results.md`, `docs/evidence/`, script đo). Dừng phiên theo yêu cầu người dùng: phần không cần AWS bắt buộc đã xong; chờ AWS để làm spike. |
| 20/11/2026 | AWS account chưa hoàn tất đăng ký (trang "Complete your account setup") → chưa dùng được. Trong lúc chờ: viết `docs/architecture.md` (13 quyết định có lý do, trạng thái triển khai thật) và nháp `docs/report/chuong-2-co-so-ly-thuyet.md`. |
| 20/11/2026 | AWS dùng được: Paid plan, MFA root, Budget 15 USD, IAM Identity Center + user SSO `duy-admin`, profile WSL `devsecops`. Kiểm tra chỉ đọc: `ap-southeast-1` có Managed Signing + Signer Notation. Spike bước 1–3: repo `podinfo` (IMMUTABLE, KMS), `D_unsigned` (0 chữ ký), `D_wrongsigner` (1 chữ ký profile B), Trivy 0 Critical; bằng chứng `docs/evidence/spike/fixtures/`. Chưa bật Managed Signing. |
| 20/11/2026 | Spike bước 4: `scripts/notation-verify.sh` (root AWS Signer ghim fingerprint, trust policy strict chỉ tin profile chính). `D_unsigned` và `D_wrongsigner` bị từ chối đúng lý do; đối chứng tin profile B → pass. Bằng chứng `docs/evidence/spike/verify-fixtures/`. |
| 20/11/2026 | Spike bước 5–7 (người dùng đồng ý): profile chính + ECR Managed Signing (1 rule, filter `podinfo`); fixture không bị ký thêm. `D_signed` tự ký `COMPLETE` ngay khi push; `notation verify` signed pass, unsigned/wrong-signer fail. Script `enable-managed-signing.sh`, `spike-signed.sh`, `wait-signature.sh`. |
| 20/11/2026 | Dừng phiên theo yêu cầu người dùng. Chờ quyết định credential verifier cho kind (đề xuất IAM role riêng). Tắt Docker Desktop + WSL. |
| 26/11/2026 | Người dùng đồng ý → spike bước 8–9: role `devsecops-verifier`, `refresh-lab-credentials.sh`, extension trên kind, Policy 2. Lỗi `Token is not authorized` (audience token Kyverno 1.19) + extension ghi token ra log → bản vá p2 thư viện verifier, rebuild 0 Critical/0 High. TC01 (admission), TC04, TC06, TC09 ĐẠT; Policy 1 với ECR thật ĐẠT. **Spike đạt tiêu chí 6.2.** Sự cố ổ C: đầy khi build. |
| 26/11/2026 | Người dùng dọn ổ C (~20 GB trống), đồng ý làm tiếp. Giai đoạn 2–3: OIDC provider + role `devsecops-publisher` (sub immutable), lifecycle `sha-` (preview 0 image), job `publish` trong `ci-cd.yml`, `fetch-release.sh`, `deploy.sh` (danh tính deployer). Bằng chứng `docs/evidence/aws/`. Chờ người dùng đặt Secret/Variables GitHub rồi merge để chạy `publish` lần đầu. |
| 26/11/2026 | Người dùng đặt Secret/Variables. Merge PR #16 → run 45798939183: `publish` xanh 45 s, ký `COMPLETE` ~5 s, không lộ account ID trong log. `deploy.sh` → 2 Pod `Running` đúng digest, extension `verified: true`. **TC01 trọn luồng ĐẠT.** Sửa `fetch-release.sh` (Git Bash không có `jq`). Bằng chứng `docs/evidence/tc01-e2e/`. |
| 26/11/2026 | Spike bước 10: kiểm upstream (1.19.2/chart 3.9.2 vẫn mới nhất, extension `main` không đổi) → chốt mục 4 `docs/versions.md`. Thêm `scripts/preflight.sh` (chỉ đọc, 33 mục) → ĐẠT. Phát hiện: Docker 29 dùng containerd store nên image ID local là digest **index**, còn node kind báo **config** → preflight so config `d3c72d96…`. |
| 26/11/2026 | Đo đạc mục 12.5 (`docs/test-results.md` mục 3): Policy 2 thêm 2 lượt (đủ 4, đều 6/6); **độ trễ Managed Signing 1735–2509 ms, tb 2216 ms** (n=4, đo bằng `imagePushedAt` của ECR, `scripts/signing-latency.sh`); `ci-metrics.sh` mở rộng cho `publish` (n=3, tb 38 s; `verify` n=35 tb 106 s); SBOM/Trivy run mới nhất không đổi (0 Critical, 2 High); bảng truy vết tự động/thủ công. |
| 26/11/2026 | Nháp **Chương 5** `docs/report/chuong-5-thuc-nghiem-danh-gia.md` (phương pháp, môi trường, kết quả 10 ca, số liệu, truy vết, phân tích, giới hạn). TC10 bổ sung yêu cầu thật tới Pod đang chạy: 6/6 Forbidden đúng động từ, logs/get pods được phép (`docs/evidence/TC10/20261126T*/`). Còn: chèn ảnh Hình 5.1–5.5. |
| 26/11/2026 | Dừng phiên theo yêu cầu người dùng. Cập nhật điểm dừng; tắt Docker Desktop + WSL. Việc tiếp: Chương 4 → 3 → 1 → 6, ảnh Hình 5.1–5.5, demo/slide. |
| 28/11/2026 | Nháp **Chương 4** `docs/report/chuong-4-trien-khai.md`: container hóa, AWS (ECR, fixture, Managed Signing, IAM, OIDC, lifecycle), pipeline (verify/policy-test/publish), Kubernetes (kind, RBAC, 3 đường xác thực, `deploy.sh`), Kyverno + extension (tự build, bản vá p2), bảng 14 khó khăn & giải pháp. Còn: Hình 4.1 (sơ đồ luồng). |
| 28/11/2026 | Nháp **Chương 3** `docs/report/chuong-3-phan-tich-thiet-ke.md`: mô hình mối đe dọa (T1–T4 + đường vòng), yêu cầu KQ1–KQ7 + phi chức năng, kiến trúc (Hình 3.1), vùng tin cậy, 3 đường xác thực, giả định tin cậy, phân quyền, gate, 2 policy + lựa chọn A/B/C, fixture, truy vết (Hình 3.2), ma trận kiểm thử, bảng Q1–Q13. Cập nhật `docs/architecture.md` (hết trạng thái chờ, thêm 3 giới hạn). |
| 28/11/2026 | Nháp **Chương 1** (bối cảnh, mục tiêu theo đề cương, câu hỏi nghiên cứu, phạm vi, phương pháp, tóm tắt kết quả, cấu trúc báo cáo) và **Chương 6** (đối chiếu 5 kết quả dự kiến của đề cương, trả lời câu hỏi nghiên cứu, 5 đóng góp, hạn chế, 10 hướng phát triển). Còn: phụ lục, rà Chương 2, ảnh/hình. |
| 28/11/2026 | **Phụ lục A** `docs/report/phu-luc-a-huong-dan-dung-lai.md` (yêu cầu, công cụ, AWS đúng thứ tự fixture → signing, GitHub, kind, phát hành/triển khai, chạy lại ca kiểm thử, mỗi buổi làm việc, 11 sự cố thường gặp, thu dọn) + **`README.md`** (tổng quan, bảng TC, liên kết). **Chưa** thử dựng lại một lượt trên máy/account sạch. |

<!-- Mẫu một dòng nhật ký: | dd/mm/yyyy | Giai đoạn · việc đã xong · bằng chứng (đường dẫn) · vấn đề còn mở | -->
