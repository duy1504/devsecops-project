# Phụ lục A. Hướng dẫn dựng lại hệ thống

> Hướng dẫn dựng lại toàn bộ hệ thống từ đầu, theo đúng thứ tự đã dùng trong đồ án. Lệnh là **Bash trên WSL2 Ubuntu**, chạy tại thư mục gốc của repo, trừ khi ghi rõ PowerShell hoặc Git Bash. Repo: <https://github.com/duy1504/devsecops-project>.
>
> **Trạng thái kiểm chứng:** từng bước dưới đây đã chạy thật trong quá trình làm đồ án (17–26/11/2026). Toàn bộ chuỗi **chưa** được chạy lại một lượt trên một máy và account hoàn toàn mới. Đây là việc cần làm trước khi nộp (kế hoạch mục 16, 18).

## A.1. Yêu cầu

| Thành phần | Yêu cầu |
|---|---|
| Máy | Windows 11 + WSL2 Ubuntu 24.04 (x86_64); RAM ≥ 16 GB; ổ đĩa trống ≥ 20 GB (Docker và build extension tốn chỗ) |
| Docker | Docker Desktop (đã dùng Engine 29.9.1), bật tích hợp WSL; cung cấp sẵn `kubectl` |
| GitHub | Repo của đồ án (hoặc bản fork); GitHub CLI `gh` đã đăng nhập trên Windows |
| AWS | Một account lab riêng; IAM Identity Center với một user có permission set `AdministratorAccess`; đặt Budget cảnh báo chi phí |
| Region | `ap-southeast-1` (đã kiểm có ECR Managed Signing và nền tảng Signer `Notation-OCI-SHA384-ECDSA`) |

**Quy tắc an toàn:**
- Không ghi account ID, access key, token hay kubeconfig vào file trong repo hay vào commit.
- Mọi credential AWS trên máy lab đều là phiên SSO hoặc credential tạm.
- Repo public thì account ID phải để trong GitHub **Secret**, không để trong Variable (mục A.4).

## A.2. Công cụ

```bash
bash scripts/install-tools.sh        # cài vào ~/.local, kiểm SHA-256 từng file; sai hash thì dừng
export PATH="$HOME/.local/bin:$PATH" # thêm vào ~/.bashrc
```

Script cài Go, AWS CLI v2, Helm, kind, jq, Trivy, Syft, Gitleaks, Notation CLI + plugin AWS Signer, và Kyverno CLI, đúng phiên bản trong `docs/versions.md`. Đổi phiên bản phải đổi cả số phiên bản lẫn SHA-256 trong script.

Cấu hình profile SSO trong `~/.aws/config`. Thay các giá trị trong `<…>` bằng giá trị của account lab; không đưa file này vào repo.

```ini
[profile devsecops]
sso_session = devsecops
sso_account_id = <ACCOUNT_ID>
sso_role_name = AdministratorAccess
region = ap-southeast-1

[sso-session devsecops]
sso_start_url = <SSO_START_URL>
sso_region = <REGION_CỦA_IDENTITY_CENTER>
sso_registration_scopes = sso:account:access
```

```bash
aws sso login --profile devsecops    # WSL không tự mở trình duyệt: mở link in ra bằng tay
source scripts/aws-env.sh            # đặt biến chung; account ID lấy từ STS lúc chạy
echo "$ECR_IMAGE"                    # <ACCOUNT_ID>.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo
```

## A.3. Hạ tầng AWS (chạy một lần, **đúng thứ tự**)

> ⚠️ **Thứ tự bắt buộc.** Fixture "chưa ký" và "sai người ký" phải tạo **trước** khi bật Managed Signing. Sau khi bật, mọi image push vào `podinfo` đều được ký bằng profile tin cậy, và không tạo lại được fixture theo cách này nữa. Không bao giờ push lại hay gắn thêm tag cho fixture.

