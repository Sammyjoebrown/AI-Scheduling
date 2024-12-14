terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "ai-scheduling-rg"
  location = "Australia Southeast"
}

# Azure Storage Account (Required for Azure Functions)
resource "azurerm_storage_account" "function_storage" {
  name                     = "aischedulefuncstore"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# App Service Plan (Dynamic SKU for Serverless Functions)
resource "azurerm_app_service_plan" "functions" {
  name                = "ai-scheduling-functions-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "FunctionApp"
  reserved            = true
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

# Azure Function App
resource "azurerm_function_app" "backend" {
  name                       = "ai-scheduling-functions"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  app_service_plan_id        = azurerm_app_service_plan.functions.id
  os_type                    = "Linux"
  runtime_stack              = "node"

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME         = "node"
    WEBSITE_RUN_FROM_PACKAGE         = "1"
    APPINSIGHTS_INSTRUMENTATIONKEY   = azurerm_application_insights.main.instrumentation_key
    AZURE_COSMOSDB_CONNECTION_STRING = azurerm_cosmosdb_account.main.connection_strings[0]
  }
}

# Azure Cosmos DB Account
resource "azurerm_cosmosdb_account" "main" {
  name                = "aischedulecosmos"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "MongoDB"
  enable_free_tier    = true
  consistency_policy {
    consistency_level = "Session"
  }
}

resource "azurerm_cosmosdb_mongo_database" "main" {
  name                = "schedulingdb"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_mongo_collection" "appointments" {
  name                  = "appointments"
  resource_group_name   = azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.main.name
  database_name         = azurerm_cosmosdb_mongo_database.main.name
  throughput            = 400
}

# Azure Static Web App (Front-End)
resource "azurerm_static_site" "frontend" {
  name                = "ai-scheduling-frontend"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Free"

  repository_url      = "https://github.com/Sammyjoebrown/AI-Scheduling"
  branch              = "main"
  build_command       = "npm run build"
  output_location     = "dist"
}

# Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                        = "aischedulekeyvault"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
}

# Azure Application Insights (Monitoring)
resource "azurerm_application_insights" "main" {
  name                = "aischeduleappinsights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
}

# Azure API Management (API Gateway)
resource "azurerm_api_management" "gateway" {
  name                = "ai-schedule-api-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "AI Scheduling"
  publisher_email     = "admin@example.com"
  sku_name            = "Consumption"

  identity {
    type = "SystemAssigned"
  }
}

# Outputs
output "static_site_url" {
  value = azurerm_static_site.frontend.default_hostname
}

output "function_app_url" {
  value = azurerm_function_app.backend.default_hostname
}

output "application_insights_key" {
  value = azurerm_application_insights.main.instrumentation_key
}

output "cosmosdb_connection_string" {
  value = azurerm_cosmosdb_account.main.connection_strings[0]
}
