# Backend Configuration for Terraform State

# This file shows how to configure S3 backend for Terraform state management
# Copy this to each module as backend.tf

## Step 1: Create S3 Bucket and DynamoDB Table (one-time setup)

# Run this once to create state backend infrastructure:

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket waterapps-terraform-state-YOUR_ACCOUNT_ID \
  --region ap-southeast-2 \
  --create-bucket-configuration LocationConstraint=ap-southeast-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket waterapps-terraform-state-YOUR_ACCOUNT_ID \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket waterapps-terraform-state-YOUR_ACCOUNT_ID \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket waterapps-terraform-state-YOUR_ACCOUNT_ID \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name waterapps-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-2
```

## Step 2: Configure Backend in Each Module

### Foundation Module (foundation/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "foundation/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Security Module (security/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/security/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Networking Module (networking/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/networking/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Database Module (database/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/database/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Compute Module (compute/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/compute/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Frontend Module (frontend/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/frontend/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

### Monitoring Module (monitoring/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "development/monitoring/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

## For Production Environment

Use different state paths:

```hcl
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "production/security/terraform.tfstate"  # Note: production prefix
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
```

## Migration to Backend

If you've already run terraform without backend:

```bash
# In each module directory:
cd foundation

# Create backend.tf with above configuration
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "waterapps-terraform-state-YOUR_ACCOUNT_ID"
    key            = "foundation/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "waterapps-terraform-locks"
  }
}
EOF

# Re-initialize and migrate state
terraform init -migrate-state

# Confirm migration
# Delete local state files
rm -f terraform.tfstate*
```

## Best Practices

1. **Never commit state files** - Add to .gitignore:
   ```
   # .gitignore
   *.tfstate
   *.tfstate.*
   .terraform/
   .terraform.lock.hcl
   ```

2. **Use separate state files per module** - Already done above

3. **Use workspaces for environment separation** (Alternative approach):
   ```bash
   terraform workspace new development
   terraform workspace new production
   terraform workspace select development
   ```

4. **Enable state file versioning** - Already configured in S3 setup

5. **Backup state regularly**:
   ```bash
   # Manual backup
   aws s3 cp s3://waterapps-terraform-state-YOUR_ACCOUNT_ID/ \
     ./terraform-state-backup/ \
     --recursive \
     --region ap-southeast-2
   ```

## State Management Commands

```bash
# List state resources
terraform state list

# Show specific resource
terraform state show aws_instance.example

# Remove resource from state (dangerous!)
terraform state rm aws_instance.example

# Import existing resource
terraform import aws_instance.example i-1234567890abcdef0

# Pull current state
terraform state pull > current-state.json

# Lock state manually (emergency)
# Get lock info from DynamoDB console if needed
```

## Cost

S3 state storage: ~$0.023/GB/month (negligible - state files are KB)
DynamoDB: Pay-per-request, ~$0.01-0.05/month for typical usage

**Total cost for state management: <$1/month**

## Security Considerations

1. State files contain sensitive data (passwords, keys)
2. Encrypt at rest (enabled)
3. Encrypt in transit (S3 uses TLS)
4. Restrict S3 bucket access via IAM
5. Enable MFA delete on state bucket (optional):
   ```bash
   aws s3api put-bucket-versioning \
     --bucket waterapps-terraform-state-YOUR_ACCOUNT_ID \
     --versioning-configuration Status=Enabled,MFADelete=Enabled \
     --mfa "arn:aws:iam::ACCOUNT:mfa/root-account-mfa-device XXXXXX"
   ```

## Troubleshooting

### State Lock Error
```
Error: Error acquiring the state lock
```

**Solution:**
```bash
# Force unlock (use lock ID from error message)
terraform force-unlock LOCK_ID
```

### State Drift
```bash
# Detect drift
terraform plan

# Refresh state to match reality
terraform refresh

# Or during plan
terraform plan -refresh-only
```

### Multiple People Editing
- Backend with DynamoDB locking prevents simultaneous edits
- Use version control for .tf files
- Communicate before running terraform apply
