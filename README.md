# Shutting Down and Starting Up VMware Cloud Foundation by Using Windows PowerShell
# Disclaimer  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Overview
Instead of the default step-by-step approach by using product user interface, you can shut down the management domain or a VI workload domain in an automated way by running a Windows PowerShell script. To shut down or start up the management domain or a VI workload domain, you run sample PowerShell scripts that come with the VMware.CloudFoundation.PowerManagement module. The scripts follow the order for manual shutdown and startup of VMware Cloud Foundation. You can complete the workflow manually at any point. You can also run the scripts multiple times. Please, check limitations section below.
# Supported Platforms
- Tested on up-to-date versions of Windows 10, Windows 2016, Windows 2019 and Windows 2022, each running Windows PowerShell 7.2.4  
- Supported target systems: vSAN ReadyNodes running VMware Cloud Foundation 4.3.x, VMware Cloud Foundation 4.4.x and VMware Cloud Foundation 4.5.x

# What's new
- Version 1.1
    - Sample scripts will use vSAN shutdown wizard API for VMware Cloud Foundation version 4.5.0 and newer.
    - Added support for multiple clusters in a single Workload Domain.
    - Added support for NSX Managers that are shared between several Workload Domains.
    - Bugfixes and workflows improvements

# Limitations
- VMware Cloud Foundation on VxRail **IS NOT** supported.
- Site Recovery Manager, vSphere Replication, vRealize Suite, Workspace ONE Access and vSphere with Tanzu are not supported.
- For VMware Cloud Foundation before version 4.5.x, you must shut down the ESXi hosts manually. The scripts only place the hosts in maintenance mode.
- The sample script for Management domain work only on Management domain with a single cluster.
- You must stop and start NSX Edge bare-metal nodes manually.
- ESXi hosts startup is not handled by the scripts. They should be started before running the scripts.
- To be able to shut down the customer VMs in the management domain or in a VI workload domain by using a script, they must have VMware Tools running. The virtual machines are shut down
in a random order by running the "Shutdown guest OS" command from vCenter Server.
- The SSH service on the ESXi hosts must be running for VMware Cloud Foundation 4.3.x and VMware Cloud Foundation 4.4.x.
- Scripts cannot handle simultaneous connections to multiple services. In the script's console, all sessions to services that are not used at the moment will be disconnected.
- For VMware Cloud Foundation 4.5.0 and newer versions the Lockdown Mode of ESXi hosts should be disabled before shutdown. It could be enabled, after the startup is completed.

# Known issues
- VMware Workspace ONE Access that is integrated with NSX, should be started manually. For VMware Cloud Foundation version 4.5.x and newer, this could be done before using the script for starting the Management domain
- All vCenter servers for Workload Domains will be started with first Workload Domain in order to get full inventory information in SDDC Manager.
- Manual intervention is required, for VMware Cloud Foundation version 4.5.x and newer, during startup if you have multiple clusters in a single Workload Domain. Clusters should be put in the correct status (shutdown). See https://kb.vmware.com/s/article/87350 Scenario 3
- From all service virtual machines, deployed by vSphere ESX Agent Manager, only the vCLS VMs will be handled in an automatic way. All other service virtual machines (e.g. vSAN File Service Nodes) will lead to an error in the script. Clusters with such virtual machines should be stopped through vCenter Server UI.
- For Workload Domains with multiple clusters if you do not specify shutdown order, the clusters will be stopped in the order returned from SDDC Manager API. For granular control, please use -vsanCluster parameter.
# Scripts for Shutdown and Startup of a Workload Domain
- **PowerManagement-ManagementDomain.ps1** - Shut down or start up all software components in the management
domain. The script does not support shutdown of vRealize Suite. Shut down the vRealize Suite components in your environment manually before running the script.

- **PowerManagement-WorkloadDomain.ps1** - Shut down or start up the management components for a VI
workload domain. The script does not support vSphere with Tanzu.

# Prerequisites
- Add forward and reverse DNS records for the client machine running the scripts must be added to the DNS server.
- Run the scripts on PowerShell 7.2.x or later.
- Run PowerShell and install the VMware.CloudFoundation.PowerManagement PowerShell
module together with module dependencies from the PowerShell Gallery by running the
following commands:  
    > `Install-Module -Name VMware.PowerCLI -MinimumVersion 12.7.0`  
    > `Install-Module -Name PowerVCF -MinimumVersion 2.2.0`  
    > `Install-Module -Name Posh-SSH -MinimumVersion 3.0.4`  
    > `Install-Module -Name VMware.CloudFoundation.PowerManagement`  
