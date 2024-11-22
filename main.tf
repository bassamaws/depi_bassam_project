# Define VPC
resource "aws_vpc" "main" {
  cidr_block = "192.168.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

# Define Subnets
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.1.0/24" # Changed CIDR block to match VPC CIDR
  availability_zone = "us-east-1a"

  tags = {
    Name = "priv_subnet-1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.2.0/24" # Changed CIDR block to match VPC CIDR
  availability_zone = "us-east-1b"

  tags = {
    Name = "priv_subnet-2"
  }
}

resource "aws_subnet" "subnet3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.3.0/24" # Changed CIDR block to match VPC CIDR
  availability_zone = "us-east-1a"

  tags = {
    Name = "pub_subnet-1"
  }
}

resource "aws_subnet" "subnet4" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "192.168.4.0/24" # Changed CIDR block to match VPC CIDR
  availability_zone = "us-east-1b"

  tags = {
    Name = "pub_subnet-2"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-gateway"
  }
}

resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.subnet4.id

  tags = {
    Name = "nat-gateway"
  }
}

# Create Route Table
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public_RT"
  }
}

resource "aws_route_table" "private_RT" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private_RT"
  }
}

# Update Private Route Table to Route Traffic Through NAT Gateway
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_RT.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Associate Subnets with Route Tables
resource "aws_route_table_association" "subnet1_association" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.private_RT.id
}

resource "aws_route_table_association" "subnet2_association" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.private_RT.id
}

resource "aws_route_table_association" "subnet3_association" {
  subnet_id      = aws_subnet.subnet3.id
  route_table_id = aws_route_table.public_RT.id
}

resource "aws_route_table_association" "subnet4_association" {
  subnet_id      = aws_subnet.subnet4.id
  route_table_id = aws_route_table.public_RT.id
}

# Create Security Group for HTTP
resource "aws_security_group" "HTTP_SG" { # Changed name to avoid hyphen
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Replace with a more restrictive CIDR if needed
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP-SG"
  }
}

# Create Security Group for Bastion Host
resource "aws_security_group" "bastion_SG" { # Changed name to avoid hyphen
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "bastion-SG"
  }
}

# Create EC2 Instances
resource "aws_instance" "bastion_host" { # Changed name to avoid hyphen
  ami                         = "ami-0fff1b9a61dec8a5f"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet3.id
  vpc_security_group_ids      = [aws_security_group.bastion_SG.id] # Updated security group reference
  associate_public_ip_address = true
  key_name                    = "vockey"

  tags = {
    Name = "bastion-host"
  }

  depends_on = [aws_security_group.bastion_SG]
}

# Create Load Balancer (ALB)
resource "aws_lb" "test" {
  name               = "bassam-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.HTTP_SG.id] # Updated security group reference
  subnets            = [aws_subnet.subnet3.id, aws_subnet.subnet4.id]

  enable_deletion_protection = false

  tags = {
    Name = "bassam-alb"
  }
}

# Create Target Group
resource "aws_lb_target_group" "test" {
  name     = "TG-bassam"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    protocol = "HTTP"
    path     = "/"
  }

  tags = {
    Name = "TG-bassam"
  }
}

# Create Listener for ALB
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test.arn
  }
}

# Create Auto Scaling Group
resource "aws_launch_configuration" "app" {
  name            = "app-launch-configuration"
  image_id        = "ami-0fff1b9a61dec8a5f"
  instance_type   = "t2.micro"
  key_name        = "vockey"
  security_groups = [aws_security_group.HTTP_SG.id] # Updated security group reference

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y 
              sudo yum install httpd -y 
              sudo systemctl start httpd
              sudo systemctl enable httpd 
              EOF
}

resource "aws_autoscaling_group" "app" {
  launch_configuration = aws_launch_configuration.app.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  target_group_arns = [aws_lb_target_group.test.arn]

  tag {
    key                 = "Name"
    value               = "ASG_Instance"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
