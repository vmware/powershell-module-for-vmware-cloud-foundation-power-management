<!-- markdownlint-disable first-line-h1 no-inline-html -->

<img src="assets/images/icon-color.svg" alt="PowerShell Module for VMware Cloud Foundation Power Management" width="150">

# PowerShell Module for VMware Cloud Foundation Power Management

`VMware.CloudFoundation.PowerManagement` is a PowerShell module that supports the ability to automate the shut down and start up of the [VMware Cloud Foundatiоn][docs-vmware-cloud-foundation]  management domain or VI workload domains using aPowerShell script.

[:material-powershell: &nbsp; PowerShell Gallery][psgallery-module-power-management]{ .md-button .md-button--primary }

## Requirements

### Platforms

The following table lists the supported platforms for this module.

Platform                                                                          | Support
----------------------------------------------------------------------------------|------------------------------------
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 5.0.x on vSAN ReadyNodes | :fontawesome-solid-check:{ .green }
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 4.5.x on vSAN ReadyNodes | :fontawesome-solid-check:{ .green }
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 4.4.x on vSAN ReadyNodes | :fontawesome-solid-check:{ .green }
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 4.3.x on vSAN ReadyNodes | :fontawesome-solid-check:{ .green }

!!! note

    VMware Cloud Foundation on Dell EMC VxRail is not supported.

### Operating Systems

The following table lists the supported operating systems for this module.

Operating System                                                       | Version
-----------------------------------------------------------------------|-----------
:fontawesome-brands-windows: &nbsp; Microsoft Windows Server           | 2019, 2022
:fontawesome-brands-windows: &nbsp; Microsoft Windows                  | 10, 11

### PowerShell

The following table lists the supported editions and versions of PowerShell for this module.

Edition                                                                           | Version
----------------------------------------------------------------------------------|----------
:material-powershell: &nbsp; [PowerShell Core][microsoft-powershell]              | >= 7.2.0

### Module Dependencies

The following table lists the required PowerShell module dependencies for this module.

PowerShell Module                                    | Version   | Publisher    | Reference
-----------------------------------------------------|-----------|--------------|---------------------------------------------------------------------------
[VMware.PowerCLI][psgallery-module-powercli]         | >= 13.0.0 | VMware, Inc. | :fontawesome-solid-book: &nbsp; [Documentation][developer-module-powercli]
[PowerVCF][psgallery-module-powervcf]                | >= 2.3.0  | VMware, Inc. | :fontawesome-solid-book: &nbsp; [Documentation][docs-module-powervcf]
[PoshSSH][psgallery-module-poshssh]                  | >= 3.0.4  | Carlos Perez | :fontawesome-brands-github: &nbsp; [GitHub][github-module-poshssh]

[docs-module-powervcf]: https://vmware.github.io/powershell-module-for-vmware-cloud-foundation
[docs-vmware-cloud-foundation]: https://docs.vmware.com/en/VMware-Cloud-Foundation/index.html
[microsoft-powershell]: https://docs.microsoft.com/en-us/powershell
[psgallery-module-powercli]: https://www.powershellgallery.com/packages/VMware.PowerCLI
[psgallery-module-powervcf]: https://www.powershellgallery.com/packages/PowerVCF
[psgallery-module-power-management]: https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement
[psgallery-module-poshssh]: https://www.powershellgallery.com/packages/Posh-SSH
[developer-module-powercli]: https://developer.vmware.com/tool/vmware-powercli
[github-module-poshssh]: https://github.com/darkoperator/Posh-SSH
