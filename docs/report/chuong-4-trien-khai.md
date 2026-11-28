# Chương 4. Triển khai (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15. Mọi cấu hình trích trong chương lấy nguyên từ repo `duy1504/devsecops-project` (nhánh `main`). Phiên bản và hash chi tiết nằm ở `docs/versions.md`; kết quả kiểm thử ở Chương 5. Account ID AWS được thay bằng `<ACCOUNT_ID>`. Trước khi nộp: thêm hình sơ đồ luồng (Hình 4.1) và ảnh chụp các màn hình cấu hình.

## 4.1. Tổng quan

Hệ thống được triển khai theo kiến trúc đã thiết kế ở Chương 3, gồm bốn khối:

1. **Workload:** ứng dụng podinfo build từ source thành image distroless chạy non-root.
2. **Pipeline GitHub Actions:** job `verify` (kiểm tra, không có quyền AWS), job `policy-test` (kiểm thử policy offline) và job `publish` (đẩy image lên ECR qua OIDC).
3. **AWS:** Amazon ECR lưu image; ECR Managed Signing dùng AWS Signer ký tự động mỗi image được push.
4. **Kubernetes (kind):** Kyverno chặn ở admission bằng hai policy, một kiểm nguồn image và một kiểm chữ ký thông qua extension `kyverno-notation-aws`.

*(Hình 4.1: sơ đồ luồng commit → `verify` → `publish` → ECR + chữ ký → `deploy.sh` → admission → Pod.)*

Mọi thao tác hạ tầng đều được viết thành script trong `scripts/`, chạy lại được (idempotent) và tự kiểm tra kết quả. Không có bước nào làm tay trên console AWS. Cấu trúc repo:

```
app/                       mã nguồn podinfo 6.17.0 (vendor từ upstream, ghim commit)
Dockerfile                 build multi-stage, base image ghim digest
.github/workflows/ci-cd.yml   pipeline verify / policy-test / publish
.gitleaks.toml             cấu hình quét secret
infra/aws/                 template IAM, signing configuration, lifecycle policy
infra/kyverno-notation-aws/   CRD, manifest và bản vá của extension
policies/                  Policy 1, Policy 2, TrustPolicy, TrustStore, test offline
k8s/                       namespace, RBAC, Deployment, Service
tests/admission/           manifest cho các ca kiểm thử trên cụm
scripts/                   toàn bộ thao tác dựng, triển khai, kiểm thử, đo đạc
docs/                      kiến trúc, phiên bản, kết quả, bằng chứng
```

## 4.2. Container hóa workload

### 4.2.1. Mã nguồn

Workload là **podinfo 6.17.0**, một ứng dụng web nhỏ viết bằng Go thường dùng để thử nghiệm Kubernetes. Mã nguồn được đưa vào thư mục `app/` bằng `scripts/vendor-podinfo.sh` tại đúng commit `fd3a834` của tag 6.17.0; nguồn gốc ghi trong `docs/upstream.md`. Đồ án **build lại từ source** thay vì dùng image dựng sẵn của tác giả. Nhờ vậy SBOM và kết quả quét phản ánh đúng thứ mà pipeline tạo ra.

### 4.2.2. Dockerfile

```dockerfile
FROM golang:1.27.4-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS builder
ENV GOTOOLCHAIN=local
WORKDIR /src
COPY app/go.mod app/go.sum ./
RUN go mod download
COPY app/ .
ARG REVISION=fd3a834ed8d14b80ea334cf8a2fddd4597924da6
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=${REVISION}" \
    -o /out/podinfo ./cmd/podinfo

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
WORKDIR /home/app
COPY --from=builder /out/podinfo /home/app/podinfo
COPY --from=builder /src/ui /home/app/ui
EXPOSE 9898
USER 65532:65532
ENTRYPOINT ["/home/app/podinfo", "--port=9898", "--ui-path=/home/app/ui"]
```

Các lựa chọn và lý do:

| Lựa chọn | Lý do |
|---|---|
| Multi-stage, runtime `distroless/static` | Image cuối không có shell, trình quản lý gói hay công cụ build, nên bề mặt tấn công và số CVE nhỏ |
| Base image **ghim theo digest** | Tag như `1.27.4-alpine` có thể bị trỏ sang nội dung khác; digest cố định nội dung, nên build lặp lại được |
| `GOTOOLCHAIN=local` | Không để Go tự tải toolchain khác khi `go.mod` yêu cầu bản mới hơn; nếu sai phiên bản thì build lỗi rõ ràng thay vì âm thầm tải mã từ mạng |
| `CGO_ENABLED=0`, `-trimpath` | Binary tĩnh chạy được trên `distroless/static`; bỏ đường dẫn máy build khỏi binary |
| `USER 65532:65532` dạng **số** | Khi Pod đặt `runAsNonRoot`, kubelet chỉ xác minh được UID dạng số; user dạng tên gây lỗi `CreateContainerConfigError` |
| Một kiến trúc `linux/amd64` | Đơn giản hóa SBOM, quét và chữ ký (một manifest, không phải index đa kiến trúc) |

Kết quả kiểm tra trên máy lab: image 50,6 MB (file `image.tar` 12 MB). Các endpoint `/healthz`, `/readyz` và `/` trả HTTP 200; `/version` trả `6.17.0` / `fd3a834`; tiến trình chạy với UID 65532.

## 4.3. Hạ tầng AWS

