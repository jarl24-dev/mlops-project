# variables.tf

variable "aws_region" {
  description = "La región de AWS donde se crearán los recursos."
  type        = string
  default     = "us-east-2"
}

variable "project_id" {
  description = "project_id"
  default = "mlops-zoomcamp"
}

variable "db_name" {
  description = "El nombre de la base de datos de MLflow."
  type        = string
  default     = "mlflowdb"
}

variable "db_username" {
  description = "El nombre de usuario de la base de datos de MLflow."
  type        = string
  default     = "mlflow"
}

variable "db_password" {
  description = "La contraseña de la base de datos de MLflow."
  type        = string
  sensitive   = true
}
