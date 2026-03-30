provider "aws" {
  region = var.aws_region
}
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
data "aws_vpc" "default" {
  default = true
}
data "aws_availability_zones" "all" {}
resource "aws_subnet" "public_a" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"   # adjust to your region
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.cluster_name}-public-a"
  }
}
resource "aws_subnet" "public_b" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"   # adjust to your region
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.cluster_name}-public-b"
  }
}
resource "aws_subnet" "public_c" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = var.public_subnet_c_cidr
  availability_zone       = "${var.aws_region}c"   # adjust to your region
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.cluster_name}-public-c"
  }
}
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}
# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Allow HTTP inbound to ALB"
  ingress {
    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }
  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }
  tags = {
    Name = "${var.cluster_name}-alb-sg"
  }
}
# EC2 Instance Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "${var.cluster_name}-instance-sg"
  description = "Allow traffic from ALB only"
  ingress {
    from_port       = var.server_port
    to_port         = var.server_port
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }
  tags = {
    Name = "${var.cluster_name}-instance-sg"
  }
}
# Launch Template (your Node.js bootstrap included)
resource "aws_launch_template" "app_lt" {
  name_prefix   = "${var.cluster_name}-lt"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name = var.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data = base64encode(
    templatefile("${path.module}/user_data.sh.tpl", {
      cluster_name = var.cluster_name,
      server_port = var.server_port
    })
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-instance"
    }
  }
}
# Application Load Balancer
resource "aws_lb" "app_alb" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id, aws_subnet.public_c.id]

    tags = {
        Name = "${var.cluster_name}-port-alb"
    }
}
# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "${var.cluster_name}-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name = "${var.cluster_name}-lb-tg"
  }
}
# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}
# Auto Scaling Group (Cluster Core)
resource "aws_autoscaling_group" "app_asg" {
  name                = "${var.cluster_name}-asg"
  desired_capacity    = var.min_size
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id, aws_subnet.public_c.id]
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 60
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg-instance"
    propagate_at_launch = true
  }
}



