variable "subscription_id" {
  description = "Azure subscription ID used for the Terraform state bootstrap."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.subscription_id)) > 0
    error_message = "subscription_id must not be empty."
  }
}

variable "location" {
  description = "Azure region used for Terraform state infrastructure."
  type        = string
  default     = "westeurope"
}

variable "name_prefix" {
  description = "Naming prefix used for Terraform state resources."
  type        = string
  default     = "sre-platform-tfstate"
}

variable "container_name" {
  description = "Blob container used to store Terraform state files."
  type        = string
  default     = "tfstate"
}

variable "public_network_access_enabled" {
  description = "Whether the backend Storage Account exposes its public network endpoint."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to Terraform state infrastructure."
  type        = map(string)

  default = {
    project    = "cloud-native-sre-platform"
    purpose    = "terraform-state"
    managed_by = "terraform"
  }
}
