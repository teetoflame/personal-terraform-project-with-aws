provider "aws" {
  region = "eu-north-1"
}

# Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"
}

# Create Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

# Create Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Associate Public Subnet with Route Table
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Security Group allowing SSH and HTTP access
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# Step 1: Define the IAM Role
resource "aws_iam_role" "cloudwatch_role" {
  name = "ec2-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Step 2: Define the IAM Role Policy
resource "aws_iam_role_policy" "cloudwatch_policy" {
  name   = "cloudwatch-policy"
  role   = aws_iam_role.cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Step 3: Create the IAM Instance Profile
resource "aws_iam_instance_profile" "cloudwatch_instance_profile" {
  name = "ec2-cloudwatch-instance-profile"
  role = aws_iam_role.cloudwatch_role.name
}

# Step 4: Define the EC2 Instance
resource "aws_instance" "web" {
  ami                   = "ami-07c8c1b18ca66bb07"  # Correct AMI ID
  instance_type         = "t3.medium"
  key_name              = "corn-key"
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile  = aws_iam_instance_profile.cloudwatch_instance_profile.name

  tags = {
    Name = "WebServer"
  }
}

# Create S3 Bucket
resource "aws_s3_bucket" "ugo_bucket" {
  bucket = "ugo-bucket"  # Ensure this is globally unique
  
  tags = {
    Name        = "MyS3Bucket"
    Environment = "Dev1"
  }
}

# Separate S3 Bucket Versioning Resource
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.ugo_bucket.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# Create log bucket
resource "aws_s3_bucket" "log_bucket" {
  bucket = "ugo-log-bucket"
  tags = {
    Name = "LogBucket"
  }
}

# Enable logging on the main S3 bucket
resource "aws_s3_bucket_logging" "my_bucket_logging" {
  bucket        = aws_s3_bucket.ugo_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "log/"
}

# Create IAM Policy for S3 Bucket
resource "aws_iam_policy" "s3_bucket_policy" {
  name        = "S3BucketAccessPolicy"
  description = "Policy to allow S3 bucket read/write access"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject"],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.ugo_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.ugo_bucket.bucket}/*"
        ]
      }
    ]
  })
}

# Create IAM User
resource "aws_iam_user" "iam_user" {
  name = "my-iam-user"
}

# Attach IAM Policy to IAM User
resource "aws_iam_user_policy_attachment" "user_policy_attachment" {
  user       = aws_iam_user.iam_user.name
  policy_arn = aws_iam_policy.s3_bucket_policy.arn
}

# Create CloudWatch Metric Alarm for High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "high_cpu_alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  actions_enabled     = true
  alarm_description   = "This metric monitors EC2 CPU utilization"
  dimensions = {
    InstanceId = aws_instance.web.id
  }
}

# Create CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "example" {
  dashboard_name = "ugo-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x    = 0,
        y    = 0,
        width  = 24,
        height = 6,
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web.id],
          ],
          period = 300,
          stat   = "Average",
          region = "eu-north-1",
          title  = "EC2 Instance CPU"
        }
      }
    ]
  })
}

# Outputs
output "vpc_id" {
  value = aws_vpc.main_vpc.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  value = aws_subnet.private_subnet.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.igw.id
}

output "security_group_id" {
  value = aws_security_group.web_sg.id
}

output "ec2_instance_id" {
  value = aws_instance.web.id
}

output "ec2_instance_public_ip" {
  value = aws_instance.web.public_ip
}

terraform {
  backend "s3" {
    bucket         = "teeto-terraform-state-bucket"  # Your S3 bucket name
    key            = "terraform.tfstate"  # The desired path within the bucket
    region         = "eu-north-1"  # Your AWS region
    encrypt        = true  # Encrypt the state file at rest in S3
  }
}
