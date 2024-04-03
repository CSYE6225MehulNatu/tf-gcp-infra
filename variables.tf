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

variable "sql_database_deletion_protection" {
  type = string
}

variable "availability_type" {
  type = string
}

variable "webapp_instance_service_account" {
  type = string
}

variable "dns_name" {
  type = string
}

variable "dns_type" {
  type = string
}

variable "managed_zone" {
  type = string
}

variable "log_file_Path_webapp" {
  type = string
}

variable "email_verifiction_topic" {
  type = string
}

variable "email_verifiction_schema" {
  type = string
}

variable "email_verification_function_service_account" {
  type = string
}

variable "ev_function_node_version" {
  type = string
}

variable "ev_function_entry_point" {
  type = string
}

variable "ev_function_zip_path" {
  type = string
}

variable "google_storage_bucket_name" {
  type = string
}

variable "mailgun_api_key" {
  type = string
}


variable "domain_name" {
  type = string
}

variable "webapp_insatance_template_name" {
  type = string
}

variable "webapp_cpu_usage_autoscaler_name" {
  type = string
}

variable "min_webapp_instance" {
  type = number
}

variable "max_webapp_instance" {
  type = number
}

variable "webapp_cpu_utilization_threshold" {
  type = number
}

variable "distribution_policy_zones" {
  type = list(string)
}

variable "proxy_only_cidr_range" {
  type = string
}

variable "named_port_instance_group" {
  type = string
}

variable "port_num" {
  type = number
}

variable "lb_global_address_name" {
  type = string
}

variable "global_forwading_rule_name" {
  type = string
}
variable "ssl_certi_name" {
  type = string
}

variable "https_target_proxy_name" {
  type = string
}

variable "backend_service_name" {
  type = string
}

variable "instance_group_manager" {
  type = string
}