# Terraform Drift Governance Policy (Article)

## Why This Exists

Terraform drift happens when cloud resources are changed outside Terraform and state/config no longer reflect reality.  
This creates release risk, security gaps, and rollback failures.

This policy defines how WaterApps prevents, detects, and remediates drift across infrastructure repositories.

## Policy Objective

Keep production infrastructure **Terraform-authoritative** by enforcing:
- remote state + locking
- CI-only change path
- scheduled drift checks
- time-bound remediation

## The Control Model

### 1) Preventive controls

1. Infrastructure mutations must run through approved CI/CD roles (OIDC).
2. Remote state is mandatory (S3 backend + DynamoDB lock).
3. Local state files are prohibited in repositories.
4. Direct cloud-console/manual mutations are treated as policy exceptions or incidents.

### 2) Detective controls

1. Scheduled policy audit verifies drift-readiness:
- S3 backend declared in Terraform
- OIDC deploy role secret exists
- remote state bucket and lock table variables exist
- no local `.tfstate` files in repo
2. Scheduled drift run executes:
- `terraform plan -refresh-only -detailed-exitcode`

Interpretation:
- `0`: no drift
- `2`: drift detected (policy breach)
- `1`/other: workflow/runtime error (fix pipeline first)

### 3) Corrective controls

1. Drift detection creates a tracked incident/work item.
2. Production drift is treated as `P1` unless explicitly downgraded with justification.
3. Every drift fix includes:
- Terraform-based remediation commit
- root-cause analysis
- control improvement (permission, guardrail, or test)

## Implemented in This Repo

### Workflow

- `.github/workflows/terraform-drift-governance.yml`

This workflow performs drift-readiness governance checks on a weekly schedule and on manual dispatch.

### Policy Script

- `scripts/ci/check_drift_readiness.sh`

This script enforces:
- explicit `backend "s3"` declaration in each stage module
- required repo configuration for OIDC and remote state locking
- no checked-in Terraform state files

## Implemented in IAM Repo

Production drift detection is also implemented in:

- `waterapps-15-iam-access/.github/workflows/terraform-drift-daily.yml`

That workflow runs daily and performs `plan -refresh-only -detailed-exitcode` against remote state.

## Required Repository Configuration

For Terraform drift controls to function end-to-end:

- Secret: `AWS_OIDC_ROLE_ARN`
- Variable: `TF_STATE_BUCKET` (or repo-specific state bucket variable)
- Variable: `TF_LOCK_TABLE` (DynamoDB lock table)

For IAM repo drift workflow:

- Secret: `AWS_DEPLOY_ROLE_ARN`
- Variables: `IAM_ACCESS_TF_STATE_BUCKET`, `IAM_ACCESS_TF_STATE_KEY`, `IAM_ACCESS_TF_LOCK_TABLE`

## Operating Procedure

1. Review daily/weekly drift workflow results.
2. If drift is detected:
- open/confirm incident
- stop manual changes
- remediate via Terraform
3. Re-run drift check until it returns exit code `0`.
4. Record RCA and preventive action in backlog.

## KPI Set

- Drift-free days (per repo)
- Mean time to remediate drift
- Number of out-of-band mutations per month
- Number of repos with complete drift-readiness controls

## Backlog Priorities

- `P1`: Enable full remote backend + lock in every Terraform stage module
- `P1`: Enforce CI role-only mutating cloud permissions
- `P2`: Auto-create issues/incidents on detected drift
- `P2`: Add org-wide dashboard for drift status
- `P3`: Quarterly exception review and IAM hardening
- `P4`: Post-incident tabletop on drift scenarios
