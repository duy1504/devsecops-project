# Chương 6. Kết luận và hướng phát triển (bản nháp)

> Bản nháp theo dàn ý `KE_HOACH_DO_AN_FINAL.md` mục 15. Số liệu dẫn lại từ Chương 5.

## 6.1. Kết luận

Đồ án đã xây dựng và kiểm chứng trên môi trường thật (GitHub Actions, Amazon ECR, AWS Signer, Kubernetes với Kyverno) một quy trình bảo mật chuỗi cung ứng cho container image, từ mã nguồn tới Pod đang chạy.

### 6.1.1. Đối chiếu với kết quả dự kiến của đề cương

| Kết quả dự kiến (đề cương) | Kết quả đạt được | Bằng chứng |
|---|---|---|
| Hoàn thiện quy trình từ mã nguồn, kiểm tra bảo mật, build, lưu trữ đến triển khai trên Kubernetes | Đạt. Một commit trên `main` đi qua `verify` → `publish` → ECR + chữ ký → `deploy.sh` → admission → 2 Pod `Running` đúng digest, không build lại, không ký thủ công | TC01 (run 45798939183) |
| Tạo SBOM, báo cáo lỗ hổng và kết quả kiểm tra secret **trước khi** image vào registry | Đạt. Job `verify` sinh SBOM CycloneDX (1032 component), báo cáo Trivy (JSON, SARIF, bảng) và báo cáo Gitleaks ở mọi run; `publish` chỉ chạy khi `verify` đạt | Artifact `security-reports-*`, TC02, TC03 |
| Image đạt yêu cầu được lưu trên ECR và tự động ký bằng ECR Managed Signing với AWS Signer | Đạt. Mỗi image phát hành có đúng một chữ ký của profile chính, tạo sau 1,7–2,5 s kể từ khi push; pipeline chỉ chờ trạng thái `COMPLETE` | Chương 5 mục 5.4.2 |
| Chính sách trên Kubernetes chỉ cho phép image có nguồn gốc phù hợp và chữ ký hợp lệ | Đạt. Policy 1 (nguồn + digest) và Policy 2 (chữ ký của đúng danh tính, có kiểm thu hồi) đều chạy ở chế độ chặn và mặc định từ chối khi không kiểm được | TC04–TC09 |
| Phát hiện/ngăn chặn: secret, Critical, chưa ký, nguồn không được phép | Đạt cả bốn, mỗi ca bị chặn đúng lớp và đúng nguyên nhân | TC02, TC03, TC04, TC05 |

### 6.1.2. Trả lời câu hỏi nghiên cứu

Câu hỏi nghiên cứu đặt ra ở Chương 1 được trả lời là **có**, trong phạm vi thực nghiệm:

- **Secret trong mã** và **image có lỗ hổng Critical** bị chặn ở CI trước khi có bất kỳ image nào được phát hành.
- **Image chưa ký**, **image ký bởi danh tính khác** và **image từ nguồn không được phép** bị chặn ở admission, kể cả khi người dùng bỏ qua pipeline và gọi `kubectl` trực tiếp.
- **Truy vết** đi được hai chiều. Chiều xuôi: commit → run → artifact đã quét → digest → chữ ký → Pod. Chiều ngược: từ digest của Pod, qua tag `sha-<commit>-run-<id>-<attempt>` trên ECR, về run, SBOM, báo cáo và commit.

Chi phí của các kiểm soát nhỏ so với lợi ích: các bước quét chiếm dưới 10 s trong job `verify` (trung bình 105,5 s), chờ ký khoảng 2 s, và xác minh chữ ký thêm 1,5–2 s cho mỗi Pod.

### 6.1.3. Đóng góp

1. **Phối hợp nhiều lớp kiểm soát** thành một quy trình liền mạch. Chữ ký số tự động là cầu nối giữa "đã kiểm ở CI" và "được phép chạy trên cụm". Phân quyền bảo đảm chỉ pipeline trên nhánh `main` mới tạo được chữ ký tin cậy.
2. **Ràng buộc artifact xuyên pipeline.** Image được build **một lần**, và chính file đó được quét rồi push, có kiểm checksum, image ID và digest ở từng bước. Hồ sơ phát hành `release.json` nối ba loại SHA thường bị nhầm lẫn: image ID, checksum file, digest registry.
3. **Thiết kế policy có chiều sâu.** Hai policy tách biệt, mỗi lần từ chối chỉ ra đúng một nguyên nhân. Policy kiểm cả init container, đòi digest đủ 64 ký tự hex, và xác minh mọi image chứ không chỉ image của registry tin cậy.
4. **Bộ kiểm thử có đối chứng và bằng chứng.** Fixture được dựng để chỉ khác đúng một yếu tố. Các ca mở rộng thử những đường vòng thực tế: sai người ký, verifier ngừng hoạt động, người triển khai vượt quyền. Kết quả admission được đối chiếu với xác minh độc lập bằng Notation CLI.
5. **Kinh nghiệm tích hợp thực tế**, ghi lại như đóng góp cho người làm sau:
   - extension `kyverno-notation-aws` không chạy được với Kyverno 1.19 và ghi bearer token vào log; đồ án đã vá mà không tắt xác thực;
   - bản phát hành chính thức của extension có 6 CVE Critical; đồ án tự build và vá về 0 Critical / 0 High;
   - dạng claim OIDC thực tế khác mẫu trong tài liệu khi repo bật *immutable subject claims*;
   - cần che account ID khi repo công khai;
   - "image ID" mang nghĩa khác nhau tùy image store của Docker.

