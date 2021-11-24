<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         Cloud Infrastructure Business Group (CIBG)
    .Organization:  VMware
    .Version:       1.0 (Build 001)
    .Date:          2021-11-23
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2021-11-03) - Initial script creation

    ===============================================================================================================

    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup the vRealize Suite components

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups the vRealize Suite components

    .EXAMPLE
    PowerManagement-vRealizeSuite.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-m01 -powerState Shutdown
    Initiaites a shutdown of the the vRealize Suite components

    .EXAMPLE
    PowerManagement-vRealizeSuite.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-m01 -powerState Startup
    Initiaites the startup of the the vRealize Suite components
#>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        #[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
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
        #$managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        #$mgmtCluster = Get-VCFCluster | Where-Object { $_.id -eq ($managementDomain.clusters.id) }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        #$cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
        #$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.type -eq "MANAGEMENT"})
        #$mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

        # Gather ESXi Host Details for the Managment Domain
        #$esxiManagementDomain = @()
        #foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
        #{
        #    $esxDetails = New-Object -TypeName PSCustomObject
        #    $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
        #    $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
        #    $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password 
        #    $esxiManagementDomain += $esxDetails
        #} 

        # Gather ESXi Host Details for the VI Workload Domain
        #$esxiWorkloadDomain = @()
        #foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $workloadDomain.id}).fqdn)
        #{
        #    $esxDetails = New-Object -TypeName PSCustomObject
        #    $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
        #    $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
        #    $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password 
        #    $esxiWorkloadDomain += $esxDetails
        #} 

        # Gather NSX Manager Cluster Details
        #$nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $workloadDomain.nsxtCluster.id}
        #$nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        #$nsxtNodes = @()
        #foreach ($node in $nsxtNodesfqdn) {
        #    [Array]$nsxtNodes += $node.Split(".")[0]
        #}

        # Gather NSX Edge Node Details
        #$nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $workloadDomain.nsxtCluster.id})
        #$nsxtEdgeNodesfqdn = $nsxtEdgeCluster.edgeNodes.hostname
        #$nsxtEdgeNodes = @()
        #foreach ($node in $nsxtEdgeNodesfqdn) {
        #    [Array]$nsxtEdgeNodes += $node.Split(".")[0]
        #}

        # Gather vRealize Suite Details
        $GLobal:vrslcm = New-Object -TypeName PSCustomObject
        $vrslcm | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRSLCM).status
        $vrslcm | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRSLCM).fqdn
        $vrslcm | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).password
        $vrslcm | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name rootPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).password

        $Global:wsa = New-Object -TypeName PSCustomObject
        $wsa | Add-Member -Type NoteProperty -Name status -Value (Get-VCFWSA).elements.status
        $wsa | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFWSA).elements.loadBalancerFqdn
        $wsa | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).username
        $wsa | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).password
        $wsaNodes = @()
        foreach ($node in (Get-VCFWSA).elements.nodes.fqdn | Sort-Object) {
            [Array]$wsaNodes += $node.Split(".")[0]
        }

        $Global:vrops = New-Object -TypeName PSCustomObject
        $vrops | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvROPS).elements.status
        $vrops | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvROPS).elements.loadBalancerFqdn
        $vrops | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).username
        $vrops | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).password
        $vrops | Add-Member -Type NoteProperty -Name master -Value  ((Get-VCFvROPs).elements.nodes | Where-Object {$_.type -eq "MASTER"}).fqdn
        $vropsNodes = @()
        foreach ($node in (Get-VCFvROPS).elements.nodes.fqdn | Sort-Object) {
            [Array]$vropsNodes += $node.Split(".")[0]
        }
        $Global:vropsCollectorNodes = @()
        foreach ($node in (Get-vROPSClusterDetail -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword | Where-Object {$_.role -eq "REMOTE_COLLECTOR"} | Select-Object name)) {
            [Array]$vropsCollectorNodes += $node
        }

        $Global:vra = New-Object -TypeName PSCustomObject
        $vra | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRA).elements.status
        $vra | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRA).elements.loadBalancerFqdn
        $vraNodes = @()
        foreach ($node in (Get-VCFvRA).elements.nodes.fqdn | Sort-Object) {
            [Array]$vraNodes += $node.Split(".")[0]
        }

        $Global:vrli = New-Object -TypeName PSCustomObject
        $vrli | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRLI).elements.status
        $vrli | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRLI).elements.loadBalancerFqdn
        $vrli | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).username
        $vrli | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).password
        $vrliNodes = @()
        foreach ($node in (Get-VCFvRLI).elements.nodes.fqdn | Sort-Object) {
            [Array]$vrliNodes += $node.Split(".")[0]
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
        # Change the DRS Automation Level to Partially Automated for both the Management Domain and VI Workload Domain Clusters
        #$checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        #if ($checkServer -eq "True") {
        #    Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level PartiallyAutomated
        #}

        # Shutdown vRealize Suite
        if ($($WorkloadDomain.type) -eq "MANAGEMENT") {
            if ($($vra.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VRA -mode power-off -timeout 1800
                pause
            }
            if ($($vrops.status -eq "ACTIVE")) {
                Set-vROPSClusterState -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword -mode OFFLINE
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsCollectorNodes -timeout 600
                pause
            }
            if ($($wsa.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VIDM -mode power-off -timeout 1800
                pause
            }
            if ($($vrslcm.status -eq "ACTIVE")) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm.fqdn.Split(".")[0] -timeout 600
                pause
            }
            if ($($vrli.status -eq "ACTIVE")) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
                pause
            }
        }

        # Shut Down the vSphere with Tanzu Virtual Machines
        #Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP
        #$clusterPattern = "^SupervisorControlPlaneVM.*"
        #foreach ($esxiNode in $esxiWorkloadDomain) {
        #    Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        #}

        #$clusterPattern = "^harbor.*"
        #foreach ($esxiNode in $esxiWorkloadDomain) {
        #    Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        #}

        # Shutdown the NSX Edge Nodes
        #$checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        #if ($checkServer -eq "True") {
        #    if ($nsxtEdgeNodes) {
        #        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        #    }
        #    else {
        #        Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping shutdown" -Colour Cyan
        #    }
        #}
        #else {
        #    Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping shutdown of $nsxtEdgeNodes" -Colour Cyan
        #}
        # Shutdown the NSX Manager Nodes
        #Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        # Check the health and sync status of the VSAN cluster
        #$checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        #if ($checkServer -eq "True") {
        #    Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        #    Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        #}
        #else {
        #    Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
        #}

        # Shutdown vCenter Server
        #Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600

        # Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        #foreach ($esxiNode in $esxiWorkloadDomain) {
        #    $clusterPattern = "^vCLS.*"
        #    Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000
        #}

        # Prepare the vSAN cluster for shutdown - Performed on a single host only
        #Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"

        # Disable vSAN cluster member updates and place host in maintenance mode
        #foreach ($esxiNode in $esxiWorkloadDomain) {
        #    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
        #}
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

        # Startup the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        $clusterPattern = "^vCLS.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Start-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1000 
        }

        # Startup the Virtual Infrastructure Workload Domain vCenter Server
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($vcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)

        # Startup the NSX Manager Nodes in the Management Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        # Startup the NSX Edge Nodes in the Virtual Infrastructure Workload Domain
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            if ($nsxtEdgeNodes) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
            }
            else {
                Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
            }
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) is not power on, skipping startup of $nsxtEdgeNodes" -Colour Cyan
            Exit
        }

        # Startup vRealize Suite
        if ($($WorkloadDomain.type) -eq "MANAGEMENT") {
            if ($($vra.status -eq "ACTIVE")) {
    
            }
            if ($($vrops.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
                Set-vROPSClusterState -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword -mode ONLINE
            }
            if ($($wsa.status -eq "ACTIVE")) {
    
            }
            if ($($vrslcm.status -eq "ACTIVE")) {
    
            }
            if ($($vrli.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
            }
        }

        # Change the DRS Automation Level to Fully Automated for both the Management Domain and VI Workload Domain Clusters
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level FullyAutomated
        }

        if (!$($WorkloadDomain.type) -eq "MANAGEMENT") {
            $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
            if ($checkServer -eq "True") {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
            }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}