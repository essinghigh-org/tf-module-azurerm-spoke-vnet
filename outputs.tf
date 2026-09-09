output "id" {
  description = "Resource ID of the spoke virtual network."
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "Name of the spoke virtual network."
  value       = azurerm_virtual_network.this.name
}

output "address_space" {
  description = "Address space(s) of the spoke virtual network."
  value       = azurerm_virtual_network.this.address_space
}
