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
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

# Customer Questions Section 
Try {
    Clear-Host; Write-Host ""
    if ($powerState -eq "Shutdown") {
        if (-Not $PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
            Write-Host "";
            $proceed_force = Read-Host " Would you like to gracefully shutdown customer deployed Virtual Machines not managed by SDDC Manager (Yes/No)? [No]"; Write-Host ""
            if ($proceed_force -Match "yes") {
                $PSBoundParameters.Add('shutdownCustomerVm','Yes')
                $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running within the Workload Domain"
            }
            else {
                $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running within the Workload Domain"
            }
        }
        else {
            $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running within the Workload Domain"
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Pre-Checks and Log Creation
Try {
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass $pass -sddcDomain $sddcDomain -powerState $powerState"
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    Write-LogMessage -Type INFO -Message "Script Executed: $str1" -Colour Yellow
    Write-LogMessage -Type INFO -Message "Script Syntax: $str2" -Colour Yellow
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    if (-Not $null -eq $customerVmMessage) { Write-LogMessage -Type INFO -Message $customerVmMessage -Colour Cyan}

    if (-Not (Get-InstalledModule -Name Posh-SSH -MinimumVersion 2.3.0 -ErrorAction Ignore)) {
        Write-LogMessage -Type ERROR -Message "Unable to find Posh-SSH module with version 2.3.0 or greater is not found. Please install before proceeding" -Colour Red
        Write-LogMessage -Type INFO -Message "Use the command 'Install-Module Posh-SSH -MinimumVersion 2.3.0' to install from PS Gallery" -Colour Cyan
        Break
    }
    else {
        Write-LogMessage -Type INFO -Message "Required version of Posh-SSH found on system"
    }

    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to communicate with SDDC Manager ($server), check fqdn/ip address"
        Break
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ($StatusMsg) {
            Write-LogMessage -Type INFO -Message "Connection to SDDC manager is validated successfully"
        }
        elseif ($ErrorMsg) {
            if ($ErrorMsg -match "4\d\d") {
                Write-LogMessage -Type ERROR -Message "The authentication/authorization failed, please check credentials once again and then retry" -colour Red
                Break
            }
            else {
                Write-Error $ErrorMsg
                Break
            }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Gather details from SDDC Manager
Try {
    Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ($StatusMsg) { Write-LogMessage -Type INFO -Message $StatusMsg } if ($WarnMsg) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ($ErrorMsg) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory (May take little time)"
        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        if ([string]::IsNullOrEmpty($workloadDomain)) {
            Write-LogMessage -Type ERROR -Message "The domain $sddcDomain doesn't exist, check it and re-trigger" -Colour Red
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
        # Change the DRS Automation Level to Partially Automated for VI Workload Domain Clusters
        if ($WorkloadDomain.type -ne "MANAGEMENT") {
            $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
            if ($checkServer -eq "True") {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Provided Workload domain '$sddcDomain' is the Management Workload domain. This script handles Worload Domains. Exiting! " -Colour Red
            Exit
        }
        
        # Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping Setting Retreat Mode" -Colour Cyan
        }

        # Waiting for VCLS VMs to be stopped for ($retries*10) seconds
        Write-LogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) shutdown will take time...please wait"
        $counter = 0
        $retries = 30
        foreach ($esxiNode in $esxiWorkloadDomain) {
            while ($counter -ne $retries) {
                $powerOnVMcount = Get-PoweredOnVMsCount -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -pattern "vcls"
                if ( $powerOnVMcount ) {
                    start-sleep 10
                    $counter += 1
                }
                else {
                    Break
                }
            }
        }
        if ($counter -eq $retries) {
            Write-LogMessage -Type WARNING -Message "The vCLS vms did't get shutdown within stipulated timeout value" -Colour Cyan
        }

        # Shut Down the vSphere with Tanzu Virtual Machines
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping stopping the WCP service" -Colour Cyan
        }
        
        $clusterPattern = "^SupervisorControlPlaneVM.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        $clusterPattern = "^.*-tkc01-.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        $clusterPattern = "^harbor.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300 -noWait
        }

        # Shutdown the NSX Edge Nodes
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
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
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            # Shutdown vCenter Server
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
        }

        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        $count = 0
        $flag = 0
        foreach ($esxiNode in $esxiWorkloadDomain) {
            $count = Get-PoweredOnVMsCount -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
            if ($count) {
                if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                    Write-LogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state. Customer VM Shutdown option is set to true" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "Hence shutting down Non VCF management VMs, to put host in maintenance mode" -Colour Cyan
                    Stop-CloudComponent -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -pattern .* -timeout 300
                    if (Get-PoweredOnVMsCount -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password) {
                        Write-LogMessage -Type ERROR -Message "Could not stop VM on ESXi $($esxiNode.fqdn). Please stop VM manually. Exiting!" -Colour Red
                        Exit
                    }                    
                }
                else {
                    $flag = 1
                    Write-LogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state. Customer VM Shutdown is not requested," -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "So not shutting down Non VCF management VMs. Hence unable to proceed with putting host in maintenance mode" -Colour Cyan
                    Write-LogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn)" -Colour Red
                }
            }
        }
        if (-Not $flag) {
            # Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
            # Disable cluster member updates from vCenter Server
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
            }
            # Run vSAN cluster preparation - should be done on one host per cluster
            # Sleeping 1 min before starting the preparation
            Start-Sleep -s 60
            Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
            # Putting hosts in maintenance mode
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Stopping shutdown process, since there are still running VMs! Please, check output above in order to identify ESXi hosts with running VMs." -Colour Red
            Write-LogMessage -Type ERROR -Message "Please shut down VMs directly from ESXi hosts and run this script again." -Colour Red 
            Exit
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($WorkloadDomain.type -eq "MANAGEMENT") {
        Write-LogMessage -Type ERROR -Message "Provided Workload domain '$sddcDomain' is the Management Workload domain. This script handles Worload Domains. Exiting! " -Colour Red
        Exit
    }
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
        Write-LogMessage -Type INFO -Message "Waiting for vCenter Server services to start on $($vcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)

        # Check the health and sync status of the VSAN cluster
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type ERROR -Message "The vCenter Server and its services are still not online" -Colour Red
            Exit
        }

        # Restart vSphere HA to avoid triggering a Cannot find vSphere HA master agent error.
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Restart-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) is not power on, skipping restarting vSphere HA" -Colour Cyan
            Exit
        }

        #Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) is not power on, skipping disabling Retreat Mode" -Colour Cyan
            Exit
        }

        # Startup the NSX Manager Nodes in the Virtual Infrastructure Workload Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        Get-NsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword

        # Startup the NSX Edge Nodes in the Virtual Infrastructure Workload Domain 
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
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
        if (Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) is not power on, skipping setting the DRS Automation level" -Colour Cyan
            Exit
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}