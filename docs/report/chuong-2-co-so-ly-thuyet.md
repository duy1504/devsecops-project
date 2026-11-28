# Chương 2. Cơ sở lý thuyết (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15. Mỗi mục kết thúc bằng phần **"Áp dụng trong đồ án"** để nối lý thuyết với phần triển khai. Trích dẫn `[n]` theo danh mục chung `docs/report/tai-lieu-tham-khao.md` (liên kết đã kiểm 28/11/2026). Trước khi nộp: thêm hình minh họa.

## 2.1. DevOps, CI/CD và DevSecOps

**DevOps** là tập hợp văn hóa và thực hành gắn phát triển (Dev) với vận hành (Ops) nhằm rút ngắn vòng đời phát hành mà vẫn giữ chất lượng. Hai thực hành cốt lõi:

- **Tích hợp liên tục (CI):** mỗi thay đổi được build và kiểm thử tự động ngay khi đưa vào kho mã chung.
- **Chuyển giao / triển khai liên tục (CD):** artifact đã qua CI được đưa tới môi trường đích bằng quy trình tự động, lặp lại được.

**DevSecOps** đưa kiểm soát bảo mật vào chính pipeline thay vì kiểm tra ở cuối dự án. Ý tưởng "dịch trái" (*shift-left*) là phát hiện vấn đề càng sớm càng rẻ: lộ secret được chặn ở bước commit/PR, lỗ hổng được chặn trước khi image vào registry. Tuy vậy, shift-left không thay thế được kiểm soát ở phía phải (lúc triển khai, lúc chạy): CI chỉ bảo vệ những gì đi qua CI.

**Áp dụng trong đồ án:** pipeline GitHub Actions là lớp kiểm soát thứ nhất (test, Gitleaks, SBOM, Trivy gate); admission của Kubernetes là lớp thứ hai, chặn cả image không đi qua pipeline.

## 2.2. Bảo mật chuỗi cung ứng phần mềm

### 2.2.1. Khái niệm và mô hình mối đe dọa

Chuỗi cung ứng phần mềm gồm mọi thành phần và bước tạo nên sản phẩm: mã nguồn, dependency, công cụ build, hệ thống CI, registry, cho tới môi trường triển khai. Kẻ tấn công có thể tấn công bất kỳ mắt xích nào thay vì tấn công trực tiếp ứng dụng. Một số sự cố tiêu biểu:

| Sự cố | Mắt xích bị tấn công |
|---|---|
| SolarWinds (2020) [9] | Hệ thống build: mã độc được chèn vào bản cập nhật hợp lệ, có chữ ký của nhà cung cấp |
| Codecov (2021) [10] | Công cụ trong CI: script tải lên bị sửa để đánh cắp biến môi trường (chứa secret) của pipeline |
| xz-utils (2024, CVE-2024-3094) [11] | Dependency mã nguồn mở: backdoor được đưa vào thư viện nén qua người bảo trì |
| tj-actions/changed-files (2025, CVE-2025-30066) [12] | GitHub Action bên thứ ba: tag bị trỏ sang commit độc hại, làm lộ secret trong log CI |

Bài học chung: "chạy được" và "có chữ ký" chưa đủ để kết luận tin cậy. SolarWinds cho thấy chữ ký chỉ chứng minh **ai** phát hành, không chứng minh nội dung lành tính. Vụ tj-actions cho thấy chính pipeline cũng là một phần của chuỗi cung ứng.

Mô hình mối đe dọa của đồ án giới hạn ở bốn tình huống trong đề cương: secret trong mã, image có lỗ hổng nghiêm trọng, image chưa ký và image từ nguồn không được phép.

### 2.2.2. Các khung tham chiếu

- **SLSA** (*Supply-chain Levels for Software Artifacts*, OpenSSF) [1]: khung phân cấp các yêu cầu đảm bảo tính toàn vẹn của artifact, xoay quanh nguồn gốc (*provenance*) của quá trình build. SLSA v1.0 tổ chức yêu cầu thành các "track", trong đó Build track có các mức L0–L3.
- **NIST SSDF** (*Secure Software Development Framework*, SP 800-218) [2]: bộ thực hành phát triển phần mềm an toàn, chia thành bốn nhóm: chuẩn bị tổ chức (PO), bảo vệ phần mềm (PS), tạo ra phần mềm an toàn (PW) và phản hồi lỗ hổng (RV).

