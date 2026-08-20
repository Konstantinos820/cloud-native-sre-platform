variable "name_prefix" {
  description = "Naming prefix used for Azure Storage resources."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix may contain only letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where Storage resources are created."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet used for the Blob Storage private endpoint."
  type        = string
}

variable "virtual_network_id" {
  description = "Resource ID of the virtual network linked to the Blob private DNS zone."
  type        = string
}

variable "container_name" {
  description = "Name of the private application Blob container."
  type        = string
  default     = "app-data"
}

variable "replication_type" {
  description = "Storage account replication type."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be a supported Azure Storage replication type."
  }
}

variable "tags" {
  description = "Tags applied to Storage resources."
  type        = map(string)
  default     = {}
}
