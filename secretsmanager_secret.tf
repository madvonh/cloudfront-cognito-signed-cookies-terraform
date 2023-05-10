# Creating a AWS secret for CloudFront keypair private key for signing cookies
resource "aws_secretsmanager_secret" "SigningPrivateKey" {
  name        = var.signing_key_name
  description = "Private key for CloudFront trusted keygroup"
  provider    = aws.us-east-1
}

# Creating a AWS secret versions for CloudFront keypair private key for signing cookies
resource "aws_secretsmanager_secret_version" "SigningPrivateKeyVersion" {
  secret_id     = aws_secretsmanager_secret.SigningPrivateKey.id
  secret_string = var.private_key_pem
  provider      = aws.us-east-1
}

resource "aws_secretsmanager_secret_rotation" "RsaKeypairRotation" {
  secret_id           = aws_secretsmanager_secret.SigningPrivateKey.id
  rotation_lambda_arn = aws_lambda_function.KeyRotator.arn
  provider            = aws.us-east-1

  rotation_rules {
    automatically_after_days = var.automatically_after_days
  }
}