Toàn bộ tài nguyên nằm ở region `ap-southeast-1`, trong một account lab riêng quản lý bằng AWS Organizations và IAM Identity Center. Quản trị viên lab dùng phiên SSO ngắn hạn (permission set `AdministratorAccess`, 8 giờ); không có access key dài hạn nào được tạo. Các biến dùng chung (tên repo, ARN profile, namespace) nằm trong `scripts/aws-env.sh`. Account ID được lấy từ STS lúc chạy, không ghi vào repo.

### 4.3.1. ECR repository

`scripts/aws-create-repo.sh` tạo repository `podinfo` với hai thuộc tính bảo mật:

- `--image-tag-mutability IMMUTABLE`: tag đã push không bị ghi đè, nên kẻ có quyền push không thể thay nội dung đằng sau một tag phát hành. Hệ quả là mỗi lần chạy pipeline phải dùng tag mới, có dạng `sha-<commit12>-run-<run_id>-<attempt>`.
- `--encryption-configuration encryptionType=KMS`: image được mã hóa khi lưu trữ bằng khóa KMS.

### 4.3.2. Fixture được tạo trước khi bật ký

ECR Managed Signing ký **mọi** image được push sau khi bật rule. Vì vậy, hai fixture cho ca "chưa ký" và "sai người ký" phải được tạo **trước**. `scripts/create-fixtures.sh` thực hiện:

1. Từ chối chạy nếu registry đã có signing configuration.
2. Build hai image khác nội dung (nhãn `demo.fixture=…`), quét Trivy (gate 0 Critical), rồi push với tag `unsigned-baseline` và `wrong-signer-baseline`.
3. Tạo **profile B** (`podinfo_wrong_signer`) và ký tay `wrong-signer-baseline` bằng `notation sign` với plugin AWS Signer.
4. Kiểm số chữ ký (0 và 1) và ghi digest vào `reports/spike/fixtures.env`.

Ký tay ở đây **chỉ** để tạo fixture cho TC06; đường phát hành không có lệnh ký thủ công nào. Fixture không bao giờ được push lại hay gắn thêm tag.

### 4.3.3. AWS Signer và ECR Managed Signing

`scripts/enable-managed-signing.sh` tạo signing profile chính `podinfo_signing_profile` (platform `Notation-OCI-SHA384-ECDSA`) và bật signing configuration ở cấp registry từ template:

```json
{"rules":[{"signingProfileArn":"${SIGNING_PROFILE_ARN}",
  "repositoryFilters":[{"filter":"${ECR_REPOSITORY}","filterType":"WILDCARD_MATCH"}]}]}
```

Trước khi gọi `put-signing-configuration`, script dừng nếu registry đã có cấu hình (phải hợp nhất chứ không ghi đè), rồi dùng `jq` kiểm cấu hình đã render:
- đúng một rule;
- đúng ARN profile chính, không phải profile B;
- filter đúng `podinfo` và **không** chứa `*`. Wildcard như `podinfo*` sẽ khớp cả repository khác và ký nhầm bằng profile tin cậy.

Sau khi bật, script kiểm lại rằng hai fixture vẫn có 0 và 1 chữ ký.

Chữ ký được lưu trong ECR dưới dạng **OCI referrer**: một artifact có `artifactMediaType` là `application/vnd.cncf.notary.signature`, trỏ tới digest của image. Chữ ký được tạo dưới danh tính của người push, vì vậy role publisher cần quyền `signer:SignPayload` trên profile. `scripts/wait-signature.sh` gọi `aws ecr describe-image-signing-status` cứ 5 giây một lần, trong tối đa 150 giây. Chỉ trạng thái `COMPLETE` **của đúng profile chính** mới đạt; `FAILED`, thiếu trạng thái, lỗi API hay hết giờ đều làm job thất bại.

### 4.3.4. Ma trận quyền IAM

| Danh tính | Cách xác thực | Quyền (inline policy) | Không có |
|---|---|---|---|
| Quản trị lab | SSO, phiên 8 giờ | `AdministratorAccess` (chỉ dùng trên máy lab) | Không dùng trong CI |
| `devsecops-publisher` | GitHub OIDC, chỉ nhánh `main` | `ecr:GetAuthorizationToken`; push / đọc / `DescribeImageSigningStatus` **chỉ** trên repo `podinfo`; `signer:SignPayload` **chỉ** trên profile chính | Sửa IAM, signing rule, xóa image, quyền Kubernetes |
| `devsecops-verifier` | `sts:AssumeRole` từ phiên SSO quản trị (≤ 1 giờ) | `ecr:GetAuthorizationToken`; đọc manifest/layer/danh sách image của repo `podinfo`; `signer:GetRevocationStatus` | Push, `SignPayload`, sửa profile |

Policy của publisher:

```json
{ "Sid": "EcrPushPodinfoOnly", "Effect": "Allow",
  "Action": ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
             "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
             "ecr:DescribeImages", "ecr:DescribeImageSigningStatus"],
  "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${ECR_REPOSITORY}" },
{ "Sid": "ManagedSigningAsPusher", "Effect": "Allow",
  "Action": "signer:SignPayload", "Resource": "${SIGNING_PROFILE_ARN}" }
```

