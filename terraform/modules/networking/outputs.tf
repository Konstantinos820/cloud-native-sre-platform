output "virtual_network_id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet."
  value       = azurerm_subnet.aks.id
}

output "postgresql_subnet_id" {
  description = "Resource ID of the PostgreSQL delegated subnet."
  value       = azurerm_subnet.postgresql.id
}

output "private_endpoints_subnet_id" {
  description = "Resource ID of the private endpoints subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "aks_network_security_group_id" {
  description = "Resource ID of the AKS network security group."
  value       = azurerm_network_security_group.aks.id
}

output "postgresql_network_security_group_id" {
  description = "Resource ID of the PostgreSQL network security group."
  value       = azurerm_network_security_group.postgresql.id
}
