resource "aws_ssm_parameter" "SigningPrivateKeyRef" {
  name     = "${var.project_prefix}-signing-key-ref"
  type     = "String"
  value    = "/aws/reference/secretsmanager/${aws_secretsmanager_secret.SigningPrivateKey.name}"
  tier     = "Standard"
  provider = aws.us-east-1
}

resource "aws_ssm_parameter" "CloudFrontKeypairId" {
  name     = "${var.project_prefix}-cloudfront-keypair-id"
  type     = "String"
  value    = aws_cloudfront_public_key.VerifySigningPublicKey.id
  provider = aws.us-east-1
  tier     = "Standard"
  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "CloudFrontDomain" {
  name     = "${var.project_prefix}-cloudfront-domain"
  type     = "String"
  value    = aws_cloudfront_distribution.ImageDistribution.domain_name
  tier     = "Standard"
  provider = aws.us-east-1
}

resource "aws_ssm_parameter" "Region" {
  name     = "${var.project_prefix}-region"
  type     = "String"
  value    = var.aws_region
  tier     = "Standard"
  provider = aws.us-east-1
}

resource "aws_ssm_parameter" "UserPoolId" {
  name     = "${var.project_prefix}-user-pool-id"
  type     = "String"
  value    = aws_cognito_user_pool.user_pool.id
  tier     = "Standard"
  provider = aws.us-east-1
}

resource "aws_ssm_parameter" "ClientId" {
  name     = "${var.project_prefix}-client-id"
  type     = "String"
  value    = aws_cognito_user_pool_client.client.id
  tier     = "Standard"
  provider = aws.us-east-1
}

resource "aws_ssm_parameter" "CookieExpirationTimeInMinuits" {
  name     = "${var.project_prefix}-expiration-time-in-minuits"
  type     = "String"
  value    = "15"
  tier     = "Standard"
  provider = aws.us-east-1
}