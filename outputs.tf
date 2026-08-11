output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "firewall_public_ip" {
  value = azurerm_public_ip.firewall.ip_address
}

output "bastion_public_ip" {
  value = azurerm_public_ip.bastion.ip_address
}

output "dc1_private_ip" {
  value = azurerm_network_interface.dc1.private_ip_address
}

output "aadconnect_private_ip" {
  value = azurerm_network_interface.aadconnect.private_ip_address
}
