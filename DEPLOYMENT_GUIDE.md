# WaterApps Terraform Deployment Guide

## Complete Step-by-Step Deployment

This guide walks you through deploying the entire WaterApps infrastructure from scratch.

## Prerequisites Checklist

- [ ] AWS CLI installed and configured
- [ ] Terraform 1.5+ installed
- [ ] Root AWS account access (for Organization setup)
- [ ] Three unique email addresses for AWS accounts
- [ ] Domain name registered (optional for initial MVP)

## Phase 1: Foundation Setup (Day 1)

### Step 1.1: Prepare Configuration

```bash
cd foundation
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your details:
```hcl
dev_account_email    = "your-email+dev@gmail.com"
prod_account_email   = "your-email+prod@gmail.com"
shared_account_email = "your-email+shared@gmail.com"
budget_alert_email   = "your-email@gmail.com"
monthly_budget_limit = "300"
```

### Step 1.2: Initialize and Deploy Foundation

```bash
terraform init
terraform plan
terraform apply
```

**Expected Outcome:**
- AWS Organization created
- 3 accounts provisioned (Dev, Prod, Shared)
- CloudTrail enabled
- Budget alerts configured
- SCPs applied

**Time to Complete:** 15-20 minutes

### Step 1.3: Accept Account Invitations

Check your email for AWS account activation emails. Click the links to activate each account.

### Step 1.4: Save Outputs

```bash
terraform output > ../foundation-outputs.txt
```

You'll need these account IDs for subsequent steps.

## Phase 2: Development Environment Setup (Day 1-2)

### Step 2.1: Configure AWS CLI for Dev Account

```bash
# Assume role in development account
aws sts assume-role \
  --role-arn "arn:aws:iam::DEV_ACCOUNT_ID:role/OrganizationAccountAccessRole" \
  --role-session-name terraform-deployment

# Configure credentials (use output from above command)
export AWS_ACCESS_KEY_ID=xxx
export AWS_SECRET_ACCESS_KEY=xxx
export AWS_SESSION_TOKEN=xxx
```

### Step 2.2: Deploy Security Infrastructure

```bash
cd ../security
terraform init

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
environment = "development"
aws_region  = "ap-southeast-2"
EOF

terraform plan
terraform apply
```

**Expected Outcome:**
- KMS keys created
- Secrets Manager configured
- IAM roles for ECS created
- CI/CD user provisioned

**Save the CI/CD credentials:**
```bash
terraform output cicd_credentials_secret_arn
# Note this ARN - you'll need it for GitHub Actions
```

### Step 2.3: Deploy Networking

```bash
cd ../networking
terraform init

cat > terraform.tfvars <<EOF
environment = "development"
vpc_cidr    = "10.0.0.0/16"
EOF

terraform plan
terraform apply
```

**Expected Outcome:**
- VPC with public/private subnets
- NAT Gateway (single for cost optimization)
- Security groups configured
- VPC endpoints for S3 and ECR

### Step 2.4: Retrieve Database Password from Secrets Manager

```bash
cd ../database

# Get the database password ARN from security module
DB_SECRET_ARN=$(cd ../security && terraform output -raw db_master_password_secret_arn)

# Retrieve the password
DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $DB_SECRET_ARN \
  --query SecretString \
  --output text)
```

### Step 2.5: Deploy Database

```bash
# Get required values from previous modules
VPC_ID=$(cd ../networking && terraform output -raw vpc_id)
DB_SUBNET_IDS=$(cd ../networking && terraform output -json database_subnet_ids)
RDS_SG_ID=$(cd ../networking && terraform output -raw rds_security_group_id)
KMS_KEY_ARN=$(cd ../security && terraform output -raw kms_key_arn)

cat > terraform.tfvars <<EOF
environment          = "development"
database_subnet_ids  = $DB_SUBNET_IDS
rds_security_group_id = "$RDS_SG_ID"
kms_key_arn         = "$KMS_KEY_ARN"
db_master_password  = "$DB_PASSWORD"
db_instance_class   = "db.t4g.micro"
EOF

terraform init
terraform plan
terraform apply
```

**Expected Outcome:**
- PostgreSQL RDS instance (single-AZ for dev)
- Automated backups configured
- CloudWatch alarms set

**Time to Complete:** 10-15 minutes (RDS provisioning)

### Step 2.6: Build and Push Docker Image

Before deploying ECS, you need a Docker image. Here's a sample Node.js backend:

```bash
# In your application repository
cat > Dockerfile <<EOF
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
EOF

