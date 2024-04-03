terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.18.0"
    }
  }
}

provider "google" {
  credentials = file("./credentials.json")

  project = var.project_id
  region  = var.region
  zone    = var.zone
}



resource "google_dns_record_set" "a_record" {
  name         = var.dns_name
  type         = var.dns_type
  ttl          = 300
  managed_zone = var.managed_zone
  rrdatas      = [google_compute_global_forwarding_rule.default.ip_address]
}




resource "google_compute_network" "vpc-first" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  name          = var.webapp_name
  region        = var.region
  network       = google_compute_network.vpc-first.self_link
  ip_cidr_range = var.webapp_subnet_cidr
}


/*

  Proxy only subnet

*/
/*
resource "google_compute_subnetwork" "proxy-only" {
  name          = "${var.region}-proxy-only"
  region        = var.region
  network       = google_compute_network.vpc-first.self_link
  ip_cidr_range = var.proxy_only_cidr_range
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}
*/

resource "google_compute_subnetwork" "db" {
  name                     = var.db_subnet_name
  region                   = var.region
  network                  = google_compute_network.vpc-first.self_link
  ip_cidr_range            = var.db_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_services_access_ip_range" {
  project       = var.project_id
  name          = "global-psconnect-ip"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  network       = google_compute_network.vpc-first.self_link
  prefix_length = 16
}

resource "google_service_networking_connection" "default" {
  network                 = google_compute_network.vpc-first.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_access_ip_range.name]
}

resource "google_compute_route" "webapp_route" {
  name             = var.webapp_route_name
  network          = google_compute_network.vpc-first.self_link
  dest_range       = "0.0.0.0/0"
  priority         = 1000
  next_hop_gateway = "default-internet-gateway"
}


/*
  vpc access connector for cloud function to connect to VPC
*/

resource "google_vpc_access_connector" "connector" {
  name = "vpc-con-function"
  //network = google_compute_network.vpc-first.self_link

  subnet {
    name       = google_compute_subnetwork.webapp.name
    project_id = var.project_id
  }

  max_throughput = 300
  machine_type   = "e2-standard-4"
}

/*
  Creating a public static ip for nat
*/

resource "google_compute_address" "public_cloud_nat" {
  name   = "${var.region}-public-cloud-nat"
  region = var.region
}

/*
  Creating a router and NAT for internet access from webapp
*/

resource "google_compute_router" "cloud_nat_router" {
  name    = "${var.region}-nat-router"
  region  = google_compute_subnetwork.webapp.region
  network = google_compute_network.vpc-first.id
}


resource "google_compute_router_nat" "public_cloud_nat" {
  name                               = "${var.region}-public-cloud-nat"
  router                             = google_compute_router.cloud_nat_router.name
  region                             = google_compute_router.cloud_nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.webapp.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}



/*
  firewall for proxy only and health check
*/

resource "google_compute_firewall" "health-check-firewall" {
  name = "fw-allow-health-check"
  allow {
    protocol = "tcp"
  }
  direction     = "INGRESS"
  network       = google_compute_network.vpc-first.id
  priority      = 1000
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["load-balanced-backend"]
}


resource "google_compute_firewall" "allow_proxy" {
  name = "fw-allow-proxies"
  allow {
    ports    = ["443"]
    protocol = "tcp"
  }
  allow {
    ports    = ["80"]
    protocol = "tcp"
  }
  allow {
    ports    = ["8080"]
    protocol = "tcp"
  }

  direction     = "INGRESS"
  network       = google_compute_network.vpc-first.id
  priority      = 1000
  source_ranges = [google_compute_global_forwarding_rule.default.ip_address]
  target_tags   = ["load-balanced-backend"]
}



resource "google_service_account" "webapp_service_account" {
  account_id   = var.webapp_instance_service_account
  display_name = "Service Account for webapp insatnce"
  project      = var.project_id
}


data "google_compute_image" "latest_image" {
  family  = var.webapp_image_family
  project = var.project_id
}

/*
resource "google_compute_firewall" "fireWall-webapp" {
  name        = var.firewall_name
  network     = google_compute_network.vpc-first.self_link
  description = "Allow SSH access from specific IP ranges"

  allow {
    protocol = "tcp"
    ports    = [22]
  }

  source_ranges = ["0.0.0.0/0"]
}
*/
resource "google_sql_database" "g-sql-database" {
  name     = var.sql_database_name
  instance = google_sql_database_instance.sql-db-instance.name
}

resource "google_sql_database_instance" "sql-db-instance" {
  name             = "sql-db-instance"
  region           = var.region
  database_version = "MYSQL_8_0"
  depends_on       = [google_service_networking_connection.default]
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = var.db_ipv4_enabled
      private_network = google_compute_network.vpc-first.self_link
    }

    backup_configuration {
      binary_log_enabled = true
      enabled            = true
    }

    disk_size         = var.db_disk_size
    disk_type         = var.db_disk_type
    availability_type = var.availability_type
  }

  deletion_protection = var.sql_database_deletion_protection
}


resource "random_password" "password" {
  length  = 16
  special = false
}



