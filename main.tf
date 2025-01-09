# OCI Free Tier Production-Grade Infrastructure using Instance Principal

provider "oci" {
  auth = "InstancePrincipal"  # Use Instance Principal for authentication
  region = var.region
}

variable "region" {
  default = "eu-frankfurt-1"  # Specify the region
}

variable "compartment_id" {
  description = "Compartment OCID where the infrastructure will be deployed"
}

variable "availability_domain" {
  description = "Availability domain for the compute instance"
}

variable "admin_password" {
  description = "Admin password for the Autonomous Database"
  sensitive = true
}

variable "notification_topic_id" {
  description = "OCID of the notification topic for monitoring alerts"
}

# Networking
resource "oci_core_vcn" "main_vcn" {
  cidr_block   = "10.0.0.0/16"
  display_name = "FreeTier-VCN"
  dns_label    = "freetiervcn"
  compartment_id = var.compartment_id
}

resource "oci_core_internet_gateway" "internet_gateway" {
  display_name   = "FreeTier-InternetGateway"
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main_vcn.id
  is_enabled     = true
}

resource "oci_core_subnet" "public_subnet" {
  cidr_block        = "10.0.1.0/24"
  display_name      = "PublicSubnet"
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main_vcn.id
  dns_label         = "publicsubnet"
  prohibit_public_ip_on_vnic = false
}

# Compute Instance
resource "oci_core_instance" "free_tier_instance" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "FreeTier-Instance"
  shape               = "VM.Standard.E2.1.Micro"  # Free Tier Shape

  create_vnic_details {
    subnet_id = oci_core_subnet.public_subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux_image.id
  }
}

data "oci_core_images" "oracle_linux_image" {
  compartment_id = var.compartment_id
  operating_system = "Oracle Linux"
  operating_system_version = "8"
}

# Autonomous Database
resource "oci_database_autonomous_database" "free_tier_adb" {
  compartment_id       = var.compartment_id
  db_name              = "FreeTierDB"
  admin_password       = var.admin_password
  cpu_core_count       = 1  # Free Tier Limit
  data_storage_size_in_tbs = 1
  display_name         = "FreeTierAutonomousDB"
  is_free_tier         = true
  db_workload          = "OLTP"
}

# Load Balancer
resource "oci_load_balancer_load_balancer" "free_tier_lb" {
  compartment_id = var.compartment_id
  display_name   = "FreeTier-LB"
  shape          = "flexible"

  subnet_ids = [oci_core_subnet.public_subnet.id]

  backend_set {
    name = "backend1"
    policy = "ROUND_ROBIN"
    health_checker {
      protocol = "HTTP"
      port     = 80
      url_path = "/health"
    }
  }
}

# Monitoring
resource "oci_monitoring_alarm" "cpu_alarm" {
  compartment_id = var.compartment_id
  display_name   = "High CPU Alarm"
  metric_compartment_id = var.compartment_id
  namespace      = "oci_computeagent"
  query          = "CpuUtilization[1m]{resourceId = \"${oci_core_instance.free_tier_instance.id}\"}.mean() > 90"
  severity       = "CRITICAL"

  destinations = [var.notification_topic_id]
  repeat_notification_duration = "PT15M"
}

output "vcn_id" {
  value = oci_core_vcn.main_vcn.id
}

output "instance_ip" {
  value = oci_core_instance.free_tier_instance.public_ip
}

output "adb_ocid" {
  value = oci_database_autonomous_database.free_tier_adb.id
}