**Áp dụng trong đồ án:** đồ án dùng các khung này làm hệ quy chiếu, **không** tuyên bố đạt một mức SLSA cụ thể, vì chưa tạo và kiểm tra provenance. Một số biện pháp tương ứng với SSDF: bảo vệ mã và pipeline (branch protection, ghim action theo SHA) thuộc nhóm PS; quét secret và lỗ hổng thuộc nhóm PW.

## 2.3. Container image, registry, digest và OCI referrers

Một **container image** theo chuẩn OCI [3] gồm *manifest*, *config* và các *layer*. Image đa kiến trúc còn có một *index* trỏ tới manifest của từng nền tảng. Mọi thành phần được định danh theo nội dung (*content-addressable*): **digest** là hàm băm (thường SHA-256) của nội dung. Đổi một byte thì digest đổi.

| | Tag (`podinfo:1.0`) | Digest (`podinfo@sha256:…`) |
|---|---|---|
| Bản chất | Con trỏ có thể đổi | Định danh bất biến của nội dung |
| Rủi ro | Có thể bị trỏ sang image khác sau khi đã kiểm tra | Luôn chỉ đúng một nội dung |

Vì vậy, xác minh và triển khai phải dùng digest: image được quét, được ký và được chạy phải là cùng một nội dung [26]. Cấu hình *tag immutable* của registry giảm rủi ro ghi đè tag nhưng không thay thế việc dùng digest.

"Digest của image" có thể là digest của các đối tượng khác nhau: **config**, **manifest** hay **index**. Image ID mà Docker báo cục bộ, checksum của file `docker save` và digest trên registry vì thế **không** bằng nhau. Chúng chỉ liên kết được bằng quy trình: build một lần, chuyển đúng file, push, rồi đọc digest từ registry.

**OCI referrers.** OCI Distribution Specification v1.1 [4] bổ sung trường `subject` và API *referrers*. Nhờ đó có thể lưu các artifact "gắn vào" một image (chữ ký, SBOM, attestation) mà không sửa image đó. Chữ ký Notation được lưu theo cơ chế này. Với registry chưa hỗ trợ API referrers, đặc tả có cơ chế dự phòng (*referrers tag schema*): một tag dạng `sha256-<digest>` trỏ tới index liệt kê các artifact.

**Áp dụng trong đồ án:**
- Policy 1 chỉ chấp nhận image tham chiếu bằng `@sha256:` + 64 ký tự hex.
- Pipeline build một lần ra `image.tar` và dùng đúng file đó cho SBOM, quét và push; `release.json` ghi cả ba loại SHA.
- Trên ECR, khi ký tay bằng Notation CLI, đồ án quan sát thấy một tag `sha256-<digest>` như trên. Lifecycle policy chọn đúng tiền tố `sha-` (không phải `sha`) để không xóa nhầm tag này.

## 2.4. SBOM, quét lỗ hổng và quét secret

### 2.4.1. SBOM

**SBOM** (*Software Bill of Materials*) là danh mục có cấu trúc các thành phần (gói, thư viện, phiên bản, giấy phép) trong một phần mềm. Hai định dạng phổ biến:

- **SPDX** (Linux Foundation), đã thành chuẩn ISO/IEC 5962:2021 [5].
- **CycloneDX** (OWASP), đã được chuẩn hóa thành ECMA-424 [6].

SBOM trả lời câu hỏi "image chứa gì", giúp truy vết nhanh khi có CVE mới. SBOM **không** phải chứng nhận an toàn: nó không cho biết thành phần nào có lỗ hổng.

### 2.4.2. Quét lỗ hổng

Scanner đối chiếu thành phần tìm thấy trong image với cơ sở dữ liệu lỗ hổng (CVE và các nguồn advisory của bản phân phối hoặc hệ sinh thái ngôn ngữ). Một số lưu ý:

