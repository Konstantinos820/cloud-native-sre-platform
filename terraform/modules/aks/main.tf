resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name_prefix}-aks-control-plane-mi"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "${var.name_prefix}-aks-kubelet-mi"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

resource "azurerm_role_assignment" "kubelet_identity_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id

  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_227:Host encryption is production hardening and is intentionally not enabled in the dev baseline.
  #checkov:skip=CKV_AZURE_170:The dev environment intentionally uses the Free AKS control-plane tier; paid SLA is a production deployment decision.
  #checkov:skip=CKV_AZURE_4:Cluster observability is provided by the existing Prometheus/Grafana stack; Azure Monitor integration is not part of this dev baseline.
  #checkov:skip=CKV_AZURE_117:Customer-managed disk encryption requires additional key-management infrastructure and is treated as production compliance hardening.

  name                = "${var.name_prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name

  dns_prefix_private_cluster = "${var.name_prefix}-aks"

  kubernetes_version = var.kubernetes_version
  sku_tier           = var.sku_tier

  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false
  private_dns_zone_id                 = "System"

  node_resource_group = "${var.name_prefix}-aks-nodes-rg"

  role_based_access_control_enabled = true
  local_account_disabled            = true

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    vnet_subnet_id               = var.aks_subnet_id
    type                         = "VirtualMachineScaleSets"
    auto_scaling_enabled         = true
    node_count                   = var.system_node_min_count
    min_count                    = var.system_node_min_count
    max_count                    = var.system_node_max_count
    node_public_ip_enabled       = false
    max_pods                     = var.max_pods_per_node
    only_critical_addons_enabled = true
    temporary_name_for_rotation  = "systemtmp"
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = var.node_os_disk_size_gb

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }
  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"

    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip

    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    ip_versions       = ["IPv4"]
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.network_contributor,
    azurerm_role_assignment.kubelet_identity_operator,
  ]
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id

  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  #checkov:skip=CKV_AZURE_227:Host encryption is production hardening and is intentionally not enabled for the dev user node pool.

  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  mode                  = "User"

  auto_scaling_enabled = true
  node_count           = var.user_node_min_count
  min_count            = var.user_node_min_count
  max_count            = var.user_node_max_count

  max_pods               = var.max_pods_per_node
  node_public_ip_enabled = false

  temporary_name_for_rotation = "usertmp"

  os_disk_type    = "Ephemeral"
  os_disk_size_gb = var.node_os_disk_size_gb

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags
}