Hai script `aws-create-publisher-role.sh` và `aws-create-verifier-role.sh` áp ba lớp kiểm tra trước khi tạo hoặc cập nhật role:
- dùng `jq` kiểm nội dung đã render: không có profile B, không có `ecr:*` hay `signer:*`, không có action `iam:`, trust policy không có wildcard;
- chạy **IAM Access Analyzer `validate-policy`** và dừng nếu có ERROR hay SECURITY_WARNING. Kết quả với publisher chỉ có một gợi ý (SUGGESTION) `CONFIRM_AUDIENCE_CLAIM_TYPE`; với verifier không có gợi ý nào;
- sau khi áp, kiểm rằng role không bị gắn thêm managed policy.

**Tối thiểu quyền được xác nhận bằng thực nghiệm.** Kế hoạch ban đầu cấp thêm `signer:GetSigningProfile` cho publisher. Tài liệu AWS về Managed Signing chỉ yêu cầu `SignPayload`, nên đồ án bỏ quyền này rồi chạy pipeline thật: ký vẫn `COMPLETE`. Quyền đó được loại hẳn. Với verifier, `scripts/refresh-lab-credentials.sh` mỗi lần chạy đều thử `ecr:PutImage` bằng chính credential của verifier và yêu cầu kết quả là `AccessDenied`.

### 4.3.5. GitHub OIDC

GitHub Actions không lưu access key nào. Job `publish` xin một token OIDC từ GitHub rồi đổi lấy credential tạm của role publisher qua `sts:AssumeRoleWithWebIdentity`. Trust policy:

```json
"Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
"Action": "sts:AssumeRoleWithWebIdentity",
"Condition": { "StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
  "token.actions.githubusercontent.com:sub":
    "repo:duy1504@210903593/devsecops-project@1460578199:ref:refs/heads/main" } }
```

Claim `sub` ở đây khác mẫu thường gặp trong tài liệu (`repo:<owner>/<repo>:ref:…`). Repo bật **immutable subject claims**, nên `sub` chứa cả ID số của owner và repo. Cách này còn an toàn hơn: nếu repo bị xóa rồi một repo khác được tạo lại cùng tên, token của repo mới sẽ không khớp trust policy. Dạng claim thực tế được lấy bằng `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` trước khi viết trust policy (mục 4.8).

Trust policy chỉ chấp nhận token của **nhánh `main`**. Job chạy trên pull request, hay chạy với `environment`, có `sub` khác nên không assume được role. Thêm vào đó, chỉ job `publish` có quyền `id-token: write`.

### 4.3.6. Lifecycle policy

`infra/aws/lifecycle-policy.json` có một rule duy nhất: giữ 10 image gần nhất có tag tiền tố `sha-`. Rule của ECR chỉ **chọn image để xóa**, không có cơ chế loại trừ. Vì vậy đồ án không viết rule cho image không tag: chữ ký Notation chính là artifact không tag, và một rule như vậy có thể xóa mất chữ ký. `scripts/aws-lifecycle.sh` chạy **preview** trước và dừng nếu preview chọn bất kỳ image nào không mang tag `sha-`. Kết quả preview: 0 image bị chọn. Tag `sha256-6452…` mà Notation tạo khi ký tay fixture không khớp tiền tố `sha-`, nên tiền tố phải viết đúng là `sha-` chứ không phải `sha`.

## 4.4. Pipeline GitHub Actions

### 4.4.1. Cấu trúc

| Sự kiện | Job chạy |
|---|---|
| `pull_request` | `verify` + `policy-test`. Không phát hành |
| `push` vào `main` | `verify` + `policy-test` chạy lại trên chính commit đã merge → `publish` (cần `verify` đạt) |

Nguyên tắc áp dụng trong `.github/workflows/ci-cd.yml`:

- **Quyền mặc định tối thiểu:** `permissions: contents: read` ở cấp workflow. `verify` chỉ thêm `security-events: write` để upload SARIF; **chỉ** `publish` có `id-token: write`. Không dùng `pull_request_target`.
- **Ghim mọi action theo commit SHA đầy đủ**, ví dụ `actions/checkout@3d3c42e5…  # v7.0.1`, để tránh kiểu tấn công thay tag như vụ tj-actions/changed-files (2025). Action mới được chọn bản đã phát hành vài tuần. Ví dụ, `configure-aws-credentials` v6.3.1 ra ngày 25/11/2026 chỉ sửa lỗi proxy, nên đồ án ghim v6.3.0.
- **Công cụ CLI cài từ binary ghim phiên bản + SHA-256** (Gitleaks, Syft, Trivy, Kyverno CLI). Hash được ghim sẵn trong workflow, không đọc từ file checksum tải cùng nguồn.
- **Không có `continue-on-error` hay `|| true` ở gate.** Các bước upload báo cáo dùng `if: always()`; các bước phát hành thì không.

### 4.4.2. Job `verify`

| Bước | Thực hiện | Khi không đạt |
|---|---|---|
| Unit test | `go -C app test -count=1 ./...` với Go đúng phiên bản của Dockerfile | Dừng |
| Gitleaks | `gitleaks git . --config .gitleaks.toml --redact --log-opts=HEAD`: quét **toàn bộ lịch sử** đi tới được từ commit đang kiểm | Dừng; báo cáo đã che giá trị |
| Build một lần | `docker/build-push-action`, `linux/amd64`, `load: true`, không provenance/SBOM tự động → `docker save` ra `image.tar` + SHA-256 + image ID | Dừng |
| SBOM | `syft docker-archive:image.tar -o cyclonedx-json`; kiểm định dạng CycloneDX, `components` > 0 và có `pkg:golang/*` | Dừng |
| Quét lỗ hổng | `trivy image --input image.tar` **một lần** ra JSON; SARIF và bảng chuyển từ chính JSON đó | Lỗi công cụ/DB → dừng |
| Upload báo cáo | Artifact `security-reports-<run>-<attempt>` (30 ngày) và SARIF lên Code Scanning | Luôn chạy |
| Gate | Đếm `Severity == "CRITICAL"` trong JSON, phải bằng 0. **Không** dùng `--ignore-unfixed` | Dừng |
| `verification.json` | Commit, run, attempt, image ID, SHA-256 của `image.tar`, SBOM, báo cáo, phiên bản scanner, thời điểm DB | — |
| Upload image đã duyệt | `approved-image-<run>-<attempt>` (`image.tar` + checksum + `verification.json`, giữ 2 ngày); **chỉ** khi push vào `main` | Bỏ qua nếu gate fail |

