# ==============================================================================
# TERRAFORM CONFIGURATION FOR AZURE DEPLOYMENT
# ==============================================================================
# Deploys FastAPI app to Azure Container Apps with Storage Queue
# ==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.57"
    }
  }
}

provider "azurerm" {
  features {}

  # Authentication will use Azure CLI: `az login`
}


# ==============================================================================
# RESOURCE GROUP - Container for all Azure resources
# ==============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = "production"
    project     = "smarsh-backend"
    managed_by  = "terraform"
  }
}

# ==============================================================================
# STORAGE ACCOUNT - Required for Storage Queue
# ==============================================================================

resource "azurerm_storage_account" "main" {
  name                     = "smarshstorage456"  # Must be globally unique, lowercase/numbers only # Must be globally unique
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Locally redundant (cheapest)

  # Security best practices
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = {
    environment = "production"
    project     = "smarsh-backend"
  }
}

# ==============================================================================
# STORAGE QUEUE - Replaces FastAPI BackgroundTasks
# ==============================================================================

resource "azurerm_storage_queue" "transcripts" {
  name                 = "transcript-processing-queue"
  storage_account_name = azurerm_storage_account.main.name

  # Purpose: Queue transcript processing tasks
  # Workers will poll this queue and process tasks asynchronously
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE - Required for Container Apps monitoring
# ==============================================================================

resource "azurerm_log_analytics_workspace" "main" { #???
  name                = "${var.app_name}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30 # Adjust based on compliance requirements

  tags = {
    environment = "production"
    project     = "smarsh-backend"
  }
}

# ==============================================================================
# CONTAINER APPS ENVIRONMENT - Managed Kubernetes-like environment
# ==============================================================================

resource "azurerm_container_app_environment" "main" {
  name                       = "${var.app_name}-env"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id # ???

  tags = {
    environment = "production"
    project     = "smarsh-backend"
  }
}

# ==============================================================================
# CONTAINER APP - Runs the FastAPI Docker container
# ==============================================================================

resource "azurerm_container_app" "main" {
  name                         = var.app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single" # Single revision at a time

  # ------------------------------------------------------------------------------
  # TEMPLATE - Container configuration
  # ------------------------------------------------------------------------------
  template {
    # Container definition
    container {
      name   = "smarsh-backend"
      image  = var.container_image
      cpu    = 0.25    # 0.25 vCPU (minimal for cost savings)
      memory = "0.5Gi" # 0.5 GB RAM

      # Environment variables (inject connection strings, etc.)
      env {
        name  = "STORAGE_QUEUE_CONNECTION_STRING"
        value = azurerm_storage_account.main.primary_connection_string
      }

      env {
        name  = "STORAGE_QUEUE_NAME"
        value = azurerm_storage_queue.transcripts.name
      }
    }

    # ------------------------------------------------------------------------------
    # COST OPTIMIZATION: Scale to Zero
    # ------------------------------------------------------------------------------
    # Azure Container Apps can scale to zero replicas when idle
    # This means you pay NOTHING when the app isn't being used
    #
    # How it works:
    # 1. No traffic → Scale down to 0 replicas (no cost)
    # 2. Request comes in → Cold start (3-5 seconds)
    # 3. Auto-scales up based on traffic
    #
    # Configuration for scale-to-zero:
    min_replicas = 0 # Scale to ZERO when idle (COST SAVINGS!)
    max_replicas = 3 # Scale up to 3 during high load

    # Scale rules (when to add/remove replicas)
    # HTTP-based scaling: Add replica for every 10 concurrent requests
    http_scale_rule { # ???
      name                = "http-scaler"
      concurrent_requests = 10
    }
  }

  # ------------------------------------------------------------------------------
  # INGRESS - Expose app to internet
  # ------------------------------------------------------------------------------
  ingress {
    external_enabled = true # Allow external traffic
    target_port      = 8000 # FastAPI default port
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # Secret management (for sensitive data) ???
  secret {
    name  = "storage-connection-string"
    value = azurerm_storage_account.main.primary_connection_string
  }

  tags = {
    environment = "production"
    project     = "smarsh-backend"
  }
}
