resource "aws_cognito_identity_pool" "identity_pool" {
  identity_pool_name               = "Signed cookie example"
  allow_unauthenticated_identities = false
  allow_classic_flow               = true

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.client.id
    provider_name           = aws_cognito_user_pool.user_pool.endpoint
    server_side_token_check = false
  }

  tags = (merge(
    tomap({ "Application" = "${var.project_prefix}" }),
    tomap({ "Managed" = "Terraform" })
  ))
}
