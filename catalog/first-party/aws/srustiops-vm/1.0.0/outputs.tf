output "instance_id" {
  description = "Reach it with: aws ssm start-session --target <id>"
  value       = aws_instance.this.id
}
output "private_ip" {
  value = aws_instance.this.private_ip
}
