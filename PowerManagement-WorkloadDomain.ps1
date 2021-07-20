Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

$moduleLoaded = Get-Module | Where-Object {$_.Name -eq "VMware.PowerManagement"}
if ($moduleLoaded) {
    Remove-module VMware.PowerManagement
}
Import-Module .\VMware.PowerManagement.psm1

#Clear-Host

Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
$StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
if ($accessToken) {
    Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
    # Gather Details from SDDC Manager
    $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
    #$esxiManagementDomain = (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn
    $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
    #$esxiWorkloadDomain = (Get-VCFHost | Where-Object {$_.domain.id -eq $workloadDomain.id}).fqdn
    $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
    $members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn

    # Gather vCenter Server Details and Credentials
    $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
    $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})
    $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
    $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

    # Gather ESXi Host Details for the Managment Domain
    $esxiManagementDomain = @()
    foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
    {
        $esxDetails = New-Object -TypeName PSCustomObject
        $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
        $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
        $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password 
        $esxiManagementDomain += $esxDetails
    } 

    # Gather ESXi Host Details for the VI Workload Domain
    $esxiWorkloadDomain = @()
    foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $workloadDomain.id}).fqdn)
    {
        $esxDetails = New-Object -TypeName PSCustomObject
        $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
        $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
        $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password 
        $esxiWorkloadDomain += $esxDetails
    } 

    # Gather NSX Manager Cluster Details
    $nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $workloadDomain.nsxtCluster.id}
    $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
    $nsxtNodes = @()
    foreach ($node in $nsxtNodesfqdn) {
        [Array]$nsxtNodes += $node.Split(".")[0]
    }

    # Gather NSX Edge Node Details
    $nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $workloadDomain.nsxtCluster.id})
    $nsxtEdgeNodesfqdn = $nsxtEdgeCluster.edgeNodes.hostname
    $nsxtEdgeNodes = @()
    foreach ($node in $nsxtEdgeNodesfqdn) {
        [Array]$nsxtEdgeNodes += $node.Split(".")[0]
    }
    $nsxtEdgeNodes = "ldn-w01-en01", "ldn-w01-en02"

    $clusterPattern = "^vCLS.*"
}
else {
    Write-LogMessage -Type ERROR -Message "Unable to connect to SDDC Manager $server" -Colour Red
    Exit
}

if ($powerState -eq "Shutdown") {
    # Shutdown the NSX Edge Nodes in the Virtual Infrastructure Workload Domain
    $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
    if ($checkServer -eq "True") {
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
    }
    else {
        Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping shutdown of $nsxtEdgeNodes" -Colour Cyan
    }
    # Shutdown the NSX Manager Nodes in the Management Domain
    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

    # Check the health and sync status of the VSAN cluster
    $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
    if ($checkServer -eq "True") {
        Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        Test-ResyncingObject -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
    }
    else {
        Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
    }

    # Shutdown the Virtual Infrastructure Workload Domain vCenter Server
    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600

    # Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
    foreach ($esxiNode in $esxiWorkloadDomain) {
        Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
    }

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
}

if ($powerState -eq "Startup") {
    # Startup the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
    foreach ($esxiNode in $esxiWorkloadDomain) {
        Start-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000 
    }

    # Startup the Virtual Infrastructure Workload Domain vCenter Server
    Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
    Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($vcServer.fqdn) (may take some time)"
    Do {}Until (Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)

    # Startup the NSX Manager Nodes in the Management Domain
    Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

    # Startup the NSX Edge Nodes in the Virtual Infrastructure Workload Domain
    $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
    if ($checkServer -eq "True") {
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
    }
    else {
        Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) is not power on, skipping startup of $nsxtEdgeNodes" -Colour Cyan
        Exit
    }  
}


