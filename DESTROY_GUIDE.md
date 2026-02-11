# How to Destroy Infrastructure - Zero Cost Guide

## ⚠️ IMPORTANT: Avoiding Unexpected Costs

AWS charges for resources while they exist, NOT for Terraform state. Destroying resources = stopping charges.

## Quick Destroy (Emergency - Stop All Costs Now!)

If you need to stop all costs immediately:

```bash
# Run this from the terraform-waterapps directory
./destroy-all.sh
```

Or manually in reverse order:

```bash
cd 07-monitoring && terraform destroy -auto-approve && cd ..
cd 06-frontend && terraform destroy -auto-approve && cd ..
cd 05-compute && terraform destroy -auto-approve && cd ..
cd 04-database && terraform destroy -auto-approve && cd ..
cd 03-networking && terraform destroy -auto-approve && cd ..
cd 02-security && terraform destroy -auto-approve && cd ..
```

**Time to complete:** 15-20 minutes
**Result:** ~$0 charges going forward (maybe $0.01-0.10 for final hour)

---

## Detailed Destruction Order

### Why Reverse Order Matters

Must destroy in **REVERSE** of creation order due to dependencies:
- Can't delete VPC while ECS tasks are running in it
- Can't delete security groups while RDS is using them
- Can't delete IAM roles while ECS services reference them

### Step-by-Step Destruction

#### Step 7→1: Destroy Monitoring (costs ~$0.50/month)
```bash
cd 07-monitoring
terraform destroy
# Confirm: yes
cd ..
```
**Removes:** CloudWatch dashboards, alarms, SNS topics
**Cost savings:** Minimal, but cleans up clutter

---

#### Step 6→2: Destroy Frontend (costs ~$1-5/month)
```bash
cd 06-frontend
terraform destroy
# Confirm: yes
cd ..
```
**Removes:** S3 bucket, CloudFront distribution
**IMPORTANT:** CloudFront takes 15-20 minutes to delete (AWS limitation)
**Cost savings:** $1-10/month depending on traffic

---

#### Step 5→3: Destroy Compute (costs ~$25-50/month)
```bash
cd 05-compute
terraform destroy
# Confirm: yes
cd ..
```
**Removes:** 
- ECS cluster and services (stops tasks immediately)
- Application Load Balancer
- ECR repository with Docker images
- CloudWatch log groups

**Cost savings:** $25-50/month (biggest saver!)
**Time:** 5-10 minutes

---

#### Step 4→4: Destroy Database (costs ~$15-90/month)
```bash
cd 04-database

# IMPORTANT DECISION POINT:
# Do you want to keep a final snapshot? (Recommended for production)

# Option A: Keep final snapshot (can restore later)
terraform destroy
# Confirm: yes
# Snapshot costs ~$0.095/GB/month (e.g., 20GB = $2/month)

# Option B: No snapshot (complete deletion - CANNOT UNDO)
# Edit variables.tf first:
# Set: skip_final_snapshot = true
terraform destroy
# Confirm: yes

cd ..
```
**Removes:** RDS instance, subnet groups, parameter groups
**Cost savings:** $15-90/month depending on instance size
**Time:** 5-10 minutes
**⚠️ WARNING:** Data will be lost unless you keep snapshot!

---

#### Step 3→5: Destroy Networking (costs ~$35-90/month)
```bash
cd 03-networking
terraform destroy
# Confirm: yes
cd ..
```
**Removes:** 
- NAT Gateway (biggest cost!)
- VPC endpoints
- Security groups
- Subnets and VPC

**Cost savings:** $35-90/month
**Time:** 2-5 minutes

---

#### Step 2→6: Destroy Security (costs ~$2-3/month)
```bash
cd 02-security
terraform destroy
# Confirm: yes
cd ..
```
**Removes:**
- KMS keys (scheduled for deletion in 7-30 days)
- Secrets Manager secrets
- IAM roles and policies
- CI/CD user

**Cost savings:** $2-3/month
**Note:** KMS keys have deletion waiting period (security feature)

---

#### Step 1→7: Foundation (DON'T DESTROY unless closing AWS accounts)
```bash
# ONLY do this if you want to close all AWS accounts!
cd 01-foundation

# READ THIS FIRST:
# - Destroys AWS Organization
# - Closes dev, prod, shared accounts
# - Loses consolidated billing
# - You'll need to recreate everything from scratch

# If you're SURE:
terraform destroy
# Confirm: yes
```

**Cost:** $0/month (Organization is free)
**DO NOT DESTROY** unless you're completely done with WaterApps infrastructure

---

## Partial Destruction Strategies

### Strategy 1: "Pause Development" (Save ~80% of costs)

Keep infrastructure, just stop expensive compute:

```bash
# Stop ECS tasks (can restart later)
aws ecs update-service \
  --cluster development-waterapps-cluster \
  --service development-backend-service \
  --desired-count 0

# Result: Keeps infrastructure, stops $25-50/month in compute
# Restart: Set --desired-count 1
```

**Cost after pause:** ~$50/month (RDS + NAT + storage)
**Restart time:** 2 minutes

---

### Strategy 2: "Weekend Shutdown" (Save ~$30/month)

Destroy expensive resources Friday, recreate Monday:

```bash
# Friday evening
cd 05-compute && terraform destroy -auto-approve
cd ../04-database && terraform destroy -auto-approve

# Monday morning  
cd 04-database && terraform apply -auto-approve
cd ../05-compute && terraform apply -auto-approve
```

**Savings:** ~$30/month (compute + RDS for 8 days/month)
**Trade-off:** 30-minute setup Monday mornings

---

### Strategy 3: "Production Only When Needed"

Keep dev destroyed, deploy prod only for demos/customers:

