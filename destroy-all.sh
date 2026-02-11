#!/bin/bash

# WaterApps Infrastructure Destroy Script
# Safely destroys all infrastructure in reverse order
# Usage: ./destroy-all.sh [options]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default options
KEEP_SNAPSHOTS=true
KEEP_FOUNDATION=true
FORCE=false
ENVIRONMENT=${1:-development}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-snapshots)
            KEEP_SNAPSHOTS=false
            shift
            ;;
        --destroy-foundation)
            KEEP_FOUNDATION=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-snapshots         Delete RDS without final snapshot (DANGEROUS!)"
            echo "  --destroy-foundation   Also destroy AWS Organization (NOT RECOMMENDED)"
            echo "  --force               Skip all confirmations (VERY DANGEROUS!)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Safe destroy, keep snapshots and foundation"
            echo "  $0 --no-snapshots     # Faster destroy, no RDS snapshots"
            echo "  $0 --force            # Automated destroy for CI/CD"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm_destruction() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    log_warn "════════════════════════════════════════════════════════════════"
    log_warn "  ⚠️  DESTRUCTIVE OPERATION - READ CAREFULLY  ⚠️"
    log_warn "════════════════════════════════════════════════════════════════"
    echo ""
    log_warn "This will DESTROY all WaterApps infrastructure:"
    echo "  - ECS tasks and containers"
    echo "  - Application Load Balancer"
    echo "  - RDS database (${KEEP_SNAPSHOTS} snapshot retention)"
    echo "  - S3 buckets and CloudFront"
    echo "  - VPC and networking"
    echo "  - Security keys and secrets"
    if [ "$KEEP_FOUNDATION" = false ]; then
        log_error "  - AWS ORGANIZATION (all accounts!)"
    fi
    echo ""
    log_warn "After destruction:"
    echo "  ✅ AWS costs will drop to ~\$0/month"
    echo "  ✅ Infrastructure can be redeployed from Terraform code"
    if [ "$KEEP_SNAPSHOTS" = true ]; then
        echo "  ✅ Database snapshots will be retained (~\$2/month)"
    else
        log_error "  ❌ Database will be PERMANENTLY DELETED (cannot recover!)"
    fi
    echo ""
    
    read -p "Type 'DESTROY $ENVIRONMENT' to confirm: " confirmation
    
    if [ "$confirmation" != "DESTROY $ENVIRONMENT" ]; then
        log_info "Destruction cancelled. Infrastructure unchanged."
        exit 0
    fi
}

destroy_module() {
    local module=$1
    local module_name=$2
    
    if [ ! -d "$module" ]; then
        log_warn "$module_name not found, skipping..."
        return 0
    fi
    
    log_info "Destroying $module_name..."
    cd "$module"
    
    if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
        log_warn "No state file found in $module_name, skipping..."
        cd ..
        return 0
    fi
    
    terraform destroy -auto-approve || {
        log_error "Failed to destroy $module_name"
        log_warn "Continuing with remaining modules..."
    }
    
    cd ..
    log_info "$module_name destroyed ✓"
}

check_aws_credentials() {
    log_info "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_error "Run: aws configure"
        exit 1
    fi
    log_info "AWS credentials verified ✓"
}

estimate_final_costs() {
    log_info ""
    log_info "════════════════════════════════════════════════════════════════"
    log_info "  Cost Estimate After Destruction"
    log_info "════════════════════════════════════════════════════════════════"
    
    if [ "$KEEP_SNAPSHOTS" = true ]; then
        echo "  RDS Snapshots: ~\$2/month (20GB @ \$0.095/GB)"
    else
        echo "  RDS Snapshots: \$0/month (none kept)"
    fi
    
    echo "  KMS Keys: ~\$1/month (deletion waiting period)"
    echo "  S3 Storage: <\$0.50/month (minimal logs)"
    
    if [ "$KEEP_FOUNDATION" = true ]; then
        echo "  AWS Organization: \$0/month (free)"
        echo ""
        echo "  TOTAL: ~\$1-3/month"
    else
        echo "  AWS Organization: \$0/month (destroyed)"
        echo ""
        echo "  TOTAL: ~\$0.50-2/month"
    fi
    
    log_info "════════════════════════════════════════════════════════════════"
}

