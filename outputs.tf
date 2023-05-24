data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "caller_user" {
  value = data.aws_caller_identity.current.user_id
}

output "aws_cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.identity_pool.id
}

output "aws_cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "aws_cognito_user_pool_Client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "aws_cloudfront_distribution_ImageDistribution_domain_name" {
  value = aws_cloudfront_distribution.ImageDistribution.domain_name
}