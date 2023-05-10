resource "aws_iam_role_policy" "authenticated_policy" {
  name = "Cognito_SignedCookie_Role_Policy"
  role = aws_iam_role.authenticated.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*",
        "cognito-identity:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "unauthenticated_policy" {
  name = "Cognito_SignedCookie_Role_Policy"
  role = aws_iam_role.unauthenticated.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "EdgeCacheRequestSignerFunctionRolePolicy" {
  name   = "${var.project_prefix}-EdgeCacheRequestSignerFunctionRolePolicy"
  policy = <<POLICY
{
  "Statement": [
    {
      "Action": [
        "ssm:GetParameter"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/${var.project_prefix}*",
        "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/aws/reference/secretsmanager/${aws_secretsmanager_secret.SigningPrivateKey.name}"
      ] 
    },
    {
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_secretsmanager_secret.SigningPrivateKey.arn}"
      ]
    }
  ],
  "Version": "2012-10-17"
}
POLICY

  role = aws_iam_role.EdgeCacheRequestSignerFunctionRole.name
}

resource "aws_iam_role_policy" "KeyRotatorLambdaRolePolicy" {
  name = "${var.project_prefix}-KeyRotatorLambdaRolePolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:UpdateSecretVersionStage"
        ],
        Condition = {
          StringEquals = {
            "secretsmanager:resource/AllowRotationLambdaArn" : aws_lambda_function.KeyRotator.arn
          }
        },
        Resource = aws_secretsmanager_secret.SigningPrivateKey.arn,
      },
      {
        Effect = "Allow",
        Action = [
          "cloudfront:CreatePublicKey",
          "cloudfront:GetPublicKey",
          "cloudfront:DeletePublicKey",
          "cloudfront:ListPublicKeys",
          "cloudfront:GetKeyGroup",
          "cloudfront:UpdateKeyGroup",
          "ssm:PutParameter"
        ],
        Resource = "*",
      }
    ]
  })
  role = aws_iam_role.KeyRotatorLambdaRole.name
}
