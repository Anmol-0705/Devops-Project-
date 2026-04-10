output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_eip.smart_task_manager_eip.public_ip
}

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.smart_task_manager.id
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.smart_task_manager_eip.public_ip}"
}

output "app_url" {
  description = "URL to access the application"
  value       = "http://${aws_eip.smart_task_manager_eip.public_ip}"
}
