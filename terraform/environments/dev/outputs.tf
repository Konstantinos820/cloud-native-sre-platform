output "resource_group_name" {
  description = "Name of the development Azure Resource Group."
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Resource ID of the development Azure Resource Group."
  value       = azurerm_resource_group.this.id
}

output "virtual_network_id" {
  description = "Resource ID of the development virtual network."
  value       = module.networking.virtual_network_id
}

output "virtual_network_name" {
  description = "Name of the development virtual network."
  value       = module.networking.virtual_network_name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet."
  value       = module.networking.aks_subnet_id
}

output "postgresql_subnet_id" {
  description = "Resource ID of the PostgreSQL delegated subnet."
  value       = module.networking.postgresql_subnet_id
}

output "private_endpoints_subnet_id" {
  description = "Resource ID of the private endpoints subnet."
  value       = module.networking.private_endpoints_subnet_id
}

output "container_registry_id" {
  description = "Resource ID of the Azure Container Registry."
  value       = module.acr.id
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry."
  value       = module.acr.name
}

output "container_registry_login_server" {
  description = "Login server hostname of the Azure Container Registry."
  value       = module.acr.login_server
}

output "aks_cluster_id" {
  description = "Resource ID of the AKS cluster."
  value       = module.aks.id
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster."
  value       = module.aks.name
}

output "aks_private_fqdn" {
  description = "Private FQDN of the AKS API server."
  value       = module.aks.private_fqdn
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for Azure Workload Identity."
  value       = module.aks.oidc_issuer_url
}

output "postgresql_server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = module.postgresql.server_id
}

output "postgresql_server_name" {
  description = "Name of the PostgreSQL Flexible Server."
  value       = module.postgresql.server_name
}

output "postgresql_fqdn" {
  description = "Private FQDN of the PostgreSQL Flexible Server."
  value       = module.postgresql.fqdn
}

output "postgresql_database_name" {
  description = "Name of the application PostgreSQL database."
  value       = module.postgresql.database_name
}

output "storage_account_id" {
  description = "Resource ID of the application Azure Storage Account."
  value       = module.storage.storage_account_id
}

output "storage_account_name" {
  description = "Name of the application Azure Storage Account."
  value       = module.storage.storage_account_name
}

output "storage_blob_endpoint" {
  description = "Primary Blob endpoint of the application Storage Account."
  value       = module.storage.primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the private application Blob container."
  value       = module.storage.container_name
}

output "storage_private_endpoint_id" {
  description = "Resource ID of the Blob private endpoint."
  value       = module.storage.private_endpoint_id
}
