# Azure Infrastructure Resources

# Resource group containing all resources
resource "azurerm_resource_group" "rancher-rg" {
  name      = "${local.prefix}-rg"
  location  = local.provider_config.region

  tags      = local.tags
}

# Public IP of Rancher servers
resource "azurerm_public_ip" "upstream-public-ips" {
  count               = local.provider_config.upstream.quantity
  name                = "${local.prefix}-public-ip-upstream-${count.index}"
  location            = azurerm_resource_group.rancher-rg.location
  resource_group_name = azurerm_resource_group.rancher-rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${local.prefix}-upstream-${count.index}"

  tags                = local.tags
}

# Azure virtual network space for quickstart resources
resource "azurerm_virtual_network" "rancher-vnet" {
  name                = "${local.prefix}-vnet"
  address_space       = local.local_network_block
  location            = azurerm_resource_group.rancher-rg.location
  resource_group_name = azurerm_resource_group.rancher-rg.name

  tags                = local.tags
}

# Azure internal subnet for quickstart resources
resource "azurerm_subnet" "rancher-subnet" {
  name                  = "${local.prefix}-subnet"
  resource_group_name   = azurerm_resource_group.rancher-rg.name
  virtual_network_name  = azurerm_virtual_network.rancher-vnet.name
  address_prefixes      = try(
    [local.provider_config.local_subnet_block], 
    azurerm_virtual_network.rancher-vnet.address_space
  )
}

# Azure network interface for quickstart resources
resource "azurerm_network_interface" "upstream-interfaces" {
  count                 = local.provider_config.upstream.quantity
  name                  = "${local.prefix}-interface-upstream-${count.index}"
  location              = azurerm_resource_group.rancher-rg.location
  resource_group_name   = azurerm_resource_group.rancher-rg.name

  ip_configuration {
    name                  = "${local.prefix}-ipconfig-upstream-${count.index}"
    subnet_id             = azurerm_subnet.rancher-subnet.id
    private_ip_address_allocation =  "Dynamic"
    public_ip_address_id  = azurerm_public_ip.upstream-public-ips[count.index].id
  }

  tags                    = local.tags
}

# Azure linux virtual machine for creating a single node RKE cluster and installing the Rancher Server
resource "azurerm_linux_virtual_machine" "upstream-vms" {
  count                 = local.provider_config.upstream.quantity
  name                  = "vm-upstream-${count.index}"
  computer_name         = substr("upstream-${count.index}", 0, 15) // 15 char limit
  location              = azurerm_resource_group.rancher-rg.location
  resource_group_name   = azurerm_resource_group.rancher-rg.name
  network_interface_ids = [azurerm_network_interface.upstream-interfaces[count.index].id]
  size                  = local.upstream.selected_server_sizes[count.index]
  admin_username        = local.server_user

  source_image_reference {
    publisher = local.provider_config.upstream.image.publisher
    offer     = local.provider_config.upstream.image.offer
    sku       = local.provider_config.upstream.image.sku
    version   = local.provider_config.upstream.image.version
  }

  admin_ssh_key {
    username   = local.server_user
    public_key = file(local.group_config.ansible_ssh_public_key_file)
  }

  os_disk {
    caching              = local.upstream.storage-caching
    storage_account_type = local.upstream.storage-account-type
  }

  tags                   = local.tags
  provisioner "remote-exec" {
    inline = [ 
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
     ]

     connection {
       type         = "ssh"
       host         = self.public_ip_address
       user         = local.server_user
       private_key  = file(local.group_config.ansible_ssh_private_key_file)
     }
  }
}

# Rancher resources
module "rancher_common" {
  source = "../rancher-common"
  #### To DO use list
  node_public_ip             = azurerm_linux_virtual_machine.upstream-vms[0].public_ip_address
  node_internal_ip           = azurerm_linux_virtual_machine.upstream-vms[0].private_ip_address
  node_username              = local.server_user
  # how to generate pem from ppk: https://repost.aws/knowledge-center/ec2-ppk-pem-conversion
  ssh_private_key_pem        = file(local.group_config.ansible_ssh_private_key_file)
  rancher_kubernetes_version = local.upstream.rancher_kubernetes_version

  cert_manager_version    = local.cert_manager_version
  rancher_version         = local.rancher_version
  rancher_helm_repository = local.rancher_helm_repository

  rancher_server_dns = join(".",
    [
      "rancher", azurerm_public_ip.upstream-public-ips[0].domain_name_label,
      azurerm_resource_group.rancher-rg.location,
      "cloudapp.azure.com"
      # "sslip.io"
    ]
  )

  admin_password = var.rancher_server_admin_password

  workload_kubernetes_version = local.downstream.workload_kubernetes_version
  workload_cluster_name       = local.downstream_cluster_name
}

# Public IP of user/workload/downstream cluster
resource "azurerm_public_ip" "downstream-public-ips" {
  count               = local.provider_config.downstream.quantity
  name                = "${local.prefix}-public-ip-downstream-${count.index}"
  location            = azurerm_resource_group.rancher-rg.location
  resource_group_name = azurerm_resource_group.rancher-rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${local.prefix}-downstream-${count.index}"

  tags                = local.tags
}

# Azure network interface for user/workload/downstream servers
resource "azurerm_network_interface" "downstream-interfaces" {
  count                 = local.provider_config.downstream.quantity
  name                  = "${local.prefix}-interface-downstream-${count.index}"
  location              = azurerm_resource_group.rancher-rg.location
  resource_group_name   = azurerm_resource_group.rancher-rg.name

  ip_configuration {
    name                  = "${local.prefix}-ipconfig-downstream-${count.index}"
    subnet_id             = azurerm_subnet.rancher-subnet.id
    private_ip_address_allocation =  "Dynamic"
    public_ip_address_id  = azurerm_public_ip.downstream-public-ips[count.index].id
  }

  tags                    = local.tags
}

# Azure linux virtual machine for creating a single node RKE cluster and installing the Rancher Server
resource "azurerm_linux_virtual_machine" "downstream-vms" {
  count                 = local.provider_config.downstream.quantity
  name                  = "vm-downstream-${count.index}"
  computer_name         = substr("downstream-${count.index}", 0, 15) // 15 char limit
  location              = azurerm_resource_group.rancher-rg.location
  resource_group_name   = azurerm_resource_group.rancher-rg.name
  network_interface_ids = [azurerm_network_interface.downstream-interfaces[count.index].id]
  size                  = local.downstream.selected_server_sizes[count.index]
  admin_username        = local.server_user

  custom_data = base64encode(
    templatefile(
      "${path.module}/files/userdata_quickstart_node.template",
      {
        register_command = module.rancher_common.custom_cluster_command
      }
    )
  )

  source_image_reference {
    publisher = local.provider_config.downstream.image.publisher
    offer = local.provider_config.downstream.image.offer
    sku = local.provider_config.downstream.image.sku
    version = local.provider_config.downstream.image.version
  }

  admin_ssh_key {
    username   = local.server_user
    public_key = file(local.group_config.ansible_ssh_public_key_file)
  }

  os_disk {
    caching              = local.downstream.storage-caching
    storage_account_type = local.downstream.storage-account-type
  }

  tags                   = local.tags

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait > /dev/null",
      "echo 'Completed cloud-init!'",
    ]

    connection {
      type        = "ssh"
      host        = self.public_ip_address
      user        = local.node_username
      private_key = file(local.group_config.ansible_ssh_private_key_file)
    }
  }
}
