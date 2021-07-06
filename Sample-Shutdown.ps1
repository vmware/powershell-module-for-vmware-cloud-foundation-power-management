$moduleLoaded = Get-Module | Where-Object {$_.Name -eq "VMware.PowerManagement"}
if ($moduleLoaded) {
    Remove-module VMware.PowerManagement
}
Import-Module .\VMware.PowerManagement.psm1

Start-SetupLogFile -Path $PSScriptRoot -ScriptName $Script

###Variables section####
$regional_mgmt_vc = "sfo-m01-vc01"
$regional_workload_vc = "sfo-w01-vc01"
$regional_mgmt_vc_fqdn = "sfo-m01-vc01.sfo.rainpole.io"
$regional_mgmt_vc_user = "administrator@vsphere.local"
$regional_mgmt_vc_pass = "VMw@re123!"
$regional_workload_vc_fqdn = "sfo-w01-vc01.sfo.rainpole.io"
$regional_workload_vc_user = "root"
$regional_workload_vc_pass = "VMw@re123!"
$nsxt_edge_node1 = "sfo-w01-en01"
$nsxt_edge_node2 = "sfo-w01-en02"
$nsxt_mgr_nodea = "sfo-w01-nsx01a"
$nsxt_mgr_nodeb = "sfo-w01-nsx01b"
$nsxt_mgr_nodec = "sfo-w01-nsx01c"



#### Edge 

#Get Virtual Machine to Host Mapping in the Virtual Infrastructure Workload Domain
#It is already in powershell

#Shut Down the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
#passing
ShutdownStartup-SDDCComponent -server sfo-w01-vc01.sfo.rainpole.io -nodes sfo-w01-en01, sfo-w01-en02 -user administrator@vsphere.local -pass VMw@re1! -task Shutdown -timeout 600
