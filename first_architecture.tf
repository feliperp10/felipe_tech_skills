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

# =========================================================================
# 1. NETWORKING (VPC, Subnets, Gateways)
# =========================================================================

# Criar a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

# Obter Zonas de Disponibilidade disponíveis
data "aws_availability_zones" "available" {
  state = "available"
}

# Sub-redes Públicas (Para ALB e NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-${count.index + 1}" }
}

# Sub-redes Privadas (Para Aplicação e RDS)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "private-subnet-${count.index + 1}" }
}

# Internet Gateway (Para acesso externo das Públicas)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "main-igw" }
}

# Elastic IP para o NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT Gateway (Permite que a sub-rede privada acesse a internet, ex: yum update)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "main-nat-gw" }
  depends_on = [aws_internet_gateway.igw]
}

# Route Table - Pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table - Privada
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =========================================================================
# 2. SECURITY GROUPS (Princípio do Menor Privilégio)
# =========================================================================

# SG do Load Balancer (Aberto para o mundo na porta 80/443)
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

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

# SG da Aplicação (Só aceita tráfego do ALB)
resource "aws_security_group" "app_sg" {
  name        = "app-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.main.id

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

# SG do Banco de Dados (Só aceita tráfego da App)
resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  description = "Allow traffic from App only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306 # Exemplo MySQL
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }
}

# =========================================================================
# 3. IAM & ROLES (Governança e Permissões)
# =========================================================================

# Role para EC2 acessar S3 e Logs
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

# Anexar política para acesso ao S3 (Somente leitura como exemplo)
resource "aws_iam_role_policy_attachment" "s3_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Anexar política para SSM (Para gerenciar a instância sem chaves SSH)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "app_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# =========================================================================
# 4. STORAGE (S3 & VPC Endpoint)
# =========================================================================

resource "aws_s3_bucket" "data_bucket" {
  bucket_prefix = "app-data-secure-"
}

# VPC Endpoint para S3 (O tráfego não sai para a internet pública)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [aws_route_table.private.id] # Associa apenas às rotas privadas
}

# =========================================================================
# 5. DATABASE (RDS)
# =========================================================================

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "main-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "default" {
  allocated_storage      = 20
  db_name                = "appdb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "ChangeMe123!" # Use AWS Secrets Manager em prod
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
  multi_az               = true # Alta disponibilidade
  storage_encrypted      = true # Segurança em repouso
}

# =========================================================================
# 6. COMPUTE & SCALING (ALB, ASG, Launch Template)
# =========================================================================

# Application Load Balancer
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
  health_check {
    path = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Launch Template (Configuração das EC2)
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-lt-"
  image_id      = "ami-0c7217cdde317cfec" # Amazon Linux 2023 (us-east-1)
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.app_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from AWS Architecture</h1>" > /var/www/html/index.html
              EOF
  )
}

# Auto Scaling Group (Escalabilidade Automática)
resource "aws_autoscaling_group" "app_asg" {
  vpc_zone_identifier = aws_subnet.private[*].id # Instâncias na rede privada!
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }
}

# =========================================================================
# 7. MONITORING & WAF (Opcional mas recomendado)
# =========================================================================

# Alarme CloudWatch de Exemplo (CPU Alta)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_asg.name
  }
}

# WAF (Web Application Firewall) Básico
resource "aws_wafv2_web_acl" "main" {
  name        = "main-waf"
  scope       = "REGIONAL"
  description = "Basic WAF protection"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "main-waf"
    sampled_requests_enabled   = true
  }
  # Em um cenário real, você adicionaria regras aqui (SQLi, XSS, etc)
}

# Associar WAF ao ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.app_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
