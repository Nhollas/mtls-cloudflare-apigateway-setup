# Cloudflare WAF + AWS REST API Gateway Setup

This setup protects your AWS REST API Gateway by routing all traffic through Cloudflare's WAF and using resource policies to restrict access to Cloudflare IP ranges only.

> **Note**: This is a proof of concept (POC). See `proof-of-concept.md` for evaluation details and decision criteria.

## Architecture

```
┌──────────┐      ┌─────────────────┐      ┌──────────────────┐      ┌────────┐
│  Client  │ ───► │  Cloudflare WAF │ ───► │ REST API Gateway │ ───► │ Lambda │
└──────────┘      │  (Proxy + WAF)  │      │  (IP Whitelist)  │      └────────┘
                  └─────────────────┘      └──────────────────┘
                          │
                  Only Cloudflare IPs
                  allowed by resource policy
```

**Security Flow:**
1. Client requests hit Cloudflare first (WAF rules, DDoS protection, bot mitigation)
2. Cloudflare connects to your API Gateway origin
3. API Gateway resource policy validates source IP is from Cloudflare
4. Invalid IPs are rejected with 403 Forbidden
5. Valid requests are forwarded to Lambda

## Prerequisites

- **AWS Account** with CLI configured
- **Cloudflare Account** with domain
- **Terraform** >= 1.0
- **Cloudflare API Token** with DNS and SSL permissions
- **Cloudflare Zone ID** for your domain

## Quick Start

**Prerequisites:**
- AWS CLI configured (`aws configure`)
- Terraform installed
- Domain managed by Cloudflare

### Step 1: Get Cloudflare Credentials

Before running setup, you'll need two values from Cloudflare:

**Zone ID:**
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) → Select your domain
2. Copy **Zone ID** from Overview page (right sidebar)

