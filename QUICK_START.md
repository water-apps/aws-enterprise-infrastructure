# WaterApps Infrastructure - Quick Start

Get your AWS infrastructure deployed in 30 minutes.

## Prerequisites (5 minutes)

### 1. Install Tools
```bash
# Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# AWS CLI
brew install awscli     # macOS
# or download from https://aws.amazon.com/cli/

# Verify installations
terraform --version  # Should be 1.5+
aws --version
```

### 2. Configure AWS CLI
```bash
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: ap-southeast-2
# - Default output format: json
```

### 3. Prepare Email Addresses
You need 3 unique email addresses for AWS accounts. Use Gmail's + trick:
- `yourname+waterapps-dev@gmail.com`
- `yourname+waterapps-prod@gmail.com`
- `yourname+waterapps-shared@gmail.com`

## Phase 1: Foundation (10 minutes)

```bash
cd foundation

# Create your configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your details
nano terraform.tfvars  # or use your favorite editor

# Deploy
terraform init
terraform plan
terraform apply

# Save important outputs
terraform output > ../foundation-outputs.txt
```

✅ **Checkpoint**: Check your email for AWS account activation links. Click all 3.

## Phase 2: Development Environment (15 minutes)

### Deploy Security Layer
```bash
cd ../security

cat > terraform.tfvars <<EOF
environment = "development"
EOF

terraform init
terraform apply

# Save CI/CD credentials ARN
terraform output cicd_credentials_secret_arn
```

### Deploy Network
```bash
cd ../networking

cat > terraform.tfvars <<EOF
environment = "development"
EOF

terraform init
terraform apply
```

### Deploy Database
```bash
cd ../database

# Get database password from Secrets Manager
DB_SECRET_ARN=$(cd ../security && terraform output -raw db_master_password_secret_arn)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $DB_SECRET_ARN --query SecretString --output text)

# Create config with all required variables
cat > terraform.tfvars <<EOF
environment = "development"
database_subnet_ids = $(cd ../networking && terraform output -json database_subnet_ids)
rds_security_group_id = "$(cd ../networking && terraform output -raw rds_security_group_id)"
kms_key_arn = "$(cd ../security && terraform output -raw kms_key_arn)"
db_master_password = "$DB_PASSWORD"
EOF

terraform init
terraform apply
```

Wait ~10 minutes for RDS to provision. ☕

### Build and Push Docker Image
```bash
cd ../compute

# Initialize to create ECR
terraform init
terraform apply -target=aws_ecr_repository.backend -auto-approve

# Get ECR URL
ECR_URL=$(terraform output -raw ecr_repository_url)

# Build sample app (or use your own)
cat > Dockerfile <<'DOCKERFILE'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
DOCKERFILE

# Build and push
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin $ECR_URL
docker build -t $ECR_URL:latest .
docker push $ECR_URL:latest
```

### Deploy ECS Service
```bash
# Still in compute/
# Create full configuration
cat > terraform.tfvars <<EOF
environment = "development"
vpc_id = "$(cd ../networking && terraform output -raw vpc_id)"
public_subnet_ids = $(cd ../networking && terraform output -json public_subnet_ids)
private_subnet_ids = $(cd ../networking && terraform output -json private_subnet_ids)
alb_security_group_id = "$(cd ../networking && terraform output -raw alb_security_group_id)"
ecs_security_group_id = "$(cd ../networking && terraform output -raw ecs_security_group_id)"
kms_key_arn = "$(cd ../security && terraform output -raw kms_key_arn)"
ecs_task_execution_role_arn = "$(cd ../security && terraform output -raw ecs_task_execution_role_arn)"
ecs_task_role_arn = "$(cd ../security && terraform output -raw ecs_task_role_arn)"
db_instance_address = "$(cd ../database && terraform output -raw db_instance_address)"
db_instance_port = $(cd ../database && terraform output -raw db_instance_port)
db_instance_name = "$(cd ../database && terraform output -raw db_instance_name)"
db_master_password_secret_arn = "$(cd ../security && terraform output -raw db_master_password_secret_arn)"
app_config_secret_arn = "$(cd ../security && terraform output -raw app_config_secret_arn)"
EOF

terraform apply

# Get your backend URL
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "🎉 Backend deployed at: http://$ALB_DNS"
```

### Deploy Frontend
```bash
cd ../frontend

cat > terraform.tfvars <<EOF
environment = "development"
kms_key_arn = "$(cd ../security && terraform output -raw kms_key_arn)"
EOF

terraform init
terraform apply

# Get URLs
S3_BUCKET=$(terraform output -raw s3_bucket_name)
CF_DOMAIN=$(terraform output -raw cloudfront_domain_name)

echo "📦 S3 Bucket: $S3_BUCKET"
echo "🌐 Frontend URL: https://$CF_DOMAIN"

# Upload your frontend
# aws s3 sync ./your-frontend-build/ s3://$S3_BUCKET/
```

