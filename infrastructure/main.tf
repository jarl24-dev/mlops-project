# Make sure to create state bucket beforehand
terraform {
  required_version = ">= 1.0"
  backend "s3" {
    bucket  = "tf-state-mlops-zoomcamp-jarl24dev"
    key     = "mlops-zoomcamp-stg.tfstate"
    region  = "us-east-2"
    encrypt = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.9.0"
    }
    # Agrega el proveedor TLS para la generación de claves
    tls = {
      source = "hashicorp/tls"
      version = "4.0.0" 
    }
    # Agrega el proveedor local para guardar la clave privada
    local = {
      source = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

# Configuración del proveedor de AWS
provider "aws" {
  region = var.aws_region
}

# ----------------------------------------------------
# Obtención de datos dinámicos (para portabilidad)
# ----------------------------------------------------

# Obtiene la identidad de la cuenta actual
data "aws_caller_identity" "current_identity" {}

# Variable local para almacenar el ID de la cuenta
locals {
  account_id = data.aws_caller_identity.current_identity.account_id
}

# Obtiene la VPC por defecto de la cuenta
data "aws_vpc" "default" {
  default = true
}

# Obtiene las subredes de la VPC por defecto
data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ----------------------------------------------------
# Creación de recursos
# ----------------------------------------------------
# model bucket para guardar artifacts mlflow y datos 
module "s3_bucket" {
  source = "./modules/s3"
  bucket_name = "${local.account_id}-${var.project_id}"
}

# Grupo de seguridad para la instancia EC2
resource "aws_security_group" "mlflow_sg" {
  name        = "mlflow-ec2-security-group"
  description = "Permite acceso SSH y a la app MLflow"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = [data.aws_vpc.default.cidr_block]
    description     = "Permite la salida a la base de datos de MLflow"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Permite la salida para actualizar paquetes y descargar codigo"
  }
}

# Grupo de seguridad para la base de datos
resource "aws_security_group" "db_security_group" {
  name        = "mlflow-db-security-group"
  description = "Permite la conexion de la instancia EC2 a la DB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.mlflow_sg.id]
  }
  # Se agrega la regla egress para ser explícito
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Grupo de subredes para la base de datos
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "mlflow-db-subnet-group"
  subnet_ids = data.aws_subnets.all.ids
}

# Instancia de la base de datos PostgreSQL
resource "aws_db_instance" "mlflow_db" {
  engine                = "postgres"
  engine_version        = "17.4"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  db_name               = var.db_name
  username              = var.db_username
  password              = var.db_password 
  skip_final_snapshot   = true
  db_subnet_group_name  = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_security_group.id]
}

# Genera un nuevo par de claves SSH
resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Sube la clave pública a AWS
resource "aws_key_pair" "my_key_pair" {
  key_name   = "mlflow-key"
  public_key = tls_private_key.key_pair.public_key_openssh
}

# Guarda la clave privada en un archivo local
resource "local_file" "private_key_pem" {
  filename        = "mlflow-key.pem"
  content         = tls_private_key.key_pair.private_key_pem
  file_permission = "0600"
}

# Instancia EC2 para la aplicación
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-server-*"]
  }
}

resource "aws_instance" "mlflow_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.mlflow_sg.id]
  key_name               = aws_key_pair.my_key_pair.key_name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y python3-pip python3-dev libpq-dev
              pip3 install mlflow boto3 psycopg2-binary
              
              nohup mlflow server \
                --backend-store-uri postgresql://${aws_db_instance.mlflow_db.username}:${aws_db_instance.mlflow_db.password}@${aws_db_instance.mlflow_db.address}:${aws_db_instance.mlflow_db.port}/${var.db_name} \
                --artifacts-destination s3://${module.s3_bucket.name}/mlflow-artifacts \
                --host 0.0.0.0 > /dev/null 2>&1 &
              EOF
}

# Reserva una IP elástica y la asocia a la instancia EC2
resource "aws_eip" "mlflow_server_ip" {
  instance = aws_instance.mlflow_server.id
}