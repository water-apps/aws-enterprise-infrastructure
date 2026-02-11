# Deployment Order - Execute in This Sequence

## Overview
The folders are numbered to show the exact order of execution. Each module depends on outputs from previous modules.

## Execution Order

### 1️⃣ `01-foundation/`
**Deploy First** - Creates AWS Organization structure
- Sets up development, production, and shared accounts
- Configures consolidated billing
- Enables CloudTrail across organization
- Applies Service Control Policies (SCPs)

**Time:** 15-20 minutes
**Dependencies:** None
**Output:** Account IDs for dev, prod, and shared accounts

---

### 2️⃣ `02-security/`
**Deploy Second** - Security foundations
- Creates KMS encryption keys
- Sets up Secrets Manager for passwords
- Creates IAM roles for ECS tasks
- Configures CI/CD user credentials

**Time:** 2-3 minutes
**Dependencies:** 01-foundation (runs in dev/prod account)
**Output:** KMS key ARN, Secret ARNs, IAM role ARNs

---

### 3️⃣ `03-networking/`
**Deploy Third** - Network infrastructure
- Creates VPC with public/private subnets
- Sets up NAT Gateway for internet access
- Configures security groups
- Creates VPC endpoints for cost optimization

**Time:** 5-10 minutes
**Dependencies:** 02-security (uses KMS for VPC flow logs)
**Output:** VPC ID, Subnet IDs, Security Group IDs

---

### 4️⃣ `04-database/`
**Deploy Fourth** - Database layer
- Provisions RDS PostgreSQL instance
- Configures automated backups
- Sets up CloudWatch alarms
- Applies encryption with KMS

**Time:** 10-15 minutes (RDS provisioning)
**Dependencies:** 02-security (KMS, Secrets), 03-networking (subnets, security groups)
**Output:** Database endpoint, port, connection details

---

### 5️⃣ `05-compute/`
**Deploy Fifth** - Application containers
- Creates ECR repository for Docker images
- Sets up ECS Fargate cluster
- Configures Application Load Balancer
- Enables auto-scaling

**Time:** 5-10 minutes
**Dependencies:** All previous modules
**Requirements:** Docker image must be pushed to ECR before deployment
**Output:** ALB DNS name, ECR repository URL

---

### 6️⃣ `06-frontend/`
**Deploy Sixth** - Static website hosting
- Creates S3 bucket for static files
- Sets up CloudFront CDN
- Configures SSL/TLS support
- Implements caching strategies

**Time:** 10-15 minutes (CloudFront distribution)
**Dependencies:** 02-security (KMS for S3 encryption)
**Output:** S3 bucket name, CloudFront URL

---

### 7️⃣ `07-monitoring/`
**Deploy Last** - Observability
- Creates CloudWatch dashboards
- Sets up alarms for all resources
- Configures SNS notifications
- Enables cost anomaly detection

**Time:** 3-5 minutes
**Dependencies:** All previous modules (monitors all resources)
**Output:** Dashboard URL, SNS topic ARN

---

## Quick Deployment Commands

```bash
# Option 1: Manual step-by-step
cd 01-foundation && terraform init && terraform apply
cd ../02-security && terraform init && terraform apply
cd ../03-networking && terraform init && terraform apply
cd ../04-database && terraform init && terraform apply
cd ../05-compute && terraform init && terraform apply
cd ../06-frontend && terraform init && terraform apply
cd ../07-monitoring && terraform init && terraform apply

# Option 2: Automated script
./deploy.sh development all
```

## Why This Order Matters

**Cannot skip modules:**
- 05-compute needs database endpoint from 04-database
- 04-database needs subnets from 03-networking
- 03-networking needs KMS keys from 02-security
- Everything needs the foundation accounts from 01-foundation

**Can deploy in parallel (advanced):**
- After 03-networking completes:
  - 04-database and 06-frontend can run simultaneously
  - But both must finish before 05-compute

## Special Notes

### Before 05-compute
You MUST push a Docker image to ECR:
```bash
cd 05-compute
terraform apply -target=aws_ecr_repository.backend  # Create ECR first
ECR_URL=$(terraform output -raw ecr_repository_url)
docker build -t $ECR_URL:latest .
docker push $ECR_URL:latest
terraform apply  # Deploy rest of compute
```

### After 07-monitoring
Check your email to confirm SNS subscription for alerts.

## Teardown Order (Reverse)

```bash
cd 07-monitoring && terraform destroy
cd ../06-frontend && terraform destroy
cd ../05-compute && terraform destroy
cd ../04-database && terraform destroy
cd ../03-networking && terraform destroy
cd ../02-security && terraform destroy
# Note: 01-foundation is typically NOT destroyed (contains organization)
```

## Total Deployment Time

- **Active work:** 1-2 hours (mostly configuration and waiting)
- **Wait time:** 20-30 minutes (RDS, CloudFront provisioning)
- **First-time setup:** Plan for half a day including learning
- **Subsequent deploys:** 1 hour (when you know what you're doing)

## Verification After Each Step

```bash
# After each module
terraform output  # Check what was created
aws sts get-caller-identity  # Verify you're in correct account
terraform state list  # See all resources created
```

## Getting Help

If deployment fails at any step:
1. Read the error message carefully
2. Check the relevant guide:
   - Quick start issues → `QUICK_START.md`
   - Detailed troubleshooting → `DEPLOYMENT_GUIDE.md`
3. Verify prerequisites are met
4. Check AWS Console to see what exists
5. Use `terraform plan` to see what would change

---

**Remember:** Each numbered folder MUST be deployed in order. Don't skip ahead!