```bash
source scripts/aws-env.sh

# 1. ECR repo podinfo: tag IMMUTABLE, mã hóa KMS (chưa bật ký)
bash scripts/aws-create-repo.sh

# 2. Fixture TC04 + TC06: D_unsigned (không ký) và D_wrongsigner (ký tay bằng profile B)
#    Script từ chối chạy nếu registry đã có signing configuration
bash scripts/create-fixtures.sh      # ghi digest vào reports/spike/fixtures.env (không commit)

# 3. Xác minh bằng Notation CLI: cả hai fixture phải THẤT BẠI (kèm ca đối chứng tin profile B)
bash scripts/notation-verify.sh

# 4. Profile chính + bật ECR Managed Signing (1 rule, filter đúng "podinfo", không wildcard)
bash scripts/enable-managed-signing.sh

# 5. D_signed: push image thứ ba → Managed Signing tự ký → COMPLETE → notation verify phải THÀNH CÔNG
bash scripts/spike-signed.sh

# 6. Role verifier cho extension trên kind (chỉ đọc + kiểm thu hồi)
bash scripts/aws-create-verifier-role.sh

# 7. GitHub OIDC provider + role publisher (trust chỉ nhánh main)
#    Với repo khác: đặt OIDC_SUB_PREFIX theo dạng sub thực tế của repo đó (xem dưới)
bash scripts/aws-create-publisher-role.sh

# 8. Lifecycle: chỉ tag sha-, giữ 10 (preview trước, dừng nếu chọn nhầm image)
bash scripts/aws-lifecycle.sh
```

**Dạng claim `sub` của OIDC.** Trust policy phải khớp `sub` **thực tế** của repo. Kiểm trên Windows (PowerShell):

```powershell
gh api repos/<owner>/<repo>/actions/oidc/customization/sub
```

Nếu `use_immutable_subject` là `true`, dùng giá trị `sub_claim_prefix`, có dạng `repo:<owner>@<owner_id>/<repo>@<repo_id>`. Ngược lại, dùng `repo:<owner>/<repo>`. Chạy bước 7 với `OIDC_SUB_PREFIX=<giá trị đó>`.

Mọi script đều chạy lại được (idempotent), tự kiểm kết quả, và lưu bằng chứng vào `reports/` (không commit). Các bản chọn lọc, đã che account ID, nằm ở `docs/evidence/`.

## A.4. Cấu hình GitHub (chạy một lần)

PowerShell tại thư mục repo, với `gh` đã đăng nhập:

```powershell
# Account ID để ở SECRET (GitHub tự che trong log của repo public); giá trị lấy thẳng từ STS, không gõ tay
wsl -d Ubuntu -- bash -lc "aws sts get-caller-identity --profile devsecops --query Account --output text" | gh secret set AWS_ACCOUNT_ID -R <owner>/<repo>
gh variable set AWS_REGION            -R <owner>/<repo> --body ap-southeast-1
gh variable set ECR_REPOSITORY        -R <owner>/<repo> --body podinfo
gh variable set SIGNING_PROFILE_NAME  -R <owner>/<repo> --body podinfo_signing_profile
gh variable set AWS_PUBLISH_ROLE_NAME -R <owner>/<repo> --body devsecops-publisher
```

Trên giao diện GitHub (Settings):
- **Branch protection cho `main`:**
  - bắt buộc pull request;
  - required status checks `verify` và `policy-test`, bật "require branches to be up to date";
  - bật "Do not allow bypassing" (`enforce_admins`);
  - cấm force push và xóa nhánh.
- **Code security:** bật Secret scanning và Push protection.

Không tạo Secret nào chứa access key AWS. Job `publish` lấy credential qua OIDC.

## A.5. Cụm Kubernetes (kind)

