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

echo -e "\n${YELLOW}Destroying resources...${NC}"
terraform destroy -auto-approve

echo -e "\n${GREEN}============================================================================="
echo "  Teardown Complete!"
echo "=============================================================================${NC}"

echo -e "\n${GREEN}All AWS and Cloudflare resources have been removed.${NC}"
echo ""
