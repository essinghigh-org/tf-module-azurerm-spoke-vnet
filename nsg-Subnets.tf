# Subnet NSGs, built on the shared subnet-nsg module. Profile and rule
# validation (including the deny_internet_inbound public-allow guard)
# lives in the shared module, which fails unknown profiles at plan.

module "subnet_nsg" {
  source  = "terraform.essinghigh.dev/essinghigh-org/subnet-nsg/azurerm"
  version = "0.1.1"
  for_each = {
    for key, subnet in var.subnets : key => subnet
    if try(subnet.nsg, null) != null && try(subnet.nsg.enabled, true)
  }

  providers = {
    azurerm = azurerm.spoke
  }

  name                = coalesce(try(each.value.nsg.name, null), "${azurerm_virtual_network.this.name}-${each.key}-nsg")
  location            = var.location
  resource_group_name = var.rg_name
  subnet_id           = azurerm_subnet.this[each.key].id
  profiles            = try(each.value.nsg.profiles, [])
  rules               = try(each.value.nsg.rules, {})
  tags                = var.tags
}
