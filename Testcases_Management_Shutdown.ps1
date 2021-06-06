Remove-module VMware.StartupShutdown
Import-Module VMware.StartupShutdown

#Shut Down the vRealize Automation Virtual Machines in the Management Domain
ShutdownStartupProduct-ViaVRSLCM -host 'xreg-vrslcm01.rainpole.io' -product 'VRA' 


#Shut Down the vRealize Operations Manager Virtual Machines in the Management Domain
SetClusterState-VROPS -host 'xreg-vrops01.rainpole.io' -mode 'OFFLINE'
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes xreg-vrops01a, xreg-vrops01b, xreg-vrops01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vropsc01a, sfo-vropsc01b -user administrator@vsphere.local -pass VMw@re123! -timeout 600

#Shut Down the Cross-Region Workspace ONE Access Virtual Machines in the Management Domain
ShutdownStartupXVIDM-ViaVRSLCM -host 'xreg-vrslcm01.rainpole.io' -product 'vidm' -mode "power-off"


#Shut Down the vRealize Suite Lifecycle Manager Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes xreg-vrslcm01 -user administrator@vsphere.local -pass VMw@re123! -timeout 600

#Shut Down the vRealize Log Insight Virtual Machines in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vrli01a, sfo-vrli01b, sfo-vrli01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600

#Shut Down the Region-Specific Workspace ONE Access Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-wsa01 -user administrator@vsphere.local -pass VMw@re123! -timeout 600


#Shut Down the NSX-T Edge Nodes in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-en01, sfo-m01-en02 -user administrator@vsphere.local -pass VMw@re123! -timeout 600



#Shut Down the NSX-T Managers in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-nsx01a, sfo-m01-nsx01b, sfo-m01-nsx01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600



#Shut Down the SDDC Manager Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vcf01 -user administrator@vsphere.local -pass VMw@re123! -timeout 600

#Set DRS Automation Level of the Management Domain to Manual
Set-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re123! -cluster 'sfo-m01-cl01' -level 'Manual'



#Shut Down the vCenter Server Instance in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-vc01 -user administrator@vsphere.local -pass VMw@re123! -timeout 600
##I shall not be able to verify if VC VM is shutdown, because mgmt vd itself is down. I might need to do ping check

#Shut Down the vSphere Cluster Services Virtual Machines in the Management Domain
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx01.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx02.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx03.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx04.sfo.rainpole.io -pattern "^vCLS.*" -user root -pass VMw@re123! -timeout 1000

#Shut Down vSAN and the ESXi Hosts in the Management Domain
Execute-OnEsx -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Execute-OnEsx -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare" -timeout 600
Set-MaintainanceMode -server "sfo01-m01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx01.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150


##################################passed
Execute-OnEsx -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server "sfo01-m01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -timeout 150


##################################passed
Execute-OnEsx -server "sfo01-m01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-m01-esx03.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx03.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150

##################################passed
Execute-OnEsx -server "sfo01-m01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
Set-MaintainanceMode -server "sfo01-m01-esx04.sfo.rainpole.io" -user "root" -pass "VMw@re123!" -cmd "esxcli system maintenanceMode set -e true -m noAction"
ShutdownStartup-ComponentOnHost -server sfo01-m01-esx04.sfo.rainpole.io -user root -pass VMw@re123! -timeout 150
