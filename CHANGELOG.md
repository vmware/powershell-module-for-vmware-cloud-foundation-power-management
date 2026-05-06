# Release History

## Unreleased

> Target: VCF 5.x and VCF 9.x. Requires PowerShell 7.4 or later. Support for VCF 4.x and Windows PowerShell (Desktop edition) has been dropped.

Breaking Changes:

- Dropped support for VMware Cloud Foundation 4.x. All version-gated code paths for VCF < 4.5 and VCF < 5.0 have been removed from the sample scripts.
- Dropped support for Windows PowerShell (Desktop edition). The module now requires PowerShell 7.4 or later.
- Removed `Invoke-EsxCommand` and `Get-SSHEnabledStatus` from the module. These functions were only called within the now-removed VCF 4.x code paths and required the `Posh-SSH` module.
- `Write-PowerManagementLogMessage` and `Debug-CatchWriterForPowerManagement` are removed and replaced by `Write-LogMessage` and `New-LogFile` (see Refactor below).

Refactor:

- Replaced the `Posh-SSH`, `PowerVCF`, and `PowerValidatedSolutions` module dependencies with VCF PowerCLI 9 and direct REST calls.
- Replaced `Test-EndpointConnection` (from `PowerValidatedSolutions`) with a private `Test-ManagementEndpoint` helper inlined in the module, eliminating the `PowerValidatedSolutions` dependency entirely.
- Replaced `Connect-NsxTServer`/`Get-NSXtService` (from `VMware.VimAutomation.Nsxt`) in `Get-EdgeNodeFromNSXManager` and `Get-NSXTComputeManagers` with direct `Invoke-RestMethod` calls using Basic Auth. NSX version is detected at runtime: VCF 9 (NSX 9.0+) uses the Policy API path; VCF 5.x uses the v1 management-plane path.
- Replaced `Connect-CisServer`/`Get-CisService` (from `VMware.VimAutomation.Cis.Core`) in `Get-VamiServiceStatus` and `Set-VamiServiceStatus` with direct `Invoke-RestMethod` calls against the vCenter REST API (`/api/vcenter/services/{name}`), which is the supported path for both VCF 5 and VCF 9.
- Replaced `get-wmcluster` (from `VMware.VimAutomation.WorkloadManagement`) in `Get-TanzuEnabledClusterStatus` with a direct `Invoke-RestMethod` call against `/api/vcenter/namespace-management/clusters/{moref}`.
- Added `Set-Retreatmode` guard: the function now detects vSphere 9.0+ and skips the vCLS retreat mode advanced-setting operation with a warning, as this setting is deprecated and unsupported in vSphere 9.0.
- Sample scripts updated to use `ssoId`-scoped credential lookup unconditionally (previously gated behind VCF >= 5.0).
- vSAN cluster shutdown and startup use the shutdown wizard (`Set-VsanClusterPowerStatus`) unconditionally in both sample scripts.

Chore:

- Updated `VMware.PowerCLI` minimum required version from `13.3.0` to `9.0.0`.
- Bumped `PowerShellVersion` in the module manifest from `7.2.0` to `7.4.0`.
- Removed `Posh-SSH`, `PowerVCF`, and `PowerValidatedSolutions` from `RequiredModules` in the module manifest.
- Replaced `Write-PowerManagementLogMessage` and `Debug-CatchWriterForPowerManagement` with `Write-LogMessage` and `New-LogFile`, aligned with the standard logging pattern from the reference `VcfEdgeAtScale` module. The new logger uses `$Script:LogFile`, `$Script:ConfiguredLogLevel`, and a `Test-LogLevel` level hierarchy (DEBUG < INFO < WARNING < EXCEPTION < ERROR). Sample scripts now call `New-LogFile` at startup instead of `Start-SetupLogFile`.
- Removed the Windows PowerShell (Desktop edition) self-signed certificate compatibility block from module initialization. `Test-ManagementEndpoint` now uses `Test-Connection -TcpPort` directly (PS 7 only).

## v1.6.0

> Release Date: 2025-06-05

Documentation:

- Updated documentation to use example context. (#119, #120, #129, #130, #131, #132, #133)

Chore:

- Updated `VMware.PowerCLI` module dependency from v13.2.1 to v13.3.0. (#126)
- Updated `PowerValidatedSolutions` module dependency from v2.11.0 to v2.12.1. (#126)

## v1.5.0

> Release Date: 2024-10-02

Bugfix:

- Added support to `PowerManagement-ManagmentDomain.ps1` and `PowerManagement-WorkloadDomain.ps1` for vSAN File Services to be excluded from customer virtual machines. [GH-95](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/95)
- Added exit to Tanzu Code in `PowerManagement-WorkloadDomain.ps1`[GH-97](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/97)
- Added support to `PowerManagement-ManagmentDomain.ps1` and `PowerManagement-WorkloadDomain.ps1` for testing ESXi host connection before SSH connection. [GH-98](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/98)
- Fix for issue [#101](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/issues/101)[GH-106](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/106)
- Fix for issue [#104](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/issues/104)[GH-106](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/106)

Enhancement:

- Added check to verify if workload domain vCenter Server instances are still powered on before starting the shutdown of the management domain to `PowerManagement-ManagmentDomain.ps1`. [GH-90](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/90)
- Various improvements in workflows, log messages, file syntax. [GH-106](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/106) and [GH-107](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/107)

Refactor:

- Replaced the use of `Test-NetConnection` with `Test-EndpointConnection` from the PowerShell module dependency `PowerValidatedSolutions`. [GH-85](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/85)
- Updated `PowerManagement-ManagmentDomain.ps1` to allow for FQDN or IP address of SDDC Manager. [GH-92](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/92)
- Removed obsolete and not used code in the sample scripts.
- Apply common formatting for the files. [GH-107](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/107)

Chore:

- Updated `PowerVCF` from v2.3.0 to v2.4.1. [GH-108](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/108)
- Added `PowerValidatedSolutions` v2.8.0 as a PowerShell module dependency. [GH-38](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/38)
- Updated `PowerValidatedSolutions` from v2.8.0 to 2.11.0. [GH-108](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/108)
- Updated `Write-PowerManagementLogMessage` to set color for message types. This will allow for all references to use color based on function. [GH-89](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/89)

## v1.4.0

> Release Date: 2023-12-05

Enhancement:

- Added support for VMware Cloud Foundation 5.0 on Dell VxRail. [GH-75](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/75)

## v1.3.0

> Release Date: 2023-11-16

Enhancement:

- Added secure strings for sensitive parameters. [GH-73](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/73)

## v1.2.0

> Release Date: 2023-07-25

Enhancement:

- Updated each cmdlet to include the `.PARAMETER` details. [GH-27](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/27)
- Added support for VMware Cloud Foundation 5.0. [GH-37](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/37)

Chore:

- Updated PowerVCF from v2.2.0 to v2.3.0. [GH-38](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/38)
- Updated Posh-SSH from v3.0.4 to v3.0.8. [GH-38](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/38)

## v1.1.0

> Release Date: 2022-12-09

The initial release of the PowerShell Module for VMware Cloud Foundation Power Management, `VMware.CloudFoundation.PowerManagement`, replacing `VMware.PowerManagement`.

Enhancement:

- Sample scripts use the vSAN shutdown wizard API (VMware Cloud Foundation version 4.5 and later.)
- Added support for multiple clusters in a workload domain.
- Added support for NSX Managers that are shared between workload domains.
- Bugfixes and workflow improvements.
