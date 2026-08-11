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
  description = "VM size for the identity servers."
  type        = string
  default     = "Standard_B2ms"
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
