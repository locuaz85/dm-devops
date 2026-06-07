#!/bin/bash
set -e

# K3sup Cluster Bootstrap
# This script installs k3s using k3sup

# Configuration
SERVER_IP="${SERVER_IP:-}"
WORKER_IPS=("${WORKER_IPS[@]:-}")
SSH_USER="${SSH_USER:-ubuntu}"
KEY_PATH="${KEY_PATH:-./my-k3s-key.pem}"
CLUSTER_NAME="${CLUSTER_NAME:-my-k3s-cluster}"

echo "=== K3sup K3s Deployment ==="
echo "Server IP: $SERVER_IP"
echo "Worker IPs: ${WORKER_IPS[@]}"
echo "SSH User: $SSH_USER"
echo "Cluster Name: $CLUSTER_NAME"
echo ""

# Validate inputs
if [ -z "$SERVER_IP" ]; then
  echo "[ERROR] SERVER_IP not set. Usage: SERVER_IP=1.2.3.4 ./bootstrap-k3sup.sh"
  exit 1
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "[ERROR] Key not found at $KEY_PATH"
  exit 1
fi

# Verify tools
if ! command -v k3sup &> /dev/null; then
  echo "[ERROR] k3sup not found. Run setup-prereqs.sh first."
  exit 1
fi

# Install server
echo "[1/3] Installing k3s server on $SERVER_IP..."
k3sup install \
  --ip "$SERVER_IP" \
  --user "$SSH_USER" \
  --ssh-key "$KEY_PATH" \
  --tls-san "$SERVER_IP" \
  --local-path "./kubeconfig.yaml" \
  --cluster-name "$CLUSTER_NAME"

echo "[OK] Server installed. Kubeconfig saved to ./kubeconfig.yaml"
sleep 5

# Join workers
if [ ${#WORKER_IPS[@]} -gt 0 ]; then
  echo "[2/3] Joining worker nodes..."
  for WORKER_IP in "${WORKER_IPS[@]}"; do
    echo "  Joining $WORKER_IP..."
    k3sup join \
      --ip "$WORKER_IP" \
      --server-ip "$SERVER_IP" \
      --user "$SSH_USER" \
      --ssh-key "$KEY_PATH"
    sleep 2
  done
  echo "[OK] All workers joined"
else
  echo "[SKIP] No worker IPs provided (single-server cluster)"
fi

# Verify cluster
echo "[3/3] Verifying cluster..."
export KUBECONFIG=$(pwd)/kubeconfig.yaml
sleep 10

kubectl get nodes
echo ""
echo "[SUCCESS] K3s cluster ready!"
echo ""
echo "Kubeconfig: $(pwd)/kubeconfig.yaml"
echo "Next: kubectl get pods -A"
