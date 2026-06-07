output "k3s_server_private_ip" {
  value       = aws_instance.k3s_server.private_ip
  description = "Private IP of k3s server"
}

output "k3s_server_public_ip" {
  value       = aws_instance.k3s_server.public_ip
  description = "Public IP of k3s server"
}

output "k3s_server_ssh_command" {
  value       = "ssh -i <your-key.pem> ubuntu@${aws_instance.k3s_server.public_ip}"
  description = "SSH command to connect to k3s server"
}

output "k3s_workers_private_ips" {
  value       = aws_instance.k3s_workers[*].private_ip
  description = "Private IPs of k3s worker nodes"
}

output "k3s_workers_public_ips" {
  value       = aws_instance.k3s_workers[*].public_ip
  description = "Public IPs of k3s worker nodes"
}

output "k3s_token" {
  value       = local.k3s_token
  sensitive   = true
  description = "K3s cluster token (sensitive)"
}

output "vpc_id" {
  value       = aws_vpc.k3s.id
  description = "VPC ID"
}

output "security_group_id" {
  value       = aws_security_group.k3s_nodes.id
  description = "Security group ID for k3s nodes"
}

output "api_loadbalancer_dns" {
  value       = aws_lb.k3s_api.dns_name
  description = "DNS name of API server load balancer"
}

output "kubeconfig_command" {
  value       = "scp -i <your-key.pem> ubuntu@${aws_instance.k3s_server.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml"
  description = "Command to download kubeconfig from server"
}

output "next_steps" {
  value = <<-EOT
    1. SSH to server: ssh -i <your-key.pem> ubuntu@${aws_instance.k3s_server.public_ip}
    2. Check k3s status: sudo systemctl status k3s
    3. View logs: sudo journalctl -u k3s -f
    4. Download kubeconfig: scp -i <your-key.pem> ubuntu@${aws_instance.k3s_server.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
    5. Set kubeconfig: export KUBECONFIG=./kubeconfig.yaml
    6. Test cluster: kubectl get nodes
  EOT
  description = "Next steps after deployment"
}
