terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Auth isn't set here. Locally, run `az login` first and the provider uses
# that session. In GitHub Actions later, it'll read ARM_* env vars from
# repo secrets instead.
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# ---------------------------------------------------------------------------
# Hub VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  address_space       = ["10.10.0.0/24"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

# Subnet name is fixed by Azure - Firewall only deploys into a subnet named exactly this.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.0/26"]
}

# Subnet name is fixed by Azure - Bastion only deploys into a subnet named exactly this.
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.64/26"]
}

# Subnet name is fixed by Azure - the VPN Gateway only deploys into a subnet named exactly this.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.128/27"]
}

resource "azurerm_subnet" "management" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.10.0.160/27"]
}

# ---------------------------------------------------------------------------
# Identity Spoke
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "identity" {
  name                = "vnet-identity"
  address_space       = ["10.20.0.0/24"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  # Points identity-spoke DNS at DC1 once it's promoted. DC1's IP is fixed
  # below so this doesn't create a chicken-and-egg dependency problem.
  dns_servers = ["10.20.0.4"]
}

resource "azurerm_subnet" "identity" {
  name                 = "snet-identity"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.identity.name
  address_prefixes     = ["10.20.0.0/25"]
}

resource "azurerm_virtual_network_peering" "hub_to_identity" {
  name                       = "peer-hub-to-identity"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.identity.id
}

resource "azurerm_virtual_network_peering" "identity_to_hub" {
  name                       = "peer-identity-to-hub"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.identity.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
}

# ---------------------------------------------------------------------------
# Network security
# ---------------------------------------------------------------------------

# Azure requires these exact rules before it will let Bastion deploy into
# a subnet at all - this isn't optional configuration, it's the minimum
# Bastion needs to function. See: https://learn.microsoft.com/azure/bastion/bastion-nsg
resource "azurerm_network_security_group" "bastion" {
  name                = "nsg-bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowBastionHostCommunicationInbound"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowSshRdpOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["22", "3389"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowBastionHostCommunicationOutbound"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowGetSessionInformationOutbound"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "bastion" {
  subnet_id                 = azurerm_subnet.bastion.id
  network_security_group_id = azurerm_network_security_group.bastion.id
}

# RDP is only reachable from the hub (i.e. via Bastion) - no direct internet rule exists here at all.
resource "azurerm_network_security_group" "identity" {
  name                = "nsg-identity"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowRdpFromHub"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "10.10.0.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "identity" {
  subnet_id                 = azurerm_subnet.identity.id
  network_security_group_id = azurerm_network_security_group.identity.id
}

# ---------------------------------------------------------------------------
# Hub services: Firewall, Bastion, VPN Gateway
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "hub" {
  name                = "fw-hub"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"

  ip_configuration {
    name                 = "fw-ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "hub" {
  name                = "bastion-hub"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Basic"

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# Costs money the moment it exists, whether or not it's carrying traffic.
# Comment this out (and its public IP above) if you don't need it yet -
# nothing else in this file depends on it.
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-vpngw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

resource "azurerm_virtual_network_gateway" "hub" {
  name                = "vpngw-hub"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "Basic"

  ip_configuration {
    name                          = "vpngw-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}

# ---------------------------------------------------------------------------
# Identity: DC1 and Entra Connect
#
# Both VMs are provisioned here, network and all. What's NOT automated:
# promoting DC1 to a domain controller, and installing Entra Connect.
# Both need interactive steps (a Safe Mode password and reboot for the
# former, a Global Admin sign-in for the latter) that don't belong in a
# public repo's Terraform. Do both manually over Bastion once apply finishes.
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "dc1" {
  name                = "nic-dc1"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.identity.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.20.0.4"
  }
}

resource "azurerm_windows_virtual_machine" "dc1" {
  name                = "vm-dc1"
  computer_name       = "DC1"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.dc1.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "aadconnect" {
  name                = "nic-aadconnect"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.identity.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.20.0.5"
  }
}

resource "azurerm_windows_virtual_machine" "aadconnect" {
  name                = "vm-aadconnect"
  computer_name       = "AADCONNECT"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.aadconnect.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}
