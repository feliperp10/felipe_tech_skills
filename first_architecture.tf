# =============================================================================================
# PROJECT: Scalable and Resilient Infrastructure for Enterprise Applications
# PROJETO: Infraestrutura Escalável e Resiliente para Aplicações Corporativas
# 
# DESCRIPTION / DESCRIÇÃO:
# This architecture follows the AWS Well-Architected Framework, focusing on security, 
# high availability (Multi-AZ), and Infrastructure as Code (IaC) with Terraform.
# Esta arquitetura segue o AWS Well-Architected Framework, focando em segurança, 
# alta disponibilidade (Multi-AZ) e Infraestrutura como Código (IaC) com Terraform.
# =============================================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project     = "AWS-Architecture-Challenge"
      Environment = "Production"
      ManagedBy   = "Terraform"
    }
  }
}

# =============================================================================================
# 1. NETWORKING (VPC, Subnets, Gateways)
# Layer separation: Public subnets for ALB/NAT and Private for App/DB.
# Separação de camadas: Subnets públicas para ALB/NAT e privadas para App/DB.
# =============================================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets (High Availability / Alta Disponibilidade)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-${count.index + 1}" }
}

# Private Subnets (Isolated for Security / Isoladas por Segurança)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "private-subnet-${count.index + 1}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
}

# Route Tables (Routing logic / Lógica de roteamento)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================================================
# 2. SECURITY GROUPS & IAM (Governance & Least Privilege)
# Enforcing security through network isolation and custom IAM roles.
# Aplicando segurança através de isolamento de rede e roles IAM customizadas.
# =============================================================================================

resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.main.id
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
}

resource "aws_security_group" "app_sg" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 (Principle of Least Privilege / Princípio do Menor Privilégio)
resource "aws_iam_role" "ec2_role" {
  name = "ec2_app_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "app_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# =============================================================================================
# 3. STORAGE & DATABASE (Persistence & Compliance)
# Using S3 Gateway Endpoints to keep traffic within AWS private network.
# Usando S3 Gateway Endpoints para manter o tráfego na rede privada da AWS.
# =============================================================================================

resource "aws_s3_bucket" "data_bucket" {
  bucket_prefix = "app-data-secure-"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_db_subnet_group" "db_subnet" {
  name       = "db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "rds" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  db_subnet_group_name = aws_db_subnet_group.db_subnet.name
  multi_az             = true # Reliability / Confiabilidade
  skip_final_snapshot  = true
  storage_encrypted    = true
  # Add credentials via Secrets Manager in production
}

# =============================================================================================
# 4. COMPUTE & MONITORING (Scalability & Operational Excellence)
# Auto Scaling and Load Balancing across Multi-AZ for fault tolerance.
# Auto Scaling e Load Balancing em Multi-AZ para tolerância a falhas.
# =============================================================================================

resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = "ami-0c7217cdde317cfec"
  instance_type = "t3.micro"
  iam_instance_profile { name = aws_iam_instance_profile.app_profile.name }
  network_interfaces {
    security_groups = [aws_security_group.app_sg.id]
  }
}

resource "aws_autoscaling_group" "app_asg" {
  vpc_zone_identifier = aws_subnet.private[*].id
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

# Proactive Monitoring (CloudWatch Alarms)
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.app_asg.name }
}

# Web Application Firewall (WAF) for Edge Security
resource "aws_wafv2_web_acl" "main" {
  name        = "main-waf"
  scope       = "REGIONAL"
  default_action { allow {} }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "main-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.app_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
