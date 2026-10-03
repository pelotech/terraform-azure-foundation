# terraform-azure-foundation

This module creates an AKS cluster that runs a CNI you install yourself. It creates:

- a VNet with a node subnet and a NAT Gateway
- an AKS cluster with bring-your-own CNI (`network_plugin = "none"`)
- a system node pool and, for kube-ovn, a CNI node pool
- Azure RBAC for Kubernetes with local accounts disabled
- etcd encryption with a customer-managed key in a Key Vault
- workload identities for external-dns and cert-manager
- the Karpenter controller identity
- optional AKS-managed CSI drivers, all off by default

Its outputs feed the helm provider and the cni-bootstrap module. The section "Install the CNI" lists the wiring.

## Prerequisites

- Terraform 1.9 or later and the azurerm provider 5.0 or later.
- `kubectl` and `kubelogin` on the host that applies cni-bootstrap.
- Locally, run `az login` against the target cloud. In CI, set `kube_exec_login_mode` to `spn`, `msi` or `workloadidentity`.
- Create the DNS zones you list in `dns_zone_ids` before the first plan.

## Quick start

```hcl
provider "azurerm" {
  environment = "usgovernment"
  features {}
}

module "stack" {
  source           = "github.com/pelotech/terraform-azure-foundation?ref=<release tag>"
  name             = "platform-dev"
  location         = "usgovvirginia"
  azure_cloud      = "usgovernment"
  cni              = "kube-ovn"
  system_node_pool = { vm_size = "Standard_D4s_v5", fips_enabled = true }
  cni_node_pool    = { kubernetes_version = "1.35" }
  access           = { admin_object_ids = [var.platform_admins_group_id] }
  workload_identity = {
    overrides = {
      external_dns = { dns_zone_ids = [var.dns_zone_id] }
      cert_manager = { dns_zone_ids = [var.dns_zone_id] }
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.stack.cluster_endpoint
    cluster_ca_certificate = base64decode(module.stack.cluster_ca_certificate)
    exec                   = module.stack.kube_exec
  }
}
```

## Install the CNI

Apply cni-bootstrap after this module. Every input it needs comes from this module's outputs:

```hcl
module "cni" {
  source                  = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cloud                   = module.stack.cloud
  cni                     = "kube-ovn-v2"
  cluster_endpoint        = module.stack.cluster_endpoint
  cluster_ca_certificate  = module.stack.cluster_ca_certificate
  kube_exec               = module.stack.kube_exec
  k8s_service_host        = module.stack.cluster_api_host
  service_cidr            = module.stack.cluster_service_cidr
  pod_cidr                = module.stack.cluster_pod_cidr
  wait_for_nodes_count    = module.stack.cni_node_size
  wait_for_nodes_selector = module.stack.cni_node_selector
}
```

For Cilium, set `cni = "cilium"` with the same inputs. `cloud = "azure"` keeps kube-proxy on and turns on the AKS
bring-your-own-CNI mode. The apply host needs `kubectl` and `kubelogin` for the kube-ovn node poll.

| Output                   | cni-bootstrap input       |
| ------------------------ | ------------------------- |
| `cloud`                  | `cloud`                   |
| `cluster_endpoint`       | `cluster_endpoint`        |
| `cluster_ca_certificate` | `cluster_ca_certificate`  |
| `kube_exec`              | `kube_exec`               |
| `cluster_api_host`       | `k8s_service_host`        |
| `cluster_service_cidr`   | `service_cidr`            |
| `cluster_pod_cidr`       | `pod_cidr`                |
| `cni_node_size`          | `wait_for_nodes_count`    |
| `cni_node_selector`      | `wait_for_nodes_selector` |

## Choose a CNI

| `cni`              | network_plugin | CNI node pool                                     | cni-bootstrap `cni` |
| ------------------ | -------------- | ------------------------------------------------- | ------------------- |
| `cilium` (default) | `none`         | none                                              | `cilium`            |
| `kube-ovn`         | `none`         | 1 node, label `kube-ovn/role=master`, tainted     | `kube-ovn-v2`       |
| `azure-cni`        | `azure`        | none                                              | not used            |

