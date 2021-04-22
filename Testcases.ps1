Remove-module VMware.StartupShutdown
Import-Module VMware.StartupShutdown


####Shutdown VI domain

#Get Virtual Machine to Host Mapping in the Virtual Infrastructure Workload Domain
#It is already in powershell

#Shut Down the NSX-T Edge Nodes in the Virtual Infrastructure Workload Domain
#passing
ShutdownStartup-SDDCComponent -server sfo-w01-vc01.sfo.rainpole.io -nodes sfo-w01-en01, sfo-w01-en02 -user administrator@vsphere.local -pass VMw@re123!  -timeout 600

#Shut Down the NSX-T Managers in the Virtual Infrastructure Workload Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-w01-nsx01a, sfo-w01-nsx01b, sfo-w01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600

#Shut Down the vCenter Server Instance in the Virtual Infrastructure Workload Domain
#passed -- But unable to do skyline health check
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-w01-vc01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150

#Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
#passes but gets turned on again if VC is on but when VC is off, able to shutdown. hence added a sleep of 10 seconds before first check
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000

#Shut Down vSAN and the ESXi Hosts in the Virtual Infrastructure Workload Domain -- could not be automated
#passed
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare" -timeout 600
Set-MaintainanceMode -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150


##################################passed
Execute-OnEsx -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -timeout 150


##################################passed
Execute-OnEsx -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-w01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx03.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150

##################################passed
Execute-OnEsx -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-w01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-w01-esx04.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150


