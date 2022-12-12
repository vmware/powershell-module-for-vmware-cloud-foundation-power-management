<!-- markdownlint-disable first-line-h1 no-inline-html -->

<img src=".github/icon-400px.svg" alt="A PowerShell Module for Cloud Foundation Power Management" width="150"></br></br>

# PowerShell Module for VMware Cloud Foundation Power Management

[<img src="https://img.shields.io/powershellgallery/v/VMware.CloudFoundation.PowerManagement?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell Gallery">][module-powermanagement]&nbsp;&nbsp;
[<img src="https://img.shields.io/badge/Changelog-Read-blue?style=for-the-badge&logo=github&logoColor=white" alt="CHANGELOG" >][changelog]&nbsp;&nbsp;
[<img src="https://img.shields.io/powershellgallery/dt/VMware.CloudFoundation.PowerManagement?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell Gallery Downloads">][module-powermanagement]&nbsp;&nbsp;

## Overview

`VMware.CloudFoundation.PowerManagement` is a PowerShell module that supports the ability to automate the shut down and start up of the [VMware Cloud Foundation][vmware-cloud-foundation] management domain or VI workload domains using aPowerShell script.

Sample PowerShell scripts are included with the module.

The scripts follow the order for manual shutdown and startup of VMware Cloud Foundation. You can complete the workflow manually at any point. You can also run the scripts multiple times.

