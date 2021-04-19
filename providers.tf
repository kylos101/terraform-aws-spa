terraform {
  # the version of terraform CLI we require
  required_version = ">= 0.13.0"
  # providers we want to use
  required_providers {
    # do stuff in AWS using hashicorp's aws modules
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    # to get random pet names for resources!
    random = "~> 2"
    null   = "~> 2"
  }
}

# Configure the AWS Provider
# this depends on the access key and secret access key existing in the environment
provider "aws" {
  region = local.region # CloudFront expects ACM resources in us-east-1 region only

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true

  # skip_requesting_account_id should be disabled to generate valid ARN in apigatewayv2_api_execution_arn
  skip_requesting_account_id = false
}