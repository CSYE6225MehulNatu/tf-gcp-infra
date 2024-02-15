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
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp" {
  name          = var.webapp_name
  region        = var.region
  network       = google_compute_network.vpc-first.self_link
  ip_cidr_range = var.webapp_subnet_cidr
}

resource "google_compute_subnetwork" "db" {
  name          = var.db_Name
  region        = var.region
  network       = google_compute_network.vpc-first.self_link
  ip_cidr_range = var.db_subnet_cidr
}

resource "google_compute_route" "webapp_route" {
  name             = "webapp-route"
  network          = google_compute_network.vpc-first.self_link
  dest_range       = "0.0.0.0/0"
  priority         = 1000
  next_hop_gateway = "default-internet-gateway"

}