Please, refer to the [Limitations](#limitations), [Known Issues](#known-issues), and [Troubleshooting](#troubleshooting) sections.

## Requirements

### Platforms

- VMware Cloud Foundation 4.5.x on vSAN ReadyNodes
- VMware Cloud Foundation 4.4.x on vSAN ReadyNodes
- VMware Cloud Foundation 4.3.x on vSAN ReadyNodes

> **Note**
>
> VMware Cloud Foundation on Dell EMC VxRail is not supported.

### Operating Systems

- Microsoft Windows Server 2016, 2019, and 2022
- Microsoft Windows 10

### PowerShell Editions and Versions

- [PowerShell Core 7.2.4 or later][microsoft-powershell]

### PowerShell Modules

- [`VMware.PowerCLI`][module-powercli] 12.7.0 or later
- [`PowerVCF`][module-powervcf] 2.2.0 or later
- [`Posh-SSH`][module-posh-ssh] 3.0.4 or later

## Installing the Module

Verify that your system has a supported edition and version of PowerShell installed.

Install the PowerShell module and its dependencies from the PowerShell Gallery by running the following commands:

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name VMware.PowerCLI -MinimumVersion 12.7.0
Install-Module -Name PowerVCF -MinimumVersion 2.2.0
Install-Module -Name Posh-SSH -MinimumVersion 3.0.4
Install-Module -Name VMware.CloudFoundation.PowerManagement
```

## Getting Started

### Sample Scripts

- `PowerManagement-ManagementDomain.ps1` - shutdown or startup all software components in the management domain.

    > **Note**
    >
    > The script does not support shutdown of vRealize Suite. Shut down the vRealize Suite components in your environment manually before running the script.

- `PowerManagement-WorkloadDomain.ps1` - Shut down or start up the management components for a workload domain.

    > **Note**
    >
    > The script does not support vSphere with Tanzu.

### Prerequisites

- Add forward and reverse DNS records for the client machine running the scripts.

- Verify that SDDC Manager is powered on and operational.

- Before you shut down the management domain, get the credentials for the management domain ESXi hosts and vCenter Server instance from SDDC Manager and save them for troubleshooting or a subsequent manual startup. Because SDDC Manager is powered off during each of these operations, you must save the credentials in advance.

To get the credentials, log in to the SDDC Manager appliance by using a Secure Shell (SSH) client as `vcf` and run the `lookup_passwords` command.

If using Windows 10, configure the PowerShell execution policy with the permissions required to run the commands.

- Run the following command to get the active execution policy:

    ```powershell
    Execute Get-ExecutionPolicy
    ```

- If the command returns `Restricted`, run the following command:

    ```powershell
    Set-ExecutionPolicy RemoteSigned
    ```

- If the target system uses self-signed or untrusted certificates, configure PowerCLI to ignore.

    ```powershell
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    ```

### Usage Examples

> **Note**
>
> More usage examples are available in the scripts.

1. Enable SSH on the ESXi hosts (required for VMware Cloud Foundation before version 4.5) in the workload domain by using the SoS utility of the SDDC Manager appliance.

    - Log in to the SDDC Manager appliance by using a Secure Shell (SSH) client as `vcf`.

    - Switch to the `root` user by running the `su` command and entering the `root` password.

    - Run the following command:

        ```bash
        /opt/vmware/sddc-support/sos --enable-ssh-esxi --domain domain-name
        ```

2. On the Windows machine that is allocated to run the scripts, start Windows PowerShell 7.x.

3. Locate the path of the `VMware.CloudFoundation.PowerManagement` module by running the following PowerShell command:

    ```powershell
    (Get-Module -ListAvailable VMware.CloudFoundation.PowerManagement*).path
    ```

    For example, the full path to the module may resemble:

    ```powershell
    C:\Program Files\WindowsPowerShell\Modules\VMware.CloudFoundation.PowerManagement\1.0.0.1000\VMware.CloudFoundation.PowerManagement.psd1
    ```

4. Go to the `SampleScripts` folder that is located in the same folder as the
`VMware.CloudFoundation.PowerManagement.psd1` file.

5. To shut down or start up a VI workload domain, perform these steps.

    - Replace the values in the sample variables with values from your environment and run the following commands in the PowerShell console:

        ```powershell
        $sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"

        $sddcManagerUser = "administrator@vsphere.local"

        $sddcManagerPass = "VMw@re1!"

        $sddcDomain = "sfo-w01"
        ```

    - Run the `PowerManagement-WorkloadDomain.ps1` script:

        ```powershell
        ./PowerManagement-WorkloadDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomain -shutdown -shutdownCustomerVm
        ```

    When you use the `-shutdownCustomerVm` parameter, the virtual machines are shut down as the first step of the process.

6. To shut down or start up the management domain, perform these steps.

    - Replace the values in the sample variables with values from your environment and run the following commands in the PowerShell console:

        ```powershell
        $sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"

        $sddcManagerUser = "administrator@vsphere.local"

        $sddcManagerPass = "VMw@re1!"
        ```

    - Run the `PowerManagement-ManagementDomain.ps1` script:

        ```powershell
        ./PowerManagement-ManagementDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -shutdown
        
        ./PowerManagement-ManagementDomain.ps1 -startup
        ```

    During the shutdown operation, the script generates a `ManagementStartupInput.json` file in the current directory. The script then uses the file for the subsequent startup of the management domain.

    Because the script overwrites the JSON file every time you run it, if you are shutting down multiple management domains, rename the file before shutting down the next domain.

    > **Warning**
    >
    > Although the credentials in the JSON file are encrypted, treat the content of this file as sensitive data.

## Limitations

- VMware Cloud Foundation on Dell EMC VxRail is not supported.

- vSphere with Tanzu, vSphere Replication, Site Recovery Manager, vRealize Suite, and Workspace ONE Access are not supported.

- For VMware Cloud Foundation 4.4 and earlier, you must shut down the ESXi hosts manually. The scripts only place the hosts in maintenance mode.

- ESXi hosts startup is not handled by the scripts. They should be started before running the scripts.

- The sample script for management domain only works on a management domain with a single cluster.

- You must stop and start NSX Edge bare-metal nodes manually.

- VMware Tools running must be running in virtual machines to shut down in the management domain or in a VI workload domain using a script. The virtual machines are shut down in a random order using the "Shutdown Guest OS" command from vCenter Server.

- For VMware Cloud Foundation 4.4 and earlier, the SSH service on the ESXi hosts must be running.

- For VMware Cloud Foundation 4.5 and newer versions the Lockdown Mode of ESXi hosts should be disabled before shut down. You can enabled it after the startup is completed.

- Scripts cannot handle simultaneous connections to multiple services. In the script's console, all sessions to services that are not used at the moment will be disconnected.

## Known Issues

- VMware Workspace ONE Access that is integrated with NSX, should be started manually. For VMware Cloud Foundation version 4.5.x and newer, this can be done before using the script for starting the Management Domain.

- All vCenter Server instances for Workload Domains will be started with the first Workload Domain in order to get full inventory information in SDDC Manager.

- For VMware Cloud Foundation version 4.5 and later, if you have multiple clusters in a single Workload Domain manual intervention is required during startup. Clusters should be put in the correct status (shutdown). See Scenario 3 in [KB 87350][vmware-kb-87350].

- From all service virtual machines, deployed by vSphere ESX Agent Manager, only the vCLS VMs will be handled in an automatic way. All other service virtual machines (_e.g._, vSAN File Service Nodes) will lead to an error in the script. Clusters with such virtual machines should be stopped through vCenter Server UI.

- For Workload Domains with multiple clusters, if you do not specify shut down order the clusters will be stopped in the order returned from SDDC Manager API. For granular control, please use the `-vsanCluster` parameter.

## Troubleshooting

- ESXi hosts must have SSH service up, running and accessible from the machine running the scripts (required for VMware Cloud Foundation 4.4 and earlier.)

- In case of a failure, run the script with the same parameters in order to overcome some errors.

- Identify the step that is causing the issue and continue the sequence following the manual guide in VMware Cloud Foundation documentation.

- During shutdown of the management domain, if SDDC Manager is already powered off, the only option is to continue by following the manual steps in the VMware Cloud Foundation documentation.

## Support

This PowerShell module is not supported by VMware Support.

If you discover a bug or would like to suggest an enhancement, please [open an issue][issues].

## Contributing

The project team welcomes contributions from the community. Before you start working with PowerValidatedSolutions, please read our [Developer Certificate of Origin][vmware-cla-dco]. All contributions to this repository must be signed as described on that page. Your signature certifies that you wrote the patch or have the right to pass it on as an open-source patch.

For more detailed information, refer to the [contribution guidelines][contributing] to get started.

## License

Copyright 2022 VMware, Inc.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[//]: Links

[changelog]: CHANGELOG.md
[contributing]: CONTRIBUTING.md
[issues]: https://github.com/vmware/powershell-module-for-vmware-cloud-foundation-power-management/issues
[microsoft-powershell]: https://docs.microsoft.com/en-us/powershell
[module-posh-ssh]: https://www.powershellgallery.com/packages/Posh-SSH
[module-powercli]: https://www.powershellgallery.com/packages/VMware.PowerCLI
[module-powermanagement]: https://www.powershellgallery.com/packages/VMware.CloudFoundation.PowerManagement
[module-powervcf]: https://www.powershellgallery.com/packages/PowerVCF
[vmware-cla-dco]: https://cla.vmware.com/dco
[vmware-cloud-foundation]: https://docs.vmware.com/en/VMware-Cloud-Foundation
[vmware-kb-87350]: https://kb.vmware.com/s/article/87350
