/* TODO: roles for public and private instances
*/

terraform {
  required_version = "~> 0.11"
  backend "s3" {
    bucket         = "terraform-aws-init-bucket"
    key            = "cloudform/terraform.tfstate"
    dynamodb_table = "TerraformLockTable"
    region         = "eu-west-3"
    profile        = "my_admin"
  }
}

provider "aws" {
  # Paris
  region  = local.region
  profile = "my_admin"
}

locals {
  proj   = "cloudform"
  region = "eu-west-3"

  # Amazon Linux
  default_ami           = "ami-4f55e332"
  default_instance_type = "t2.nano"
  default_public_key    = join(".", [local.proj, "pub"]) // will return "key_name.pub"
  tags = {
    Name = local.proj
  }
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  tags       = local.tags
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags   = local.tags
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
  tags   = local.tags

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id
  tags   = local.tags

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_eip" "nat_eip" {
  tags = local.tags
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.default]
  tags          = local.tags
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_route_table_association" "private" {
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private.id
}

resource "aws_subnet" "public" {
  cidr_block              = "10.0.1.0/24"
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
  tags                    = local.tags
}

resource "aws_subnet" "private" {
  cidr_block = "10.0.2.0/24"
  vpc_id     = aws_vpc.default.id
  tags       = local.tags
}

resource "aws_key_pair" "default" {
  key_name   = local.proj
  public_key = file(join("/", [pathexpand("~/.ssh"), local.default_public_key]))
}

resource "aws_security_group" "default" {
  vpc_id = aws_vpc.default.id
  tags   = local.tags

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "public" {
  ami             = local.default_ami
  instance_type   = local.default_instance_type
  subnet_id       = aws_subnet.public.id
  key_name        = aws_key_pair.default.key_name
  security_groups = [aws_security_group.default.id]
  tags            = local.tags
}

resource "aws_instance" "private" {
  ami             = local.default_ami
  instance_type   = local.default_instance_type
  subnet_id       = aws_subnet.private.id
  key_name        = aws_key_pair.default.key_name
  security_groups = [aws_security_group.default.id]
  tags            = local.tags
}

resource "aws_s3_bucket" "private_bucket" {
  bucket = "cloud-private-bucket"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.default.id
  service_name    = "com.amazonaws.${local.region}.s3"
  route_table_ids = [aws_route_table.private.id]
  policy          = <<EOF
{
  "Statement": [
    {
      "Sid": "Access-to-private-bucket-only",
      "Principal": "*",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": ["${aws_s3_bucket.private_bucket.arn}",
                   "${aws_s3_bucket.private_bucket.arn}/*"]
    }
  ]
}
EOF

}
