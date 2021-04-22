<#
#Testcse1
###Start vSAN and the ESXi Hosts in the Virtual Infrastructure Workload Domain

##using ILO ip 10.144.40.44 and powered on manually, need to check what is the powershell module for dell idrac
Set-MaintainanceMode -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.43 and powered on manually, need to check what is the powershell module for dell idrac
Set-MaintainanceMode -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
Set-MaintainanceMode -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"

##using ILO ip 10.144.40.42 and powered on manually, need to check what is the powershell module for dell idrac
Set-MaintainanceMode -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e false"


##################################passed only on  first host
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

######
Verify-VSANClusterMembers -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io"
Verify-VSANClusterMembers -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -members "sfo01-w01-esx01.sfo.rainpole.io"

#####
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"


#Testcse2
#Start the vSphere Cluster Services in the Virtual Infrastructure Workload Domain
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 500 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000 -task "Startup"



#Testcase3
#Start vCenter Server in the Virtual Infrastructure Workload Domain    --  Am not able to to VSAN health check
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-w01-vc01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"
Get-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re123! -service 'wcp' -check_status 'STARTED'




#Testcase4
#Start the NSX-T Manager Virtual Machines in the Virtual Infrastructure Workload Domain
#ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-w01-nsx01a, sfo-w01-nsx01b, sfo-w01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
#login to local ip of nsxt manager to see if it is reachable
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
Connect-NSXTLocal -url "https://sfo-w01-nsx01.sfo.rainpole.io/login.jsp?local=true"

################################There is something pending, like NSXT local system->cluster->applicance status ---- need to check same available


#Testcase5
#Start the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
ShutdownStartup-SDDCComponent -server sfo-w01-vc01.sfo.rainpole.io -nodes sfo-w01-en01, sfo-w01-en02 -user administrator@vsphere.local -pass VMw@re123!  -task "Startup" -timeout 600

After the vSphere with Tanzu services and the NSX-T Data Center infrastructure are operational, the following virtual machines will automatically start:

Supervisor Control Plane virtual machines

Tanzu Kubernetes Cluster control plane virtual machines

Tanzu Kubernetes Cluster worker virtual machines

Harbor registry virtual machines

#>

