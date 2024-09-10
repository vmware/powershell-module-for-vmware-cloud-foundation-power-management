# Copyright 2023-2024 Broadcom. All Rights Reserved.
# SPDX-License-Identifier: BSD-2

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===============================================================================================================
    .CHANGE_LOG
    Check the CHANGELOG.md file for the latest changes and updates made to this script.
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
    Initiates the startup of all clusters in the the Virtual Infrastructure Workload Domain 'sfo-w01', excluding the clusters in ERROR state

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -Startup -forceRunOnClustersInErrorState
    Initiates the startup of all clusters in the the Virtual Infrastructure Workload Domain 'sfo-w01', including the clusters in ERROR state

    .EXAMPLE
    PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -vsanCluster cluster1, cluster2 -Startup
    Initiates the startup of clusters 'cluster1' and 'cluster2' in the Virtual Infrastructure Workload Domain 'sfo-w01'. Startup order will be 'cluster1', then 'cluster2'.
#>

Param (
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $false, ParameterSetName = "startup")]
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
    [Parameter (Mandatory = $false, ParameterSetName = "startup")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$forceRunOnClustersInErrorState,
    [Parameter (Mandatory = $false, ParameterSetName = "startup")]
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Array]$vsanCluster,
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [Switch]$startup,
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdown
)

##########################################################################
#Region     Non Exported Functions                                  ######
Function Get-Password {
    param (
        [string]$user,
        [string]$password
    )

    if ([string]::IsNullOrEmpty($password)) {
        $secureString = Read-Host -Prompt "Enter the password for $user" -AsSecureString
        $password = ConvertFrom-SecureString $secureString -AsPlainText
    }
    return $password
}

# Error Handling (script scope function)
Function Debug-CatchWriterForPowerManagement {
    Param (
        [Parameter (Mandatory = $true)] [PSObject]$object
    )
    $ErrorActionPreference = 'Stop'
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-PowerManagementLogMessage -Message " ERROR at Script Line $lineNumber"
    Write-PowerManagementLogMessage -Message " Relevant Command: $lineText"
    Write-PowerManagementLogMessage -Message " ERROR Message: $errorMessage"
    Write-Error -Message $errorMessage
}
#EndRegion  Non Exported Functions                                  ######
##########################################################################

$pass = Get-Password -User $user -Password $pass

# Set some useful variables
$simultaneousClustersPowerOperation = 5

# Setup logging
Try {
    Clear-Host; Write-Host ""
    $logLocation = $PSScriptRoot
    $Global:logFile = $logLocation + "\PowerManagement_" + $sddcDomain + ".log"
    $timeStamp = Get-Date -Format "MM/dd/yyyy_HH:mm:ss"
    Add-Content -Path $logFile "*************************************** $timeStamp ***************************************"
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path '$logfile'"
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Initial checks and information messages
Try {
    $Global:ProgressPreference = 'SilentlyContinue'
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass ******* -sddcDomain $sddcDomain"
    if ($PsBoundParameters.ContainsKey("vsanCluster")) { $str2 = $str2 + " -vsanCluster " + ($vsanCluster -join ",") }
    if ($PsBoundParameters.ContainsKey("startup")) { $str2 = $str2 + " -startup" }
    if ($PsBoundParameters.ContainsKey("shutdown")) { $str2 = $str2 + " -shutdown" }
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1"
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2"
    if ($PsBoundParameters.ContainsKey("Shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Workload Domain." }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Workload Domain." }
    }
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage }

    if (!(Test-EndpointConnection -server $server -port 443)) {
        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with SDDC Manager ($server). Check the FQDN or IP address or power state of the '$server'."
        Exit
    } else {
        $statusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $statusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $statusMsg }
        if ( $warnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $warnMsg }
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg }
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC Manager has been validated successfully."
        }
    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Gather details from SDDC Manager
