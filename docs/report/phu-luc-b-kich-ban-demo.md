# Phụ lục B. Kịch bản demo và câu hỏi bảo vệ

> Theo kế hoạch mục 16. Thời lượng 12–15 phút. Lệnh chạy trực tiếp dùng `scripts/demo.sh` trên WSL: một lệnh cho mỗi ca, không phải gõ account, region hay digest, và mặc định che account ID trên màn hình. Lệnh cho TC02/TC03 (mở PR từ nhánh demo) nằm ở `demo/commands.md`.

## B.1. Chuẩn bị

### Một ngày trước

- [ ] `bash scripts/preflight.sh` → phải **ĐẠT** (33 mục: công cụ, cụm, policy, AWS, fixture, credential).
- [ ] Kiểm lại fixture TC03 còn Critical theo DB Trivy hiện tại (lệnh trong `demo/commands.md`). DB thay đổi theo thời gian.
- [ ] Tập chạy toàn bộ kịch bản một lượt và bấm giờ.
- [ ] Quay **video dự phòng** của toàn bộ phần chạy trực tiếp. Chuẩn bị sẵn các thư mục bằng chứng (`docs/evidence/`) để mở khi mạng hoặc cloud gặp sự cố.
- [ ] **Không** nâng cấp công cụ, không sửa policy sát giờ demo.

### 30 phút trước

```bash
# Windows: mở Docker Desktop; chờ cụm kind lên
aws sso login --profile devsecops
bash scripts/refresh-lab-credentials.sh   # credential verifier chỉ sống ≤ 1 giờ → làm SÁT giờ
bash scripts/demo.sh check
bash scripts/demo.sh tc01                 # chạy thử: Pod Running, /version trả 6.17.0
```

