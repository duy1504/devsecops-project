# podinfo — build từ source tại tag đã ghim (app/, xem docs/upstream.md). Kế hoạch mục 7.2.
# Base image ghim theo digest (index đa kiến trúc; build luôn dùng --platform linux/amd64). Nguồn: docs/versions.md.
# GO_VERSION theo dòng `go` trong app/go.mod (6.17.0 yêu cầu go 1.27.0).
FROM golang:1.27.4-alpine@sha256:70bd7ddea8b6cbe5d6943cde279d6b67feb10cc924fb9100d1d8757c1575b280 AS builder
# Không tự tải toolchain khác: image Go cũ hơn yêu cầu thì build lỗi rõ ràng
ENV GOTOOLCHAIN=local
WORKDIR /src
COPY app/go.mod app/go.sum ./
RUN go mod download
COPY app/ .
# REVISION: commit podinfo upstream (không phải secret), hiện ở endpoint /version
ARG REVISION=unknown
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=${REVISION}" \
    -o /out/podinfo ./cmd/podinfo

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
WORKDIR /home/app
COPY --from=builder /out/podinfo /home/app/podinfo
COPY --from=builder /src/ui /home/app/ui
EXPOSE 9898
# UID/GID dạng SỐ: với runAsNonRoot, kubelet không xác minh được user dạng tên (CreateContainerConfigError)
USER 65532:65532
ENTRYPOINT ["/home/app/podinfo", "--port=9898", "--ui-path=/home/app/ui"]
