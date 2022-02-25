# Shutting Down and Starting Up VMware Cloud Foundation by Using Windows PowerShell
# Disclaimer  
Use this software on your own risk..... (Add notes from the scripts here) 

# Supported Platforms
Tested on Windows 10 and Windows 2016 running Windows PowerShell 5.1
Supported target systems: VMware Cloud Foundation 4.4 and VMware Cloud Foundation 4.3

# Limitations
- Site Recovery Manager and vSphere Replication are not supported.
- Limited error handling.
- The parameters and behavior of the scripts might change in the next version of the module.
VMware, Inc.
4Shutting Down and Starting Up VMware Cloud Foundation by Using Windows PowerShell
- You must shut down the ESXi hosts manually. The scripts only place the hosts in maintenance
mode.
- The sample scripts work only on a workload domain with a single cluster.
- You must shut down manually the NSX Edge nodes that are not deployed by SDDC Manager.
- vRealize Log Insight might not be detected in the vCenter Server inventory.
- Timeouts for some operations might be too short.
- To be able to shut down the customer virtual machines in the management domain or in a VI
workload domain, they must have VMware Tools running. The virtual machines are shut down
in a random order.
- The SSH service on the ESXi hosts must be running.
# Scripts for Shutdown and Startup of a Workload Domain
- **PowerManagement-ManagementDomain.ps1** - Shut down or start up all software components in the management 
domain including vRealize Suite and virtual infrastructure components.

- **PowerManagement-vRealizeSuite.ps1** - Shut down or start up the vRealize Suite components in the management 
domain.

- **PowerManagement-WorkloadDomain.ps1** - Shut down or start up the management components for a VI
workload domain including vSphere with Tanzu and virtual infrastructure
components.

- **PowerManagement-Tanzu.ps1** - Shut down or start up the vSphere with Tanzu components in a VI workload
domain.
# Prerequisites
- Run PowerShell as Administrator and install the VMware.PowerManagement PowerShell
module together with the supporting modules from the PowerShell Gallery by running the
following commands:  
    > `Install-Module -Name VMware.PowerCLI -MinimumVersion 12.3.0`  
    > `Install-Module -Name VMware.PowerManagement -MinimumVersion 0.5.0`  
    > `Install-Module -Name PowerVCF -MinimumVersion 2.1.7`  
    > `Install-Module -Name Posh-SSH -MinimumVersion 2.3.0`  
- Verify that SDDC Manager is running.
- Before you shut down the management domain, get the credentials for the management
domain hosts and vCenter Server from SDDC Manager and save them for troubleshooting or a
subsequent manual startup. Because SDDC Manager is down during each of these operations,
you must save the credentials in advance.
To get the credentials, log in to the SDDC Manager appliance by using a Secure Shell (SSH)
client as **vcf** and run the `lookup_passwords` command.
On Windows 10, configure the PowerShell execution policy with the permissions required to
run the commands.  
a) Run the `Execute Get-ExecutionPolicy` command to get the active execution policy.  
b) If the `Execute Get-ExecutionPolicy` command returns `Restricted`, run the 
`Set-ExecutionPolicy RemoteSigned` command.

# How to use sample scripts
1. Enable SSH on the ESXi hosts in the workload domain by using the SoS utility of the SDDC
Manager appliance.
    - Log in to the SDDC Manager appliance by using a Secure Shell (SSH) client as vcf.
    - Switch to the root user by running the su command and entering the root password.
    - Run this command:
         > `/opt/vmware/sddc-support/sos --enable-ssh-esxi --domain domain-name`
2. On the Windows machine that is allocated to run the scripts, start Windows PowerShell.
3. Locate the home directory of the VMware.PowerManagement module by running this
PowerShell command.
    > `(Get-Module -ListAvailable VMware.PowerManagement*).path`  

> For example, the full path to the module might be `C:\Program
Files\WindowsPowerShell\Modules\VMware.PowerManagement\0.5.0\VMware.PowerM
anagement.psd1`.  
4. Go to the SampleScripts folder that is located in the same folder as the
`VMware.PowerManagement.psd1` file.
5. To shut down or start up a VI workload domain, perform these steps.  
    - Replace the values in the sample code with values from your environment and run the
commands in the PowerShell console.  
    > `$sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"`  
    > `$sddcManagerUser = "administrator@vsphere.local"`  
    > `$sddcManagerPass = "VMw@re1!"`  
    > `$sddcDomain = "sfo-w01"`  
    > `$powerState = "Shutdown"`  
    - Run the PowerManagement-WorkloadDomain.ps1 script.  
    > `PowerManagement-WorkloadDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomain -powerState $powerState -shutdownCustomerVm`  

    > You can use the `-shutdownCustomerVm` parameter for a VI workload domain that does not
run vSphere with Tanzu. When you use this parameter, the customer virtual machines are
shut down before the ESXi hosts. As a result, those of them that use overlay-backed NSX
segments lose connectivity until they are shut down.
6. To shut down or start up the vRealize Suite components in the management domain, perform
these steps.  
    - Replace the values in the sample code with values from your environment and run the
commands in the PowerShell console.
    > `$sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"`  
    > `$sddcManagerUser = "administrator@vsphere.local"`  
    > `$sddcManagerPass = "VMw@re1!"`  
    > `$powerState = "Startup"`  
    - Run the PowerManagement-vRealizeSuite.ps1 script.  
    > `PowerManagement-vRealizeSuite.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -powerState $powerState`  
7. To shut down or start up the management domain, perform these steps.
    - Replace the values in the sample code with values from your environment and run the
commands in the PowerShell console.
    > `$sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"`  
    > `$sddcManagerUser = "administrator@vsphere.local"`  
    > `$sddcManagerPass = "VMw@re1!"`  
    - Run the `PowerManagement-ManagementDomain.ps1` script.  
    > `PowerManagement-ManagementDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -powerState Shutdown`  
    > `PowerManagement-ManagementDomain.ps1 -powerState Startup`  
    During the shutdown operation, the script generates a ManagementStartupInput.json file
in the current directory. The script then uses the file for the subsequent startup of the
management domain.  
    Because the script overwrites the JSON file every time you run it, if you are shutting down
multiple management domains, rename the file before shutting down the next domain.
___
### *Caution* Although the credentials in the JSON file are encrypted, treat the content of this file as sensitive data.
___

___
**Note** More usage examples are available in the scripts.
___
# Troubleshooting
- ESXi hosts should have SSH service running and accessible from the machine running the scripts
- In case of failure the script could be started again with the same parameters in order to overcome
some errors.
- Identify the step that is causing the issue and continue the sequence following the manual guide
- During shutdown of the Management Domain if SDDC manager is already stopped the only option is to continue
with manual steps, following VCF documentation
