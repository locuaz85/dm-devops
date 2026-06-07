variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "K3s cluster name"
  type        = string
  default     = "my-k3s-cluster"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type_server" {
  description = "EC2 instance type for k3s server"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_worker" {
  description = "EC2 instance type for k3s workers"
  type        = string
  default     = "t3.small"
}

variable "num_workers" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 2
}

variable "ami_name_filter" {
  description = "AMI name filter for Ubuntu 22.04 LTS"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ami_owner" {
  description = "Canonical AWS account ID for Ubuntu AMIs"
  type        = string
  default     = "099720109477"
}

variable "key_name" {
  description = "AWS EC2 Key Pair name for SSH access"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # CHANGE IN PRODUCTION!
}

variable "k3s_token" {
  description = "K3s cluster token (generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable AWS EBS CSI driver for dynamic PVs"
  type        = bool
  default     = true
}

variable "enable_traefik" {
  description = "Enable Traefik ingress controller (default k3s)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "k3s"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}
