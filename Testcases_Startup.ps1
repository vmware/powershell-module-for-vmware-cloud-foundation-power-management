<#
#Testcse1
###Start vSAN and the ESXi Hosts in the Virtual Infrastructure Workload Domain
### I have installed racadm module to get CLI equivalent of IDRAC console.
#Passed --- PS C:\users\Administrator\shutdownandstartup> cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r 10.144.40.30 -u vmware -p 'ca$hc0w'  --nocertwarn getsysinfo

# Need to Test: PS C:\users\Administrator\shutdownandstartup> cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r 10.144.40.30 -u vmware -p 'ca$hc0w'  --nocertwarn serveraction powerup
#PS C:\users\Administrator\shutdownandstartup> cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r 10.144.40.39 -u vmware -p 'ca$hc0w'  --nocertwarn serveraction powerup
#Server is already powered ON.
#PS C:\users\Administrator\shutdownandstartup> cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r 10.144.40.39 -u vmware -p 'ca$hc0w'  --nocertwarn serveraction powerdown
#Server power operation successful

#PS C:\users\Administrator\shutdownandstartup> cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r 10.144.40.39 -u vmware -p 'ca$hc0w'  --nocertwarn serveraction powerdown
#Server is already powered OFF.\
#>

Remove-module VMware.StartupShutdown
Import-Module VMware.StartupShutdown


$esx1_ilo_ip = "10.144.40.143"
$esx1_ilo_user = "vmware" 
$esx1_ilo_pass = 'ca$hc0w'
$esx2_ilo_ip = "10.144.40.144" #<<change>>
$esx2_ilo_user = "vmware" 
$esx2_ilo_pass = 'ca$hc0w'
$esx3_ilo_ip = "10.144.40.145" #<<change>>
$esx3_ilo_user = "vmware" 
$esx3_ilo_pass = 'ca$hc0w'
$esx4_ilo_ip = "10.144.40.146" #<<change>>
$esx4_ilo_user = "vmware" 
$esx4_ilo_pass = 'ca$hc0w'



##using ILO ip 10.144.40.44 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx1_ilo_ip  -ilo_user $esx1_ilo_user  -ilo_pass $esx1_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.43 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx2_ilo_ip  -ilo_user $esx2_ilo_user  -ilo_pass $esx2_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx3_ilo_ip  -ilo_user $esx3_ilo_user  -ilo_pass $esx3_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx4_ilo_ip  -ilo_user $esx4_ilo_user  -ilo_pass $esx4_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"


##################################passed only on  first host
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

######
Verify-VSANClusterMembers -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io", "sfo01-w01-esx02.sfo.rainpole.io", "sfo01-w01-esx03.sfo.rainpole.io", "sfo01-w01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io", "sfo01-w01-esx02.sfo.rainpole.io", "sfo01-w01-esx03.sfo.rainpole.io", "sfo01-w01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io", "sfo01-w01-esx02.sfo.rainpole.io", "sfo01-w01-esx03.sfo.rainpole.io", "sfo01-w01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io", "sfo01-w01-esx02.sfo.rainpole.io", "sfo01-w01-esx03.sfo.rainpole.io", "sfo01-w01-esx04.sfo.rainpole.io"

#####
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"


#Testcse2
#Start the vSphere Cluster Services in the Virtual Infrastructure Workload Domain
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"



#Testcase3
#Start vCenter Server in the Virtual Infrastructure Workload Domain    --  Am not able to to VSAN health check
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-w01-vc01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
Start-Sleep -Seconds 300
Test-VsanHealth -cluster sfo-w01-cl01 -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re123!
Test-ResyncingObjects -cluster sfo-w01-cl01 -server "sfo-w01-vc01.sfo.rainpole.io" -user "administrator@vsphere.local" -pass "VMw@re123!"



#Testcase4
#Start the NSX-T Manager Virtual Machines in the Virtual Infrastructure Workload Domain
#ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-w01-nsx01a, sfo-w01-nsx01b, sfo-w01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
#login to local ip of nsxt manager to see if it is reachable
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-w01-nsx01a, sfo-w01-nsx01b, sfo-w01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
Start-Sleep -Seconds 120
#login to local ip of nsxt manager to see if it is reachable
<#
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#>
Connect-NSXTLocal -url "https://sfo-w01-nsx01.sfo.rainpole.io/login.jsp?local=true"
Get-NSXTMgrClusterStatus -server sfo-w01-nsx01.sfo.rainpole.io -user admin -pass VMw@re123!VMw@re123


#Testcase5
#Start the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
ShutdownStartup-SDDCComponent -server sfo-w01-vc01.sfo.rainpole.io -nodes sfo-w01-en01, sfo-w01-en02 -user administrator@vsphere.local -pass VMw@re123!  -task "Startup" -timeout 600