- Verify that SDDC Manager is running.
- Before you shut down the management domain, get the credentials for the management
domain hosts and vCenter Server from SDDC Manager and save them for troubleshooting or a
subsequent manual startup. Because SDDC Manager is down during each of these operations,
you must save the credentials in advance.
To get the credentials, log in to the SDDC Manager appliance by using a Secure Shell (SSH)
client as **vcf** and run the `lookup_passwords` command.
- On Windows 10, configure the PowerShell execution policy with the permissions required to
run the commands.  
a) Run the `Execute Get-ExecutionPolicy` command to get the active execution policy.  
b) If the `Execute Get-ExecutionPolicy` command returns `Restricted`, run the
`Set-ExecutionPolicy RemoteSigned` command.
- If the target system uses self-signed or untrusted certificates, configure PowerCLI to ignore them.
# How to use the sample scripts
1. Enable SSH on the ESXi hosts (Required for VMware Cloud Foundation before version 4.5.0) in the workload domain by using the SoS utility of the SDDC
Manager appliance.
    - Log in to the SDDC Manager appliance by using a Secure Shell (SSH) client as vcf.
    - Switch to the root user by running the su command and entering the root password.
    - Run this command:
         > `/opt/vmware/sddc-support/sos --enable-ssh-esxi --domain domain-name`
2. On the Windows machine that is allocated to run the scripts, start Windows PowerShell 7.x.
3. Locate the home directory of the VMware.CloudFoundation.PowerManagement module by running this
PowerShell command.
    > `(Get-Module -ListAvailable VMware.CloudFoundation.PowerManagement*).path`  

> For example, the full path to the module might be:
    `C:\Program Files\WindowsPowerShell\Modules\VMware.CloudFoundation.PowerManagement\1.0.0.1000\VMware.CloudFoundation.PowerManagement.psd1`.  
4. Go to the `SampleScripts` folder that is located in the same folder as the
`VMware.CloudFoundation.PowerManagement.psd1` file.
5. To shut down or start up a VI workload domain, perform these steps.  
    - Replace the values in the sample code with values from your environment and run the
commands in the PowerShell console.  
    > `$sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"`  
    > `$sddcManagerUser = "administrator@vsphere.local"`  
    > `$sddcManagerPass = "VMw@re1!"`  
    > `$sddcDomain = "sfo-w01"`  
    - Run the PowerManagement-WorkloadDomain.ps1 script.  
    > `PowerManagement-WorkloadDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $sddcDomain -shutdown -shutdownCustomerVm`  
    When you use the `-shutdownCustomerVm` parameter, the customer virtual machines are shut down as the first step of the shutdown process.

6. To shut down or start up the management domain, perform these steps.
    - Replace the values in the sample code with values from your environment and run the
commands in the PowerShell console.
    > `$sddcManagerFqdn = "sfo-vcf01.sfo.rainpole.io"`  
    > `$sddcManagerUser = "administrator@vsphere.local"`  
    > `$sddcManagerPass = "VMw@re1!"`  
    - Run the `PowerManagement-ManagementDomain.ps1` script.  
    > `PowerManagement-ManagementDomain.ps1 -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -shutdown`  
    > `PowerManagement-ManagementDomain.ps1 -startup`  
    During the shutdown operation, the script generates a `ManagementStartupInput.json` file
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
- ESXi hosts must have SSH service up, running and accessible from the machine running the scripts (Required for VMware Cloud Foundation before version 4.5.0).
- In case of a failure, run the script with the same parameters in order to overcome some errors.
- Identify the step that is causing the issue and continue the sequence following the manual guide in VMware Cloud Foundation documentation.
- During shutdown of the management domain, if SDDC Manager is already stopped, the only option is to continue by following the manual steps in the VMware Cloud Foundation documentation.

# Feedback
Please share with us your experience with using this Power Shell module. 
Use the "Send Feedback" form on the right in the <a href="https://docs.vmware.com/en/VMware-Cloud-Foundation/4.4/vcf-operations/GUID-65F5FE47-5831-4C72-B0DB-9D0C537446E2.html" target="_blank">Shutdown and Startup of VMware Cloud Foundation</a> documentation.