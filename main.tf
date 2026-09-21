terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
     resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-uptime-monitor-${var.yourname}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "main" {
  # Must be globally unique across all of Azure: 3-24 chars, lowercase + numbers only.
  name                     = "stuptime${var.yourname}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_storage_table" "uptime_checks" {
  name                 = "uptimechecks"
  storage_account_name = azurerm_storage_account.main.name
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-uptime-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-uptime-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_service_plan" "main" {
  name                = "asp-uptime-${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

resource "azurerm_linux_function_app" "monitor" {
  name                       = "func-uptime-${var.yourname}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.main.id

    site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string

    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    "TARGET_URL"               = var.target_url
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    # WEBSITE_RUN_FROM_PACKAGE is intentionally omitted — see note above.
  }


  tags = var.tags
}

resource "azurerm_monitor_action_group" "downtime_alerts" {
  name                = "ag-uptime-${var.yourname}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "uptime"

  email_receiver {
    name                    = "owner-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  sms_receiver {
    name         = "owner-sms"
    country_code = "1"
    phone_number = replace(replace(var.alert_phone, "+1", ""), "-", "")
  }

  tags = var.tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "site_down" {
  name                     = "alert-site-down-${var.yourname}"
  resource_group_name     = azurerm_resource_group.main.name
  location                = var.location
  description             = "Fires when the uptime monitor detects site failure."
  severity                = 1
  enabled                 = true
  scopes                  = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  auto_mitigation_enabled = true

  criteria {
    query = <<-QUERY
      AppTraces
      | where SeverityLevel == 3
      | where Message contains "SITE DOWN"
      | summarize count() by bin(TimeGenerated, 5m)
      | where count_ > 0
    QUERY
    time_aggregation_method = "Count"
    threshold                = 0
    operator                 = "GreaterThan"
  }

  action {
    action_groups = [azurerm_monitor_action_group.downtime_alerts.id]
  }

  tags = var.tags
}

