output "server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "server_name" {
  description = "Name of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_id" {
  description = "Resource ID of the application PostgreSQL database."
  value       = azurerm_postgresql_flexible_server_database.app.id
}

output "database_name" {
  description = "Name of the application PostgreSQL database."
  value       = azurerm_postgresql_flexible_server_database.app.name
}

output "private_dns_zone_id" {
  description = "Resource ID of the PostgreSQL private DNS zone."
  value       = azurerm_private_dns_zone.postgresql.id
}
