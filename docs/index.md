<!-- markdownlint-disable first-line-h1 no-inline-html -->

<img src="assets/images/icon-color.svg" alt="PowerShell Module for VMware Cloud Foundation Power Management" width="150">

# PowerShell Module for VMware Cloud Foundation Power Management

`VMware.CloudFoundation.PowerManagement` is a PowerShell module that supports the ability to automate the shut down and start up of the VMware Cloud Foundatiоn]management domain or workload domains using aPowerShell script.

[:material-powershell: &nbsp; PowerShell Gallery][psgallery-module-power-management]{ .md-button .md-button--primary }

## Requirements

### VMware Cloud Foundation

The following table lists the supported releases for this module.

Platform                                                     | vSAN ReadyNodes                     | Dell VxRail
-------------------------------------------------------------|-------------------------------------|------------------------------------
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 5.2 | :fontawesome-solid-check:{ .green } | :fontawesome-solid-x:{ .red }
:fontawesome-solid-cloud: &nbsp; VMware Cloud Foundation 5.1 | :fontawesome-solid-check:{ .green } | :fontawesome-solid-x:{ .red }

???+ tip "Support for Newer Major Releases"

    This module will **only** be sustained for supported versions of the VMware Cloud Foundation releases listed above to address critical issues. You can find general details on supported versions in the [Broadcom Product Lifecycle](https://support.broadcom.com/group/ecx/productlifecycle).

    Please note that this module **will not** provide support or new enhancements for future major releases of VMware Cloud Foundation. If you're planning to upgrade to those newer releases, we encourage you to explore alternative in-product or custom automation solutions.

    We truly appreciate your reliance on and support of this module. Thank you for your understanding as we transition to sustaining the module for these specific major versions.

???+ note

    VMware Cloud Foundation on Dell VxRail cluster shutdown API cannot be used when the managed VMware vCenter Server instance is running on VxRail.

### PowerShell

The following table lists the supported editions and versions of PowerShell for this module.

Edition                                                                           | Version
----------------------------------------------------------------------------------|----------
:material-powershell: &nbsp; [PowerShell Core][microsoft-powershell]              | >= 7.2.0

### Module Dependencies

The following table lists the required PowerShell module dependencies for this module.

PowerShell Module                                    | Version   | Publisher    | Reference
-----------------------------------------------------|-----------|--------------|---------------------------------------------------------------------------
[VMware.PowerCLI][psgallery-module-powercli]         | >= 13.3.0 | Broadcom     | :fontawesome-solid-book: &nbsp; [Documentation][developer-module-powercli]
[PowerVCF][psgallery-module-powervcf]                | >= 2.4.1  | Broadcom     | :fontawesome-solid-book: &nbsp; [Documentation][docs-module-powervcf]
[PowerValidatedSolutions][psgallery-module-pvs]      | >= 2.12.1 | Broadcom     | :fontawesome-solid-book: &nbsp; [Documentation][docs-module-pvs]
[PoshSSH][psgallery-module-poshssh]                  | >= 3.0.8  | Carlos Perez | :fontawesome-brands-github: &nbsp; [GitHub][github-module-poshssh]

[docs-module-powervcf]: https://vmware.github.io/powershell-module-for-vmware-cloud-foundation
[docs-module-pvs]: https://vmware.github.io/power-validated-solutions-for-cloud-foundation/
[microsoft-powershell]: https://docs.microsoft.com/en-us/powershell
[psgallery-module-powercli]: https://www.powershellgallery.com/packages/VMware.PowerCLI
[psgallery-module-powervcf]: https://www.powershellgallery.com/packages/PowerVCF
[psgallery-module-pvs]: https://www.powershellgallery.com/packages/PowerValidatedSolutions
[psgallery-module-power-management]: https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement
[psgallery-module-poshssh]: https://www.powershellgallery.com/packages/Posh-SSH
[developer-module-powercli]: https://developer.broadcom.com/powercli
[github-module-poshssh]: https://github.com/darkoperator/Posh-SSH
[vxrail-cluster-shutdown]: https://www.dell.com/support/manuals/en-us/vxrail-appliance-series/vxrail-8.x_admin_guide/shut-down-a-vxrail-cluster?guid=guid-da69fd52-38b2-465e-b8d9-45191b016679&lang=en-us
