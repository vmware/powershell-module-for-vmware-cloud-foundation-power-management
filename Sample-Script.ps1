$moduleLoaded = Get-Module | Where-Object {$_.Name -eq "VMware.PowerManagement"}
if ($moduleLoaded) {
    Remove-module VMware.PowerManagement
}
Import-Module .\VMware.PowerManagement.psm1

#Clear-Host
Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name


$vcServer = "ldn-w01-vc01.ldn.cloudy.io"
$vcUser = "administrator@vsphere.local"
$vcPass = "VMw@re1!"

$edgeNodes = "ldn-w01-en01", "ldn-w01-en02"

$esxHost = "ldn01-w01-esx04.ldn.cloudy.io"
$esxiUser = "root"
$esxiPass = "VMw@re1!"
$clusterPattern = "ldn*"

#### Edge

# Shutdown the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
Stop-CloudComponent -server $vcServer -user $vcUser -pass $vcPass -nodes $edgeNodes -timeout 600
# Startup the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
Start-CloudComponent -server $vcServer -user $vcUser -pass $vcPass -nodes $edgeNodes -timeout 600

# Testing Get-VMRunningStatus for different scenarios
Get-VMRunningStatus -server $esxHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern
Get-VMRunningStatus -server $esxHost -user $esxiUser -pass $esxiPass -pattern $clusterPattern -status NotRunning
Get-VMRunningStatus -server $vcServer -user $vcUser -pass $vcPass -pattern $clusterPattern
