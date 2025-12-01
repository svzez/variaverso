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

resource "aws_s3_bucket" "svzez_com" {
  bucket = "svzez.com"
  region = "ca-central-1"

  tags = {
    Name        = "svzez.com"
    ManagedBy   = "terraform"
    Environment = "production"
  }
}

resource "aws_s3_bucket_website_configuration" "svzez_com" {
  bucket = aws_s3_bucket.svzez_com.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "svzez_com" {
  bucket = aws_s3_bucket.svzez_com.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "svzez_com_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"
    
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.svzez_com.arn}/*"
    ]
  }
}

# 5. Attach the Policy to the Bucket
resource "aws_s3_bucket_policy" "svzez_com" {
  bucket = aws_s3_bucket.svzez_com.id
  policy = data.aws_iam_policy_document.svzez_com_public_read.json
  depends_on = [aws_s3_bucket_public_access_block.svzez_com]
}

# 6. (Optional) Upload a sample index.html
resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.svzez_com.id
  key    = "index.html"
  source = "./index.html"
}

output "website_endpoint" {
  description = "The public URL of the website"
  value       = "http://${aws_s3_bucket_website_configuration.svzez_com.website_endpoint}"
}