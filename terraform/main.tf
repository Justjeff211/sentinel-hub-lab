terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstate3691e4ab"
    container_name       = "tfstate"
    key                  = "sentinel-hub-lab.tfstate"
    use_azuread_auth     = false
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

# VPN Gateway removed 12 Aug 2026 - was never actually used (no site-to-site
# or point-to-site connection ever configured) and was the single most
# expensive idle resource in the stack. GatewaySubnet is left in place below
# in case it's genuinely needed later.

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

# ---------------------------------------------------------------------------
# Telemetry: Log Analytics + Azure Monitor Agent (Windows Event Logs)
#
# Scope note: this covers Windows host telemetry only. Zeek and Suricata
# (network-level monitoring) need a dedicated sensor with visibility into
# real traffic - deliberately deferred until there's a workload/Kali VM
# actually generating something worth watching.
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "soc" {
  name                = "law-soc-hub-lab"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_data_collection_endpoint" "soc" {
  name                = "dce-soc-hub-lab"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_monitor_data_collection_rule" "windows_events" {
  name                        = "dcr-windows-events"
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.soc.id

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.soc.id
      name                  = "law-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["law-destination"]
  }

  data_sources {
    windows_event_log {
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "Security!*",
        "System!*",
        "Application!*",
        "Microsoft-Windows-Sysmon/Operational!*"
      ]
      name = "windowsEventLogs"
    }
  }
}

resource "azurerm_virtual_machine_extension" "ama_dc1" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc1.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule_association" "dc1" {
  name                    = "dcra-dc1"
  target_resource_id      = azurerm_windows_virtual_machine.dc1.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows_events.id
  depends_on              = [azurerm_virtual_machine_extension.ama_dc1]
}

resource "azurerm_virtual_machine_extension" "ama_aadconnect" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.aadconnect.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule_association" "aadconnect" {
  name                    = "dcra-aadconnect"
  target_resource_id      = azurerm_windows_virtual_machine.aadconnect.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows_events.id
  depends_on              = [azurerm_virtual_machine_extension.ama_aadconnect]
}

# ---------------------------------------------------------------------------
# Production Workloads spoke
#
# Scope for tonight: one Ubuntu box, host-based Zeek/Suricata (monitoring
# its own traffic) rather than a dedicated network-wide sensor with traffic
# mirroring - that's a genuinely bigger piece (Azure VNet TAP + route tables)
# deliberately left for a future session.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "workloads" {
  name                = "vnet-workloads"
  address_space       = ["10.30.0.0/24"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "workloads" {
  name                 = "snet-workloads"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.workloads.name
  address_prefixes     = ["10.30.0.0/25"]
}

resource "azurerm_virtual_network_peering" "hub_to_workloads" {
  name                       = "peer-hub-to-workloads"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.workloads.id
}

resource "azurerm_virtual_network_peering" "workloads_to_hub" {
  name                       = "peer-workloads-to-hub"
  resource_group_name       = azurerm_resource_group.this.name
  virtual_network_name      = azurerm_virtual_network.workloads.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
}

# SSH only reachable from the hub (i.e. via Bastion) - no direct internet rule, same pattern as the identity NSG.
resource "azurerm_network_security_group" "workloads" {
  name                = "nsg-workloads"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowSshFromHub"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.10.0.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workloads" {
  subnet_id                 = azurerm_subnet.workloads.id
  network_security_group_id = azurerm_network_security_group.workloads.id
}

resource "azurerm_network_interface" "ubuntu" {
  name                = "nic-ubuntu"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.workloads.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.30.0.4"
  }
}

resource "azurerm_linux_virtual_machine" "ubuntu" {
  name                            = "vm-ubuntu"
  computer_name                   = "ubuntu-workload"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.ubuntu.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}