- **Mức độ nghiêm trọng của scanner có thể khác điểm CVSS trên NVD**, vì scanner có thể ưu tiên đánh giá của nhà cung cấp bản phân phối. Báo cáo cần ghi rõ scanner, phiên bản và thời điểm cơ sở dữ liệu.
- Kết quả **thay đổi theo thời gian**: cùng một image, hôm nay sạch, mai có thể có CVE mới.
- Scanner chỉ phát hiện lỗ hổng **đã biết**, không phát hiện zero-day hay mã độc chưa được công bố.

### 2.4.3. Quét secret

Công cụ quét secret dùng biểu thức chính quy và độ hỗn loạn (*entropy*) để tìm chuỗi giống khóa, token, mật khẩu trong mã và lịch sử commit. Quét cả lịch sử là cần thiết vì secret đã commit vẫn còn trong Git dù bị xóa ở commit sau; khi lộ thật, phải **thu hồi** secret chứ không chỉ xóa commit. Công cụ có thể báo nhầm (*false positive*) hoặc bỏ sót.

**Áp dụng trong đồ án:** Syft tạo SBOM CycloneDX; Trivy quét một lần và gate chặn mọi Critical; Gitleaks quét toàn bộ lịch sử của commit đang kiểm, với rule lab `DEMO_SECRET_` để kiểm thử mà không cần secret thật.

## 2.5. Chữ ký số cho container image

### 2.5.1. Mục đích

Chữ ký ràng buộc **một digest cụ thể** với **một danh tính** (người hoặc hệ thống ký). Bên xác minh kiểm tra được: nội dung không bị sửa sau khi ký, và người ký nằm trong danh sách tin cậy. Chữ ký không chứng minh nội dung an toàn hay đã qua kiểm tra; điều đó phụ thuộc vào việc ai được phép ký.

### 2.5.2. Notary Project / Notation và Sigstore / Cosign

| | Notary Project (Notation) [7] | Sigstore (Cosign) [8] |
|---|---|---|
| Mô hình tin cậy | Chứng chỉ X.509 và trust store do bên xác minh cấu hình | Thường dùng ký "keyless": chứng chỉ ngắn hạn cấp theo danh tính OIDC (Fulcio), ghi vào nhật ký minh bạch (Rekor) |
| Lưu chữ ký | OCI referrer gắn với digest | Artifact OCI trong registry |
| Liên quan đề tài | AWS Signer / ECR Managed Signing tạo chữ ký Notation | Hệ sinh thái khác, không dùng |

### 2.5.3. Các khái niệm khi xác minh bằng Notation

- **Trust store:** tập chứng chỉ gốc được tin (ở đây là chứng chỉ gốc AWS Signer).
- **Trust policy:** quy tắc áp cho phạm vi registry/repository (`registryScopes`): mức xác minh, trust store nào, và **danh tính tin cậy** (`trustedIdentities`).
- **Trusted identity:** giới hạn chữ ký phải đến từ danh tính cụ thể. Nếu chỉ tin chứng chỉ gốc AWS Signer, mọi profile trong hệ thống AWS Signer đều được chấp nhận; giới hạn theo signing profile mới phân biệt được "đúng người ký".
- **Thu hồi (revocation):** chữ ký hoặc profile ký có thể bị thu hồi; bên xác minh cần kiểm tra trạng thái này tại thời điểm xác minh.

### 2.5.4. AWS Signer và ECR Managed Signing

**AWS Signer** [16][17] là dịch vụ ký mã do AWS quản lý: khóa ký nằm trong dịch vụ, người dùng làm việc qua *signing profile* (với container image dùng platform `Notation-OCI-SHA384-ECDSA`). Profile có thể bị thu hồi. Chữ ký dùng scheme `notary.x509.signingAuthority`.

