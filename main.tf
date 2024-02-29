terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

provider "google" {
  credentials = file("./credentials.json")

  project = var.project_id
  region  = var.region
  zone    = var.zone
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

resource "google_compute_subnetwork" "db" {
  name                     = var.db_subnet_name
  region                   = var.region
  network                  = google_compute_network.vpc-first.self_link
  ip_cidr_range            = var.db_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_services_access_ip_range" {
  //provider      = google-beta
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

data "google_compute_image" "latest_image" {
  family  = var.webapp_image_family
  project = var.project_id
}

resource "google_compute_instance" "instance" {
  boot_disk {
    initialize_params {
      image = data.google_compute_image.latest_image.self_link
      size  = 100
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  depends_on = [ google_sql_database_instance.db-instance ]
  machine_type = "e2-medium"
  name         = var.instance_name
  tags         = ["http-server"]
  zone         = var.zone

  metadata_startup_script = templatefile("./webappInstanceStartUpScript.sh", {"password" = google_sql_user.user.password, 
  "sqlUser" = google_sql_user.user.name, 
  "dbName" = google_sql_database.g-sql-database.name, 
  "host" = google_sql_database_instance.db-instance.private_ip_address})


  network_interface {
    access_config {
    }

    network     = google_compute_network.vpc-first.self_link
    queue_count = 0
    stack_type  = "IPV4_ONLY"
    subnetwork  = google_compute_subnetwork.webapp.self_link
  }
}


resource "google_compute_firewall" "fireWall-webapp" {
  name        = var.firewall_name
  network     = google_compute_network.vpc-first.self_link
  description = "Allow SSH access from specific IP ranges"

  allow {
    protocol = "tcp"
    ports    = [var.port, "80"]
  }

  source_ranges = ["0.0.0.0/0"]
}


resource "google_sql_database" "g-sql-database" {
  name     = var.sql_database_name
  instance = google_sql_database_instance.db-instance.name
}

resource "google_sql_database_instance" "db-instance" {
  name             = "db-instance"
  region           = var.region
  database_version = "MYSQL_8_0"
  depends_on       = [google_service_networking_connection.default]
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = var.db_ipv4_enabled
      private_network = google_compute_network.vpc-first.self_link
    }

    disk_size = var.db_disk_size
    disk_type = var.db_disk_type
    availability_type = var.availability_type
  }

  deletion_protection = var.sql_database_deletion_protection
}


resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_sql_user" "user" {
  name     = var.sql_user_name
  instance = google_sql_database_instance.db-instance.name
  password = random_password.password.result
}

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