Try {
    Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details..."
    $statusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ($statusMsg) { Write-PowerManagementLogMessage -Type INFO -Message $statusMsg } if ($warnMsg) { Write-PowerManagementLogMessage -Type WARNING -Message $warnMsg } if ($ErrorMsg) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg }
    if ($accessToken) {
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from the SDDC Manager inventory... It will take some time."

        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $allWld = Get-VCFWorkloadDomain | Where-Object { ($_.Type -ne "MANAGEMENT") }
        $allWldVCs = $allWld.vcenters.fqdn
        if ([string]::IsNullOrEmpty($workloadDomain)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Domain $sddcDomain doesn't exist. Check your environment and try again. "
            Exit
        }

        # Check if there are multiple clusters in the WLD
        $sddcClusterDetails = @()
        $userClusterDetails = @()
        $clusterDetails = @()
        $userClusterArray = @()
        $sddcClusterArray = @()
        if ($vsanCluster) {
            $userClusterArray = $vsanCluster.split(",")
        }

        $allClusterShutdown = $false
        $hostsClusterMapping = @{}
        $sddcHostsClusterMapping = @{}
        $esxiWorkloadCluster = @{}
        $ClusterStatusMapping = @{}

        # Gather cluster details from SDDC Manager
        foreach ($id in $($workloadDomain.clusters.id)) {
            $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
            $sddcClusterDetails += $clusterData
            $sddcHostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
            $sddcClusterArray += $clusterData.name
            $esxiWorkloadCluster[$clusterData.name] = @()
        }
        Write-PowerManagementLogMessage -Type INFO -Message "Clusters in SDDC Manager database: '$($sddcClusterArray -join ",")'."

        if ($vsanCluster) {
            # TODO - Handle clusters in the order that are passed.
            foreach ($name in $userClusterArray) {
                $clusterData = (Get-VCFCluster | Where-Object { $_.name -eq ($name) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
                $userClusterDetails += $clusterData
            }
            $clusterDetails = $userClusterDetails
            if (((Compare-Object $sddcClusterArray $userClusterArray -IncludeEqual | Where-Object -FilterScript { $_.SideIndicator -eq '=>' }).InputObject).count) {
                $wrongClusterNames = (Compare-Object $sddcClusterArray $userClusterArray -IncludeEqual | Where-Object -FilterScript { $_.SideIndicator -eq '=>' }).InputObject
                Write-PowerManagementLogMessage -Type WARNING -Message "A wrong cluster name has been passed."
                Write-PowerManagementLogMessage -Type WARNING -Message "The known clusters, part of this workload domain are:$($sddcClusterDetails.name)"
                Write-PowerManagementLogMessage -Type WARNING -Message "The cluster names passed are: $userClusterArray"
                Write-PowerManagementLogMessage -Type WARNING -Message "Clusters not matching the SDDC Manager database:  $wrongClusterNames"
                Write-PowerManagementLogMessage -Type ERROR -Message "Please cross check and run the script again. Exiting!"
            }
        } else {
            foreach ($id in $($workloadDomain.clusters.id)) {
                $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
            }
            $clusterDetails = $sddcClusterDetails
            $allClusterShutdown = $true
            if ($PsBoundParameters.ContainsKey("shutdown")) {
                Write-PowerManagementLogMessage -Type INFO -Message "All clusters in the VI domain '$sddcDomain' will be stopped."
            }
            if ($PsBoundParameters.ContainsKey("startup")) {
                Write-PowerManagementLogMessage -Type INFO -Message "All clusters in the VI domain '$sddcDomain' will be started."
            }
        }

        # Check the SDDC Manager version if VCF less than or greater than VCF 5.0
        $vcfVersion = Get-VCFManager | Select-Object version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object { $_.matches.groups[0].value }
        if ([float]$vcfVersion -lt [float]5.0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The script supports only VCF 5.0 and newer versions. Exiting!"
            Exit
        }

        # Gather Workload vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
        $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).username
        $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).password

        # Gather Management vCenter Server Details and Credentials
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id) })
        $mgmtVcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($managementDomain.ssoId) }).username
        $mgmtVcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($managementDomain.ssoId) }).password

        # Array to hold "service" VMs
        [Array]$vcfVMs = @()
        [Array]$vcfVMs += ($vcServer.fqdn).Split(".")[0]

        # Gather VxRail Manager details for the VI workload domain, if it exists.
        if ($PsBoundParameters.ContainsKey("shutdown")) {
            $vxRailCred = (Get-VCFCredential | Where-Object { $_.resource.resourceType -eq "VXRAIL_MANAGER" -and $_.resource.domainName -eq ($workloadDomain.name) -and $_.username -eq "root" })
            if ($null -ne $vxRailCred) {
                # Connecting to vCenter Server to get the VxRail Manager virtual machine name.
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                if (Test-EndpointConnection -server $vcServer.fqdn -port 443 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                    if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                        $vxrailVMObject = Get-VM | Where-Object { $_.Guest.Hostname -Match $vxRailCred.resource.resourceName -Or $_.Guest.Hostname -Match ($vxRailCred.resource.resourceName.Split("."))[0] }
                        if ($vxrailVMObject) {
                            $vxRailVmName = $vxrailVMObject.Name
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "VxRail($($vxRailCred.resource.resourceName)) Virtual Machine object cannot be located within VC Server ($($vcServer.fqdn))"
                        }
                    }
                }

                $vxRailDetails = New-Object -TypeName PSCustomObject
                $vxRailDetails | Add-Member -Type NoteProperty -Name fqdn -Value $vxRailCred.resource.resourceName
                $vxRailDetails | Add-Member -Type NoteProperty -Name vmName -Value $vxRailVmName
                $vxRailDetails | Add-Member -Type NoteProperty -Name username -Value $vxRailCred.username
                $vxRailDetails | Add-Member -Type NoteProperty -Name password -Value $vxRailCred.password
                [Array]$vcfVMs += ($vxRailDetails.vmName)
                Write-PowerManagementLogMessage -Type INFO -Message "VxRail Manager($vxRailVmName) found within VC Server ($($vcServer.fqdn))"
            } else {
                $vxRailDetails = ""
            }
        }

        # Gather ESXi Host Details for the VI Workload Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id })) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost.fqdn
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost.fqdn -and $_.accountType -eq "USER" })).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost.fqdn -and $_.accountType -eq "USER" })).password
            $esxiWorkloadDomain += $esxDetails
            #Gather ESXi Host to Cluster mapping info for the given VI Workload domain
            foreach ($clusterName in $sddcHostsClusterMapping.keys) {
                if ($sddcHostsClusterMapping[$clusterName] -contains $esxiHost.id) {
                    $esxiWorkloadCluster[$clusterName] += $esxDetails
                }
            }
        }

        # Get the status of the clusters that are about to be stopped or started
        if ( Test-EndpointConnection -server $vcServer.fqdn -port 443 ) {
            if ($DefaultVIServer.Name -notcontains $vcServer.fqdn -or $DefaultVIServer.IsConnected -eq $false) {
                if ( Test-EndpointConnection -server $vcServer.fqdn -port 443 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check your environment and try again"
                }
            } else {
                Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Already connected to server '$server'."
            }
            if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get clusters power status..."
                foreach ($cluster in $clusterDetails.Name) {
                    $clusterPowerStatus = Get-VsanClusterPowerState -Cluster $cluster -Server $vcServer.fqdn
                    if ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOff" -and $null -eq $clusterPowerStatus.TrackingTask) {
                        $ClusterStatusMapping[$cluster] = 'DOWN'
                    } elseif ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOn" -and $null -eq $clusterPowerStatus.TrackingTask) {
                        $ClusterStatusMapping[$cluster] = 'UP'
                    } elseif ($null -ne $clusterPowerStatus.LastErrorMessage) {
                        $ClusterStatusMapping[$cluster] = 'ERROR'
                        Write-PowerManagementLogMessage -Type WARNING -Message "Cluster $cluster is in error state. Current status: '$($clusterPowerStatus.CurrentClusterPowerStatus)'"
                        Write-PowerManagementLogMessage -Type WARNING -Message "Cluster $cluster is in error state. Error: '$($clusterPowerStatus.LastErrorMessage)'"
                    }
                    # Handle clusters that are running power operation at the moment
                    if ($null -ne $clusterPowerStatus.TrackingTask) {
                        $ClusterStatusMapping[$cluster] = 'RUNNING_POWER_OPERATION'
                        Write-Host "Cluster $cluster is running power operation"
                    }
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check the console output for more details."
            }
        } else {
            # If we cannot connect to vCenter Server and we are in startup mode we will assume that all clusters are down.
            if ($PsBoundParameters.ContainsKey("startup")) {
                foreach ($cluster in $clusterDetails.Name) {
                    $ClusterStatusMapping[$cluster] = 'DOWN'
                }
            }
            # We will stop the script if we are in shutdown mode and we cannot connect to vCenter Server.
            if ($PsBoundParameters.ContainsKey("shutdown")) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not reach ($($vcServer.fqdn)). Check if it is powered on and reachable."
                Exit
            }
        }

        # We will get NSX-T details in the respective startup/shutdown sections below.
    } else {
        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to vCenter Server ($($vcServer.fqdn)). Check your credentials."
        Exit
    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Run the Shutdown procedures
Try {
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        # Get NSX-T Details
        ## Gather NSX Manager Cluster Details
        $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
        $nsxtManagerFQDN = $nsxtCluster.vipFqdn
        $nsxtManagerVIP = New-Object -TypeName PSCustomObject
        $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).username
        $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).password
        $nsxtNodesFQDN = $nsxtCluster.nodes.fqdn
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesFQDN) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }

        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about all powered-on vCLS virtual machines from vCenter Server $($vcServer.fqdn)..."
        [Array]$vclsVMs += Get-VMsWithPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon"-pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence
        foreach ($vm in $vclsVMs) {
            [Array]$vcfVMs += $vm
        }

        Write-PowerManagementLogMessage -Type INFO -Message "Fetching all powered on vSAN File Services virtual machines from vCenter Server instance $($vcenter)..."
        [Array]$vsanFsVMs += Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(vSAN File)" -silence
        foreach ($vm in $vsanFsVMs) {
            [Array]$vcfVMs += $vm
        }

        #Check if NSX-T manager VMs are running. If they are stopped skip NSX-T edge shutdown
        $nsxtManagerPowerOnVMs = 0
        foreach ($nsxtManager in $nsxtNodes) {
            $state = Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -pattern $nsxtManager -exactMatch -powerstate "poweredon"
            if ($state) { $nsxtManagerPowerOnVMs += 1 }
            # If we have all NSX-T managers running or minimum of 2 nodes up - query NSX-T for edges.
            if (($nsxtManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxtManagerPowerOnVMs -eq 2)) {
                $statusOfNsxtClusterVMs = 'running'
            }
        }

        $nsxtClusterEdgeNodes = @()
        if ($statusOfNsxtClusterVMs -ne 'running') {
            Write-PowerManagementLogMessage -Type WARNING -Message "The NSX Manager VMs have been stopped. The NSX Edge VMs will not be handled in an automatic way."
            Write-PowerManagementLogMessage -Type WARNING -Message "The NSX Manager VMs have been stopped. We could not check if this NSX Manager is spanned across Workload Domains."
        } else {
            Try {
                [Array]$nsxtEdgeNodes = Get-EdgeNodeFromNSXManager -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword -VCfqdn $vcServer.fqdn
                foreach ($node in $nsxtEdgeNodes) {
                    [Array]$vcfVMs += $node
                }
            } Catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Unable to fetch NSX Edge node information from NSX Manager '$nsxtManagerFQDN'. Exiting!"
            }

            # This variable holds True of False based on if NSX is spanned across workloads or not.
            $nsxtSpannedAcrossWldVc = Get-NSXTComputeManagers -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword
            $NSXTSpannedAcrossWld = $nsxtSpannedAcrossWldVc.count -gt 1
        }

        $vcfVMs_string = $vcfVMs -join "; "

        # TODO Add check if clusters are vSAN or not.
        # TODO Add support for non-vSAN clusters.
        # Use different workflows based on individual cluster and whole WLD shutdown

        if ($allClusterShutdown) {
            # Check if there are clusters in error state
            $ErrorCount = 0
            foreach ($cluster in $clusterDetails) {
                if ($ClusterStatusMapping[$cluster.name] -eq 'ERROR') {
                    $ErrorCount += 1
                }
            }
            if ($ErrorCount -ne 0) {
                Write-PowerManagementLogMessage -Type WARNING -Message "$ErrorCount out of $($clusterDetails.count) clusters are in error state."
                Write-PowerManagementLogMessage -Type WARNING -Message "Clusters in error state: '$($($clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'ERROR' }).name -join "; ")'."
            }

            # Check if all clusters are already stopped
            $DownCount = 0
            foreach ($cluster in $clusterDetails) {
                if ($ClusterStatusMapping[$cluster.name] -eq 'DOWN') {
                    $DownCount += 1
                }
            }
            Write-PowerManagementLogMessage -Type INFO -Message "Shutting down all clusters in the VI domain '$sddcDomain'..."
            Write-PowerManagementLogMessage -Type INFO -Message "$DownCount out of $($clusterDetails.count) clusters are stopped."
            if ($DownCount -eq $clusterDetails.count) {
                Write-PowerManagementLogMessage -Type INFO -Message "All clusters are already stopped. Skipping clusters shutdown."
            } else {
                # Get all user VMs in the VI domain
                Write-PowerManagementLogMessage -Type INFO -Message "Fetching information about all powered-on virtual machines for the specified vCenter Server $($vcServer.fqdn)..."
                [Array]$allPoweredOnVMs = Get-VMsWithPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate poweredOn -silence

                # Get all powered-on customer VMs in the VI domain
                $runningCustomerVMs = $allPoweredOnVMs | Where-Object { $vcfVMs -NotContains $_ }
                $runningCustomerVMs_string = $runningCustomerVMs -join "; "

                # Check for running customer VMs and stop them if the flag is passed. Exit if the flag is not passed.
                if ($runningCustomerVMs.count -ne 0) {
                    if ($PSBoundParameters -contains "shutdownCustomerVm") {
                        Write-PowerManagementLogMessage -Type WARNING -Message "Virtual machines for the VI domain '$sddcDomain' that are not covered by the script: '$runningCustomerVMs_string'. These VMs will be stopped in a random order since 'shutdownCustomerVm' flag is passed."
                        # TODO - Add check if VMware Tools are running in the customer VMs as a function.
                        # Stop Customer VMs with one call to VC:
                        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $clusterCustomerVMs -timeout 300


                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "Virtual machines for the VI domain '$sddcDomain' that are not covered by the script: '$runningCustomerVMs_string'. These VMs could not be stopped by the script."
                        Write-PowerManagementLogMessage -Type ERROR -Message "Please stop these VMs manually before proceeding with the shutdown process or pass 'shutdownCustomerVm' for random order shutdown."
                    }
                }

                # Shutdown NSX-T Edge Nodes
                if ($nsxtEdgeNodes) {
                    if ($NSXTSpannedAcrossWld) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "NSX-T is spanned across multiple Workload Domains. NSX-T Edge nodes be stopped with this Workload Domain."
                    }
                    $nsxtEdgeNodes_string = $nsxtEdgeNodes -join "; "
                    Write-PowerManagementLogMessage -Type INFO -Message "Stopping NSX-T Edge nodes '$nsxtEdgeNodes_string' ..."
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 300
                }

                # Shutdown NSX-T Managers
                if ($nsxtManagerPowerOnVMs -ne 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Stopping NSX-T Manager nodes '$nsxtNodes' ..."
                    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 300
                }

                # Get clusters that are still running from $ClusterStatusMapping and stop only those.
                $clustersToStop = $clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'UP' }
                if ($clustersToStop.count -eq 0) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "There are no suitable clusters to stop. Check above messages for more details. Exiting..."
                }
                # Handle case if forceRunOnClustersInErrorState is passed
                if ($PSBoundParameters.ContainsKey("forceRunOnClustersInErrorState")) {
                    Write-PowerManagementLogMessage -type WARNING -Message "Attempting to stop clusters in error state as well."
                    $clustersToStop = $clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'UP' -or $ClusterStatusMapping[$_.name] -eq 'ERROR' }
                }

                # All clusters shutdown starts here
                $($clustersToStop.Name) | ForEach-Object -ThrottleLimit $simultaneousClustersPowerOperation -Parallel {
                    # Put random sleep to avoid collisions during vCenter connection and log writing.
                    Start-Sleep -Seconds $(Get-Random -Minimum 1 -Maximum 60)

                    $cluster = $_
                    $esxiWorkloadCluster = $USING:esxiWorkloadCluster
                    $vcServer = $USING:vcServer
                    $vcUser = $USING:vcUser
                    $vcPass = $USING:vcPass
                    $logFile = $USING:logFile

                    # Check if Tanzu is enabled in the cluster
                    $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster
                    if ($status -eq $True) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Currently workload domains with vSphere with Tanzu are not supported for shutdown. Exiting..."
                        Exit
                    }

                    # Check the health and sync status of the vSAN cluster
                    if ((Test-VsanHealth -cluster $cluster -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Cluster health is good."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] The cluster isn't in a healthy state. Check your environment and run the script again."
                        # TODO - Log the error in another file and continue with the startup of other clusters.
                        #Exit
                    }
                    # Check the health and sync status of the vSAN cluster
                    if ((Test-VsanObjectResync -cluster $cluster -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                        # Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] vSAN object resynchronization has failed. Check your environment and run the script again."
                        Exit
                    }

                    # vSAN Cluster wizard
                    $powerOperationResult = Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster -PowerStatus "clusterPoweredOff"
                    # Check for errors during the shutdown operation
                    if ($null -ne $powerOperationResult) {
                        # TODO - Log the error in another file and continue with the startup of other clusters.
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Result of the power operation for cluster '$cluster': '$powerOperationResult'."
                    }

                    # Get status of the cluster after shutdown
                    $clusterPowerStatus = Get-VsanClusterPowerState -Cluster $cluster -Server $vcServer.fqdn
                    if ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOff" -and $clusterPowerStatus.TrackingTask -eq $null) {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Cluster '$cluster' is stopped."
                    } else {
                        #TODO - Log the error in another file and continue with the startup of other clusters.
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cluster '$cluster' is not stopped. Check the vSphere Client and run the script again."
                    }

                    # End of shutdown
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] ########################################################"
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] End of the shutdown sequence for '$cluster' !"
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] ########################################################"
                }

                # Check if all clusters are stopped
                if ($DefaultVIServer.Name -notcontains $vcServer.fqdn -or $DefaultVIServer.IsConnected -eq $false) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                }

                foreach ($cluster in $clusterDetails.Name) {
                    $clusterPowerStatus = Get-VsanClusterPowerState -Cluster $cluster -Server $vcServer.fqdn
                    if ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOff") {
                        $ClusterStatusMapping[$cluster] = 'DOWN'
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "Cluster '$($cluster)' is not stopped. Check the vSphere Client and run the script again."
                    }
                }
            }
        } else {
            #### Shutdown sequence for specific clusters - Under Development ###
            Write-PowerManagementLogMessage -Type ERROR -Message "This feature is under development. Do not provide individual clusters to shutdown all clusters in the VI domain."
            EXIT
            $clustersCount = $sddcClusterDetails.count
            $DownCount = 0
            $lastElement = $false

            foreach ($cluster in $clusterDetails) {
                foreach ($clusterDetail in $sddcClusterDetails) {
                    if ($ClusterStatusMapping[$clusterDetail.name] -eq 'DOWN') {
                        $DownCount += 1
                    }
                }
                if (($DownCount -eq ($clustersCount - 1)) -or ($DownCount -eq $clustersCount) ) {
                    $lastElement = $true
                    Write-PowerManagementLogMessage -Type INFO -Message "Last cluster of VSAN detected"
                }

                if ($ClusterStatusMapping[$cluster.name] -eq 'DOWN') {
                    Write-PowerManagementLogMessage -Type INFO -Message "Cluster '$($cluster.name)' is already stopped, hence proceeding with next cluster in the sequence"
                    Continue
                }

                Write-PowerManagementLogMessage -Type INFO -Message "Processing cluster '$($cluster.name)'..."

                # Check if the ESXi hosts are reachable
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                foreach ($esxiNode in $esxiDetails) {
                    if (!(Test-EndpointConnection -server $esxiNode.fqdn -port 443)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to communicate with ESXi host $($esxiNode.fqdn). Check the FQDN or IP address, or the power state. Exiting..."
                        Exit
                    }
                }

                $clusterVcfVMs = @()
                $clusterVclsVMs = @()
                # TODO If not specific cluster is passed - we should check for customer VMs in all clusters. In this way we will fail early if there are some VMs running and not managed by VCF.
                Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about all powered-on virtual machines for the specified vSphere cluster $($cluster.name)..."
                [Array]$clusterAllVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "VM" -powerstate "poweredon"
                Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about all powered-on vCLS virtual machines for a the specified vSphere cluster $($cluster.name)..."
                [Array]$clusterVclsVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon"
                foreach ($vm in $clusterVclsVMs) {
                    [Array]$clusterVcfVMs += $vm
                }
                $clusterVcfVMs += $vcServer.fqdn.Split(".")[0]

                if ($nsxtEdgeNodes) {
                    foreach ($node in $nsxtEdgeNodes) {
                        foreach ($element in $clusterAllVMs) {
                            if ( $element -like $node) {
                                $nsxtClusterEdgeNodes += $node
                                [Array]$clusterVcfVMs += $node
                                break
                            }
                        }
                    }
                }
                Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about all powered-on customer virtual machines for the specified vSphere cluster $($cluster.name)..."
                $clusterCustomerVMs = $clusterAllVMs | Where-Object { $vcfVMs -NotContains $_ }
                $clusterVcfVMs_string = $clusterVcfVMs -join "; "
                Write-PowerManagementLogMessage -Type INFO -Message "Management virtual machines covered by the script for the cluster $($cluster.name): '$($clusterVcfVMs_string)' ."
                if ($clusterCustomerVMs.count -ne 0) {
                    $clusterCustomerVMs_string = $clusterCustomerVMs -join "; "
                    Write-PowerManagementLogMessage -Type INFO -Message "Virtual machines for the cluster $($cluster.name) that are not covered by the script: '$($clusterCustomerVMs_string)'. These VMs will be stopped in a random order if the 'shutdownCustomerVm' flag is passed."
                }

                if ($clusterCustomerVMs.count -ne 0) {
                    $clusterCustomerVMs_string = $clusterCustomerVMs -join "; "
                    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                        # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
                        $VMwareToolsNotRunningVMs = @()
                        $VMwareToolsRunningVMs = @()
                        if ($DefaultVIServers) {
                            Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                        }
                        if ( Test-EndpointConnection -server $vcServer.fqdn -port 443 ) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                            Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                            if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get VMware Tools status."
                                foreach ($vm in $clusterCustomerVMs) {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Checking VMware Tools status for '$vm'..."
                                    $vm_data = Get-VM -Name $vm
                                    if ($vm_data.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
                                        [Array]$VMwareToolsRunningVMs += $vm
                                    } else {
                                        [Array]$VMwareToolsNotRunningVMs += $vm
                                    }
                                }
                            } else {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot to connect to vCenter Server '$($vcServer.fqdn)'. The command returned the following error: '$vcConnectError'."
                            }
                        }
                        # Disconnect from the VC
                        if ($DefaultVIServers) {
                            Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                        }
                        if ($VMwareToolsNotRunningVMs.count -ne 0) {
                            $noToolsVMs = $VMwareToolsNotRunningVMs -join "; "
                            Write-PowerManagementLogMessage -Type WARNING -Message "There are some VMs that are not managed by VMware Cloud Foundation where VMware Tools isn't running. Unable to shut down these VMs:'$noToolsVMs'."
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot proceed until these VMs are shut down manually. Shut them down manually and run the script again."
                            Exit
                        }

                        Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still powered on. -shutdownCustomerVm is passed to the script."
                        Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down VMs not managed by SDDC Manager to put the host in maintenance mode."
                        Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management VMs: '$clusterCustomerVMs_string'."
                        # Stop Customer VMs with one call to VC:
                        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $clusterCustomerVMs -timeout 300
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still powered on. -shutdownCustomerVm is not passed to the script."
                        Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down VMs that are not managed by VMware Cloud Foundation: '$clusterCustomerVMs_string'."
                        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot proceed until these VMs are shut down manually or the customer VM Shutdown option is set to true. Please take the necessary action and run the script again."
                        Exit
                    }
                }

                ## Gather NSX Edge Node Details from NSX-T Manager
                if (Test-EndpointConnection -server $vcServer.fqdn -port 443) {
                    if ($nsxtClusterEdgeNodes) {
                        # Testing
                        Write-Host "NSX Edge nodes to be stopped: $($nsxtClusterEdgeNodes -join ",")"
                        # Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtClusterEdgeNodes -timeout 600
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes found for a given cluster '$($cluster.name)' . Skipping edge nodes shutdown..."
                    }
                } else {
                    Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shut down. Skipping shutdown of $nsxtEdgeNodes..."
                }

                ## Shutdown the NSX Manager Nodes
                # Get info if NSX Manager is spanned across workloads
                # Check if it is the last cluster of the domain to shutdown
                # The below condition tells that we need to go ahead with NSX-T shutdown only under
                $allOtherVcDown = $true
                if ($NSXTSpannedAcrossWld) {
                    foreach ($VCnode in $nsxtSpannedAcrossWldVc) {
                        if ($VCnode -eq ($vcServer.fqdn)) {
                            continue
                        } else {
                            $checkServer = (Test-EndpointConnection -server $VCnode -port 443)
                            if ($checkServer) {
                                $allOtherVcDown = $false
                                break
                            }
                        }
                    }
                    if (-not $allOtherVcDown) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "NSX Manager is shared across workload domains. Some of the vCenter Server instances for these workload domains are still running. Hence, not shutting down NSX Manager at this point."
                    } else {
                        if ($lastElement) {
                            # Testing
                            Write-Host "NSX Manager nodes to be stopped: $($nsxtNodes -join ",")"
                            # Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 600
                        }
                    }
                } else {
                    if ($lastElement) {
                        # Testing
                        Write-Host "NSX Manager nodes to be stopped: $($nsxtNodes -join ",")"
                        # Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 600
                    }
                }

                # Check the health and sync status of the vSAN cluster
                if (Test-EndpointConnection -server $vcServer.fqdn -port 443) {
                    $RemoteVMs = @()
                    $RemoteVMs = Get-poweronVMsOnRemoteDS -server $vcServer.fqdn -user $vcUser -pass $vcPass -clustertocheck $cluster.name
                    if ($RemoteVMs.count -eq 0) {
                        Write-PowerManagementLogMessage -Type INFO -Message "All remote VMs are powered off."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Not all remote VMs are powered off : $($RemoteVMs.Name), Unable to proceed. Please stop the VMs running on vSAN HCI Mesh datastore shared by this cluster."
                    }
                    if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                        Write-PowerManagementLogMessage -Type INFO -Message "vSAN health is good."
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "The vSAN cluster isn't in a healthy state. Check the vSAN health status in vCenter Server '$($vcServer.fqdn)'. After vSAN health is restored, run the script again."
                        Write-PowerManagementLogMessage -Type WARNING -Message "If the script execution has reached ESXi vSAN shutdown previously, this warning is expected. Please continue by following the documentation of VMware Cloud Foundation. "
                        Write-PowerManagementLogMessage -Type ERROR -Message "The vSAN cluster isn't in a healthy state. Check the messages above for a solution."
                        Exit
                    }
                    if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                        # Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "There is an active vSAN object resynchronization operation. Check your environment and run the script again."
                        Exit
                    }
                } else {
                    Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shut down. Skipping the vSAN health check for cluster $($cluster.name)."
                }

                # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.

                $runningAllVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vm" -powerstate "poweredon" -silence
                $runningVclsVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon" -silence
                $runningVMs = $runningAllVMs | Where-Object { $runningVclsVMs -NotContains $_ }
                if ($vxRailDetails -ne "") {
                    $runningVMs = $runningAllVMs | Where-Object { $vcfVMs -NotContains $_ }
                }

                if ($runningVMs.count) {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                    Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed until all VMs are shut down. Shut them down manually and run the script again."
                    Write-PowerManagementLogMessage -Type ERROR -Message "The environment has running VMs: $($runningVMs). Could not continue with vSAN shutdown while there are running VMs. Exiting! "
                } else {

                    # vSAN or VxRail Manager shutdown wizard automation.
                    if ($vxRailDetails -ne "") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Invoke VxRail cluster shutdown $($vxRailDetails.fqdn) $vcUser, and $vcPass"
                        Invoke-VxrailClusterShutdown -server $vxRailDetails.fqdn -user $vcUser -pass $vcPass
                        Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 60 seconds before polling for ESXI hosts shutdown status check..."
                        Start-Sleep -s 60

                        $counter = 0
                        $sleepTime = 60 # in seconds

                        while ($counter -lt 1800) {
                            $successCount = 0
                            #Verify if all ESXi hosts are down in here to conclude End of Shutdown sequence
                            foreach ($esxiNode in $esxiDetails) {
                                if (Test-EndpointConnection -server $esxiNode.fqdn -port 443) {
                                    Write-PowerManagementLogMessage -Type WARNING -Message "$($esxiNode.fqdn) is still up. Sleeping for $sleepTime seconds before next check..."
                                } else {
                                    $successCount++
                                }
                            }
                            if ($successCount -eq $esxiDetails.count) {
                                Write-PowerManagementLogMessage -Type INFO -Message "All Hosts have been shutdown successfully!"
                                Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence!"
                                Exit
                            } else {
                                Start-Sleep -s $sleepTime
                                $counter += $sleepTime
                            }
                        }
                    } else {
                        # vSAN shutdown wizard automation.
                        Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOff
                        foreach ($esxiNode in $esxiDetails) {
                            if (Test-EndpointConnection -server $esxiNode.fqdn -port 443) {
                                Write-PowerManagementLogMessage -Type ERROR -Message "$($esxiNode.fqdn) is still up. Check the FQDN or IP address, or the power state of the '$($esxiNode.fqdn)'."
                                Exit
                            }
                        }
                    }

                    # Set Cluster as "Down"
                    $ClusterStatusMapping[$cluster.name] = 'DOWN'

                    # End of shutdown for the cluster
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                    Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for the specified cluster $($cluster.name)!"
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                }
            }
        }

        # Check if all clusters are stopped
        $allClustersStopped = $true
        foreach ($cluster in $clusterDetails) {
            if ($ClusterStatusMapping[$cluster.name] -ne 'DOWN') {
                $allClustersStopped = $false
                break
            }
        }

        # Stop vCenter Server if all clusters are stopped
        if ($allClustersStopped) {
            Write-PowerManagementLogMessage -Type INFO -Message "All clusters in the VI domain '$sddcDomain' are stopped."
            # TODO - Add check if NSX-T is topped before stopping the vCenter Server.
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
        } else {
            Write-PowerManagementLogMessage -Type WARNING -Message "Not all clusters in the VI domain '$sddcDomain' are stopped. vCenter server will not be stopped."
        }

        Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for the VI domain '$sddcDomain' !"

    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Startup procedures
