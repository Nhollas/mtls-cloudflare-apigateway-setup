# Securing AWS HTTP API Gateway with Cloudflare mTLS - Proof of Concept

## Table of Contents

- [Summary](#summary)
- [Glossary](#glossary)
- [Problem Statement](#problem-statement)
- [Security Requirements](#security-requirements)
- [Solutions Evaluated](#solutions-evaluated)
  - [1. IP Whitelisting](#1-ip-whitelisting)
  - [2. API Key Authentication](#2-api-key-authentication)
  - [3. Lambda Authorizer](#3-lambda-authorizer)
  - [4. AWS WAF](#4-aws-waf)
  - [5. Mutual TLS (mTLS) - Tested Solution](#5-mutual-tls-mtls---tested-solution)
- [Implementation Details](#implementation-details)
  - [Architecture Overview](#architecture-overview)
  - [Key Components](#key-components)
  - [Infrastructure as Code](#infrastructure-as-code)
- [POC Results](#poc-results)
- [Trade-offs & Limitations](#trade-offs--limitations)
- [Conclusion](#conclusion)
- [References & Tools](#references--tools)

## Summary

**Objective**: Evaluate approaches to secure AWS HTTP API Gateway to only accept traffic from Cloudflare, preventing origin bypass attacks without adding latency or per-request costs.

**Approach Tested**: Mutual TLS (mTLS) with Cloudflare Authenticated Origin Pulls

**POC Results**:

- Authentication occurs during TLS handshake (no added latency)
- No per-request AWS costs incurred
- Invalid requests rejected before Lambda invocation (attackers cannot trigger compute)
- No application code changes required

**Alternatives Evaluated**:

- IP Whitelisting: No cryptographic authentication
- API Key/Lambda Authorizer: Adds latency, attackers can trigger compute costs
- AWS WAF: Not supported for HTTP API Gateway

**Testing**: Default API Gateway endpoint disabled (returns 404). Cloudflare-proxied requests with mTLS successful.

**Key Limitation**: Coupled to Cloudflare's certificate authority (switching CDNs requires updating truststore with new CA certificates).

**Status**: POC successful - awaiting decision on production implementation.

## Glossary

- **ACM (AWS Certificate Manager)**: AWS service for provisioning and managing SSL/TLS certificates
- **CDN (Content Delivery Network)**: Distributed network of servers that cache and deliver content from locations closer to end users
- **mTLS (Mutual TLS)**: Extension of TLS where both client and server authenticate each other using certificates
- **PKI (Public Key Infrastructure)**: Framework for managing digital certificates and public-key encryption
- **TLS (Transport Layer Security)**: Cryptographic protocol for securing network communications
- **Truststore**: Repository of trusted certificates used to validate incoming client certificates
- **WAF (Web Application Firewall)**: Security system that filters and monitors HTTP traffic to protect web applications

## Problem Statement

When deploying APIs on AWS API Gateway behind Cloudflare's CDN and WAF, a critical security gap exists: **anyone can bypass Cloudflare by directly accessing the API Gateway endpoint**.

This creates several risks:

1. **WAF Bypass**: Attackers can circumvent Cloudflare's Web Application Firewall rules and DDoS protection by hitting the origin directly
2. **Rate Limit Evasion**: Cloudflare rate limiting becomes ineffective if attackers discover the origin endpoint
3. **Visibility Loss**: Direct traffic bypasses Cloudflare's analytics and security monitoring
4. **Attack Surface**: The public API Gateway endpoint becomes a direct attack vector

**Goal**: Ensure **all** traffic to API Gateway must flow through Cloudflare, while maintaining low latency and avoiding operational overhead.

## Security Requirements

1. **Origin Protection**: API Gateway should only accept requests from Cloudflare
2. **Minimal Latency Overhead**: Authentication should not add measurable latency to the request path
3. **No Application Changes**: Solution should work at the infrastructure layer without modifying application code
4. **Cost Effective**: Minimal or no additional AWS costs
5. **Easy Maintenance**: Certificates and credentials should not require frequent rotation

## Solutions Evaluated

### 1. IP Whitelisting

**Approach**: Restrict API Gateway to only accept traffic from Cloudflare's IP ranges.

**Pros**:

- Simple to implement
- No latency overhead
- No additional costs

**Cons**:

- ❌ **IP ranges can change** - Cloudflare publishes IP ranges that may be updated over time, requiring monitoring
- ❌ **No cryptographic authentication** - relies on network-level filtering only
- ❌ **Not officially recommended** by Cloudflare for origin security (per their documentation)

**Verdict**: ❌ Rejected - Requires ongoing IP range monitoring without cryptographic verification

### 2. API Key Authentication

**Approach**: Use AWS API Gateway API keys with Cloudflare workers forwarding a secret header.

**Pros**:

- Simple to implement
- Works at application layer

**Cons**:

- ❌ **Secret management complexity** - API keys must be stored in Cloudflare and AWS
- ❌ **Rotation overhead** - requires coordination between Cloudflare and AWS when rotating keys
- ❌ **Header inspection required** - API Gateway must validate headers on every request
- ❌ **Potential for leakage** - API keys could be exposed in logs or configuration

**Verdict**: ⚠️ Workable but adds operational complexity

### 3. AWS Lambda Authorizer

**Approach**: Use a Lambda authorizer to validate a secret header or token from Cloudflare.

**Pros**:

- Flexible validation logic
- Works at infrastructure layer

**Cons**:

- ❌ **Compute costs on every request** - Lambda authorizer invoked for all requests (AWS charges per invocation)
- ❌ **Attackers still trigger compute** - Invalid requests invoke the authorizer Lambda before rejection
- ❌ **Latency overhead** - Lambda authorizer execution time adds to request path
- ❌ **Secret management** - Requires storing and rotating secrets
- ❌ **Headers can be guessed** - Not cryptographically secure

**Verdict**: ❌ Rejected - Attackers can cause compute costs even with invalid requests

### 4. AWS WAF

**Approach**: Use AWS WAF on API Gateway with custom rules to verify Cloudflare headers.

**Pros**:

- Would work at infrastructure layer

**Cons**:

- ❌ **Not supported for HTTP API Gateway** - AWS WAF only works with REST API Gateway (v1), not HTTP APIs (v2)
- ❌ **Would require downgrading** - REST APIs have higher costs and worse performance than HTTP APIs

**Verdict**: ❌ Not applicable - Incompatible with HTTP API Gateway

### 5. Mutual TLS (mTLS) - Tested Solution

**Approach**: Configure API Gateway to require client certificate authentication, trusting only Cloudflare's Origin CA certificate.

**Pros**:

- ✅ **Cryptographic authentication** - Only Cloudflare can present valid client certificates
- ✅ **No additional latency** - Authentication occurs during TLS handshake (part of standard HTTPS connection establishment)
- ✅ **No application changes** - Implemented entirely at infrastructure layer
- ✅ **No ongoing costs** - Built into API Gateway, no per-request charges
- ✅ **Low maintenance** - Cloudflare's Origin CA certificate valid for 15 years (no rotation required during that period)
- ✅ **Automatic rejection** - Invalid requests fail at TLS layer before reaching application
- ✅ **Zero compute cost for invalid requests** - Attackers cannot trigger Lambda invocations or incur any AWS charges (connection dies at TLS handshake)

**Cons**:

- ⚠️ **Initial setup time** - ACM certificate validation takes 5-30 minutes (automated via Terraform, no manual intervention required)
- ⚠️ **Cloudflare CA dependency** - Truststore contains Cloudflare's Origin CA certificate; switching to another CDN requires updating truststore with that CDN's CA (if they support mTLS origin authentication)
- ⚠️ **Debugging difficulty** - TLS handshake failures can be harder to troubleshoot than application-layer errors
- ⚠️ **All-or-nothing security** - Cannot selectively allow certain IPs or implement gradual rollout without additional infrastructure

**POC Verdict**: ✅ **Tested in POC** - Met requirements for origin authentication without per-request compute costs

## Implementation Details

### Architecture Overview

```
Internet → Cloudflare (presents client cert) → API Gateway (validates cert) → Lambda
```

**Security Flow**:

1. Client makes request to `api-origin.yourdomain.com`
2. Cloudflare proxies the request and establishes mTLS connection to API Gateway
3. Cloudflare presents its client certificate (signed by Cloudflare Origin CA)
4. API Gateway validates the certificate against the trusted CA in S3 truststore
5. If valid: Request forwarded to Lambda
6. If invalid: Connection terminated at TLS layer (before application logic runs)

### Key Components

1. **ACM Certificate**: AWS-managed SSL certificate for the custom domain (validated via DNS)
2. **S3 Truststore**: Contains Cloudflare's Origin CA certificate (`.pem` file)
3. **API Gateway Custom Domain**: Configured with:
   - ACM certificate for TLS
   - mTLS authentication pointing to S3 truststore
4. **Cloudflare Settings**:
   - Authenticated Origin Pulls: ON
   - SSL Mode: Full (strict)
   - DNS: CNAME pointing to API Gateway with proxy enabled

### Infrastructure as Code

The entire setup is defined in Terraform:

**AWS Resources** (`main.tf`):
- **Automatic Certificate Validation**: `aws_acm_certificate_validation` resource waits for ACM validation to complete (5-30 minutes)
- **Default Endpoint Disabled**: `disable_execute_api_endpoint = true` forces all traffic through mTLS-protected custom domain
- **Single-Apply Deployment**: One `terraform apply` creates all resources, waits for validation, and configures everything automatically

**Cloudflare Resources** (`cloudflare.tf`):
- **DNS Records**: ACM validation CNAME and API origin CNAME
- **Authenticated Origin Pulls**: Enabled automatically
- **Managed via Terraform**: Fully automated deployment

**Key Design Decisions**:

- Automatic certificate validation using `aws_acm_certificate_validation` resource (Terraform waits for ACM validation)
- Default API Gateway endpoint disabled (`disable_execute_api_endpoint = true`) to prevent mTLS bypass
- Embedded Lambda code inline for simplicity (proof of concept)
- Cloudflare resources managed via Terraform for full automation

## POC Results

1. **Origin Protection**: Multi-layered protection enforced

   - **Default endpoint disabled**: Direct requests to `https://*.execute-api.*.amazonaws.com` return 404 (`disable_execute_api_endpoint = true`)
   - **mTLS enforced on custom domain**: Only Cloudflare (with valid client certificate) can access `api-origin.yourdomain.com`
   - **Test result**: Requests via `api-origin.yourdomain.com` (Cloudflare proxy) return HTTP 200 with API response
   - Invalid certificates rejected during TLS handshake (before Lambda invocation)

2. **No Additional Latency**: mTLS authentication integrated into TLS handshake

   - No additional network round trips beyond standard HTTPS connection
   - Authentication occurs at transport layer, not application layer

3. **Cost Analysis**: No per-request charges for authentication

   - API Gateway custom domain: Included in standard API Gateway pricing
   - S3 storage for truststore: Standard S3 pricing (certificate file < 10KB)
   - ACM certificate: No charge (AWS-managed certificates are free)

4. **Operational Requirements**:

   - Cloudflare Origin CA certificate: Valid for 15 years from download date
   - Terraform lifecycle protection: Prevents `terraform destroy` from removing ACM cert and S3 bucket
   - DNS records: Configured once during initial setup, no ongoing changes required

5. **Infrastructure Layer**: No application code changes required
   - Works with any backend (Lambda, ALB, NLB, etc.)
   - Transparent to application logic

## Trade-offs & Limitations

1. **CDN Certificate Authority Dependency**: Solution uses Cloudflare's Origin CA certificate in the truststore

   - Switching to a different CDN requires replacing the CA certificate in S3 truststore
   - If the new CDN supports mTLS origin authentication, the architecture remains the same (just swap CA certificates)
   - If the new CDN doesn't support mTLS, would need to switch to alternative authentication (API keys, Lambda authorizers)

2. **Initial Setup Time**: ACM certificate validation requires waiting period

   - Certificate validation takes 5-30 minutes (fully automated via Terraform)
   - Terraform automatically waits for validation to complete before proceeding
   - While automated, initial deployment takes longer than alternatives without certificate validation

3. **Debugging Complexity**: TLS handshake failures provide limited error information

   - "Connection reset by peer" indicates mTLS failure but doesn't explain why
   - Requires understanding of certificate chains and trust stores to troubleshoot
   - Cannot easily test locally without Cloudflare proxy

4. **No Granular Control**: Binary authentication (valid certificate or rejected connection)

   - Cannot implement allowlists for specific IPs or gradual rollout strategies
   - All control must be implemented at application layer after mTLS authentication passes
   - Less flexible than request-based authorization mechanisms

## Conclusion

**This proof of concept evaluated Mutual TLS (mTLS) with Cloudflare Authenticated Origin Pulls** against defined requirements.

**POC Findings:**

**What this approach demonstrated:**

- TLS client certificate authentication (cryptographic verification)
- Invalid requests rejected at TLS handshake (no Lambda invocation costs for attackers)
- No application code changes required
- No per-request AWS charges for authentication

**What this approach requires:**

- CDN that supports mTLS origin authentication (Cloudflare, Fastly, Akamai, etc.)
- Truststore containing the CDN's certificate authority
- Understanding of PKI concepts, ACM, and DNS validation
- TLS-layer debugging for authentication failures
- Application-layer implementation for any additional access control needs

**Evaluation criteria used:**

1. Cloudflare as CDN (no multi-CDN requirement)
2. Latency requirement: No additional authentication overhead
3. Cost requirement: No per-request charges for authentication
4. Security requirement: Prevent unauthorized requests from reaching Lambda

**Why alternative solutions were not tested in POC:**

- IP Whitelisting: No cryptographic authentication, requires IP range monitoring
- API Key/Lambda Authorizer: Adds latency and per-request compute costs, attackers can trigger Lambda invocations
- AWS WAF: Not supported for HTTP API Gateway (only REST API v1)

**POC Outcome**: mTLS successfully met all evaluation criteria in testing. Production deployment decision pending based on organizational requirements and Cloudflare CDN commitment.

## References & Tools

### Documentation

- **[Cloudflare Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/)** - Official guide for mTLS setup
- **[AWS API Gateway mTLS](https://docs.aws.amazon.com/apigateway/latest/developerguide/rest-api-mutual-tls.html)** - AWS documentation on mutual TLS
- **[Cloudflare Origin CA Certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)** - Download location for CA certificate

### Infrastructure

- **[Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)** - Infrastructure as Code
- **[AWS ACM](https://aws.amazon.com/certificate-manager/)** - Certificate management
- **[AWS API Gateway v2 (HTTP APIs)](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)** - Modern API Gateway implementation

### Testing & Verification

- **curl** - Used to verify mTLS protection by testing:
  - Custom domain with mTLS (via Cloudflare) - should succeed
  - Default API Gateway endpoint - should return 404 (endpoint disabled)

### Key Files

- `setup.sh` - Automated deployment script with AWS credential handling
- `terraform/main.tf` - AWS infrastructure definition (API Gateway, Lambda, ACM, S3)
- `terraform/cloudflare.tf` - Cloudflare configuration (DNS, SSL, Authenticated Origin Pulls)
- `certs/cloudflare-origin-pull-ca.pem` - Cloudflare Origin CA certificate