**ECR Managed Signing** [13] để ECR tự ký image khi push, theo cấu hình ký ở cấp registry với các quy tắc lọc theo repository. Pipeline chỉ cần push, không gọi lệnh ký. Chữ ký được tạo dưới danh tính của người push, nên danh tính đó cần quyền `signer:SignPayload` trên signing profile. Trạng thái ký của từng image (`IN_PROGRESS`, `COMPLETE`, `FAILED`) đọc được qua API [15]. Việc xác minh có thể làm cục bộ bằng Notation CLI [18] hoặc trong cụm Kubernetes [19][20]. Điểm cần hiểu đúng: ECR **ký mọi image** push vào repository khớp quy tắc, không đọc kết quả quét. "Chỉ image đạt mới được ký" phải được bảo đảm bởi pipeline và việc giới hạn quyền push.

**Áp dụng trong đồ án:** repository `podinfo` có signing rule đúng tên, không wildcard; profile thứ hai (profile B) chỉ dùng tạo fixture "sai người ký" và không nằm trong `trustedIdentities`.

## 2.6. Kubernetes admission control và policy-as-code

### 2.6.1. Admission control

Mỗi yêu cầu tạo hoặc sửa tài nguyên tới kube-apiserver đi qua xác thực, phân quyền (RBAC), rồi **admission** [23]: các admission controller có thể sửa (*mutating*) hoặc từ chối (*validating*) yêu cầu trước khi lưu vào etcd. Hệ thống bên ngoài tham gia qua *admission webhook*. Với webhook, `failurePolicy` quyết định khi webhook lỗi thì cho qua (`Ignore`) hay từ chối (`Fail`). Kiểm soát an ninh cần **fail-closed** (`Fail`).

Kubernetes còn có **ValidatingAdmissionPolicy** [24] viết bằng CEL, chạy ngay trong API server (GA từ v1.30), không cần webhook.

Admission chỉ kiểm tra **yêu cầu mới**: Pod đã chạy không bị gỡ khi policy hay trạng thái chữ ký thay đổi.

### 2.6.2. Policy-as-code: Kyverno và OPA Gatekeeper

| | Kyverno | OPA Gatekeeper |
|---|---|---|
| Ngôn ngữ policy | YAML; dòng policy mới viết bằng CEL (`ValidatingPolicy`, `ImageValidatingPolicy`…) | Rego (OPA) trong ConstraintTemplate |
| Xác minh chữ ký image | Có sẵn cho một số định dạng; với AWS Signer cần extension chạy Notation + plugin | Kết hợp Ratify |
| Ghi chú | Kyverno đang chuyển từ `ClusterPolicy` sang các policy CEL; `ClusterPolicy` bị đánh dấu deprecated [29][31] | Ratify [35] làm bên xác minh chữ ký cho Gatekeeper [34] |

**Vòng đời phiên bản.** Từ 1.18, Kyverno hỗ trợ theo mô hình N-1: bản minor hiện tại và bản ngay trước đó được vá lỗi CVE critical/high [30]. Khi chọn phiên bản cần tính tới thời điểm bản đó hết hỗ trợ, cũng như việc một loại policy đang bị đánh dấu deprecated.

**Áp dụng trong đồ án:** Kyverno 1.19.2. Policy 1 viết bằng CEL (`ValidatingPolicy`) kiểm nguồn và digest; Policy 2 dùng `ClusterPolicy` gọi extension `kyverno-notation-aws` để xác minh chữ ký AWS Signer. Phương án lùi: xác minh native của Kyverno, hoặc Ratify + Gatekeeper. Quyền deployer bị giới hạn bằng RBAC (không sửa policy, không exec, không dùng ephemeral container).

## 2.7. Bảo mật cho chính pipeline CI/CD

Vụ Codecov và tj-actions cho thấy **pipeline cũng là một mắt xích của chuỗi cung ứng**: ai kiểm soát được pipeline thì phát hành được artifact "hợp lệ". Ba biện pháp nền tảng:

### 2.7.1. Xác thực tới cloud không dùng khóa dài hạn (OIDC)