Mở sẵn trên trình duyệt:
1. Sơ đồ Hình 3.1.
2. Run thành công mới nhất trên `main` (tab Actions), có đủ ba job `verify`, `policy-test`, `publish`.
3. Run TC02 ([44134429165](https://github.com/duy1504/devsecops-project/actions/runs/44134429165)) và TC03 ([44135534522](https://github.com/duy1504/devsecops-project/actions/runs/44135534522)).
4. ECR console: repository `podinfo`, image `sha-…` mới nhất cùng chữ ký đi kèm.

Mở hai terminal WSL tại thư mục repo, cỡ chữ lớn: **T1** cho các ca admission, **T2** cho truy vết và lệnh phụ.

## B.2. Kịch bản

| Thời gian | Phần | Thao tác | Lời dẫn chính |
|---|---|---|---|
| 0:00–1:30 | Bài toán | Mở Hình 3.1 | Image "chạy được" chưa chắc đáng tin. Bốn tình huống của đề cương. Hai lớp kiểm soát: CI chặn trước khi phát hành, admission chặn trước khi chạy; chữ ký số nối hai lớp |
| 1:30–4:30 | Pipeline thành công | Tab Actions: run trên `main` | Đồ thị job: `verify` không có quyền AWS; `publish` chỉ chạy trên `main` qua OIDC, không có access key. Job summary: test, Gitleaks, SBOM, Trivy, gate 0 Critical. Artifact `security-reports`: SBOM CycloneDX, báo cáo Trivy. Log `publish`: kiểm checksum + image ID (image được push chính là image đã quét), push tag `sha-…`, "Signed by expected profile". Artifact `release`: `release.json` |
| | | ECR console | Tag `sha-<commit>-run-<id>-<attempt>`, tag IMMUTABLE. Chữ ký Notation là artifact riêng trỏ vào digest, do ECR Managed Signing tạo khoảng 2 s sau khi push. Pipeline không có lệnh ký nào |
| 4:30–6:30 | Triển khai hợp lệ | **T1:** `bash scripts/demo.sh tc01` | Pod chạy bằng **digest**, không phải tag. Hai policy đã nhận Pod này: đúng nguồn, chữ ký hợp lệ của đúng profile. `/version` trả 6.17.0 / commit upstream. `release.json` nối commit, run, SBOM, báo cáo CVE |
| 6:30–8:00 | TC02, TC03 (đã chạy) | Mở run TC02, TC03 | TC02: chuỗi `DEMO_SECRET_` giả, Gitleaks chặn sau 29 s, chưa build gì. Push Protection của GitHub **không** chặn chuỗi này, nên gate riêng là cần thiết. TC03: `alpine:3.14.0`, gate báo 4 Critical, exit 1, không có artifact phát hành |
| 8:00–11:00 | TC04, TC05 (chạy trực tiếp) | **T1:** `bash scripts/demo.sh tc04` | Cùng repository, đúng digest, nên Policy 1 cho qua. Policy 2 từ chối vì `no signature is associated`. Image này được push **trước** khi bật ký, nên chưa bao giờ có chữ ký |
| | | **T1:** `bash scripts/demo.sh tc05` | Image podinfo **gốc** của tác giả trên ghcr.io, digest thật, nội dung lành tính, nhưng sai nguồn nên Policy 1 từ chối. Cả Policy 2 cũng không có trust policy cho registry này |
| | *(nếu còn giờ)* | **T1:** `bash scripts/demo.sh tc06` | Có chữ ký hợp lệ về mật mã, nhưng của profile B, nên bị từ chối vì `Signature publisher doesn't match any trusted identities` |
| 11:00–13:00 | Truy vết | **T2:** `bash scripts/demo.sh trace` | Từ Pod: digest → tag trên ECR chứa commit và run → chữ ký của đúng profile → run, commit, SBOM. Không cần cơ sở dữ liệu riêng |
| 13:00–15:00 | Kết luận | Slide giới hạn và hướng phát triển | 10/10 ca đạt. Giới hạn: ECR ký mọi image push vào repo nên niềm tin dựa vào phân quyền; chữ ký không chứng minh nội dung lành tính; SBOM chưa được ký; admission không gỡ Pod đã chạy. Hướng phát triển quan trọng nhất: ký attestation cho kết quả quét và kiểm ở admission |

**Nếu bị hỏi về fail-closed (TC09):** không chạy trực tiếp, vì tắt extension sẽ chặn mọi Pod mới trong lúc demo. Mở bằng chứng `docs/evidence/spike/policy2-kind/` và Chương 5 mục 5.3.5: Pod hợp lệ bị chặn sau khoảng 0,3 s khi extension tắt, bật lại thì được nhận. Nếu còn thời gian và hội đồng muốn xem tận mắt:

```bash
kubectl -n kyverno-notation-aws scale deploy/kyverno-notation-aws --replicas=0
bash scripts/demo.sh tc04     # bị chặn vì không kết nối được verifier, không phải vì thiếu chữ ký
kubectl -n kyverno-notation-aws scale deploy/kyverno-notation-aws --replicas=1
kubectl -n kyverno-notation-aws rollout status deploy/kyverno-notation-aws
```

## B.3. Khi có sự cố

| Sự cố | Xử lý |
|---|---|
| TC04/TC06 bị từ chối nhưng thông báo là lỗi kết nối hoặc credential, không phải lý do chữ ký | Credential verifier hết hạn: `bash scripts/refresh-lab-credentials.sh`, chạy lại. Giải thích: đây chính là hành vi fail-closed |
| Mất mạng, AWS hoặc GitHub không truy cập được | Chuyển sang video dự phòng và bằng chứng gốc trong `docs/evidence/` (có thời điểm UTC); nói rõ phần nào không chạy trực tiếp |
| Docker/kind không lên | Tắt Docker Desktop → `wsl --shutdown` → mở lại; nếu không kịp, dùng video |
| `demo.sh tc01` không thấy Pod | Pod bị chặn khi khởi động lại do credential hết hạn: refresh credential; ReplicaSet tự tạo lại Pod |

## B.4. Câu hỏi bảo vệ

| Câu hỏi | Trả lời (kèm bằng chứng của đồ án) |
|---|---|
| SBOM khác báo cáo lỗ hổng thế nào? | SBOM là **danh mục thành phần** (1032 component của podinfo). Scanner đối chiếu danh mục đó với dữ liệu advisory để ra báo cáo lỗ hổng. SBOM không đổi theo thời gian; báo cáo lỗ hổng thì đổi khi có CVE mới, nên có thể quét lại từ SBOM mà không cần build lại |
| Vì sao vừa quét vừa ký? | Quét đánh giá rủi ro **đã biết** tại một thời điểm. Ký ràng buộc **nội dung** (digest) với **danh tính** phát hành. Quét trả lời "có lỗ hổng không", ký trả lời "có đúng image đã quét, do pipeline phát hành không". Thiếu một trong hai thì không đủ |
| ECR có tự chặn image Critical không? | Không. ECR Managed Signing ký **mọi** image push vào repo khớp filter. Gate trong CI quyết định có push hay không (TC03: không có artifact phát hành). Chỉ role publisher mới push được, và role chỉ assume được từ nhánh `main` |
| Vì sao triển khai bằng digest? | Digest cố định chính xác nội dung đã quét, đã ký và đã xác minh; tag có thể bị trỏ sang image khác. Policy 1 từ chối tag (TC07) và digest không đủ 64 hex |
| Image có chữ ký nhưng độc hại thì sao? | Vẫn có thể được nhận nếu pipeline hoặc role publisher bị lạm dụng, vì chữ ký chứng minh **ai** phát hành chứ không chứng minh nội dung lành tính (bài học SolarWinds). Biện pháp: bảo vệ CI và IAM (branch protection, OIDC chỉ `main`, ghim action theo SHA), và hướng phát triển là kiểm attestation kết quả quét ở admission |
| Verifier lỗi thì sao? | Fail-closed: Pod mới bị từ chối (TC09, khoảng 0,3 s). Cái giá là tính sẵn sàng; trên kind còn phụ thuộc credential 1 giờ. Trên EKS sẽ dùng IRSA/Pod Identity để credential tự làm mới |
| Thu hồi profile thì Pod cũ có dừng không? | Không. Admission chỉ kiểm yêu cầu mới. Cần cơ chế rà soát riêng: dùng truy vết để tìm Pod chạy digest bị ảnh hưởng (hướng phát triển 4) |
| Đi vòng CI bằng `kubectl` được không? | Vẫn gặp admission: TC04 và TC05 chính là mô phỏng điều này. Nhưng cần hạn chế quyền push, quyền sửa policy và namespace ngoại lệ: deployer không đọc được Secret, không exec, không sửa policy (TC10) |
| Sao không dùng Cosign? | Đề tài dùng AWS Signer và ECR Managed Signing, vốn tạo chữ ký định dạng **Notation** (Notary Project). Cosign thuộc hệ sinh thái Sigstore, có định dạng và cách xác minh khác |
| Sao lại tự build extension? | Bản phát hành chính thức `v1.1` có 6 CVE Critical và upstream sắp lưu trữ. Đồ án áp chính gate 0 Critical cho extension, và vá thêm hai lỗi phát hiện khi chạy: không xác thực được token của Kyverno 1.19, và ghi bearer token vào log |
| Sao dùng Kyverno 1.19 mà không lên 1.20? | Extension tích hợp qua `ClusterPolicy`, đã bị đánh dấu deprecated. Nâng cấp đòi hỏi kiểm lại tương thích. 1.19 vẫn được vá CVE nghiêm trọng tới khi 1.21 phát hành. Policy 1 đã viết bằng CEL để sẵn sàng chuyển đổi |
| Chi phí bảo mật bao nhiêu? | Các bước quét dưới 10 s trong job `verify` (trung bình 105,5 s); chờ ký khoảng 2 s; xác minh chữ ký thêm 1,5–2 s cho mỗi Pod (Chương 5 mục 5.4) |