resource "google_sql_user" "user" {
  name     = var.sql_user_name
  instance = google_sql_database_instance.sql-db-instance.name
  password = random_password.password.result
}


/*
  Creating Instance Template
*/

resource "google_compute_region_instance_template" "webapp" {
  name        = var.webapp_insatance_template_name
  description = "This template is used to create webapp server instances."
  region      = var.region
  tags        = ["webapp-template", "http-server-template", "allow-health-check", "load-balanced-backend"]

  labels = {
    environment = "prod"
  }

  depends_on = [google_sql_database_instance.sql-db-instance, google_service_account.webapp_service_account,
  google_sql_user.user]

  instance_description = "webapp instance"
  machine_type         = "e2-medium"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    source_image = data.google_compute_image.latest_image.self_link
    auto_delete  = true
    boot         = true
    mode         = "READ_WRITE"
    disk_type    = "pd-balanced"
    disk_size_gb = 50
    // backup the disk every day
    //resource_policies = [google_compute_resource_policy.daily_backup.id]
  }

  network_interface {

    access_config {
    }

    network     = google_compute_network.vpc-first.self_link
    queue_count = 0
    stack_type  = "IPV4_ONLY"
    subnetwork  = google_compute_subnetwork.webapp.self_link
  }

  metadata_startup_script = templatefile("./webappInstanceStartUpScript.sh", { "password" = random_password.password.result,
    "sqlUser" = google_sql_user.user.name,
    "dbName"  = google_sql_database.g-sql-database.name,
    "host"    = google_sql_database_instance.sql-db-instance.private_ip_address,
  "logFilePath" = var.log_file_Path_webapp })

  service_account {
    email  = google_service_account.webapp_service_account.email
    scopes = ["logging-write", "monitoring-write", "cloud-platform"]
  }
}


/*
  Creating an Autoscaler for webapp - 
*/

resource "google_compute_region_autoscaler" "webapp-autoscaler" {
  name   = var.webapp_cpu_usage_autoscaler_name
  region = var.region
  target = google_compute_region_instance_group_manager.webapp.id

  autoscaling_policy {
    max_replicas    = var.max_webapp_instance
    min_replicas    = var.min_webapp_instance
    cooldown_period = 60

    cpu_utilization {
      target = var.webapp_cpu_utilization_threshold
    }
  }
}


/*
  Creating health check
*/

resource "google_compute_health_check" "webapp" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  http_health_check {
    request_path = "/healthz"
    port         = var.port
  }

  log_config {
    enable = true
  }
}


/*
  Creating region instance group manager
*/

resource "google_compute_region_instance_group_manager" "webapp" {
  name = var.instance_group_manager

  base_instance_name        = "app"
  region                    = var.region
  distribution_policy_zones = var.distribution_policy_zones

  version {
    name              = "webapp-nodejs20"
    instance_template = google_compute_region_instance_template.webapp.self_link
  }

  depends_on = [google_compute_region_instance_template.webapp]

  //target_pools = [google_compute_target_pool.webapp.id]
  //target_size  = 2

  named_port {
    name = var.named_port_instance_group
    port = var.port_num
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.webapp.id
    initial_delay_sec = 300
  }
}


/*
  Creating Topic Schema 
*/
resource "google_pubsub_schema" "email-schema" {
  name       = var.email_verifiction_schema
  type       = "AVRO"
  definition = "{  \"type\" : \"record\",  \"name\" : \"Avro\",  \"fields\" : [ { \"name\" : \"email\",  \"type\" : \"string\" } ]}"
}

/*
  Topic created for email verification
*/

resource "google_pubsub_topic" "email-verifiction-topic" {
  name                       = var.email_verifiction_topic
  message_retention_duration = "604800s"
  project                    = var.project_id

  depends_on = [google_pubsub_schema.email-schema]
  schema_settings {
    schema   = "projects/${var.project_id}/schemas/${var.email_verifiction_schema}"
    encoding = "JSON"
  }
}


/*

  creating a storage bucket and object for storing function

*/


resource "google_storage_bucket" "csye6225-function-bucket" {
  name          = var.google_storage_bucket_name
  location      = "US"
  force_destroy = true
}

resource "google_storage_bucket_object" "function-bucket-object" {
  name   = "index.zip"
  bucket = google_storage_bucket.csye6225-function-bucket.name
  source = var.ev_function_zip_path
}



/*
  creating service account for cloud function - 
*/

resource "google_service_account" "ev_function_service_account" {
  account_id   = var.email_verification_function_service_account
  display_name = "Service Account for email verification cloud function"
  project      = var.project_id
}


/*
  Creating function
*/


