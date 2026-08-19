data "azurerm_client_config" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  sanitized_prefix = replace(lower(var.name_prefix), "-", "")
  storage_name     = "${substr(local.sanitized_prefix, 0, 16)}${random_id.suffix.hex}"
}

resource "azurerm_resource_group" "tfstate" {
  name     = "${var.name_prefix}-rg"
  location = var.location

  tags = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_59:Public endpoint access is intentionally configurable so GitHub-hosted runners can reach the Terraform backend; Shared Key authorization remains disabled and Entra RBAC is required.
  #checkov:skip=CKV_AZURE_33:The Terraform backend uses Blob storage only; Queue service logging is not applicable.
  #checkov:skip=CKV_AZURE_206:LRS is intentional for the dev state bootstrap; blob versioning and soft delete provide state recovery controls.
  #checkov:skip=CKV2_AZURE_33:A backend Private Endpoint would require private runner network connectivity; this bootstrap supports GitHub-hosted runners.
  #checkov:skip=CKV2_AZURE_1:Platform-managed encryption is used for the dev Terraform backend; customer-managed keys are production compliance hardening.

  name                = local.storage_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  public_network_access_enabled    = var.public_network_access_enabled
  cross_tenant_replication_enabled = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "terraform_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Legacy Storage Analytics logging is not part of the Terraform backend baseline; production diagnostics should use Azure Monitor.

  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"

  depends_on = [
    azurerm_role_assignment.terraform_state
  ]

  lifecycle {
    prevent_destroy = true
  }
}
