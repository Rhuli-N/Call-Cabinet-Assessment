# ==============================================================================
# VARIABLES - Customize these for your deployment
# ==============================================================================

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-smarsh-backend"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "southafricanorth"
}

variable "app_name" {
  description = "Name of the application (used for naming resources)"
  type        = string
  default     = "smarsh-backend"
}

variable "container_image" {
  description = "Docker image to deploy (e.g., from Azure Container Registry)"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}
