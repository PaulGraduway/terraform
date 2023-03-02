terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.71.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_vpc" "dev-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name : "${var.app_name}-vpc"
  }
}

resource "aws_internet_gateway" "dev-gateway" {
  vpc_id = aws_vpc.dev-vpc.id
  tags = {
    Name : "${var.app_name}-gateway"
  }
}

resource "aws_route_table" "dev-route-table" {
  vpc_id = aws_vpc.dev-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev-gateway.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.dev-gateway.id
  }

  tags = {
    Name = "${var.app_name}-route-table"
  }
}

resource "aws_subnet" "dev-subnet" {
  vpc_id            = aws_vpc.dev-vpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "${var.region}a"
}

resource "aws_route_table_association" "dev-route_table_association" {
  subnet_id      = aws_subnet.dev-subnet.id
  route_table_id = aws_route_table.dev-route-table.id
}

resource "aws_security_group" "dev-sg" {
  name        = "${var.app_name}-vpc-sg"
  description = "API ports"
  vpc_id      = aws_vpc.dev-vpc.id

  ingress {
    description      = "http"
    from_port        = 4000
    to_port          = 4000
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.app_name}-vpc-sg"
  }
}

resource "aws_security_group" "sg-allow_public" {
  name        = "${var.app_name}-allow_public"
  description = "Allow public traffic"
  vpc_id      = aws_vpc.dev-vpc.id

  ingress {
    description      = "https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "http"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.app_name}-allow_public"
  }
}

resource "aws_network_interface" "server-nic" {
  subnet_id       = aws_subnet.dev-subnet.id
  private_ips     = ["10.0.0.10"]
  security_groups = [aws_security_group.dev-sg.id]
}

resource "aws_instance" "dev-api" {
  ami               = "ami-0fec2c2e2017f4e7b" # debian
  instance_type     = "t2.nano"
  availability_zone = "${var.region}a"
  key_name          = var.ssh_key_name
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.server-nic.id
  }
  root_block_device {
    volume_type = "gp3" # gp3 has better performance and cost for small sizes
    encrypted   = true
  }

  user_data = file("setup.sh")

  tags = {
    Name : "${var.app_name}-dev-api"
  }
}

resource "aws_eip" "dev-api-ip" {
  vpc        = true
  instance   = aws_instance.dev-api.id
  depends_on = [aws_internet_gateway.dev-gateway]
  tags = {
    Name = "${var.app_name}-elastic-ip"
  }
}

resource "aws_eip" "lb-ip" {
  tags = {
    Name : "${var.app_name}-lb-ip"
  }
}


resource "aws_lb" "lb" {
  name               = "${var.app_name}-lb"
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id     = aws_subnet.dev-subnet.id
    allocation_id = aws_eip.lb-ip.id
  }
}

resource "aws_lb_target_group" "target-http" {
  name     = "${var.app_name}-lb-target-group-http"
  protocol = "TCP"
  port     = 80
  vpc_id   = aws_vpc.dev-vpc.id
}

resource "aws_lb_target_group" "target-https" {
  name     = "${var.app_name}-lb-target-group-https"
  protocol = "TCP"
  port     = 443
  vpc_id   = aws_vpc.dev-vpc.id
}

resource "aws_lb_listener" "lb-http" {
  load_balancer_arn = aws_lb.lb.arn
  protocol          = "TCP"
  port              = 80

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-http.arn
  }
}

resource "aws_lb_listener" "lb-https" {
  load_balancer_arn = aws_lb.lb.arn
  protocol          = "TLS"
  port              = 443
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-https.arn
  }
}

resource "aws_lb_target_group_attachment" "lb-http" {
  target_group_arn = aws_lb_target_group.target-http.arn
  target_id        = aws_instance.dev-api.id
  port             = 4000
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "peerpal.v3computing.com"
  validation_method = "DNS"

  tags = {
    Name = "${var.app_name}-dev-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}
