# Tài liệu tham khảo

> Dùng chung cho toàn báo cáo; trong văn bản trích theo số `[n]`. Mọi liên kết được kiểm tra truy cập được (HTTP 200) ngày **28/11/2026**. Riêng [9] chặn truy cập tự động (HTTP 403), nên cần mở bằng trình duyệt để xác nhận. Với tài liệu thay đổi theo phiên bản (Kyverno, AWS CLI), nội dung được đối chiếu với đúng phiên bản đồ án dùng (`docs/versions.md`).

## Khung tham chiếu và tiêu chuẩn

[1] OpenSSF. *SLSA Specification v1.0*. https://slsa.dev/spec/v1.0/

[2] NIST. *SP 800-218: Secure Software Development Framework (SSDF) Version 1.1*. https://csrc.nist.gov/pubs/sp/800/218/final

[3] Open Container Initiative. *OCI Image Format Specification*. https://github.com/opencontainers/image-spec

[4] Open Container Initiative. *OCI Distribution Specification* (v1.1: trường `subject`, Referrers API). https://github.com/opencontainers/distribution-spec

[5] The Linux Foundation. *SPDX* (ISO/IEC 5962:2021). https://spdx.dev/

[6] OWASP. *CycloneDX* (ECMA-424). https://cyclonedx.org/

[7] Notary Project (CNCF). *Notation*. https://notaryproject.dev/

[8] Sigstore (OpenSSF). *Cosign, Fulcio, Rekor*. https://www.sigstore.dev/

## Sự cố chuỗi cung ứng

[9] CISA. *Advisory AA20-352A: Advanced Persistent Threat Compromise of Government Agencies, Critical Infrastructure, and Private Sector Organizations* (SolarWinds). https://www.cisa.gov/news-events/cybersecurity-advisories/aa20-352a

[10] Codecov. *Bash Uploader Security Update* (2021). https://about.codecov.io/security-update/

[11] NIST NVD. *CVE-2024-3094* (xz-utils). https://nvd.nist.gov/vuln/detail/CVE-2024-3094

[12] NIST NVD. *CVE-2025-30066* (tj-actions/changed-files). https://nvd.nist.gov/vuln/detail/CVE-2025-30066

## AWS

[13] Amazon ECR User Guide. *Managed signing*. https://docs.aws.amazon.com/AmazonECR/latest/userguide/managed-signing.html

[14] AWS CLI Reference. *ecr put-signing-configuration*. https://docs.aws.amazon.com/cli/latest/reference/ecr/put-signing-configuration.html

[15] AWS CLI Reference. *ecr describe-image-signing-status*. https://docs.aws.amazon.com/cli/latest/reference/ecr/describe-image-signing-status.html

[16] AWS Signer Developer Guide. *Sign an image*. https://docs.aws.amazon.com/signer/latest/developerguide/image-signing-steps.html

[17] AWS Signer Developer Guide. *Prerequisites for signing container images*. https://docs.aws.amazon.com/signer/latest/developerguide/image-signing-prerequisites.html

[18] AWS Signer Developer Guide. *Locally verify an image after signing*. https://docs.aws.amazon.com/signer/latest/developerguide/image-verification.html

[19] AWS Signer Developer Guide. *Verify an image in Amazon EKS or Kubernetes clusters*. https://docs.aws.amazon.com/signer/latest/developerguide/kubernetes-verification.html

[20] Amazon EKS User Guide. *Validate container image signatures during deployment*. https://docs.aws.amazon.com/eks/latest/userguide/image-verification.html

[21] AWS. *Service Authorization Reference: Amazon Elastic Container Registry*. https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonelasticcontainerregistry.html

[22] AWS IAM User Guide. *Validate policies with IAM Access Analyzer*. https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-validation.html

## Kubernetes và Kyverno

[23] Kubernetes Documentation. *Admission Control in Kubernetes*. https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/

[24] Kubernetes Documentation. *Validating Admission Policy*. https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/

[25] Kubernetes Documentation. *Using RBAC Authorization*. https://kubernetes.io/docs/reference/access-authn-authz/rbac/

[26] Kubernetes Documentation. *Images*. https://kubernetes.io/docs/concepts/containers/images/

[27] kind. *Quick Start*. https://kind.sigs.k8s.io/docs/user/quick-start/

[28] Kyverno Documentation. *Installation*. https://kyverno.io/docs/installation/installation/

[29] Kyverno Documentation. *Policy Types Overview*. https://kyverno.io/docs/policy-types/overview/

[30] Kyverno Blog. *Announcing Kyverno Release 1.18* (chính sách hỗ trợ N-1). https://kyverno.io/blog/2026/04/24/announcing-kyverno-release-1.18/

[31] Kyverno Blog. *Announcing Kyverno Release 1.19*. https://kyverno.io/blog/2026/08/20/announcing-kyverno-release-1.19

[32] Kyverno Documentation. *kyverno test* (CLI). https://kyverno.io/docs/kyverno-cli/reference/kyverno_test/

[33] Nirmata. *kyverno-notation-aws*. https://github.com/nirmata/kyverno-notation-aws

[34] Open Policy Agent. *Gatekeeper*. https://open-policy-agent.github.io/gatekeeper/website/docs/

[35] Ratify (CNCF). https://ratify.dev/

## GitHub

[36] GitHub Docs. *Configuring OpenID Connect in Amazon Web Services*. https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws

[37] GitHub Docs. *OpenID Connect reference* (các claim của token). https://docs.github.com/en/actions/reference/security/oidc

[38] GitHub Docs. *REST API endpoints for GitHub Actions OIDC* (tùy biến claim `sub`, `use_immutable_subject`). https://docs.github.com/en/rest/actions/oidc

[39] GitHub Docs. *Secure use reference* (ghim action theo commit SHA, quyền `GITHUB_TOKEN`). https://docs.github.com/en/actions/reference/security/secure-use

[40] GitHub Docs. *About protected branches*. https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches

## Công cụ và workload

[41] Aqua Security. *Trivy*. https://trivy.dev/

[42] Anchore. *Syft*. https://github.com/anchore/syft

[43] Gitleaks. https://github.com/gitleaks/gitleaks

[44] ORAS. *oras attach*. https://oras.land/docs/commands/oras_attach/

[45] S. Prodan. *podinfo*. https://github.com/stefanprodan/podinfo
