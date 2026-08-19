output "id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "private_fqdn" {
  description = "Private FQDN of the AKS API server."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "node_resource_group" {
  description = "Resource Group containing AKS managed node resources."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used by Azure Workload Identity."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "control_plane_identity_id" {
  description = "Resource ID of the AKS control-plane managed identity."
  value       = azurerm_user_assigned_identity.control_plane.id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
