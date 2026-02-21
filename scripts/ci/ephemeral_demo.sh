#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_NAME="${ENV_NAME:-development}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
DRY_RUN="${DRY_RUN:-false}"

log() {
  printf '[ephemeral-demo] %s\n' "$*"
}

die() {
  printf '[ephemeral-demo] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmds() {
  command -v terraform >/dev/null 2>&1 || die "terraform not installed"
  command -v aws >/dev/null 2>&1 || die "aws CLI not installed"
  command -v jq >/dev/null 2>&1 || die "jq not installed"
}

run_tf() {
  local dir="$1"
  shift
  (cd "${ROOT_DIR}/${dir}" && terraform "$@")
}

tf_out_raw() {
  local dir="$1"
  local key="$2"
  (cd "${ROOT_DIR}/${dir}" && terraform output -raw "${key}")
}

tf_out_json() {
  local dir="$1"
  local key="$2"
  (cd "${ROOT_DIR}/${dir}" && terraform output -json "${key}")
}

write_file() {
  local path="$1"
  shift
  cat > "${path}" <<EOF
$*
EOF
}

init_module() {
  local dir="$1"
  log "terraform init ${dir}"
  run_tf "${dir}" init -input=false
}

apply_module() {
  local dir="$1"
  log "terraform apply ${dir}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    run_tf "${dir}" plan -input=false
  else
    run_tf "${dir}" apply -auto-approve -input=false
  fi
}

destroy_module() {
  local dir="$1"
  log "terraform destroy ${dir}"
  if [[ ! -f "${ROOT_DIR}/${dir}/terraform.tfvars" ]]; then
    log "skip ${dir} (no generated tfvars)"
    return 0
  fi
  set +e
  run_tf "${dir}" destroy -auto-approve -input=false
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    log "destroy failed for ${dir} (continuing)"
    return $rc
  fi
}

generate_02_security_tfvars() {
  write_file "${ROOT_DIR}/02-security/terraform.tfvars" \
"environment = \"${ENV_NAME}\"
aws_region  = \"${AWS_REGION}\""
}

generate_03_networking_tfvars() {
  write_file "${ROOT_DIR}/03-networking/terraform.tfvars" \
"environment = \"${ENV_NAME}\"
aws_region  = \"${AWS_REGION}\""
}

generate_04_database_tfvars() {
  local db_password
  local db_secret_arn
  db_secret_arn="$(tf_out_raw 02-security db_master_password_secret_arn)"
  db_password="$(aws secretsmanager get-secret-value \
    --secret-id "${db_secret_arn}" \
    --query SecretString \
    --output text)"

  cat > "${ROOT_DIR}/04-database/terraform.tfvars" <<EOF
environment = "${ENV_NAME}"
aws_region = "${AWS_REGION}"
database_subnet_ids = $(tf_out_json 03-networking database_subnet_ids)
rds_security_group_id = "$(tf_out_raw 03-networking rds_security_group_id)"
kms_key_arn = "$(tf_out_raw 02-security kms_key_arn)"
db_master_password = "${db_password}"
EOF
}

generate_05_compute_tfvars() {
  cat > "${ROOT_DIR}/05-compute/terraform.tfvars" <<EOF
environment = "${ENV_NAME}"
aws_region = "${AWS_REGION}"
vpc_id = "$(tf_out_raw 03-networking vpc_id)"
public_subnet_ids = $(tf_out_json 03-networking public_subnet_ids)
private_subnet_ids = $(tf_out_json 03-networking private_subnet_ids)
alb_security_group_id = "$(tf_out_raw 03-networking alb_security_group_id)"
ecs_security_group_id = "$(tf_out_raw 03-networking ecs_security_group_id)"
kms_key_arn = "$(tf_out_raw 02-security kms_key_arn)"
ecs_task_execution_role_arn = "$(tf_out_raw 02-security ecs_task_execution_role_arn)"
ecs_task_role_arn = "$(tf_out_raw 02-security ecs_task_role_arn)"
db_instance_address = "$(tf_out_raw 04-database db_instance_address)"
db_instance_port = $(tf_out_raw 04-database db_instance_port)
db_instance_name = "$(tf_out_raw 04-database db_instance_name)"
db_master_password_secret_arn = "$(tf_out_raw 02-security db_master_password_secret_arn)"
app_config_secret_arn = "$(tf_out_raw 02-security app_config_secret_arn)"
desired_count = 0
min_capacity = 0
max_capacity = 1
EOF
}

generate_06_frontend_tfvars() {
  cat > "${ROOT_DIR}/06-frontend/terraform.tfvars" <<EOF
environment = "${ENV_NAME}"
aws_region = "${AWS_REGION}"
kms_key_arn = "$(tf_out_raw 02-security kms_key_arn)"
EOF
}

