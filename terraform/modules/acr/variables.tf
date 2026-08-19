variable "name_prefix" {
  description = "Naming prefix used for Azure Container Registry resources."
  type        = string

  validation {
    condition     = length(trimspace(var.name_prefix)) > 0
    error_message = "name_prefix must not be empty."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where ACR resources are created."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet used for the ACR private endpoint."
  type        = string
}

variable "virtual_network_id" {
  description = "Resource ID of the virtual network linked to the ACR private DNS zone."
  type        = string
}

variable "tags" {
  description = "Tags applied to ACR resources."
  type        = map(string)
  default     = {}
}
