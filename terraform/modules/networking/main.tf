resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space

  tags = var.tags
}

resource "azurerm_network_security_group" "aks" {
  name                = "${var.name_prefix}-aks-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_network_security_group" "postgresql" {
  name                = "${var.name_prefix}-postgresql-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "${var.name_prefix}-private-endpoints-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# PostgreSQL accepts database traffic only from the AKS subnet and from
# PostgreSQL peers inside its own delegated subnet. The self-subnet rule is
# required for Flexible Server service operations such as HA communication.
resource "azurerm_network_security_rule" "postgresql_allow_aks" {
  name                         = "Allow-AKS-PostgreSQL"
  description                  = "Allow AKS nodes to reach PostgreSQL Flexible Server on TCP 5432."
  priority                     = 100
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "5432"
  source_address_prefixes      = var.aks_subnet_prefixes
  destination_address_prefixes = var.postgresql_subnet_prefixes

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgresql.name
}

resource "azurerm_network_security_rule" "postgresql_allow_self" {
  name                         = "Allow-PostgreSQL-Subnet-5432"
  description                  = "Allow PostgreSQL Flexible Server communication within the delegated subnet."
  priority                     = 110
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "5432"
  source_address_prefixes      = var.postgresql_subnet_prefixes
  destination_address_prefixes = var.postgresql_subnet_prefixes

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgresql.name
}

resource "azurerm_network_security_rule" "postgresql_deny_other_vnet" {
  name                         = "Deny-Other-VNet-PostgreSQL"
  description                  = "Deny other virtual-network sources from reaching the PostgreSQL delegated subnet."
  priority                     = 200
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "VirtualNetwork"
  destination_address_prefixes = var.postgresql_subnet_prefixes

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.postgresql.name
}

# Private Endpoints are reachable from AKS over HTTPS. Network policies are
# enabled on the subnet so the NSG can enforce traffic to Private Endpoint NICs.
resource "azurerm_network_security_rule" "private_endpoints_allow_aks_https" {
  name                         = "Allow-AKS-PrivateEndpoints-HTTPS"
  description                  = "Allow AKS nodes to access private Azure PaaS endpoints over HTTPS."
  priority                     = 100
  direction                    = "Inbound"
  access                       = "Allow"
  protocol                     = "Tcp"
  source_port_range            = "*"
  destination_port_range       = "443"
  source_address_prefixes      = var.aks_subnet_prefixes
  destination_address_prefixes = var.private_endpoints_subnet_prefixes

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "private_endpoints_deny_other_vnet" {
  name                         = "Deny-Other-VNet-PrivateEndpoints"
  description                  = "Deny other virtual-network sources from reaching the Private Endpoints subnet."
  priority                     = 200
  direction                    = "Inbound"
  access                       = "Deny"
  protocol                     = "*"
  source_port_range            = "*"
  destination_port_range       = "*"
  source_address_prefix        = "VirtualNetwork"
  destination_address_prefixes = var.private_endpoints_subnet_prefixes

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.name_prefix}-aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.aks_subnet_prefixes
}

resource "azurerm_subnet" "postgresql" {
  name                 = "${var.name_prefix}-postgresql-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.postgresql_subnet_prefixes

  delegation {
    name = "postgresql-flexible-server"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"

      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.name_prefix}-private-endpoints-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.private_endpoints_subnet_prefixes

  private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "postgresql" {
  subnet_id                 = azurerm_subnet.postgresql.id
  network_security_group_id = azurerm_network_security_group.postgresql.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}
