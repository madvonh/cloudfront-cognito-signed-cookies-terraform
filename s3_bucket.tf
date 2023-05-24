resource "aws_s3_bucket" "photo_bucket" {
  bucket = "${var.project_prefix}-photos"

  tags = (merge(
    tomap({ "Application" = "${var.project_prefix}" }),
    tomap({ "Managed" = "Terraform" })
  ))
}

resource "aws_s3_bucket_acl" "photo_bucket_acl" {
  bucket = aws_s3_bucket.photo_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "authenticated_access" {
  bucket = aws_s3_bucket.photo_bucket.id
  policy = data.aws_iam_policy_document.authenticated_access.json
}

data "aws_iam_policy_document" "authenticated_access" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.authenticated.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.photo_bucket.arn,
      "${aws_s3_bucket.photo_bucket.arn}/*",
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.photo_bucket.arn,
      "${aws_s3_bucket.photo_bucket.arn}/*",
    ]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
}

resource "aws_s3_bucket_cors_configuration" "photo_bucket_cors" {
  bucket = aws_s3_bucket.photo_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_origins = ["*"]
    allowed_methods = ["HEAD", "GET", "PUT", "POST", "DELETE"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}