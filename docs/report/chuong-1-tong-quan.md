# Chương 1. Tổng quan (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15 và đề cương môn học (`Dự kiến.txt`). Trước khi nộp: đối chiếu trích dẫn các sự cố ở mục 1.1 với nguồn gốc (danh mục tài liệu tham khảo cuối báo cáo).

## 1.1. Bối cảnh và lý do chọn đề tài

Phần mềm ngày nay hiếm khi được viết từ đầu. Một ứng dụng container điển hình được ghép từ mã nguồn của nhóm phát triển, hàng trăm thư viện mã nguồn mở, một image nền do bên thứ ba duy trì, và được build, đóng gói, phân phối qua một chuỗi công cụ tự động: hệ thống CI, registry, nền tảng điều phối. Tập hợp các mắt xích đó là **chuỗi cung ứng phần mềm**. Mỗi mắt xích là một điểm mà kẻ tấn công có thể nhắm tới thay vì tấn công trực tiếp ứng dụng.

Một số sự cố nổi bật cho thấy rủi ro này là có thật:

| Sự cố | Mắt xích bị tấn công |
|---|---|
| SolarWinds (2020) | Hệ thống build: mã độc được chèn vào bản cập nhật hợp lệ, có chữ ký của nhà cung cấp |
| Codecov (2021) | Công cụ trong CI: script tải lên bị sửa để đánh cắp biến môi trường chứa secret của pipeline |
| xz-utils (2024, CVE-2024-3094) | Dependency mã nguồn mở: backdoor được đưa vào thư viện nén qua người bảo trì |
| tj-actions/changed-files (2025, CVE-2025-30066) | GitHub Action của bên thứ ba: tag bị trỏ sang commit độc hại, làm lộ secret trong log CI |

Bài học chung: một container image "chạy được" chưa đủ để kết luận nó đáng tin. Cần trả lời được các câu hỏi sau:
- image chứa những gì;
- có lỗ hổng nghiêm trọng đã biết không;
- có lộ thông tin bí mật không;
- do ai phát hành, từ mã nguồn nào;
- có đúng là image đã được kiểm tra hay đã bị thay thế.

Các câu hỏi này phải được trả lời **tự động**, ở **mỗi lần** phát hành và triển khai, chứ không phải bằng một lần rà soát thủ công.

Hướng **DevSecOps** đưa các kiểm soát bảo mật vào chính quy trình CI/CD. Các thực hành tiêu biểu là quét secret, quét lỗ hổng, sinh SBOM (*Software Bill of Materials*, danh mục thành phần phần mềm), ký số artifact, và kiểm soát ở bước triển khai bằng *admission policy* của Kubernetes. Mỗi thực hành đều có công cụ trưởng thành. Câu hỏi thực tế là **phối hợp chúng thế nào** để các kiểm soát bổ sung cho nhau, không để lại khe hở giữa "đã kiểm ở CI" và "đang chạy trên cụm".

Đề tài chọn bộ công nghệ gắn với hạ tầng AWS và Kubernetes:
- **GitHub Actions** cho pipeline;
- **Gitleaks**, **Trivy** và **Syft** để quét secret, quét lỗ hổng và sinh SBOM;
- **Amazon ECR** làm registry, với tính năng **ECR Managed Signing** dùng **AWS Signer** để ký image tự động khi push. Tính năng này loại bỏ việc tự quản lý khóa ký trong pipeline;
- **Kyverno** làm admission controller trên Kubernetes, kiểm nguồn gốc và chữ ký của image trước khi cho phép tạo Pod.

## 1.2. Mục tiêu

**Tên đề tài:** *Xây dựng quy trình bảo mật chuỗi cung ứng phần mềm cho container image sử dụng SBOM, Amazon ECR Managed Signing và kiểm soát triển khai trên Kubernetes.*

Mục tiêu chung là xây dựng và kiểm chứng một quy trình khép kín:
1. từ mã nguồn, qua các bước kiểm tra bảo mật tự động;
2. tới image được lưu trữ và ký số trong registry tin cậy;
3. rồi được triển khai lên Kubernetes;

sao cho chỉ những image đạt yêu cầu và có nguồn gốc kiểm chứng được mới chạy được.

Mục tiêu cụ thể, theo nội dung dự kiến của đề cương:

1. Container hóa một ứng dụng web mã nguồn mở làm workload mẫu.
2. Xây dựng pipeline GitHub Actions để tự động kiểm thử, build image, kiểm tra secret, quét lỗ hổng và tạo SBOM.
3. Chỉ đưa image đáp ứng yêu cầu bảo mật lên Amazon ECR; cấu hình ECR Managed Signing với AWS Signer để tự động ký số image.
4. Triển khai ứng dụng trên Kubernetes và áp dụng admission policy bằng Kyverno để kiểm soát nguồn image và xác minh chữ ký trước khi cho phép triển khai.
5. Xây dựng các kịch bản kiểm thử cho bốn tình huống: mã nguồn chứa secret, image có lỗ hổng nghiêm trọng, image chưa ký, và image từ registry không được phép.

Mục tiêu được cụ thể hóa thành bảy kết quả có tiêu chí nghiệm thu (KQ1–KQ7, Chương 3 mục 3.2).

## 1.3. Câu hỏi nghiên cứu

> **Phối hợp kiểm soát trong CI và tại Kubernetes admission có phát hiện hoặc ngăn chặn được bốn tình huống — secret trong mã nguồn, image có lỗ hổng mức Critical, image chưa ký và image từ nguồn không được phép — đồng thời truy vết được từ Pod đang chạy về digest, SBOM và commit nguồn hay không?**

