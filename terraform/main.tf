terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "domain_name" {
  description = "Custom domain for API Gateway (e.g., api-origin.yourdomain.com)"
  type        = string
}

variable "cloudflare_ca_cert_path" {
  description = "Path to Cloudflare origin pull CA certificate"
  type        = string
  default     = "../certs/cloudflare-origin-pull-ca.pem"
}

# S3 bucket for mTLS truststore
resource "aws_s3_bucket" "truststore" {
  bucket_prefix = "api-mtls-truststore-"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "truststore" {
  bucket = aws_s3_bucket.truststore.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "truststore" {
  bucket = aws_s3_bucket.truststore.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload Cloudflare CA certificate to S3
resource "aws_s3_object" "cloudflare_ca" {
  bucket = aws_s3_bucket.truststore.id
  key    = "cloudflare-ca.pem"
  source = var.cloudflare_ca_cert_path
  etag   = filemd5(var.cloudflare_ca_cert_path)
}

# ACM Certificate for custom domain (DNS validation)
resource "aws_acm_certificate" "api" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "mtls-api-cert"
  }
}

# Automatic certificate validation (waits for DNS validation to complete)
resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [cloudflare_record.acm_validation.hostname]

  timeouts {
    create = "45m"
  }
}

# HTTP API Gateway
resource "aws_apigatewayv2_api" "main" {
  name                         = "mtls-protected-api"
  protocol_type                = "HTTP"
  description                  = "HTTP API with mTLS protection for Cloudflare origin"
  disable_execute_api_endpoint = true  # Force all traffic through custom domain with mTLS
}

# Lambda function for test endpoint
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<EOF
exports.handler = async (event) => {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      message: "Hello from mTLS-protected API!",
      timestamp: new Date().toISOString(),
      requestId: event.requestContext?.requestId || "unknown",
      path: event.rawPath || "/"
    })
  };
};
EOF
    filename = "index.js"
  }
}

resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "mtls-api-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

resource "aws_iam_role" "lambda" {
  name = "mtls-api-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "hello" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Default stage with auto-deploy
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 100
  }
}

# =============================================================================
# Custom domain with mTLS
# Certificate validation is automatic - Terraform waits for DNS validation
# =============================================================================

resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = var.domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.api.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  mutual_tls_authentication {
    truststore_uri     = "s3://${aws_s3_bucket.truststore.id}/${aws_s3_object.cloudflare_ca.key}"
    truststore_version = aws_s3_object.cloudflare_ca.version_id
  }

  depends_on = [
    aws_s3_object.cloudflare_ca,
    aws_acm_certificate_validation.api
  ]
}

# API mapping to custom domain
resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.main.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.default.id
}

# =============================================================================
# Outputs
# =============================================================================

output "api_endpoint" {
  description = "Default API Gateway endpoint (for testing, bypasses mTLS)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "custom_domain" {
  description = "Custom domain with mTLS enabled"
  value       = "https://${var.domain_name}"
}

output "api_gateway_target_domain" {
  description = "API Gateway domain name - CNAME target for Cloudflare DNS"
  value       = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
}

output "truststore_bucket" {
  description = "S3 bucket containing mTLS truststore"
  value       = aws_s3_bucket.truststore.id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for checking validation status"
  value       = aws_acm_certificate.api.arn
}

# =============================================================================
# ACM DNS Validation Records - ADD THESE TO CLOUDFLARE
# =============================================================================

output "acm_validation_records" {
  description = "DNS records to add in Cloudflare for ACM certificate validation"
  value = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      record_name  = dvo.resource_record_name
      record_type  = dvo.resource_record_type
      record_value = dvo.resource_record_value
    }
  }
}

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
