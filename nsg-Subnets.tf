locals {
  public_inbound_source_prefixes = toset([
    "*",
    "0.0.0.0/0",
    "::/0",
    "internet",
  ])

  deny_internet_inbound_rule = {
    priority                                   = 4090
    direction                                  = "Inbound"
    access                                     = "Deny"
    protocol                                   = "*"
    description                                = "Deny inbound traffic from the public Internet."
    source_port_range                          = "*"
    source_port_ranges                         = null
    destination_port_range                     = "*"
    destination_port_ranges                    = null
    source_address_prefix                      = "Internet"
    source_address_prefixes                    = null
    source_application_security_group_ids      = null
    destination_address_prefix                 = "*"
    destination_address_prefixes               = null
    destination_application_security_group_ids = null
  }

  nsg_profile_rules = {
    none = {}

    deny_internet_inbound = {
      "DenyInternetInbound" = local.deny_internet_inbound_rule
    }
  }

  subnet_nsgs = {
    for subnet_key, subnet in var.subnets : subnet_key => {
      name    = try(subnet.nsg.name, null)
      profile = try(subnet.nsg.profile, "none")
      rules = merge(
        try(subnet.nsg.rules, {}),
        local.nsg_profile_rules[try(subnet.nsg.profile, "none")]
      )
    }
    if try(subnet.nsg, null) != null && try(subnet.nsg.enabled, true)
  }
}

resource "azurerm_network_security_group" "subnet" {
  for_each = local.subnet_nsgs

  name                = coalesce(try(each.value.name, null), "${azurerm_virtual_network.this.name}-${each.key}-nsg")
  location            = var.location
  resource_group_name = var.rg_name
  tags                = var.tags

  lifecycle {
    precondition {
      condition     = length(distinct([for rule in values(each.value.rules) : rule.priority])) == length(each.value.rules)
      error_message = "Each subnet NSG rule must have a unique priority."
    }

    precondition {
      condition = each.value.profile != "deny_internet_inbound" || alltrue([
        for rule in values(each.value.rules) : !(
          lower(rule.direction) == "inbound" &&
          lower(rule.access) == "allow" &&
          (
            try(contains(local.public_inbound_source_prefixes, lower(trimspace(rule.source_address_prefix))), false) ||
            try(anytrue([
              for prefix in rule.source_address_prefixes : contains(local.public_inbound_source_prefixes, lower(trimspace(prefix)))
            ]), false)
          )
        )
      ])
      error_message = "The deny_internet_inbound profile cannot include public Internet inbound Allow rules."
    }
  }

  dynamic "security_rule" {
    for_each = each.value.rules

    content {
      name                                       = security_rule.key
      priority                                   = security_rule.value.priority
      direction                                  = security_rule.value.direction
      access                                     = security_rule.value.access
      protocol                                   = security_rule.value.protocol
      description                                = security_rule.value.description
      source_port_range                          = security_rule.value.source_port_range
      source_port_ranges                         = security_rule.value.source_port_ranges
      destination_port_range                     = security_rule.value.destination_port_range
      destination_port_ranges                    = security_rule.value.destination_port_ranges
      source_address_prefix                      = security_rule.value.source_address_prefix
      source_address_prefixes                    = security_rule.value.source_address_prefixes
      source_application_security_group_ids      = security_rule.value.source_application_security_group_ids
      destination_address_prefix                 = security_rule.value.destination_address_prefix
      destination_address_prefixes               = security_rule.value.destination_address_prefixes
      destination_application_security_group_ids = security_rule.value.destination_application_security_group_ids
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "subnet" {
  for_each = local.subnet_nsgs

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.subnet[each.key].id
}