Câu hỏi được trả lời bằng thực nghiệm: mỗi tình huống có ca kiểm thử với lớp chặn và nguyên nhân xác định trước, kèm đối chứng và bằng chứng (Chương 5).

## 1.4. Phạm vi và giới hạn

**Trong phạm vi:**
- Một ứng dụng (podinfo, viết bằng Go), một kiến trúc image (`linux/amd64`).
- Một account AWS, region `ap-southeast-1`, một repository ECR.
- Một cụm Kubernetes cục bộ (kind) cho phát triển và demo; EKS chỉ là hướng mở rộng.
- Bốn tình huống bắt buộc của đề cương, cộng năm ca mở rộng nhằm thử các đường vòng: sai người ký, dùng tag thay digest, giấu image trong init container, verifier ngừng hoạt động, người triển khai vượt quyền.

**Ngoài phạm vi:** bảo mật lúc chạy (runtime), quét mã nguồn tĩnh (SAST), ký và kiểm tra attestation cho SBOM hay kết quả quét, chứng nhận theo một mức SLSA cụ thể, CD tự động hoàn toàn (GitOps).

**Phạm vi kết luận:** đồ án kiểm soát *một số* rủi ro chuỗi cung ứng trong môi trường thực nghiệm. Đồ án không kết luận "image có chữ ký là an toàn", "chặn được mọi tấn công" hay "đạt SLSA level X".

## 1.5. Phương pháp thực hiện

- **Ưu tiên phần rủi ro cao nhất (spike đường găng).** Chuỗi *ký tự động → xác minh bằng Notation → extension xác minh → Kyverno từ chối* có nhiều thành phần mới và ít tài liệu tích hợp nhất. Vì vậy chuỗi này được thử nghiệm sớm, với tiêu chí đạt rõ ràng, trước khi đầu tư vào pipeline hoàn chỉnh. Kế hoạch chuẩn bị sẵn hai phương án lùi nếu spike không đạt.
- **Thiết kế dựa trên ranh giới tin cậy:** phân tích các vùng tin cậy và danh tính trước, rồi cấp quyền tối thiểu cho từng danh tính.
- **Ghim phiên bản và tái lập:** mọi công cụ, image nền, GitHub Action và Helm chart đều được ghim theo phiên bản cùng hash hoặc digest, ghi trong `docs/versions.md`. Mọi thao tác hạ tầng được viết thành script chạy lại được.
- **Thực nghiệm có đối chứng và bằng chứng:** mỗi ca kiểm thử xác định trước lớp chặn và nguyên nhân. Mỗi lần từ chối phải có stderr, exit code, event và log; mỗi lượt có yêu cầu đối chứng hợp lệ. Số liệu chỉ lấy từ lần chạy thật.
- **Không nới lỏng kiểm soát để hệ thống "chạy được":** khi gặp lỗi, không chuyển policy sang chế độ cảnh báo, không tắt xác minh TLS, không tin mọi người ký, không bỏ qua lỗ hổng chưa có bản vá.

## 1.6. Kết quả đạt được (tóm tắt)

- Pipeline GitHub Actions gồm ba job:
  - `verify`: test, Gitleaks, build một lần, SBOM CycloneDX, Trivy với gate 0 Critical;
  - `policy-test`: kiểm thử policy offline;
  - `publish`: đẩy đúng image đã kiểm lên ECR qua GitHub OIDC, không có access key dài hạn.
- ECR Managed Signing ký tự động mỗi image phát hành bằng AWS Signer, sau khoảng 2 giây kể từ khi push; pipeline không có lệnh ký thủ công.
- Trên Kubernetes, hai policy Kyverno chạy ở chế độ chặn và mặc định từ chối khi không kiểm được:
  - Policy 1 chỉ cho phép image đúng repository, tham chiếu bằng digest;
  - Policy 2 xác minh chữ ký Notation của đúng signing profile, có kiểm tra thu hồi.
- Mười ca kiểm thử (TC01–TC10) đều đạt, có bằng chứng; luồng hợp lệ đi trọn từ commit tới Pod; truy vết được hai chiều giữa Pod và commit.
- Quá trình thực nghiệm phát hiện và xử lý nhiều lỗi tích hợp chỉ lộ ra khi chạy thật. Ví dụ: extension xác minh chữ ký không xác thực được token của Kyverno 1.19 và ghi token vào log; dạng claim OIDC thực tế khác mẫu trong tài liệu. Cả hai đều được giải quyết mà không nới lỏng kiểm soát.

## 1.7. Cấu trúc báo cáo

| Chương | Nội dung |
|---|---|
| 1. Tổng quan | Bối cảnh, mục tiêu, câu hỏi nghiên cứu, phạm vi, phương pháp |
| 2. Cơ sở lý thuyết | DevSecOps, bảo mật chuỗi cung ứng, container image và digest, SBOM, quét lỗ hổng và secret, chữ ký số (Notation, AWS Signer, ECR Managed Signing), admission control và Kyverno |
| 3. Phân tích và thiết kế | Mô hình mối đe dọa, yêu cầu, kiến trúc, ranh giới tin cậy, phân quyền, thiết kế gate, policy và truy vết |
| 4. Triển khai | Container hóa, hạ tầng AWS, pipeline, Kubernetes, Kyverno và extension; khó khăn và giải pháp |
| 5. Thực nghiệm và đánh giá | Môi trường, kết quả mười ca kiểm thử, số liệu đo, truy vết, phân tích và giới hạn |
| 6. Kết luận và hướng phát triển | Đối chiếu với kết quả dự kiến, đóng góp, hạn chế, hướng phát triển |
| Phụ lục | Hướng dẫn dựng lại, cấu hình, lệnh demo, liên kết repository |
