resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location

  tags = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  vnet_address_space                = var.vnet_address_space
  aks_subnet_prefixes               = var.aks_subnet_prefixes
  postgresql_subnet_prefixes        = var.postgresql_subnet_prefixes
  private_endpoints_subnet_prefixes = var.private_endpoints_subnet_prefixes

  tags = local.common_tags
}

module "acr" {
  source = "../../modules/acr"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  virtual_network_id         = module.networking.virtual_network_id

  tags = local.common_tags
}

module "aks" {
  source = "../../modules/aks"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  aks_subnet_id = module.networking.aks_subnet_id
  acr_id        = module.acr.id

  kubernetes_version    = var.aks_kubernetes_version
  sku_tier              = var.aks_sku_tier
  system_node_vm_size   = var.aks_system_node_vm_size
  system_node_min_count = var.aks_system_node_min_count
  system_node_max_count = var.aks_system_node_max_count

  pod_cidr       = var.aks_pod_cidr
  service_cidr   = var.aks_service_cidr
  dns_service_ip = var.aks_dns_service_ip

  admin_group_object_ids = var.aks_admin_group_object_ids

  tags = local.common_tags
}

module "postgresql" {
  source = "../../modules/postgresql"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  delegated_subnet_id = module.networking.postgresql_subnet_id
  virtual_network_id  = module.networking.virtual_network_id

  administrator_login            = var.postgresql_administrator_login
  administrator_password         = var.postgresql_administrator_password
  administrator_password_version = var.postgresql_administrator_password_version

  postgresql_version    = var.postgresql_version
  sku_name              = var.postgresql_sku_name
  storage_mb            = var.postgresql_storage_mb
  backup_retention_days = var.postgresql_backup_retention_days
  database_name         = var.postgresql_database_name

  tags = local.common_tags
}