Try {
    if ($WorkloadDomain.type -eq "MANAGEMENT") {
        Write-PowerManagementLogMessage -Type ERROR -Message "The specified workload domain '$sddcDomain' is the management domain. This script handles only VI workload domains. Exiting! "
        Exit
    }

    if ($PsBoundParameters.ContainsKey("startup")) {
        $nsxtManagerVIP = New-Object -TypeName PSCustomObject
        $nsxtManagerFQDN = ""

        # We are starting all vCenter Servers, since we need to get NSX details. SDDC Manager needs VC connection to build this knowledge.
        # NSX Manager should be started after the VC, so if NSX manager is spanned across WLDs, we need to start all VCs.
        # Start all vCenter Servers
        Write-PowerManagementLogMessage -Type INFO -Message "Checking if all vCenter Servers in all workload domains are started."
        foreach ($wldVC in $allWldVCs) {
            $vcStarted = (Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -powerstate "poweredon" -pattern $wldVC.Split(".")[0] -silence).count
            if (-not $vcStarted) {
                # Startup the Virtual Infrastructure Workload Domain vCenter Server
                Start-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $wldVC.Split(".")[0] -timeout 600
                Write-PowerManagementLogMessage -Type INFO -Message "Waiting for the vCenter Server services to start on '$($wldVC.Split(".")[0])'. It will take some time."
            } else {
                Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server '$($wldVC.Split(".")[0])' is already started"
            }
        }

        # Wait for all vCenter Servers to start
        $serviceStatus = 0
        foreach ($wldVC in $allWldVCs) {
            $retries = 20
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            While ($retries) {
                Connect-VIServer -Server $wldVC -User $vcUser -pass $vcPass -ErrorAction SilentlyContinue | Out-Null
                if ($DefaultVIServer.Name -eq $wldVC) {
                    # Max wait time for services to come up is 10 mins.
                    for ($i = 0; $i -le 10; $i++) {
                        $status = Get-VamiServiceStatus -server $wldVC -user $vcUser -pass $vcPass -service 'vsphere-ui' -nolog
                        if ($status -eq "STARTED") {
                            $serviceStatus += 1
                            break
                        } else {
                            Write-PowerManagementLogMessage -Type INFO -Message "The services on vCenter Server $wldVC are still starting. Please wait."
                            Start-Sleep -s 60
                        }
                    }
                    Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                    break
                }
                Start-Sleep -s 60
                $retries -= 1
                Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server is still starting. Please wait."
            }
        }

        if ($serviceStatus -ne $allWldVCs.count) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Not all vCenter Servers are started. Check the vCenter Server services and run the script again."
            Exit
        } else {
            Write-PowerManagementLogMessage -Type INFO -Message "All vCenter Servers are started."
        }

        # Start ESXi hosts here
        $timeoutForESXiConnection = 900 # 15 minutes
        # TODO - Add switch for this functionality
        #.\StartServers.ps1

        # TODO - Get clusters status after vCenter Server and ESXi hosts are started
        # Check if there are clusters in error state
        $ErrorCount = 0
        foreach ($cluster in $clusterDetails) {
            if ($ClusterStatusMapping[$cluster.name] -eq 'ERROR') {
                $ErrorCount += 1
            }
        }
        if ($ErrorCount -ne 0) {
            Write-PowerManagementLogMessage -Type WARNING -Message "$ErrorCount out of $($clusterDetails.count) clusters are in error state."
            Write-PowerManagementLogMessage -Type WARNING -Message "Clusters in error state: '$($($clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'ERROR' }).name -join "; ")'."
        }

        # Check if all clusters are already started
        $upCount = 0
        foreach ($cluster in $clusterDetails) {
            if ($ClusterStatusMapping[$cluster.name] -eq 'UP') {
                $upCount += 1
            }
        }
        Write-PowerManagementLogMessage -Type INFO -Message "$upCount out of $($clusterDetails.count) clusters are started."
        if ($upCount -eq $clusterDetails.count) {
            Write-PowerManagementLogMessage -Type INFO -Message "All clusters are already started. Skipping clusters startup."
        } else {
            # Start Clusters provided to the script that are in powerOff state
            $clustersToStart = $clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'DOWN' }
            # Handle case if forceRunOnClustersInErrorState is passed
            if ($PSBoundParameters.ContainsKey("forceRunOnClustersInErrorState")) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Attempting to start clusters in error state as well."
                $clustersToStart = $clusterDetails | Where-Object { $ClusterStatusMapping[$_.name] -eq 'DOWN' -or $ClusterStatusMapping[$_.name] -eq 'ERROR' }
            }

            $($clustersToStart.name) | ForEach-Object -ThrottleLimit $simultaneousClustersPowerOperation -Parallel {
                #Set-PowerCLIConfiguration -Scope Session -DefaultVIServerMode Single -Confirm:$false | Out-Null
                Start-Sleep -Seconds $(Get-Random -Minimum 1 -Maximum 60)
                $cluster = $_
                $esxiWorkloadCluster = $USING:esxiWorkloadCluster
                $vcServer = $USING:vcServer
                $vcUser = $USING:vcUser
                $vcPass = $USING:vcPass
                $timeoutForESXiConnection = $USING:timeoutForESXiConnection
                $logFile = $USING:logFile

                $esxiDetails = $($esxiWorkloadCluster[$cluster])
                # Wait till all ESXi hosts are connected to the vCenter Server
                $timeout = $timeoutForESXiConnection
                $sleepTime = 30
                $counter = 0
                while ($counter -lt $timeout) {
                    $connectedHosts = Get-PoweredOnHostsInCluster -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster
                    if ($connectedHosts.count -eq $esxiDetails.count) {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] All ESXi hosts from cluster '$cluster' are connected to the vCenter Server."
                        break
                    } else {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Waiting for all ESXi hosts to be connected to the vCenter Server. Sleeping for $sleepTime seconds before next check..."
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connected hosts: $($connectedHosts.count) out of $($esxiDetails.count)."
                        if ($connectedHosts.count -ne 0) {
                            Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connected ESXi hosts: '$($connectedHosts.name -join '; ')'."
                            $notConnectedESXiHosts = $esxiDetails.fqdn | Where-Object { $connectedHosts.name -notContains $_ }
                            Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Not connected ESXi hosts: '$($notConnectedESXiHosts -join '; ')'."
                        }
                        Start-Sleep -s $sleepTime
                        $counter += $sleepTime
                    }
                }
                # TODO - Check for timeout and log in separate file
                if ($counter -eq $timeout) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Timeout occurred while waiting for all ESXi hosts to be connected to the vCenter Server. Exiting..."
                    Exit
                }

                # Start vSAN Cluster wizard
                $powerOperationResult = Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster -PowerStatus clusterPoweredOn
                if ($null -ne $powerOperationResult) {
                    # TODO - Log the error in another file and continue with the startup of other clusters.
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Result of the power operation for cluster '$cluster': '$powerOperationResult'"
                }

                # Get status of the cluster after power on
                $clusterPowerStatus = Get-VsanClusterPowerState -Cluster $cluster -Server $vcServer.fqdn
                if ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOn") {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Cluster '$cluster' is powered on."
                } else {
                    #TODO - Log the error in another file and continue with the startup of other clusters.
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cluster '$cluster' is not powered on. Check the vSphere Client and run the script again."
                }

                # Check the health and sync status of the vSAN cluster
                if ((Test-VsanHealth -cluster $cluster -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Cluster health is good."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] The cluster isn't in a healthy state. Check your environment and run the script again."
                    # TODO - Log the error in another file and continue with the startup of other clusters.
                    #Exit
                }
                # Check the health and sync status of the vSAN cluster
                if ((Test-VsanObjectResync -cluster $cluster -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    # Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] vSAN object resynchronization has failed. Check your environment and run the script again."
                    Exit
                }
            }
        }

        # Get fresh token from SDDC manager
        $statusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ($statusMsg) { Write-PowerManagementLogMessage -Type INFO -Message $statusMsg }
        if ($warnMsg) { Write-PowerManagementLogMessage -Type WARNING -Message $warnMsg }
        if ($ErrorMsg) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg }

        # TODO - Check if clusters that are requested to start are actually started
        # Check if all clusters are started
        if ($DefaultVIServer.Name -notcontains $vcServer.fqdn -or $DefaultVIServer.IsConnected -eq $false) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
            Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
        }
        $allClustersStarted = 0
        foreach ($cluster in $clusterDetails.Name) {
            $clusterPowerStatus = Get-VsanClusterPowerState -Cluster $cluster -Server $vcServer.fqdn
            if ($clusterPowerStatus.CurrentClusterPowerStatus -eq "clusterPoweredOn") {
                Write-PowerManagementLogMessage -Type INFO -Message "Cluster '$cluster' is powered on."
                $allClustersStarted++
            } else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Cluster '$cluster' is not powered on. Check the vSphere Client and run the script again."
            }
        }

        if ($allClustersStarted -eq $clusterDetails.count) {
            Write-PowerManagementLogMessage -Type INFO -Message "All clusters are started."
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Not all clusters are started. Check the vSphere Client and run the script again."
            Exit
        }

        # Get NSX-T Details
        ## Gather NSX Manager Cluster Details
        $counter = 0
        $retries = 15
        $sleepTime = 30
        while ($counter -ne $retries) {
            Try {
                $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id -ErrorAction SilentlyContinue -InformationAction Ignore
            } Catch {
                Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still retrieving NSX-T Data Center information. Sleeping for $sleepTime seconds until the next check..."
                Start-Sleep -s $sleepTime
                $counter += 1
            }
            # Stop loop if we have FQDN for NSX-T VIP
            if ( $($nsxtCluster.vipFqdn) ) { Break }
            else {
                Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still retrieving NSX-T Data Center information. Sleeping for $sleepTime seconds until the next check..."
                Start-Sleep -s $sleepTime
                $counter += 1
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "SDDC Manager did not manage to retrieve NSX-T Data Center information. Please check the LCM log file for errors. Stopping the script execution!"
            Exit
        }
        $nsxtManagerFQDN = $nsxtCluster.vipFqdn

        $nsxtManagerVIP | Add-Member -Force -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).username
        $nsxtManagerVIP | Add-Member -Force -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).password
        $nsxtNodesFQDN = $nsxtCluster.nodes.fqdn
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesFQDN) {
            [Array]$nsxtNodes += $node.Split(".")[0]
            [Array]$vcfVMs += $node.Split(".")[0]
            [Array]$clusterVcfVMs += $node.Split(".")[0]

        }

        $nsxtStarted = 0
        foreach ($node in $nsxtNodes) {
            Write-PowerManagementLogMessage -Type INFO -Message "Checking if $node is already started."
            $nsxtStarted += (Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -powerstate "poweredon" -pattern $node -silence).count
        }
        if (-not ($nsxtStarted -eq $nsxtNodes.count)) {
            # Startup the NSX Manager Nodes for Virtual Infrastructure Workload Domain
            Start-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 600
            if (!(Wait-ForStableNsxtClusterStatus -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The NSX Manager cluster is not in 'STABLE' state. Exiting!"
                Exit
            }
        } else {
            Write-PowerManagementLogMessage -Type INFO -Message "NSX Manager is already started."
        }

        $($clusterDetails.name) | ForEach-Object -ThrottleLimit $simultaneousClustersPowerOperation -Parallel {
            Start-Sleep -Seconds $(Get-Random -Minimum 1 -Maximum 60)
            $cluster = $_
            $esxiWorkloadCluster = $USING:esxiWorkloadCluster
            $vcServer = $USING:vcServer
            $vcUser = $USING:vcUser
            $vcPass = $USING:vcPass
            $logFile = $USING:logFile

            # Waiting for vCLS VMs to be started for ($retries*10) seconds
            $counter = 0
            $retries = 30
            $sleepTime = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon" -cluster $cluster -folder "vcls" -silence).count
                if ( $powerOnVMcount -lt 3 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleepTime seconds until the next check..."
                    Start-Sleep -s $sleepTime
                    $counter += 1
                } else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                # TODO - Log in a separate file if there is an issue with VCLS VMs in any cluster.
                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] The vCLS VMs were not started within the expected time. Stopping script execution!"
                Exit
            }
        }

        # TODO - Get all NSX Edge Nodes from all clusters and start them.
        foreach ($cluster in $clusterDetails) {

            [Array]$clusterVclsVMs = @()
            [Array]$clusterVcfVMs = @()
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch virtual machines for the specified vSphere cluster $($cluster.name)..."
            [Array]$clusterAllVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "VM"
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about the vCLS virtual machines for the specified vSphere cluster $($cluster.name)..."
            [Array]$clusterVclsVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls"
            foreach ($vm in $clusterVclsVMs) {
                [Array]$clusterVcfVMs += $vm
            }
            $vcfVMs += $vcServer.fqdn.Split(".")[0]
            $clusterVcfVMs += $vcServer.fqdn.Split(".")[0]
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch information about customer virtual machines for the specified vSphere cluster $($cluster.name)..."
            $clusterCustomerVMs = $clusterAllVMs | Where-Object { $vcfVMs -NotContains $_ }

            # Gather NSX Edge Node Details and do the startup
            $nsxtClusterEdgeNodes = @()
            Try {
                [Array]$nsxtEdgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword -VCfqdn $vcServer.fqdn)
                foreach ($node in $nsxtEdgeNodes) {
                    foreach ($element in $clusterAllVMs) {
                        if ( $element -like $node) {
                            $nsxtClusterEdgeNodes += $node
                            [Array]$clusterVcfVMs += $node
                            break
                        }
                    }
                    [Array]$vcfVMs += $node
                }
            } Catch {
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot fetch information about NSX Edge nodes."
            }
            if ($nsxtClusterEdgeNodes.count -ne 0) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtClusterEdgeNodes -timeout 600
            } else {
                Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes found. Skipping edge nodes startup for vSAN cluster '$($cluster.name)'!"
            }

            # End of startup
            $vcfVMs_string = ""
            $vcfVMs_string = ($clusterVcfVMs | Select-Object -Unique) -join "; "

            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
            Write-PowerManagementLogMessage -Type INFO -Message "The following components have been started: $vcfVMs_string ."
            Write-PowerManagementLogMessage -Type INFO -Message "Check the list above and start any additional VMs, that are required, before you proceed with workload startup!"
            Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs"
            Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
            Write-PowerManagementLogMessage -Type INFO -Message "End of startup sequence for the cluster '$($cluster.name)'!"
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
        }
    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}
