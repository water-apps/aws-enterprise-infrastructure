#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

violations=0

log_info() {
  printf '[drift-policy] %s\n' "$*"
}

log_violation() {
  printf '[drift-policy][VIOLATION] %s\n' "$*" >&2
  violations=$((violations + 1))
}

check_stage_backend() {
  local stage="$1"
  if ! rg -q 'backend[[:space:]]+"s3"' "${stage}"/*.tf; then
    log_violation "${stage} has no explicit S3 backend block. Drift detection requires remote state."
  fi
}

log_info "Checking Terraform drift-readiness controls"

for stage in $(find . -maxdepth 1 -mindepth 1 -type d -name '[0-9][0-9]-*' | sort); do
  stage="${stage#./}"
  check_stage_backend "${stage}"
done

if [[ -n "${AWS_OIDC_ROLE_ARN:-}" ]]; then
  log_info "AWS_OIDC_ROLE_ARN is configured"
else
  log_violation "Missing secret AWS_OIDC_ROLE_ARN (required for CI OIDC auth)."
fi

if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
  log_info "TF_STATE_BUCKET is configured"
else
  log_violation "Missing repo variable TF_STATE_BUCKET (required for remote state)."
fi

if [[ -n "${TF_LOCK_TABLE:-}" ]]; then
  log_info "TF_LOCK_TABLE is configured"
else
  log_violation "Missing repo variable TF_LOCK_TABLE (required for state locking)."
fi

if find . -type f \( -name '*.tfstate' -o -name '*.tfstate.backup' \) \
  -not -path './.terraform/*' \
  -not -path './*/.terraform/*' \
  | grep -q .; then
  log_violation "Terraform state file(s) detected in repository path; state must remain remote-only."
fi

if [[ "${violations}" -gt 0 ]]; then
  log_violation "Total policy violations: ${violations}"
  exit 1
fi

log_info "All drift-readiness controls passed."
