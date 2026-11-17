# Mã nguồn kế thừa

Đóng góp của đồ án là **quy trình bảo mật chuỗi cung ứng**. Workload chỉ dùng để minh họa và không phải do đồ án tự phát triển.

## podinfo

| Mục | Giá trị |
|---|---|
| Nguồn | https://github.com/stefanprodan/podinfo |
| Tag | `6.17.0` (tag annotated, có chữ ký GPG; commit ngày 26/10/2026) |
| Commit | `fd3a834ed8d14b80ea334cf8a2fddd4597924da6` |
| Ngày lấy mã | 17/11/2026 |
| License | Apache License 2.0 (`app/LICENSE`, giữ nguyên) |
| Cách lấy | `scripts/vendor-podinfo.sh`: clone tag, kiểm tra đúng commit, `git archive` vào `app/` (không có `.git`) |
| Thay đổi so với upstream | **Không sửa mã.** Đồ án dùng `Dockerfile` riêng ở thư mục gốc, không dùng `app/Dockerfile` của upstream |
| Yêu cầu Go | `go 1.27.0` (`app/go.mod`) |

Ghi chú:
- Có 3 dương tính giả Gitleaks trong mã upstream: chuỗi `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9`, là header JWT công khai `{"alg":"HS256","typ":"JWT"}`. Nó xuất hiện ở `cmd/podinfo/main.go` (giá trị mặc định của cờ `--jwt-secret`) và ở hai file `token_test.go`. Đã allowlist ở cấp rule, điều kiện AND (đúng file và đúng chuỗi), trong `.gitleaks.toml`. Đã kiểm tra rằng secret khác trong cùng các file đó vẫn bị phát hiện.
- Upstream có sẵn thư mục `.github/`, `.cosign/`, `.notation/`, `charts/`… nằm trong `app/`. GitHub Actions chỉ đọc `.github/` ở thư mục gốc, nên workflow của upstream không chạy.

## kyverno-notation-aws

Tự build từ source và có bản vá cục bộ. Xem `docs/versions.md` mục 2b và `scripts/build-notation-ext.sh`.
