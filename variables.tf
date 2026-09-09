variable "name" {
  description = "Name of the spoke virtual network."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the spoke virtual network."
  type        = string
}

variable "location" {
  description = "Azure region for the spoke virtual network."
  type        = string
}

variable "address_space" {
  description = "Address space(s) for the spoke virtual network."
  type        = list(string)
}

variable "dns_servers" {
  description = "Custom DNS servers for the spoke virtual network."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the spoke virtual network."
  type        = map(string)
  default     = {}
}
