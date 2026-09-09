locals {
  routed_subnets = {
    for subnet_key, subnet in var.subnets : subnet_key => subnet
    if try(subnet.route_table, null) != null || coalesce(subnet.create_dedicated_route_table, var.nva_ip != null || length(subnet.additional_nva_routes) > 0)
  }

  subnet_route_tables = {
    for subnet_key, subnet in local.routed_subnets : lower(trimsuffix(subnet_key, "Subnet")) => {
      name                          = coalesce(try(subnet.route_table.name, null), "${trimsuffix(var.vnet_name, "-vnet")}-${lower(trimsuffix(subnet_key, "Subnet"))}-rt")
      subnet_key                    = subnet_key
      bgp_route_propagation_enabled = try(subnet.route_table.bgp_route_propagation_enabled, false)
      routes = merge(
        var.nva_ip == null ? {} : {
          default = {
            address_prefix         = "0.0.0.0/0"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = var.nva_ip
          }
        },
        var.nva_ip == null || var.security_vnet == null || !var.route_security_vnet_through_nva ? {} : {
          for prefix in var.security_vnet.address_space : "to-${replace(replace(prefix, "/", "-"), ".", "-")}" => {
            address_prefix         = prefix
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = var.nva_ip
          }
        },
        {
          for route_key, route in subnet.additional_nva_routes : route_key => {
            address_prefix         = route.address_prefix
            next_hop_type          = route.next_hop_type
            next_hop_in_ip_address = route.next_hop_in_ip_address != null ? route.next_hop_in_ip_address : var.nva_ip
          }
        },
        try(subnet.route_table.routes, {})
      )
    }
  }

  custom_routes = merge({}, [
    for route_table_key, route_table in var.route_tables : {
      for route_key, route in route_table.routes : "${route_table_key}.${route_key}" => merge(route, {
        route_table_key = route_table_key
        route_key       = route_key
      })
    }
  ]...)
}

resource "azurerm_virtual_network" "this" {
  name                           = var.vnet_name
  location                       = var.location
  resource_group_name            = var.rg_name
  address_space                  = var.address_space
  dns_servers                    = var.dns_servers
  bgp_community                  = var.bgp_community
  edge_zone                      = var.edge_zone
  flow_timeout_in_minutes        = var.flow_timeout_in_minutes
  private_endpoint_vnet_policies = var.private_endpoint_vnet_policies
  tags                           = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes

  default_outbound_access_enabled               = each.value.default_outbound_access_enabled
  private_endpoint_network_policies             = each.value.private_endpoint_network_policies
  private_link_service_network_policies_enabled = each.value.private_link_service_network_policies_enabled
  service_endpoint_policy_ids                   = each.value.service_endpoint_policy_ids
  service_endpoints                             = each.value.service_endpoints
  sharing_scope                                 = each.value.sharing_scope

  dynamic "delegation" {
    for_each = each.value.delegations

    content {
      name = delegation.key

      service_delegation {
        name    = delegation.value.name
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_virtual_network_peering" "spoke_to_security" {
  count = var.security_vnet == null ? 0 : 1

  name                         = "${var.vnet_name}-to-${var.security_vnet.name}"
  resource_group_name          = var.rg_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.security_vnet.id
  allow_forwarded_traffic      = try(var.security_vnet.allow_forwarded_traffic, true)
  allow_gateway_transit        = try(var.security_vnet.allow_gateway_transit, false)
  allow_virtual_network_access = try(var.security_vnet.allow_virtual_network_access, true)
  use_remote_gateways          = try(var.security_vnet.use_remote_gateways, false)
}

resource "azurerm_virtual_network_peering" "security_to_spoke" {
  count = var.security_vnet == null || !try(var.security_vnet.create_remote_peering, true) ? 0 : 1

  provider = azurerm.transit

  name                         = "${var.security_vnet.name}-to-${var.vnet_name}"
  resource_group_name          = var.security_vnet.resource_group_name
  virtual_network_name         = var.security_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_gateway_transit        = try(var.security_vnet.allow_gateway_transit, false)
  allow_forwarded_traffic      = try(var.security_vnet.allow_forwarded_traffic, true)
  allow_virtual_network_access = try(var.security_vnet.allow_virtual_network_access, true)
  use_remote_gateways          = try(var.security_vnet.use_remote_gateways, false)
}

resource "azurerm_virtual_network_peering" "additional" {
  for_each = var.additional_peerings

  name                         = each.value.name
  resource_group_name          = var.rg_name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = each.value.remote_virtual_network_id
  allow_forwarded_traffic      = each.value.allow_forwarded_traffic
  allow_gateway_transit        = each.value.allow_gateway_transit
  allow_virtual_network_access = each.value.allow_virtual_network_access
  use_remote_gateways          = each.value.use_remote_gateways
}

resource "azurerm_route_table" "nva" {
  for_each = local.subnet_route_tables

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = var.rg_name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = var.tags

  dynamic "route" {
    for_each = each.value.routes

    content {
      name                   = route.key
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = route.value.next_hop_in_ip_address
    }
  }
}

resource "azurerm_route_table" "custom" {
  for_each = var.route_tables

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = var.rg_name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = var.tags
}

resource "azurerm_route" "custom" {
  for_each = local.custom_routes

  name                   = each.value.route_key
  resource_group_name    = var.rg_name
  route_table_name       = azurerm_route_table.custom[each.value.route_table_key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_in_ip_address
}

resource "azurerm_subnet_route_table_association" "nva" {
  for_each = local.subnet_route_tables

  subnet_id      = azurerm_subnet.this[each.value.subnet_key].id
  route_table_id = azurerm_route_table.nva[each.key].id
}

resource "azurerm_subnet_route_table_association" "custom" {
  for_each = var.route_tables

  subnet_id      = azurerm_subnet.this[each.value.subnet_key].id
  route_table_id = azurerm_route_table.custom[each.key].id
}
