

// this will take the index.js in edge-cache-request-signer folder, replace the parameter: ssm_prefix in the file, 
// create a new file an save if in edge-cache-request-signer/deploy folder. The newly created file is the one that will be deployed.
// This is done since environment variables isn't supported in lambda@edge, adding a prefix like this will enable to deploy dev, 
// test and prod versions in the same aws account if needed. We can just chande the env_name variable. 
resource "local_file" "templated" {
  content = templatefile("${path.module}/edge-cache-request-signer/index.js", {
    ssm_prefix = var.project_prefix,
  })
  filename = "${path.module}/edge-cache-request-signer/deploy/index.js"
}

data "archive_file" "EdgeCacheRequestSignerArchive" {
  depends_on = [
    local_file.templated
  ]
  type        = "zip"
  source_dir  = "${path.module}/edge-cache-request-signer/deploy"
  output_path = "${path.module}/edge-cache-request-signer/deploy/edge-cache-request-signer.zip"
}

resource "aws_lambda_function" "EdgeCacheRequestSigner" {
  architectures                  = ["x86_64"]
  description                    = "Signing requests to cache"
  function_name                  = "edge-cache-request-signer"
  handler                        = "index.handler"
  filename                       = data.archive_file.EdgeCacheRequestSignerArchive.output_path
  memory_size                    = "128" # max size allowed for "viewer-request" event type
  package_type                   = "Zip"
  reserved_concurrent_executions = "-1"
  role                           = aws_iam_role.EdgeCacheRequestSignerFunctionRole.arn
  runtime                        = "nodejs16.x"
  timeout                        = "5"
  provider                       = aws.us-east-1
  # publish will publish a new version of the lambda. Take this away after first publish if code is not changes
  publish          = true
  source_code_hash = data.archive_file.EdgeCacheRequestSignerArchive.output_base64sha256

  tags = (merge(
    tomap({ "Application" = "${var.project_prefix}" }),
    tomap({ "Managed" = "Terraform" })
  ))
}

output "lambda_function_EdgeCacheRequestSigner_version" {
  // Get the version number assigned by AWS
  value = aws_lambda_function.EdgeCacheRequestSigner.version
}

data "archive_file" "KeyRotatorArchive" {
  type        = "zip"
  source_dir  = "${path.module}/key-rotator"
  output_path = "${path.module}/key-rotator/key-rotator.zip"
}

resource "aws_lambda_function" "KeyRotator" {
  architectures    = ["x86_64"]
  description      = "Rotates RSA key for cloudfront"
  filename         = data.archive_file.KeyRotatorArchive.output_path
  function_name    = "${var.project_prefix}-key-rotator"
  role             = aws_iam_role.KeyRotatorLambdaRole.arn
  handler          = "index.handler"
  runtime          = "nodejs16.x"
  memory_size      = "128"
  timeout          = 300
  source_code_hash = data.archive_file.KeyRotatorArchive.output_base64sha256
  provider         = aws.us-east-1
  ephemeral_storage {
    size = "512"
  }
  environment {
    variables = {
      SECRET_NAME  = var.signing_key_name
      REGION       = "us-east-1"
      KEY_GROUP_ID = aws_cloudfront_key_group.VerifySigningKeyGroup.id
      PREFIX       = var.project_prefix
      SSM_PARAM    = aws_ssm_parameter.CloudFrontKeypairId.name
    }
  }
}

resource "aws_lambda_permission" "AllowSecretManagerCallLambda" {
  function_name  = aws_lambda_function.KeyRotator.function_name
  statement_id   = "AllowExecutionSecretManager"
  action         = "lambda:InvokeFunction"
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  provider       = aws.us-east-1
}


 