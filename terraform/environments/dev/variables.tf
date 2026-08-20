variable "subscription_id" {
  description = "Azure subscription ID used by the AzureRM provider."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.subscription_id)) > 0
    error_message = "subscription_id must not be empty."
  }
}

variable "project_name" {
  description = "Base name used for Azure resources."
  type        = string
  default     = "sre-platform"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region used for the development environment."
  type        = string
  default     = "westeurope"
}

variable "vnet_address_space" {
  description = "Address space for the development virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

variable "aks_subnet_prefixes" {
  description = "CIDR prefixes for the AKS node subnet."
  type        = list(string)
  default     = ["10.20.0.0/23"]
}

variable "postgresql_subnet_prefixes" {
  description = "CIDR prefixes for the PostgreSQL delegated subnet."
  type        = list(string)
  default     = ["10.20.2.0/24"]
}

variable "private_endpoints_subnet_prefixes" {
  description = "CIDR prefixes for the private endpoints subnet."
  type        = list(string)
  default     = ["10.20.3.0/24"]
}

variable "aks_kubernetes_version" {
  description = "Optional Kubernetes version. Null lets AKS choose the recommended version at provisioning time."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "AKS control plane SKU tier."
  type        = string
  default     = "Free"
}

variable "aks_system_node_vm_size" {
  description = "VM size used by the AKS system node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "aks_system_node_min_count" {
  description = "Minimum number of AKS system nodes."
  type        = number
  default     = 2
}

variable "aks_system_node_max_count" {
  description = "Maximum number of AKS system nodes."
  type        = number
  default     = 5
}

variable "aks_max_pods_per_node" {
  description = "Maximum number of Kubernetes pods scheduled per AKS node."
  type        = number
  default     = 110

  validation {
    condition     = var.aks_max_pods_per_node >= 50 && var.aks_max_pods_per_node <= 250
    error_message = "aks_max_pods_per_node must be between 50 and 250."
  }
}

variable "aks_user_node_vm_size" {
  description = "VM size used by the AKS application user node pool."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "aks_user_node_min_count" {
  description = "Minimum number of AKS application user nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.aks_user_node_min_count >= 1
    error_message = "aks_user_node_min_count must be at least 1."
  }
}

variable "aks_user_node_max_count" {
  description = "Maximum number of AKS application user nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.aks_user_node_max_count >= var.aks_user_node_min_count
    error_message = "aks_user_node_max_count must be greater than or equal to aks_user_node_min_count."
  }
}

variable "aks_pod_cidr" {
  description = "CIDR used by Azure CNI Overlay pods."
  type        = string
  default     = "10.244.0.0/16"
}

variable "aks_service_cidr" {
  description = "CIDR used by Kubernetes Services."
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_dns_service_ip" {
  description = "IP address used by CoreDNS."
  type        = string
  default     = "10.0.0.10"
}

variable "aks_admin_group_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS administrator access."
  type        = list(string)
  default     = []
}

variable "postgresql_administrator_login" {
  description = "Administrator login for PostgreSQL Flexible Server."
  type        = string
  default     = "appadmin"
}

variable "postgresql_administrator_password" {
  description = "PostgreSQL administrator password supplied securely at runtime."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "postgresql_administrator_password_version" {
  description = "Increment when rotating the PostgreSQL administrator password."
  type        = number
  default     = 1
}

variable "postgresql_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "postgresql_sku_name" {
  description = "PostgreSQL Flexible Server SKU."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage allocation in MB."
  type        = number
  default     = 32768
}

variable "postgresql_backup_retention_days" {
  description = "PostgreSQL backup retention period."
  type        = number
  default     = 7
}

variable "postgresql_database_name" {
  description = "Application PostgreSQL database name."
  type        = string
  default     = "app_db"
}

variable "storage_container_name" {
  description = "Name of the private application Blob container."
  type        = string
  default     = "app-data"
}

variable "storage_replication_type" {
  description = "Replication type used by the application Storage Account."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be a supported Azure Storage replication type."
  }
}

variable "aks_node_os_disk_size_gb" {
  description = "OS disk size used by AKS node pools."
  type        = number
  default     = 60

  validation {
    condition     = var.aks_node_os_disk_size_gb >= 30
    error_message = "aks_node_os_disk_size_gb must be at least 30 GB."
  }
}