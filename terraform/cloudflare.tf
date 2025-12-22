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
  content = aws_api_gateway_domain_name.api.regional_domain_name
  ttl     = 1 # Auto TTL (Cloudflare manages)
  proxied = true

  depends_on = [aws_api_gateway_domain_name.api]
}

# =============================================================================
# Cloudflare Security Settings
# =============================================================================

# Note: SSL Mode must be set manually in Cloudflare Dashboard
# Go to: SSL/TLS > Overview > Set to "Full (strict)"
# Terraform's zone_settings_override has issues with read-only settings on some plan types
#
# Note: Cloudflare WAF is enabled by default when proxied=true
# Configure additional WAF rules in Cloudflare Dashboard > Security > WAF

# =============================================================================
# IP Allowlist - Restrict to Company IPs (Optional)
# =============================================================================

# Only create the filter if company IPs are specified
resource "cloudflare_filter" "company_ip_allowlist" {
  count = length(var.company_ip_allowlist) > 0 ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  description = "Block non-company IPs from accessing ${var.domain_name}"
  expression  = "(http.host eq \"${var.domain_name}\") and not (ip.src in {${join(" ", var.company_ip_allowlist)}})"
}

resource "cloudflare_firewall_rule" "company_ip_allowlist" {
  count = length(var.company_ip_allowlist) > 0 ? 1 : 0

  zone_id     = var.cloudflare_zone_id
  description = "Only allow API access from company IP addresses"
  filter_id   = cloudflare_filter.company_ip_allowlist[0].id
  action      = "block"
}
