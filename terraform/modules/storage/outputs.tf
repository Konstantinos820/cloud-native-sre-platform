output "storage_account_id" {
  description = "Resource ID of the Azure Storage Account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the Azure Storage Account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Primary Blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_id" {
  description = "Resource ID of the private application Blob container."
  value       = azurerm_storage_container.app.id
}

output "container_name" {
  description = "Name of the private application Blob container."
  value       = azurerm_storage_container.app.name
}

output "private_endpoint_id" {
  description = "Resource ID of the Blob private endpoint."
  value       = azurerm_private_endpoint.blob.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the Blob private DNS zone."
  value       = azurerm_private_dns_zone.blob.id
}
