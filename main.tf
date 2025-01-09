provider "oci" {
  version = "~> 5.0"  # Use a version that supports identity resources
  auth = "InstancePrincipal"
  region = var.region
}

variable "region" {
  default = "eu-frankfurt-1"  # Specify the region
}

variable "compartment_id" {
  description = "Compartment OCID where the infrastructure will be deployed"
  default = "ocid1.tenancy.oc1..aaaaaaaaancvivxhuaqaq47c5p6smmm4sf7yesh6e75sluc2lisckbcx5zbq"
}

variable "availability_domain" {
  description = "Availability domain for the compute instance"
  default = "AD-3"
}

variable "admin_password" {
  description = "Admin password for the Autonomous Database"
  sensitive = true
  default = "441319@Ss"
}

variable "notification_topic_id" {
  description = "OCID of the notification topic for monitoring alerts"
  default = "ocid1.onstopic.oc1.eu-frankfurt-1.amaaaaaakxm3yfqapdgy4xiwb5xcfpa2y5uqos6n7bkxdprf23zo7bc6hkra"
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
}

resource "oci_load_balancer_backend_set" "backend_set" {
  load_balancer_id = oci_load_balancer_load_balancer.free_tier_lb.id
  name             = "backend1"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol = "HTTP"
    port     = 80
    url_path = "/health"
  }
}

# Monitoring
resource "oci_monitoring_alarm" "cpu_alarm" {
  compartment_id          = var.compartment_id
  display_name            = "High CPU Alarm"
  metric_compartment_id   = var.compartment_id
  namespace               = "oci_computeagent"
  query                   = "CpuUtilization[1m]{resourceId = \"${oci_core_instance.free_tier_instance.id}\"}.mean() > 90"
  severity                = "CRITICAL"
  destinations            = [var.notification_topic_id]
  repeat_notification_duration = "PT15M"
  is_enabled              = true
}

# IAM Group and Role
resource "oci_identity_group" "db_vcn_group" {
  name        = "DB_VCN_Group"
  description = "Group for creating VCN and ADB instances"
}

resource "oci_identity_custom_role" "db_vcn_role" {
  compartment_id = var.compartment_id
  name           = "DB_VCN_Creator"
  description    = "Role to create and manage VCN and ADB"
  
  permissions = [
    "oci:core:vcn:manage",                # Manage VCN
    "oci:core:subnet:manage",             # Manage Subnets (optional)
    "oci:database:autonomous-database:manage"  # Manage Autonomous Databases
  ]
}

resource "oci_identity_policy" "db_vcn_policy" {
  compartment_id = var.compartment_id
  name           = "DB_VCN_Policy"
  description    = "Policy to allow group to manage VCN and Autonomous Database"
  
  statements = [
    "Allow group DB_VCN_Group to manage virtual-network-family in compartment ${var.compartment_id}",
    "Allow group DB_VCN_Group to manage autonomous-database in compartment ${var.compartment_id}"
  ]
}

resource "oci_identity_group_membership" "group_role_membership" {
  group_id = oci_identity_group.db_vcn_group.id
  user_id  = "ocid1.user.oc1..aaaaaaaavic4n4t247hl7fmovtiqfv3pbi2kxsw6imdjmwcs4sfgodijgkwq"  # Replace with actual user ID
}

# Outputs
output "vcn_id" {
  value = oci_core_vcn.main_vcn.id
}

output "instance_ip" {
  value = oci_core_instance.free_tier_instance.public_ip
}

output "adb_ocid" {
  value = oci_database_autonomous_database.free_tier_adb.id
}
