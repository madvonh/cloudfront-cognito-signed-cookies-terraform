resource "aws_cloudfront_public_key" "VerifySigningPublicKey" {
  encoded_key = var.public_key_pem
  name        = "${var.project_prefix}-DUMMY_KEY"
  # remove below if you have changed the value of the encoded_key 
  lifecycle {
    ignore_changes        = [encoded_key]
    create_before_destroy = true
  }
}

resource "aws_cloudfront_key_group" "VerifySigningKeyGroup" {
  items = [aws_cloudfront_public_key.VerifySigningPublicKey.id]
  name  = "${var.project_prefix}-group"
  lifecycle {
    ignore_changes = [items]
  }
}

resource "aws_cloudfront_distribution" "ImageDistribution" {
  enabled         = "true"
  http_version    = "http2"
  is_ipv6_enabled = "true"

  ordered_cache_behavior {
    allowed_methods = ["HEAD", "GET", "OPTIONS"]
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

    max_ttl          = "0"
    min_ttl          = "0"
    smooth_streaming = "false"
    # Could be any value, since this target never will be hit
    target_origin_id       = "www.google.com"
    viewer_protocol_policy = "redirect-to-https"
  }

  default_cache_behavior {
    allowed_methods    = ["HEAD", "GET"]
    trusted_key_groups = [aws_cloudfront_key_group.VerifySigningKeyGroup.id]
    cached_methods     = ["HEAD", "GET"]
    compress           = "true"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    min_ttl     = "0"
    max_ttl     = "86400"
    default_ttl = "3600"

    smooth_streaming       = "false"
    target_origin_id       = aws_s3_bucket.photo_bucket.bucket_regional_domain_name
    viewer_protocol_policy = "redirect-to-https"
  }

  origin {
    connection_attempts = "1"
    connection_timeout  = "10"

    custom_origin_config {
      http_port                = "80"
      https_port               = "443"
      origin_keepalive_timeout = "5"
      origin_protocol_policy   = "https-only"
      origin_read_timeout      = "30"
      origin_ssl_protocols     = ["TLSv1.2"]
    }

    domain_name = "www.google.com"
    origin_id   = "www.google.com"
  }

  origin {
    connection_attempts = "3"
    connection_timeout  = "10"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
    domain_name = aws_s3_bucket.photo_bucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.photo_bucket.bucket_regional_domain_name
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  retain_on_delete = "false"

  viewer_certificate {
    cloudfront_default_certificate = "true"
    minimum_protocol_version       = "TLSv1"
  }

  tags = (merge(
    tomap({ "Application" = "${var.project_prefix}" }),
    tomap({ "Managed" = "Terraform" })
  ))
}