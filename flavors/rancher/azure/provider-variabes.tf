# value will be passed at runtime
# var.group will be provided from cli -var 'group=group_name'

locals {
  # get environment name from parent folder
  parent_path = abspath("${path.module}")
  folder_name = basename(local.parent_path)
  parent_folder_name = basename(dirname(local.parent_path))
  # group is synonymous to environment here
  group = split("-", local.parent_folder_name)[1] # eg. dev

  # read ansible group_vars related to this group/environment
  # eg. read group_vars/dev.yaml
  group_config  = yamldecode(file("../../group_vars/${local.group}.yml"))
  provider_config = local.group_config.flavour.rancher[local.folder_name]

  prefix = try(local.group_config.prefix, "")
}

locals {
  server_user = local.group_config.ansible_user
  
  # "Version of cert-manager to install alongside Rancher (format: 0.0.0)"
  cert_manager_version = try(
    local.provider_config.cert_manager_version,
    "1.11.0"
  )
  #"Rancher server version (format: v0.0.0)"
  rancher_version = try(
    local.provider_config.rancher_version,
    "2.7.9"
  )
  # "The helm repository, where the Rancher helm chart is installed from"
  rancher_helm_repository = try(
    local.provider_config.rancher_helm_repository,
    "https://releases.rancher.com/server-charts/latest"
  )
  # Name of workload/user/downstream cluster
  downstream_cluster_name = try(
    local.provider_config.workload_cluster_name,
    "downstream-cluster"
  )
}

locals {
  local_network_block = [
    try(local.provider_config.local_network_block, "10.0.0.0/16")
  ]
  allowed_ports = try(
    local.provider_config.security_rules.allowed_ports, 
    [22, 80, 443, 8443]
  )
  allowed_source_address_prefix = try(
    local.provider_config.security_rules.allowed_source_address_prefix, 
    "0.0.0.0/0"
  )
  allowed_destination_address_prefix = try(
    local.provider_config.security_rules.allowed_destination_address_prefix, 
    "0.0.0.0/0"
  )
}

locals {
  tags = merge(
    try(local.group_config.tag, {}),
    try(local.provider_config.tag, {})
  )
}

locals {
  upstream = {
    # assign server size from custom_sizes list
    # If custom_sizes list is smaller than server quantity,
    # then all extra servers will take the size of the last item in the custom_sizes list
    # if custom_sizes list is not defined or it is empty, then create a list of default sizes
    custom_size_map = (
      try(length(local.provider_config.upstream.custom_sizes) > 0, false) ?
        [
          for i in range(0, local.provider_config.upstream.quantity) :
            local.provider_config.upstream.custom_sizes[
              min(max(0,i), length(local.provider_config.upstream.custom_sizes) - 1)
            ]
        ] : []
    )

    storage_account_type = try(
      local.provider_config.upstream.storage_account_type,
      "StandardSSD_LRS"
    )
    # "The general caching requirements to use for storages
    storage_caching = try(
      local.provider_config.upstream.storage_caching,
      "ReadWrite"
    )

    # "Kubernetes version to use for Rancher server cluster"
    rancher_kubernetes_version = try(
      local.provider_config.upstream.rancher_kubernetes_version,
      "v1.24.14+k3s1"
    )

  server_sizes = {
  "nano"     = [for _ in range(0, local.provider_config.quantity) : "Standard_B1s"] 
  "micro"    = [for _ in range(0, local.provider_config.quantity) : "Standard_B2s"]
  "small"    = [for _ in range(0, local.provider_config.quantity) : "Standard_D2s_v3"]
  # pricing danger zone
  "medium"   = [for _ in range(0, local.provider_config.quantity) : "Standard_D4s_v3"]
  "large"    = [for _ in range(0, local.provider_config.quantity) : "Standard_D8s_v3"]
  "xlarge"   = [for _ in range(0, local.provider_config.quantity) : "Standard_D16s_v3"]
  "2xlarge"  = [for _ in range(0, local.provider_config.quantity) : "Standard_D32s_v3"]
  "custom"   = local.upstream.custom_size_map
  }

  selected_server_sizes = (
    local.upstream.server_sizes[
      local.provider_config.upstream.size
      ]
  )
}

  downstream = {
    custom_size_map = (
    try(length(local.provider_config.downstream.custom_sizes) > 0, false) ?
      [
        for i in range(0, local.provider_config.downstream.quantity) :
          local.provider_config.downstream.custom_sizes[
            min(max(0,i), length(local.provider_config.downstream.custom_sizes) - 1)
          ]
      ] : []
    )

    # "The general storage account type to use for storages"
    storage_account_type = try(
      local.provider_config.downstream.storage_account_type,
      "StandardSSD_LRS"
    )

    storage_caching = try(
      local.provider_config.downstream.storage_caching,
      "ReadWrite"
    )

    # "Kubernetes version to use for managed workload/user/downstream cluster"
    rancher_kubernetes_version = try(
      local.provider_config.downstream.rancher_kubernetes_version,
      "v1.24.14+rke2r1"
    )

    
  }
}
