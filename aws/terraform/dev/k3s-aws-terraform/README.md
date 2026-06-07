# K3s on AWS - Terraform IaC

Complete Infrastructure-as-Code setup to provision a k3s cluster on AWS using Terraform.

## What Gets Deployed

- **VPC** with public subnet and internet gateway
- **Security Groups** for nodes and load balancer with proper ingress/egress rules
- **IAM Role & Instance Profile** for EC2 instances with EBS CSI driver permissions
- **1 K3s Server** (Control Plane) - t3.medium by default
- **N K3s Workers** (configurable, default 2) - t3.small by default
- **Network Load Balancer** for stable k3s API access
- **Auto-generated K3s token** for cluster joining (or provide your own)
- **EBS CSI Driver** IAM policy (optional, enabled by default)
- **Encrypted EBS volumes** for all instances
- **SSM Agent** for EC2 Systems Manager access (troubleshooting)

## Prerequisites

1. **AWS Account** with programmatic access (Access Key ID + Secret Access Key)
2. **AWS CLI** installed and configured:
   ```bash
   aws configure
   ```
3. **Terraform** installed (v1.0+)
   ```bash
   terraform --version
   ```
4. **EC2 Key Pair** created in AWS:
   ```bash
   aws ec2 create-key-pair --key-name my-k3s-key --query 'KeyMaterial' --output text > my-k3s-key.pem
   chmod 400 my-k3s-key.pem
   ```

## Quick Start

### 1. Prepare Variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings:
# - key_name: your EC2 key pair name
# - aws_region: your preferred region
# - ssh_allowed_cidrs: restrict to your IP (e.g., ["203.0.113.0/24"])
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review Plan
```bash
terraform plan -out=tfplan
```

### 4. Apply
```bash
terraform apply tfplan
```

Terraform will output:
- K3s server public/private IPs
- Worker node IPs
- SSH command to access server
- Kubeconfig download command
- Next steps

### 5. Connect to Cluster

**SSH to server:**
```bash
ssh -i my-k3s-key.pem ubuntu@<server-public-ip>
```

**Check k3s status on server:**
```bash
sudo systemctl status k3s
sudo journalctl -u k3s -f  # Follow logs
```

**Download kubeconfig to local machine:**
```bash
scp -i my-k3s-key.pem ubuntu@<server-public-ip>:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
# Edit kubeconfig.yaml: replace 127.0.0.1 with server public IP or LB DNS
```

**Use kubeconfig:**
```bash
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

## Customization

### Change Instance Types
Edit `terraform.tfvars`:
```hcl
instance_type_server = "t3.large"  # For more resources
instance_type_worker = "t3.medium"
```

### Add More Workers
```hcl
num_workers = 5
```

### Restrict SSH Access
```hcl
ssh_allowed_cidrs = ["203.0.113.0/24"]  # Your IP/VPN CIDR
```

### Disable EBS CSI Driver
```hcl
enable_ebs_csi_driver = false
```

## Networking

### Ports Opened

| Protocol | Port Range | Purpose | Source |
|----------|-----------|---------|--------|
| TCP | 22 | SSH | ssh_allowed_cidrs |
| TCP | 6443 | Kubernetes API | 0.0.0.0/0 |
| TCP | 80 | HTTP (Ingress) | 0.0.0.0/0 |
| TCP | 443 | HTTPS (Ingress) | 0.0.0.0/0 |
| TCP | 30000-32767 | NodePort range | 0.0.0.0/0 |
| All (TCP/UDP) | All | Inter-node comms | VPC CIDR |

### Load Balancer

A Network Load Balancer (NLB) is created for the k3s API server:
- Endpoint: `<nlb-dns-name>:6443`
- Useful for multi-server HA setups

## Managing Cluster

### View Terraform State
```bash
terraform show
terraform state list
```

### Modify Cluster (Update)
Edit `terraform.tfvars`, then:
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Scale Workers Up/Down
```bash
# In terraform.tfvars:
num_workers = 10  # Or lower

terraform apply
```

### Destroy Everything
```bash
terraform destroy
```

## Troubleshooting

### k3s not starting on instances
```bash
ssh -i my-k3s-key.pem ubuntu@<ip>
sudo journalctl -u k3s -n 50  # Last 50 lines
```

### Nodes stuck in "NotReady"
Check CNI, kubelet, and EBS CSI driver installation:
```bash
kubectl describe node <node-name>
kubectl get pods -A  # Are system pods running?
```

### Cannot connect to kubeconfig
Edit `kubeconfig.yaml` and replace `server: https://127.0.0.1:6443` with:
- Server public IP, or
- Load balancer DNS: `https://<nlb-dns>:6443`

Then:
```bash
kubectl get nodes
```

### Security Group Issues
If nodes can't communicate, check:
```bash
aws ec2 describe-security-groups --group-ids <sg-id> --region <region>
```

## Costs

Rough **hourly cost estimates** (t3 on-demand, us-east-1):
- t3.medium (server): $0.0416/hr
- t3.small (worker, ×2): $0.0208/hr × 2 = $0.0416/hr
- **Total: ~$0.083/hr (~$60/month for 24/7)**

Use `terraform plan` to see all resource costs before applying.

## Next Steps After Deployment

1. **Deploy a sample app:**
   ```bash
   kubectl create deployment nginx --image=nginx
   kubectl expose deployment nginx --port=80 --type=NodePort
   kubectl get svc
   ```

2. **Install Helm** (if not pre-installed):
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

3. **Install cert-manager** (for TLS):
   ```bash
   helm repo add jetstack https://charts.jetstack.io
   helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace
   ```

4. **Set up external-dns** (auto DNS management - requires Route53 or similar)

5. **Enable monitoring** (Prometheus/Grafana stack)

6. **Back up cluster state** (Velero to S3)

## Additional Resources

- [K3s Official Docs](https://docs.k3s.io)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [K3s Architecture](https://docs.k3s.io/architecture)
