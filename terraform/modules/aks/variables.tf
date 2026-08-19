variable "name_prefix" {
  description = "Naming prefix used for AKS resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where AKS resources are created."
  type        = string
}

variable "aks_subnet_id" {
  description = "Resource ID of the subnet used by AKS nodes."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the Azure Container Registry."
  type        = string
}

variable "kubernetes_version" {
  description = "Optional Kubernetes version. Null lets AKS select the recommended version at provisioning time."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS control plane SKU tier."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard, or Premium."
  }
}

variable "system_node_vm_size" {
  description = "VM size used by the AKS system node pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "system_node_min_count" {
  description = "Minimum number of nodes in the AKS system node pool."
  type        = number
  default     = 2
}

variable "system_node_max_count" {
  description = "Maximum number of nodes in the AKS system node pool."
  type        = number
  default     = 5
}

variable "pod_cidr" {
  description = "CIDR used by Azure CNI Overlay pods."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR used by Kubernetes Services."
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address used by kube-dns/CoreDNS."
  type        = string
  default     = "10.0.0.10"
}

variable "admin_group_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS administrator access."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to AKS resources."
  type        = map(string)
  default     = {}
}

variable "max_pods_per_node" {
  description = "Maximum number of Kubernetes pods scheduled per AKS node."
  type        = number
  default     = 110

  validation {
    condition     = var.max_pods_per_node >= 50 && var.max_pods_per_node <= 250
    error_message = "max_pods_per_node must be between 50 and 250."
  }
}

variable "user_node_vm_size" {
  description = "VM size used by the AKS application user node pool."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "user_node_min_count" {
  description = "Minimum number of nodes in the AKS application user node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.user_node_min_count >= 1
    error_message = "user_node_min_count must be at least 1."
  }
}

variable "user_node_max_count" {
  description = "Maximum number of nodes in the AKS application user node pool."
  type        = number
  default     = 3

  validation {
    condition     = var.user_node_max_count >= var.user_node_min_count
    error_message = "user_node_max_count must be greater than or equal to user_node_min_count."
  }
}

variable "node_os_disk_size_gb" {
  description = "OS disk size used by AKS system and user node pools."
  type        = number
  default     = 60

  validation {
    condition     = var.node_os_disk_size_gb >= 30
    error_message = "node_os_disk_size_gb must be at least 30 GB."
  }
}