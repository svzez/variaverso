terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.23.0"
    }
  }
  backend "s3" {
    bucket         = "svzez-state-files"
    key            = "variaverso/svzez-com.tfstate"
    region         = "ca-central-1"
    encrypt        = true
  }
}

data "aws_s3_bucket" "svzez_com" {
  bucket = "svzez.com"
}

data "aws_s3_object" "index_html" {
  bucket = data.aws_s3_bucket.svzez_com.id
  key    = "index.html"
}

output "s3_test" {
  description = "The raw content of the S3 object."
  value       = data.aws_s3_object.index_html.body
}