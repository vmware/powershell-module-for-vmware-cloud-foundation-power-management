    <#
        .SYNOPSIS
        Connects to the specified SDDC Manager and shutdown/startup a Tanzu Workload Domain

        .DESCRIPTION
        This script connects to the specified SDDC Manager and either shutdowns or startups a Tanzu Workload Domain

        .EXAMPLE
        PowerManagement-Tanzu.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
        Initiates a shutdown of the Tanzu Workload Domain 'sfo-w01'

        .EXAMPLE
        PowerManagement-Tanzu.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Startup
        Initiates the startup of the Tanzu Workload Domain 'sfo-w01'
    #>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""

# Check that the FQDN of the SDDC Manager is valid 
Try {
    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to connect to server: $server, check details and try again"
        Break
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Setup a log file and gather details from SDDC Manager
Try {
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

    Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $mgmtCluster = Get-VCFCluster | Where-Object { $_.id -eq ($managementDomain.clusters.id) }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
        #$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn

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

        # Gather ESXi Host Details for the Tanzu Domain
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


    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to connect to SDDC Manager $server" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        # Change the DRS Automation Level to Partially Automated for both the Management Domain and Tanzu Domain Clusters
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level PartiallyAutomated
        }

        #Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode 'disable'

        # Shut Down the vSphere with Tanzu Virtual Machines
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP

        # Check the health and sync status of the VSAN cluster
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            # Shutdown vCenter Server
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
        }

        $clusterPattern = "^SupervisorControlPlaneVM.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        }

        $clusterPattern = "^.*-tkc01-.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        }

        $clusterPattern = "^harbor.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        }

        #search for the edgenodes and shutdown
        foreach ($nsxtEdgeNode in $nsxtEdgeNodes) {
            $gethost = Get-VM | where-object Name -match $nsxtEdgeNode  | select VMHost
            Stop-CloudComponent -server $gethost.VMHost.Name -pattern $nsxtEdgeNode -user $esxiNode.username -pass $esxiNode.password -timeout 600
        }

        # Shutdown the NSX Manager Nodes
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        # Prepare the vSAN cluster for shutdown - Performed on a single host only
        Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"

        # Disable vSAN cluster member updates and place host in maintenance mode
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($powerState -eq "Startup") {

        # Take hosts out of maintenance mode
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
        }

        # Prepare the vSAN cluster for startup - Performed on a single host only
        Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"
        
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
        }

        # Startup the Tanzu Workload Domain vCenter Server
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($vcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)

        # Check the health and sync status of the VSAN cluster
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type ERROR -Message "The VC is still not up" -Colour RED
            Exit
        }

        $HAStatus = Get-Cluster -Name $cluster.name | Select HAEnabled
        if ($HAStatus)  {
             Write-LogMessage -Type INFO -Message "The HA is enabled on the VSAN cluster, restarting the same"
             Set-Cluster -Name $cluster.name -HAEnabled:$false
             if (-Not get-cluster -Name $cluster.name | select HAEnabled) {
                 Write-LogMessage -Type INFO -Message "The HA is disabled"
             }
             Start-Sleep -s 5
             Set-Cluster -Name $cluster.name -HAEnabled:$true
             if (get-cluster -Name $cluster.name | select HAEnabled) {
                 Write-LogMessage -Type INFO -Message "The HA is enabled. Vsphere HA is restarted"
             }
        }
        Get-VAMIServiceStatus $vcServer.fqdn -user $vcUser -pass $vcPass -service 'wcp' -check_status 'STARTED'

        #Startup vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode 'enable'

        # Startup the NSX Manager Nodes in the Management Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        # Startup the NSX Edge Nodes in the Tanzu Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
        }

        # Change the DRS Automation Level to Fully Automated for both the Management Domain and Tanzu Domain Clusters
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level FullyAutomated
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}