```bash
# Default state: dev environment destroyed
# Cost: $0/month

# Before customer demo:
cd 01-foundation && terraform apply
cd 02-security && terraform apply
# ... deploy through 07-monitoring

# After demo:
# Destroy 07→02 (keep foundation)

# Cost: $0 most of the time, $300-400 only during active weeks
```

---

## Cost-to-Zero Checklist

Run this checklist to ensure NO ongoing AWS costs:

```bash
# 1. Check ECS tasks are stopped
aws ecs list-services --cluster development-waterapps-cluster

# 2. Check no RDS instances
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]'

# 3. Check NAT Gateways deleted
aws ec2 describe-nat-gateways --filter "Name=state,Values=available"

# 4. Check Load Balancers deleted
aws elbv2 describe-load-balancers

# 5. Check CloudFront distributions
aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,Status]'

# 6. Verify current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost

# Expected result after destruction: <$1 for the current month
```

---

## What Survives Destruction

These continue to exist (and may have minimal costs):

### 1. S3 Buckets (if not empty)
```bash
# Check for leftover buckets
aws s3 ls

# Force delete with contents
aws s3 rb s3://bucket-name --force
```

### 2. Snapshots
```bash
# Check for RDS snapshots
aws rds describe-db-snapshots --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,AllocatedStorage]'

# Delete if not needed
aws rds delete-db-snapshot --db-snapshot-identifier snapshot-name
```

### 3. CloudWatch Logs (if retention set)
```bash
# Check log groups
aws logs describe-log-groups --query 'logGroups[*].[logGroupName,storedBytes]'

# Delete if not needed
aws logs delete-log-group --log-group-name /ecs/development-waterapps
```

### 4. KMS Keys (deletion waiting period)
```bash
# Check key status
aws kms list-keys
aws kms describe-key --key-id KEY_ID

# Keys cost $1/month until deleted (7-30 day wait)
```

### 5. Secrets Manager (if not deleted)
```bash
# Check secrets
aws secretsmanager list-secrets

# Cost: $0.40/secret/month during retention period
```

---

## Automated Destroy Script

I'll create a script that handles everything safely:

```bash
#!/bin/bash
# This script is included in your package as destroy-all.sh

./destroy-all.sh

# Options:
./destroy-all.sh --keep-snapshots    # Keep RDS snapshots
./destroy-all.sh --keep-foundation   # Don't destroy AWS Organization (recommended)
./destroy-all.sh --force             # Skip confirmations (dangerous!)
```

---

## Re-deployment After Destruction

Good news: You can recreate everything quickly!

```bash
# After complete destruction, to redeploy:
./deploy.sh development all

# Time: 1-2 hours (mostly automated)
# Cost: Back to ~$100-150/month
```

Your Terraform code is the "source of truth" - destruction is reversible!

---

## Emergency Cost Alerts

Set these up BEFORE deploying:

```bash
# In 01-foundation, already configured:
# - Budget alerts at 80%, 90%, 100% of $300
# - Cost anomaly detection
# - Daily email summaries

# To change budget:
# Edit: 01-foundation/variables.tf
monthly_budget_limit = "100"  # Lower for testing
```

---

## Cost After Partial Destruction

| Scenario | Monthly Cost |
|----------|-------------|
| Everything running (dev) | $100-150 |
| Compute stopped (ECS tasks = 0) | $50-70 |
| Compute + DB destroyed | $20-30 |
| Only networking remains | $35-40 |
| Everything destroyed except foundation | $0-2 |
| Complete destruction | $0 |

---

## Common Destruction Errors

### Error: "Resource still in use"
```bash
# Solution: Wait 5 minutes, retry
terraform destroy
```

### Error: "Cannot delete non-empty S3 bucket"
```bash
# Solution: Empty bucket first
aws s3 rm s3://bucket-name --recursive
terraform destroy
```

### Error: "CloudFront distribution must be disabled first"
```bash
# Solution: Wait 15-20 minutes for AWS to disable it
# Or manually in console: disable → wait → delete
```

### Error: "Deletion protection enabled"
```bash
# Solution: Edit main.tf, set deletion_protection = false
# Then: terraform apply, then terraform destroy
```

---

## "Oops, I Destroyed Too Much!" Recovery

### If you destroyed database without snapshot:
❌ **Data is GONE** - cannot recover
✅ **Lesson learned:** Always keep snapshots in production

### If you destroyed everything but kept Terraform code:
✅ **Easy fix:** Redeploy with `./deploy.sh development all`

### If you destroyed Terraform state files:
⚠️ **Partial fix possible:**
```bash
# Import existing resources back into state
terraform import aws_vpc.main vpc-xxxxx
terraform import aws_instance.example i-xxxxx
# ... repeat for each resource
```

### If you destroyed AWS Organization accidentally:
⚠️ **Complex recovery:**
- Contact AWS Support
- May need to recreate accounts
- Can take several days

---

## Pro Tips from Your Banking Experience

You know from RBA/PFB that:

1. **Always test destroy in dev first** - Never first-time destroy in prod
2. **Snapshots are cheap insurance** - $2/month vs. irreplaceable data
3. **Document before destroying** - Export configurations, take screenshots
4. **Notify stakeholders** - Even if it's just you, write it down
5. **Verify costs drop** - Check billing console 24 hours after destruction

---

## Final Reminders

✅ **Destruction is reversible** (except data loss)  
✅ **Terraform state doesn't cost anything** - only live resources  
✅ **Can partially destroy** to save costs while keeping infrastructure  
✅ **Foundation can stay** - costs $0, enables quick redeployment  
✅ **Always check billing after 24 hours** to confirm costs stopped  

**When in doubt: Destroy and redeploy later. Your time is worth more than $100/month.**
