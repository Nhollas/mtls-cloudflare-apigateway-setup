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

# =============================================================================
# Local Variables - Common Tags
# =============================================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "mtls-cloudflare-apigateway-setup"
  }
}

# =============================================================================
# S3 Resources
# =============================================================================

# S3 bucket for mTLS truststore
resource "aws_s3_bucket" "truststore" {
  bucket_prefix = "api-mtls-truststore-"
  force_destroy = true # Allow easy teardown for POC

  tags = merge(local.common_tags, {
    Name = "mtls-truststore"
  })
}

resource "aws_s3_bucket_versioning" "truststore" {
  bucket = aws_s3_bucket.truststore.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "truststore" {
  bucket = aws_s3_bucket.truststore.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
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

  tags = merge(local.common_tags, {
    Name = "mtls-api-cert"
  })

  lifecycle {
    create_before_destroy = true
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

# =============================================================================
# API Gateway Resources
# =============================================================================

# HTTP API Gateway
resource "aws_apigatewayv2_api" "main" {
  name                         = "mtls-protected-api"
  protocol_type                = "HTTP"
  description                  = "HTTP API with mTLS protection for Cloudflare origin"
  disable_execute_api_endpoint = true # Force all traffic through custom domain with mTLS

  tags = merge(local.common_tags, {
    Name = "mtls-protected-api"
  })
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
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "mtls-api-handler"
  })
}

resource "aws_iam_role" "lambda" {
  name_prefix = "mtls-api-lambda-role-"

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

  tags = merge(local.common_tags, {
    Name = "mtls-api-lambda-role"
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

  tags = merge(local.common_tags, {
    Name = "mtls-api-default-stage"
  })
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
