terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    key = "smart-task-manager/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# ── VPC ──────────────────────────────────────────────────────────────────────
resource "aws_vpc" "smart_task_manager_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "smart-task-manager-vpc", Project = "smart-task-manager" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.smart_task_manager_vpc.id
  tags   = { Name = "smart-task-manager-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.smart_task_manager_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "smart-task-manager-public-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.smart_task_manager_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "smart-task-manager-public-rt" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ── Security Group ───────────────────────────────────────────────────────────
resource "aws_security_group" "smart_task_manager_sg" {
  name        = "smart-task-manager-sg"
  description = "Security group for Smart Task Manager app"
  vpc_id      = aws_vpc.smart_task_manager_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
    description = "SSH access"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "App port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "smart-task-manager-sg", Project = "smart-task-manager" }
}

# ── EC2 Instance ─────────────────────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "smart_task_manager_key" {
  key_name   = "smart-task-manager-key"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "smart_task_manager" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.smart_task_manager_sg.id]
  key_name               = aws_key_pair.smart_task_manager_key.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
  EOF

  tags = {
    Name    = "smart-task-manager-server"
    Project = "smart-task-manager"
    Env     = var.environment
  }
}

# ── Elastic IP ───────────────────────────────────────────────────────────────
resource "aws_eip" "smart_task_manager_eip" {
  instance = aws_instance.smart_task_manager.id
  domain   = "vpc"
  tags     = { Name = "smart-task-manager-eip" }
}
