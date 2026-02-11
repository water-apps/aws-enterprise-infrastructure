#!/bin/bash

# GitHub Repository Setup Script
# This script helps you create and push to GitHub

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GitHub Repository Setup for aws-enterprise-infrastructure${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}[WARN]${NC} Git is not installed. Please install git first."
    exit 1
fi

# Check if GitHub CLI is installed (optional)
if command -v gh &> /dev/null; then
    echo -e "${GREEN}✓${NC} GitHub CLI detected"
    USE_GH_CLI=true
else
    echo -e "${YELLOW}!${NC} GitHub CLI not found. You'll need to create the repo manually on GitHub."
    USE_GH_CLI=false
fi

echo ""
echo "This script will help you:"
echo "1. Initialize git repository"
echo "2. Create .gitignore for sensitive files"
echo "3. Make initial commit"
if [ "$USE_GH_CLI" = true ]; then
    echo "4. Create GitHub repository (public)"
    echo "5. Push to GitHub"
else
    echo "4. Provide instructions for manual GitHub setup"
fi

echo ""
read -p "Continue? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}[1/5]${NC} Initializing git repository..."

# Initialize git if not already done
if [ ! -d ".git" ]; then
    git init
    echo -e "${GREEN}✓${NC} Git repository initialized"
else
    echo -e "${YELLOW}!${NC} Git repository already exists"
fi

echo ""
echo -e "${GREEN}[2/5]${NC} Checking .gitignore..."

# .gitignore should already exist, but verify critical patterns
if grep -q "*.tfstate" .gitignore; then
    echo -e "${GREEN}✓${NC} .gitignore properly configured"
else
    echo -e "${YELLOW}!${NC} Warning: .gitignore may need review"
fi

echo ""
echo -e "${GREEN}[3/5]${NC} Staging files for commit..."

# Stage all files
git add .

echo ""
echo -e "${GREEN}[4/5]${NC} Creating initial commit..."

# Create initial commit
git commit -m "Initial commit: AWS Enterprise Infrastructure v1.0.0

- Multi-account AWS Organization setup
- ECS Fargate with auto-scaling
- RDS PostgreSQL with backups
- S3 + CloudFront CDN
- Complete monitoring and security
- Automated deployment scripts
- Comprehensive documentation

Cost: \$100-150/month (dev), \$300-400/month (prod)"

echo -e "${GREEN}✓${NC} Initial commit created"

echo ""
echo -e "${GREEN}[5/5]${NC} Setting up GitHub repository..."

if [ "$USE_GH_CLI" = true ]; then
    echo ""
    read -p "Create public GitHub repository? (y/n): " create_repo
    
    if [ "$create_repo" = "y" ]; then
        gh repo create aws-enterprise-infrastructure \
            --public \
            --description "Production-ready AWS infrastructure with enterprise security practices. Multi-account, ECS Fargate, RDS, CloudFront. \$100-400/month." \
            --source=. \
            --remote=origin \
            --push
        
        echo -e "${GREEN}✓${NC} Repository created and pushed to GitHub!"
        echo ""
        echo "Your repository is now live at:"
        gh repo view --web
    else
        echo "Skipping repository creation."
    fi
else
    echo ""
    echo "GitHub CLI not available. Follow these steps manually:"
    echo ""
    echo "1. Go to https://github.com/new"
    echo "2. Repository name: ${BLUE}aws-enterprise-infrastructure${NC}"
    echo "3. Description: ${BLUE}Production-ready AWS infrastructure with enterprise security practices. Multi-account, ECS Fargate, RDS, CloudFront. \$100-400/month.${NC}"
    echo "4. Choose: ${BLUE}Public${NC}"
    echo "5. DO NOT initialize with README (we already have one)"
    echo "6. Click 'Create repository'"
    echo ""
    echo "Then run these commands:"
    echo ""
    echo "  ${BLUE}git remote add origin https://github.com/YOUR_USERNAME/aws-enterprise-infrastructure.git${NC}"
    echo "  ${BLUE}git branch -M main${NC}"
    echo "  ${BLUE}git push -u origin main${NC}"
    echo ""
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Add repository topics on GitHub:"
echo "   aws, terraform, infrastructure, devops, ecs, fargate, rds,"
echo "   cloudfront, enterprise, startup, infrastructure-as-code"
echo ""
echo "2. Enable GitHub Discussions (optional):"
echo "   Settings → Features → Discussions"
echo ""
echo "3. Add repository description (if not using gh cli):"
echo "   Production-ready AWS infrastructure with enterprise security"
echo "   practices. Multi-account, ECS Fargate, RDS, CloudFront."
echo "   \$100-400/month."
echo ""
echo "4. Share with:"
echo "   - LinkedIn (showcase your DevOps expertise)"
echo "   - Consulting prospects (proof of enterprise skills)"
echo "   - Dev community (help others learn)"
echo ""
echo "Repository ready to showcase your enterprise DevOps experience! 🚀"
echo ""
