# Release History

## v1.4.1

> Release Date: Not Released

Enhancement:

- Added check for VMware Aria Operations for Logs deployment and shutdown if it exists. [GH-87](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/87)
- Updated `PowerManagement-ManagmentDomain.ps1` to check for virtual machines running on an NSX overlay segment. [GH-86](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/86)
- Added check to verify if workload domain vCenter Server instances are still powered on before starting the shutdown of the management domain to `PowerManagement-ManagmentDomain.ps1`. [GH-90](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/90)
- Added check for virtual machines running on an NSX overlay segment to `PowerManagement-ManagmentDomain.ps1`. [GH-86](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/86)
- Added support for more than one cluster in management domain for shut down and start up to `PowerManagement-ManagmentDomain.ps1`. [GH-93](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/93)
- Added support to `PowerManagement-ManagmentDomain.ps1` and `PowerManagement-WorkloadDomain.ps1` for vSAN File Services to be excluded from customer virtual machines [GH-94](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/94)

Refactor:

- Replaced the use of `Test-NetConnection` to with `Test-EndpointConnection` from the PowerShell module `PowerValidatedSolutions`. [GH-85](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/85)
- Replaced current if statement `nsxtEdgeNodes` to check for virtual machines running on an NSX overlay network. [GH-86] (https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/86)

Chore:

- Updated `PowerVCF` from v2.3.0 to v2.4.0. [GH-85](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/85)
- Added `PowerValidatedSolutions` v2.8.0 as a module dependency. [GH-38](https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/pull/38)
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
