# =============================================================================
# Cloudflare Provider Configuration
# =============================================================================

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# =============================================================================
# Local Variables
# =============================================================================

# Local variables for certificate validation
locals {
  # Use one() to safely extract the single domain validation option
  domain_validation = one(aws_acm_certificate.api.domain_validation_options)
}

# ACM Certificate Validation Record
# This record must be created BEFORE the custom domain can be created
resource "cloudflare_record" "acm_validation" {
  zone_id = var.cloudflare_zone_id
  name    = trim(local.domain_validation.resource_record_name, ".")
  type    = local.domain_validation.resource_record_type
  content = trim(local.domain_validation.resource_record_value, ".")
  ttl     = 60
  proxied = false

  lifecycle {
    create_before_destroy = true
  }
}

# API Origin CNAME Record (points to API Gateway)
resource "cloudflare_record" "api_origin" {
  zone_id = var.cloudflare_zone_id
  name    = split(".", var.domain_name)[0] # Extract subdomain (e.g., "api-origin" from "api-origin.yourdomain.com")
  type    = "CNAME"
  content = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
  ttl     = 1 # Auto TTL (Cloudflare manages)
  proxied = true

  depends_on = [aws_apigatewayv2_domain_name.api]
}

# =============================================================================
# Cloudflare Security Settings
# =============================================================================

# Enable Authenticated Origin Pulls
resource "cloudflare_authenticated_origin_pulls" "api" {
  zone_id = var.cloudflare_zone_id
  enabled = true
}

# Note: SSL Mode must be set manually in Cloudflare Dashboard
# Go to: SSL/TLS > Overview > Set to "Full (strict)"
# Terraform's zone_settings_override has issues with read-only settings on some plan types