Quét một lần rồi dùng chung kết quả cho cả báo cáo lẫn gate giúp tránh trường hợp DB cập nhật giữa hai lần quét làm báo cáo và quyết định lệch nhau. Mỗi run có **job summary** hiển thị trạng thái từng cổng (đạt / không đạt / chưa chạy). Summary chỉ trình bày, không thay đổi kết quả của gate.

`.gitleaks.toml` giữ toàn bộ rule mặc định (`useDefault = true`) và thêm rule `demo-secret` cho chuỗi giả của TC02. Ba dương tính giả trong mã upstream podinfo (một header JWT công khai dùng làm giá trị mặc định và trong test) được bỏ qua bằng allowlist **ở cấp rule**, với điều kiện AND: đúng file **và** đúng chuỗi. Allowlist cấp toàn cục đã bị loại, vì thử nghiệm cho thấy nó bỏ qua cả file (mục 4.8).

### 4.4.3. Job `policy-test`

Job chạy song song với `verify`, không có quyền AWS và không nằm trong chuỗi `needs` của `publish`. Nhờ vậy lỗi policy không lẫn với lỗi CVE của image, nhưng job vẫn chặn merge vì là required check. Job cài Kyverno CLI v1.19.2 (cùng bản với cụm) rồi chạy `scripts/policy-test.sh`, đúng lệnh dùng ở máy local. Script render policy và resource bằng một giá trị ECR giả cố định, rồi chạy `kyverno test` với 6 Pod mẫu: 1 hợp lệ phải `pass` (`tc-ok`) và 5 phải `fail`. Năm Pod `fail` gồm sai account (`tc-wrong-account`, ứng với TC05), chỉ có tag (`tc-tag-only`, TC07), init container vi phạm (`tc-bad-init`, TC08), digest không đủ 64 hex (`tc-bad-digest`) và repository tên gần giống (`tc-similar-repo`).

### 4.4.4. Job `publish`

Đây là job duy nhất chạm vào AWS. Các bước chính:

```yaml
publish:
  needs: verify
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  permissions: { contents: read, id-token: write }
  steps:
    - Resolve configuration            # ghép ARN từ secret AWS_ACCOUNT_ID + variables
    - actions/download-artifact        # approved-image-<run>-<attempt>, digest-mismatch = error
    - Verify artifact integrity & load # sha256sum -c; verification.json khớp commit/run/attempt,
                                       # gate = pass; docker load; image ID = local_image_id
    - aws-actions/configure-aws-credentials  # OIDC → devsecops-publisher, phiên 900 s,
                                       # allowed-account-ids, mask-aws-account-id
    - Push                             # tag sha-<12>-run-<id>-<attempt>; digest registry = digest push
    - Wait for ECR Managed Signing     # scripts/wait-signature.sh: COMPLETE đúng profile
    - Release manifest                 # release.json = verification.json + URI, tag, digest, profile
    - Mask account ID in release files # thay account ID bằng <ACCOUNT_ID>
    - Upload release record            # artifact release-<run>-<attempt>, 30 ngày
```

Điểm cốt lõi là **build một lần**. `publish` không build lại image, mà tải đúng `image.tar` mà `verify` đã test và quét trong **cùng run**. Trước khi push, job kiểm ba điều kiện liên tiếp:
1. checksum của file;
2. `verification.json` thuộc đúng commit/run/attempt và gate đã đạt;
3. image ID sau `docker load` khớp image ID đã ghi.

Sau khi push, digest do ECR trả về phải trùng digest mà `docker push` ghi nhận. Đồ án không dùng thêm action `amazon-ecr-login`; đăng nhập ECR bằng `aws ecr get-login-password`, nên số action bên thứ ba ít hơn một.

`release.json` liên kết ba loại SHA dễ bị nhầm:
- **image ID local:** digest config, hoặc digest index trên Docker dùng containerd store;
- **SHA-256 của `image.tar`:** checksum của file;
- **digest trên ECR:** digest của manifest.

Ba giá trị này không bằng nhau. Chúng được nối với nhau bằng quy trình build một lần → chuyển đúng file → push → đọc digest.

### 4.4.5. Cấu hình GitHub

- **Branch protection `main`:** bắt PR; hai required check `verify` và `policy-test`; `strict` (nhánh phải cập nhật với `main`); `enforce_admins`; cấm force push và xóa nhánh. Mọi thay đổi, kể cả tài liệu, đều đi qua PR.
- **Secret scanning + Push Protection** của GitHub được bật như lớp bổ sung cho Gitleaks.
- **Repo public nên phải che account ID.** GitHub Variables không được che trong log, nên account ID được đặt ở **Secret** `AWS_ACCOUNT_ID`; GitHub tự thay mọi chuỗi chứa nó bằng `***`. Các ARN được ghép trong job từ secret này cùng các Variables `AWS_REGION`, `ECR_REPOSITORY`, `SIGNING_PROFILE_NAME`, `AWS_PUBLISH_ROLE_NAME`. Không có Secret nào chứa access key.

