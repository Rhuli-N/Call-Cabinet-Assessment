# ==============================================================================
# OUTPUTS - Display important values after deployment
# ==============================================================================

output "container_app_url" {
  description = "Public URL of the deployed FastAPI app"
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "storage_queue_name" {
  description = "Name of the Azure Storage Queue"
  value       = azurerm_storage_queue.transcripts.name
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}