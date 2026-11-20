# Biến cấu hình thống nhất (kế hoạch mục 4.3). Dùng: source scripts/aws-env.sh
# Không ghi account ID vào repo: lấy từ STS lúc chạy.
export PATH="$HOME/.local/bin:$PATH"
# Máy lab dùng profile SSO; CI (OIDC) đã có credential qua biến môi trường nên không đặt profile.
if [ -z "${AWS_PROFILE:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then export AWS_PROFILE=devsecops; fi
export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
export AWS_PAGER=""
if ! AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"; then
  echo "Chưa đăng nhập AWS. Chạy: aws sso login --profile ${AWS_PROFILE:-devsecops}" >&2
  return 1 2>/dev/null || exit 1
fi
export AWS_ACCOUNT_ID
export ECR_REPOSITORY=podinfo
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ECR_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}"
export SIGNING_PROFILE=podinfo_signing_profile
export SIGNING_PROFILE_ARN="arn:aws:signer:${AWS_REGION}:${AWS_ACCOUNT_ID}:/signing-profiles/${SIGNING_PROFILE}"
export WRONG_SIGNING_PROFILE=podinfo_wrong_signer        # profile B – chỉ dùng tạo fixture TC06
export WRONG_SIGNING_PROFILE_ARN="arn:aws:signer:${AWS_REGION}:${AWS_ACCOUNT_ID}:/signing-profiles/${WRONG_SIGNING_PROFILE}"
export APP_NAMESPACE=app
export TEST_NAMESPACE=demo
