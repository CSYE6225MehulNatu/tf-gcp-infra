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


resource "google_dns_record_set" "a_record" {
  name         = var.dns_name
  type         = var.dns_type
  ttl          = 300
  managed_zone = var.managed_zone
  rrdatas      = [google_compute_instance.instance.network_interface[0].access_config[0].nat_ip]
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


resource "google_service_account" "webapp_service_account" {
  account_id   = var.webapp_instance_service_account
  display_name = "Service Account for webapp insatnce"
  project      = var.project_id
}


data "google_compute_image" "latest_image" {
  family  = var.webapp_image_family
  project = var.project_id
}


resource "google_compute_firewall" "fireWall-webapp" {
  name        = var.firewall_name
  network     = google_compute_network.vpc-first.self_link
  description = "Allow SSH access from specific IP ranges"

  allow {
    protocol = "tcp"
    ports    = [var.port, "80", 22]
  }

  source_ranges = ["0.0.0.0/0"]
}


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
  length           = 16
  special          = false
}



resource "google_sql_user" "user" {
  name     = var.sql_user_name
  instance = google_sql_database_instance.sql-db-instance.name
  password = random_password.password.result
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