```bash
# 1. Cụm kind (node v1.35.8 ghim digest) + namespace app/demo + RBAC + Kyverno 1.19.2 (chart 3.9.2, kiểm SHA-256)
bash scripts/cluster-up.sh

# 2. Extension kyverno-notation-aws: tự build từ main@58b210b + bản vá p2, gate 0 Critical
#    (lần đầu tải module Go và image builder, tốn vài GB đĩa)
bash scripts/build-notation-ext.sh

# 3. Credential verifier (≤ 1 giờ) + Secret ecr-pull cho kubelet
bash scripts/refresh-lab-credentials.sh

# 4. Policy 1 (nguồn + digest) với ECR thật
source scripts/aws-env.sh && bash scripts/apply-policies.sh

# 5. Extension + TrustStore (kiểm fingerprint root AWS Signer) + TrustPolicy + Policy 2
bash scripts/install-notation-ext.sh

# 6. Kiểm tra tổng thể (chỉ đọc, 33 mục): phải ĐẠT
bash scripts/preflight.sh
```

Nếu build extension cho ra image ID khác (build không tái lập từng byte), cập nhật giá trị ghim trong `scripts/install-notation-ext.sh`, `scripts/preflight.sh` và `docs/versions.md` mục 2b, **sau khi** gate Trivy đạt.

## A.6. Phát hành và triển khai

1. Tạo thay đổi trên một nhánh → mở PR. Hai check `verify` và `policy-test` phải xanh; job `publish` bị bỏ qua trên PR.
2. Merge vào `main`. Workflow chạy lại `verify` và `policy-test` trên commit đã merge, rồi tới `publish`:
   - push tag `sha-<commit12>-run-<id>-<attempt>`;
   - chờ ký `COMPLETE`;
   - upload artifact `release-<run>-<attempt>`.
3. Tải hồ sơ phát hành (**Git Bash** trên Windows, vì cần `gh`):

   ```bash
   bash scripts/fetch-release.sh            # run push main thành công mới nhất
   bash scripts/fetch-release.sh <run-id>   # hoặc một run cụ thể
   ```

4. Triển khai (**WSL**):

   ```bash
   bash scripts/refresh-lab-credentials.sh                       # nếu credential đã quá ~50 phút
   bash scripts/deploy.sh reports/release/<run-id>/release.json
   ```

   `deploy.sh` thực hiện:
   - kiểm `release.json` khớp `run.json`, digest có trên ECR với đúng tag và đã ký;
   - apply bằng danh tính deployer;
   - chờ rollout, kiểm Pod chạy đúng digest;
   - smoke test `/healthz` và `/version`.

**Rollback:** triển khai lại `release.json` của bản tốt trước đó. Việc này **vẫn đi qua admission**; không chuyển policy sang Audit hay tắt verifier để rollback.

## A.7. Chạy lại các ca kiểm thử

| Ca | Lệnh | Ghi chú |
|---|---|---|
| Test offline Policy 1 | `bash scripts/policy-test.sh` | Cũng chạy trong job `policy-test` |
| TC05, TC07, TC08 | `source scripts/aws-env.sh; set -a; source reports/spike/fixtures.env; set +a; APP_DIGEST=$D_SIGNED bash scripts/test-policy1-cluster.sh` | Có đối chứng và namespace ngoài phạm vi |
| TC01 (admission), TC04, TC06, TC09 | `bash scripts/test-policy2-cluster.sh` | TC09 tạm scale extension về 0 rồi bật lại |
| TC01 trọn luồng | mục A.6 | |
| TC10 | `bash scripts/check-rbac.sh` | Impersonation group `devsecops-deployers` |
| `notation verify` | `bash scripts/notation-verify.sh` | signed pass; unsigned, wrong-signer fail; đối chứng |
| TC02, TC03 | Mở PR từ nhánh demo theo `demo/commands.md` | **Đóng PR, xóa nhánh** sau khi có bằng chứng; chuỗi `DEMO_SECRET_` không được vào `main` |
| Đo đạc | `bash scripts/ci-metrics.sh 40` (Git Bash); `bash scripts/signing-latency.sh` (WSL) | |

Bằng chứng được ghi vào `reports/<loại>/<thời điểm UTC>/`.

## A.8. Mỗi buổi làm việc hoặc demo

