# K3s on AWS – Quick Start with k3sup

Fast way to get k3s running on AWS using k3sup (no infrastructure-as-code needed).

## What is k3sup?

**k3sup** (k3s + superpower) is a CLI tool that:
- Installs k3s on remote instances via SSH
- Joins worker nodes to the cluster
- Downloads kubeconfig automatically
- Works with any Linux distro on EC2, DigitalOcean, Hetzner, bare metal, etc.

**Advantage over Terraform:** Quick manual setup, great for learning/testing.  
**Disadvantage:** No IaC; you manage instances manually (or script it).

## Prerequisites

1. **AWS Account** with CLI access
2. **AWS CLI** installed and configured:
   ```bash
   aws configure
   ```
3. **EC2 Key Pair** in AWS:
   ```bash
   aws ec2 create-key-pair --key-name my-k3s-key --query 'KeyMaterial' --output text > my-k3s-key.pem
   chmod 400 my-k3s-key.pem
   ```
4. **k3sup** (auto-installed by scripts) or manually:
   ```bash
   curl -sLS https://get.k3sup.dev | sh
   sudo install k3sup /usr/local/bin/
   ```
5. **kubectl** (optional, auto-installed)

## Quick Start (Complete Workflow)

**Fastest path:** Run one command to provision everything:

```bash
export CLUSTER_NAME=my-k3s-cluster
export KEY_NAME=my-k3s-key
export KEY_PATH=./my-k3s-key.pem
export NUM_WORKERS=2
export AWS_REGION=us-east-1

bash complete-workflow.sh
```

This will:
1. Create VPC, subnet, security groups, route tables
2. Launch 1 server (t3.medium) + 2 workers (t3.small)
3. Install k3s using k3sup
4. Join workers
5. Save kubeconfig as `./kubeconfig.yaml`

Done! → `kubectl get nodes`

---

## Step-by-Step Workflow (Manual Control)

### Step 1: Launch EC2 Instances

```bash
export CLUSTER_NAME=my-k3s-cluster
export KEY_NAME=my-k3s-key
export NUM_WORKERS=2
export AWS_REGION=us-east-1

bash launch-instances.sh
```

Output:
```
Server IP: 54.1.2.3
Worker IPs: 54.1.2.4 54.1.2.5
Security Group: sg-0abc123def
```

Or **launch manually** in AWS Console:
- 1× Ubuntu 22.04 LTS, t3.medium (server)
- 2× Ubuntu 22.04 LTS, t3.small (workers)
- Same security group (see below)
- Assign public IPs

### Step 2: Configure Security Group

Allow inbound (if not auto-created):
- **22 (SSH)**: Your IP or 0.0.0.0/0
- **6443 (API)**: 0.0.0.0/0
- **80, 443 (Ingress)**: 0.0.0.0/0
- **30000-32767 (NodePort)**: 0.0.0.0/0
- **All TCP/UDP**: Between nodes (via SG)

### Step 3: Bootstrap with k3sup

Install prerequisites:
```bash
bash setup-prereqs.sh
```

Bootstrap cluster:
```bash
export SERVER_IP=54.1.2.3
export WORKER_IPS=(54.1.2.4 54.1.2.5)
export KEY_PATH=./my-k3s-key.pem

bash bootstrap-k3sup.sh
```

Or **manually with k3sup**:

```bash
# Install server
k3sup install \
  --ip 54.1.2.3 \
  --user ubuntu \
  --ssh-key ./my-k3s-key.pem \
  --tls-san 54.1.2.3 \
  --local-path ./kubeconfig.yaml

# Join first worker
k3sup join \
  --ip 54.1.2.4 \
  --server-ip 54.1.2.3 \
  --user ubuntu \
  --ssh-key ./my-k3s-key.pem

# Join second worker
k3sup join \
  --ip 54.1.2.5 \
  --server-ip 54.1.2.3 \
  --user ubuntu \
  --ssh-key ./my-k3s-key.pem
```

### Step 4: Use Cluster

```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml

kubectl get nodes
kubectl get pods -A
```

---

## Manual Commands (Reference)

### Get IPs from AWS CLI

```bash
# Server IP
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=my-k3s-cluster-server" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text \
  --region us-east-1

# Worker IPs
aws ec2 describe-instances \
  --filters "Name=tag:Role,Values=k3s-worker" \
  --query "Reservations[].Instances[].PublicIpAddress" \
  --output text \
  --region us-east-1
```

### SSH to Instance

```bash
ssh -i my-k3s-key.pem ubuntu@<ip>
```

### Check k3s Status (on server)

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -f  # Follow logs
k3s kubectl get nodes  # On server
```

### Download kubeconfig

```bash
scp -i my-k3s-key.pem ubuntu@<server-ip>:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml

# Edit kubeconfig: replace "127.0.0.1" with server IP
sed -i 's/127.0.0.1/<server-ip>/g' kubeconfig.yaml
```

---

## Troubleshooting

### k3s service not running
```bash
ssh -i my-k3s-key.pem ubuntu@<server-ip>
sudo systemctl restart k3s
sudo journalctl -u k3s -n 50
```

### Nodes stuck in "NotReady"
```bash
kubectl describe node <node-name>
kubectl get pods -A -o wide | grep -v Running
```

**Common causes:**
- Pod network (flannel/canal) not deployed → k3s deploys it automatically
- EBS CSI driver missing → Install manually if needed
- Kubelet not running → Check logs on node

### Cannot connect from kubeconfig
Edit `kubeconfig.yaml`, look for:
```yaml
server: https://127.0.0.1:6443
```

Replace with:
```yaml
server: https://54.1.2.3:6443  # or your server public IP
```

Then test:
```bash
kubectl cluster-info
```

### Worker node won't join
```bash
# On worker:
ssh -i my-k3s-key.pem ubuntu@<worker-ip>
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f
```

**Common causes:**
- Wrong server IP
- Token mismatch
- Network/firewall issue

---

## Cost Estimates

**Hourly** (t3 on-demand, us-east-1):
- t3.medium (server): $0.0416/hr
- t3.small (worker ×2): $0.0416/hr
- **Total: ~$0.083/hr** (~$60/month 24/7)

Stop instances when not in use:
```bash
aws ec2 stop-instances --instance-ids <id> --region us-east-1
```

Delete everything:
```bash
aws ec2 terminate-instances --instance-ids <id> --region us-east-1
# (VPC, SG, etc. will auto-delete after a few minutes)
```

---

## Next Steps

### Install Helm
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Deploy Sample App
```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc
```

### Install cert-manager (TLS)
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace
```

### Set Up Monitoring (Prometheus/Grafana)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

### Enable EBS CSI Driver (dynamic volumes)
```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver -n kube-system
```

---

## Additional Resources

- [k3sup GitHub](https://github.com/alexellis/k3sup)
- [K3s Official Docs](https://docs.k3s.io)
- [K3s Architecture](https://docs.k3s.io/architecture)
- [AWS EC2 Launch Types](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-types.html)
