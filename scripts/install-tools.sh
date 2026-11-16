#!/usr/bin/env bash
# Cài công cụ của đồ án vào ~/.local (KHÔNG cần sudo) trên WSL2 Ubuntu / Linux x86_64.
# Mỗi công cụ ghim phiên bản + SHA-256; sai hash thì dừng. Nguồn và ngày kiểm tra: docs/versions.md.
# Đổi phiên bản = đổi cả VERSION lẫn SHA256 ở đây, rồi cập nhật docs/versions.md.
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
NOTATION_PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/notation/plugins/com.amazonaws.signer.notation.plugin"

GO_VERSION=1.27.4;        GO_SHA256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840
AWSCLI_VERSION=2.40.4;    AWSCLI_SHA256=81f573c2a0ace70cfb97aa4d014c17cbd605cb04cbad09adbc7aaf9c0979ae8e
HELM_VERSION=v4.3.2;      HELM_SHA256=d1c0278d46beab79582d7e50f5b3dc206944ba8e577cde618513fd07daa53983
KIND_VERSION=v0.33.0;     KIND_SHA256=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d
JQ_VERSION=1.8.2;         JQ_SHA256=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
TRIVY_VERSION=0.76.2;     TRIVY_SHA256=bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf
SYFT_VERSION=1.56.0;      SYFT_SHA256=1c2493cfcf52d3367d6cb25780d9190c111c2219c34c820574c43e8bae15c528
GITLEAKS_VERSION=8.30.1;  GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
NOTATION_VERSION=1.3.2;   NOTATION_SHA256=e1a0f060308086bf8020b2d31defb7c5348f133ca0dba6a1a7820ef3cbb6dfe5
KYVERNO_VERSION=v1.19.2;  KYVERNO_SHA256=357eaf1df8bc24ddd5a73979fadeaae6a032e8710f11af264229756e4956bf4a
# AWS chỉ có link "latest" cho plugin → hash ghim lúc kiểm tra; AWS ra bản mới thì script dừng ở đây.
SIGNER_PLUGIN_URL=https://d2hvyiie56hcat.cloudfront.net/linux/amd64/plugin/latest/notation-aws-signer-plugin.zip
SIGNER_PLUGIN_SHA256=f8efa548932edc4851f4ba464496994bad753cdf21cd32baa575f7291a26c7b9

[ "$(uname -m)" = "x86_64" ] || { echo "Script chỉ hỗ trợ x86_64" >&2; exit 1; }
mkdir -p "$BIN"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fetch() {  # fetch <url> <sha256> <tên file>
  echo "→ $3"
  curl -fsSL --retry 3 -o "$TMP/$3" "$1"
  echo "$2  $TMP/$3" | sha256sum -c --quiet - || { echo "SHA-256 KHÔNG KHỚP: $3 — dừng." >&2; exit 1; }
}
unzip_keep_mode() {  # Ubuntu chưa có unzip; giải nén bằng Python và giữ quyền thực thi
  python3 - "$1" "$2" <<'PY'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for info in z.infolist():
        path = z.extract(info, sys.argv[2])
        mode = (info.external_attr >> 16) & 0o777
        if mode:
            os.chmod(path, mode)
PY
}
tar_bin() {  # tar_bin <tên file> <đường dẫn trong tar> <tên lệnh>
  tar -xzf "$TMP/$1" -C "$TMP" "$2"
  install -m 0755 "$TMP/$2" "$BIN/$3"
}

fetch "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" "$GO_SHA256" go.tgz
rm -rf "$PREFIX/go" && tar -xzf "$TMP/go.tgz" -C "$PREFIX"
ln -sf "$PREFIX/go/bin/go" "$BIN/go" && ln -sf "$PREFIX/go/bin/gofmt" "$BIN/gofmt"

fetch "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" "$AWSCLI_SHA256" awscli.zip
unzip_keep_mode "$TMP/awscli.zip" "$TMP"
"$TMP/aws/install" -i "$PREFIX/aws-cli" -b "$BIN" --update >/dev/null

fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" "$HELM_SHA256" helm.tgz
tar_bin helm.tgz linux-amd64/helm helm

fetch "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" "$KIND_SHA256" kind
install -m 0755 "$TMP/kind" "$BIN/kind"

fetch "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" "$JQ_SHA256" jq
install -m 0755 "$TMP/jq" "$BIN/jq"

fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "$TRIVY_SHA256" trivy.tgz
tar_bin trivy.tgz trivy trivy

fetch "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.tar.gz" "$SYFT_SHA256" syft.tgz
tar_bin syft.tgz syft syft

fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "$GITLEAKS_SHA256" gitleaks.tgz
tar_bin gitleaks.tgz gitleaks gitleaks

fetch "https://github.com/notaryproject/notation/releases/download/v${NOTATION_VERSION}/notation_${NOTATION_VERSION}_linux_amd64.tar.gz" "$NOTATION_SHA256" notation.tgz
tar_bin notation.tgz notation notation

fetch "$SIGNER_PLUGIN_URL" "$SIGNER_PLUGIN_SHA256" signer-plugin.zip
mkdir -p "$NOTATION_PLUGIN_DIR"
unzip_keep_mode "$TMP/signer-plugin.zip" "$NOTATION_PLUGIN_DIR"
chmod 0755 "$NOTATION_PLUGIN_DIR/notation-com.amazonaws.signer.notation.plugin"

fetch "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz" "$KYVERNO_SHA256" kyverno.tgz
tar_bin kyverno.tgz kyverno kyverno

# ~/.local/bin vào PATH (Ubuntu chỉ tự thêm ở login shell khi thư mục đã tồn tại)
MARK="# >>> devsecops-project tools >>>"
grep -qF "$MARK" "$HOME/.bashrc" 2>/dev/null || printf '\n%s\nexport PATH="%s:$PATH"\n# <<< devsecops-project tools <<<\n' "$MARK" "$BIN" >> "$HOME/.bashrc"

export PATH="$BIN:$PATH"
echo; echo "== Phiên bản đã cài"
go version
aws --version
helm version --short
kind version
jq --version
trivy --version | sed -n 1p   # sed đọc hết luồng → tránh SIGPIPE (mã 141) khi có pipefail
syft version | grep -E '^Version'
gitleaks version
notation version | grep -E '^Version'
notation plugin ls
kyverno version | sed -n 1p
