variable "name_prefix" {
  description = "Naming prefix used for PostgreSQL resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where PostgreSQL resources are created."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Resource ID of the subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "virtual_network_id" {
  description = "Resource ID of the virtual network linked to PostgreSQL private DNS."
  type        = string
}

variable "administrator_login" {
  description = "Administrator login for PostgreSQL Flexible Server."
  type        = string
  default     = "appadmin"
}

variable "administrator_password" {
  description = "Administrator password supplied securely at deployment time."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "administrator_password_version" {
  description = "Increment this value whenever the administrator password is rotated."
  type        = number
  default     = 1
}

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "PostgreSQL Flexible Server SKU."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Allocated PostgreSQL storage in MB."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "Number of days PostgreSQL backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "database_name" {
  description = "Application PostgreSQL database name."
  type        = string
  default     = "app_db"
}

variable "tags" {
  description = "Tags applied to PostgreSQL resources."
  type        = map(string)
  default     = {}
}
