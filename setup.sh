#!/bin/bash

# =============================================================================
# Cloudflare WAF + REST API Gateway Setup Script
# (Cloudflare DNS version - no Route53 required)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "============================================================================="
echo "  Cloudflare WAF + AWS REST API Gateway Setup"
echo "  (Resource Policy IP Whitelist)"
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
# Step 2: Configure Terraform variables
# -----------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 2: Terraform configuration${NC}"

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
    read -sp "Enter Cloudflare API Token (input hidden): " CF_API_TOKEN
    echo ""

    # Provide feedback that token was received
    if [ -n "$CF_API_TOKEN" ]; then
        TOKEN_LEN=${#CF_API_TOKEN}
        TOKEN_PREVIEW="${CF_API_TOKEN:0:4}...${CF_API_TOKEN: -4}"
        echo -e "${GREEN}✓ Token received (${TOKEN_LEN} characters): ${TOKEN_PREVIEW}${NC}"
    else
        echo -e "${RED}✗ No token entered${NC}"
        exit 1
    fi
    echo ""

    # Export Cloudflare credentials as environment variables (more secure than tfvars file)
    export TF_VAR_cloudflare_api_token="$CF_API_TOKEN"
    export TF_VAR_cloudflare_zone_id="$CF_ZONE_ID"

    cat > "$TERRAFORM_DIR/terraform.tfvars" << EOF
aws_region = "$AWS_REGION"
domain_name = "$DOMAIN_NAME"

# Cloudflare Configuration (using environment variables for security)
# TF_VAR_cloudflare_api_token and TF_VAR_cloudflare_zone_id are set as environment variables
cloudflare_zone_id = "$CF_ZONE_ID"
EOF
    echo -e "${GREEN}✓ Created terraform.tfvars (API token stored as environment variable)${NC}"
else
    echo -e "${GREEN}✓ terraform.tfvars already exists${NC}"
    DOMAIN_NAME=$(grep 'domain_name' "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)

    # Load Cloudflare credentials from environment or prompt
    if [ -z "$TF_VAR_cloudflare_api_token" ]; then
        echo -e "${YELLOW}Cloudflare API token not found in environment${NC}"
        read -sp "Enter Cloudflare API Token: " CF_API_TOKEN
        echo ""
        export TF_VAR_cloudflare_api_token="$CF_API_TOKEN"
    else
        echo -e "${GREEN}✓ Using Cloudflare API token from environment${NC}"
    fi

    if [ -z "$TF_VAR_cloudflare_zone_id" ]; then
        CF_ZONE_ID=$(grep 'cloudflare_zone_id' "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)
        if [ -n "$CF_ZONE_ID" ]; then
            export TF_VAR_cloudflare_zone_id="$CF_ZONE_ID"
            echo -e "${GREEN}✓ Loaded Cloudflare Zone ID from terraform.tfvars${NC}"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Step 3: Deploy with Terraform
# -----------------------------------------------------------------------------
echo -e "\n${YELLOW}Step 3: Deploying AWS infrastructure...${NC}"

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
# Step 4: Display next steps
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}============================================================================="
echo "  AWS Deployment Complete!"
echo "=============================================================================${NC}"

echo ""
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${YELLOW}What just happened:${NC}"
echo "  ✓ ACM certificate created and validated automatically (Terraform waited)"
echo "  ✓ REST API Gateway custom domain created"
echo "  ✓ Resource policy restricts access to Cloudflare IPs only"
echo "  ✓ Cloudflare DNS records configured"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait 2-5 minutes for DNS propagation"
echo "     (If curl fails, flush DNS cache: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder)"
echo ""
echo "  2. Verify SSL mode in Cloudflare Dashboard is 'Full (strict)'"
echo "     Go to: SSL/TLS > Overview"
echo ""
echo "  3. Configure Cloudflare WAF (recommended):"
echo "     Go to: Cloudflare Dashboard > Security > WAF"
echo "     - Enable managed rulesets"
echo "     - Set up rate limiting"
echo "     - Configure bot protection"
echo ""
echo "  4. Test your API:"
echo "     curl https://$DOMAIN_NAME/health"
echo ""
echo -e "${GREEN}Your Cloudflare-protected API is ready!${NC}"
