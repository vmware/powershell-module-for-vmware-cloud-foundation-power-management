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
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -Shutdown
    Initiates a shutdown of the Virtual Infrastructure Workload Domain 'sfo-w01'

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -Shutdown -shutdownCustomerVm
    Initiates a shutdown of the Virtual Infrastructure Workload Domain 'sfo-w01' with shutdown of customer deployed VMs.
    Note: customer VMs will be stopped (Guest shutdown) only if they have VMware tools running and after NSX-T components, so they will loose networking before shutdown if they are running on overlay network.

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -Startup
    Initiates the startup of the Virtual Infrastructure Workload Domain 'sfo-w01'
#>

Param (
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [Switch]$startup,
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdown
    #[Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

# Customer Questions Section
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    if ($PsBoundParameters.ContainsKey("Shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Workload Domain." }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Workload Domain." }
    }
    #         Write-Host "";
    #         $proceed_force = Read-Host " Would you like to gracefully shutdown customer deployed Virtual Machines not managed by SDDC Manager (Yes/No)? [No]"; Write-Host ""
    #         if ($proceed_force -Match "yes") {
    #             $PSBoundParameters.Add('shutdownCustomerVm', 'Yes')
    #             $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Workload Domain."
    #         }
    #         else {
    #             $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Workload Domain."
    #         }
    #     }
    #     else {
    #         $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Workload Domain"
    #     }
    # }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Pre-Checks
Try {
    $Global:ProgressPreference = 'SilentlyContinue'
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass ******* -sddcDomain $sddcDomain "
    if ($PsBoundParameters.ContainsKey("startup")) { $str2 = $str2 + " -startup" }
    if ($PsBoundParameters.ContainsKey("shutdown")) { $str2 = $str2 + " -shutdown" }
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile" -Colour Yellow
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage -Colour Yellow }

    if (-Not (Get-InstalledModule -Name Posh-SSH -MinimumVersion 3.0.4 -ErrorAction Ignore)) {
        Write-PowerManagementLogMessage -Type INFO -Message "Use the command 'Install-Module Posh-SSH -MinimumVersion 3.0.4' to install from PS Gallery" -Colour Yellow
        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to find Posh-SSH module with version 3.0.4 or greater. Exiting!" -Colour Red
        Exit
    }
    else {
        $ver = Get-InstalledModule -Name Posh-SSH -MinimumVersion 3.0.4
        Write-PowerManagementLogMessage -Type INFO -Message "The version of Posh-SSH found on the system is: $($ver.Version)" -Colour Green
        # Try {
        #     Write-PowerManagementLogMessage -Type INFO -Message "Module Posh-SSH not loaded, importing now please wait..." -Colour Yellow
        #     Import-Module "Posh-SSH"
        #     Write-PowerManagementLogMessage -Type INFO -Message "Module Posh-SSH imported successfully." -Colour Green

        # }
        # Catch {
        #     Write-PowerManagementLogMessage -Type ERROR -Message "could not import Posh-SSH module, refer the documentation for possible solution"  -Colour Red
        #     Write-PowerManagementLogMessage -Type ERROR -Message "$($PSItem.Exception.Message)" -Colour Red
        #     Exit
        # }
    }

    if (!(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to communicate with SDDC Manager ($server), check fqdn/ip address or power state of the '$server'" -Colour Red
        Exit
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } 
        if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Cyan } 
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC manager is validated successfully"
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Gather details from SDDC Manager
Try {
    Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ($StatusMsg) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } if ($WarnMsg) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ($ErrorMsg) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory (May take some time)"

        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        if ([string]::IsNullOrEmpty($workloadDomain)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The domain $sddcDomain doesn't exist, check it and re-trigger" -Colour Red
            Exit
        }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
        $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password
        # We are using same user name and password for both workload and management vc, need to change or cross check
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id) })
        $mgmtvcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $mgmtvcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

        [Array]$allvms = @()
        [Array]$vcfvms = @()
        [Array]$vcfvms += ($vcServer.fqdn).Split(".")[0]


        # Gather ESXi Host Details for the VI Workload Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id }).fqdn) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).password
            $esxiWorkloadDomain += $esxDetails
        }
        # We will get NSX-T details in the respective startup/shutdown sections below.
    }
    else {
        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Run the Shutdown procedures
Try {
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
        Try {
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if (-Not $status) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
                }
            }
        }
        catch {
            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to the host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
        }
        
        # Check if Tanzu is enabled in WLD
        $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
        if ($status -eq $True) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Currently we are not supporting Tanzu enabled domains. Please try on other domains" -Colour Red
        }

        # Get NSX-T Details
        ## Gather NSX Manager Cluster Details
        $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).password
        $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
            [Array]$vcfvms += $node.Split(".")[0]
        }

        #Check if NSX-T manager VMs are running. If they are stopped skip NSX-T edge shutdown
        $nsxManagerPowerOnVMs = 0
        foreach ($nsxtManager in $nsxtNodes) {
            $state = Get-PoweredOnVMs -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch
            if ($state) { $nsxManagerPowerOnVMs += 1 }
            # If we have all NSX-T managers running or minimum of 2 nodes up - query NSX-T for edges.
            if (($nsxManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxManagerPowerOnVMs -eq 2)) { 
                $statusOfNsxtClusterVMs = 'running'
            }
        }
        if ($statusOfNsxtClusterVMs -ne 'running') {
            Write-PowerManagementLogMessage -Type WARNING -Message "NSX-T Manager VMs have been stopped, so NSX-T Edge cluster VMs will not be handled in automatic way" -Colour Cyan
        }
        else {
            Try {
                [Array]$nsxtEdgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $VcServer.fqdn)
                foreach ($node in $nsxtEdgeNodes) {
                    [Array]$vcfvms += $node
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Unable to fetch nsx edge nodes information from NSX-T manager '$nsxtMgrfqdn'. Exiting!" -Colour Red
            }
        }
        ## Gather NSX Edge Node Details from NSX-T Manager
        if ($nsxtEdgeNodes.count -ne 0) {
            $edgeVMs_string = $nsxtEdgeNodes -join "; "
            Write-PowerManagementLogMessage -Type INFO -Message "Found those NSX-T Data Center Edge Nodes managed by '$nsxtMgrfqdn': $edgeVMs_string ." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes found, skipping NSX-T edge nodes shutdown for NSX-T manager cluster '$nsxtMgrfqdn'!" -Colour Cyan
        }
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch All PoweredOn virtual machines from the server $($vcServer.fqdn)"
        [Array]$allvms = Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass
        $customervms = @()
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch All PoweredOn vCLS virtual machines from the server $($vcServer.fqdn)"
        [Array]$vclsvms += Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)"
        foreach ($vm in $vclsvms) {
            [Array]$vcfvms += $vm
        }

        $customervms = $allvms | ? { $vcfvms -notcontains $_ }
        $vcfvms_string = $vcfvms -join ","
        Write-PowerManagementLogMessage -Type INFO -Message "The SDDC manager managed virtual machines are: '$($vcfvms_string)' ." -Colour Cyan
        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join ", "
            Write-PowerManagementLogMessage -Type INFO -Message "The SDDC manager non-managed customer virtual machines are: '$($customervms_string)' ." -Colour Cyan
        }
        $VMwareToolsNotRunningVMs = @()
        $VMwareToolsRunningVMs = @()
        foreach ($vm in $customervms) {
            $status = Get-VMwareToolsStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -vm $vm
            if ($status -eq "RUNNING") {
                [Array]$VMwareToolsRunningVMs += $vm
            }
            else {
                [Array]$VMwareToolsNotRunningVMs += $vm
            }
        }
        if (($VMwareToolsNotRunningVMs.count -ne 0) -and ($PsBoundParameters.ContainsKey("shutdownCustomerVm"))) {
            Write-PowerManagementLogMessage -Type WARNING -Message "There are some non VCF maintained VMs where VMwareTools NotRunning, hence unable to shutdown these VMs:$($VMwareToolsNotRunningVMs)" -Colour cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "Unless these VMs are shutdown manually, we cannot proceed. Please shutdown manually and rerun the script" -Colour Red
            Exit
        }

        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join ","
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state. Customer VM Shutdown option is set to true" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down Non VCF management VMs, to put host in maintenance mode" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management VMs: $($customervms_string)" -Colour Cyan
                foreach ($vm in $customervms) {
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vm -timeout 300
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state. Customer VM Shutdown option is set to false" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down Non VCF management VMs: $($customervms_string)" -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shutdown manually or the customer VM Shutdown option is set to true.  Please take the necessary action and rerun the script" -Colour Red
                Exit
            }
        }

        # # Shut Down the vSphere with Tanzu Virtual Machines
        # if ((Test-NetConnection -ComputerName $vcServer.fqdn).PingSucceeded ) {
        #     Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP
        # }
        # else {
        #     Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping stopping the WCP service" -Colour Cyan
        # }

        # $clusterPattern = "^SupervisorControlPlaneVM.*"
        # foreach ($esxiNode in $esxiWorkloadDomain) {
        #     Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        # }

        # $clusterPattern = "^.*-tkc01-.*"
        # foreach ($esxiNode in $esxiWorkloadDomain) {
        #     Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        # }

        # $clusterPattern = "^harbor.*"
        # foreach ($esxiNode in $esxiWorkloadDomain) {
        #     Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300 -noWait
        # }

        ## Shutdown the NSX Edge Nodes
        if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
            if ($nsxtEdgeNodes) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes found, skipping NSX-T edge nodes shutdown for NSX-T manager cluster '$nsxtMgrfqdn'!" -Colour Cyan
            }
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping shutdown of $nsxtEdgeNodes" -Colour Cyan
        }

        ## Shutdown the NSX Manager Nodes
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        ## Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
        if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping Setting Retreat Mode" -Colour Cyan
        }

        # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) shutdown will take time...please wait" -Colour Yellow
        $counter = 0
        $retries = 10
        $sleep_time = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount ) {
                Write-PowerManagementLogMessage -Type INFO -Message "There are still vCLS VMs running. Sleeping for $sleep_time seconds before next check."
                start-sleep $sleep_time
                $counter += 1
            }
            else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS vms did't get shutdown within stipulated timeout value. Stopping the script" -Colour Red
            Exit
        }

        # Check the health and sync status of the vSAN cluster -- bug-2925318
        if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
            if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "VSAN Cluster health is Good." -Colour Green
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "vSAN Cluster health is BAD. Please check vSAN status in vCenter Server '$($vcServer.fqdn)'. Once vSAN is fixed, please restart the script." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "If script have reached ESXi vSAN Showdown previously, this error is expected. Please continue by following the VCF Documentation. " -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "VSAN Cluster health is BAD. Please check console messages above for possible solution." -Colour Red
                Exit
            }
            if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "VSAN Object Resync is successfully" -Colour Green
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "There is an active VSAN Object resync. Please check and rerun the script" -Colour Red
                Exit
            }
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking vSAN health for cluster $($cluster.name)" -Colour Cyan
        }
        
        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        $runningVMs = Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass
        if ($runningVMs.count) {
            Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state." -Colour Cyan
            Write-PowerManagementLogMessage -Type WARNING -Message "Unable to proceed unless they are shutdown. Kindly shutdown them manually and rerun the script" -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "There are running VMs in environment: $($runningVMs). We could not continue with vSAN shutdown while there are running VMs. Exiting! " -Colour Red
        }
        else {
            # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
            }

            ## Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
            # Disable cluster member updates from vCenter Server
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
            }
            # Run vSAN cluster preparation - should be done on one host per cluster
            # Sleeping 1 min before starting the preparation
            Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for one minute..."
            Start-Sleep -s 60
            Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
            # Putting hosts in maintenance mode
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
            }

            ## TODO Add ESXi shutdown here
    
            ## Shutdown vCenter Server
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
    
            # End of shutdown
            Write-PowerManagementLogMessage -Type INFO -Message "End of Shutdown sequence!" -Colour Cyan
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Startup procedures
Try {
    if ($WorkloadDomain.type -eq "MANAGEMENT") {
        Write-PowerManagementLogMessage -Type ERROR -Message "Provided Workload domain '$sddcDomain' is the Management Workload domain. This script handles Worload Domains. Exiting! " -Colour Red
        Exit
    }
    if ($PsBoundParameters.ContainsKey("startup")) {
        # Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
        Try {
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if (-Not $status) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
                    Exit
                }
            }
        }
        catch {
            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to the host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
        }

        # Take hosts out of maintenance mode
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
        }

        # Prepare the vSAN cluster for startup - Performed on a single host only
        Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

        # Enable vSAN cluster member updates
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
        }

        # Check ESXi status for each host
        Write-PowerManagementLogMessage -Type INFO -Message "Chgeck vSAN status for ESXi hosts." -Colour Green
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
        }

        # Startup the Virtual Infrastructure Workload Domain vCenter Server
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        Write-PowerManagementLogMessage -Type INFO -Message "Waiting for vCenter Server services to start on $($vcServer.fqdn) (may take some time)" -Colour Yellow
        $retries = 20
        $flag = 0
        $service_status = 0
        if ($DefaultVIServers) {
            Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        }
        While ($retries) {
            Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue | Out-Null
            if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                #Max wait time for services to come up is 10 mins.
                for ($i = 0; $i -le 10; $i++) {
                    $status = Get-VAMIServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service 'vsphere-ui' -nolog
                    if ($status -eq "STARTED") {
                        $service_status = 1
                        break
                    }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "The services on Virtual Center is still starting. Please wait." -Colour Yellow
                        Start-Sleep 60
                    }
                }
                $flag = 1
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Start-Sleep 60
            $retries -= 1
            Write-PowerManagementLogMessage -Type INFO -Message "The Virtual Center is still starting. Please wait." -Colour Yellow
        }

        # Check the health and sync status of the vSAN cluster
        if ( $flag -and $service_status) {
            if ((Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "Cluster health is Good." -Colour Green
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cluster health is BAD. Please check and rerun the script" -Colour Red
                Exit
            }
            if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "VSAN Object Resync is successful" -Colour Green
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "VSAN Object resync is unsuccessful. Please check and rerun the script" -Colour Red
                Exit
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCenter Server and its services are still not online" -Colour Red
            Exit
        }

        # Start vSphere HA to avoid triggering a "Cannot find vSphere HA master agent" error.
        if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
        }

        <# 2963366 : DRS settings in not exactly needed for workload domain, rather needed for management
                # Change the DRS Automation Level to Fully Automated for VI Workload Domain Clusters
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
        #>
        #Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable

        # Waiting for vCLS VMs to be started for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) startup will take time...please wait" -Colour Yellow
        $counter = 0
        $retries = 30
        $sleep_time = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount -lt 3 ) {
                Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleep_time seconds before next check."
                start-sleep $sleep_time
                $counter += 1
            }
            else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS vms did't get started within stipulated timeout value. Stopping the script" -Colour Red
            Exit
        }

        # Get NSX-T Details once VC is started
        ## Gather NSX Manager Cluster Details
        $counter = 0
        $retries = 15
        $sleep_time = 30
        while ($counter -ne $retries) {
            Try {
                $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id -ErrorAction SilentlyContinue -InformationAction Ignore
            }
            Catch {
                Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still populating NSX-T information. Sleeping for $sleep_time seconds before next check...."
                start-sleep $sleep_time
                $counter += 1
            }
            # Stop loop if we have FQDN for NSX-T VIP
            if ( $($nsxtCluster.vipFqdn) ) { Break }
            else {
                Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still populating NSX-T information. Sleeping for $sleep_time seconds before next check...."
                start-sleep $sleep_time
                $counter += 1
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "SDDC Manager did not manage to obtain NSX-T information. Please check LCM log file for errors. Stopping the script!" -Colour Red
            Exit
        }
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).password
        $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
            [Array]$vcfvms += $node.Split(".")[0]
        }

        # Startup the NSX Manager Nodes for Virtual Infrastructure Workload Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "NSX-T Cluster is not in 'STABLE' state. Exiting!" -Colour Red
            Exit
        }

        # Gather NSX Edge Node Details and do the startup
        Try {
            [Array]$nsxtEdgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $VcServer.fqdn)
            foreach ($node in $nsxtEdgeNodes) {
                [Array]$vcfvms += $node
            }
        }
        catch {
            Write-PowerManagementLogMessage -Type WARNING -Message "Unable to fetch nsx edge nodes information" -Colour Cyan
        }
        if ($nsxtEdgeNodes.count -ne 0) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes found, skipping NSX-T edge nodes startup for NSX-T manager cluster '$nsxtMgrfqdn'!" -Colour Cyan
        }

        # End of startup
        $vcfvms_string = $vcfvms -join "; "
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "The following components have been started: $vcfvms_string , " -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "vSphere vSphere High Availability has been enabled by the script, please disable it if it is not desired" -Colour Cyan
        Write-PowerManagementLogMessage -Type INFO -Message "Please check the list above and start any additional VMs, that are required, before you proceed with workload startup!" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts through SDDC manager, please make sure that you disable it at this point." -Colour Cyan
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "End of startup sequence!" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}