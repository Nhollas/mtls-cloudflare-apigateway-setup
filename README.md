# mTLS Setup: Cloudflare WAF → AWS HTTP API Gateway

This setup protects your AWS HTTP API Gateway by requiring all traffic to come through Cloudflare's WAF using mutual TLS (mTLS) authentication.

> **Note**: This is a proof of concept (POC). See `proof-of-concept.md` for evaluation details and decision criteria.

## Architecture

```
┌──────────┐      ┌─────────────────┐      ┌──────────────────┐      ┌────────┐
│  Client  │ ───► │  Cloudflare WAF │ ───► │  HTTP API Gateway │ ───► │ Lambda │
└──────────┘      │  (Proxy + WAF)  │ mTLS │  (Custom Domain)  │      └────────┘
                  └─────────────────┘      └──────────────────┘
                          │
                  Presents client cert
                  from Cloudflare CA
```

**Security Flow:**
1. Client requests hit Cloudflare first (WAF rules apply)
2. Cloudflare connects to your API Gateway origin
3. Cloudflare presents its client certificate
4. API Gateway validates cert against Cloudflare's CA
5. Invalid/missing certs are rejected at TLS layer

## Prerequisites

- **AWS Account** with CLI configured
- **Cloudflare Account** with domain
- **Terraform** >= 1.0
- **Cloudflare API Token** with DNS and SSL permissions
- **Cloudflare Zone ID** for your domain

## Quick Start

### 1. Get Cloudflare Credentials

**Get Zone ID:**
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. Copy **Zone ID** from the Overview page (right sidebar)

**Get API Token:**
1. Go to [API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create Token → Use "Edit zone DNS" template
3. Add permissions: `DNS (Edit)` + `SSL and Certificates (Edit)`
4. Select your specific zone
5. Copy the token (save it securely!)

### 2. Run Setup Script

```bash
./setup.sh
```

The script will:
- Prompt for your domain name
- Prompt for Cloudflare Zone ID and API token
- Download Cloudflare Origin CA certificate
- Deploy AWS infrastructure (API Gateway, Lambda, S3, ACM)
- **Automatically wait for ACM certificate validation** (5-30 minutes)
- Create API Gateway custom domain with mTLS
- Configure Cloudflare DNS records and Authenticated Origin Pulls

**Note:** The script runs a single `terraform apply` that waits for certificate validation automatically. No manual steps required!

### 3. Test

```bash
# Through Cloudflare proxy with mTLS (should SUCCEED)
curl https://api-origin.yourdomain.com/health
# Expected: {"message":"Hello from mTLS-protected API!","timestamp":"..."}

# Direct access to origin (should FAIL - endpoint disabled)
curl https://d-xxxx.execute-api.region.amazonaws.com/health
# Expected: {"message":"Not Found"} with 404 status
# Note: Default endpoint is disabled, returns 404 for all routes
```

## File Structure

```
mtls-cloudflare-apigateway-setup/
├── setup.sh                  # Automated deployment script
├── README.md                 # This file
├── proof-of-concept.md       # POC evaluation and decision criteria
├── certs/
│   └── cloudflare-origin-pull-ca.pem  # Downloaded by setup
└── terraform/
    ├── main.tf               # AWS infrastructure
    ├── cloudflare.tf         # Cloudflare configuration
    └── terraform.tfvars      # Your config
```

## AWS Resources Created

| Resource | Purpose |
|----------|---------|
| HTTP API Gateway | Main API with custom domain |
| API Gateway Custom Domain | mTLS-enabled endpoint |
| Lambda Function | Simple test handler |
| S3 Bucket | Stores Cloudflare CA for truststore |
| ACM Certificate | TLS cert for custom domain |
| IAM Role | Lambda execution role |

**Cloudflare Resources:**
| Resource | Purpose |
|----------|---------|
| DNS Records | ACM validation + API origin CNAME |
| Authenticated Origin Pulls | Enabled via Terraform |

## Cost Estimate (Free Tier)

| Service | Free Tier | Your Usage |
|---------|-----------|------------|
| API Gateway | 1M requests/month | ✅ Covered |
| Lambda | 1M requests + 400K GB-s | ✅ Covered |
| S3 | 5GB storage | ✅ Covered (< 10KB) |
| ACM | Free | ✅ Free |
| Cloudflare | Free plan available | ✅ Basic features free |

**Total: $0/month** within free tier limits

## Troubleshooting

### Default endpoint returns 404
✅ **Expected!** The default API Gateway endpoint is disabled (`disable_execute_api_endpoint = true`). All traffic must go through the custom domain with mTLS.

### API Gateway returns 403 on custom domain
- Check the truststore S3 bucket has the correct certificate
- Verify S3 bucket versioning is enabled
- Check API Gateway custom domain mTLS configuration
- Ensure Cloudflare Authenticated Origin Pulls is enabled

### Cloudflare returns 526 (Invalid SSL certificate)
- Ensure SSL mode is "Full (strict)"
- Verify Authenticated Origin Pulls is enabled
- Check the custom domain certificate is valid in ACM

### DNS not resolving
- Wait for DNS propagation (usually 5-10 minutes)
- Run: `terraform state list | grep cloudflare_record` to verify DNS records exist
- Check Cloudflare DNS record is proxied (orange cloud ON) in dashboard

## Teardown

To destroy all resources:

```bash
./teardown.sh
```

This will remove:
- All AWS resources (API Gateway, Lambda, S3, ACM, IAM)
- All Cloudflare resources (DNS records, Authenticated Origin Pulls)

## Security Notes

1. **Keep your origin domain obscure** - Don't use obvious names like `api.example.com`
2. **Enable Cloudflare WAF rules** - The free tier includes basic protection
3. **Set up billing alerts** - Even with free tier, monitor for unexpected usage
4. **Rotate credentials** - If your origin domain leaks, you can change it

## Documentation

- **`proof-of-concept.md`** - Evaluation of mTLS approach vs alternatives

## References

- [AWS HTTP API mTLS](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-mutual-tls.html)
- [Cloudflare Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/)
- [Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Cloudflare Terraform Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