# Build and push
cd ../compute
ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")

if [ -z "$ECR_URL" ]; then
  # Deploy compute first to create ECR
  terraform init
  terraform apply -target=aws_ecr_repository.backend
  ECR_URL=$(terraform output -raw ecr_repository_url)
fi

# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and push
docker build -t $ECR_URL:latest .
docker push $ECR_URL:latest
```

### Step 2.7: Deploy Compute (ECS)

```bash
cd ../compute

# Gather required variables
VPC_ID=$(cd ../networking && terraform output -raw vpc_id)
PUBLIC_SUBNETS=$(cd ../networking && terraform output -json public_subnet_ids)
PRIVATE_SUBNETS=$(cd ../networking && terraform output -json private_subnet_ids)
ALB_SG=$(cd ../networking && terraform output -raw alb_security_group_id)
ECS_SG=$(cd ../networking && terraform output -raw ecs_security_group_id)
KMS_KEY=$(cd ../security && terraform output -raw kms_key_arn)
EXEC_ROLE=$(cd ../security && terraform output -raw ecs_task_execution_role_arn)
TASK_ROLE=$(cd ../security && terraform output -raw ecs_task_role_arn)
DB_ADDR=$(cd ../database && terraform output -raw db_instance_address)
DB_PORT=$(cd ../database && terraform output -raw db_instance_port)
DB_NAME=$(cd ../database && terraform output -raw db_instance_name)
DB_SECRET=$(cd ../security && terraform output -raw db_master_password_secret_arn)
APP_SECRET=$(cd ../security && terraform output -raw app_config_secret_arn)

cat > terraform.tfvars <<EOF
environment                   = "development"
vpc_id                        = "$VPC_ID"
public_subnet_ids             = $PUBLIC_SUBNETS
private_subnet_ids            = $PRIVATE_SUBNETS
alb_security_group_id         = "$ALB_SG"
ecs_security_group_id         = "$ECS_SG"
kms_key_arn                   = "$KMS_KEY"
ecs_task_execution_role_arn   = "$EXEC_ROLE"
ecs_task_role_arn             = "$TASK_ROLE"
db_instance_address           = "$DB_ADDR"
db_instance_port              = $DB_PORT
db_instance_name              = "$DB_NAME"
db_master_password_secret_arn = "$DB_SECRET"
app_config_secret_arn         = "$APP_SECRET"
desired_count                 = 1
task_cpu                      = "256"
task_memory                   = "512"
EOF

terraform init
terraform plan
terraform apply
```

**Expected Outcome:**
- ECS Fargate cluster
- Application Load Balancer
- ECS service running
- Auto-scaling configured

**Access your backend:**
```bash
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Backend URL: http://$ALB_DNS"
curl http://$ALB_DNS/health
```

### Step 2.8: Deploy Frontend

```bash
cd ../frontend

KMS_KEY=$(cd ../security && terraform output -raw kms_key_arn)

cat > terraform.tfvars <<EOF
environment = "development"
kms_key_arn = "$KMS_KEY"
EOF

terraform init
terraform plan
terraform apply
```

**Expected Outcome:**
- S3 bucket for static files
- CloudFront distribution
- OAC configured

**Upload your frontend:**
```bash
S3_BUCKET=$(terraform output -raw s3_bucket_name)
CF_DIST=$(terraform output -raw cloudfront_distribution_id)

# Build your frontend (example with React)
cd /path/to/your/frontend
npm run build

# Upload to S3
aws s3 sync build/ s3://$S3_BUCKET/ --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $CF_DIST \
  --paths "/*"

# Get your URL
cd -
CF_URL=$(terraform output -raw cloudfront_domain_name)
echo "Frontend URL: https://$CF_URL"
```

### Step 2.9: Deploy Monitoring

```bash
cd ../monitoring

# Gather required variables
KMS_KEY=$(cd ../security && terraform output -raw kms_key_arn)
ECS_CLUSTER=$(cd ../compute && terraform output -raw ecs_cluster_name)
ECS_SERVICE=$(cd ../compute && terraform output -raw ecs_service_name)
LOG_GROUP=$(cd ../compute && terraform output -raw log_group_name)
ALB_ARN=$(cd ../compute && terraform output -raw alb_arn)
CF_DIST=$(cd ../frontend && terraform output -raw cloudfront_distribution_id)

# Extract ARN suffixes for CloudWatch
ALB_SUFFIX=$(echo $ALB_ARN | cut -d: -f6 | cut -d/ -f2-)