### Deploy Monitoring
```bash
cd ../monitoring

cat > terraform.tfvars <<EOF
environment = "development"
kms_key_arn = "$(cd ../security && terraform output -raw kms_key_arn)"
alert_email = "your-email@gmail.com"
ecs_cluster_name = "$(cd ../compute && terraform output -raw ecs_cluster_name)"
ecs_service_name = "$(cd ../compute && terraform output -raw ecs_service_name)"
ecs_log_group_name = "$(cd ../compute && terraform output -raw log_group_name)"
alb_arn_suffix = "$(cd ../compute && terraform output -raw alb_arn | cut -d: -f6 | cut -d/ -f2-)"
target_group_arn_suffix = "app/development-waterapps-alb/target-group-id"
cloudfront_distribution_id = "$(cd ../frontend && terraform output -raw cloudfront_distribution_id)"
EOF

terraform init
terraform apply

# Check your email for SNS subscription confirmation
```

## ✅ You're Done!

Your infrastructure is deployed. Here's what you have:

### Access Your Applications
- **Backend API**: `http://$(cd compute && terraform output -raw alb_dns_name)`
- **Frontend**: `https://$(cd frontend && terraform output -raw cloudfront_domain_name)`
- **Dashboard**: [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/)

### Check Health
```bash
# Backend health check
curl http://$(cd compute && terraform output -raw alb_dns_name)/health

# View logs
aws logs tail /ecs/development-waterapps --follow

# Check costs
aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-01),End=$(date -d '+1 month' +%Y-%m-01) \
  --metric BLENDED_COST \
  --granularity MONTHLY
```

### Next Steps

1. **Set up CI/CD**
   - Copy `.github/workflows/deploy.yml` to your app repo
   - Add GitHub secrets for AWS credentials
   - Push to main → auto-deploy

2. **Configure Custom Domain** (Optional)
   - Register domain in Route 53
   - Create ACM certificate (in us-east-1 for CloudFront)
   - Update CloudFront with domain + certificate
   - Update ALB listener with certificate

3. **Upload Your Application**
   ```bash
   # Backend: Already running from ECR
   # Update: docker build + push, ECS auto-updates
   
   # Frontend: Upload to S3
   aws s3 sync ./build s3://$(cd frontend && terraform output -raw s3_bucket_name)/
   aws cloudfront create-invalidation \
     --distribution-id $(cd frontend && terraform output -raw cloudfront_distribution_id) \
     --paths "/*"
   ```

4. **Monitor Costs**
   ```bash
   # Check daily
   ./scripts/cost-check.sh  # If you create this script
   
   # Or manually
   aws ce get-cost-and-usage \
     --time-period Start=2025-02-01,End=2025-02-07 \
     --granularity DAILY \
     --metrics BlendedCost
   ```

## Automation Script (Alternative)

Instead of running commands manually, use the deployment script:

```bash
chmod +x deploy.sh
./deploy.sh development all
```

This will prompt you through each step and handle the variable passing automatically.

## Common Issues

### "Access Denied" errors
- Check your AWS credentials: `aws sts get-caller-identity`
- Ensure you have admin permissions
- Verify region is correct

### "Resource already exists"
- State file exists from previous run
- Either: `terraform import` the resource, or
- Delete the resource manually and retry

### ECS tasks not starting
- Check logs: `aws logs tail /ecs/development-waterapps --follow`
- Common causes:
  - Docker image not in ECR
  - Secrets Manager ARN incorrect
  - Security group blocking traffic

### High costs
- Check what's running: AWS Console → Cost Explorer
- Stop development environment when not in use:
  ```bash
  # Scale down to zero
  aws ecs update-service \
    --cluster development-waterapps-cluster \
    --service development-backend-service \
    --desired-count 0
  
  # Scale back up
  aws ecs update-service \
    --cluster development-waterapps-cluster \
    --service development-backend-service \
    --desired-count 1
  ```

## Destroy Everything (Be Careful!)

```bash
./deploy.sh development destroy
```

Or manually:
```bash
cd monitoring && terraform destroy -auto-approve
cd ../frontend && terraform destroy -auto-approve
cd ../compute && terraform destroy -auto-approve
cd ../database && terraform destroy -auto-approve
cd ../networking && terraform destroy -auto-approve
cd ../security && terraform destroy -auto-approve
# Don't destroy foundation unless removing entire organization
```

## Help

- Review `DEPLOYMENT_GUIDE.md` for detailed explanations
- Check `COST_OPTIMIZATION.md` for reducing expenses
- See `BACKEND_CONFIG.md` for state management setup

## VK's Pro Tips

Based on your RBA/banking experience:

1. **Start with dev** - Don't deploy production until you have revenue
2. **Monitor costs daily** - Set up alerts, check every morning
3. **Use Fargate Spot** - Already configured for dev (50% savings)
4. **Right-size immediately** - After 1 week, check actual usage and downsize if needed
5. **Automate everything** - Set up CI/CD from day 1, saves hours later

Your $300/month infrastructure budget should cover dev environment with room to spare. Focus on building product, not optimizing infrastructure (yet).

Good luck! 🚀
