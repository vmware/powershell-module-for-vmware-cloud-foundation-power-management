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

    - 1.0.001   (Gary Blake / 2021-11-23) - Initial script creation

    ===============================================================================================================
    
    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup a VI Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Virual Infrastructure Workload Domain

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
    Initiaites a shutdown of the Virual Infrastructure Workload Domain 'sfo-w01'

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Startup
    Initiaites the startup of the Virual Infrastructure Workload Domain 'sfo-w01'
#>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$force,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""
$str1 = "$PSCommandPath -server $server -user $user -pass $pass -powerState $powerState -sddcDomain $sddcDomain"
if ($force) {$str1 = $str1 + " -force $force"}
Write-LogMessage -Message "The execution command is:  $str1" -colour "Yellow"

if (-Not (Get-InstalledModule -Name Posh-SSH -MinimumVersion 2.3.0)) {
    Write-Error "The Posh-SSH module with version 2.3.0 or greater is not found. Please install it before proceeding. The command is Install-Module Posh-SSH -MinimumVersion 2.3.0"
    Break
}
# Check that the FQDN of the SDDC Manager is valid 
Try {
    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to communicate with SDDC Manager ($server), check fqdn/ip address"
        Break
    } else {
        if ($powerState -eq "Shutdown") {
            if (-Not $force) {
                 Write-Host "";
                 $proceed_force = Read-Host "Would you like to gracefully shutdown customer deployed Virtual Machines not managed by VCF Workloads (Yes/No)? [No]"
                 if ($proceed_force -match "yes") {
                    $force = $true
                    Write-LogMessage -Type INFO -Message "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running within the Workload Domain"
                } else {
                    $force = $false
                    Write-LogMessage -Type INFO -Message "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running within the Workload Domain"
                }
             }
         }
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
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory (May take little time)"
        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $mgmtCluster = Get-VCFCluster | Where-Object { $_.id -eq ($managementDomain.clusters.id) }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        if ([string]::IsNullOrEmpty($workloadDomain)) {
             Write-LogMessage -Type ERROR -Message "The domain $sddcDomain doesn't exist, check it and re-trigger" -colour Red
             Exit
        }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

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
        $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).password
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

        $nsxt_local_url = "https://$nsxtMgrfqdn/login.jsp?local=true"
    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        # Change the DRS Automation Level to Partially Automated for both the VI Workload Domain Clusters
        if (!$($WorkloadDomain.type) -eq "MANAGEMENT") {
            $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
            if ($checkServer -eq "True") {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
            }
        }

        # Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable

        Write-LogMessage -Type INFO -Message "RetreatMode has been set, VCLS vm's getting shutdown will take time...please wait"

        $counter = 0
        $retries = 30

        foreach ($esxiNode in $esxiWorkloadDomain) {
            while ($counter -ne $retries) {
                $count = Get-PoweredOnVMsCount -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -pattern "vcls"
                if ( $count ) {
                    start-sleep 10
                    $count += 1
                } else {
                    break
                }
            }
        }
        if ($counter -eq 30) {
            Write-LogMessage -Type WARNING -Message "The vCLS vms did't get shutdown within stipulated timeout value" -Colour Cyan
        }

        # Shut Down the vSphere with Tanzu Virtual Machines
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP
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

        # Shutdown the NSX Edge Nodes
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            if ($nsxtEdgeNodes) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
            }
            else {
                Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping shutdown" -Colour Cyan
            }
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping shutdown of $nsxtEdgeNodes" -Colour Cyan
        }
        # Shutdown the NSX Manager Nodes
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

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

        # Prepare the vSAN cluster for shutdown - Performed on a single host only
        Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"

        # Disable vSAN cluster member updates and place host in maintenance mode
        $count = 0
        $flag = 0
        foreach ($esxiNode in $esxiWorkloadDomain) {
            $count = Get-PoweredOnVMsCount -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
            if ( $count) {
                if ($force) {
                    Write-LogMessage -Type WARNING -Message "Looks like there are some VM's still in powered On state. Force option is set to true" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "Hence shutting down Non VCF management vm's to put host in  maintenence mode" -Colour Cyan
                    Stop-CloudComponent -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -pattern .* -timeout 100
                } else {
                    $flag = 1
                    Write-LogMessage -Type WARNING -Message "Looks like there are some VM's still in powered On state. Force option is set to false" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "So not shutting down Non VCF management vm's. Hence unable to proceed with putting host in  maintenence mode" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "use cmdlet:  Stop-CloudComponent -server $($esxiNode.fqdn) -user $($esxiNode.username) -pass $($esxiNode.password) -pattern .* -timeout 100" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "use cmdlet:  Set-MaintenanceMode -server $($esxiNode.fqdn) -user $($esxiNode.username) -pass $($esxiNode.password) -state ENABLE" -Colour Cyan
                }
            }
        }
        if (-Not $flag) {
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
            }
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

        # Startup the Virtual Infrastructure Workload Domain vCenter Server
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($vcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)

        # Check the health and sync status of the VSAN cluster
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type ERROR -Message "The VC is still not up" -Colour RED
            Exit
        }

        #restart vSphere HA to avoid triggering a Cannot find vSphere HA master agent error.
        Restart-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name

        # Startup the vSphere with Tanzu Virtual Machines
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action START

        #Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable

        # Startup the NSX Manager Nodes in the Virtual Infrastructure Workload Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        Get-NsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword

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

        # Change the DRS Automation Level to Fully Automated for VI Workload Domain Clusters
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