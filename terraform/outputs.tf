# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_endpoint" {
  description = "REST API Gateway invoke URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "custom_domain" {
  description = "Custom domain with Cloudflare WAF protection - use this endpoint"
  value       = "https://${var.domain_name}"
}

output "api_gateway_target_domain" {
  description = "API Gateway regional domain name - CNAME target for Cloudflare DNS"
  value       = aws_api_gateway_domain_name.api.regional_domain_name
}

# =============================================================================
# Security & Certificate Outputs
# =============================================================================

output "acm_certificate_arn" {
  description = "ACM certificate ARN for checking validation status"
  value       = aws_acm_certificate.api.arn
}

output "acm_validation_records" {
  description = "DNS records for ACM certificate validation (managed by Terraform via Cloudflare)"
  value = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      record_name  = dvo.resource_record_name
      record_type  = dvo.resource_record_type
      record_value = dvo.resource_record_value
    }
  }
}

output "cloudflare_ip_ranges" {
  description = "Cloudflare IP ranges allowed in resource policy"
  value = {
    ipv4 = local.cloudflare_ipv4
    ipv6 = local.cloudflare_ipv6
  }
}

output "company_ip_allowlist" {
  description = "Company IPs allowed at Cloudflare WAF level (empty = all IPs allowed)"
  value       = length(var.company_ip_allowlist) > 0 ? var.company_ip_allowlist : ["All IPs allowed (no restrictions)"]
}

# =============================================================================
# Cloudflare Outputs
# =============================================================================

output "cloudflare_acm_validation_record" {
  description = "Cloudflare DNS record created for ACM validation"
  value = {
    name  = cloudflare_record.acm_validation.hostname
    type  = cloudflare_record.acm_validation.type
    value = cloudflare_record.acm_validation.content
  }
}

output "cloudflare_api_origin_record" {
  description = "Cloudflare DNS record for API origin"
  value = {
    name    = cloudflare_record.api_origin.hostname
    type    = cloudflare_record.api_origin.type
    value   = cloudflare_record.api_origin.content
    proxied = cloudflare_record.api_origin.proxied
  }
}

# =============================================================================
# Deployment Instructions
# =============================================================================

output "next_steps" {
  description = "Instructions for completing setup"
  value       = <<-EOT

    ============================================================================
    DEPLOYMENT COMPLETE
    ============================================================================

    ✓ ACM certificate validated automatically
    ✓ REST API Gateway custom domain created
    ✓ Cloudflare DNS records configured
    ✓ Resource policy restricts access to Cloudflare IPs only

    SECURITY ARCHITECTURE:
    Client → Cloudflare WAF/DDoS → REST API (IP whitelist) → Lambda

    NEXT STEPS:

    1. VERIFY SSL MODE (one-time check):
       Go to: Cloudflare Dashboard > SSL/TLS > Overview
       Ensure encryption mode is set to "Full (strict)"

    2. CONFIGURE CLOUDFLARE WAF (recommended):
       Go to: Cloudflare Dashboard > Security > WAF
       - Enable managed rulesets
       - Set up rate limiting rules
       - Configure bot protection

    3. WAIT FOR DNS PROPAGATION (2-5 minutes):
       DNS records were just created and may need time to propagate.
       If curl fails, flush your local DNS cache:

       macOS: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
       Linux: sudo systemd-resolve --flush-caches

    4. TEST YOUR API:
       curl https://${var.domain_name}/health

    5. VERIFY IP PROTECTION:
       Direct access should be blocked by resource policy:
       curl ${aws_api_gateway_stage.prod.invoke_url}/health
       (Should return 403 Forbidden unless you're on a Cloudflare IP)

    ============================================================================
  EOT
}
