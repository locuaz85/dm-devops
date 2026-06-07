#!/bin/bash
set -e

# Complete k3sup workflow script
# Combines EC2 launch and k3sup bootstrap

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-my-k3s-cluster}"
KEY_NAME="${KEY_NAME:-my-k3s-key}"
KEY_PATH="${KEY_PATH:-./$KEY_NAME.pem}"
SSH_USER="${SSH_USER:-ubuntu}"
NUM_WORKERS="${NUM_WORKERS:-2}"
PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-10.0.1.0/24}"
EXISTING_PUBLIC_SUBNET_CIDR="${EXISTING_PUBLIC_SUBNET_CIDR:-$PUBLIC_SUBNET_CIDR}"

# If the user has an existing VPC, override the default subnet CIDR to match it.
# Example: EXISTING_PUBLIC_SUBNET_CIDR=172.31.32.0/24 when reusing the AWS default VPC.

echo "=========================================="
echo "K3s on AWS - Complete Workflow"
echo "=========================================="
echo ""

# Step 1: Prerequisites
echo "[Step 1] Checking prerequisites..."

if ! command -v aws &> /dev/null; then
  echo "[ERROR] AWS CLI not found"
  exit 1
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "[ERROR] SSH key not found at $KEY_PATH"
  echo "Create it: aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_PATH && chmod 400 $KEY_PATH"
  exit 1
fi

if ! command -v k3sup &> /dev/null; then
  echo "[INFO] Installing k3sup..."
  curl -sLS https://get.k3sup.dev | sh
  sudo install k3sup /usr/local/bin/
fi

if ! command -v kubectl &> /dev/null; then
  echo "[INFO] Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

echo "[OK] All prerequisites ready"
echo ""

# Step 2: Launch instances
echo "[Step 2] Launching EC2 instances..."
echo "  Region: $AWS_REGION"
echo "  Cluster: $CLUSTER_NAME"
echo "  Workers: $NUM_WORKERS"
echo ""

# Get AMI
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text \
  --region "$AWS_REGION")

echo "  AMI: $AMI_ID"

# Create or reuse VPC resources
if [ -n "$EXISTING_VPC_ID" ]; then
  echo "[INFO] Reusing existing VPC: $EXISTING_VPC_ID"
  VPC_ID="$EXISTING_VPC_ID"
  IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" --region "$AWS_REGION" --query 'InternetGateways[0].InternetGatewayId' --output text)
  if [ "$IGW_ID" = "None" ] || [ -z "$IGW_ID" ]; then
    IGW_ID=$(aws ec2 create-internet-gateway --region "$AWS_REGION" --query "InternetGateway.InternetGatewayId" --output text)
    aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
  fi
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "${EXISTING_PUBLIC_SUBNET_CIDR}" --availability-zone "${AWS_REGION}a" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$CLUSTER_NAME-subnet}]" --region "$AWS_REGION" --query "Subnet.SubnetId" --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"
  RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$AWS_REGION" --query "RouteTable.RouteTableId" --output text)
  aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" --region "$AWS_REGION"
  aws ec2 associate-route-table --subnet-id "$SUBNET_ID" --route-table-id "$RT_ID" --region "$AWS_REGION"
else
  VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --region "$AWS_REGION" --query "Vpc.VpcId" --output text)
  SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$PUBLIC_SUBNET_CIDR" --region "$AWS_REGION" --query "Subnet.SubnetId" --output text)
  IGW_ID=$(aws ec2 create-internet-gateway --region "$AWS_REGION" --query "InternetGateway.InternetGatewayId" --output text)
  aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
  RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$AWS_REGION" --query "RouteTable.RouteTableId" --output text)
  aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" --region "$AWS_REGION"
  aws ec2 associate-route-table --subnet-id "$SUBNET_ID" --route-table-id "$RT_ID" --region "$AWS_REGION"
fi

# Create security group
SG_ID=$(aws ec2 create-security-group --group-name "$CLUSTER_NAME-sg" --description "K3s cluster" --vpc-id "$VPC_ID" --region "$AWS_REGION" --query "GroupId" --output text)

# Add security group rules
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 6443 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 0-65535 --source-group "$SG_ID" --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol udp --port 0-65535 --source-group "$SG_ID" --region "$AWS_REGION"

# Launch server
SERVER_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "t3.medium" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,DeleteOnTermination=true}" \
  --region "$AWS_REGION" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "  Server: $SERVER_INSTANCE_ID"

# Launch workers
for i in $(seq 1 $NUM_WORKERS); do
  WORKER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "t3.small" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,DeleteOnTermination=true}" \
    --region "$AWS_REGION" \
    --query "Instances[0].InstanceId" \
    --output text)
  echo "  Worker $i: $WORKER_INSTANCE_ID"
done

echo ""
echo "Waiting for instances to start..."
aws ec2 wait instance-running --instance-ids "$SERVER_INSTANCE_ID" --region "$AWS_REGION"

sleep 10

# Get IPs
SERVER_IP=$(aws ec2 describe-instances --instance-ids "$SERVER_INSTANCE_ID" --region "$AWS_REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

WORKER_INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Role,Values=k3s-worker" "Name=vpc-id,Values=$VPC_ID" --region "$AWS_REGION" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || echo "")

echo "[OK] Instances running"
echo "  Server: $SERVER_IP"

# Step 3: Bootstrap with k3sup
echo ""
echo "[Step 3] Bootstrapping k3s cluster..."

k3sup install \
  --ip "$SERVER_IP" \
  --user "$SSH_USER" \
  --ssh-key "$KEY_PATH" \
  --tls-san "$SERVER_IP" \
  --local-path "./kubeconfig.yaml"

echo "[OK] Server configured"

# Join workers
if [ -n "$WORKER_INSTANCES" ]; then
  for WORKER_ID in $WORKER_INSTANCES; do
    WORKER_IP=$(aws ec2 describe-instances --instance-ids "$WORKER_ID" --region "$AWS_REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    echo "  Joining worker: $WORKER_IP"
    k3sup join \
      --ip "$WORKER_IP" \
      --server-ip "$SERVER_IP" \
      --user "$SSH_USER" \
      --ssh-key "$KEY_PATH"
    sleep 2
  done
fi

echo ""
echo "=========================================="
echo "SUCCESS! K3s cluster is ready"
echo "=========================================="
echo ""
echo "Kubeconfig: $(pwd)/kubeconfig.yaml"
echo "API Server: https://$SERVER_IP:6443"
echo ""
echo "Test cluster:"
echo "  export KUBECONFIG=$(pwd)/kubeconfig.yaml"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
