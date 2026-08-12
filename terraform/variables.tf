variable "resource_group_name" {
  description = "Name of the resource group everything deploys into."
  type        = string
  default     = "rg-sentinel-hub-lab"
}

variable "location" {
  description = "Azure region for the lab."
  type        = string
  default     = "South Africa North"
}

variable "vm_size" {
  description = "VM size for the identity servers. Standard_DS2_v2 confirmed available with quota headroom in South Africa North as of Aug 2026 - Standard_B2ms, Standard_D2s_v3, and Standard_D2s_v5 were all tried first and failed on either capacity or quota."
  type        = string
  default     = "Standard_DS2_v2"
}

variable "admin_username" {
  description = "Local admin username for the identity VMs."
  type        = string
}

variable "admin_password" {
  description = "Local admin password for the identity VMs. Set via terraform.tfvars, never commit a real value."
  type        = string
  sensitive   = true
}
