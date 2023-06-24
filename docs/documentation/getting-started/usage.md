# Using the Module

## Prerequisites

- Add forward and reverse DNS records for the client machine running the scripts.

- Verify that SDDC Manager is powered on and operational.

- Before you shut down the management domain, get the credentials for the management domain ESXi hosts and vCenter Server instance from SDDC Manager and save them for troubleshooting or a subsequent manual startup. Because SDDC Manager is powered off during each of these operations, you must save the credentials in advance.

To get the credentials, use the `Get-VCFCredential` cmdlet from the [`PowerVCF`][docs-module-powervcf] module.

If using Windows 10 or 11, configure the PowerShell execution policy with the permissions required to run the commands.

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

## Sample Scripts

- `PowerManagement-ManagementDomain.ps1` - shutdown or startup all software components in the management domain.

    !!! Note

        The script does not support shutdown of Aria Suite (formerly vRealize Suite). 
        Shut down the Aria Suite components in your environment before running the script.

- `PowerManagement-WorkloadDomain.ps1` - Shut down or start up the management components for a workload domain.

    !!! Note

        The script does not support vSphere with Tanzu.

## Usage Examples

!!! Note

    More usage examples are available in the sample scripts.

1. Enable SSH on the ESXi hosts (required for VMware Cloud Foundation 4.4 and earlier) in the workload domain by using the SoS utility of the SDDC Manager appliance.

    - Log in to the SDDC Manager appliance by using a Secure Shell (SSH) client as `vcf`.

    - Switch to the `root` user by running the `su` command and entering the `root` password.

    - Run the following command:

        ```bash
        /opt/vmware/sddc-support/sos --enable-ssh-esxi --domain domain-name
        ```

2. On the Windows machine that is allocated to run the scripts, start PowerShell 7.x.

3. Locate the path of the `VMware.CloudFoundation.PowerManagement` module by running the following PowerShell command:

    ```powershell
    (Get-Module -ListAvailable VMware.CloudFoundation.PowerManagement*).path
    ```

    For example, the full path to the module may resemble:

    ```powershell
    C:\Program Files\WindowsPowerShell\Modules\VMware.CloudFoundation.PowerManagement\1.0.0.1000\VMware.CloudFoundation.PowerManagement.psd1
    ```

4. Go to the `SampleScripts` folder that is located in the same folder as the `VMware.CloudFoundation.PowerManagement.psd1` file.

5. To shut down or start up a VI workload domain, perform these steps.

    - Replace the values in the sample variables with values from your environment and run the following commands in the PowerShell console:

        ```powershell
        --8<-- "./docs/snippets/vars-vcf.ps1"
        --8<-- "./docs/snippets/vars-domain.ps1"
        ```

    - Run the `PowerManagement-WorkloadDomain.ps1` script:

        ```powershell
        ./PowerManagement-WorkloadDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomain -shutdown -shutdownCustomerVm
        ```

    When you use the `-shutdownCustomerVm` parameter, the virtual machines are shut down as the first step of the process.

6. To shut down or start up the management domain, perform these steps.

    - Replace the values in the sample variables with values from your environment and run the following commands in the PowerShell console:

        ```powershell
        --8<-- "./docs/snippets/vars-vcf.ps1"
        ```

    - Run the `PowerManagement-ManagementDomain.ps1` script:

        ```powershell
        ./PowerManagement-ManagementDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -shutdown
        
        ./PowerManagement-ManagementDomain.ps1 -startup
        ```

    During the shutdown operation, the script generates a `ManagementStartupInput.json` file in the current directory. The script then uses the file for the subsequent startup of the management domain.

    Because the script overwrites the JSON file every time you run it, if you are shutting down multiple management domains, rename the file before shutting down the next domain.

    !!! Warning

        Although the credentials in the JSON file are encrypted, treat the content of this file as sensitive data.

[docs-module-powervcf]: https://vmware.github.io/powershell-module-for-vmware-cloud-foundation
