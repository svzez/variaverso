# Make sure that the backend for the tf state files is setup properly
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.55.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#####

variable "base_name" {
  description = "Base name to be used as a prefix for the resources created"
}

variable "resource_group_name" {
  description = "Resource Group where to deploy the VM"
}

variable "source_address_prefixes" {
  description = "List of source address prefixes allowed to access the VM for administration"
  type        = list(string)
}

variable "private_address_space" {
  description = "List of the private ip address cidr used for the new virtaul network"
  type        = string
}

variable "private_subnet_address_prefix" {
  description = "The address prefix to be used for the subnet"
  type        = string
}

variable "azure_key_vault_name" {
  description = "The name of the Azure Key Vault with the deployment secrets"
  type        = string
}

#####

locals {
  vm_name              = "${var.base_name}-vm"
  virtual_network_name = "${var.base_name}-network"
  azure_subnet_name    = "${var.base_name}-subnet"
}

#####

data "azurerm_resource_group" "resource_group" {
  name = var.resource_group_name
}

data "azurerm_subscription" "current" {}

data "azurerm_key_vault" "monitoring_secrets" {
  name                = var.azure_key_vault_name
  resource_group_name = data.azurerm_resource_group.resource_group.name
}

#####

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.base_name}-security-group"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "securityrule-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.source_address_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.resource_group.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "k3s" {
  name                        = "securityrule-k3s"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefixes     = var.source_address_prefixes
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.resource_group.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "http" {
  name                        = "securityrule-http"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.resource_group.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_security_rule" "https" {
  name                        = "securityrule-httpss"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = data.azurerm_resource_group.resource_group.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.base_name}-vnet"
  address_space       = [var.private_address_space]
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.base_name}-subnet"
  resource_group_name  = data.azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.private_subnet_address_prefix]
}

resource "random_string" "dns_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${local.vm_name}-public-ip"
  resource_group_name = data.azurerm_resource_group.resource_group.name
  location            = data.azurerm_resource_group.resource_group.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${local.vm_name}-${random_string.dns_suffix.result}"
}

resource "azurerm_network_interface" "main" {
  name                = "${local.vm_name}-nic"
  location            = data.azurerm_resource_group.resource_group.location
  resource_group_name = data.azurerm_resource_group.resource_group.name

  ip_configuration {
    name                          = "${var.base_name}-ipconfiguration1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${local.vm_name}"
  resource_group_name   = data.azurerm_resource_group.resource_group.name
  location              = data.azurerm_resource_group.resource_group.location
  network_interface_ids = [azurerm_network_interface.main.id]
  size                  = "Standard_B1ms"

  os_disk {
    name                 = "${local.vm_name}-os"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "minimal"
    version   = "latest"
  }

  computer_name                   = local.vm_name
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("id_rsa.pub")
  }

  # ENABLE MANAGED IDENTITY
  identity {
    type = "SystemAssigned"
  }
}

# Grant the VM access to read Azure Monitor data
resource "azurerm_role_assignment" "vm_monitor_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}

# Grant the VM "Read" access to ALL secrets in this Vault
resource "azurerm_role_assignment" "vm_kv_global_read" {
  # The Scope is the entire Key Vault ID
  scope                = data.azurerm_key_vault.monitoring_secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}

#######

output "public_ip" {
  value = azurerm_public_ip.public_ip
  description = "Need it to setup Cloudflare DNS record"
}