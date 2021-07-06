Remove-module VMware.PowerManagement
Import-Module VMware.PowerManagement


$ErrorActionPreference = 'STOP'

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


write-output "Testcase1: Start the ESXi host using ILO ip"
##using ILO ip 10.144.40.44 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx1_ilo_ip  -ilo_user $esx1_ilo_user  -ilo_pass $esx1_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.43 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx2_ilo_ip  -ilo_user $esx2_ilo_user  -ilo_pass $esx2_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx3_ilo_ip  -ilo_user $esx3_ilo_user  -ilo_pass $esx3_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-m01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
PowerOn-EsxiUsingILO -ilo_ip $esx4_ilo_ip  -ilo_user $esx4_ilo_user  -ilo_pass $esx4_ilo_pass
Start-Sleep -Seconds 300
Set-MaintainanceMode -server "sfo01-m01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"


##################################passed only on  first host
Execute-OnEsx -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

######
Verify-VSANClusterMembers -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-m01-esx01.sfo.rainpole.io", "sfo01-m01-esx02.sfo.rainpole.io", "sfo01-m01-esx03.sfo.rainpole.io", "sfo01-m01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-m01-esx01.sfo.rainpole.io", "sfo01-m01-esx02.sfo.rainpole.io", "sfo01-m01-esx03.sfo.rainpole.io", "sfo01-m01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-m01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-m01-esx01.sfo.rainpole.io", "sfo01-m01-esx02.sfo.rainpole.io", "sfo01-m01-esx03.sfo.rainpole.io", "sfo01-m01-esx04.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-m01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-m01-esx01.sfo.rainpole.io", "sfo01-m01-esx02.sfo.rainpole.io", "sfo01-m01-esx03.sfo.rainpole.io", "sfo01-m01-esx04.sfo.rainpole.io"

#####
Execute-OnEsx -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-m01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-m01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"


#Start the vSphere Cluster Services in the Management Domain
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"

#Start the vCenter Server Instance in the Management Domain
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx01.sfo.rainpole.io -pattern "sfo-m01-vc01" -user root -pass VMw@re123! -timeout 500 -task "Startup"
Start-Sleep -Seconds 300
Test-VsanHealth -cluster sfo-m01-cl01 -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re123!
Test-ResyncingObjects -cluster sfo-m01-cl01 -server "sfo-m01-vc01.sfo.rainpole.io" -user "administrator@vsphere.local" -pass "VMw@re123!"



#Set DRS Automation Level of the Management Domain to Automatic
Set-DrsAutomationLevel  -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re123! -level 'FullyAutomated' -cluster 'sfo-m01-cl01'

#Start the SDDC Manager Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-vcf01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"

#Start the NSX-T Manager Virtual Machines in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-nsx01a, sfo-m01-nsx01b, sfo-m01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
#login to local ip of nsxt manager to see if it is reachable
<#add-type @"
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

Connect-NSXTLocal -url "https://sfo-m01-nsx01.sfo.rainpole.io/login.jsp?local=true"
Get-NSXTMgrClusterStatus -server 'sfo-m01-nsx01.sfo.rainpole.io' -user 'admin' -pass 'VMw@re123!VMw@re123'


#Start the NSX-T Edge Nodes in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-en01, sfo-m01-en02 -user administrator@vsphere.local -pass VMw@re123!  -task "Startup" -timeout 600

#Start the Region-Specific Workspace ONE Access Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-wsa01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"

#Start the vRealize Log Insight Virtual Machines in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-vrli01a, sfo-vrli01b, sfo-vrli01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"

#Start the vRealize Suite Lifecycle Manager Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node xreg-vrslcm01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"

#Start the Cross-Region Workspace ONE Access Virtual Machines in the Management Domain
ShutdownStartupProduct-ViaVRSLCM -server 'xreg-vrslcm01.rainpole.io' -product 'vidm' -mode "power-on" -user 'vcfadmin@local' -pass 'VMw@re123!' -env "global" -timeout 1800
Execute-OnEsx -server "xreg-wsa01a.rainpole.io" -user 'root' -pass 'VMw@re123!' -cmd 'echo "Domain rainpole.io" >> /etc/resolv.conf;  echo "search rainpole.io sfo.rainpole.io" >> /etc/resolv.conf' -timeout 600
Execute-OnEsx -server "xreg-wsa01b.rainpole.io" -user 'root' -pass 'VMw@re123!' -cmd 'echo "Domain rainpole.io" >> /etc/resolv.conf;  echo "search rainpole.io sfo.rainpole.io" >> /etc/resolv.conf' -timeout 600
Execute-OnEsx -server "xreg-wsa01c.rainpole.io" -user 'root' -pass 'VMw@re123!' -cmd 'echo "Domain rainpole.io" >> /etc/resolv.conf;  echo "search rainpole.io sfo.rainpole.io" >> /etc/resolv.conf' -timeout 600
ShutdownStartupProduct-ViaVRSLCM -server 'xreg-vrslcm01.rainpole.io' -product 'vidm' -mode "health-check" -user 'vcfadmin@local' -pass 'VMw@re123!' -env "global"  -timeout 300

#Start the vRealize Operations Manager Virtual Machines in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes xreg-vrops01a, xreg-vrops01b, xreg-vrops01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600 -task "Startup"
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vropsc01a, sfo-vropsc01b -user administrator@vsphere.local -pass VMw@re123! -timeout 600 -task "Startup"
SetClusterState-VROPS -server 'xreg-vrops01a.rainpole.io' -mode 'ONLINE' -user 'admin' -pass 'VMw@re123!'

#Start the vRealize Automation Virtual Machines in the Management Domain
ShutdownStartupProduct-ViaVRSLCM -server 'xreg-vrslcm01.rainpole.io' -product 'VRA' -mode "power-on" -user 'vcfadmin@local' -pass 'VMw@re123!' -env "Cross" -timeout 1800
