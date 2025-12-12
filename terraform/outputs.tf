# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_endpoint" {
  description = "Default API Gateway endpoint (disabled - returns 404)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "custom_domain" {
  description = "Custom domain with mTLS enabled - use this endpoint"
  value       = "https://${var.domain_name}"
}

output "api_gateway_target_domain" {
  description = "API Gateway domain name - CNAME target for Cloudflare DNS"
  value       = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
}

# =============================================================================
# Security & Certificate Outputs
# =============================================================================

output "truststore_bucket" {
  description = "S3 bucket containing mTLS truststore"
  value       = aws_s3_bucket.truststore.id
}

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
    ✓ API Gateway custom domain created with mTLS
    ✓ Cloudflare DNS records configured
    ✓ Authenticated Origin Pulls enabled

    NEXT STEPS:

    1. VERIFY SSL MODE (one-time check):
       Go to: Cloudflare Dashboard > SSL/TLS > Overview
       Ensure encryption mode is set to "Full (strict)"

    2. WAIT FOR DNS PROPAGATION (2-5 minutes):
       DNS records were just created and may need time to propagate.
       If curl fails, flush your local DNS cache:

       macOS: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
       Linux: sudo systemd-resolve --flush-caches

    3. TEST YOUR API:
       curl https://${var.domain_name}/health

    4. VERIFY MTLS PROTECTION:
       Direct access should be blocked:
       curl https://${aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name}/health
       (Should fail with "Connection reset by peer")

    ============================================================================
  EOT
}
