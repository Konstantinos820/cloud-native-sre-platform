output "id" {
  description = "Resource ID of the Azure Container Registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Name of the Azure Container Registry."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Login server hostname of the Azure Container Registry."
  value       = azurerm_container_registry.this.login_server
}

output "private_endpoint_id" {
  description = "Resource ID of the ACR private endpoint."
  value       = azurerm_private_endpoint.acr.id
}

output "private_dns_zone_id" {
  description = "Resource ID of the ACR private DNS zone."
  value       = azurerm_private_dns_zone.acr.id
}
