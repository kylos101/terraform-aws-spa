terraform {
  backend "s3" {
    bucket = "s3-my-cool-state-bucket-name"
    key    = "state"
    region = "us-east-1"
  }
}