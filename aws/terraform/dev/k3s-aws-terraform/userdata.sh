#!/bin/bash
set -e

# K3s Installation Script (cloud-init)
# This script runs on EC2 instance startup

# Update system
apt-get update
apt-get install -y \
  curl \
  wget \
  git \
  jq \
  unzip \
  awscli

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install k3s
export K3S_TOKEN="${K3S_TOKEN}"
export INSTALL_K3S_EXEC="${K3S_EXEC}"

# Determine if this is server or agent node
if [ "${K3S_SERVER_TYPE}" = "server" ]; then
  # K3s Server (Control Plane)
  curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN INSTALL_K3S_EXEC="--tls-san=localhost --tls-san=127.0.0.1 --disable-helm-controller" sh -
  
  # Wait for k3s to be ready
  sleep 10
  
  # Extract kubeconfig and save to SSM Parameter Store (optional)
  if command -v aws &> /dev/null; then
    cat /etc/rancher/k3s/k3s.yaml | sed "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" > /tmp/kubeconfig.yaml
    aws ssm put-parameter \
      --name "/${K3S_CLUSTER_NAME}/kubeconfig" \
      --value file:///tmp/kubeconfig.yaml \
      --type "String" \
      --overwrite 2>/dev/null || true
  fi
else
  # K3s Agent (Worker)
  curl -sfL https://get.k3s.io | K3S_URL="https://${K3S_SERVER_IP}:6443" K3S_TOKEN=$K3S_TOKEN sh -
fi

# Install EBS CSI Driver (optional but recommended)
if [ "${ENABLE_EBS_CSI}" = "true" ]; then
  sleep 30
  until k3s kubectl get deployment -n kube-system coredns &> /dev/null; do
    echo "Waiting for k3s to stabilize..."
    sleep 5
  done
  
  # Install EBS CSI driver
  helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
  helm repo update
  helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    -n kube-system \
    --set enableWindowsHostProcess=true \
    --set node.nodeSelector."kubernetes\.io/os"=linux || true
fi

echo "K3s installation complete!"
