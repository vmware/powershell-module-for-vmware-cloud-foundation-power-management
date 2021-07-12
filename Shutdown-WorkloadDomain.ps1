Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain
    )

$moduleLoaded = Get-Module | Where-Object {$_.Name -eq "VMware.PowerManagement"}
if ($moduleLoaded) {
    Remove-module VMware.PowerManagement
}
Import-Module .\VMware.PowerManagement.psm1

#Clear-Host
Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name

$StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

# Gather Details from SDDC Manager
$managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
$workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
$cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn
$vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
$vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password
$vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
$mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})

$nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $workloadDomain.nsxtCluster.id}
$nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
$nsxtNodes = @()
foreach ($node in $nsxtNodesfqdn) {
    [Array]$nsxtNodes += $node.Split(".")[0]
}

$nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $workloadDomain.nsxtCluster.id})
$nsxtEdgeNodesfqdn = $nsxtEdgeCluster.edgeNodes.hostname
$nsxtEdgeNodes = @()
foreach ($node in $nsxtEdgeNodesfqdn) {
    [Array]$nsxtEdgeNodes += $node.Split(".")[0]
}
$nsxtEdgeNodes = "ldn-w01-en01", "ldn-w01-en02"

$esxiUser = "root"
$esxiPass = "VMw@re1!"
$clusterPattern = "ldn*"


# Shutdown the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
# Shutdown the NSX-T Manager Nodes in the Management Domain
Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600


# Shut Down the vCenter Server Instance in the Virtual Infrastructure Workload Domain
Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
Test-ResyncingObject -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
#ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-w01-vc01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150


#Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
#passes but gets turned on again if VC is on but when VC is off, able to shutdown. hence added a sleep of 10 seconds before first check
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000

#Shut Down vSAN and the ESXi Hosts in the Virtual Infrastructure Workload Domain -- could not be automated
#passed
#Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
#Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare" -timeout 600
#Set-MaintainanceMode -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150


##################################passed
#Execute-OnEsx -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
#Set-MaintainanceMode -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
#ShutdownStartup-ComponentOnHost -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -timeout 150


##################################passed
#Execute-OnEsx -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
#Set-MaintainanceMode -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150

##################################passed
#Execute-OnEsx -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
#Set-MaintainanceMode -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
#ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150



# Testing Get-VMRunningStatus for different scenarios
#Get-VMRunningStatus -server $esxiHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern
#Get-VMRunningStatus -server $esxiHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern -status NotRunning
#Get-VMRunningStatus -server $vcServer -user $vcUser -pass $vcPass -pattern $clusterPattern
#foreach ($member in $members) {
#    Get-VSANClusterMember -server $member -user $esxiUser -pass $esxiPass -members $members
#}
