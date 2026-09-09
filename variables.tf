variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
}

variable "location" {
  description = "Azure region for the networking resources."
  type        = string
}

variable "rg_name" {
  description = "Resource group where the networking resources are deployed."
  type        = string
}

variable "vnet_name" {
  description = "Name of the VNet to create."
  type        = string
}

variable "address_space" {
  description = "Address spaces for the VNet."
  type        = list(string)
}

variable "dns_servers" {
  description = "DNS servers configured on the VNet."
  type        = list(string)
  default     = null
}

variable "bgp_community" {
  description = "BGP community associated with the VNet."
  type        = string
  default     = null
}

variable "edge_zone" {
  description = "Azure edge zone for the VNet."
  type        = string
  default     = null
}

variable "flow_timeout_in_minutes" {
  description = "VNet flow timeout in minutes."
  type        = number
  default     = null
}

variable "private_endpoint_vnet_policies" {
  description = "Private endpoint network policies for the VNet."
  type        = string
  default     = null
}

variable "nva_ip" {
  description = "Virtual appliance IP used as the next hop for generated subnet route tables."
  type        = string
  default     = null
}

variable "route_security_vnet_through_nva" {
  description = "Whether generated subnet route tables should send security VNet address spaces through the NVA."
  type        = bool
  default     = true
}

variable "subnets" {
  description = "Subnets to create in the VNet and their optional policies, delegations, routes, and NSGs."
  type = map(object({
    address_prefixes = list(string)

    create_dedicated_route_table = optional(bool)
    additional_nva_routes = optional(map(object({
      address_prefix         = string
      next_hop_type          = optional(string, "VirtualAppliance")
      next_hop_in_ip_address = optional(string)
    })), {})
    default_outbound_access_enabled               = optional(bool, true)
    service_endpoints                             = optional(list(string), [])
    service_endpoint_policy_ids                   = optional(list(string), [])
    sharing_scope                                 = optional(string)
    private_endpoint_network_policies             = optional(string, "Enabled")
    private_link_service_network_policies_enabled = optional(bool, true)

    delegations = optional(map(object({
      name    = string
      actions = list(string)
    })), {})

    route_table = optional(object({
      name                          = optional(string)
      bgp_route_propagation_enabled = optional(bool, false)
      routes = optional(map(object({
        address_prefix         = string
        next_hop_type          = string
        next_hop_in_ip_address = optional(string)
      })), {})
    }))

    nsg = optional(object({
      enabled = optional(bool, true)
      name    = optional(string)
      profile = optional(string, "none")
      rules = optional(map(object({
        priority                                   = number
        direction                                  = string
        access                                     = string
        protocol                                   = optional(string, "*")
        description                                = optional(string)
        source_port_range                          = optional(string)
        source_port_ranges                         = optional(list(string))
        destination_port_range                     = optional(string)
        destination_port_ranges                    = optional(list(string))
        source_address_prefix                      = optional(string)
        source_address_prefixes                    = optional(list(string))
        source_application_security_group_ids      = optional(list(string))
        destination_address_prefix                 = optional(string)
        destination_address_prefixes               = optional(list(string))
        destination_application_security_group_ids = optional(list(string))
      })), {})
    }))
  }))

  validation {
    condition = alltrue([
      for subnet in values(var.subnets) : contains(
        ["none", "deny_internet_inbound"],
        try(subnet.nsg.profile, "none")
      )
    ])
    error_message = "Each subnet NSG profile must be one of: none, deny_internet_inbound."
  }
}

variable "security_vnet" {
  description = "Security VNet to peer with this spoke VNet. The local peering is always created; the remote peering is optional for cross-tenant deployments."
  type = object({
    id                           = string
    name                         = string
    resource_group_name          = string
    address_space                = optional(list(string), [])
    create_remote_peering        = optional(bool, true)
    allow_forwarded_traffic      = optional(bool, true)
    allow_gateway_transit        = optional(bool, false)
    allow_virtual_network_access = optional(bool, true)
    use_remote_gateways          = optional(bool, false)
  })
  default = null
}

variable "additional_peerings" {
  description = "Additional peerings from this VNet to external VNets."
  type = map(object({
    name                         = string
    remote_virtual_network_id    = string
    allow_forwarded_traffic      = optional(bool, true)
    allow_gateway_transit        = optional(bool, false)
    allow_virtual_network_access = optional(bool, true)
    use_remote_gateways          = optional(bool, false)
  }))
  default = {}
}

variable "route_tables" {
  description = "Custom route tables to create and associate to subnets."
  type = map(object({
    name                          = string
    subnet_key                    = string
    bgp_route_propagation_enabled = optional(bool, false)
    routes = map(object({
      address_prefix         = string
      next_hop_type          = string
      next_hop_in_ip_address = optional(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for route_table in values(var.route_tables) : contains(keys(var.subnets), route_table.subnet_key)])
    error_message = "Each route_tables subnet_key must reference a subnet key in var.subnets."
  }
}
