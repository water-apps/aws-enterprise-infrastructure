#!/bin/bash

# WaterApps Infrastructure Deployment Script
# Usage: ./deploy.sh [environment] [phase]
# Example: ./deploy.sh development all

set -e

ENVIRONMENT=${1:-development}
PHASE=${2:-all}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install Terraform 1.5+"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure'"
        exit 1
    fi
    
    log_info "Prerequisites check passed ✓"
}

deploy_module() {
    local module=$1
    log_info "Deploying $module module..."
    
    cd "$module"
    
    if [ ! -f "terraform.tfvars" ]; then
        log_warn "terraform.tfvars not found in $module"
        if [ -f "terraform.tfvars.example" ]; then
            log_warn "Please copy terraform.tfvars.example to terraform.tfvars and configure"
            exit 1
        fi
    fi
    
    terraform init -upgrade
    terraform plan -out=tfplan
    
    read -p "Apply this plan? (yes/no): " confirm
    if [ "$confirm" == "yes" ]; then
        terraform apply tfplan
        rm tfplan
        log_info "$module deployment completed ✓"
    else
        log_warn "Skipping $module deployment"
        rm tfplan
    fi
    
    cd ..
}

deploy_foundation() {
    log_info "=== Deploying 01-Foundation ==="
    deploy_module "01-foundation"
    
    # Save outputs
    cd 01-foundation
    terraform output > ../foundation-outputs.txt
    log_info "Foundation outputs saved to foundation-outputs.txt"
    cd ..
}

deploy_security() {
    log_info "=== Deploying 02-Security ==="
    
    # Check if foundation outputs exist
    if [ ! -f "foundation-outputs.txt" ]; then
        log_error "Foundation must be deployed first"
        exit 1
    fi
    
    deploy_module "02-security"
    
    # Retrieve and save CI/CD credentials
    cd 02-security
    CICD_SECRET_ARN=$(terraform output -raw cicd_credentials_secret_arn 2>/dev/null || echo "")
    if [ -n "$CICD_SECRET_ARN" ]; then
        log_info "CI/CD credentials stored in: $CICD_SECRET_ARN"
        log_info "Retrieve with: aws secretsmanager get-secret-value --secret-id $CICD_SECRET_ARN"
    fi
    cd ..
}

deploy_networking() {
    log_info "=== Deploying 03-Networking ==="
    deploy_module "03-networking"
}

deploy_database() {
    log_info "=== Deploying 04-Database ==="
    
    # Get database password from secrets manager
    cd 02-security
    DB_SECRET_ARN=$(terraform output -raw db_master_password_secret_arn)
    cd ..
    
    log_info "Retrieving database password from Secrets Manager..."
    DB_PASSWORD=$(aws secretsmanager get-secret-value \
        --secret-id "$DB_SECRET_ARN" \
        --query SecretString \
        --output text)
    
    # Update database terraform.tfvars with password if needed
    cd 04-database
    if ! grep -q "db_master_password" terraform.tfvars 2>/dev/null; then
        log_warn "Adding db_master_password to terraform.tfvars"
        echo "db_master_password = \"$DB_PASSWORD\"" >> terraform.tfvars
    fi
    cd ..
    
    deploy_module "04-database"
}

deploy_compute() {
    log_info "=== Deploying 05-Compute (ECS) ==="
    
    # Check if Docker image exists in ECR
    cd 05-compute
    if terraform state show aws_ecr_repository.backend &> /dev/null; then
        ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
        if [ -n "$ECR_URL" ]; then
            log_warn "Before deploying, ensure Docker image exists in ECR: $ECR_URL"
            log_warn "Build and push with: docker build -t $ECR_URL:latest . && docker push $ECR_URL:latest"
            read -p "Image pushed to ECR? (yes/no): " image_ready
            if [ "$image_ready" != "yes" ]; then
                log_error "Push Docker image to ECR first"
                cd ..
                exit 1
            fi
        fi
    fi
    cd ..
    
    deploy_module "05-compute"
    
    # Display ALB endpoint
    cd 05-compute
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        log_info "Application Load Balancer: http://$ALB_DNS"
        log_info "Test health endpoint: curl http://$ALB_DNS/health"
    fi
    cd ..
}

deploy_frontend() {
    log_info "=== Deploying 06-Frontend ==="
    deploy_module "06-frontend"
    
    # Display CloudFront URL
    cd 06-frontend
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    CF_URL=$(terraform output -raw cloudfront_domain_name 2>/dev/null || echo "")
    CF_DIST=$(terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
    
    if [ -n "$S3_BUCKET" ]; then
        log_info "S3 Bucket: $S3_BUCKET"
        log_info "Upload frontend: aws s3 sync ./build s3://$S3_BUCKET/"
    fi
    
    if [ -n "$CF_URL" ]; then
        log_info "CloudFront URL: https://$CF_URL"
    fi
    
    if [ -n "$CF_DIST" ]; then
        log_info "Invalidate cache: aws cloudfront create-invalidation --distribution-id $CF_DIST --paths '/*'"
    fi
    cd ..
}

deploy_monitoring() {
    log_info "=== Deploying 07-Monitoring ==="
    deploy_module "07-monitoring"
    
    log_warn "Check your email for SNS subscription confirmation"
    
    # Display dashboard link
    DASHBOARD_NAME="${ENVIRONMENT}-waterapps-dashboard"
    AWS_REGION=$(grep -oP 'aws_region\s*=\s*"\K[^"]+' 07-monitoring/terraform.tfvars 2>/dev/null || echo "ap-southeast-2")
    log_info "CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
}

deploy_all() {
    log_info "=== Starting Full Deployment for $ENVIRONMENT ==="
    
    deploy_foundation
    deploy_security
    deploy_networking
    deploy_database
    deploy_compute
    deploy_frontend
    deploy_monitoring
    
    log_info "=== Deployment Complete ==="
    log_info "Review outputs in each module directory"
}

destroy_environment() {
    log_warn "=== DESTROYING $ENVIRONMENT environment ==="
    log_warn "This will delete ALL resources. This action cannot be undone!"
    read -p "Type 'destroy $ENVIRONMENT' to confirm: " confirm
    
    if [ "$confirm" != "destroy $ENVIRONMENT" ]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    
    # Destroy in reverse order
    modules=(07-monitoring 06-frontend 05-compute 04-database 03-networking 02-security)
    
    for module in "${modules[@]}"; do
        if [ -d "$module" ]; then
            log_warn "Destroying $module..."
            cd "$module"
            terraform destroy -auto-approve || log_error "Failed to destroy $module (continuing...)"
            cd ..
        fi
    done
    
    log_warn "01-Foundation NOT destroyed (contains organization). Destroy manually if needed."
}

# Main execution
case $PHASE in
    foundation)
        check_prerequisites
        deploy_foundation
        ;;
    security)
        check_prerequisites
        deploy_security
        ;;
    networking)
        check_prerequisites
        deploy_networking
        ;;
    database)
        check_prerequisites
        deploy_database
        ;;
    compute)
        check_prerequisites
        deploy_compute
        ;;
    frontend)
        check_prerequisites
        deploy_frontend
        ;;
    monitoring)
        check_prerequisites
        deploy_monitoring
        ;;
    all)
        check_prerequisites
        deploy_all
        ;;
    destroy)
        destroy_environment
        ;;
    *)
        echo "Usage: $0 [environment] [phase]"
        echo "Phases: foundation, security, networking, database, compute, frontend, monitoring, all, destroy"
        exit 1
        ;;
esac

log_info "Done!"
