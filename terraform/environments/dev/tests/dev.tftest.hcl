mock_provider "azurerm" {
  override_during = plan
}

mock_provider "random" {
  override_during = plan
}

# -------------------------------------------------------------------
# Root environment
# -------------------------------------------------------------------

override_resource {
  target          = azurerm_resource_group.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg"
  }
}

# -------------------------------------------------------------------
# Networking
# -------------------------------------------------------------------

override_resource {
  target          = module.networking.azurerm_virtual_network.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet"
  }
}

override_resource {
  target          = module.networking.azurerm_subnet.aks
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-aks-subnet"
  }
}

override_resource {
  target          = module.networking.azurerm_subnet.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-postgresql-subnet"
  }
}

override_resource {
  target          = module.networking.azurerm_subnet.private_endpoints
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-private-endpoints-subnet"
  }
}

override_resource {
  target          = module.networking.azurerm_network_security_group.aks
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-aks-nsg"
  }
}

override_resource {
  target          = module.networking.azurerm_network_security_group.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-postgresql-nsg"
  }
}

override_resource {
  target          = module.networking.azurerm_network_security_group.private_endpoints
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-private-endpoints-nsg"
  }
}

# -------------------------------------------------------------------
# Azure Container Registry
# -------------------------------------------------------------------

override_resource {
  target          = module.acr.random_id.suffix
  override_during = plan

  values = {
    hex = "a1b2c3"
  }
}

override_resource {
  target          = module.acr.azurerm_container_registry.this
  override_during = plan

  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.ContainerRegistry/registries/sreplatformdeva1b2c3"
    login_server = "sreplatformdeva1b2c3.azurecr.io"
  }
}

override_resource {
  target          = module.acr.azurerm_private_dns_zone.acr
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  }
}

# -------------------------------------------------------------------
# AKS
# -------------------------------------------------------------------

override_resource {
  target          = module.aks.azurerm_user_assigned_identity.control_plane
  override_during = plan

  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/sre-platform-dev-aks-control-plane-mi"
    client_id    = "11111111-1111-1111-1111-111111111111"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}

override_resource {
  target          = module.aks.azurerm_user_assigned_identity.kubelet
  override_during = plan

  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/sre-platform-dev-aks-kubelet-mi"
    client_id    = "33333333-3333-3333-3333-333333333333"
    principal_id = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target          = module.aks.azurerm_kubernetes_cluster.this
  override_during = plan

  values = {
    id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.ContainerService/managedClusters/sre-platform-dev-aks"
    private_fqdn    = "sre-platform-dev-aks.privatelink.westeurope.azmk8s.io"
    oidc_issuer_url = "https://oidc.prod-aks.azure.com/mock/"
  }
}

# -------------------------------------------------------------------
# PostgreSQL
# -------------------------------------------------------------------

override_resource {
  target          = module.postgresql.random_id.suffix
  override_during = plan

  values = {
    hex = "d4e5f6"
  }
}

override_resource {
  target          = module.postgresql.azurerm_private_dns_zone.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/privateDnsZones/sre-platform-dev.postgres.database.azure.com"
  }
}

override_resource {
  target          = module.postgresql.azurerm_postgresql_flexible_server.this
  override_during = plan

  values = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/sre-platform-dev-pg-d4e5f6"
    fqdn = "sre-platform-dev-pg-d4e5f6.postgres.database.azure.com"
  }
}

# -------------------------------------------------------------------
# Storage
# -------------------------------------------------------------------

override_resource {
  target          = module.storage.random_id.suffix
  override_during = plan

  values = {
    hex = "1a2b3c"
  }
}

override_resource {
  target          = module.storage.azurerm_storage_account.this
  override_during = plan

  values = {
    id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Storage/storageAccounts/sreplatformdevst1a2b3c"
    primary_blob_endpoint = "https://sreplatformdevst1a2b3c.blob.core.windows.net/"
  }
}

override_resource {
  target          = module.storage.azurerm_private_dns_zone.blob
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
}

override_resource {
  target          = module.storage.azurerm_private_endpoint.blob
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/privateEndpoints/sre-platform-dev-blob-pe"
  }
}

# -------------------------------------------------------------------
# Test inputs
# -------------------------------------------------------------------

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"

  postgresql_administrator_password = "Mock-Only-Passw0rd!2026"
}

# -------------------------------------------------------------------
# Root composition contract
# -------------------------------------------------------------------

run "dev_environment_composition" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "sre-platform-dev-rg"
    error_message = "The dev Resource Group naming convention has changed unexpectedly."
  }

  assert {
    condition     = azurerm_resource_group.this.location == "westeurope"
    error_message = "The dev environment must remain in West Europe."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["project"] == "sre-platform"
    error_message = "The project tag must remain sre-platform."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["environment"] == "dev"
    error_message = "The environment tag must remain dev."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["managed_by"] == "terraform"
    error_message = "The managed_by tag must remain terraform."
  }

  assert {
    condition     = output.virtual_network_name == "sre-platform-dev-vnet"
    error_message = "The root environment must expose the expected VNet."
  }

  assert {
    condition     = output.container_registry_name == "sreplatformdeva1b2c3"
    error_message = "The root environment must expose the expected ACR."
  }

  assert {
    condition     = output.container_registry_login_server == "sreplatformdeva1b2c3.azurecr.io"
    error_message = "The root environment must expose the ACR login server."
  }

  assert {
    condition     = output.aks_cluster_name == "sre-platform-dev-aks"
    error_message = "The root environment must expose the expected AKS cluster."
  }

  assert {
    condition     = output.postgresql_server_name == "sre-platform-dev-pg-d4e5f6"
    error_message = "The root environment must expose the expected PostgreSQL server."
  }

  assert {
    condition     = output.postgresql_database_name == "app_db"
    error_message = "The root environment must expose the application PostgreSQL database."
  }

  assert {
    condition     = output.storage_account_name == "sreplatformdevst1a2b3c"
    error_message = "The root environment must expose the expected Storage Account."
  }

  assert {
    condition     = output.storage_container_name == "app-data"
    error_message = "The root environment must expose the private application Blob container."
  }

  assert {
    condition     = output.storage_private_endpoint_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sre-platform-dev-rg/providers/Microsoft.Network/privateEndpoints/sre-platform-dev-blob-pe"
    error_message = "The root environment must expose the Blob private endpoint."
  }
}