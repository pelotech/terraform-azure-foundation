variable "name" {
  type        = string
  description = "Name of the AKS cluster. It is also the DNS prefix and the base of every generated resource name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,52}[a-z0-9]$", var.name))
    error_message = "name must be 2-54 characters of lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "create_cluster" {
  type        = bool
  default     = true
  description = "Creates the AKS cluster and every resource that depends on it. The VNet, NAT Gateway, private endpoints and storage account have their own switches."
}

variable "location" {
  type        = string
  description = "Azure region for every resource, for example usgovvirginia."
}

variable "azure_cloud" {
  type        = string
  default     = "public"
  description = "Azure cloud for the kubelogin --environment flag in kube_exec: public or usgovernment. Set it to the same cloud as your azurerm provider."

  validation {
    condition     = contains(["public", "usgovernment"], var.azure_cloud)
    error_message = "azure_cloud must be one of: public, usgovernment."
  }
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Resource group for every resource. null generates rg-<name>."
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Creates the resource group. Set false to use an existing group named resource_group_name."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for every resource. The Owner tag, when present, seeds the blob CSI storage account name."
}

variable "cluster_version" {
  type        = string
  default     = "1.35"
  description = "Kubernetes version in MAJOR.MINOR form. AKS picks the patch version."

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.cluster_version))
    error_message = "cluster_version must be in MAJOR.MINOR form, for example \"1.35\"."
  }
}

variable "kube_exec_login_mode" {
  type        = string
  default     = "azurecli"
  description = "kubelogin --login mode in kube_exec. azurecli reuses your az session; use spn, msi or workloadidentity in CI."

  validation {
    condition     = contains(["devicecode", "interactive", "spn", "ropc", "msi", "azurecli", "azd", "workloadidentity", "azurepipelines"], var.kube_exec_login_mode)
    error_message = "kube_exec_login_mode must be a kubelogin login mode: devicecode, interactive, spn, ropc, msi, azurecli, azd, workloadidentity, azurepipelines."
  }
}

