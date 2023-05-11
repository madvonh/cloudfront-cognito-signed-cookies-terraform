# Cloudfront Cognito Signed Cookies Terraform

## Get started with terraform

You need to setup terraform on your machine and be able to connect and deploy to AWS.

1 Install Terraform. Use this link to find out how on your machine: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli
2 Create an IAM user in AWS with the credential type "Access key - Programmatic access" and attach the Administrator policy to it. Save the Access Key and Secret Key that is created.
3 Configure AWS CLI in your local system by writing "aws configure" in the command prompt. Fill in the access and secret keys, default region and output format. Terraform will use this to connect to the AWS api.

### Security setup for image request

To retreive the images from the origin in a safe way, the request is signed by the "edge-origin-request-signer" lambda function. The request will be passed throught to the bucket by the access points. The "images-exif-transform" lambda will resize the image to the requested size before it is returned to the user and cached.

Viewer access for the cached images are restricted by the CloudFront authorization type Trusted Key Group.
With this configuration only http-requests with correctly signed cookies are passed throught. At least one key needs to be added to CloudFront to be able to authenticate a call. The key added to the Trusted Key Group needs to contain a public key from an RSA key-pair.

The private key from the RSA key-pair is used to sign the cookie. In this setup the private key is saved in Secrets Manager since it needs to be saved in a secure place. It will be retrived from Secrets Manager throught Systems Manager Parameter Store by the lambda "edge-cache-request-signer" that create the cookie. The lambda will only allow users with a valid token issued by the correct Cognito client to retrieve a cookie.

### Token validation and signed cookie

Once a user is signed in to a frontend application, the application makes a request to get the cookie nedded for image view authorization. The specific endpoint set up in Cloudfront for this is:
"https://xxxxxxx.cloudfront.net/cookie/"
The lambda "edge-cache-request-signer" executed on this request validates the users bearer token in the Authorization header. The setup in CloudFront to make this possible to configure a Lambda@Edge to execute on Viewer Request like this:

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
  target_origin_id       = "www.sony.com"
  viewer_protocol_policy = "redirect-to-https"
}
```

The origin itself for this could be anything (eg. a public website like "www.sony.com"). This origin will never be hit because it has a behavior attached to it execute on viewer request. The path "cookie/\*" is configured so that any request to this path will execute the lambda@Edge before it is forwarded to the origin. The lambda will shortcut the request and always return a response to the user.

The response from the lambda "edge-cache-request-signer" will either be with the signed cookie or an error explaining what went wrong. The users token will be examined and verified in Cognito. Since the Lambda@Edge cannot have any environment variables Systems Manager Parameter Store is used. Also the private key is retrieved from there since it is integrated with Secrets Manager. The cookie set by the lambda will work cross domains and expire according to the configured value of "xxx-expiration-time-in-minuits".

### Handling expiration of cookie

When the cookie is expired, the frontend application needs to request for a new. One way to do this is to set the same expiration time for the cookie as for the token. Then we can listen for the token refresh event and make a new request for the cookie when the event is fired.

### Key rotation

To be able to keep the solution safe we need to rotate the keys regulary. Since the RSA key pair resides both in Secrets Manager (private) and in CloudFront (public) we have some custom code to do it. Secrets Manager has the ability to execute a lambda according to a configured scheme. The terrafrom for this is:

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

The lambda performing the operations is "key-rotator". This is what is does:
1 A new RSA key pair is created.
2 Identifies the oldest public key saved in CloudFront that is associated with this solution (if there are 2 keys).
3 The old key (if any) is disassociated from the Trusted Key Group.
4 The old key (if any) is deleted.
5 A new CloudFront key will be created with a predefined name but a new Id. It will contain the public key of RSA key pair created in step 1.
6 The new CloudFront key is associated with the Trusted Key Group together with the newest of the keys from step 2 (or the only existing if any). That key will stay in the keygroup until next rotation. This allows newly created cookie to be valid for the rest of the cookie's lifetime.
7 The secret in Secret Manager is updated with the new RSA key pair private key.
8 The parmeter "xxx-cloudfront-keypair-id" in SSM Parmeter Store is updated with the Id of the newly created CloudFront public key. This parameter is used by the lambda "edge-cache-request-signer" to create the signed cookie.

To be able to do all the operations the role and policys are also set up in this project in the "iam-[...]" files associated with the "key-rotator" lambda.

### Build lambda function for cookie request

The lambda function "edge-cache-request-signer" uses packages that needs to be downloaded before this Terraform project is deployed.

To do this, make sure you have npm and node installed. Then open a terminal window in the folder "edge-cache-request-signer/deploy" and run the command below. When thats done you should have a "node_module" folder in the current directory.

```bash
npm install
```

When Terraform executes, it will take all content in the deploy folder and upload. During this process it will first replace the index.js file.

This is done so that we can inject the "var.project_prefix" as the prefix for the ssm parameters. This way we could have e.g. dev, stage and prod ssm parameter in the same aws account. So the source file for the "index.js" in not in the "depoy" folder. The source "index.js" file is one level up in the "edge-cache-request-signer". The one in "deploy" will be replaced with the Terraform code below.

```code
resource "local_file" "changed_index_file" {
  content  = templatefile("${path.module}/edge-cache-request-signer/index.js", {
      ssm_prefix = var.project_prefix,
  })
  filename = "${path.module}/edge-cache-request-signer/deploy/index.js"
}
```
### Deploy solution

If this terraform solution is deployed more than once, be aware that a new verion for the lambda function "EdgeOriginRequestSigner" will be deployed. This is caused by the parameter:  
"publish = true" which is needed for the CloudFront reference to it.

If changes was made to the function you need to deploy a new version. If not, comment out "publish = true" and no new version will be deployed.

### Destroy lambda

To be able to destroy only the lambda that is connected to the cloudfront we need to disconnect the "EdgeCacheRequestSigner" lambda first. The connection is set in the file: "cloudfront_distribution.tf" like this:

```code
  lambda_function_association {
    event_type   = "viewer-request"
    include_body = "false"
    lambda_arn   = "${aws_lambda_function.EdgeCacheRequestSigner.arn}:${aws_lambda_function.EdgeCacheRequestSigner.version}"
  }
```

Remove the above part first and run "Terraform apply". Then remove the the lambda. If everything is removed in one go the Terraform apply will fail.
If you want to remove the whole solution, use "Terrafrom destroy" instead.