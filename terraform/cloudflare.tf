# Cloudflare Provider Configuration
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Variables
variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS and SSL permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
}

# ACM Certificate Validation Record
# This record must be created BEFORE the custom domain can be created
resource "cloudflare_record" "acm_validation" {
  zone_id = var.cloudflare_zone_id
  name    = trim(tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_name, ".")
  type    = tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_type
  value   = trim(tolist(aws_acm_certificate.api.domain_validation_options)[0].resource_record_value, ".")
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
  value   = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
  ttl     = 1 # Auto TTL (Cloudflare manages)
  proxied = true

  depends_on = [aws_apigatewayv2_domain_name.api]
}

# Enable Authenticated Origin Pulls
resource "cloudflare_authenticated_origin_pulls" "api" {
  zone_id = var.cloudflare_zone_id
  enabled = true
}

# Note: SSL Mode must be set manually in Cloudflare Dashboard
# Go to: SSL/TLS > Overview > Set to "Full (strict)"
# Terraform's zone_settings_override has issues with read-only settings on some plan types

# Outputs
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
