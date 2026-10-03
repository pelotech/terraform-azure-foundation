# Changelog

## 0.1.0 (2026-10-03)


### ⚠ BREAKING CHANGES

* blob_csi.enabled = true no longer turns on the AKS-managed blob driver.

### Features

* create blob CSI storage and containers with the AKS-managed driver off by default ([#5](https://github.com/pelotech/terraform-azure-foundation/issues/5)) ([7a42bff](https://github.com/pelotech/terraform-azure-foundation/commit/7a42bffcef6d6c25123bd7d87f5b4a6381f8fee2))
* expose subscription_id and tenant_id ([6df0389](https://github.com/pelotech/terraform-azure-foundation/commit/6df03892359051b0ee5d15ab516c14a0e6dd9eac))
* grant the kubelet identity Contributor on the node resource group when the managed disk driver is off ([39d55ea](https://github.com/pelotech/terraform-azure-foundation/commit/39d55ea03ca78ab997af0167af0cf380a5adf050))
* import the Azure foundation stack with an Azure-first interface ([647f775](https://github.com/pelotech/terraform-azure-foundation/commit/647f775c23e3edf3bff9d91ce91b709fc2d3a156))
* make the AKS-managed CSI drivers configurable and off by default ([51eb1d5](https://github.com/pelotech/terraform-azure-foundation/commit/51eb1d548c73d050360724ecd06ad22f92f3bfd7))


### Chores

* suppress the Key Vault network ACL check with its rationale ([beb8b5d](https://github.com/pelotech/terraform-azure-foundation/commit/beb8b5d1f66dac524762683f277c33f99fc966e8))
* suppress the storage account network rules check with its rationale ([5a70c6b](https://github.com/pelotech/terraform-azure-foundation/commit/5a70c6b89a697ec8657924f45ad22a4af081b61e))


### Docs

* wire cni-bootstrap through its cloud-neutral inputs ([8a1ef56](https://github.com/pelotech/terraform-azure-foundation/commit/8a1ef56ff74d48e38cd3ed46caa3b747605d735f))
