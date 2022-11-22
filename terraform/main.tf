terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.40.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

variable "service_name" {
  type    = string
  default = "sethetter-social-uploads"
}

variable "domain_name" {
  type    = string
  default = "cdn.sethetter.social"
}

resource "aws_s3_bucket" "uploads" {
  bucket = var.service_name
}

resource "aws_s3_bucket_acl" "uploads_acl" {
  bucket = aws_s3_bucket.uploads.id
  acl    = "public-read"
}

resource "aws_s3_bucket_cors_configuration" "uploads_cors" {
  bucket = aws_s3_bucket.uploads.id

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
  }
}

resource "aws_s3_bucket_policy" "uploads_public_read_policy" {
  bucket = aws_s3_bucket.uploads.id
  policy = data.aws_iam_policy_document.s3_public_read.json
}

data "aws_iam_policy_document" "s3_public_read" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:GetObject", "s3:ListBucket"]

    resources = [
      aws_s3_bucket.uploads.arn,
      "${aws_s3_bucket.uploads.arn}/*",
    ]
  }
}

resource "aws_iam_user" "main" {
  name = var.service_name
}

resource "aws_iam_user_policy" "main_s3" {
  name   = "${var.service_name}-s3"
  user   = aws_iam_user.main.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["s3:*"],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uploads.arn}",
        "${aws_s3_bucket.uploads.arn}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}


locals {
  s3_origin_id = "sethetter-social-uploads-origin"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {}

resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name = aws_s3_bucket.uploads.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  depends_on = [
    aws_acm_certificate.cert
  ]

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # TODO: set up a logging bucket?
  # logging_config {
  #   include_cookies = false
  #   bucket          = aws_s3_bucket.logs.bucket_domain_name
  #   prefix          = ""
  # }

  aliases = [var.domain_name]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    compress               = true
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_200"

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }
}

output "acm_dns_validation" {
  value = aws_acm_certificate.cert.domain_validation_options
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "username" {
  value = aws_iam_user.main.name
}

output "bucket_endpoint" {
  value = aws_s3_bucket.uploads.bucket_domain_name
}
