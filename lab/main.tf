provider "azurerm" {
    version = "=1.38.0"

    subscription_id = var.authentication.subscription_id
    client_id       = var.authentication.client_id
    client_secret   = var.authentication.client_secret
    tenant_id       = var.authentication.tenant_id
}

# Create lab virtual network
resource "azurerm_virtual_network" "vnet" {
    name                = "${var.prefix}-vnet"
    address_space       = ["10.0.0.0/16"]
    location            = var.location
    resource_group_name = "${var.prefix}"
    tags                = var.tags
}

# Create network security group and rules
resource "azurerm_network_security_group" "nsg" {
    name                = "${var.prefix}-nsg"
    location            = var.location
    resource_group_name = "${var.prefix}"
    tags                = var.tags
    depends_on          = [azurerm_virtual_network.vnet]

    security_rule {
        name                       = "RDP"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3389"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "HTTP-inbound"
        priority                   = 102
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "HTTPS-inbound"
        priority                   = 103
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "HTTP-outbound"
        priority                   = 104
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "HTTPS-outbound"
        priority                   = 105
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

# Create lab subnet
resource "azurerm_subnet" "subnet" {
    name                        = "${var.prefix}-subnet"
    resource_group_name         = "${var.prefix}"
    virtual_network_name        = azurerm_virtual_network.vnet.name
    address_prefix              = "10.0.1.0/24"
    network_security_group_id   = azurerm_network_security_group.nsg.id
    depends_on                  = [azurerm_network_security_group.nsg]
}

# Create storage account
resource "azurerm_storage_account" "storageaccount" {
  name                     = "${var.prefix}sablobstrg01"
  resource_group_name      = "${var.prefix}"
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  depends_on               = [azurerm_subnet.subnet]
}

# Create blob storage container for post configuration files
resource "azurerm_storage_container" "blobstorage" {
  name                  = "${var.prefix}-store1"
  storage_account_name  = azurerm_storage_account.storageaccount.name
  container_access_type = "blob"
  depends_on            = [azurerm_storage_account.storageaccount]
}

# Create storage blob for install-utilities.ps1 file
resource "azurerm_storage_blob" "utilsblob" {
  depends_on             = [azurerm_storage_container.blobstorage]
  name                   = "install-utilities.ps1"
  storage_account_name   = azurerm_storage_account.storageaccount.name
  storage_container_name = azurerm_storage_container.blobstorage.name
  type                   = "block"
  source                 =  "./files/install-utilities.ps1"
}

# Create storage blob for create-ad.ps1 file
resource "azurerm_storage_blob" "adblob" {
  depends_on             = [azurerm_storage_blob.utilsblob]
  name                   = "create-ad.ps1"
  storage_account_name   = azurerm_storage_account.storageaccount.name
  storage_container_name = azurerm_storage_container.blobstorage.name
  type                   = "block"
  source                 =  "./files/create-ad.ps1"
}

# Create public ip for domain controller 1
resource "azurerm_public_ip" "dc1_publicip" {
    name                         = "${var.workstations.dc1}-external"
    location                     = var.location
    resource_group_name          = "${var.prefix}"
    allocation_method            = "Dynamic"
    tags                         = var.tags
    depends_on                   = [azurerm_storage_blob.adblob]
}

# Create network interface for domain controller 1
resource "azurerm_network_interface" "dc1_nic" {
    name                      = "${var.workstations.dc1}-primary"
    location                  = var.location
    resource_group_name       = "${var.prefix}"
    network_security_group_id = azurerm_network_security_group.nsg.id
    tags                      = var.tags

    ip_configuration {
        name                          = "${var.workstations.dc1}-nic-conf"
        subnet_id                     = azurerm_subnet.subnet.id
        private_ip_address_allocation = "dynamic"
        public_ip_address_id          = azurerm_public_ip.dc1_publicip.id
    }
    depends_on = [azurerm_public_ip.dc1_publicip]
}

# Deploy domain controller 1
resource "azurerm_virtual_machine" "dc1" {
  name                          = var.workstations.dc1
  location                      = var.location
  resource_group_name           = "${var.prefix}"
  network_interface_ids         = ["${azurerm_network_interface.dc1_nic.id}"]
  vm_size                       = var.workstations.vm_size
  tags                          = var.tags

  # This means the OS Disk will be deleted when Terraform destroys the Virtual Machine
  # This may not be optimal in all cases.
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2012-R2-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.workstations.dc1}-disk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = var.workstations.dc1
    admin_username = var.accounts.dc1_admin_user
    admin_password = var.accounts.dc1_admin_password
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = false

    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "AutoLogon"
      content      = "<AutoLogon><Password><Value>${var.accounts.dc1_admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.accounts.dc1_admin_user}</Username></AutoLogon>"
    }
  }
  depends_on = [azurerm_network_interface.dc1_nic]
}

