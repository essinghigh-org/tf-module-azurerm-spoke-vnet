terraform {
  required_version = ">= 1.9.8"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 4.39.0"
      configuration_aliases = [azurerm.spoke]
    }
  }
}
