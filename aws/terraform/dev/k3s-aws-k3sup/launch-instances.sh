#!/bin/bash
set -e

# Launch EC2 instances for k3s cluster
# This script uses AWS CLI to create instances with minimal setup

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-my-k3s-cluster}"
KEY_NAME="${KEY_NAME:-my-k3s-key}"
NUM_WORKERS="${NUM_WORKERS:-2}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-$CLUSTER_NAME-sg}"
PUBLIC_SUBNET_CIDR="${PUBLIC_SUBNET_CIDR:-10.0.1.0/24}"
EXISTING_PUBLIC_SUBNET_CIDR="${EXISTING_PUBLIC_SUBNET_CIDR:-$PUBLIC_SUBNET_CIDR}"

echo "=== AWS EC2 Instance Launch ==="
echo "Region: $AWS_REGION"
echo "Cluster: $CLUSTER_NAME"
echo "Workers: $NUM_WORKERS"
echo ""

# Verify AWS CLI
if ! command -v aws &> /dev/null; then
  echo "[ERROR] AWS CLI not found"
  exit 1
fi

# Verify key exists
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "[ERROR] Key pair '$KEY_NAME' not found in $AWS_REGION"
  echo "Create it: aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem && chmod 400 $KEY_NAME.pem"
  exit 1
fi

# Get latest Ubuntu 22.04 AMI
echo "[1/4] Finding Ubuntu 22.04 LTS AMI..."
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text \
  --region "$AWS_REGION")

if [ -z "$AMI_ID" ]; then
  echo "[ERROR] Could not find Ubuntu 22.04 AMI"
  exit 1
fi

echo "[OK] AMI: $AMI_ID"

# Create VPC and Security Group (if needed)
echo "[2/4] Setting up VPC and Security Group..."

if [ -n "$EXISTING_VPC_ID" ]; then
  echo "[INFO] Reusing existing VPC: $EXISTING_VPC_ID"
  VPC_ID="$EXISTING_VPC_ID"
  IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" --region "$AWS_REGION" --query 'InternetGateways[0].InternetGatewayId' --output text)
  if [ "$IGW_ID" = "None" ] || [ -z "$IGW_ID" ]; then
    IGW_ID=$(aws ec2 create-internet-gateway \
      --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$CLUSTER_NAME-igw}]" \
      --region "$AWS_REGION" \
      --query "InternetGateway.InternetGatewayId" \
      --output text)
    aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
  fi
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "${EXISTING_PUBLIC_SUBNET_CIDR}" \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$CLUSTER_NAME-subnet}]" \
    --region "$AWS_REGION" \
    --query "Subnet.SubnetId" \
    --output text)
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$AWS_REGION"
else
  # Create VPC
  VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "10.0.0.0/16" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$CLUSTER_NAME-vpc}]" \
    --region "$AWS_REGION" \
    --query "Vpc.VpcId" \
    --output text)

  echo "[OK] VPC: $VPC_ID"

  # Create subnet
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "10.0.1.0/24" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$CLUSTER_NAME-subnet}]" \
    --region "$AWS_REGION" \
    --query "Subnet.SubnetId" \
    --output text)

  echo "[OK] Subnet: $SUBNET_ID"

  # Create Internet Gateway
  IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$CLUSTER_NAME-igw}]" \
    --region "$AWS_REGION" \
    --query "InternetGateway.InternetGatewayId" \
    --output text)

  echo "[OK] IGW: $IGW_ID"
  aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$AWS_REGION"
fi

# Create route table
RT_ID=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$CLUSTER_NAME-rt}]" \
  --region "$AWS_REGION" \
  --query "RouteTable.RouteTableId" \
  --output text)

aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID" --region "$AWS_REGION"
aws ec2 associate-route-table --subnet-id "$SUBNET_ID" --route-table-id "$RT_ID" --region "$AWS_REGION"

echo "[OK] Route table: $RT_ID"

# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SECURITY_GROUP_NAME" \
  --description "K3s cluster security group" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query "GroupId" \
  --output text)

# Add ingress rules
echo "[3/4] Configuring Security Group rules..."

# SSH
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$AWS_REGION"

# Kubernetes API
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 6443 --cidr 0.0.0.0/0 --region "$AWS_REGION"

# HTTP/HTTPS
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$AWS_REGION"

# NodePort range
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0 --region "$AWS_REGION"

# Inter-node communication
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 0-65535 --source-group "$SG_ID" --region "$AWS_REGION"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol udp --port 0-65535 --source-group "$SG_ID" --region "$AWS_REGION"

echo "[OK] Security group: $SG_ID"

# Launch k3s server instance
echo "[4/4] Launching instances..."

SERVER_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "t3.medium" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTER_NAME-server},{Key=Role,Values=k3s-server}]" \
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}" \
  --region "$AWS_REGION" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "[OK] Server instance launched: $SERVER_INSTANCE_ID"

# Launch worker instances
for i in $(seq 1 $NUM_WORKERS); do
  WORKER_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "t3.small" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --subnet-id "$SUBNET_ID" \
    --associate-public-ip-address \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTER_NAME-worker-$i},{Key=Role,Value=k3s-worker}]" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}" \
    --region "$AWS_REGION" \
    --query "Instances[0].InstanceId" \
    --output text)
  echo "[OK] Worker instance launched: $WORKER_INSTANCE_ID"
done

# Wait for instances to be running
echo ""
echo "Waiting for instances to enter 'running' state..."
aws ec2 wait instance-running --instance-ids "$SERVER_INSTANCE_ID" --region "$AWS_REGION"

# Get IPs
echo "[INFO] Fetching instance IPs..."
sleep 5

SERVER_IP=$(aws ec2 describe-instances \
  --instance-ids "$SERVER_INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

WORKER_IPS=$(aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=k3s-worker" "Name=vpc-id,Values=$VPC_ID" \
  --region "$AWS_REGION" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text)

echo ""
echo "=========================================="
echo "Instances launched successfully!"
echo "=========================================="
echo "Server IP: $SERVER_IP"
echo "Worker IPs: $WORKER_IPS"
echo "Security Group: $SG_ID"
echo ""
echo "Next: Run k3sup to bootstrap the cluster"
echo "  export SERVER_IP=$SERVER_IP"
echo "  export WORKER_IPS=($WORKER_IPS)"
echo "  ./bootstrap-k3sup.sh"