generate_07_monitoring_tfvars() {
  [[ -n "${ALERT_EMAIL}" ]] || die "ALERT_EMAIL is required for 07-monitoring"

  cat > "${ROOT_DIR}/07-monitoring/terraform.tfvars" <<EOF
environment = "${ENV_NAME}"
aws_region = "${AWS_REGION}"
kms_key_arn = "$(tf_out_raw 02-security kms_key_arn)"
alert_email = "${ALERT_EMAIL}"
alb_arn_suffix = "$(tf_out_raw 05-compute alb_arn_suffix)"
target_group_arn_suffix = "$(tf_out_raw 05-compute target_group_arn_suffix)"
ecs_cluster_name = "$(tf_out_raw 05-compute ecs_cluster_name)"
ecs_service_name = "$(tf_out_raw 05-compute ecs_service_name)"
ecs_log_group_name = "$(tf_out_raw 05-compute log_group_name)"
cloudfront_distribution_id = "$(tf_out_raw 06-frontend cloudfront_distribution_id)"
EOF
}

preflight() {
  require_cmds
  aws sts get-caller-identity >/dev/null
  log "Using AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
}

up() {
  preflight
  log "Skipping 01-foundation intentionally (Organizations/account creation is high-cost and not suitable for ephemeral CI)"

  generate_02_security_tfvars
  generate_03_networking_tfvars

  init_module 02-security
  apply_module 02-security

  init_module 03-networking
  apply_module 03-networking

  generate_04_database_tfvars
  init_module 04-database
  apply_module 04-database

  generate_05_compute_tfvars
  init_module 05-compute
  apply_module 05-compute

  generate_06_frontend_tfvars
  init_module 06-frontend
  apply_module 06-frontend

  generate_07_monitoring_tfvars
  init_module 07-monitoring
  apply_module 07-monitoring

  log "Ephemeral stack apply completed"
}

smoke() {
  preflight
  log "Smoke checks: terraform outputs and AWS resource lookups"

  local vpc_id ecs_cluster ecs_service db_id cf_id alb_dns dashboard
  vpc_id="$(tf_out_raw 03-networking vpc_id)"
  ecs_cluster="$(tf_out_raw 05-compute ecs_cluster_name)"
  ecs_service="$(tf_out_raw 05-compute ecs_service_name)"
  db_id="$(tf_out_raw 04-database db_instance_id)"
  cf_id="$(tf_out_raw 06-frontend cloudfront_distribution_id)"
  alb_dns="$(tf_out_raw 05-compute alb_dns_name)"
  dashboard="$(tf_out_raw 07-monitoring dashboard_name)"

  aws ec2 describe-vpcs --vpc-ids "${vpc_id}" >/dev/null
  aws ecs describe-clusters --clusters "${ecs_cluster}" >/dev/null
  aws ecs describe-services --cluster "${ecs_cluster}" --services "${ecs_service}" >/dev/null
  aws rds describe-db-instances --db-instance-identifier "${db_id}" >/dev/null
  aws cloudfront get-distribution --id "${cf_id}" >/dev/null
  aws cloudwatch get-dashboard --dashboard-name "${dashboard}" >/dev/null

  {
    echo "## Ephemeral Demo Smoke Test"
    echo "- Environment: \`${ENV_NAME}\`"
    echo "- Region: \`${AWS_REGION}\`"
    echo "- VPC: \`${vpc_id}\`"
    echo "- ECS: \`${ecs_cluster}/${ecs_service}\`"
    echo "- RDS: \`${db_id}\`"
    echo "- CloudFront: \`${cf_id}\`"
    echo "- ALB DNS: \`${alb_dns}\`"
    echo "- Dashboard: \`${dashboard}\`"
    echo "- Note: ECS desired count is set to \`0\` in CI to minimize cost."
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true

  log "Smoke checks passed"
}

destroy() {
  preflight
  local rc=0

  destroy_module 07-monitoring || rc=1
  destroy_module 06-frontend || rc=1
  destroy_module 05-compute || rc=1
  destroy_module 04-database || rc=1
  destroy_module 03-networking || rc=1
  destroy_module 02-security || rc=1

  rm -f \
    "${ROOT_DIR}/02-security/terraform.tfvars" \
    "${ROOT_DIR}/03-networking/terraform.tfvars" \
    "${ROOT_DIR}/04-database/terraform.tfvars" \
    "${ROOT_DIR}/05-compute/terraform.tfvars" \
    "${ROOT_DIR}/06-frontend/terraform.tfvars" \
    "${ROOT_DIR}/07-monitoring/terraform.tfvars"

  if [[ $rc -ne 0 ]]; then
    die "One or more destroy steps failed"
  fi
  log "Ephemeral stack destroy completed"
}

case "${1:-}" in
  up|smoke|destroy)
    "$1"
    ;;
  *)
    cat <<USAGE
Usage: $(basename "$0") <up|smoke|destroy>

Environment variables:
  ENV_NAME      Terraform environment value (default: development)
  AWS_REGION    AWS region (default: ap-southeast-2)
  ALERT_EMAIL   Required for up (07-monitoring SNS subscription)
  DRY_RUN       If true, use plan instead of apply in up
USAGE
    exit 2
    ;;
esac