## 4.5. Kubernetes

### 4.5.1. Cụm kind và Kyverno

`scripts/cluster-up.sh` dựng cụm kind `devsecops` từ node image ghim digest (`kindest/node:v1.35.8@sha256:07b2536e…`), tạo namespace và RBAC, rồi cài Kyverno:

- Chart **3.9.2** (app v1.19.2) được tải qua OCI `oci://ghcr.io/kyverno/charts/kyverno`, vì `kyverno.github.io` bị timeout từ mạng lab.
- File `.tgz` được **kiểm SHA-256** trước khi cài, và cài từ đúng file đã kiểm.
- Lệnh Helm luôn có `--version`, không dùng `--devel`.
- Sau khi cài, script kiểm cả bốn controller đều chạy image `v1.19.2`.

Kyverno 1.20.0 đã phát hành trong thời gian làm đồ án (11/11/2026), nhưng vẫn giữ CRD `ClusterPolicy` (đánh dấu deprecated). Đồ án giữ 1.19.2, vì nâng cấp đòi hỏi kiểm lại tương thích của extension.

### 4.5.2. Namespace, RBAC và manifest

- **Namespace:** `app` cho workload; `demo` cho các ca kiểm thử. Cả hai policy **chỉ** áp lên hai namespace này, để không chặn nhầm thành phần hệ thống.
- **RBAC (`k8s/rbac.yaml`):** Role `app-deployer` gắn cho group `devsecops-deployers`, chỉ trong `app`. Role cho phép tạo/sửa Deployment và Service, và đọc Pod, log, event, ReplicaSet. Ngoài ra có `get services/proxy` để smoke test. Role **không** cấp `secrets`, `pods/exec`, `pods/attach`, `pods/portforward`, `pods/ephemeralcontainers`, quyền tạo namespace, policy Kyverno, TrustPolicy hay webhook.
- **Deployment (`k8s/deployment.template.yaml`):**
  - 2 replica; `automountServiceAccountToken: false`;
  - `runAsNonRoot`, `runAsUser`/`runAsGroup: 65532`, seccomp `RuntimeDefault`;
  - container `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, bỏ mọi capability; giới hạn CPU/bộ nhớ;
  - probe `/healthz` và `/readyz`; `emptyDir` cho `/tmp` và `/data` vì root filesystem chỉ đọc;
  - image là `${APP_IMAGE_REF}` = `<ECR>/podinfo@sha256:<digest>`, render từ `release.json`.
- **Service:** `ClusterIP`; khi demo dùng proxy của API server, không dùng LoadBalancer.

### 4.5.3. Ba đường xác thực

Trên cụm có ba nhu cầu truy cập AWS khác nhau, và đồ án tách chúng ra để mỗi danh tính chỉ có đúng quyền cần thiết:

| Đường | Mục đích | Trên kind |
|---|---|---|
| GitHub Actions → AWS | Push image, kích hoạt ký | OIDC → role publisher |
| Extension → ECR, AWS Signer | Đọc chữ ký, kiểm tra thu hồi | Credential tạm của role verifier, nạp qua Secret `verifier-aws-credentials` (ngoài Git) |
| Kubelet → ECR | Pull image sau khi được nhận | `imagePullSecret` `ecr-pull` gắn vào ServiceAccount `default` của `app` và `demo` |

`scripts/refresh-lab-credentials.sh` làm mới cả hai đường trên cụm:
- assume role verifier (phiên ≤ 1 giờ, do role chaining từ phiên SSO);
- kiểm `PutImage` bị từ chối;
- ghi Secret cho extension (kèm annotation thời điểm hết hạn);
- lấy token ECR **bằng chính role verifier** (chỉ đọc) để tạo `ecr-pull`, rồi khởi động lại extension.

Credential đi qua file tạm quyền 600 và bị xóa ngay; không in ra log, không nằm trong Git. Trên EKS, hai đường này sẽ được thay bằng IRSA/Pod Identity và IAM role của node.

### 4.5.4. Triển khai bằng digest

Đồ án dùng kind nên không có job `deploy` tự động. Triển khai gồm hai script:

1. **`scripts/fetch-release.sh`** (chạy trên Git Bash/Windows bằng `gh`): chỉ chấp nhận run **thành công** của sự kiện **push vào `main`**; tải artifact `release-<run>-<attempt>` và ghi thông tin run lấy từ API GitHub vào `run.json`.
2. **`scripts/deploy.sh <release.json>`** (chạy trên WSL):
   - kiểm `release.json`: ký `COMPLETE`, gate đạt, digest đúng định dạng, đúng profile, và khớp `run.json` về run/attempt/commit;
   - ghép lại account ID và đối chiếu URI với cấu hình;
   - xác nhận trên ECR rằng digest mang đúng tag phát hành và đã ký;
   - dừng nếu credential verifier sắp hết hạn;
   - render manifest **cuối cùng** → `apply --dry-run=server` → `apply` bằng **danh tính deployer** (impersonate group `devsecops-deployers`);
   - chờ rollout; kiểm `spec.image` và `status.imageID` của mọi Pod bằng digest phát hành;
   - smoke test `/healthz` và `/version` qua `services/proxy`;
   - lưu bằng chứng (đã che account ID).

Chạy `deploy.sh` bằng danh tính deployer thay vì quyền quản trị cho thấy Role tối thiểu là **đủ** để triển khai thật. Nếu admission từ chối, `apply` Deployment vẫn thành công nhưng ReplicaSet không tạo được Pod; script khi đó in event `FailedCreate` làm bằng chứng.

## 4.6. Kyverno và extension xác minh chữ ký

### 4.6.1. Policy 1: nguồn image và digest

`policies/allowed-image.template.yaml` là một `ValidatingPolicy` (API `policies.kyverno.io/v1`) viết bằng **CEL**, kiểu policy mới mà Kyverno khuyến nghị thay cho `ClusterPolicy`:

```yaml
  validationActions: [Deny]
  failurePolicy: Fail
  matchConstraints:            # Pod CREATE/UPDATE trong namespace app, demo
  variables:
    - name: prefix
      expression: "'${ECR_IMAGE}@sha256:'"
    - name: images
      expression: >-
        object.spec.containers.map(c, c.image) +
        (has(object.spec.initContainers) ? object.spec.initContainers.map(c, c.image) : [])
  validations:
    - expression: >-
        variables.images.all(i,
          i.startsWith(variables.prefix) &&
          i.substring(size(variables.prefix)).matches('^[a-f0-9]{64}$'))
