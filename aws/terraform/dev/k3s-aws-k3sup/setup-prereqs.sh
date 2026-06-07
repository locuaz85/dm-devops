#!/bin/bash
set -e

# K3sup Bootstrap Script for AWS
# Quick setup: provision EC2 instances manually, then run k3sup

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-my-k3s-cluster}"
KEY_NAME="${KEY_NAME:-my-k3s-key}"
KEY_PATH="${KEY_PATH:-./my-k3s-key.pem}"

echo "=== K3sup K3s Cluster Bootstrap ==="
echo "Region: $AWS_REGION"
echo "Cluster Name: $CLUSTER_NAME"
echo "Key Path: $KEY_PATH"
echo ""

# Verify key exists
if [ ! -f "$KEY_PATH" ]; then
  echo "[ERROR] Key not found at $KEY_PATH"
  echo "Create it with: aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_PATH && chmod 400 $KEY_PATH"
  exit 1
fi

# Verify k3sup is installed
if ! command -v k3sup &> /dev/null; then
  echo "[INFO] Installing k3sup..."
  curl -sLS https://get.k3sup.dev | sh
  sudo install k3sup /usr/local/bin/
fi

# Verify kubectl is installed
if ! command -v kubectl &> /dev/null; then
  echo "[INFO] Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

echo "[INFO] Required tools ready: k3sup, kubectl"
echo ""
echo "Next steps:"
echo "1. Launch EC2 instances in AWS console (or use EC2 launch template from docs)"
echo "2. Get server IP: aws ec2 describe-instances --filters 'Name=tag:Role,Values=k3s-server' --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region $AWS_REGION"
echo "3. Get worker IPs: aws ec2 describe-instances --filters 'Name=tag:Role,Values=k3s-worker' --query 'Reservations[].Instances[].PublicIpAddress' --output text --region $AWS_REGION"
echo "4. Edit this script to add SERVER_IP and WORKER_IPS, then run bootstrap"
echo ""
