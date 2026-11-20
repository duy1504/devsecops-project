#!/usr/bin/env bash
# Spike bước 1 (kế hoạch mục 6.1, 8.1): tạo ECR repo podinfo, tag IMMUTABLE, mã hóa KMS.
# KHÔNG bật signing rule ở đây (fixture phải tạo trước). Chạy lại an toàn.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/aws-env.sh
if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
  echo "Repo $ECR_REPOSITORY đã tồn tại, không tạo lại."
else
  aws ecr create-repository --repository-name "$ECR_REPOSITORY" \
    --image-tag-mutability IMMUTABLE \
    --encryption-configuration encryptionType=KMS >/dev/null
  echo "Đã tạo repo $ECR_REPOSITORY."
fi
aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --output table \
  --query 'repositories[0].{name:repositoryName,tagMutability:imageTagMutability,encryption:encryptionConfiguration.encryptionType,scanOnPush:imageScanningConfiguration.scanOnPush}'