```

Policy kiểm cả container chính lẫn **init container** (TC08). Nó yêu cầu đúng registry + repository, theo sau là `@sha256:` và **đúng 64 ký tự hex**. Đây là điểm siết hơn mẫu trong kế hoạch: mẫu chỉ kiểm tiền tố, nên chuỗi như `podinfo@sha256:abc` vẫn lọt. Ephemeral container được chặn bằng RBAC. Kyverno tự sinh (*autogen*) quy tắc tương ứng cho Deployment, nên Deployment vi phạm bị từ chối ngay khi `apply`.

### 4.6.2. Extension `kyverno-notation-aws`: tự build và vá

Kyverno có xác minh chữ ký Notary dựa trên chứng chỉ, nhưng không chạy plugin AWS Signer của Notation. Plugin này là thành phần kiểm danh tính theo ARN signing profile (`trustedIdentities`) và kiểm thu hồi qua AWS Signer. Vì vậy, theo quyết định ở mục 3.4 của kế hoạch, đồ án dùng **phương án A**: extension `kyverno-notation-aws` của Nirmata, một service nhận danh sách image từ Kyverno và xác minh bằng thư viện Notation cùng plugin AWS Signer. Kyverno native được giữ làm phương án lùi B. Khi đánh giá, đồ án gặp hai vấn đề:

- **Bản phát hành chính thức mới nhất (`v1.1`, 01/2025) có 6 CVE Critical và 80 High** (Trivy, DB 16/11/2026). Các bản 1.2.x đã bị gỡ, và upstream ghi rõ sắp lưu trữ repo.
- **Nhánh `main` đã vá phần lớn** nhưng không có artifact phát hành. Build nguyên trạng từ `main@58b210b` vẫn còn 6 High.

Đồ án chọn **tự build từ source** bằng `scripts/build-notation-ext.sh` và áp cho extension đúng gate đã dùng cho workload:
- ghim commit upstream, builder `golang:1.26.10` và runtime distroless theo digest;
- nâng `golang.org/x/net` lên 0.62.0 và `go-jose/v4` lên 4.1.6;
- quét Trivy với gate 0 Critical.

Kết quả bản cuối (p2): **0 Critical, 0 High**.

**Bản vá p2** cho thư viện `kyverno-notation-verifier` v1.1.0 (`infra/kyverno-notation-aws/patches/verifier-v1.1.0-token-review.patch`) xử lý hai lỗi phát hiện khi chạy trên cụm:

1. Extension xác thực Kyverno bằng TokenReview nhưng không khai báo audience, trong khi token của Kyverno 1.19 có audience `kyverno-svc.kyverno.io`. Hệ quả là **mọi** Pod, kể cả hợp lệ, bị chặn với `Token is not authorized`. Bản vá đọc danh sách audience từ biến môi trường `TOKEN_REVIEW_AUDIENCES`. Đồ án **không** tắt bước xác thực token (`--reviewKyvernoToken`).
2. Thư viện ghi **toàn bộ đối tượng TokenReview, gồm cả bearer token của Kyverno**, vào log ở mức INFO. Bản vá chỉ ghi tên user.

Script lấy mã thư viện từ module cache sau khi `go mod verify` (đối chiếu `go.sum`), chép vào `third_party/`, áp bản vá, trỏ `go.mod` sang bản đã vá bằng `replace`, rồi chạy `go vet`. Toàn bộ diff so với upstream được lưu làm bằng chứng.

### 4.6.3. Cài extension, TrustStore, TrustPolicy và Policy 2

`scripts/install-notation-ext.sh`:

1. Kiểm image ID của extension khớp giá trị đã ghim, rồi nạp vào kind (`imagePullPolicy: Never`).
2. Áp CRD và manifest (chỉnh từ upstream):
   - bỏ annotation IRSA;
   - thêm probe;
   - đặt `TOKEN_REVIEW_AUDIENCES`;
   - lấy credential từ Secret `verifier-aws-credentials`;
   - giữ binding `system:auth-delegator` để extension gọi được TokenReview.
3. Áp **TrustStore** `aws-signer-ts`: root CA "AWS Signer Code Signing Root CA G1", tải từ nguồn AWS và **kiểm fingerprint SHA-256** đã ghim trước khi áp.
4. Render **TrustPolicy** `tp-supply-chain`:
   - `registryScopes` đúng repo;
   - mức `strict`;
   - trust store `signingAuthority:aws-signer-ts`;
   - `trustedIdentities` chỉ có ARN profile chính.

   Script dừng nếu bản render chứa profile B. Đây là cùng scope, danh tính và trust store với trust policy dùng cho Notation CLI ở `scripts/notation-verify.sh`, nên hai cách xác minh cho kết quả giống nhau.
5. Render **Policy 2** và nhúng chứng chỉ CA **công khai** của extension vào `caBundle`. Mẫu của upstream cho Kyverno đọc Secret TLS của extension, vốn chứa cả private key; cách nhúng này không cần cấp quyền đó. Sau đó chạy `apply --dry-run=server`, rồi `apply` và chờ policy `Ready`.

Policy 2 (`ClusterPolicy` `verify-signer`):

```yaml
spec:
  background: false
  failurePolicy: Fail
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-aws-signer
      match: { any: [ { resources: { kinds: [Pod], namespaces: [app, demo], operations: [CREATE, UPDATE] } } ] }
      context:
        - name: response
          apiCall:
            method: POST
            data:
              - { key: images,          value: "{{ images }}" }
              - { key: imageReferences, value: ["*"] }
              - { key: trustPolicy,     value: tp-supply-chain }
            service: { url: https://svc.kyverno-notation-aws/checkimages, caBundle: <CA công khai> }
      validate:
        failureAction: Enforce
        deny:
          conditions:
            any: [ { key: "{{ response.verified || false }}", operator: NotEquals, value: true } ]
```

Ba lựa chọn quan trọng:
- `failurePolicy: Fail`: extension không trả lời thì từ chối (fail-closed, TC09).
- `imageReferences: ["*"]`: **mọi** image trong Pod đều phải được xác minh, không chỉ image của ECR.
- Điều kiện `response.verified || false`: thiếu trường `verified` cũng bị coi là không đạt.

Đồ án bỏ phần kiểm SBOM attestation minh họa trong mẫu upstream, vì MVP chưa phát hành attestation. Kyverno 1.19 in cảnh báo `ClusterPolicy is deprecated`. Đồ án vẫn dùng loại này vì mẫu tích hợp của extension được upstream viết và kiểm thử cho `ClusterPolicy` (`context.apiCall`). Chuyển Policy 2 sang policy CEL là một hướng phát triển (Chương 6).

### 4.6.4. Xác minh độc lập bằng Notation CLI

`scripts/notation-verify.sh` dựng trust store và trust policy tương đương trên máy lab rồi chạy `notation verify` cho cả ba fixture, kèm một ca đối chứng (tạm tin profile B). Phép kiểm này không đi qua Kyverno, dùng để đối chiếu với kết quả admission (Chương 5, mục 5.3.4).

## 4.7. Các script hỗ trợ

| Script | Chức năng | Môi trường |
|---|---|---|
| `install-tools.sh` | Cài công cụ vào `~/.local`, kiểm SHA-256 | WSL |
| `cluster-up.sh` | Cụm kind + Kyverno ghim phiên bản | WSL |
| `aws-env.sh` | Biến cấu hình chung; lấy account ID từ STS | WSL |
| `aws-create-repo.sh`, `create-fixtures.sh`, `enable-managed-signing.sh` | ECR, fixture, Managed Signing | WSL |
| `aws-create-publisher-role.sh`, `aws-create-verifier-role.sh`, `aws-lifecycle.sh` | IAM/OIDC, lifecycle (Access Analyzer, preview) | WSL |
| `build-notation-ext.sh`, `install-notation-ext.sh` | Tự build, vá, gate và cài extension + Policy 2 | WSL |
| `refresh-lab-credentials.sh` | Credential verifier + `ecr-pull` (trước mỗi buổi làm việc) | WSL |
| `wait-signature.sh` | Chờ ký `COMPLETE` đúng profile | CI, WSL |
| `fetch-release.sh`, `deploy.sh` | Tải `release.json`, triển khai bằng digest | Git Bash, WSL |
| `policy-test.sh` | Kiểm thử policy offline | CI, WSL |
| `test-policy1-cluster.sh`, `test-policy2-cluster.sh`, `check-rbac.sh`, `notation-verify.sh` | Kiểm thử trên cụm, thu bằng chứng | WSL |
| `ci-metrics.sh`, `signing-latency.sh` | Đo đạc | Git Bash, WSL |
| `preflight.sh` | Kiểm tra chỉ đọc 33 mục trước buổi demo | WSL |

Các script thu bằng chứng đều che account ID (`<ACCOUNT_ID>`) và lọc chuỗi giống JWT trước khi ghi file.

## 4.8. Khó khăn và giải pháp

| # | Vấn đề | Nguyên nhân | Giải pháp | Bài học |
|---|---|---|---|---|
| 1 | Mọi Pod, kể cả hợp lệ, bị chặn với `Token is not authorized` | TokenReview của thư viện verifier không khai báo audience; token Kyverno 1.19 có audience `kyverno-svc.kyverno.io` | Bản vá p2 khai báo audience; **không** tắt xác thực token | Fail-closed giữ an toàn ngay cả khi hệ thống chưa dùng được; lỗi tích hợp chỉ lộ ra trên cụm thật |
| 2 | Bearer token của Kyverno nằm trong log extension | Thư viện in nguyên TokenReview ở mức INFO | Bản vá p2 chỉ ghi tên user; script thu bằng chứng lọc chuỗi JWT | Log của thành phần bảo mật cũng có thể làm lộ credential |
| 3 | Extension bản phát hành có 6 Critical | Bản v1.1 build bằng Go 1.22 và thư viện cũ; upstream sắp lưu trữ | Tự build từ `main` ghim commit, vá dependency, gate 0 Critical | Thành phần trong chuỗi kiểm soát cũng phải qua chính các gate đó |
| 4 | Trust policy OIDC theo mẫu sẽ luôn bị từ chối | Repo bật immutable subject claims, `sub` chứa ID số | Lấy dạng `sub` thật từ API GitHub rồi mới viết trust | Không viết trust policy theo mẫu khi chưa kiểm claim thực tế |
| 5 | Gitleaks làm fail PR không liên quan | Checkout `fetch-depth: 0` tải mọi nhánh; Gitleaks mặc định quét mọi ref nên bắt secret ở nhánh TC02 | `--log-opts=HEAD`: chỉ quét lịch sử của commit đang kiểm | Phạm vi quét phải khớp với đối tượng đang được kiểm |
| 6 | Allowlist Gitleaks bỏ qua cả file | `paths` ở allowlist toàn cục áp cho mọi rule | Allowlist cấp rule, điều kiện AND (file + chuỗi); kiểm chứng bằng secret thử nghiệm | Ngoại lệ phải hẹp và được kiểm chứng |
| 7 | `.gitignore` bỏ sót mã nguồn | Mẫu `*token*` (để chặn file token) khớp 7 file `token*.go` của podinfo | Thêm ngoại lệ `!app/**/*token*` | Quy tắc chặn secret quá rộng có thể làm hỏng build |
| 8 | `docker login` ECR lỗi `The stub received bad data` | Token ECR quá dài cho Windows Credential Manager | Dùng `DOCKER_CONFIG` tạm (quyền 700, xóa khi xong) | — |
| 9 | Không tải được chart Kyverno / Trivy DB | `kyverno.github.io` timeout; `mirror.gcr.io` bị ngắt từ mạng lab | Chart qua OCI `ghcr.io` (kiểm SHA-256); DB qua `ghcr.io/aquasecurity/trivy-db:2` | Ghi nguồn tải thay thế vào script |
| 10 | Script cài extension báo sai | (a) chú thích template nhắc tên profile B; (b) `envsubst` thay cả biến trong chú thích làm hỏng YAML | Chỉ kiểm dòng không phải chú thích; đổi cách viết chú thích | Template render bằng `envsubst` cần chú ý cả phần chú thích |
| 11 | Repo public làm lộ account ID | Variables không được che trong log; artifact ai cũng tải được | Account ID đặt ở Secret; `release.json` che `<ACCOUNT_ID>` trước khi upload | Thông tin "không bí mật" vẫn cần cân nhắc khi repo công khai |
| 12 | So image ID của extension báo sai | Docker 29 (containerd store) báo digest **index**; node kind báo digest **config** | Lần chuỗi index → manifest → config trong `docker save`; `preflight.sh` so config | Phải biết rõ "image ID" đang là digest của đối tượng nào |
| 13 | Ổ C: đầy khi build (`Bus error`), WSL dừng đột ngột khi quét | Ổ đĩa ảo Docker chỉ tăng, không tự co lại | Khởi động lại Docker/WSL; dọn đĩa; fixture chưa push nên chạy lại an toàn | Script tạo fixture phải an toàn khi chạy lại |
| 14 | Kiểm lộ thông tin chạy với biến rỗng | Git Bash tự đổi đường dẫn `/mnt/c/…`; WSL thiếu `~/.local/bin` trong `PATH` | Bắt buộc account ID khớp `^[0-9]{12}$` trước khi dùng | Phép kiểm cũng cần được kiểm |

Vấn đề 1–4 nằm trên đường găng: nếu không giải quyết, Policy 2 hoặc job `publish` không hoạt động. Kế hoạch đã chuẩn bị phương án lùi: Kyverno native (`ImageValidatingPolicy`), rồi Ratify + Gatekeeper. Phương án lùi không cần dùng tới, vì bản vá p2 giải quyết được vấn đề mà không nới lỏng bất kỳ kiểm soát nào.

## 4.9. Tiểu kết

Toàn bộ hệ thống đã được triển khai và chạy thật trên GitHub Actions, AWS và một cụm Kubernetes:

- **Đường phát hành tự động hoàn toàn từ commit tới image đã ký:** build một lần, quét một lần, push đúng artifact đã quét, ký tự động bằng AWS Signer, ghi hồ sơ phát hành. Không có access key dài hạn, không có lệnh ký thủ công.
- **Mỗi danh tính chỉ có quyền tối thiểu**, đã kiểm bằng Access Analyzer và bằng thực nghiệm: publisher chỉ push và ký được, verifier chỉ đọc được, deployer chỉ triển khai được.
- **Hai policy admission:** một kiểm nguồn image bằng CEL, một kiểm chữ ký qua extension đã tự build và vá. Cả hai chạy chế độ fail-closed.
- **Nhiều lỗi tích hợp chỉ lộ ra khi chạy thật** và đã được xử lý mà không nới lỏng kiểm soát. Hiệu quả của từng lớp được đánh giá ở Chương 5.