resource "google_cloudfunctions2_function" "function" {
  name        = "email-verification-function"
  location    = var.region
  description = "function for sending verifiction email to user function"
  project     = var.project_id

  depends_on = [google_pubsub_topic.email-verifiction-topic, google_sql_user.user,
  google_sql_database_instance.sql-db-instance, google_storage_bucket_object.function-bucket-object]


  build_config {
    runtime     = var.ev_function_node_version
    entry_point = var.ev_function_entry_point # Set the entry point 
    source {
      storage_source {
        bucket = google_storage_bucket.csye6225-function-bucket.name
        object = google_storage_bucket_object.function-bucket-object.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.ev_function_service_account.email
    vpc_connector         = google_vpc_access_connector.connector.self_link
    //vpc_connector = 
    environment_variables = {
      DB_HOST         = google_sql_database_instance.sql-db-instance.private_ip_address
      DB_USER         = google_sql_user.user.name
      DB_PASSWORD     = random_password.password.result
      DB_NAME         = google_sql_database.g-sql-database.name
      MAILGUN_API_KEY = var.mailgun_api_key
      DOMAIN_PORT     = var.port
      DOMAIN_NAME     = var.domain_name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.email-verifiction-topic.id
  }
}

output "function_uri" {
  value = google_cloudfunctions2_function.function.service_config[0].uri
}


/*
  Iam bindings for service account
*/

resource "google_project_iam_binding" "logging_admin_iam_role" {
  project = var.project_id
  role    = "roles/logging.admin"

  members = [
    google_service_account.webapp_service_account.member,
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer_role" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"

  members = [
    google_service_account.webapp_service_account.member,
  ]
}

resource "google_project_iam_binding" "cloudsql-editor" {
  project = var.project_id
  role    = "roles/cloudsql.editor"

  members = [
    google_service_account.webapp_service_account.member,
    google_service_account.ev_function_service_account.member
  ]
}

resource "google_project_iam_binding" "pubsub-publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"

  members = [
    google_service_account.webapp_service_account.member,
  ]
}

/*
  Load balancer Configuration

*/

resource "google_compute_global_address" "lb-ip" {
  name = var.lb_global_address_name
}


# forwarding rule

resource "google_compute_global_forwarding_rule" "default" {
  name                  = var.global_forwading_rule_name
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.target-https-proxy.id
  //ip_address            = google_compute_global_address.lb-ip.id
}

#ssl certificate
resource "google_compute_managed_ssl_certificate" "default" {
  name = var.ssl_certi_name
  managed {
    domains = [var.domain_name]
  }
}

# http proxy
resource "google_compute_target_https_proxy" "target-https-proxy" {
  name             = var.https_target_proxy_name
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
}

# url map
resource "google_compute_url_map" "default" {
  name            = "url-map"
  default_service = google_compute_backend_service.default.id
}


# backend service with custom request and response headers
resource "google_compute_backend_service" "default" {
  name                  = var.backend_service_name
  protocol              = "HTTP"
  port_name             = var.named_port_instance_group
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  //enable_cdn              = true
  health_checks = [google_compute_health_check.webapp.self_link]
  backend {
    group           = google_compute_region_instance_group_manager.webapp.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1
  }
}




/*
resource "google_project_iam_binding" "cloud-functions" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"

  members = [
    google_service_account.ev_function_service_account.member,
  ]
}

/*
# IAM entry for all users to invoke the function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}


/*
  Creating subscription for the topic
*/
/*
resource "google_pubsub_subscription" "email_verifiction_subscription" {
  name  = "email-verifiction-subscription"
  topic = google_pubsub_topic.email-verifiction-topic.id

  ack_deadline_seconds = 60

  labels = {
    consumed_form = google_pubsub_topic.email-verifiction-topic.name
    pushed_to = google_cloudfunctions2_function.function.name
  }

  push_config {
    push_endpoint = google_cloudfunctions2_function.function.service_config[0].uri

    
  }
}

/*
    attributes = {
      x-goog-version = "v1"
    }
*/




/*
resource "google_service_account" "default" {
  account_id   = var.service_account
  display_name = "VPC-Instance Service account"
}
 {
    service_account
    #scopes = ["https://www.googleapis.com/auth/devstorage.read_only", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/service.management.readonly", "https://www.googleapis.com/auth/servicecontrol", "https://www.googleapis.com/auth/trace.append"]

  }
  */

/*
resource "google_compute_instance" "instance" {
  boot_disk {
    initialize_params {
      image = data.google_compute_image.latest_image.self_link
      size  = 100
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  depends_on = [google_sql_database_instance.sql-db-instance, google_service_account.webapp_service_account,
  google_sql_user.user]
  machine_type = "e2-medium"
  name         = var.instance_name
  tags         = ["http-server"]
  zone         = var.zone


  metadata_startup_script = templatefile("./webappInstanceStartUpScript.sh", { "password" = random_password.password.result,
    "sqlUser" = google_sql_user.user.name,
    "dbName"  = google_sql_database.g-sql-database.name,
    "host"    = google_sql_database_instance.sql-db-instance.private_ip_address,
  "logFilePath" = var.log_file_Path_webapp })


  service_account {
    email  = google_service_account.webapp_service_account.email
    scopes = ["logging-write", "monitoring-write", "cloud-platform"]
  }


  network_interface {
    access_config {
    }

    network     = google_compute_network.vpc-first.self_link
    queue_count = 0
    stack_type  = "IPV4_ONLY"
    subnetwork  = google_compute_subnetwork.webapp.self_link
  }
}

*/