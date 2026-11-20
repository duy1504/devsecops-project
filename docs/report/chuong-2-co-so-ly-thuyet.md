# Chương 2. Cơ sở lý thuyết (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15. Mỗi mục kết thúc bằng phần **"Áp dụng trong đồ án"** để nối lý thuyết với phần triển khai. Trước khi nộp: đối chiếu lại thuật ngữ và trích dẫn với tài liệu gốc (danh mục ở cuối chương), thêm hình minh họa.

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
| SolarWinds (2020) | Hệ thống build: mã độc được chèn vào bản cập nhật hợp lệ, có chữ ký của nhà cung cấp |
| Codecov (2021) | Công cụ trong CI: script tải lên bị sửa để đánh cắp biến môi trường (chứa secret) của pipeline |
| xz-utils (2024, CVE-2024-3094) | Dependency mã nguồn mở: backdoor được đưa vào thư viện nén qua người bảo trì |
| tj-actions/changed-files (2025, CVE-2025-30066) | GitHub Action bên thứ ba: tag bị trỏ sang commit độc hại, làm lộ secret trong log CI |

Bài học chung: "chạy được" và "có chữ ký" chưa đủ để kết luận tin cậy. SolarWinds cho thấy chữ ký chỉ chứng minh **ai** phát hành, không chứng minh nội dung lành tính. Vụ tj-actions cho thấy chính pipeline cũng là một phần của chuỗi cung ứng.

Mô hình mối đe dọa của đồ án giới hạn ở bốn tình huống trong đề cương: secret trong mã, image có lỗ hổng nghiêm trọng, image chưa ký và image từ nguồn không được phép.

### 2.2.2. Các khung tham chiếu

- **SLSA** (*Supply-chain Levels for Software Artifacts*, OpenSSF): khung phân cấp các yêu cầu đảm bảo tính toàn vẹn của artifact, xoay quanh nguồn gốc (*provenance*) của quá trình build. SLSA v1.0 tổ chức yêu cầu thành các "track", trong đó Build track có các mức L0–L3.
- **NIST SSDF** (*Secure Software Development Framework*, SP 800-218): bộ thực hành phát triển phần mềm an toàn, chia thành bốn nhóm: chuẩn bị tổ chức (PO), bảo vệ phần mềm (PS), tạo ra phần mềm an toàn (PW) và phản hồi lỗ hổng (RV).

**Áp dụng trong đồ án:** đồ án dùng các khung này làm hệ quy chiếu, **không** tuyên bố đạt một mức SLSA cụ thể, vì chưa tạo và kiểm tra provenance. Một số biện pháp tương ứng với SSDF: bảo vệ mã và pipeline (branch protection, ghim action theo SHA) thuộc nhóm PS; quét secret và lỗ hổng thuộc nhóm PW.

## 2.3. Container image, registry, digest và OCI referrers

Một **container image** theo chuẩn OCI gồm *manifest*, *config* và các *layer*. Mọi thành phần được định danh theo nội dung (*content-addressable*): **digest** là hàm băm (thường SHA-256) của nội dung. Đổi một byte thì digest đổi.

| | Tag (`podinfo:1.0`) | Digest (`podinfo@sha256:…`) |
|---|---|---|
| Bản chất | Con trỏ có thể đổi | Định danh bất biến của nội dung |
| Rủi ro | Có thể bị trỏ sang image khác sau khi đã kiểm tra | Luôn chỉ đúng một nội dung |

Vì vậy, xác minh và triển khai phải dùng digest: image được quét, được ký và được chạy phải là cùng một nội dung. Cấu hình *tag immutable* của registry giảm rủi ro ghi đè tag nhưng không thay thế việc dùng digest.

**OCI referrers.** OCI Distribution Specification v1.1 bổ sung trường `subject` và API *referrers*, cho phép lưu các artifact "gắn vào" một image (chữ ký, SBOM, attestation) mà không sửa image đó. Chữ ký Notation được lưu theo cơ chế này.

**Áp dụng trong đồ án:** Policy 1 chỉ chấp nhận image tham chiếu bằng `@sha256:` + 64 ký tự hex; pipeline build một lần ra `image.tar` và dùng đúng tar đó cho SBOM, quét và push.

## 2.4. SBOM, quét lỗ hổng và quét secret

### 2.4.1. SBOM

**SBOM** (*Software Bill of Materials*) là danh mục có cấu trúc các thành phần (gói, thư viện, phiên bản, giấy phép) trong một phần mềm. Hai định dạng phổ biến:

- **SPDX** (Linux Foundation), đã thành chuẩn ISO/IEC 5962:2021.
- **CycloneDX** (OWASP), đã được chuẩn hóa thành ECMA-424.

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

| | Notary Project (Notation) | Sigstore (Cosign) |
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

