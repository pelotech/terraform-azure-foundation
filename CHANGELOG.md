# Changelog

## [1.0.2](https://github.com/pelotech/terraform-azure-foundation/compare/v1.0.1...v1.0.2) (2026-10-05)


### Bug Fixes

* **blob_csi:** hold the network rules in their own resource so an open account plans clean ([#12](https://github.com/pelotech/terraform-azure-foundation/issues/12)) ([ab2ba13](https://github.com/pelotech/terraform-azure-foundation/commit/ab2ba13cea8d56cc4a48c47cf5f7753b3ad9c14a))

## [1.0.1](https://github.com/pelotech/terraform-azure-foundation/compare/v1.0.0...v1.0.1) (2026-10-05)


### Bug Fixes

* **blob_csi:** reopen a Public account and turn account keys off by default ([#10](https://github.com/pelotech/terraform-azure-foundation/issues/10)) ([a4dcb7c](https://github.com/pelotech/terraform-azure-foundation/commit/a4dcb7c969c8af4d5daf15a46ed36a8b7cc7c0f6))

## [1.0.0](https://github.com/pelotech/terraform-azure-foundation/compare/v0.1.0...v1.0.0) (2026-10-05)


### ⚠ BREAKING CHANGES

* **blob_csi:** answer only the node subnet by default ([#8](https://github.com/pelotech/terraform-azure-foundation/issues/8))

### Features

* **access:** grant readers kube-system Secrets and drop the deployer Key Vault grant ([#6](https://github.com/pelotech/terraform-azure-foundation/issues/6)) ([0a72885](https://github.com/pelotech/terraform-azure-foundation/commit/0a72885f7bda3bdba5d5b91080215f4299187ac8))
* **blob_csi:** allow extra subnets on the storage account ([#9](https://github.com/pelotech/terraform-azure-foundation/issues/9)) ([a9150cc](https://github.com/pelotech/terraform-azure-foundation/commit/a9150cc36e9d98e2f7c2fc156f41c51dd445ef7e))
* **blob_csi:** answer only the node subnet by default ([#8](https://github.com/pelotech/terraform-azure-foundation/issues/8)) ([1d62bc8](https://github.com/pelotech/terraform-azure-foundation/commit/1d62bc86b6a9e6ab723419fd6a8bff7f749e19ec))


### Chores

* **deps:** bump nixpkgs from `e554fab` to `e158d9e` ([#4](https://github.com/pelotech/terraform-azure-foundation/issues/4)) ([7779a54](https://github.com/pelotech/terraform-azure-foundation/commit/7779a54ad6b2cdf00368e91a0e1d5cbbe7c592a6))
* **deps:** update pre-commit hook antonbabenko/pre-commit-terraform to v1.109.2 ([#2](https://github.com/pelotech/terraform-azure-foundation/issues/2)) ([85567e9](https://github.com/pelotech/terraform-azure-foundation/commit/85567e95d79190d113a3eff0d0173bb3da9813a8))

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
