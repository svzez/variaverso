# An example of how secrets are created in Azure Key Vault from a sops file
# Providers
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.55.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "sops_file" "monitoring_secrets" {
  source_file = "./monitoring_secrets.enc.yaml"
}

data "azurerm_key_vault" "monitoring_secrets" {
  name                = "my-vault"
  resource_group_name = "my-rg"
}

resource "azurerm_key_vault_secret" "secrets" {
  for_each     = toset(keys(nonsensitive(data.sops_file.monitoring_secrets.data)))
  name         = replace(each.key, "/[^0-9a-zA-Z-]/", "-")
  value        = data.sops_file.monitoring_secrets.data[each.key]
  key_vault_id = data.azurerm_key_vault.monitoring_secrets.id
}