variable "vnet" {
  type = object({
    cidr                 = optional(string, "10.0.0.0/16")
    node_subnet_cidr     = optional(string, "10.0.0.0/22")
    database_subnet_cidr = optional(string)
    service_endpoints    = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "VNet the module creates; ignored when existing_vnet is set. Size node_subnet_cidr for the maximum node count plus surge and private endpoints."
}

variable "existing_vnet" {
  type = object({
    vnet_id        = string
    node_subnet_id = string
    outbound_type  = optional(string, "loadBalancer")
  })
  default     = null
  description = "Existing VNet and node subnet to use instead of creating them. Set outbound_type to how that subnet reaches the internet: loadBalancer, userAssignedNATGateway or userDefinedRouting."

  validation {
    condition     = var.existing_vnet == null ? true : contains(["loadBalancer", "userAssignedNATGateway", "userDefinedRouting"], var.existing_vnet.outbound_type)
    error_message = "existing_vnet.outbound_type must be one of: loadBalancer, userAssignedNATGateway, userDefinedRouting."
  }
}

variable "nat_gateway" {
  type = object({
    enabled              = optional(bool)
    public_ip_count      = optional(number, 1)
    idle_timeout_minutes = optional(number, 4)
  })
  default     = {}
  nullable    = false
  description = "NAT Gateway for node egress on the subnet the module creates. enabled defaults to true when the module creates the VNet, and cannot be true with existing_vnet."

  validation {
    condition     = var.nat_gateway.enabled != true || var.existing_vnet == null
    error_message = "nat_gateway.enabled cannot be true with existing_vnet. Describe that subnet's egress with existing_vnet.outbound_type instead."
  }
  validation {
    condition     = var.nat_gateway.public_ip_count >= 1 && var.nat_gateway.public_ip_count <= 16
    error_message = "nat_gateway.public_ip_count must be between 1 and 16."
  }
  validation {
    condition     = var.nat_gateway.idle_timeout_minutes >= 4 && var.nat_gateway.idle_timeout_minutes <= 120
    error_message = "nat_gateway.idle_timeout_minutes must be between 4 and 120."
  }
}

variable "private_endpoints" {
  type = map(object({
    resource_id          = string
    subresource_names    = list(string)
    private_dns_zone_ids = list(string)
  }))
  default     = {}
  nullable    = false
  description = "Private endpoints in the node subnet, one per target resource, keyed by a name you choose. Example subresource_names: [\"blob\"], [\"vault\"], [\"registry\"]."
}

variable "cni" {
  type        = string
  default     = "cilium"
  description = "CNI to run: cilium, kube-ovn or azure-cni. cilium and kube-ovn set network_plugin none and are installed by cni-bootstrap; kube-ovn also creates the CNI node pool."

  validation {
    condition     = contains(keys(local.cni_profiles), var.cni)
    error_message = "cni must be one of: cilium, kube-ovn, azure-cni."
  }
}

variable "azure_cni" {
  type = object({
    network_plugin_mode = optional(string, "overlay")
    network_data_plane  = optional(string, "azure")
  })
  default     = {}
  nullable    = false
  description = "Ignored unless cni = azure-cni. network_plugin_mode is overlay or node-subnet; network_data_plane is azure or cilium."

  validation {
    condition     = contains(["overlay", "node-subnet"], var.azure_cni.network_plugin_mode)
    error_message = "azure_cni.network_plugin_mode must be one of: overlay, node-subnet."
  }
  validation {
    condition     = contains(["azure", "cilium"], var.azure_cni.network_data_plane)
    error_message = "azure_cni.network_data_plane must be one of: azure, cilium."
  }
}

variable "system_node_pool" {
  type = object({
    vm_size         = string
    min_count       = optional(number, 2)
    max_count       = optional(number, 6)
    node_count      = optional(number, 3)
    labels          = optional(map(string), {})
    os_sku          = optional(string, "AzureLinux3")
    fips_enabled    = optional(bool, false)
    zones           = optional(list(string), ["1", "2", "3"])
    max_pods        = optional(number, 110)
    os_disk_size_gb = optional(number, 100)
  })
  nullable    = false
  description = "System node pool, the AKS default node pool. vm_size is required, min_count is at least 2, and the pool always carries the CriticalAddonsOnly taint."

  validation {
    condition     = var.system_node_pool.min_count >= 2
    error_message = "system_node_pool.min_count must be at least 2: AKS system pools need two nodes."
  }
  validation {
    condition     = var.system_node_pool.min_count <= var.system_node_pool.node_count && var.system_node_pool.node_count <= var.system_node_pool.max_count
    error_message = "system_node_pool counts must satisfy min_count <= node_count <= max_count."
  }
  validation {
    condition     = !startswith(lower(var.system_node_pool.vm_size), "standard_b")
    error_message = "system_node_pool.vm_size must not be a B-series size: AKS rejects burstable VMs for system pools."
  }
  validation {
    condition     = contains(["AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204", "Ubuntu2404"], var.system_node_pool.os_sku)
    error_message = "system_node_pool.os_sku must be one of: AzureLinux, AzureLinux3, Ubuntu, Ubuntu2204, Ubuntu2404."
  }
  validation {
    condition     = var.system_node_pool.max_pods >= 30 && var.system_node_pool.max_pods <= 250
    error_message = "system_node_pool.max_pods must be between 30 and 250."
  }
}

variable "cni_node_pool" {
  type = object({
    enabled            = optional(bool)
    kubernetes_version = optional(string)
    vm_size            = optional(string)
    zones              = optional(list(string))
    node_count         = optional(number, 1)
  })
  default     = {}
  nullable    = false
  description = "Dedicated CNI node pool, created for kube-ovn. Set kubernetes_version when cni = kube-ovn; set enabled = false, then true, to recycle the pool."

  validation {
    condition     = var.cni != "kube-ovn" || var.cni_node_pool.kubernetes_version != null
    error_message = "cni_node_pool.kubernetes_version is required when cni = kube-ovn, so a control plane upgrade does not replace the kube-ovn master node on its own."
  }
  validation {
    condition     = var.cni_node_pool.node_count >= 1
    error_message = "cni_node_pool.node_count must be at least 1."
  }
}

variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/16"
  description = "Kubernetes service CIDR, with a prefix longer than /12. It must not overlap the VNet, pod_cidr or the ranges AKS reserves."

  validation {
    condition     = can(cidrhost(var.service_cidr, 0)) && tonumber(split("/", var.service_cidr)[1]) > 12
    error_message = "service_cidr must be a valid IPv4 CIDR with a prefix longer than /12."
  }
  validation {
    # Two CIDRs overlap when one contains the other's network address. Malformed input is left to the format check.
    condition = !anytrue([for other in local.service_cidr_must_avoid : try(
      cidrhost("${cidrhost(var.service_cidr, 0)}/${split("/", other)[1]}", 0) == cidrhost(other, 0) ||
      cidrhost("${cidrhost(other, 0)}/${split("/", var.service_cidr)[1]}", 0) == cidrhost(var.service_cidr, 0),
      false,
    )])
    error_message = "service_cidr must not overlap vnet.cidr or the ranges AKS reserves: 169.254.0.0/16, 172.30.0.0/16, 172.31.0.0/16, 192.0.2.0/24."
  }
}

variable "dns_service_ip" {
  type        = string
  default     = null
  description = "Cluster DNS service IP inside service_cidr. null uses the tenth address."

  validation {
    condition     = var.dns_service_ip == null ? true : (cidrhost("${var.dns_service_ip}/${split("/", var.service_cidr)[1]}", 0) == cidrhost(var.service_cidr, 0) && var.dns_service_ip != cidrhost(var.service_cidr, 1))
    error_message = "dns_service_ip must be inside service_cidr and must not be its first address, which AKS reserves for the kubernetes service."
  }
}

variable "pod_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod CIDR the AKS control plane routes to. Pass the cluster_pod_cidr output to cni-bootstrap so the CNI uses the same range."

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid IPv4 CIDR."
  }
  validation {
    condition = !anytrue([for other in local.pod_cidr_must_avoid : try(
      cidrhost("${cidrhost(var.pod_cidr, 0)}/${split("/", other)[1]}", 0) == cidrhost(other, 0) ||
      cidrhost("${cidrhost(other, 0)}/${split("/", var.pod_cidr)[1]}", 0) == cidrhost(var.pod_cidr, 0),
      false,
    )])
    error_message = "pod_cidr must not overlap vnet.cidr, service_cidr or the ranges AKS reserves: 169.254.0.0/16, 172.30.0.0/16, 172.31.0.0/16, 192.0.2.0/24."
  }
}

