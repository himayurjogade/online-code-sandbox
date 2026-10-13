output "server_public_ip" {
  description = "Public IP address of the single Kubernetes server"
  value       = aws_instance.server.public_ip
}

output "web_url" {
  description = "URL to access the Web Application Frontend"
  value       = "http://${aws_instance.server.public_ip}"
}

output "api_url" {
  description = "URL to access the REST API"
  value       = "http://${aws_instance.server.public_ip}:3000"
}

output "grafana_url" {
  description = "URL to access the Grafana Observability Dashboard"
  value       = "http://${aws_instance.server.public_ip}:3002"
}

output "prometheus_url" {
  description = "URL to access the Prometheus Metrics UI"
  value       = "http://${aws_instance.server.public_ip}:9090"
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    server_ip = aws_instance.server.public_ip
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
