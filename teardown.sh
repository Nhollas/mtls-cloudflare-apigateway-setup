#!/bin/bash

# =============================================================================
# Teardown Script: Remove all AWS resources
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}"
echo "============================================================================="
echo "  TEARDOWN: This will destroy all AWS resources"
echo "============================================================================="
echo -e "${NC}"

echo -e "${YELLOW}This will delete:${NC}"
echo "  • HTTP API Gateway (including custom domain)"
echo "  • Lambda function"
echo "  • S3 truststore bucket"
echo "  • ACM certificate"
echo "  • IAM roles"
echo "  • Cloudflare DNS records"
echo "  • Cloudflare Authenticated Origin Pulls setting"
echo ""

read -p "Are you sure you want to destroy all resources? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo -e "${GREEN}Teardown cancelled.${NC}"
    exit 0
fi

cd "$TERRAFORM_DIR"

# Export AWS credentials
eval "$(aws configure export-credentials --format env)"

# Load Cloudflare credentials from environment or prompt
if [ -z "$TF_VAR_cloudflare_api_token" ]; then
    echo -e "${YELLOW}Cloudflare API token needed for destroying Cloudflare resources${NC}"
    read -sp "Enter Cloudflare API Token: " CF_API_TOKEN
    echo ""
    export TF_VAR_cloudflare_api_token="$CF_API_TOKEN"
fi

if [ -z "$TF_VAR_cloudflare_zone_id" ] && [ -f "terraform.tfvars" ]; then
    CF_ZONE_ID=$(grep 'cloudflare_zone_id' terraform.tfvars | cut -d'"' -f2)
    if [ -n "$CF_ZONE_ID" ]; then
        export TF_VAR_cloudflare_zone_id="$CF_ZONE_ID"
    fi
fi

echo -e "\n${YELLOW}Generating destruction plan...${NC}"
terraform plan -destroy -out=destroy.tfplan

echo -e "\n${RED}============================================================================="
echo "  REVIEW THE DESTRUCTION PLAN ABOVE"
echo "=============================================================================${NC}"
echo ""
read -p "Proceed with destruction? Type 'yes' to confirm: " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" = "yes" ]; then
    echo -e "\n${YELLOW}Destroying resources...${NC}"
    terraform apply destroy.tfplan
else
    echo -e "${GREEN}Destruction cancelled.${NC}"
    rm -f destroy.tfplan
    exit 0
fi

echo -e "\n${GREEN}============================================================================="
echo "  Teardown Complete!"
echo "=============================================================================${NC}"

echo -e "\n${GREEN}All AWS and Cloudflare resources have been removed.${NC}"
echo ""