cleanup_orphaned_resources() {
    log_info ""
    log_info "Checking for orphaned resources..."
    
    # Check ECS tasks
    local ecs_clusters=$(aws ecs list-clusters --query 'clusterArns' --output text 2>/dev/null || echo "")
    if [ -n "$ecs_clusters" ]; then
        log_warn "Found ECS clusters still running. They should have been deleted."
    fi
    
    # Check NAT Gateways
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --filter "Name=state,Values=available" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text 2>/dev/null || echo "")
    if [ -n "$nat_gateways" ]; then
        log_warn "NAT Gateways still exist: $nat_gateways"
        log_warn "These cost ~\$35/month. Delete manually if needed."
    fi
    
    # Check RDS instances
    local rds_instances=$(aws rds describe-db-instances \
        --query 'DBInstances[*].DBInstanceIdentifier' \
        --output text 2>/dev/null || echo "")
    if [ -n "$rds_instances" ]; then
        log_warn "RDS instances still exist: $rds_instances"
        log_warn "These cost \$15-90/month. Delete manually if needed."
    fi
    
    # Check Load Balancers
    local albs=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[*].LoadBalancerName' \
        --output text 2>/dev/null || echo "")
    if [ -n "$albs" ]; then
        log_warn "Load Balancers still exist: $albs"
        log_warn "These cost ~\$18/month. Delete manually if needed."
    fi
    
    log_info "Orphaned resource check complete"
}

show_next_steps() {
    log_info ""
    log_info "════════════════════════════════════════════════════════════════"
    log_info "  Destruction Complete!"
    log_info "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Verify costs in 24 hours:"
    echo "   aws ce get-cost-and-usage \\"
    echo "     --time-period Start=\$(date +%Y-%m-%d),End=\$(date -d '+1 day' +%Y-%m-%d) \\"
    echo "     --granularity DAILY --metrics BlendedCost"
    echo ""
    echo "2. Check for orphaned resources:"
    echo "   - AWS Console → Cost Explorer → Daily costs"
    echo "   - Look for unexpected charges"
    echo ""
    echo "3. Delete snapshots if not needed (saves ~\$2/month):"
    echo "   aws rds describe-db-snapshots --query 'DBSnapshots[*].DBSnapshotIdentifier'"
    echo "   aws rds delete-db-snapshot --db-snapshot-identifier SNAPSHOT_ID"
    echo ""
    echo "4. To redeploy infrastructure:"
    echo "   ./deploy.sh $ENVIRONMENT all"
    echo ""
    
    if [ "$KEEP_FOUNDATION" = true ]; then
        log_info "Foundation (AWS Organization) preserved for quick redeployment"
    fi
    
    log_info "════════════════════════════════════════════════════════════════"
}

# Main execution
main() {
    log_info "WaterApps Infrastructure Destruction"
    log_info "Environment: $ENVIRONMENT"
    
    check_aws_credentials
    confirm_destruction
    estimate_final_costs
    
    echo ""
    log_info "Starting destruction sequence..."
    sleep 2
    
    # Destroy in reverse order of dependencies
    destroy_module "07-monitoring" "Monitoring (CloudWatch, Alarms, SNS)"
    destroy_module "06-frontend" "Frontend (S3, CloudFront)"
    destroy_module "05-compute" "Compute (ECS, ALB, ECR)"
    
    # Handle database with snapshot option
    if [ -d "04-database" ]; then
        cd 04-database
        if [ "$KEEP_SNAPSHOTS" = false ]; then
            log_warn "Configuring RDS for deletion without snapshot..."
            # Temporarily modify to skip final snapshot
            export TF_VAR_skip_final_snapshot=true
        fi
        cd ..
        destroy_module "04-database" "Database (RDS PostgreSQL)"
    fi
    
    destroy_module "03-networking" "Networking (VPC, NAT, Security Groups)"
    destroy_module "02-security" "Security (KMS, Secrets, IAM)"
    
    if [ "$KEEP_FOUNDATION" = false ]; then
        log_warn "Destroying AWS Organization (this is permanent!)..."
        sleep 3
        destroy_module "01-foundation" "Foundation (AWS Organization)"
    else
        log_info "Skipping foundation destruction (use --destroy-foundation to remove)"
    fi
    
    cleanup_orphaned_resources
    show_next_steps
}

# Run main function
main
