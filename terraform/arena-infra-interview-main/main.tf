terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  profile = "infra-test"
}

locals {
  ami           = "ami-09a0dac4253cfa03f" # Amazon Linux 2
  instance_type = "t3.micro"              # free-tier instance type
  bucket_name   = "arena-infra-test-brian-bucket"
}

# Default VPC and subnet are automatically created by AWS
resource "aws_default_vpc" "default" {}
resource "aws_default_subnet" "default_subnet" {
  availability_zone = "us-east-1a"
}

# Create a key pair with the public key file specified
resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh_key"
  public_key = file(var.ssh_public_key_filename)
}

# Setup user data via cloud-init, that will:
# 1. Install Docker, amazon-cloudwatch-agent, and setup the required Docker user groups (one-time)
# 2. Create a `web` directory in the ec2-user home folder, and write a simple index.html file (one-time)
# 3. Start a Docker container with Nginx that mounts the `web` directory from (2) (on every boot)
locals {
  cloud_config = <<-END
	#cloud-config
	${jsonencode({
  write_files = [
    {
      # files in /var/lib/cloud/scripts/per-once/ are executed once
      path        = "/var/lib/cloud/scripts/per-once/initial-setup.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = <<-EOF
					#!/bin/bash
					yum update -y
					yum install -y docker amazon-cloudwatch-agent
					usermod -a -G docker ec2-user
					newgrp docker
					systemctl enable docker.service
					systemctl start docker.service
					mkdir -p /home/ec2-user/web
					echo "Hello World" > /home/ec2-user/web/index.html
				EOF
    },
    {
      # files in /var/lib/cloud/scripts/per-boot/ are executed on every boot
      path        = "/var/lib/cloud/scripts/per-boot/start-nginx.sh"
      permissions = "0755"
      owner       = "root:root"
      content     = <<-EOF
					#!/bin/bash
					/home/ec2-user/refresh-index.sh
					docker pull nginx
					docker run -d -p 80:80 \
						-v /home/ec2-user/web:/usr/share/nginx/html \
						nginx
				EOF
    }
  ]
})}
  END
}

data "cloudinit_config" "server" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content      = local.cloud_config
  }
}

# Create an EC2 instance with the key pair and user data configured above
resource "aws_instance" "server" {
  ami                         = local.ami
  instance_type               = local.instance_type
  key_name                    = aws_key_pair.ssh_key.key_name
  user_data_replace_on_change = false
  subnet_id                   = aws_default_subnet.default_subnet.id
  user_data                   = data.cloudinit_config.server.rendered

  tags = {
    Name = "server"
  }
}
