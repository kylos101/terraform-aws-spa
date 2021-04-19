output "s3_site_rw_access_key" {
  value = aws_iam_access_key.s3_site.id
}

output "s3_site_rw_secret_access_key" {
  value = aws_iam_access_key.s3_site.secret
}
