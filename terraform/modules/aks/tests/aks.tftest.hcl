mock_provider "azurerm" {
  override_during = plan
}

override_resource {
  target          = azurerm_user_assigned_identity.control_plane
  override_during = plan

  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/sre-platform-dev-aks-control-plane-mi"
    client_id    = "11111111-1111-1111-1111-111111111111"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.kubelet
  override_during = plan

  values = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/sre-platform-dev-aks-kubelet-mi"
    client_id    = "33333333-3333-3333-3333-333333333333"
    principal_id = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target          = azurerm_kubernetes_cluster.this
  override_during = plan

  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.ContainerService/managedClusters/sre-platform-dev-aks"
  }
}

variables {
  name_prefix         = "sre-platform-dev"
  resource_group_name = "rg-sre-platform-dev"
  location            = "westeurope"

  aks_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.Network/virtualNetworks/vnet-sre-platform-dev/subnets/snet-aks"
  acr_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sre-platform-dev/providers/Microsoft.ContainerRegistry/registries/sreplatformdevacr"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

run "secure_aks_baseline" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled == true
    error_message = "AKS must remain a private cluster."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_public_fqdn_enabled == false
    error_message = "AKS must not expose a public FQDN."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "AKS local accounts must remain disabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled == true
    error_message = "The AKS system node pool must be reserved for critical system workloads."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].os_disk_type == "Ephemeral"
    error_message = "The AKS system node pool must use Ephemeral OS disks."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].max_pods >= 50
    error_message = "The AKS system node pool must support at least 50 pods per node."
  }
}

run "application_user_node_pool" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user.mode == "User"
    error_message = "Application workloads must use a dedicated AKS User node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user.auto_scaling_enabled == true
    error_message = "The AKS application user node pool must have autoscaling enabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user.node_public_ip_enabled == false
    error_message = "AKS application nodes must not receive public IP addresses."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user.os_disk_type == "Ephemeral"
    error_message = "The AKS application user node pool must use Ephemeral OS disks."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.user.max_pods >= 50
    error_message = "The AKS application user node pool must support at least 50 pods per node."
  }
}

run "secrets_rotation_baseline" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_rotation_enabled == true
    error_message = "AKS Key Vault Secrets Store CSI secret rotation must remain enabled."
  }
}