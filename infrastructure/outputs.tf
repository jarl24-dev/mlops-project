# Muestra la IP pública de la instancia EC2
output "public_ip" {
  description = "La IP pública para acceder al servidor de MLflow."
  value       = aws_eip.mlflow_server_ip.public_ip
}

# Muestra el endpoint de la base de datos RDS
output "db_endpoint" {
  description = "El endpoint de la base de datos de MLflow."
  value       = aws_db_instance.mlflow_db.address
}

# Muestra la URL para acceder a la UI de MLflow
output "mlflow_ui_url" {
  description = "La URL para acceder a la UI de MLflow."
  value       = "http://${aws_eip.mlflow_server_ip.public_ip}:5000"
}