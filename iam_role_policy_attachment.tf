
resource "aws_cognito_identity_pool_roles_attachment" "roles_attachment" {
  identity_pool_id = aws_cognito_identity_pool.identity_pool.id
  roles = {
    "authenticated"   = aws_iam_role.authenticated.arn
    "unauthenticated" = aws_iam_role.unauthenticated.arn
  }
  /*role_mapping {
    ambiguous_role_resolution = "Deny"
    type                      = "Token"
    identity_provider         = "${aws_cognito_user_pool.user_pool.endpoint}:${aws_cognito_user_pool_client.client.id}"
  }*/
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_AuthenticatedRole" {
  role       = aws_iam_role.authenticated.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
