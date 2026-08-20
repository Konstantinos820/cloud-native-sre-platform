mock_provider "azurerm" {
  override_during = plan
}

override_resource {
  target          = azurerm_subnet.aks
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-aks-subnet"
  }
}

override_resource {
  target          = azurerm_subnet.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-postgresql-subnet"
  }
}

override_resource {
  target          = azurerm_subnet.private_endpoints
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/sre-platform-dev-vnet/subnets/sre-platform-dev-private-endpoints-subnet"
  }
}

override_resource {
  target          = azurerm_network_security_group.aks
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-aks-nsg"
  }
}

override_resource {
  target          = azurerm_network_security_group.postgresql
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-postgresql-nsg"
  }
}

override_resource {
  target          = azurerm_network_security_group.private_endpoints
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/networkSecurityGroups/sre-platform-dev-private-endpoints-nsg"
  }
}

variables {
  name_prefix         = "sre-platform-dev"
  resource_group_name = "rg-sre-platform-dev"
  location            = "westeurope"

  vnet_address_space = [
    "10.20.0.0/16"
  ]

  aks_subnet_prefixes = [
    "10.20.0.0/23"
  ]

  postgresql_subnet_prefixes = [
    "10.20.2.0/24"
  ]

  private_endpoints_subnet_prefixes = [
    "10.20.3.0/24"
  ]

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

run "network_segmentation_baseline" {
  command = plan

  assert {
    condition     = toset(azurerm_virtual_network.this.address_space) == toset(["10.20.0.0/16"])
    error_message = "The VNet address space must remain 10.20.0.0/16."
  }

  assert {
    condition     = toset(azurerm_subnet.aks.address_prefixes) == toset(["10.20.0.0/23"])
    error_message = "The AKS subnet must remain isolated in 10.20.0.0/23."
  }

  assert {
    condition     = toset(azurerm_subnet.postgresql.address_prefixes) == toset(["10.20.2.0/24"])
    error_message = "The PostgreSQL subnet must remain isolated in 10.20.2.0/24."
  }

  assert {
    condition     = toset(azurerm_subnet.private_endpoints.address_prefixes) == toset(["10.20.3.0/24"])
    error_message = "Private endpoints must remain isolated in 10.20.3.0/24."
  }
}

run "postgresql_delegation_baseline" {
  command = plan

  assert {
    condition     = azurerm_subnet.postgresql.delegation[0].service_delegation[0].name == "Microsoft.DBforPostgreSQL/flexibleServers"
    error_message = "The PostgreSQL subnet must remain delegated to Flexible Server."
  }

  assert {
    condition = contains(
      azurerm_subnet.postgresql.delegation[0].service_delegation[0].actions,
      "Microsoft.Network/virtualNetworks/subnets/join/action"
    )
    error_message = "The PostgreSQL subnet delegation must allow subnet join operations."
  }
}

run "private_endpoint_network_policy_baseline" {
  command = plan

  assert {
    condition     = azurerm_subnet.private_endpoints.private_endpoint_network_policies == "NetworkSecurityGroupEnabled"
    error_message = "Private endpoint subnet NSG policies must remain enabled."
  }
}

run "nsg_association_baseline" {
  command = plan

  assert {
    condition     = azurerm_subnet_network_security_group_association.aks.network_security_group_id == azurerm_network_security_group.aks.id
    error_message = "The AKS subnet must remain associated with the AKS NSG."
  }

  assert {
    condition     = azurerm_subnet_network_security_group_association.postgresql.network_security_group_id == azurerm_network_security_group.postgresql.id
    error_message = "The PostgreSQL subnet must remain associated with the PostgreSQL NSG."
  }

  assert {
    condition     = azurerm_subnet_network_security_group_association.private_endpoints.network_security_group_id == azurerm_network_security_group.private_endpoints.id
    error_message = "The private endpoint subnet must remain associated with the private endpoint NSG."
  }
}