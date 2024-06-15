# Variables for Azure infrastructure module

# variable "azure_subscription_id" {
#   type        = string
#   description = "Azure subscription id under which resources will be provisioned"
# }

# variable "azure_client_id" {
#   type        = string
#   description = "Azure client id used to create resources"
# }

# variable "azure_client_secret" {
#   type        = string
#   description = "Client secret used to authenticate with Azure apis"
# }

# variable "azure_tenant_id" {
#   type        = string
#   description = "Azure tenant id used to create resources"
# }

# variable "azure_location" {
#   type        = string
#   description = "Azure location used for all resources"
#   default     = "East US"
# }

variable "prefix" {
  type        = string
  description = "Prefix added to names of all resources"
  default     = "quickstart"
}

variable "instance_type" {
  type        = string
  description = "Instance type used for all linux virtual machines"
  default     = "Standard_DS2_v2"
}


# Required
variable "add_windows_node" {
  type        = bool
  description = "Add a windows node to the workload cluster"
  default     = false
}

# Required
variable "rancher_server_admin_password" {
  type        = string
  description = "Admin password to use for Rancher server bootstrap, min. 12 characters"
  default     = "vpass.14+k279"
}

# Required
variable "windows_admin_password" {
  type        = string
  description = "Admin password to use for the Windows VM"
}

# Local variables used to reduce repetition
locals {
  node_username = "azureuser"
}
