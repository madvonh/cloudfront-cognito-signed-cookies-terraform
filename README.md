# cloudfront-cognito-signed-cookies-terraform

This repository contains a solution for creating an AWS CloudFront distribution with S3, secured with Cognito signed cookies, using Terraform.

The implementation details and usage instructions are provided in the following blog post:

[https://medium.com/webstep/use-terraform-to-create-an-aws-cloudfront-distribution-from-s3-secured-with-cognito-signed-cookie-26cdfddb306c] (https://medium.com/webstep/use-terraform-to-create-an-aws-cloudfront-distribution-from-s3-secured-with-cognito-signed-cookie-26cdfddb306c)


## Get Started with Terraform

To use this solution, follow these steps:

1. Install Terraform on your machine. You can find installation instructions for your specific operating system by visiting: 
[https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli] (https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
2. Create an IAM user in AWS with the credential type "Access key - Programmatic access" and attach the Administrator policy to it. Save the Access Key and Secret Key generated for this user.
3. Configure the AWS CLI on your local system by running the command `aws configure` in the command prompt. Provide the access and secret keys, default region, and output format. Terraform will use these credentials to connect to the AWS API.

## Build Lambda Function for Cookie Request

The lambda function "edge-cache-request-signer" uses packages that need to be downloaded before deploying this Terraform project.

To do this, make sure you have npm and Node.js installed. Then open a terminal window in the folder "edge-cache-request-signer/deploy" and run the following command. Once done, you should have a "node_modules" folder in the current directory.

```bash
npm install
```

When Terraform executes, it will upload all the contents of the deploy folder. During this process, it will replace the index.js file.

This is done to inject the "var.project_prefix" as the prefix for the SSM parameters. This allows having separate dev, stage, and prod SSM parameters in the same AWS account. So the source file for "index.js" is not in the "deploy" folder. The source "index.js" file is one level up in the "edge-cache-request-signer" directory. The one in the "deploy" folder will be replaced with the Terraform code below.

```code
resource "local_file" "changed_index_file" {
  content  = templatefile("${path.module}/edge-cache-request-signer/index.js", {
      ssm_prefix = var.project_prefix,
  })
  filename = "${path.module}/edge-cache-request-signer/deploy/index.js"
}
```
## Deploy Solution

The command to deploy with Terraform is:
```code
terraform apply
```
To preview the changes before deploying, you can use the plan command:
```code
terraform plan
```

If this Terraform solution is deployed multiple times and the lambda function "EdgeOriginRequestSigner" is modified, please note that a new version of the lambda function will be created. This behavior is due to the "publish = true" parameter, which is necessary for the CloudFront reference.

If changes were made to the function and you want to deploy a new version, ensure that "publish = true" is included. However, if you don't want a new version to be deployed, you can comment out or remove the "publish = true" line.

## Security Setup for Image Request

The viewer access to cached images is restricted by the CloudFront authorization type called Trusted Key Group. This configuration ensures that only HTTP requests with correctly signed cookies are passed through. At least one key needs to be added to CloudFront for authentication purposes. The key added to the Trusted Key Group should contain a public key from an RSA key pair.

The private key from the RSA key pair is used to sign the cookie. In this setup, the private key is securely stored in Secrets Manager since it requires protection. It is retrieved from Secrets Manager via Systems Manager Parameter Store by the lambda function "edge-cache-request-signer", which creates the cookie. This lambda function only allows users with a valid access token issued by the correct Cognito client to retrieve a cookie.

## Token Validation and Signed Cookie

When a user is signed in to a frontend application, the application sends a request to obtain the cookie needed for image view authorization. The specific endpoint set up in CloudFront for this purpose is:
"https://xxxxxxx.cloudfront.net/cookie/"

The lambda function "edge-cache-request-signer" executes on this request and validates the user's bearer token provided in the Authorization header. In CloudFront, a Lambda@Edge function is configured to execute on Viewer Request, as shown in the example below:

```code
ordered_cache_behavior {
  allowed_methods = ["HEAD", "GET","OPTIONS"]
  cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  cached_methods  = ["HEAD", "GET"]
  compress        = "true"
  default_ttl     = "0"
  path_pattern    = "cookie/*"

  lambda_function_association {
    event_type   = "viewer-request"
    include_body = "false"
    lambda_arn   = "${aws_lambda_function.EdgeCacheRequestSigner.arn}:${aws_lambda_function.EdgeCacheRequestSigner.version}"
  }

  max_ttl                = "0"
  min_ttl                = "0"
  smooth_streaming       = "false"
  target_origin_id       = "www.google.com"
  viewer_protocol_policy = "redirect-to-https"
}
```

The origin itself for this could be anything (e.g. a public website like "www.google.com"). This origin will never be hit because it has a behavior attached to it to execute on viewer request. The path "cookie/*" is configured so that any request to this path will execute the Lambda@Edge before it is forwarded to the origin. The lambda will shortcut the request and always return a response to the user.

The response from the lambda "edge-cache-request-signer" will either be the signed cookie, expiring the present signed cookie, or an error explaining what went wrong. The user's token will be examined and verified in Cognito. Since the Lambda@Edge cannot have any environment variables, Systems Manager Parameter Store is used. Also, the private key is retrieved from there since it is integrated with Secrets Manager. The cookie set by the lambda will work cross-domains and expire according to the configured value of "xxx-expiration-time-in-minutes".

## Handling the Expiration of the Cookie

When the cookie expires, the frontend application needs to request a new one. One way to do this is to set the same expiration time for the cookie as for the token. Then, we can listen for the token refresh event and make a new request for the cookie when the event is fired.

## Key Rotation

To keep the solution safe, we need to rotate the keys regularly. Since the RSA key pair resides both in Secrets Manager (private) and in CloudFront (public), we have some custom code to do it. Secrets Manager has the ability to execute a lambda according to a configured scheme. The Terraform for this is:

```code
resource "aws_secretsmanager_secret_rotation" "RsaKeypairRotation" {
  secret_id           = aws_secretsmanager_secret.SigningPrivateKey.id
  rotation_lambda_arn = aws_lambda_function.KeyRotator.arn
  provider            = aws.us-east-1

  rotation_rules {
    automatically_after_days = var.automatically_after_days
  }
}
```

The lambda performing the operations is "key-rotator". This is what it does:
1. Creates a new RSA key pair.
2. Identifies the oldest public key associated with this solution in CloudFront (if there are two keys).
3. Disassociates the old key (if any) from the Trusted Key Group.
4. Deletes the old key (if any).
5. Creates a new CloudFront key with a predefined name but a new ID. It contains the public key of the RSA key pair created in step 1.
6. Associates the new CloudFront key with the Trusted Key Group, along with the newest key from step 2 (or the only existing key, if any). This ensures that newly created cookies remain valid for the remainder of their lifetime.
7. Updates the secret in Secrets Manager with the private key of the new RSA key pair.
8. Updates the parameter "xxx-cloudfront-keypair-id" in SSM Parameter Store with the ID of the newly created CloudFront public key. This parameter is used by the lambda function "edge-cache-request-signer" to create the signed cookie.

In addition to these operations, the necessary roles and policies are set up in this project in the "iam-[...]" files associated with the "key-rotator" lambda function.

## Destroy Solution

To be able to destroy the solution, the lambda@edge "EdgeCacheRequestSigner" connected to CloudFront needs to be disconnected first. The connection is set in the file "cloudfront_distribution.tf" as shown below:

```code
  lambda_function_association {
    event_type   = "viewer-request"
    include_body = "false"
    lambda_arn   = "${aws_lambda_function.EdgeCacheRequestSigner.arn}:${aws_lambda_function.EdgeCacheRequestSigner.version}"
  }
```

Remove the above part and run "Terraform apply". Then you can remove the lambda or the whole solution using terraform destroy. If everything is removed at once, the Terraform apply will fail. For more information about this issue, refer to the following documentation from the Terraform provider:

[https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html] (https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html)