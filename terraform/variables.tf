# =============================================================================
# AWS Configuration Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., eu-west-2, us-east-1)."
  }
}

variable "domain_name" {
  description = "Custom domain for API Gateway (e.g., api-origin.yourdomain.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.domain_name))
    error_message = "Domain name must be a valid DNS name (lowercase alphanumeric and hyphens only)."
  }
}

variable "cloudflare_ca_cert_path" {
  description = "Path to Cloudflare origin pull CA certificate"
  type        = string
  default     = "../certs/cloudflare-origin-pull-ca.pem"

  validation {
    condition     = can(regex("\\.pem$", var.cloudflare_ca_cert_path))
    error_message = "Certificate path must point to a .pem file."
  }
}

# =============================================================================
# Cloudflare Configuration Variables
# =============================================================================

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS and SSL permissions"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.cloudflare_api_token) > 0
    error_message = "Cloudflare API token cannot be empty."
  }
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_zone_id))
    error_message = "Cloudflare Zone ID must be a 32-character hexadecimal string."
  }
}

# =============================================================================
# Project Configuration Variables
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod, poc)"
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["dev", "staging", "prod", "poc"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, poc."
  }
}

variable "project_name" {
  description = "Project name for resource tagging and identification"
  type        = string
  default     = "mtls-api"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}