`azure-cni` is the Microsoft-managed CNI. Configure it with `azure_cni`: overlay or node-subnet mode, azure or cilium data plane.

## AKS constraints

- **The system node pool has no startup taints.** AKS accepts only CriticalAddonsOnly on the system pool, and the Kubernetes API cannot remove AKS node taints. Nodes stay NotReady until the CNI runs.
- **AKS manages coredns.** There is no coredns toleration or affinity setting.
- **kube-proxy stays on.** The azurerm provider cannot turn it off. Set `kube_proxy_replacement = false` for Cilium.
- **Set the pod CIDR.** AKS routes control-plane-to-pod traffic through `pod_cidr`. Pass `cluster_pod_cidr` to cni-bootstrap so the CNI uses the same range.

## Networking

| Setup                      | Inputs                                                      | AKS outbound_type        |
| -------------------------- | ----------------------------------------------------------- | ------------------------ |
| Created VNet, NAT Gateway  | defaults                                                    | `userAssignedNATGateway` |
| Created VNet, load balancer | `nat_gateway = { enabled = false }`                        | `loadBalancer`           |
| Existing VNet              | `existing_vnet = { vnet_id, node_subnet_id, outbound_type }` | your `outbound_type`     |

`nat_gateway_public_ips` lists the gateway addresses for allow lists. `private_endpoints` creates one private endpoint
per target resource in the node subnet, with an existing VNet too.

## Access

| Input                      | Roles on the cluster                                                   |
| -------------------------- | ---------------------------------------------------------------------- |
| `access.admin_object_ids`  | RBAC Cluster Admin, Cluster User Role, Key Vault Crypto Officer on the KMS vault |
| `access.reader_object_ids` | RBAC Reader (no Secrets), Cluster User Role, Key Vault Reader on the KMS vault |

Grant extra roles against the `cluster_id` output.

By default, anyone on the internet can reach the API server. To restrict it, set `cluster_endpoint_authorized_ip_ranges`.
For a private cluster, set `cluster_endpoint_public_access = false`.

## Workload identity

The module uses Microsoft Entra Workload ID for every identity. For each controller, the GitOps layer must:

1. Set the service account annotation `azure.workload.identity/client-id` to the `<identity>_client_id` output.
2. Set the label `azure.workload.identity/use: "true"` on the pod template.

Without the label, the pod gets no token.

Azure has no wildcard DNS scope. List each zone in `dns_zone_ids`. The module grants DNS Zone Contributor on each zone.
For external-dns, it also grants Reader on the zone's resource group. To assign roles yourself, leave `dns_zone_ids`
empty and use `<identity>_principal_id`.

## Karpenter

With `karpenter.mode = "self-hosted"` (default), the module creates the controller identity with these roles:

| Role                        | Scope               |
| --------------------------- | ------------------- |
| Virtual Machine Contributor | node resource group |
| Network Contributor         | node resource group |
| Managed Identity Operator   | node resource group |
| Network Contributor         | node subnet         |
| Managed Identity Operator   | kubelet identity    |

The GitOps layer deploys the chart, the node classes and the `karpenter/karpenter` service account. It needs these
outputs: `karpenter_client_id`, `node_resource_group_name`, `node_subnet_id` and `kubelet_identity_client_id`.

Set `karpenter.mode = "node-auto-provisioning"` to use AKS node auto provisioning instead.

## Storage drivers

Every AKS-managed CSI driver is off by default. Storage then comes from charts you deploy and pin yourself, such as the
upstream Azure Disk CSI driver with external-snapshotter, or Rook Ceph. Turn a managed driver on to let AKS run and
upgrade it with the cluster version.

With the managed disk driver off, the kubelet identity gets Contributor on the node resource group. A self-managed
disk CSI driver authenticates with that identity from the nodes' azure.json and creates its disks there.

| Input                                  | Driver                                   |
| -------------------------------------- | ---------------------------------------- |
| `storage_drivers.disk`                 | Azure Disk CSI, with the default StorageClasses |
| `storage_drivers.file`                 | Azure Files CSI                          |
| `storage_drivers.snapshot_controller`  | CSI snapshot controller                  |
| `blob_csi.managed_driver`              | Azure Blob CSI                           |