variable "kms" {
  type = object({
    enabled                  = optional(bool, true)
    key_vault_name           = optional(string)
    key_vault_network_access = optional(string, "Public")
  })
  default     = {}
  nullable    = false
  description = "Encrypts etcd secrets with a customer-managed key in a Key Vault the module creates. Destroying keeps the vault name reserved for 90 days; set key_vault_name to create a new one."

  validation {
    condition     = contains(["Public", "Private"], var.kms.key_vault_network_access)
    error_message = "kms.key_vault_network_access must be one of: Public, Private."
  }
  validation {
    # RE2 has no lookahead, so the consecutive-hyphen rule is a separate strcontains check.
    condition     = var.kms.key_vault_name == null ? true : (can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.kms.key_vault_name)) && !strcontains(var.kms.key_vault_name, "--"))
    error_message = "kms.key_vault_name must be 3-24 characters of letters, digits and single hyphens, start with a letter and end with a letter or digit."
  }
}

variable "cluster_enabled_log_types" {
  type        = list(string)
  default     = []
  description = "AKS control plane log categories sent to cluster_log_analytics_workspace_id. Empty sends nothing."

  validation {
    condition = alltrue([
      for t in var.cluster_enabled_log_types : contains([
        "kube-apiserver", "kube-audit", "kube-audit-admin", "kube-controller-manager", "kube-scheduler",
        "cluster-autoscaler", "cloud-controller-manager", "guard",
        "csi-azuredisk-controller", "csi-azurefile-controller", "csi-snapshot-controller",
      ], t)
    ])
    error_message = "cluster_enabled_log_types entries must be AKS diagnostic categories: kube-apiserver, kube-audit, kube-audit-admin, kube-controller-manager, kube-scheduler, cluster-autoscaler, cloud-controller-manager, guard, csi-azuredisk-controller, csi-azurefile-controller, csi-snapshot-controller."
  }
}

variable "cluster_log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "ID of an existing Log Analytics workspace for cluster_enabled_log_types. Required when that list is not empty."

  validation {
    condition     = length(var.cluster_enabled_log_types) == 0 || var.cluster_log_analytics_workspace_id != null
    error_message = "cluster_log_analytics_workspace_id is required when cluster_enabled_log_types is not empty."
  }
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = true
  description = "Makes the API server reachable from the internet. false creates a private cluster, which needs VNet connectivity to run cni-bootstrap."
}

