variable "credentials_file_path" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "webapp_name" {
  type = string
}

variable "webapp_route_name" {
  type = string
}

variable "db_subnet_name" {
  type = string
}


variable "webapp_subnet_cidr" {
  type = string
}

variable "db_subnet_cidr" {
  type = string
}

variable "service_account" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "firewall_name" {
  type = string
}

variable "port" {
  type = string
}

variable "webapp_image_family" {
  type = string
}

variable "routing_mode" {
  type = string
}

variable "db_disk_size" {
  type = number
}

variable "db_disk_type" {
  type = string
}

variable "db_ipv4_enabled" {
  type = bool
}

variable "sql_user_name" {
  type = string
}

variable "sql_database_name" {
  type = string
}