```bash
# Windows: mở Docker Desktop (cụm kind tự lên lại cùng Kyverno, extension, policy, Deployment)
aws sso login --profile devsecops
bash scripts/refresh-lab-credentials.sh   # credential verifier chỉ sống ≤ 1 giờ
bash scripts/preflight.sh                 # phải ĐẠT trước khi demo
```

Credential verifier hết hạn thì mọi Pod **mới** trong `app` và `demo` bị chặn cho tới khi refresh. Đây là hành vi fail-closed đúng thiết kế, không phải lỗi. Pod đang chạy không bị ảnh hưởng.

## A.9. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Docker Desktop báo `Wsl/Service/CreateInstance/0x80072746` | WSL ở trạng thái lỗi | Tắt Docker Desktop → `wsl --shutdown` (PowerShell) → mở lại |
| `docker: command not found` trong WSL | Docker Desktop chưa chạy | Mở Docker Desktop |
| `docker login` ECR lỗi `The stub received bad data` | Token ECR quá dài cho Windows Credential Manager | Các script đã dùng `DOCKER_CONFIG` tạm; khi tự chạy tay, đặt `DOCKER_CONFIG=$(mktemp -d)` |
| Mọi Pod bị chặn, stderr có `connection refused` hoặc lỗi từ extension | Extension không chạy, hoặc credential verifier hết hạn | `kubectl -n kyverno-notation-aws get pods`; chạy `refresh-lab-credentials.sh` |
| Mọi Pod bị chặn `Token is not authorized` | Image extension không phải bản vá p2, hoặc thiếu `TOKEN_REVIEW_AUDIENCES` | Build lại bằng `build-notation-ext.sh`; kiểm `infra/kyverno-notation-aws/install.yaml` |
| Job `publish` lỗi ở bước OIDC (`Not authorized to perform sts:AssumeRoleWithWebIdentity`) | `sub` trong trust policy không khớp repo | Kiểm dạng `sub` (mục A.3), chạy lại `aws-create-publisher-role.sh` với `OIDC_SUB_PREFIX` đúng |
| Job `publish` dừng ở `Resolve configuration` | Thiếu Secret hoặc Variable | Đặt lại theo mục A.4 |
| Không tải được Trivy DB hoặc chart Kyverno | `mirror.gcr.io` / `kyverno.github.io` bị chặn từ mạng | Script đã dùng `ghcr.io`; khi chạy tay: `--db-repository ghcr.io/aquasecurity/trivy-db:2` |
| `Bus error` khi build, Docker dừng đột ngột | Ổ đĩa đầy | Giải phóng đĩa; ổ đĩa ảo của Docker chỉ tăng, không tự co lại |
| `preflight.sh` báo SAI ở fixture | Fixture bị push lại hoặc gắn tag mới, nên bị ký thêm | Không sửa được tại chỗ; ghi nhận và xem lại cách tạo fixture (mục A.3) |

**Không bao giờ "chữa" lỗi bằng cách nới lỏng kiểm soát:** không đổi trust level sang `skip`, không tin mọi người ký, không đổi webhook sang `Ignore`, không chuyển policy sang Audit, không dùng `--ignore-unfixed`, `continue-on-error` hay `|| true` cho gate.

## A.10. Thu dọn

Sau khi bảo vệ, theo kế hoạch mục 17:
1. Tải về bản sao bằng chứng, `release.json`, log và video.
2. Xóa cụm kind: `kind delete cluster --name devsecops`.
3. Xóa image và repository `podinfo`.
4. Gỡ signing rule của đồ án, giữ các rule khác nếu registry có.
5. Thu hồi hoặc hủy cả profile chính lẫn profile B.
6. Xóa role `devsecops-publisher`, `devsecops-verifier`, OIDC provider (nếu chỉ tạo cho đồ án), Secret và Variable trên GitHub.
7. Kiểm tra Billing vài ngày sau.

Mọi lệnh xóa phải nêu đích danh account, region và tên tài nguyên; không xóa hàng loạt trên toàn account.