variable "cluster_endpoint_authorized_ip_ranges" {
  type        = list(string)
  default     = []
  description = "CIDRs allowed to reach the public API server. Empty allows all."

  validation {
    condition     = length(var.cluster_endpoint_authorized_ip_ranges) == 0 || var.cluster_endpoint_public_access
    error_message = "cluster_endpoint_authorized_ip_ranges only applies to a public API server. Unset it or set cluster_endpoint_public_access = true."
  }
}

variable "sku_tier" {
  type        = string
  default     = "Standard"
  description = "AKS pricing tier: Free, Standard or Premium. Standard includes the uptime SLA."

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be one of: Free, Standard, Premium."
  }
}

variable "automatic_upgrade_channel" {
  type        = string
  default     = "none"
  description = "AKS control plane upgrade channel: none, patch, rapid, node-image or stable. Each value follows the azurerm spelling."

  validation {
    condition     = contains(["none", "patch", "rapid", "node-image", "stable"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be one of: none, patch, rapid, node-image, stable."
  }
}

variable "node_os_upgrade_channel" {
  type        = string
  default     = "None"
  description = "AKS node OS image upgrade channel: None, Unmanaged, SecurityPatch or NodeImage. Keep None with kube-ovn so AKS does not reimage the CNI node pool."

  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of: None, Unmanaged, SecurityPatch, NodeImage."
  }
}

variable "local_account_disabled" {
  type        = bool
  default     = true
  description = "Disables AKS local accounts so every access goes through Entra ID. Set false to keep kube_admin_config as a break-glass path."
}

variable "access" {
  type = object({
    admin_object_ids  = optional(list(string), [])
    reader_object_ids = optional(list(string), [])
  })
  default     = {}
  nullable    = false
  description = "Entra object IDs with cluster access. admin_object_ids get RBAC Cluster Admin and Key Vault Crypto Officer; reader_object_ids get RBAC Reader."

  validation {
    condition     = length(distinct(concat(var.access.admin_object_ids, var.access.reader_object_ids))) == length(concat(var.access.admin_object_ids, var.access.reader_object_ids))
    error_message = "access object IDs must be unique across admin_object_ids and reader_object_ids: Azure rejects a duplicate role assignment."
  }
}

variable "workload_identity" {
  type = object({
    enabled = optional(bool, true)
    overrides = optional(object({
      external_dns = optional(object({
        enabled      = optional(bool)
        dns_zone_ids = optional(list(string), [])
      }), {})
      cert_manager = optional(object({
        enabled      = optional(bool)
        dns_zone_ids = optional(list(string), [])
      }), {})
    }), {})
  })
  default     = {}
  nullable    = false
  description = "Workload identities for external_dns and cert_manager. Use overrides.<identity>.enabled to change one, and dns_zone_ids to grant it DNS Zone Contributor on those zones."
}

variable "karpenter" {
  type = object({
    enabled = optional(bool, true)
    mode    = optional(string, "self-hosted")
  })
  default     = {}
  nullable    = false
  description = "Karpenter mode. self-hosted creates the controller identity and its role assignments; node-auto-provisioning turns on AKS-managed Karpenter; enabled = false turns both off."

  validation {
    condition     = contains(["self-hosted", "node-auto-provisioning"], var.karpenter.mode)
    error_message = "karpenter.mode must be one of: self-hosted, node-auto-provisioning."
  }
}

variable "storage_drivers" {
  type = object({
    disk                = optional(bool, false)
    file                = optional(bool, false)
    snapshot_controller = optional(bool, false)
  })
  default     = {}
  nullable    = false
  description = "AKS-managed CSI drivers and snapshot controller. All off by default, so storage comes from charts you pin yourself; turn one on to let AKS run and upgrade it."
}

variable "blob_csi" {
  type = object({
    enabled                = optional(bool, false)
    create_storage_account = optional(bool, true)
    storage_account_name   = optional(string)
  })
  default     = {}
  nullable    = false
  description = "AKS-managed blob CSI driver with a storage account for it, off by default. Set storage_account_name when the generated <Owner tag><name>csi name is taken."

  validation {
    condition     = var.blob_csi.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.blob_csi.storage_account_name))
    error_message = "blob_csi.storage_account_name must be 3-24 lowercase letters and digits."
  }
}
