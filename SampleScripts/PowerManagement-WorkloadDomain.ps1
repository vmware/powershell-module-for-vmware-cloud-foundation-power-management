# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake / Sowjanya V
    .Group:         Cloud Infrastructure Business Group (CIBG)
    .Organization:  VMware
    .Version:       1.0 (Build 001)
    .Date:          2022-02-22
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2022-02-22) - Initial release

    ===============================================================================================================
    
    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup a VI Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Virtual Infrastructure Workload Domain

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
    Initiates a shutdown of the Virtual Infrastructure Workload Domain 'sfo-w01'

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown -shutdownCustomerVm
    Initiates a shutdown of the Virtual Infrastructure Workload Domain 'sfo-w01' with shutdown of customer deployed VMs. 
    Note: customer VMs will be stopped (Guest shutdown) only if they have VMware tools running and after NSX-T components, so they will loose networking before shutdown if they are running on overlay network.

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Startup
    Initiates the startup of the Virtual Infrastructure Workload Domain 'sfo-w01'
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
    $Global:ProgressPreference = 'SilentlyContinue'
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass ******* -sddcDomain $sddcDomain -powerState $powerState"
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    Write-LogMessage -Type INFO -Message "Script used: $str1" -Colour Yellow
    Write-LogMessage -Type INFO -Message "Script syntax: $str2" -Colour Yellow
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile" -Colour Yellow
    if (-Not $null -eq $customerVmMessage) { Write-LogMessage -Type INFO -Message $customerVmMessage -Colour Yellow}

    if (-Not (Get-InstalledModule -Name Posh-SSH -MinimumVersion 2.3.0 -ErrorAction Ignore)) {
        Write-LogMessage -Type ERROR -Message "Unable to find Posh-SSH module with version 2.3.0 or greater, Please install before proceeding" -Colour Red
        Write-LogMessage -Type INFO -Message "Use the command 'Install-Module Posh-SSH -MinimumVersion 2.3.0' to install from PS Gallery" -Colour Yellow
        Exit
    }
    else {
        $ver = Get-InstalledModule -Name Posh-SSH -MinimumVersion 2.3.0
        Write-LogMessage -Type INFO -Message "The version of Posh-SSH $($ver.Version) found on system" -Colour Green
        if (Get-Module -Name Posh-SSH) {
            Write-LogMessage -Type INFO -Message "The required version of Posh-SSH $($ver.Version) is already imported" -Colour Green
        } else {
            # If module is not imported, check if available on disk and try to import
            Try {
                Write-LogMessage -Type INFO -Message "Module Posh-SSH not loaded, importing now please wait..."
                Import-Module "Posh-SSH"
                Write-LogMessage -Type INFO -Message "Module Posh-SSH imported successfully." -Colour Green

            }
            Catch {
                Write-LogMessage -Type ERROR -Message "Import is not sucessfull, please refer doc for possible reason and solution"
                Exit
            }
        }
    }

    if (!(Test-NetConnection -ComputerName $server)) {
        Write-Error "Unable to communicate with SDDC Manager ($server), check fqdn/ip address"
        Break
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ($StatusMsg) {
            Write-LogMessage -Type INFO -Message "Connection to SDDC manager is validated successfully" -Colour Green
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
    if ($StatusMsg) { Write-LogMessage -Type INFO -Message $StatusMsg } if ($WarnMsg) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Cyan } if ($ErrorMsg) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
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
            $checkServer = Test-NetConnection -ComputerName $vcServer.fqdn
            if ($checkServer) {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Provided Workload domain '$sddcDomain' is the Management Workload domain. This script handles Worload Domains. Exiting! " -Colour Red
            Exit
        }
        
        # Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        if (Test-NetConnection -ComputerName $vcServer.fqdn ) {
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping Setting Retreat Mode" -Colour Cyan
        }

        # Waiting for VCLS VMs to be stopped for ($retries*10) seconds
        Write-LogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) shutdown will take time...please wait" -Colour Yellow
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
        if (Test-NetConnection -ComputerName $vcServer.fqdn ) {
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
        if (Test-NetConnection -ComputerName $vcServer.fqdn ) {
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

        # Check the health and sync status of the vSAN cluster 
        if (Test-NetConnection -ComputerName $vcServer.fqdn ) {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            # Shutdown vCenter Server
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking vSAN health for cluster $($cluster.name)" -Colour Cyan
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
                    Write-LogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn)" -Colour Cyan
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
            # End of shutdown
            Write-LogMessage -Type INFO -Message "End of Shutdown sequence!" -Colour Yellow
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

# Startup procedures
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
        Write-LogMessage -Type INFO -Message "Waiting for vCenter Server services to start on $($vcServer.fqdn) (may take some time)" -Colour Yellow
        $retries = 20
        $flag = 0
        While ($retries) {
            Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue
            if ($DefaultVIServer.Name -eq $server) {
                $flag =1
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Start-Sleep 60
            $retries -= 1
            Write-LogMessage -Type INFO -Message "The services still coming up. Please wait." -colour Yellow
        }

        # Check the health and sync status of the vSAN cluster
        if ( $flag ) {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type ERROR -Message "The vCenter Server and its services are still not online despite waiting for 20 mins" -Colour Red
            Exit
        }

        # Restart vSphere HA to avoid triggering a Cannot find vSphere HA master agent error.
        Restart-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name

        # Change the DRS Automation Level to Fully Automated for VI Workload Domain Clusters
        Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated

        #Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable


        # Startup the NSX Manager Nodes in the Virtual Infrastructure Workload Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
            Write-LogMessage -Type ERROR -Message "NSX-T Cluster is not in 'STABLE' state. Exiting!" -Colour Red
            Exit
        }

        # Startup the NSX Edge Nodes in the Virtual Infrastructure Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
        }

        # End of startup
        Write-LogMessage -Type INFO -Message "End of startup sequence!" -Colour Yellow
    }
}
Catch {
    Debug-CatchWriter -object $_
}