# Create active directory domain forest
resource "azurerm_virtual_machine_extension" "create_ad" {
  name                 = "create_ad"
  location             = var.location
  resource_group_name  = "${var.prefix}"
  virtual_machine_name = azurerm_virtual_machine.dc1.name
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  tags                 = var.tags
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storageaccount.name}.blob.core.windows.net/${azurerm_storage_container.blobstorage.name}/create-ad.ps1"],
        "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File create-ad.ps1"
    }
SETTINGS
  depends_on = [azurerm_virtual_machine.dc1]
}
 
# Create public IP for workstation 1
resource "azurerm_public_ip" "pc1_publicip" {
  name                         = "${var.workstations.pc1}-external"
  location                     = var.location
  resource_group_name          = "${var.prefix}"
  allocation_method            = "Dynamic"
  tags                         = var.tags
  depends_on                   = [azurerm_virtual_machine_extension.create_ad]
}

# Create network interface for workstation 1
resource "azurerm_network_interface" "pc1_nic" {
  name                      = "${var.workstations.pc1}-primary"
  location                  = var.location
  resource_group_name       = "${var.prefix}"
  network_security_group_id = azurerm_network_security_group.nsg.id
  tags                      = var.tags#
  ip_configuration {
      name                          = "${var.workstations.pc1}-nic-conf"
      subnet_id                     = azurerm_subnet.subnet.id
      private_ip_address_allocation = "dynamic"
      public_ip_address_id          = azurerm_public_ip.pc1_publicip.id
  }
  depends_on = [azurerm_public_ip.pc1_publicip]
}

# Create workstation 1
resource "azurerm_virtual_machine" "pc1" {
  name                  = var.workstations.pc1
  location              = var.location
  resource_group_name   = "${var.prefix}"
  network_interface_ids = ["${azurerm_network_interface.pc1_nic.id}"]
  vm_size               = var.workstations.vm_size
  tags                  = var.tags

  # This means the OS Disk will be deleted when Terraform destroys the Virtual Machine
  # This may not be optimal in all cases.
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = var.workstations.os_manufacturer
    offer     = var.workstations.os_type
    sku       = var.workstations.os_sku
    version   = var.workstations.os_version
  }

  storage_os_disk {
    name              = "${var.workstations.pc1}-disk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = var.workstations.pc1
    admin_username = var.accounts.pc1_admin_user
    admin_password = var.accounts.pc1_admin_password
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = false

    additional_unattend_config {
      pass         = "oobeSystem"
      component    = "Microsoft-Windows-Shell-Setup"
      setting_name = "AutoLogon"
      content      = "<AutoLogon><Password><Value>${var.accounts.pc1_admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.accounts.pc1_admin_user}</Username></AutoLogon>"
    }
  }
  depends_on = [azurerm_network_interface.pc1_nic]
}
 
# Install utilities on workstation 1 and join domain
resource "azurerm_virtual_machine_extension" "utils_pc1" {
  name                 = "utils_pc1"
  location             = var.location
  resource_group_name  = "${var.prefix}"
  virtual_machine_name = azurerm_virtual_machine.pc1.name
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  tags                 = var.tags
  settings = <<SETTINGS
    {
        "fileUris": ["https://${azurerm_storage_account.storageaccount.name}.blob.core.windows.net/${azurerm_storage_container.blobstorage.name}/install-utilities.ps1"],
        "commandToExecute": "powershell -ExecutionPolicy Unrestricted -File install-utilities.ps1"
    }
SETTINGS
  depends_on = [azurerm_storage_blob.utilsblob]
}
