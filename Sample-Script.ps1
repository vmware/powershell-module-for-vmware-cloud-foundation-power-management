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

$managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
$workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
$cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn
$vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
$mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})

$nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $workloadDomain.nsxtCluster.id}
$nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
$nsxtNodes = @()
foreach ($node in $nsxtNodesfqdn) {
    [Array]$nsxtNodes += $node.Split(".")[0]
}


$nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $workloadDomain.nsxtCluster.id})

$vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
$vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

$edgeNodes = "ldn-w01-en01", "ldn-w01-en02"

$esxiUser = "root"
$esxiPass = "VMw@re1!"
$clusterPattern = "ldn*"


# Shutdown the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $edgeNodes -timeout 600
Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

# Testing Get-VMRunningStatus for different scenarios
#Get-VMRunningStatus -server $esxiHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern
#Get-VMRunningStatus -server $esxiHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern -status NotRunning
#Get-VMRunningStatus -server $vcServer -user $vcUser -pass $vcPass -pattern $clusterPattern
foreach ($member in $members) {
    Get-VSANClusterMember -server $member -user $esxiUser -pass $esxiPass -members $members
}
