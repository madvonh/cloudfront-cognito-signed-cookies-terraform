
resource "aws_cognito_identity_pool_roles_attachment" "roles_attachment" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id
  roles = {
    "authenticated"   = aws_iam_role.authenticated.arn
    "unauthenticated" = aws_iam_role.unauthenticated.arn
  }
}
