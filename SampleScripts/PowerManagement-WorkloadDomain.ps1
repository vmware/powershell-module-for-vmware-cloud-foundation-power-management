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
    Initiates the startup of all clusters in the the Virtual Infrastructure Workload Domain 'sfo-w01'

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

#EndRegion  Non Exported Functions                                  ######
##########################################################################

$pass = Get-Password -User $user -Password $pass

# Error Handling (script scope function)
Function Debug-CatchWriterForPowerManagement {
    Param (
        [Parameter (Mandatory = $true)] [PSObject]$object
    )
    $ErrorActionPreference = 'Stop'
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-PowerManagementLogMessage -message " ERROR at Script Line $lineNumber"
    Write-PowerManagementLogMessage -message " Relevant Command: $lineText"
    Write-PowerManagementLogMessage -message " ERROR Message: $errorMessage"
    Write-Error -Message $errorMessage
}

# Customer Questions Section
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    if ($PsBoundParameters.ContainsKey("Shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Workload Domain." }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Workload Domain." }
    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Pre-Checks
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
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage }

    if (!(Test-EndpointConnection -server $server -Port 443)) {
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
            #$userShutdownOrder = $true
        }
        $allClusterShutdown = $false
        $hostsClusterMapping = @{}
        $sddcHostsClusterMapping = @{}
        $esxiWorkloadCluster = @{}
        $ClusterStatusMapping = @{}



        if ($workloadDomain.clusters.id.count -gt 1) {
            Write-PowerManagementLogMessage -Type INFO -Message "There are multiple clusters in VI domain '$sddcDomain'."
        }
        foreach ($id in $($workloadDomain.clusters.id)) {
            $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
            $sddcClusterDetails += $clusterData
            $sddcHostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
            $sddcClusterArray += $clusterData.name
            $esxiWorkloadCluster[$clusterData.name] = @()
        }
        Write-PowerManagementLogMessage -Type INFO -Message "Clusters in SDDC Manager database: $($sddcClusterArray -join ",")"

        if ($vsanCluster) {
            foreach ($name in $userClusterArray) {
                $clusterData = (Get-VCFCluster | Where-Object { $_.name -eq ($name) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
                $userClusterDetails += $clusterData

            }
            $clusterDetails = $userClusterDetails
            if (($userClusterDetails.count -eq $sddcClusterDetails.count) -and (((Compare-Object $userClusterDetails $sddcClusterDetails -IncludeEqual | Where-Object -FilterScript { $_.SideIndicator -eq '==' }).InputObject).count -eq $sddcClusterDetails.count)) {
                Write-PowerManagementLogMessage -Type INFO -Message "All cluster-related information is correct."
                $allClusterShutdown = $true
            }
            if (((Compare-Object $sddcClusterArray $userClusterArray -IncludeEqual | Where-Object -FilterScript { $_.SideIndicator -eq '=>' }).InputObject).count) {
                $wrongClusterNames = (Compare-Object $sddcClusterArray $userClusterArray -IncludeEqual | Where-Object -FilterScript { $_.SideIndicator -eq '=>' }).InputObject
                Write-PowerManagementLogMessage -Type WARNING -Message "A wrong cluster name has been passed."
                Write-PowerManagementLogMessage -Type WARNING -Message "The known clusters, part of this workload domain are:$($sddcClusterDetails.name)"
                Write-PowerManagementLogMessage -Type WARNING -Message "The cluster names passed are: $userClusterArray"
                Write-PowerManagementLogMessage -Type WARNING -Message "Clusters not matching the SDDC Manager database:  $wrongClusterNames"
                Write-PowerManagementLogMessage -Type ERROR -Message "Please cross check and run the script again. Exiting!"
            }
            Write-PowerManagementLogMessage -Type INFO -Message "All clusters to be taken care of: '$allClusterShutdown'"
        } else {
            foreach ($id in $($workloadDomain.clusters.id)) {
                $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
            }
            $clusterDetails = $sddcClusterDetails
            $allClusterShutdown = $true
        }

        # Check the SDDC Manager version if VCF less than or greater than VCF 5.0
        $vcfVersion = Get-VCFManager | Select-Object version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object { $_.matches.groups[0].value }
        if ([float]$vcfVersion -lt [float]5.0) {
            # Gather vCenter Server Details and Credentials
            $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
            $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
            $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

            # We are using same user name and password for both workload and management vc
            $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id) })
            $mgmtVcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
            $mgmtVcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password
        } else {
            # Gather Workload vCenter Server Details and Credentials
            $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
            $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).username
            $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).password

            # Gather Management vCenter Server Details and Credentials
            $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id) })
            $mgmtVcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($managementDomain.ssoId) }).username
            $mgmtVcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($managementDomain.ssoId) }).password
        }

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

        if ($PsBoundParameters.ContainsKey("shutdown")) {
            foreach ($clusterName in $sddcHostsClusterMapping.keys) {
                $name = $clusterName
                $hostsName = @()
                $hostsIds = $sddcHostsClusterMapping[$clusterName]
                foreach ($id in $hostsIds) {
                    $hostsName += (Get-VCFHost | Where-Object id -EQ $id).fqdn
                }
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                if ( Test-EndpointConnection -server $vcServer.fqdn -port 443 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                    if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                        Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get host status..."
                        $HostsInMaintenanaceOrDisconnectedState = Get-VMHost $hostsName | Where-Object { ($_.ConnectionState -eq 'Maintenance') -or ($_.ConnectionState -eq 'NotResponding') -or ($_.ConnectionState -eq 'Disconnected') }
                        if ( $HostsInMaintenanaceOrDisconnectedState.count -eq $sddcHostsClusterMapping[$clusterName].count) {
                            $ClusterStatusMapping[$clusterName] = 'DOWN'
                        } else {
                            $ClusterStatusMapping[$clusterName] = 'UP'
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check the console output for more details."
                    }

                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check your environment and try again"
                }
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
            [Array]$vcfVMs += $node.Split(".")[0]
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

        # From here the looping of all clusters begin.
        $count = $sddcClusterDetails.count
        $index = 1
        $DownCount = 0
        $lastElement = $false

        # TODO Add check if clusters are vSAN or not.
        # TODO Add support for non-vSAN clusters.
        foreach ($cluster in $clusterDetails) {
            foreach ($clusterDetail in $sddcClusterDetails) {
                if ($ClusterStatusMapping[$clusterDetail.name] -eq 'DOWN') {
                    $DownCount += 1
                }
            }
            if (($DownCount -eq ($count - 1)) -or ($DownCount -eq $count) ) {
                $lastElement = $true
                Write-PowerManagementLogMessage -Type INFO -Message "Last cluster of VSAN detected"
            }

            if ($ClusterStatusMapping[$cluster.name] -eq 'DOWN') {
                Write-PowerManagementLogMessage -Type INFO -Message "Cluster '$($cluster.name)' is already stopped, hence proceeding with next cluster in the sequence"
                Continue
            }

            Write-PowerManagementLogMessage -Type INFO -Message "Processing cluster '$($cluster.name)'..."

            $esxiDetails = $esxiWorkloadCluster[$cluster.name]

            # Check the SDDC Manager version if VCF >=4.5 or vcf4.5
            $vcfVersion = Get-VCFManager | Select-Object version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object { $_.matches.groups[0].value }
            if ([float]$vcfVersion -lt [float]4.5) {
                # For versions prior VCF 4.5
                # Check if SSH is enabled on the esxi hosts before proceeding with shutdown procedure
                Try {
                    foreach ($esxiNode in $esxiWorkloadDomain) {
                        if (Test-VsphereConnection -server $esxiNode) {
                            $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                            if (-Not $status) {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to establish an SSH connection to ESXi host $($esxiNode.fqdn). SSH is not enabled. Exiting..."
                                Exit
                            }
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to connect to ESXi host $($esxiNode.fqdn). Exiting..."
                            Exit
                        }
                    }
                } Catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message $_.Exception.Message
                    Exit
                }
            } else {
                foreach ($esxiNode in $esxiDetails) {
                    if (!(Test-EndpointConnection -server $esxiNode.fqdn -port 443)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to communicate with ESXi host $($esxiNode.fqdn). Check the FQDN or IP address, or the power state. Exiting..."
                        Exit
                    }
                }
                # Check Lockdown Mode
                Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            }
            # Check if Tanzu is enabled in WLD
            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            if ($status -eq $True) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Currently workload domains with vSphere with Tanzu are not supported. Exiting..."
                Exit
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

            # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
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
            }

            if ($clusterCustomerVMs.count -ne 0) {
                $clusterCustomerVMs_string = $clusterCustomerVMs -join "; "
                if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
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
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtClusterEdgeNodes -timeout 600
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
                        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 600
                    }
                }
            } else {
                if ($lastElement) {
                    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $nsxtNodes -timeout 600
                }
            }

            ## The below block was supposed to be only for verison < 4.5, but due to the bug in 4.5
            ## vcls vms are not handled automatically though expected in vcf4.5
            ## Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
            if (Test-EndpointConnection -server $vcServer.fqdn -port 443) {
                Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable
            } else {
                Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shut down. Skipping putting the cluster in retreat mode..."
            }

            # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take some time, please wait..."
            $counter = 0
            $retries = 10
            $sleepTime = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon" -silence).count
                if ( $powerOnVMcount ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Some vCLS VMs are still running. Sleeping for $sleepTime seconds until next check..."
                    Start-Sleep -s $sleepTime
                    $counter += 1
                } else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not shut down within the expected time. Stopping the script execution."
                Exit
            }

            # Check the health and sync status of the vSAN cluster
            if (Test-EndpointConnection -server $vcServer.fqdn -port 443) {
                if ([float]$vcfVersion -gt [float]4.4) {
                    $RemoteVMs = @()
                    $RemoteVMs = Get-poweronVMsOnRemoteDS -server $vcServer.fqdn -user $vcUser -pass $vcPass -clustertocheck $cluster.name
                    if ($RemoteVMs.count -eq 0) {
                        Write-PowerManagementLogMessage -Type INFO -Message "All remote VMs are powered off."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Not all remote VMs are powered off : $($RemoteVMs.Name), Unable to proceed. Please stop the VMs running on vSAN HCI Mesh datastore shared by this cluster."
                    }
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
            if ([float]$vcfVersion -lt [float]4.5) {
                # VCF before version 4.5
                $runningVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vm" -powerstate "poweredon" -silence
            } else {
                $runningAllVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vm" -powerstate "poweredon" -silence
                $runningVclsVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon" -silence
                $runningVMs = $runningAllVMs | Where-Object { $runningVclsVMs -NotContains $_ }
                if ($vxRailDetails -ne "") {
                    $runningVMs = $runningAllVMs | Where-Object { $vcfVMs -NotContains $_ }
                }
            }
            if ($runningVMs.count) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed until all VMs are shut down. Shut them down manually and run the script again."
                Write-PowerManagementLogMessage -Type ERROR -Message "The environment has running VMs: $($runningVMs). Could not continue with vSAN shutdown while there are running VMs. Exiting! "
            } else {

                if ([float]$vcfVersion -lt [float]4.5) {
                    # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
                    if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!"
                    }

                    ## Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
                    # Disable cluster member updates from vCenter Server
                    foreach ($esxiNode in $esxiDetails) {
                        Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
                    }
                    # Run vSAN cluster preparation - should be done on one host per cluster
                    # Sleeping 1 min before starting the preparation
                    Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for one minute..."
                    Start-Sleep -s 60
                    Invoke-EsxCommand -server $esxiDetails.fqdn[0] -user $esxiDetails.username[0] -pass $esxiDetails.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
                    # Putting hosts in maintenance mode
                    foreach ($esxiNode in $esxiDetails) {
                        Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
                    }

                    ## TODO Add ESXi shutdown here
                } else {

                    # Check if hosts are in maintainence mode before cluster stop
                    foreach ($esxiNode in $esxiDetails) {
                        $hostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if ($hostConnectionState -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type ERROR -Message "$($esxiNode.fqdn) is in maintenance mode before cluster shutdown. Automation could not proceed. Check the vSphere Client for more details ."
                            Exit
                        }
                    }
                    $esxiDetails = $esxiWorkloadCluster[$cluster.name]

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
                }
                if ($lastElement) {
                    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
                }
                $ClusterStatusMapping[$cluster.name] = 'DOWN'

                # End of shutdown
                if ([float]$vcfVersion -lt [float]4.5) {
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                    Write-PowerManagementLogMessage -Type INFO -Message "Note: ESXi hosts are still powered on. Please stop them manually."
                    Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for the specified cluster $($cluster.name)!"
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                    Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for the specified cluster $($cluster.name)!"
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################"
                }
            }
        }
        $index += 1
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
        $count = $sddcClusterDetails.count
        $vcfVersion = Get-VCFManager | Select-Object version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object { $_.matches.groups[0].value }
        if ([float]$vcfVersion -lt [float]4.5) {
            foreach ($cluster in $clusterDetails) {
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                # Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
                Try {
                    foreach ($esxiNode in $esxiDetails) {
                        $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if (-Not $status) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it."
                            Exit
                        }
                    }
                } Catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn), If SSH is not enabled, follow the steps in the documentation to enable it."
                }

                # Take hosts out of maintenance mode
                foreach ($esxiNode in $esxiDetails) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
                }
            }

            foreach ($cluster in $clusterDetails) {
                # Prepare the vSAN cluster for startup - Performed on a single host only
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                Invoke-EsxCommand -server $esxiDetails.fqdn[0] -user $esxiDetails.username[0] -pass $esxiDetails.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"
            }
            foreach ($cluster in $clusterDetails) {
                # Enable vSAN cluster member updates
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                foreach ($esxiNode in $esxiDetails) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                }
            }
            foreach ($cluster in $clusterDetails) {
                # Check ESXi status for each host
                Write-PowerManagementLogMessage -Type INFO -Message "Checking the vSAN status of the ESXi hosts...."
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                foreach ($esxiNode in $esxiDetails) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                }
            }
        }
        foreach ($cluster in $clusterDetails) {
            $esxiDetails = $esxiWorkloadCluster[$cluster.name]
            # TODO - Do not run this for each cluster - we need to run it once per WLD.
            # We are starting all vCenter Servers, since we need to get NSX details. SDDC Manager needs VC connection to build this knowledge.
            # NSX Manager should be started after the VC, so if NSX manager is spanned across WLDs, we need to start all VCs.
            Write-PowerManagementLogMessage -Type INFO -Message "Checking if all vCenter Servers in all workload domains are started."
            $serviceStatus = 0
            foreach ($wldVC in $allWldVCs) {
                $vcStarted = (Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -powerstate "poweredon" -pattern $wldVC.Split(".")[0] -silence).count
                if (-not $vcStarted) {
                    # Startup the Virtual Infrastructure Workload Domain vCenter Server
                    Start-CloudComponent -server $mgmtVcServer.fqdn -user $mgmtVcUser -pass $mgmtVcPass -nodes $wldVC.Split(".")[0] -timeout 600
                    Write-PowerManagementLogMessage -Type INFO -Message "Waiting for the vCenter Server services to start on '$($wldVC.Split(".")[0])'. It will take some time."
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server '$($wldVC.Split(".")[0])' is already started"
                }
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
                        if (([float]$vcfVersion -lt [float]4.5) -and ($wldVC -eq $vcServer.fqdn)) {
                            # Workaround for ESXis that do not communicate their Maintenance status to vCenter Server
                            foreach ($esxiNode in $esxiDetails) {
                                if ((Get-VMHost -Name $esxiNode.fqdn).ConnectionState -eq "Maintenance") {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Performing exit maintenance mode on '$($esxiNode.fqdn)' from vCenter Server."
                                    (Get-VMHost -Name $esxiNode.fqdn | Get-View).ExitMaintenanceMode_Task(0) | Out-Null
                                }
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

            if ($serviceStatus -eq $allWldVCs.count) {
                Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server has been started successfully."
                if ([float]$vcfVersion -gt [float]4.4) {
                    #Start ESXi hosts here
                    # TODO - Check if this workaround is needed for VCF 5.1 and newer.
                    Write-Host ""
                    $warningString = ""
                    if ($sddcClusterDetails.count -eq 1) {
                        $warningString = "==========================================================`n"
                        $warningString += "Please start all the ESXi hosts belonging to the cluster '$($cluster.name)' and wait for the host console to come up. Once done, please enter yes`n"
                        $warningString += "==========================================================`n"
                    } else {
                        $warningString = "==========================================================`n"
                        $warningString += "1) Please start all the ESXi hosts belonging to the cluster '$($cluster.name)'`n"
                        $warningString += "2) Also, verify that 'Restart cluster' option(Right-click the cluster and navigate to vSAN) is available in vSphere UI for the cluster '$($cluster.name)'.`n"
                        $warningString += "3) If it is not available, refer scenario 3 in https://kb.vmware.com/s/article/87350 and perform its workaround as mentioned'`n"
                        $warningString += "Once all the above points are taken care, please enter yes`n"
                        $warningString += "==========================================================`n"
                    }
                    $proceed = Read-Host $warningString
                    if (-Not $proceed) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence stopping script execution."
                        Exit
                    } else {
                        if (($proceed -match "no") -or ($proceed -match "yes")) {
                            if ($proceed -match "no") {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'."
                                Exit
                            }
                        } else {
                            Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string - either 'Yes' or 'No'."
                            Exit
                        }
                    }

                    $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                    foreach ($esxiNode in $esxiDetails) {
                        if (!(Test-EndpointConnection -server $esxiNode.fqdn -port 443)) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with the host $($esxiNode.fqdn). Check the FQDN or IP address, or the power state of '$($esxiNode.fqdn)'."
                            Exit
                        }
                    }

                    # Check if Lockdown Mode is enabled on ESXi hosts
                    Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
                    # Start vSAN Cluster wizard
                    # TODO - Add check if the cluster is vSAN or not.
                    Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOn

                    # Check if host are out of maintenance mode after cluster restart
                    foreach ($esxiNode in $esxiDetails) {
                        $hostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if ($hostConnectionState -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type ERROR -Message "$($esxiNode.fqdn) is still in maintenance mode even after cluster restart. Check the vSphere Client and take the necessary actions."
                            Exit
                        }
                    }
                }
                if ((Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Cluster health is good."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "The cluster isn't in a healthy state. Check your environment and run the script again."
                    Exit
                }
                # Check the health and sync status of the vSAN cluster
                if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    # Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization has failed. Check your environment and run the script again."
                    Exit
                }

                if ([float]$vcfVersion -lt [float]4.5) {
                    # Start vSphere HA to avoid triggering a "Cannot find vSphere HA master agent" error.
                    if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'. Exiting!"
                    }
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Some of the vCenter Server instances are not started. Check the vSphere Client for more details and run the script again after all vCenter Server instances are up and running."
                Exit
            }
        }
        # Workaround for IAM service not starting vCLS VMs
        # TODO Check if this is still required for VCF 5.1 and newer. This workaround have an issue with Non vSAN Clusters.
        foreach ($cluster in $clusterDetails) {
            # Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
            Set-RetreatMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS startup will take some time. Please wait! "
        }

        $index = 1
        foreach ($cluster in $clusterDetails) {
            # Waiting for vCLS VMs to be started for ($retries*10) seconds
            $counter = 0
            $retries = 30
            $sleepTime = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon" -cluster $cluster.name -folder "vcls" -silence).count
                if ( $powerOnVMcount -lt 3 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleepTime seconds until the next check..."
                    Start-Sleep -s $sleepTime
                    $counter += 1
                } else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not started within the expected time. Stopping script execution!"
                Exit
            }
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

            if ($index -eq 1) {
                # Get fresh token from SDDC manager
                $statusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ($statusMsg) { Write-PowerManagementLogMessage -Type INFO -Message $statusMsg } if ($warnMsg) { Write-PowerManagementLogMessage -Type WARNING -Message $warnMsg } if ($ErrorMsg) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg }

                # Get NSX-T Details once VC is started
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
            }

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
            if ([float]$vcfVersion -lt [float]4.5) {
                Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability has been enabled by the script. Disable it per your environment's design."
            }
            Write-PowerManagementLogMessage -Type INFO -Message "Check the list above and start any additional VMs, that are required, before you proceed with workload startup!"
            Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs"
            Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
            if ([float]$vcfVersion -lt [float]4.5) {
                Write-PowerManagementLogMessage -Type WARNING -Message "If you have enabled SSH for the ESXi hosts through SDDC manager, disable it at this point."
            }
            if ([float]$vcfVersion -gt [float]4.4) {
                Write-PowerManagementLogMessage -Type WARNING -Message "If you have disabled lockdown mode for the ESXi hosts in workload cluster, you can enable it at this point."
            }
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
            Write-PowerManagementLogMessage -Type INFO -Message "End of startup sequence for the cluster '$($cluster.name)'!"
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
            $index += 1
        }
    }
} Catch {
    Debug-CatchWriterForPowerManagement -object $_
}
