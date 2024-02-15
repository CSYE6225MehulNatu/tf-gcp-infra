variable "credentials_file_path" {
  type     = string
  nullable = false
}

variable "project_id" {
  type     = string
  nullable = false
}

variable "region" {
  type     = string
  nullable = false
}

variable "zone" {
  type     = string
  nullable = false
}

variable "vpc_name" {
  type     = string
  nullable = false
}

variable "webapp_name" {
  type     = string
  nullable = false
}

variable "db_Name" {
  type     = string
  nullable = false
}


variable "webapp_subnet_cidr" {
  type     = string
  nullable = false
}

variable "db_subnet_cidr" {
  type     = string
  nullable = false
}