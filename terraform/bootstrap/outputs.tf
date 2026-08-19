output "resource_group_name" {
  description = "Resource Group containing the Terraform state backend."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage Account used by the Terraform azurerm backend."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container used to store Terraform state."
  value       = azurerm_storage_container.tfstate.name
}