With `blob_csi.enabled`, the module creates a storage account named from the Owner tag plus the cluster name plus
`csi`, lowercased, letters and digits only, cut to 24 characters, the kubelet grant on it and the private containers
listed in `blob_csi.containers`. Set `blob_csi.storage_account_name` when that name is taken. The driver itself comes
from GitOps; set `blob_csi.managed_driver = true` only to let AKS run it. Use the `blob_csi_storage_account_name`
output as the `storageAccount` of a PersistentVolume.

## Recycle the CNI node pool

1. Set `cni_node_pool.enabled = false` and apply.
2. Set it back to `true`. For an upgrade, raise `cni_node_pool.kubernetes_version` at the same time.
3. In the same apply, raise cni-bootstrap `bootstrap_generation` so kube-ovn reads the new master node IP.

Keep `node_os_upgrade_channel = "None"` so AKS does not reimage this pool.

## Known issues

On a first apply, Key Vault role grants can take minutes to apply. If the apply fails with 403, run it again.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_federated_identity_credential.karpenter](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_federated_identity_credential.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_key_vault.kms](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_key.kms](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_key) | resource |
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.cni](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_monitor_diagnostic_setting.cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway) | resource |
| [azurerm_nat_gateway_public_ip_association.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/nat_gateway_public_ip_association) | resource |
| [azurerm_private_endpoint.node_subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_public_ip.nat](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/public_ip) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.access](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.access_admin_key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.access_reader_key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.cluster_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.deployer_key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.external_dns_zone_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.karpenter](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kubelet_blob_storage_account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kubelet_node_resource_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.workload_dns_zone](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.blob_csi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.blob_csi](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_subnet.database](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_nat_gateway_association.nodes](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_nat_gateway_association) | resource |
| [azurerm_user_assigned_identity.cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.karpenter](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.kubelet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.workload](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region for every resource, for example usgovvirginia. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the AKS cluster. It is also the DNS prefix and the base of every generated resource name. | `string` | n/a | yes |
| <a name="input_system_node_pool"></a> [system\_node\_pool](#input\_system\_node\_pool) | System node pool, the AKS default node pool. vm\_size is required, min\_count is at least 2, and the pool always carries the CriticalAddonsOnly taint. | <pre>object({<br/>    vm_size         = string<br/>    min_count       = optional(number, 2)<br/>    max_count       = optional(number, 6)<br/>    node_count      = optional(number, 3)<br/>    labels          = optional(map(string), {})<br/>    os_sku          = optional(string, "AzureLinux3")<br/>    fips_enabled    = optional(bool, false)<br/>    zones           = optional(list(string), ["1", "2", "3"])<br/>    max_pods        = optional(number, 110)<br/>    os_disk_size_gb = optional(number, 100)<br/>  })</pre> | n/a | yes |
| <a name="input_access"></a> [access](#input\_access) | Entra object IDs with cluster access. admin\_object\_ids get RBAC Cluster Admin and Key Vault Crypto Officer; reader\_object\_ids get RBAC Reader and Key Vault Reader. | <pre>object({<br/>    admin_object_ids  = optional(list(string), [])<br/>    reader_object_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_automatic_upgrade_channel"></a> [automatic\_upgrade\_channel](#input\_automatic\_upgrade\_channel) | AKS control plane upgrade channel: none, patch, rapid, node-image or stable. Each value follows the azurerm spelling. | `string` | `"none"` | no |
| <a name="input_azure_cloud"></a> [azure\_cloud](#input\_azure\_cloud) | Azure cloud for the kubelogin --environment flag in kube\_exec: public or usgovernment. Set it to the same cloud as your azurerm provider. | `string` | `"public"` | no |
| <a name="input_azure_cni"></a> [azure\_cni](#input\_azure\_cni) | Ignored unless cni = azure-cni. network\_plugin\_mode is overlay or node-subnet; network\_data\_plane is azure or cilium. | <pre>object({<br/>    network_plugin_mode = optional(string, "overlay")<br/>    network_data_plane  = optional(string, "azure")<br/>  })</pre> | `{}` | no |
| <a name="input_blob_csi"></a> [blob\_csi](#input\_blob\_csi) | Blob storage for the blob CSI driver, off by default. When enabled the module creates the storage account, the kubelet grant and the private containers; set managed\_driver = true only to let AKS run the driver instead of GitOps. Set storage\_account\_name when the generated <Owner tag><name>csi name is taken. | <pre>object({<br/>    enabled                = optional(bool, false)<br/>    managed_driver         = optional(bool, false)<br/>    create_storage_account = optional(bool, true)<br/>    storage_account_name   = optional(string)<br/>    containers             = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_cluster_enabled_log_types"></a> [cluster\_enabled\_log\_types](#input\_cluster\_enabled\_log\_types) | AKS control plane log categories sent to cluster\_log\_analytics\_workspace\_id. Empty sends nothing. | `list(string)` | `[]` | no |
| <a name="input_cluster_endpoint_authorized_ip_ranges"></a> [cluster\_endpoint\_authorized\_ip\_ranges](#input\_cluster\_endpoint\_authorized\_ip\_ranges) | CIDRs allowed to reach the public API server. Empty allows all. | `list(string)` | `[]` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | Makes the API server reachable from the internet. false creates a private cluster, which needs VNet connectivity to run cni-bootstrap. | `bool` | `true` | no |
| <a name="input_cluster_log_analytics_workspace_id"></a> [cluster\_log\_analytics\_workspace\_id](#input\_cluster\_log\_analytics\_workspace\_id) | ID of an existing Log Analytics workspace for cluster\_enabled\_log\_types. Required when that list is not empty. | `string` | `null` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | Kubernetes version in MAJOR.MINOR form. AKS picks the patch version. | `string` | `"1.35"` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI to run: cilium, kube-ovn or azure-cni. cilium and kube-ovn set network\_plugin none and are installed by cni-bootstrap; kube-ovn also creates the CNI node pool. | `string` | `"cilium"` | no |
| <a name="input_cni_node_pool"></a> [cni\_node\_pool](#input\_cni\_node\_pool) | Dedicated CNI node pool, created for kube-ovn. Set kubernetes\_version when cni = kube-ovn; set enabled = false, then true, to recycle the pool. | <pre>object({<br/>    enabled            = optional(bool)<br/>    kubernetes_version = optional(string)<br/>    vm_size            = optional(string)<br/>    zones              = optional(list(string))<br/>    node_count         = optional(number, 1)<br/>  })</pre> | `{}` | no |
| <a name="input_create_cluster"></a> [create\_cluster](#input\_create\_cluster) | Creates the AKS cluster and every resource that depends on it. The VNet, NAT Gateway, private endpoints and storage account have their own switches. | `bool` | `true` | no |
| <a name="input_create_resource_group"></a> [create\_resource\_group](#input\_create\_resource\_group) | Creates the resource group. Set false to use an existing group named resource\_group\_name. | `bool` | `true` | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | Cluster DNS service IP inside service\_cidr. null uses the tenth address. | `string` | `null` | no |
| <a name="input_existing_vnet"></a> [existing\_vnet](#input\_existing\_vnet) | Existing VNet and node subnet to use instead of creating them. Set outbound\_type to how that subnet reaches the internet: loadBalancer, userAssignedNATGateway or userDefinedRouting. | <pre>object({<br/>    vnet_id        = string<br/>    node_subnet_id = string<br/>    outbound_type  = optional(string, "loadBalancer")<br/>  })</pre> | `null` | no |
| <a name="input_karpenter"></a> [karpenter](#input\_karpenter) | Karpenter mode. self-hosted creates the controller identity and its role assignments; node-auto-provisioning turns on AKS-managed Karpenter; enabled = false turns both off. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    mode    = optional(string, "self-hosted")<br/>  })</pre> | `{}` | no |
| <a name="input_kms"></a> [kms](#input\_kms) | Encrypts etcd secrets with a customer-managed key in a Key Vault the module creates. Destroying keeps the vault name reserved for 90 days; set key\_vault\_name to create a new one. | <pre>object({<br/>    enabled                  = optional(bool, true)<br/>    key_vault_name           = optional(string)<br/>    key_vault_network_access = optional(string, "Public")<br/>  })</pre> | `{}` | no |
| <a name="input_kube_exec_login_mode"></a> [kube\_exec\_login\_mode](#input\_kube\_exec\_login\_mode) | kubelogin --login mode in kube\_exec. azurecli reuses your az session; use spn, msi or workloadidentity in CI. | `string` | `"azurecli"` | no |
| <a name="input_local_account_disabled"></a> [local\_account\_disabled](#input\_local\_account\_disabled) | Disables AKS local accounts so every access goes through Entra ID. Set false to keep kube\_admin\_config as a break-glass path. | `bool` | `true` | no |
| <a name="input_nat_gateway"></a> [nat\_gateway](#input\_nat\_gateway) | NAT Gateway for node egress on the subnet the module creates. enabled defaults to true when the module creates the VNet, and cannot be true with existing\_vnet. | <pre>object({<br/>    enabled              = optional(bool)<br/>    public_ip_count      = optional(number, 1)<br/>    idle_timeout_minutes = optional(number, 4)<br/>  })</pre> | `{}` | no |
| <a name="input_node_os_upgrade_channel"></a> [node\_os\_upgrade\_channel](#input\_node\_os\_upgrade\_channel) | AKS node OS image upgrade channel: None, Unmanaged, SecurityPatch or NodeImage. Keep None with kube-ovn so AKS does not reimage the CNI node pool. | `string` | `"None"` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Pod CIDR the AKS control plane routes to. Pass the cluster\_pod\_cidr output to cni-bootstrap so the CNI uses the same range. | `string` | `"10.244.0.0/16"` | no |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints in the node subnet, one per target resource, keyed by a name you choose. Example subresource\_names: ["blob"], ["vault"], ["registry"]. | <pre>map(object({<br/>    resource_id          = string<br/>    subresource_names    = list(string)<br/>    private_dns_zone_ids = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group for every resource. null generates rg-<name>. | `string` | `null` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Kubernetes service CIDR, with a prefix longer than /12. It must not overlap the VNet, pod\_cidr or the ranges AKS reserves. | `string` | `"10.96.0.0/16"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS pricing tier: Free, Standard or Premium. Standard includes the uptime SLA. | `string` | `"Standard"` | no |
| <a name="input_storage_drivers"></a> [storage\_drivers](#input\_storage\_drivers) | AKS-managed CSI drivers and snapshot controller. All off by default, so storage comes from charts you pin yourself; turn one on to let AKS run and upgrade it. | <pre>object({<br/>    disk                = optional(bool, false)<br/>    file                = optional(bool, false)<br/>    snapshot_controller = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for every resource. The Owner tag, when present, seeds the blob CSI storage account name. | `map(string)` | `{}` | no |
| <a name="input_vnet"></a> [vnet](#input\_vnet) | VNet the module creates; ignored when existing\_vnet is set. Size node\_subnet\_cidr for the maximum node count plus surge and private endpoints. | <pre>object({<br/>    cidr                 = optional(string, "10.0.0.0/16")<br/>    node_subnet_cidr     = optional(string, "10.0.0.0/22")<br/>    database_subnet_cidr = optional(string)<br/>    service_endpoints    = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_workload_identity"></a> [workload\_identity](#input\_workload\_identity) | Workload identities for external\_dns and cert\_manager. Use overrides.<identity>.enabled to change one, and dns\_zone\_ids to grant it DNS Zone Contributor on those zones. | <pre>object({<br/>    enabled = optional(bool, true)<br/>    overrides = optional(object({<br/>      external_dns = optional(object({<br/>        enabled      = optional(bool)<br/>        dns_zone_ids = optional(list(string), [])<br/>      }), {})<br/>      cert_manager = optional(object({<br/>        enabled      = optional(bool)<br/>        dns_zone_ids = optional(list(string), [])<br/>      }), {})<br/>    }), {})<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_blob_csi_container_names"></a> [blob\_csi\_container\_names](#output\_blob\_csi\_container\_names) | Names of the blob containers created in the blob CSI storage account, empty when none. |
| <a name="output_blob_csi_storage_account_id"></a> [blob\_csi\_storage\_account\_id](#output\_blob\_csi\_storage\_account\_id) | Resource ID of the blob CSI storage account, null when not created. |
| <a name="output_blob_csi_storage_account_name"></a> [blob\_csi\_storage\_account\_name](#output\_blob\_csi\_storage\_account\_name) | Name of the blob CSI storage account, null when not created. Use it as the storageAccount of a PersistentVolume. |
| <a name="output_cert_manager_client_id"></a> [cert\_manager\_client\_id](#output\_cert\_manager\_client\_id) | Client ID of the cert-manager workload identity, null when disabled. |
| <a name="output_cert_manager_identity_id"></a> [cert\_manager\_identity\_id](#output\_cert\_manager\_identity\_id) | Resource ID of the cert-manager workload identity. |
| <a name="output_cert_manager_principal_id"></a> [cert\_manager\_principal\_id](#output\_cert\_manager\_principal\_id) | Principal ID of the cert-manager workload identity, for role assignments you create yourself. |
| <a name="output_cloud"></a> [cloud](#output\_cloud) | Cloud this stack runs on. Pass it to cni-bootstrap cloud. |
| <a name="output_cluster_api_host"></a> [cluster\_api\_host](#output\_cluster\_api\_host) | API server host without scheme or port, for Cilium k8sServiceHost. Use port 443. |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | Base64 encoded cluster CA certificate for the helm provider and cni-bootstrap. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | API server URL for the helm provider and cni-bootstrap. |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | Resource ID of the AKS cluster, the scope for extra role assignments. |
| <a name="output_cluster_identity_principal_id"></a> [cluster\_identity\_principal\_id](#output\_cluster\_identity\_principal\_id) | Principal ID of the cluster identity. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of the AKS cluster, null when create\_cluster = false. |
| <a name="output_cluster_pod_cidr"></a> [cluster\_pod\_cidr](#output\_cluster\_pod\_cidr) | Pod CIDR the AKS control plane routes to, null for azure-cni in node-subnet mode. Pass it to cni-bootstrap pod\_cidr. |
| <a name="output_cluster_service_cidr"></a> [cluster\_service\_cidr](#output\_cluster\_service\_cidr) | Kubernetes service CIDR. Pass it to cni-bootstrap service\_cidr. |
| <a name="output_cni_node_labels_resolved"></a> [cni\_node\_labels\_resolved](#output\_cni\_node\_labels\_resolved) | Labels of the CNI node pool. Set even when the pool is not created. |
| <a name="output_cni_node_pool_enabled"></a> [cni\_node\_pool\_enabled](#output\_cni\_node\_pool\_enabled) | Whether the CNI node pool is created. |
| <a name="output_cni_node_selector"></a> [cni\_node\_selector](#output\_cni\_node\_selector) | Label selector of the CNI node pool, empty when the profile has none. Pass it to cni-bootstrap wait\_for\_nodes\_selector. |
| <a name="output_cni_node_size"></a> [cni\_node\_size](#output\_cni\_node\_size) | Node count of the CNI node pool, 0 when the pool is not created. Pass it to cni-bootstrap wait\_for\_nodes\_count. |
| <a name="output_cni_node_taints_resolved"></a> [cni\_node\_taints\_resolved](#output\_cni\_node\_taints\_resolved) | Taints of the CNI node pool as key, value and effect objects. Set even when the pool is not created. |
| <a name="output_database_subnet_id"></a> [database\_subnet\_id](#output\_database\_subnet\_id) | ID of the database subnet, null unless vnet.database\_subnet\_cidr is set. |
| <a name="output_dns_service_ip_resolved"></a> [dns\_service\_ip\_resolved](#output\_dns\_service\_ip\_resolved) | Cluster DNS service IP after resolving dns\_service\_ip and service\_cidr. |
| <a name="output_external_dns_client_id"></a> [external\_dns\_client\_id](#output\_external\_dns\_client\_id) | Client ID of the external-dns workload identity, null when disabled. |
| <a name="output_external_dns_identity_id"></a> [external\_dns\_identity\_id](#output\_external\_dns\_identity\_id) | Resource ID of the external-dns workload identity. |
| <a name="output_external_dns_principal_id"></a> [external\_dns\_principal\_id](#output\_external\_dns\_principal\_id) | Principal ID of the external-dns workload identity, for role assignments you create yourself. |
| <a name="output_karpenter_client_id"></a> [karpenter\_client\_id](#output\_karpenter\_client\_id) | Client ID of the Karpenter controller identity, null unless mode is self-hosted. Set it on the chart's workload identity annotation. |
| <a name="output_karpenter_identity_id"></a> [karpenter\_identity\_id](#output\_karpenter\_identity\_id) | Resource ID of the Karpenter controller identity. |
| <a name="output_karpenter_mode_resolved"></a> [karpenter\_mode\_resolved](#output\_karpenter\_mode\_resolved) | self-hosted, node-auto-provisioning, or disabled. |
| <a name="output_karpenter_principal_id"></a> [karpenter\_principal\_id](#output\_karpenter\_principal\_id) | Principal ID of the Karpenter controller identity, for extra role assignments. |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | Versioned Key Vault key ID used for etcd encryption, null when kms is disabled. |
| <a name="output_kms_key_vault_id"></a> [kms\_key\_vault\_id](#output\_kms\_key\_vault\_id) | ID of the Key Vault holding the etcd encryption key, null when kms is disabled. |
| <a name="output_kube_exec"></a> [kube\_exec](#output\_kube\_exec) | kubelogin exec block for the helm provider and cni-bootstrap. |
| <a name="output_kubelet_identity_client_id"></a> [kubelet\_identity\_client\_id](#output\_kubelet\_identity\_client\_id) | Client ID of the kubelet identity, used for image pulls, the CSI drivers and Karpenter nodes. |
| <a name="output_kubelet_identity_id"></a> [kubelet\_identity\_id](#output\_kubelet\_identity\_id) | Resource ID of the kubelet identity. |
| <a name="output_location"></a> [location](#output\_location) | Azure region of the stack. |
| <a name="output_nat_gateway_public_ips"></a> [nat\_gateway\_public\_ips](#output\_nat\_gateway\_public\_ips) | Public IP addresses of the NAT Gateway, for allow lists. Empty when the gateway is not created. |
| <a name="output_network_data_plane_resolved"></a> [network\_data\_plane\_resolved](#output\_network\_data\_plane\_resolved) | AKS network\_data\_plane: azure, cilium, or null for bring-your-own CNI. |
| <a name="output_network_plugin_mode_resolved"></a> [network\_plugin\_mode\_resolved](#output\_network\_plugin\_mode\_resolved) | AKS network\_plugin\_mode: overlay, or null. |
| <a name="output_network_plugin_resolved"></a> [network\_plugin\_resolved](#output\_network\_plugin\_resolved) | AKS network\_plugin: none for cilium and kube-ovn, azure for azure-cni. |
| <a name="output_node_resource_group_name"></a> [node\_resource\_group\_name](#output\_node\_resource\_group\_name) | Name of the resource group AKS creates for the nodes. |
| <a name="output_node_subnet_id"></a> [node\_subnet\_id](#output\_node\_subnet\_id) | ID of the subnet every node pool and private endpoint uses. |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | OIDC issuer URL of the cluster, for federated identity credentials you create yourself. |
| <a name="output_outbound_type_resolved"></a> [outbound\_type\_resolved](#output\_outbound\_type\_resolved) | AKS outbound\_type after resolving nat\_gateway and existing\_vnet. |
| <a name="output_region"></a> [region](#output\_region) | Same value as location, for consumers that expect an output named region. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group holding the module's resources. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Azure subscription the stack runs in. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra tenant of the subscription. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | ID of the VNet, created or taken from existing\_vnet. |
| <a name="output_workload_identity_enabled_resolved"></a> [workload\_identity\_enabled\_resolved](#output\_workload\_identity\_enabled\_resolved) | Which workload identities are created, after create\_cluster, enabled and overrides. |
| <a name="output_workload_identity_service_accounts_resolved"></a> [workload\_identity\_service\_accounts\_resolved](#output\_workload\_identity\_service\_accounts\_resolved) | Namespace and service account each created identity federates with. |
<!-- END_TF_DOCS -->~~
