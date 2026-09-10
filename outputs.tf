output "vnet" {
  description = "Virtual network created by this module."
  value       = azurerm_virtual_network.this
}

output "subnets" {
  description = "Subnets created by this module."
  value       = azurerm_subnet.this
}

output "network_security_groups" {
  description = "Network security groups created for configured subnets."
  value       = azurerm_network_security_group.subnet
}

output "spoke_to_security_peering" {
  description = "Spoke-to-security VNet peering."
  value       = one(azurerm_virtual_network_peering.spoke_to_security[*])
}

output "security_to_spoke_peering" {
  description = "Security-to-spoke VNet peering."
  value       = one(azurerm_virtual_network_peering.security_to_spoke[*])
}

output "additional_peerings" {
  description = "Additional VNet peerings created by this module."
  value       = azurerm_virtual_network_peering.additional
}

output "route_tables" {
  description = "Route tables created by this module."
  value       = merge(azurerm_route_table.nva, azurerm_route_table.custom)

  precondition {
    condition = length(setintersection(
      toset(keys(azurerm_route_table.nva)),
      toset(keys(azurerm_route_table.custom))
    )) == 0
    error_message = "NVA and custom route-table keys must be disjoint so the route_tables output cannot omit an entry."
  }
}
