# Lệnh demo theo thứ tự

Chạy trong **PowerShell** tại `C:\Teo\DevOps` cho git/gh (xem quy tắc 9 trong `CLAUDE.md`). Chạy trong **WSL** cho docker/trivy/kubectl. `main` đã bật branch protection: mọi thay đổi phải qua PR, và hai check `verify` + `policy-test` phải đạt.

Biến dùng chung (PowerShell):

```powershell
$gh = Join-Path $env:LOCALAPPDATA 'Programs\gh\bin\gh.exe'
$repo = 'duy1504/devsecops-project'
```

## TC02 — secret trong mã nguồn (Gitleaks)

Chuỗi phải là **giả**: `DEMO_SECRET_` + 32 hex, sinh ngẫu nhiên mỗi lần chạy. Nhánh demo **không bao giờ merge**; branch protection chặn merge vì `verify` fail.

```powershell
git switch main; git pull --ff-only
git switch -c demo/leak-secret
$hex = -join ((1..16) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
"DEMO_TOKEN=DEMO_SECRET_$hex" | Out-File -Encoding ascii demo/leak.env.example
git add demo/leak.env.example
git commit -m "demo TC02: thêm secret giả (không merge)"
git push -u origin demo/leak-secret
& $gh pr create --repo $repo --base main --head demo/leak-secret --title "[DEMO TC02] Secret giả – không merge" --body "Ca kiểm thử TC02: Gitleaks phải chặn. Không merge."
& $gh pr checks --repo $repo --watch          # mong đợi: verify fail ở bước Gitleaks
```

Thu bằng chứng: trang run (bước Gitleaks đỏ, exit code), artifact `security-reports-*` (`gitleaks.json` đã redact), job summary, trạng thái PR "Merging is blocked".

Dọn dẹp:

```powershell
& $gh pr close <số PR> --repo $repo --delete-branch
git switch main; git branch -D demo/leak-secret
```

GitHub Push Protection là lớp kiểm soát **khác**: nó chỉ chặn mẫu secret của nhà cung cấp. `DEMO_SECRET_` không thuộc mẫu đó nên push qua được, và Gitleaks mới là thứ chặn.

## TC03 — image có CVE Critical (Trivy gate)

Fixture: `demo/Dockerfile.vulnerable` (runtime `alpine:3.14.0` ghim digest, 4 Critical theo scan thật). Nhánh demo thay `Dockerfile` gốc bằng fixture để CI build đúng image đó.

```powershell
git switch main; git pull --ff-only
git switch -c demo/critical-cve
Copy-Item demo/Dockerfile.vulnerable Dockerfile -Force
git add Dockerfile
git commit -m "demo TC03: build image có CVE Critical (không merge)"
git push -u origin demo/critical-cve
& $gh pr create --repo $repo --base main --head demo/critical-cve --title "[DEMO TC03] Image có CVE Critical – không merge" --body "Ca kiểm thử TC03: gate Trivy phải chặn. Không merge."
& $gh pr checks --repo $repo --watch          # mong đợi: verify fail ở bước "GATE – no CRITICAL"
```

Thu bằng chứng: log bước GATE (`Critical vulnerabilities: N`, exit code), `trivy.json`/`trivy.txt` trong artifact (CVE, package, installed/fixed version), `trivy-version.json` (phiên bản scanner, thời điểm DB), job summary. Không có artifact `approved-image-*` vì đây là PR, không phải push vào `main`.

Dọn dẹp: giống TC02 (`gh pr close … --delete-branch`).

Kiểm tra fixture còn Critical trước buổi bảo vệ (chạy trong WSL; DB thay đổi theo thời gian):

```bash
docker buildx build --platform linux/amd64 --load -f demo/Dockerfile.vulnerable -t podinfo:tc03 .
docker save podinfo:tc03 -o /tmp/tc03.tar
trivy image --input /tmp/tc03.tar --scanners vuln --severity CRITICAL
```

## TC05, TC07, TC08 — Policy 1 trên cụm kind

```bash
bash scripts/cluster-up.sh
export ECR_IMAGE=<account>.dkr.ecr.ap-southeast-1.amazonaws.com/podinfo   # mục 4.3 kế hoạch
export APP_DIGEST=sha256:<digest image hợp lệ từ release.json>
bash scripts/apply-policies.sh
bash scripts/test-policy1-cluster.sh       # bằng chứng: reports/admission/<thời điểm>/
bash scripts/check-rbac.sh                 # TC10 (phần auth can-i)
```
