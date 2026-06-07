data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  k3s_token = var.k3s_token != "" ? var.k3s_token : random_password.k3s_token.result
  userdata_base = file("${path.module}/userdata.sh")
}

resource "random_password" "k3s_token" {
  length  = 48
  special = true
}

# K3s Server (Control Plane)
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_server
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k3s_nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    K3S_TOKEN            = local.k3s_token
    K3S_SERVER_TYPE      = "server"
    K3S_EXEC             = "--tls-san=${self.private_ip} --disable-helm-controller"
    K3S_SERVER_IP        = ""
    K3S_CLUSTER_NAME     = var.cluster_name
    ENABLE_EBS_CSI       = var.enable_ebs_csi_driver ? "true" : "false"
  }))

  monitoring             = true
  associate_public_ip_address = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-server-0"
      Role = "server"
    }
  )

  depends_on = [aws_internet_gateway.k3s]
}

# K3s Worker Nodes
resource "aws_instance" "k3s_workers" {
  count                  = var.num_workers
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_worker
  key_name               = var.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k3s_nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    K3S_TOKEN            = local.k3s_token
    K3S_SERVER_TYPE      = "worker"
    K3S_EXEC             = ""
    K3S_SERVER_IP        = aws_instance.k3s_server.private_ip
    K3S_CLUSTER_NAME     = var.cluster_name
    ENABLE_EBS_CSI       = var.enable_ebs_csi_driver ? "true" : "false"
  }))

  monitoring             = true
  associate_public_ip_address = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-worker-${count.index}"
      Role = "worker"
    }
  )

  depends_on = [aws_instance.k3s_server]
}

# Network Load Balancer for API server (optional - for HA)
resource "aws_lb" "k3s_api" {
  name               = "${var.cluster_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]
  security_groups    = [aws_security_group.k3s_lb.id]

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nlb"
    }
  )
}

resource "aws_lb_target_group" "k3s_api" {
  name        = "${var.cluster_name}-api"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.k3s.id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-api-tg"
    }
  )
}

resource "aws_lb_target_group_attachment" "k3s_api_server" {
  target_group_arn = aws_lb_target_group.k3s_api.arn
  target_id        = aws_instance.k3s_server.id
  port             = 6443
}

resource "aws_lb_listener" "k3s_api" {
  load_balancer_arn = aws_lb.k3s_api.arn
  port              = "6443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s_api.arn
  }
}