Cách truyền thống là lưu access key của cloud trong secret của CI. Khóa đó sống lâu, và một khi lộ thì dùng được từ bất kỳ đâu. Với **OpenID Connect (OIDC)** [36][37], các bước diễn ra như sau:
1. Mỗi job xin GitHub một token JWT ngắn hạn, do GitHub ký, mang các *claim* mô tả ngữ cảnh: repository, nhánh, sự kiện, environment…
2. Cloud được cấu hình để tin nhà cung cấp OIDC của GitHub.
3. Cloud đổi token đó lấy credential tạm (trên AWS là `sts:AssumeRoleWithWebIdentity`), **chỉ khi** các claim khớp điều kiện trong trust policy của role.

Hai claim quan trọng nhất là `aud` (người nhận token) và `sub` (chủ thể: repo nào, nhánh nào hay environment nào). Dạng của `sub` phụ thuộc ngữ cảnh: job chạy trên nhánh khác với job gắn `environment`. Dạng này cũng có thể được tùy biến, ví dụ định dạng *immutable* dựa trên ID của repository thay vì tên [38]. Vì vậy trust policy phải viết theo dạng `sub` **thực tế** của repo. Job chỉ xin được token OIDC khi được cấp quyền `id-token: write`.

### 2.7.2. Ghim phụ thuộc của pipeline

Action của bên thứ ba là mã chạy trong pipeline với quyền của pipeline. Tag như `@v4` có thể bị trỏ sang commit khác, như vụ tj-actions. Tài liệu bảo mật của GitHub (kiểm ngày 28/11/2026) [39] đưa ra hai mức bảo vệ:
- **Workflow dependency lockfile** là mức mạnh nhất, thay thế việc ghim SHA với repo áp dụng được.
- Với repo chưa dùng lockfile, cần **ghim action theo commit SHA đầy đủ**: muốn cài cửa sau vào một SHA đã ghim, kẻ tấn công phải tạo được va chạm SHA-1. Nguyên tắc này áp dụng tương tự cho công cụ CLI (kiểm SHA-256 khi tải), image nền (ghim digest) và Helm chart (ghim phiên bản cùng hash).

### 2.7.3. Quyền tối thiểu và bảo vệ nhánh

- **`GITHUB_TOKEN` chỉ cấp quyền cần thiết cho từng job** [39]. Job chạy mã chưa tin cậy (pull request) không được có quyền ghi hay token OIDC. Không dùng sự kiện `pull_request_target` để chạy mã của PR với quyền của repo.
- **Branch protection** [40] buộc mọi thay đổi vào nhánh phát hành đi qua pull request và các check bắt buộc, áp dụng cả cho quản trị viên. Như vậy, chỉ mã đã qua kiểm tra mới đến được job có quyền phát hành.
- **Phía cloud, mỗi danh tính chỉ có quyền tối thiểu**, giới hạn theo tài nguyên cụ thể [21], và được kiểm bằng công cụ phân tích policy [22].

**Áp dụng trong đồ án:**
- Chỉ job `publish`, chạy trên `main` sau khi `verify` đạt, có `id-token: write`. Role publisher chỉ tin `sub` của nhánh `main` (repo dùng định dạng immutable).
- Mọi action được ghim theo commit SHA đầy đủ (chưa dùng workflow dependency lockfile); công cụ CLI kiểm SHA-256 khi tải.
- Branch protection bắt buộc hai check `verify` và `policy-test`.
- Không có access key nào trong GitHub Secrets.

## 2.8. Tóm tắt chương

Không biện pháp nào đủ một mình:
- SBOM cho biết thành phần;
- scanner đánh giá rủi ro đã biết;
- quét secret ngăn lộ thông tin;
- chữ ký ràng buộc digest với danh tính;
- admission bảo đảm chỉ image đáp ứng chính sách mới được chạy;
- bảo vệ pipeline (OIDC, ghim phụ thuộc, quyền tối thiểu) bảo đảm chỉ pipeline hợp lệ mới tạo được chữ ký tin cậy.

Đồ án kết hợp các lớp này thành hai tầng kiểm soát (CI và admission) và đánh giá bằng bộ kiểm thử có đối chứng ở Chương 5.

Danh mục tài liệu tham khảo của toàn báo cáo: `docs/report/tai-lieu-tham-khao.md`.
