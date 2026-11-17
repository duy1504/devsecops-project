# Fixture TC03 — image CỐ Ý có CVE Critical để chứng minh gate Trivy chặn được (kế hoạch mục 12.2).
# KHÔNG dùng để phát hành. CI không build file này trên main; ca demo dùng nhánh demo/critical-cve
# thay Dockerfile gốc bằng file này rồi mở PR (scripts/tc03-prepare-branch.sh).
#
# Giống Dockerfile gốc, chỉ khác runtime: alpine:3.14.0 (ghim digest). Kết quả scan thật 18/11/2026,
# Trivy 0.76.2, DB 2026-11-16T18:50:18Z: 4 Critical — CVE-2022-37434 (zlib 1.2.11-r3), CVE-2021-3711
# (libcrypto1.1/libssl1.1 1.1.1k-r0), CVE-2021-36159 (apk-tools 2.12.5-r1). Kiểm tra lại trước buổi bảo vệ.
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

FROM alpine:3.14.0@sha256:adab3844f497ab9171f070d4cae4114b5aec565ac772e2f2579405b78be67c96
WORKDIR /home/app
COPY --from=builder /out/podinfo /home/app/podinfo
COPY --from=builder /src/ui /home/app/ui
EXPOSE 9898
USER 65532:65532
ENTRYPOINT ["/home/app/podinfo", "--port=9898", "--ui-path=/home/app/ui"]