## 6.2. Hạn chế

- **"Chỉ image đạt mới được ký" dựa vào pipeline và phân quyền**, không dựa vào ECR. ECR Managed Signing ký mọi image push vào repository khớp filter; danh tính nào có quyền push và ký đều tạo được chữ ký hợp lệ.
- **Chữ ký chỉ chứng minh nguồn gốc, không chứng minh nội dung lành tính.** Pipeline hoặc role publisher bị chiếm quyền vẫn có thể phát hành image độc hại có chữ ký hợp lệ.
- **SBOM và kết quả quét chưa được ký.** Admission chưa kiểm attestation, nên chưa đòi được bằng chứng "image này đã qua quét" ở bước triển khai.
- **Admission chỉ kiểm yêu cầu mới.** Pod đã chạy không bị gỡ khi chữ ký bị thu hồi hoặc khi CVE mới được công bố.
- **Quét lỗ hổng phụ thuộc DB tại thời điểm quét**, không phát hiện zero-day.
- **Môi trường là kind một node.** Bước triển khai còn thủ công; credential của verifier sống tối đa 1 giờ; kiểm RBAC dùng impersonation từ kubeconfig quản trị.
- **Thành phần có rủi ro vòng đời.** Policy 2 dùng `ClusterPolicy` (đã deprecated). Kyverno 1.19 chỉ còn được vá tới khi 1.21 phát hành. Extension là bản tự build từ upstream sắp lưu trữ.
- **Cỡ mẫu đo đạc nhỏ:** đủ để kết luận về hành vi chặn, chưa đủ để kết luận thống kê về hiệu năng.

## 6.3. Hướng phát triển

Các hướng phát triển, xếp theo mức độ bổ sung trực tiếp cho hạn chế ở trên:

| # | Hướng phát triển | Giải quyết hạn chế |
|---|---|---|
| 1 | **Ký và kiểm attestation cho SBOM, kết quả quét và provenance** (in-toto/SLSA). Admission chỉ nhận image có attestation "đã quét, 0 Critical" do pipeline ký | Chữ ký chưa chứng minh image đã qua quét; SBOM chưa được ký |
| 2 | **Gắn SBOM vào ECR dưới dạng OCI referrer** (`oras attach` [44]) để SBOM đi cùng digest, không phụ thuộc thời hạn lưu artifact của GitHub (30 ngày) | Truy vết dài hạn |
| 3 | **Quét lại định kỳ từ SBOM** (`trivy sbom`, hoặc nạp vào Dependency-Track) để phát hiện CVE mới trên image đang chạy mà không phải build lại | Kết quả quét chỉ đúng tại thời điểm quét |
| 4 | **Khắc phục workload đang chạy:** khi chữ ký bị thu hồi hoặc phát hiện CVE mới, tự động tìm Pod dùng digest đó (nhờ truy vết) và cảnh báo hoặc thay thế | Admission không gỡ Pod đã chạy |
| 5 | **Chuyển sang EKS:** IRSA/Pod Identity cho extension (credential tự làm mới), IAM role của node để pull image, Access Entry giới hạn namespace, job `deploy` qua role deployer với trust theo `environment` | Credential 1 giờ; triển khai thủ công; RBAC dùng impersonation |
| 6 | **GitOps (Argo CD / Flux):** cụm tự kéo cấu hình từ Git, không cần quyền triển khai từ bên ngoài | Triển khai thủ công; giảm quyền của CI |
| 7 | **Chuyển Policy 2 sang policy CEL của Kyverno** (`ImageValidatingPolicy`) hoặc phương án được hỗ trợ lâu dài, khi có cách tích hợp plugin AWS Signer; bật cache xác minh | `ClusterPolicy` deprecated; extension sắp hết bảo trì; độ trễ admission |
| 8 | **Hạ tầng dưới dạng mã (Terraform)** cho ECR, Signer, IAM, OIDC thay cho script AWS CLI; dùng **workflow dependency lockfile** của GitHub Actions, mức bảo vệ mà GitHub xếp trên việc ghim SHA [39] | Tái lập và rà soát thay đổi hạ tầng; bảo vệ phụ thuộc của pipeline |
| 9 | **Mở rộng gate:** chặn cả High có bản vá; dùng VEX để ghi nhận lỗ hổng không ảnh hưởng; kiểm giấy phép (license compliance) từ SBOM | Gate hiện chỉ chặn Critical |
| 10 | **Image đa kiến trúc** (index `linux/amd64` + `linux/arm64`) và kiểm ephemeral container trong policy (hiện chặn bằng RBAC) | Phạm vi hiện tại một kiến trúc |

Hướng 1 là bước tiến quan trọng nhất. Nó biến giả định "chỉ pipeline mới ký được, nên image có chữ ký là image đã qua quét" thành một điều kiện **được kiểm tra** tại admission. Như vậy niềm tin không còn chỉ dựa vào phân quyền.