**API Token:**
1. Go to [API Tokens](https://dash.cloudflare.com/profile/api-tokens) → Create Token
2. Use "Edit zone DNS" template
3. Add permissions: `DNS (Edit)` + `SSL and Certificates (Edit)`
4. Select your specific zone → Create → Copy the token

### Step 2: Run Setup

```bash
./setup.sh
```

The script will **prompt you for**:
- ✍️ Your custom domain (e.g., `api.yourdomain.com`)
- ✍️ AWS region (default: `eu-west-2`)
- ✍️ Cloudflare Zone ID (from Step 1)
- ✍️ Cloudflare API Token (from Step 1)

Then **automatically**:
- ⚙️ Creates `terraform.tfvars` with your configuration
- ⚙️ Deploys all AWS infrastructure (REST API Gateway, Lambda, ACM)
- ⏳ Waits for ACM certificate validation (5-30 minutes)
- ⚙️ Creates API Gateway custom domain with resource policy
- ⚙️ Configures Cloudflare DNS records

**One command. Fully automated. No manual configuration required.**

### 3. Test

```bash
# Through Cloudflare proxy (should SUCCEED)
curl https://api.yourdomain.com/health
# Expected: {"message":"Hello from mTLS-protected API!","timestamp":"..."}

# Direct access to API Gateway (should FAIL with 403)
curl https://xxxxxxxxxx.execute-api.region.amazonaws.com/prod/health
# Expected: {"message":"Forbidden"} with 403 status
```

## File Structure

```
mtls-cloudflare-apigateway-setup/
├── setup.sh                  # Automated deployment script
├── teardown.sh               # Automated teardown script
├── README.md                 # This file
├── proof-of-concept.md       # POC evaluation and decision criteria
└── terraform/
    ├── main.tf               # AWS infrastructure
    ├── cloudflare.tf         # Cloudflare configuration
    ├── variables.tf          # Input variables
    ├── outputs.tf            # Outputs
    └── terraform.tfvars      # Auto-created by setup.sh
```

## AWS Resources Created

| Resource | Purpose |
|----------|---------|
| REST API Gateway | Main API with resource policy |
| API Gateway Custom Domain | TLS-enabled endpoint |
| Lambda Function | Simple test handler |
| ACM Certificate | TLS cert for custom domain |
| IAM Role | Lambda execution role |
| Resource Policy | Restricts access to Cloudflare IPs |

**Cloudflare Resources:**
| Resource | Purpose |
|----------|---------|
| DNS Records | ACM validation + API origin CNAME |
| WAF | Enabled by default when proxied |

## Cost Estimate (Free Tier)

| Service | Free Tier | Your Usage |
|---------|-----------|------------|
| API Gateway | 1M requests/month | ✅ Covered |
| Lambda | 1M requests + 400K GB-s | ✅ Covered |
| ACM | Free | ✅ Free |
| Cloudflare | Free plan available | ✅ Basic features free |

**Total: $0/month** within free tier limits

## Security Features

### Cloudflare WAF (Layer 1)
- DDoS protection
- Bot mitigation
- SQL injection & XSS prevention
- Rate limiting
- Geo-blocking
- Custom WAF rules
- **Optional:** Company IP allowlist (only allow requests from your office/VPN)

### REST API Resource Policy (Layer 2)
- IP whitelist for Cloudflare ranges
- Blocks all non-Cloudflare traffic
- No secrets to manage
- Automatically updated Cloudflare IPs in Terraform

### Defense in Depth
Both layers work together:
1. **Cloudflare** blocks non-company IPs (if configured)
2. **AWS API Gateway** blocks non-Cloudflare IPs
3. Direct API Gateway access is impossible - all traffic must flow through Cloudflare

## Troubleshooting

### API Gateway returns 403
✅ **Expected for direct access!** The resource policy blocks all non-Cloudflare IPs. Traffic must go through your custom domain (Cloudflare proxy).

**If you get 403 through Cloudflare:**
- Check Cloudflare DNS record is proxied (orange cloud ON)
- Verify SSL mode is "Full (strict)"
- Check Cloudflare IP ranges are up to date in `terraform/main.tf`

### Cloudflare returns 526 (Invalid SSL certificate)
- Ensure SSL mode is "Full (strict)"
- Verify the custom domain certificate is valid in ACM
- Check DNS propagation completed

### DNS not resolving
- Wait for DNS propagation (usually 5-10 minutes)
- Run: `terraform state list | grep cloudflare_record` to verify DNS records exist
- Check Cloudflare DNS record is proxied (orange cloud ON) in dashboard

## Restricting Access to Company IPs (Optional)

By default, your API is accessible from any IP address (protected by Cloudflare WAF). To restrict access to only your company's IP addresses:

### Step 1: Add Your Company IPs to terraform.tfvars

```hcl
company_ip_allowlist = [
  "203.0.113.10/32",      # Office static IP
  "198.51.100.0/24",      # VPN CIDR range
  "192.0.2.50/32"         # Additional IP
]
```

**Finding your IP:**
```bash
curl ifconfig.me
```

**Important Notes:**
- Use `/32` for single IPs (e.g., `203.0.113.10/32`)
- Use CIDR ranges for multiple IPs (e.g., `198.51.100.0/24` allows 198.51.100.0-255)
- IPv4 only (IPv6 support can be added if needed)

### Step 2: Apply the Changes

```bash
cd terraform
terraform apply
```

This creates a Cloudflare WAF rule that:
- ✅ Allows requests from your company IPs
- ❌ Blocks all other IPs with 403 Forbidden

### Step 3: Verify

**From allowed IP (should work):**
```bash
curl https://api-origin.nhollas.com/health
# Expected: 200 OK
```

**From other IP (should be blocked):**
```bash
curl https://api-origin.nhollas.com/health
# Expected: 403 Forbidden or Cloudflare error page
```

### Removing IP Restrictions

To allow all IPs again, set the list to empty in `terraform.tfvars`:
```hcl
company_ip_allowlist = []
```

Then run `terraform apply`.

## Updating Cloudflare IP Ranges

Cloudflare rarely changes their IP ranges, but when they do:

1. Check latest ranges: https://www.cloudflare.com/ips/
2. Update `locals.cloudflare_ipv4` and `locals.cloudflare_ipv6` in `terraform/main.tf`
3. Run: `terraform apply`

## Teardown

To destroy all resources:

```bash
./teardown.sh
```

This will remove:
- All AWS resources (API Gateway, Lambda, ACM, IAM)
- All Cloudflare resources (DNS records)

## Security Notes

1. **Cloudflare WAF is your primary defense** - Configure it properly:
   - Go to Cloudflare Dashboard > Security > WAF
   - Enable managed rulesets
   - Set up rate limiting
   - Configure bot protection

2. **Keep your origin domain obscure** - Don't use obvious names like `api.example.com`

3. **Monitor Cloudflare Analytics** - Check for blocked threats and adjust WAF rules

4. **Set up billing alerts** - Even with free tier, monitor for unexpected usage

5. **Consider AWS WAF** - For defense-in-depth, you can add AWS WAF (additional cost)

## For Contributors

If you're working on this project and need to run Terraform commands manually (outside of `setup.sh`/`teardown.sh`), you'll need to export AWS credentials each time.

**Option 1: Manual export (each time)**
```bash
eval "$(aws configure export-credentials --format env)"
terraform plan
```

**Option 2: Shell alias (recommended)**

Add this to your `~/.zshrc` (or `~/.bashrc`):
```bash
tf() {
  eval "$(aws configure export-credentials --format env)"
  terraform "$@"
}
```

Then reload: `source ~/.zshrc`

Now you can use `tf` instead of `terraform`:
```bash
tf plan
tf apply
tf destroy
```

**Note:** The `setup.sh` and `teardown.sh` scripts already handle credential export automatically, so you don't need this alias to use them.

## Documentation

- **`proof-of-concept.md`** - Evaluation of this approach vs alternatives

## References

- [AWS REST API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-rest-api.html)
- [AWS REST API Resource Policies](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-resource-policies.html)
- [Cloudflare WAF](https://developers.cloudflare.com/waf/)
- [Cloudflare IP Ranges](https://www.cloudflare.com/ips/)
- [Cloudflare Terraform Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
