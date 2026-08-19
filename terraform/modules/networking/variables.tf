variable "name_prefix" {
  description = "Naming prefix applied to networking resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where networking resources are created."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space assigned to the virtual network."
  type        = list(string)
}

variable "aks_subnet_prefixes" {
  description = "CIDR prefixes assigned to the AKS node subnet."
  type        = list(string)
}

variable "postgresql_subnet_prefixes" {
  description = "CIDR prefixes assigned to the PostgreSQL delegated subnet."
  type        = list(string)
}

variable "private_endpoints_subnet_prefixes" {
  description = "CIDR prefixes assigned to the private endpoints subnet."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to networking resources."
  type        = map(string)
  default     = {}
}
