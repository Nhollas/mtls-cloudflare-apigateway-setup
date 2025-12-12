#!/bin/bash

# =============================================================================
# mTLS Setup Script: Cloudflare WAF → AWS HTTP API Gateway
# (Cloudflare DNS version - no Route53 required)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="$SCRIPT_DIR/certs"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "============================================================================="
echo "  mTLS Setup: Cloudflare WAF → AWS HTTP API Gateway"
echo "  (Cloudflare DNS version)"
echo "============================================================================="
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Step 1: Check prerequisites
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}✗ $1 is not installed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $1 found${NC}"
        return 0
    fi
}

MISSING=0
check_command "aws" || MISSING=1
check_command "terraform" || MISSING=1
check_command "curl" || MISSING=1

if [ $MISSING -eq 1 ]; then
    echo -e "\n${RED}Please install missing prerequisites and try again.${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "\n${YELLOW}Checking AWS credentials...${NC}"
if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✓ AWS credentials valid (Account: $ACCOUNT_ID)${NC}"
else
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo "  Run: aws configure"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 2: Download Cloudflare Origin Pull CA Certificate
# -----------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 2: Downloading Cloudflare Origin Pull CA certificate...${NC}"

mkdir -p "$CERTS_DIR"

CLOUDFLARE_CA_URL="https://developers.cloudflare.com/ssl/static/authenticated_origin_pull_ca.pem"

if [ -f "$CERTS_DIR/cloudflare-origin-pull-ca.pem" ]; then
    echo -e "${GREEN}✓ Certificate already exists${NC}"
else
    curl -sSL "$CLOUDFLARE_CA_URL" -o "$CERTS_DIR/cloudflare-origin-pull-ca.pem"
    echo -e "${GREEN}✓ Certificate downloaded${NC}"
fi

# Verify the certificate
openssl x509 -in "$CERTS_DIR/cloudflare-origin-pull-ca.pem" -noout -subject -dates
echo -e "${GREEN}✓ Certificate is valid${NC}"

# -----------------------------------------------------------------------------
# Step 3: Configure Terraform variables
# -----------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 3: Terraform configuration${NC}"

if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    echo ""
    read -p "Enter your custom domain (e.g., api-origin.yourdomain.com): " DOMAIN_NAME
    read -p "Enter AWS region [eu-west-2]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-eu-west-2}

    echo ""
    echo -e "${YELLOW}Cloudflare Configuration:${NC}"
    echo "To get your Cloudflare credentials:"
    echo "  Zone ID: Dashboard > Select Domain > Overview > Zone ID"
    echo "  API Token: Dashboard > Profile > API Tokens > Create Token"
    echo "    Required permissions: DNS (Edit), SSL and Certificates (Edit)"
    echo ""
    read -p "Enter Cloudflare Zone ID: " CF_ZONE_ID
    read -sp "Enter Cloudflare API Token: " CF_API_TOKEN
    echo ""

    cat > "$TERRAFORM_DIR/terraform.tfvars" << EOF
aws_region              = "$AWS_REGION"
domain_name             = "$DOMAIN_NAME"
cloudflare_ca_cert_path = "../certs/cloudflare-origin-pull-ca.pem"

# Cloudflare Configuration
cloudflare_api_token = "$CF_API_TOKEN"
cloudflare_zone_id   = "$CF_ZONE_ID"
EOF
    echo -e "${GREEN}✓ Created terraform.tfvars${NC}"
else
    echo -e "${GREEN}✓ terraform.tfvars already exists${NC}"
    DOMAIN_NAME=$(grep 'domain_name' "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)
fi

# -----------------------------------------------------------------------------
# Step 4: Deploy with Terraform
# -----------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 4: Deploying AWS infrastructure...${NC}"

# Export AWS credentials for Terraform
echo "Exporting AWS credentials for Terraform..."
eval "$(aws configure export-credentials --format env)"

cd "$TERRAFORM_DIR"

echo "Initializing Terraform..."
terraform init

echo -e "\n${BLUE}Planning deployment...${NC}"
terraform plan -out=tfplan

echo ""
read -p "Do you want to apply this plan? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
fi

echo -e "\n${BLUE}Applying...${NC}"
terraform apply tfplan

# -----------------------------------------------------------------------------
# Step 5: Display next steps
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}============================================================================="
echo "  AWS Deployment Complete!"
echo "=============================================================================${NC}"

echo ""
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${YELLOW}What just happened:${NC}"
echo "  ✓ ACM certificate created and validated automatically (Terraform waited)"
echo "  ✓ API Gateway custom domain created with mTLS"
echo "  ✓ Cloudflare DNS records configured"
echo "  ✓ Authenticated Origin Pulls enabled"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait 2-5 minutes for DNS propagation"
echo "     (If curl fails, flush DNS cache: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder)"
echo ""
echo "  2. Verify SSL mode in Cloudflare Dashboard is 'Full (strict)'"
echo "     Go to: SSL/TLS > Overview"
echo ""
echo "  3. Test your API:"
echo "     curl https://$DOMAIN_NAME/health"
echo ""
echo -e "${GREEN}Your mTLS-protected API is ready!${NC}"
