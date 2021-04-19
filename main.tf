#
# S3 Bucket to store the site content
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket#example-usage
resource "aws_s3_bucket" "site" {
  bucket = "s3-${local.domain_name}"
  acl    = "private"
  tags = {
    site        = local.domain_name
    Environment = local.env_class
  }
}

#
# A user that can push content to the bucket
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user
resource "aws_iam_user" "s3_site" {
  name = "s3_site_iam_user"
  path = "/system/"
}

#
# Produce an access key for the S3 site user
# For example, these credentials can be Output and then used with Github Actions
resource "aws_iam_access_key" "s3_site" {
  user    = aws_iam_user.s3_site.name
}

#
# Attach a policy to the s3_site user, which'll allow it to upload to s3
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy_attachment

resource "aws_iam_user_policy_attachment" "s3_upload_policy_attachment" {
  user       = aws_iam_user.s3_site.name
  policy_arn = aws_iam_policy.s3_upload_policy.arn
}

#
# A "DNS Zone", where you can create records for the site
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone
resource "aws_route53_zone" "site" {
  name = local.domain_name
  tags = {
    site        = local.domain_name
    Environment = local.env_class
  }
}

#
# Setup a DNS entry for www
resource "aws_route53_record" "site" {
  zone_id = aws_route53_zone.site.zone_id
  name    = "www.${local.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = true
  }
}

#
# Setup a DNS entry for queries to the APEX (no www.), just domain.com
# https://engineering.resolvergroup.com/2020/06/how-to-redirect-an-apex-domain-to-www-using-cloudfront-and-s3/
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.site.zone_id
  name    = local.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = true
  }
}

#
# Setup a DNS entry to support a custom domain for auth0
# https://engineering.resolvergroup.com/2020/06/how-to-redirect-an-apex-domain-to-www-using-cloudfront-and-s3/
resource "aws_route53_record" "auth0" {
  count = local.support_auth0
  zone_id = aws_route53_zone.site.zone_id  
  name    = local.auth0_alias
  type    = "CNAME"
  ttl = "300"
  records        = [local.auth0_domain]
}

#
# An identity for the Cloudfront CDN
# Later associated with a policy that can get content from the S3 bucket
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_identity
resource "aws_cloudfront_origin_access_identity" "site_origin" {
  comment = "This allows my cloudfront access to the private S3 bucket"
}

#
# Get a TLS certificate from Amazon for your apex, with the www as a SAN (subject alternative name)
# Uses AWS ACM certificate & validation through DNS for the site
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "site" {
  domain_name               = local.domain_name
  subject_alternative_names = ["www.${local.domain_name}"]
  validation_method         = "DNS"

  tags = {
    site        = local.domain_name
    Environment = local.env_class
  }

  lifecycle {
    create_before_destroy = true
  }
}

#
# Setup up some DNS entries to support the ACM DNS challenge
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
resource "aws_route53_record" "site_certificate_cname" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.site.zone_id
}

#
# Setup a rule to govern TLS cert validation for the site using DNS
resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.site_certificate_cname : record.fqdn]
}

#
# Setup a policy for CloudFront to get s3 site content and relate it to our identity origin from earlier
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.site_origin.iam_arn]
    }
  }
}

# 
# Relate the S3 bucket to the aforementioned policy needed for Cloudfront to get content
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

#
# Setup a policy for to sync content to S3 via aws-cli sync
# https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazons3.html#amazons3-actions-as-permissions
# https://aws.amazon.com/premiumsupport/knowledge-center/s3-access-denied-listobjects-sync/
resource "aws_iam_policy" "s3_upload_policy" {
  name        = "s3-upload-policy-again"
  description = "s3 upload policy"

  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:DeleteObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:GetBucketLocation"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.site.arn}",
        "${aws_s3_bucket.site.arn}/*"
      ]
    }
  ]
}
EOT
}

#
# Setup a Cloundfront CDN, which'll serve content from the S3 bucket
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
resource "aws_cloudfront_distribution" "site" {
  origin {
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.site.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.site_origin.cloudfront_access_identity_path
    }
  }

  # Redirect to our SPA
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  # Redirect to our SPA
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  enabled         = true
  is_ipv6_enabled = true
  default_root_object = "index.html"

  aliases = [local.domain_name, "www.${local.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # You can use this PriceClass if you with to host in US, Mexico, Canada, Europe, Israel.
  # Otherwise you have to use another priceclass
  # https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_DistributionConfig.html
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html
  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      # I am currently targeting North America
      locations        = ["US", "CA"]
    }
  }

  tags = {
    site        = local.domain_name
    Environment = local.env_class
  }

  # tie the CDN to our site's TLS certificate
  viewer_certificate {
    # Use the custom certificate (above) because we have a custom domain
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.site.arn
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method       = "sni-only"
  }
}