cat > terraform.tfvars <<EOF
environment              = "development"
kms_key_arn              = "$KMS_KEY"
alert_email              = "your-email@gmail.com"
ecs_cluster_name         = "$ECS_CLUSTER"
ecs_service_name         = "$ECS_SERVICE"
ecs_log_group_name       = "$LOG_GROUP"
alb_arn_suffix           = "$ALB_SUFFIX"
target_group_arn_suffix  = "REPLACE_WITH_TG_SUFFIX"
cloudfront_distribution_id = "$CF_DIST"
EOF

terraform init
terraform plan
terraform apply
```

**Check your email** for SNS subscription confirmation.

**View Dashboard:**
- Go to AWS Console → CloudWatch → Dashboards
- Open "development-waterapps-dashboard"

## Phase 3: Production Environment (Week 2-3)

Repeat Phase 2 steps but with these differences:

### Production-Specific Settings

```hcl
# networking/terraform.tfvars
environment = "production"
vpc_cidr    = "10.1.0.0/16"  # Different CIDR from dev

# database/terraform.tfvars
db_instance_class = "db.t4g.small"  # Upgrade from micro
# RDS will be Multi-AZ automatically

# compute/terraform.tfvars
desired_count = 2  # At least 2 tasks for HA
task_cpu     = "512"
task_memory  = "1024"
```

### Production Checklist

- [ ] Use multi-AZ RDS
- [ ] Enable enhanced monitoring
- [ ] Configure custom domain with ACM certificate
- [ ] Set up proper CI/CD pipeline
- [ ] Enable deletion protection on critical resources
- [ ] Review and tighten security group rules
- [ ] Configure WAF (optional)
- [ ] Set up proper backup strategies

## Phase 4: CI/CD Integration

### GitHub Actions Setup

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-southeast-2
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build, tag, and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: development-waterapps-backend
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG \
                     $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
      
      - name: Update ECS service
        run: |
          aws ecs update-service \
            --cluster development-waterapps-cluster \
            --service development-backend-service \
            --force-new-deployment
```

Add secrets to GitHub:
- Go to repo → Settings → Secrets
- Add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from security module output

## Cost Optimization Tips

### Development Environment
- Use Fargate Spot (already configured)
- Single NAT Gateway (already configured)
- db.t4g.micro RDS instance
- Minimal log retention (7 days)
- No read replicas
- **Estimated Cost:** $150-200/month

### Production Environment  
- Standard Fargate for reliability
- Multi-AZ everything
- Regular instance types
- 30-day log retention
- Read replicas when needed
- **Estimated Cost:** $300-500/month

## Monitoring and Maintenance

### Daily Checks
```bash
# Check ECS service health
aws ecs describe-services \
  --cluster development-waterapps-cluster \
  --services development-backend-service

# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier development-waterapps-db

# Check costs
aws ce get-cost-and-usage \
  --time-period Start=2025-02-01,End=2025-02-07 \
  --granularity DAILY \
  --metrics BlendedCost
```

### Weekly Reviews
- Review CloudWatch dashboard
- Check CloudTrail for suspicious activity
- Review cost allocation reports
- Update security patches

## Troubleshooting

### ECS Task Won't Start
```bash
# Check task logs
aws logs tail /ecs/development-waterapps --follow

# Describe failed tasks
aws ecs list-tasks --cluster development-waterapps-cluster --desired-status STOPPED
aws ecs describe-tasks --cluster development-waterapps-cluster --tasks TASK_ARN
```

### Database Connection Issues
```bash
# Test from ECS task
aws ecs execute-command \
  --cluster development-waterapps-cluster \
  --task TASK_ID \
  --container backend \
  --interactive \
  --command "/bin/sh"

# Inside container:
nc -zv DB_HOST 5432
```

### High Costs
```bash
# Identify top spending services
aws ce get-cost-and-usage \
  --time-period Start=2025-02-01,End=2025-02-07 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Next Steps

1. **Custom Domain:** Register domain, create ACM certificate, update CloudFront
2. **CI/CD:** Set up automated testing and deployment
3. **Monitoring:** Configure PagerDuty/Opsgenie for on-call
4. **Backups:** Test RDS restore procedures
5. **Security:** Run AWS Security Hub scans
6. **Documentation:** Document runbooks for common issues

## Support

For issues specific to your deployment, check:
- CloudWatch Logs: `/ecs/development-waterapps`
- CloudWatch Dashboard: `development-waterapps-dashboard`
- SNS Alerts: Check email for notifications