**AWS Signer** là dịch vụ ký mã do AWS quản lý: khóa ký nằm trong dịch vụ, người dùng làm việc qua *signing profile* (với container image dùng platform `Notation-OCI-SHA384-ECDSA`). Profile có thể bị thu hồi. Chữ ký dùng scheme `notary.x509.signingAuthority`.

**ECR Managed Signing** để ECR tự ký image khi push, theo cấu hình ký ở cấp registry với các quy tắc lọc theo repository. Pipeline chỉ cần push, không gọi lệnh ký. Điểm cần hiểu đúng: ECR **ký mọi image** push vào repository khớp quy tắc, không đọc kết quả quét. "Chỉ image đạt mới được ký" phải được bảo đảm bởi pipeline và việc giới hạn quyền push.

**Áp dụng trong đồ án:** repository `podinfo` có signing rule đúng tên, không wildcard; profile thứ hai (profile B) chỉ dùng tạo fixture "sai người ký" và không nằm trong `trustedIdentities`.

## 2.6. Kubernetes admission control và policy-as-code

### 2.6.1. Admission control

Mỗi yêu cầu tạo hoặc sửa tài nguyên tới kube-apiserver đi qua xác thực, phân quyền (RBAC), rồi **admission**: các admission controller có thể sửa (*mutating*) hoặc từ chối (*validating*) yêu cầu trước khi lưu vào etcd. Hệ thống bên ngoài tham gia qua *admission webhook*. Với webhook, `failurePolicy` quyết định khi webhook lỗi thì cho qua (`Ignore`) hay từ chối (`Fail`). Kiểm soát an ninh cần **fail-closed** (`Fail`).

Kubernetes còn có **ValidatingAdmissionPolicy** viết bằng CEL, chạy ngay trong API server (GA từ v1.30), không cần webhook.

Admission chỉ kiểm tra **yêu cầu mới**: Pod đã chạy không bị gỡ khi policy hay trạng thái chữ ký thay đổi.

### 2.6.2. Policy-as-code: Kyverno và OPA Gatekeeper

| | Kyverno | OPA Gatekeeper |
|---|---|---|
| Ngôn ngữ policy | YAML; dòng policy mới viết bằng CEL (`ValidatingPolicy`, `ImageValidatingPolicy`…) | Rego (OPA) trong ConstraintTemplate |
| Xác minh chữ ký image | Có sẵn cho một số định dạng; với AWS Signer cần extension chạy Notation + plugin | Kết hợp Ratify |
| Ghi chú | Kyverno đang chuyển từ `ClusterPolicy` sang các policy CEL; `ClusterPolicy` bị đánh dấu deprecated | — |

**Áp dụng trong đồ án:** Kyverno 1.19.2. Policy 1 viết bằng CEL (`ValidatingPolicy`) kiểm nguồn và digest; Policy 2 dùng `ClusterPolicy` gọi extension `kyverno-notation-aws` để xác minh chữ ký AWS Signer. Phương án lùi: xác minh native của Kyverno, hoặc Ratify + Gatekeeper. Quyền deployer bị giới hạn bằng RBAC (không sửa policy, không exec, không dùng ephemeral container).

## 2.7. Tóm tắt chương

Không biện pháp nào đủ một mình. SBOM cho biết thành phần, scanner đánh giá rủi ro đã biết, quét secret ngăn lộ thông tin, chữ ký ràng buộc digest với danh tính, còn admission bảo đảm chỉ image đáp ứng chính sách mới được chạy. Đồ án kết hợp các lớp này thành hai tầng kiểm soát (CI và admission) và đánh giá bằng bộ kiểm thử có đối chứng ở Chương 5.

## Tài liệu tham khảo (đối chiếu trước khi nộp)

- OpenSSF, *SLSA specification v1.0* — https://slsa.dev/spec/v1.0/
- NIST SP 800-218, *Secure Software Development Framework (SSDF) Version 1.1* — https://csrc.nist.gov/pubs/sp/800/218/final
- Open Container Initiative, *Image Format Specification* và *Distribution Specification v1.1* — https://github.com/opencontainers
- SPDX (ISO/IEC 5962:2021) — https://spdx.dev ; CycloneDX (ECMA-424) — https://cyclonedx.org
- Notary Project — https://notaryproject.dev ; Sigstore — https://www.sigstore.dev
- AWS Signer Developer Guide; Amazon ECR User Guide (Managed Signing) — https://docs.aws.amazon.com
- Kubernetes, *Admission Control*, *ValidatingAdmissionPolicy* — https://kubernetes.io/docs/
- Kyverno — https://kyverno.io/docs/ ; OPA Gatekeeper — https://open-policy-agent.github.io/gatekeeper/ ; Ratify — https://ratify.dev
- Trivy — https://trivy.dev ; Syft — https://github.com/anchore/syft ; Gitleaks — https://github.com/gitleaks/gitleaks
- CVE-2024-3094 (xz-utils); CVE-2025-30066 (tj-actions/changed-files) — https://nvd.nist.gov
