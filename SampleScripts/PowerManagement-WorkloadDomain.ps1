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
    .Version:       1.0 (Build 1000)
    .Date:          2022-28-06
    ===============================================================================================================

    .CHANGE_LOG

    - 0.6.0   (Gary Blake / 2022-02-22) - Initial release
    - 1.0.0.1000   (Gary Blake / 2022-28-06) - GA version

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
    [Parameter (Mandatory = $false, ParameterSetName = "startup")]
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Array]$vsanCluster,
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [Switch]$startup,
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdown
)

# Customer Questions Section
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    if ($PsBoundParameters.ContainsKey("Shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Workload Domain." }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Workload Domain." }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Pre-Checks
Try {
    $Global:ProgressPreference = 'SilentlyContinue'
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass ******* -sddcDomain $sddcDomain"
    if ($PsBoundParameters.ContainsKey("vsanCluster")) { $str2 = $str2 + " -vsanCluster " +  ($vsanCluster -join ",")}
    if ($PsBoundParameters.ContainsKey("startup")) { $str2 = $str2 + " -startup" }
    if ($PsBoundParameters.ContainsKey("shutdown")) { $str2 = $str2 + " -shutdown" }
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile" -Colour Yellow
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage -Colour Yellow }

    if (!(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with SDDC Manager ($server). Check the FQDN or IP address or power state of the '$server'." -Colour Red
        Exit
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } 
        if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Cyan } 
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC Manager has been validated successfully."-Colour Green
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Gather details from SDDC Manager
Try {
    $original_flow = $false
    Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details..."
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ($StatusMsg) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } if ($WarnMsg) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ($ErrorMsg) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from the SDDC Manager inventory... It will take some time."

        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $allWld = Get-VCFWorkloadDomain | Where-Object { ($_.Type -ne "MANAGEMENT") }
        $allWldVCs = $allWld.vcenters.fqdn
        if ([string]::IsNullOrEmpty($workloadDomain)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Domain $sddcDomain doesn't exist. Check your environment and try again. " -Colour Red
            Exit
        }
        # Check if there are multiple clusters in the WLD
        #$sddcShutdownOrder = $false
        #$userShutdownOrder = $false
        $sddcClusterDetails = @()
        $userClusterDetails = @()
        $ClusterDetails = @()
        $userClusterarray = @()
        $SDDCclusterarray = @()
        if ($vsanCluster) {
            $userClusterarray = $vsanCluster.split(",")
            #$userShutdownOrder = $true
        }
        $multiClusterEnvironment = $false
        $allClusterShutdown = $false
        $hostsClusterMapping = @{}
		$sddchostsClusterMapping = @{}
        $esxiWorkloadCluster = @{}
        $ClusterStatusMapping = @{}



        if ($workloadDomain.clusters.id.count -gt 1) {
            $multiClusterEnvironment = $true
            Write-PowerManagementLogMessage -Type INFO -Message "There are multiple clusters in VI domain '$sddcDomain'."
        }
        foreach ($id in $($workloadDomain.clusters.id))  {
            $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
            $sddcClusterDetails += $clusterData
            $sddchostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
            $sddcClusterarray += $clusterData.name
            $esxiWorkloadCluster[$clusterData.name] = @()
        }
        Write-PowerManagementLogMessage -Type INFO -Message "The clusters got from SDDC: $($sddcClusterarray -join ",")"

        if($vsanCluster) {
            foreach ($name in $userClusterarray)  {
                $clusterData = (Get-VCFCluster | Where-Object { $_.name -eq ($name) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
                #$esxiWorkloadCluster[$clusterData.name] = @()
                $userClusterDetails += $clusterData

            }
            $ClusterDetails = $userClusterDetails
            if (($userClusterDetails.count -eq $sddcClusterDetails.count) -and (((Compare-Object $userClusterDetails $sddcClusterDetails -IncludeEqual | Where-Object -FilterScript {$_.SideIndicator -eq '=='}).InputObject).count -eq $sddcClusterDetails.count)) {
                Write-PowerManagementLogMessage -Type INFO -Message "User has passed all clusters information correctly" -colour green
                $allClusterShutdown = $true
            }
            if(((Compare-Object $sddcClusterarray $userClusterarray -IncludeEqual | Where-Object -FilterScript {$_.SideIndicator -eq '=>'}).InputObject).count){
                $wrongClusterNames = (Compare-Object $sddcClusterarray $userClusterarray -IncludeEqual | Where-Object -FilterScript {$_.SideIndicator -eq '=>'}).InputObject
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like some wrong cluster name being passed" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The clusters part of this domain and got from SDDC are:$($sddcClusterDetails.name)" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The cluster names passed by User are: $userClusterarray" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The wrong cluster names are:  $wrongClusterNames" -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "Please cross check and re-trigger the run. Exiting for now" -Colour Red
            }
            Write-PowerManagementLogMessage -Type INFO -Message "All clusters to be taken care: '$allClusterShutdown'"
        } else {
            foreach ($id in $($workloadDomain.clusters.id))  {
                $clusterData = (Get-VCFCluster | Where-Object { $_.id -eq ($id) })
                $hostsClusterMapping.($clusterData.name) = $clusterData.hosts.id
                #$esxiWorkloadCluster[$clusterData.name] = @()
            }
            $ClusterDetails = $sddcClusterDetails
            $allClusterShutdown = $true
            #$sddcShutdownOrder = $true
        }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
        $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

        # We are using same user name and password for both workload and management vc
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id) })
        $mgmtvcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $mgmtvcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

        #[Array]$allvms = @()
        [Array]$vcfvms = @()
        [Array]$vcfvms += ($vcServer.fqdn).Split(".")[0]

        # Gather ESXi Host Details for the VI Workload Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id })) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost.fqdn
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost.fqdn -and $_.accountType -eq "USER" })).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost.fqdn -and $_.accountType -eq "USER" })).password
            $esxiWorkloadDomain += $esxDetails
            #Gather ESXi Host to Cluster mapping info for the given VI Workload domain
            foreach ($clustername in $sddchostsClusterMapping.keys) {
                if ($sddchostsClusterMapping[$clustername] -contains $esxiHost.id) {
                    $esxiWorkloadCluster[$clustername] += $esxDetails
                }
            }
        }

        if ($PsBoundParameters.ContainsKey("shutdown")) {
            foreach ($ClusterName in $sddchostsClusterMapping.keys) {
				$name = $ClusterName
                $hostsName = @()
                $hostsIds = $sddchostsClusterMapping[$ClusterName]
                foreach ($id in $hostsIds) {
                    $hostsName += (get-vcfhost | where id -eq $id).fqdn
                }
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                if (( Test-NetConnection -ComputerName $vcServer.fqdn -Port 443 ).TcpTestSucceeded) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                    if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                        Write-PowerManagementLogMessage -type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get Host Status."
                        $HostsInMaintenanaceOrDisconnectedState = Get-VMHost $hostsName | Where-Object {($_.ConnectionState -eq 'Maintenance') -or ($_.ConnectionState -eq 'NotResponding') -or ($_.ConnectionState -eq 'Disconnected')}
                        $HostsInConnectedMode = Get-VMHost $hostsName | Where-Object {$_.ConnectionState -eq 'Connected'}
                        $HostsInDisconnectedMode = Get-VMHost $hostsName | Where-Object {$_.ConnectionState -eq 'Disconnected'}
                        if ( $HostsInMaintenanaceOrDisconnectedState.count -eq $sddchostsClusterMapping[$ClusterName].count) {
                            $ClusterStatusMapping[$ClusterName] = 'DOWN'
                        } else {
                            $ClusterStatusMapping[$ClusterName] = 'UP'
                        }
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check the console output for more details." -Colour Red
                    }

                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$($vcServer.fqdn)' has failed. Check your environment and try again" -Colour Red
                }
            }
        }
        # We will get NSX-T details in the respective startup/shutdown sections below.
    }
    else {
        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to vcenter server ($($vcServer.fqdn)). Check your credentials." -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Run the Shutdown procedures
Try {
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        # Get NSX-T Details
        ## Gather NSX Manager Cluster Details
        $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and  $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).password
        $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
            [Array]$vcfvms += $node.Split(".")[0]
        }

        #Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on virtual machines from vCenter Server $($vcServer.fqdn)..."
        #[Array]$allvms = Get-VMsWithPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon"
        #$customervms = @()
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on vCLS virtual machines from vCenter Server $($vcServer.fqdn)..."
        [Array]$vclsvms += Get-VMsWithPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon"-pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence
        foreach ($vm in $vclsvms) {
            [Array]$vcfvms += $vm
        }

        #Check if NSX-T manager VMs are running. If they are stopped skip NSX-T edge shutdown
        $nsxManagerPowerOnVMs = 0
        foreach ($nsxtManager in $nsxtNodes) {
            $state = Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch -powerstate "poweredon"
            if ($state) { $nsxManagerPowerOnVMs += 1 }
            # If we have all NSX-T managers running or minimum of 2 nodes up - query NSX-T for edges.
            if (($nsxManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxManagerPowerOnVMs -eq 2)) {
                $statusOfNsxtClusterVMs = 'running'
            }
        }

        $nxtClusterEdgeNodes = @()
        if ($statusOfNsxtClusterVMs -ne 'running') {
            Write-PowerManagementLogMessage -Type WARNING -Message "NSX Manager VMs have been stopped. NSX Edge VMs will not be handled in am automatic way." -Colour Cyan
        }
        else {
            Try {
                [Array]$nsxtEdgeNodes = Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $vcServer.fqdn
                foreach ($node in $nsxtEdgeNodes) {
                     [Array]$vcfvms += $node
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Unable to fetch NSX Edge node information from NSX Manager '$nsxtMgrfqdn'. Exiting!" -Colour Red
            }
        }


        #$customervms = $allvms | ? { $vcfvms -notcontains $_ }
        $vcfvms_string = $vcfvms -join "; "

        #This variable holds True of False based on if NSX-T is spanned across workloads or not.
        $NSXTSpannedAcrossWldVCArray = Get-NSXTComputeManger -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword
        $NSXTSpannedAcrossWld = $NSXTSpannedAcrossWldVCArray.count -gt 1

        #From here the looping of all clusters begin.
        $count = $sddcClusterDetails.count
        $index = 1
        $DownCount = 0
        $lastelement = $false


        foreach ($cluster in $ClusterDetails) {
            foreach ($clusterdetail in $sddcClusterDetails) {
                if ($ClusterStatusMapping[$clusterdetail.name] -eq 'DOWN') {
                    $DownCount += 1
                }
            }
            if (($DownCount -eq ($count -1)) -or ($DownCount -eq $count) ) {
                $lastelement = $true
				Write-PowerManagementLogMessage -Type INFO -Message "Last cluster of VSAN detected"
            }

            if ($ClusterStatusMapping[$cluster.name] -eq 'DOWN') {
                Write-PowerManagementLogMessage -Type INFO -Message "Cluster '$($cluster.name)' is already down, hence proceeding with next cluster in the sequence" -Colour GREEN
                Continue
            }

            $esxiDetails = $esxiWorkloadCluster[$cluster.name]

            ###This is where I need to check on the version thing if VCF >=4.5 or vcf4.5
            $SDDCVer = Get-vcfmanager | select version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object {$_.matches.groups[0].value}
            if ([float]$SDDCVer -lt [float]4.5) {
                #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
                Try {
                    foreach ($esxiNode in $esxiDetails) {
                        $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if (-Not $status) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                        }
                    }
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn), If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                }
            } else {
                   #lockin mode if any enabled on any host, we have to exit then and there
                   Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            }
            # Check if Tanzu is enabled in WLD
            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            if ($status -eq $True) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Currently we do not support workload domains with vSphere with Tanzu. Exiting." -Colour Red
            }

            $clustervcfvms = @()
            $clustervclsvms = @()
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on virtual machines for a given vsphere cluster $($cluster.name)..."
            [Array]$clusterallvms = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "VM" -powerstate "poweredon"
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on vCLS virtual machines for a given vsphere cluster $($cluster.name)..."
            [Array]$clustervclsvms = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon"
            foreach ($vm in $clustervclsvms) {
                [Array]$clustervcfvms += $vm
            }
            $clustervcfvms += $vcServer.fqdn.Split(".")[0]

            if ($nsxtEdgeNodes) {
                foreach ($node in $nsxtEdgeNodes) {
                    foreach ($element in $clusterallvms) {
                        if( $element -like $node) {
                            $nxtClusterEdgeNodes += $node
                            [Array]$clustervcfvms += $node
                            break
                        }
                    }
                }
            }
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on customer virtual machines for a given vsphere cluster $($cluster.name)..."
            $clustercustomervms = $clusterallvms | ? { $vcfvms -notcontains $_ }
            $clustervcfvms_string = $clustervcfvms -join "; "
            Write-PowerManagementLogMessage -Type INFO -Message "Management virtual machines covered by the script for the cluster $($cluster.name): '$($clustervcfvms_string)' ." -Colour Cyan
            if ($clustercustomervms.count -ne 0) {
                $clustercustomervms_string = $clustercustomervms -join "; "
                Write-PowerManagementLogMessage -Type INFO -Message "Virtual machines not covered by the script for the cluster $($cluster.name): '$($clustercustomervms_string)'. Those VMs will be stopped in a random order if the 'shutdownCustomerVm' flag is passed." -Colour Cyan
            }

            # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                $VMwareToolsNotRunningVMs = @()
                $VMwareToolsRunningVMs = @()
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                if (( Test-NetConnection -ComputerName $vcServer.fqdn -Port 443 ).TcpTestSucceeded) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                    Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                    if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                        Write-PowerManagementLogMessage -type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get VMwareTools Status."
                        #foreach ($vm in $customervms) {  -- This line is at the domain level and below line is at the cluster level
                        foreach ($vm in $clustercustomervms) {
                            Write-PowerManagementLogMessage -type INFO -Message "Checking VMwareTools Status for '$vm'..."
                            $vm_data = Get-VM -Name $vm
                            if ($vm_data.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
                                [Array]$VMwareToolsRunningVMs += $vm
                            }
                            else {
                                [Array]$VMwareToolsNotRunningVMs += $vm
                            }
                        }
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to connect to vCenter Server '$($vcServer.fqdn)'. Command returned the following error: '$vcConnectError'." -Colour Red
                    }
                }
                # Disconnect from the VC
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                if ($VMwareToolsNotRunningVMs.count -ne 0) {
                    $noToolsVMs = $VMwareToolsNotRunningVMs -join "; "
                    Write-PowerManagementLogMessage -Type WARNING -Message "There are some non VCF maintained VMs where VMwareTools NotRunning, hence unable to shutdown these VMs:'$noToolsVMs'." -Colour cyan
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unless these VMs are shutdown manually, we cannot proceed. Please shutdown manually and rerun the script." -Colour Red
                    Exit
                }
            }

            if ($clustercustomervms.count -ne 0) {
                $clustercustomervms_string = $clustercustomervms -join "; "
                if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still powered on. -shutdownCustomerVm is passed to the script." -Colour Cyan
                    Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down VMs not managed by SDDC Manager to put the host in maintenance mode." -Colour Cyan
                    Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management VMs: '$clustercustomervms_string'." -Colour Cyan
                    # Stop Customer VMs with one call to VC:
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $clustercustomervms -timeout 300
                }
                else {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still powered on. -shutdownCustomerVm is not passed to the script." -Colour Cyan
                    Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down Non VCF management VMs: '$clustercustomervms_string'." -Colour Cyan
                    Write-PowerManagementLogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shut down manually or the customer VM Shutdown option is set to true.  Please take the necessary action and run the script again." -Colour Red
                    Exit
                }
            }

            ## Gather NSX Edge Node Details from NSX-T Manager
            if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
                if ($nxtClusterEdgeNodes) {
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nxtClusterEdgeNodes -timeout 600
                }
                else {
                    Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes found for a given cluster '$($cluster.name)' . Skipping edge nodes shutdown.!" -Colour Cyan
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shut down. Skipping shutdown of $nsxtEdgeNodes." -Colour Cyan
            }


            ## Shutdown the NSX Manager Nodes
            #Try getting info if NSX Manger is spanned across workloads
            #Try getting logic if it is the last cluster of the domain to shutdown
            #The below condition tells that we need to go ahead with NSX-T shutdown only under
            #1. if it is a single cluster per domain environment, which is original original_flow
            #2. if it multiClusterEnvironment and NSX-T is not spanned across VC and if it is lastcluster
            $allothervcdown = $true
            if ($NSXTSpannedAcrossWld) {
                foreach ($VCnode in $NSXTSpannedAcrossWldVCArray) {
                    if ($VCnode -eq ($vcServer.fqdn)) {
                        continue
                    } else {
                        $checkServer = (Test-NetConnection -ComputerName $VCnode -Port 443).TcpTestSucceeded
                        if ($checkServer) {
                            $allothervcdown = $false
                            break
                        }
                    }
                }
                if (-not $allothervcdown) {
                    Write-PowerManagementLogMessage -Type WARNING -Message "The NSX-T is spanned across workloads. But there are some Virtual Centers running, Hence Not shutting down NSX-T" -Colour Cyan
                } else {
                    if ($lastelement) {
                        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
                    }
                }
            } else {
                if ($lastelement) {
                    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
                }
            }

            ## The below block was supposed to be only for verison < 4.5, but due to the bug in 4.5
            ## vcls vms are not handled automatically though expected in vcf4.5
            ## Shut Down the vSphere Cluster Services Virtual Machines in the Virtual Infrastructure Workload Domain
            if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
                Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shutdown. Skipping putting the cluster in retreat mode." -Colour Cyan
            }

            # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take some time, please wait..." -Colour Yellow
            $counter = 0
            $retries = 10
            $sleep_time = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon" -silence).count
                if ( $powerOnVMcount ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Some vCLS VMs are still running. Sleeping for $sleep_time seconds until next check."
                    start-sleep $sleep_time
                    $counter += 1
                }
                else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not shut down within the expected time. Stopping the script execution." -Colour Red
                Exit
            }

            # Check the health and sync status of the vSAN cluster
            if ((Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded) {
                if ([float]$SDDCVer -gt [float]4.4) {
                    $RemoteVMs = @()
                    $RemoteVMs = Get-poweronVMsOnRemoteDS -server $vcServer.fqdn -user $vcUser -pass $vcPass -clustertocheck $cluster.name
                    if($RemoteVMs.count -eq 0) {
                        Write-PowerManagementLogMessage -Type INFO -Message "All remote VMs are Powered off." -Colour Green
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Not all remote VMs are Powered Off : $($RemoteVMs.Name), Unable to proceed, please check " -Colour RED
                    }
                }
                if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSAN health is good." -Colour Green
                }
                else {
                    Write-PowerManagementLogMessage -Type WARNING -Message "vSAN health is bad. Check the vSAN health status in vCenter Server '$($vcServer.fqdn)'. Once vSAN health is restored, run the script again." -Colour Cyan
                    Write-PowerManagementLogMessage -Type WARNING -Message "If the script execution has reached ESXi vSAN shutdown previously, this warning is expected. Please continue by following the documentation of VMware Cloud Foundation. " -Colour Cyan
                    Write-PowerManagementLogMessage -Type ERROR -Message "vSAN health is bad. Check the messages above for a solution." -Colour Red
                    Exit
                }
                if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful." -Colour Green
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "There is an active vSAN object resynchronization operation. Check your environment and run the script again." -Colour Red
                    Exit
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "'$($vcServer.fqdn)' might already be shut down. Skipping the vSAN health check for cluster $($cluster.name)." -Colour Cyan
            }

            # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
            if ([float]$SDDCVer -lt [float]4.5) {
                $runningVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vm" -powerstate "poweredon" -silence
            } else {
                $runningAllVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vm" -powerstate "poweredon" -silence
                $runningVclsVMs = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls" -powerstate "poweredon" -silence
                $runningVMs = $runningAllVMs | ? { $runningVclsVMs -notcontains $_ }
            }
            if ($runningVMs.count) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed unless all VMs are shut down. Shut down them manually and run the script again." -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "The environment has running VMs: $($runningVMs). Could not continue with vSAN shutdown while there are running VMs. Exiting! " -Colour Red
            }
            else {

                if ([float]$SDDCVer -lt [float]4.5) {
                    # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
                    if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
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

                   #Check if hosts are in maintainence mode before cluster stop
                   foreach ($esxiNode in $esxiDetails) {
                        $HostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if ($HostConnectionState  -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Looks like $($esxiNode.fqdn) is in maintainence mode before cluster shutdown, please check UI'." -Colour Red
                            Exit
                        }
                   }
                    #VSAN shutdown wizard automation
                    Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOff
                    $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                    foreach ($esxiNode in $esxiDetails) {
                        if ((Test-NetConnection -ComputerName $esxiNode.fqdn -Port 443).TcpTestSucceeded) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Looks like $($esxiNode.fqdn) is still UP. Check the FQDN or IP address or power state of the '$($esxiNode.fqdn)'." -Colour Red
                            Exit
                        }
                    }

                }
                if ($lastelement) {
                    Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vcServer.fqdn.Split(".")[0] -timeout 600
                }
                $ClusterStatusMapping[$cluster.name] = 'DOWN'

                # End of shutdown
                if ([float]$SDDCVer -lt [float]4.5) {
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "Note: ESXi hosts are still in power-on state. Please stop them manually." -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for a given cluster $($cluster.name)!" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################" -Colour Green
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence for a given cluster $($cluster.name)!" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "########################################################" -Colour Green
                }
            }
        }
        $index += 1
        }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Startup procedures
Try {
    if ($WorkloadDomain.type -eq "MANAGEMENT") {
        Write-PowerManagementLogMessage -Type ERROR -Message "Specified workload domain '$sddcDomain' is the management domain. This script handles only VI workload domains. Exiting! " -Colour Red
        Exit
    }


    if ($PsBoundParameters.ContainsKey("startup")) {
        #From here the looping of all clusters begin.
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxtMgrfqdn = ""
        $count = $sddcClusterDetails.count
        $SDDCVer = Get-vcfmanager | select version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object {$_.matches.groups[0].value}
        if ([float]$SDDCVer -lt [float]4.5) {
            foreach ($cluster in $ClusterDetails) {
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                # Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
                Try {
                    foreach ($esxiNode in $esxiDetails) {
                        $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if (-Not $status) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                            Exit
                        }
                    }
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn), If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                }

                # Take hosts out of maintenance mode
                foreach ($esxiNode in $esxiDetails) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
                }
            }

            foreach ($cluster in $ClusterDetails) {
                # Prepare the vSAN cluster for startup - Performed on a single host only
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                Invoke-EsxCommand -server $esxiDetails.fqdn[0] -user $esxiDetails.username[0] -pass $esxiDetails.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"
            }
            foreach ($cluster in $ClusterDetails) {
                # Enable vSAN cluster member updates
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                foreach ($esxiNode in $esxiDetails) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                }
            }
            foreach ($cluster in $ClusterDetails) {
                # Check ESXi status for each host
                Write-PowerManagementLogMessage -Type INFO -Message "Checking the vSAN status of the ESXi hosts...." -Colour Green
                $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                foreach ($esxiNode in $esxiDetails) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                }
            }
        }
        foreach ($cluster in $ClusterDetails) {
            if ([float]$SDDCVer -gt [float]4.4) {
                #lockin mode if any enabled on any host, we have to exit then and there
                Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            }
            $esxiDetails = $esxiWorkloadCluster[$cluster.name]
            #we are turning on all vc as we are not able to read NSX info because SDDC manager restart is removing the cache
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to see if all vCenter Servers in a workload domain are already started"
            $service_status = 0
            foreach ($wldVC in $allWldVCs) {
                $VcStarted = (Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon" -pattern $wldVC.Split(".")[0] -silence).count
                if (-not $VcStarted) {
                    # Startup the Virtual Infrastructure Workload Domain vCenter Server
                    Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $wldVC.Split(".")[0] -timeout 600
                    Write-PowerManagementLogMessage -Type INFO -Message "Waiting for the vCenter Server services to start on '$($wldVC.Split(".")[0])'. It will take some time." -Colour Yellow
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server '$($wldVC.Split(".")[0])' is already started" -Colour Gre
                }
                $retries = 20
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                While ($retries) {
                    Connect-VIServer -server $wldVC -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue | Out-Null
                    if ($DefaultVIServer.Name -eq $wldVC) {
                        #Max wait time for services to come up is 10 mins.
                        for ($i = 0; $i -le 10; $i++) {
                            $status = Get-VAMIServiceStatus -server $wldVC -user $vcUser -pass $vcPass -service 'vsphere-ui' -nolog
                            if ($status -eq "STARTED") {
                                $service_status += 1
                                break
                            }
                            else {
                                Write-PowerManagementLogMessage -Type INFO -Message "The services on vCenter Server $wldVC are still starting. Please wait." -Colour Yellow
                                Start-Sleep 60
                            }
                        }
                        if (([float]$SDDCVer -lt [float]4.5) -and ($wldVC -eq $vcServer.fqdn)) {
                            # Workaround for ESXis that do not communicate their Maintenance status to vCenter Server
                            foreach ($esxiNode in $esxiDetails) {
                                if ((Get-VMHost -name $esxiNode.fqdn).ConnectionState -eq "Maintenance") {
                                    write-PowerManagementLogMessage -Type INFO -Message "Performing exit MaintenanceMode on '$($esxiNode.fqdn)' from vCenter Server." -Colour Yellow
                                    (Get-VMHost -name $esxiNode.fqdn | Get-View).ExitMaintenanceMode_Task(0) | Out-Null
                                }
                            }
                        }
                        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                        break
                    }
                    Start-Sleep 60
                    $retries -= 1
                    Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server is still starting. Please wait." -Colour Yellow
                }
            }

            if ($service_status -eq $allWldVCs.count) {
                Write-PowerManagementLogMessage -Type INFO -Message "Virtual Center Start Successfull." -Colour Green
                if ([float]$SDDCVer -gt [float]4.4) {
                    #Start ESXi hosts here
                    Write-Host "";
                    $WarningString = ""
                    if ($sddcClusterDetails.count -eq 1) {
                        $WarningString = "==========================================================`n"
                        $WarningString += "Please start all the ESXi hosts belonging to the cluster '$($cluster.name)'. Once done, please enter yes"
                        $WarningString += "==========================================================`n"
                    } else {
                        $WarningString = "==========================================================`n"
                        $WarningString += "1) Please start all the ESXi hosts belonging to the cluster '$($cluster.name)'`n"
                        $WarningString += "2) Also, verify that 'Restart cluster' option is available in vSphere UI for the cluster '$($cluster.name)'.`n"
                        $WarningString += "3) If it is not available, refer scenario 3 in https://kb.vmware.com/s/article/87350 and perform its workaround as mentioned'`n"
                        $WarningString += "Once all the above points are taken care, please enter yes`n"
                        $WarningString += "==========================================================`n"
                    }
                    $proceed = Read-Host $WarningString
                    if (-Not $proceed) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence stopping script execution." -Colour Cyan
                        Exit
                    }
                    else {
                        if (($proceed -match "no") -or ($proceed -match "yes")) {
                            if ($proceed -match "no") {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'." -Colour Cyan
                                Exit
                            }
                        }
                        else {
                            Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string, either 'Yes' or 'No'." -Colour Cyan
                            Exit
                        }
                    }

                    $esxiDetails = $esxiWorkloadCluster[$cluster.name]
                    foreach ($esxiNode in $esxiDetails) {
                        if (!(Test-NetConnection -ComputerName $esxiNode.fqdn -Port 443).TcpTestSucceeded) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with the host $($esxiNode.fqdn). Check the FQDN or IP address or power state of '$($esxiNode.fqdn)'." -Colour Red
                            Exit
                        }
                    }
                   #start VSAN Cluster wizard automation
                   Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOn

                   #Check if host are out of maintainence mode after cluster restart
                   foreach ($esxiNode in $esxiDetails) {
                        $HostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if ($HostConnectionState  -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Looks like $($esxiNode.fqdn) is still in maintainence mode even after cluster restart, please check UI'." -Colour Red
                            Exit
                        }
                   }
                }
                if ((Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Cluster health is good." -Colour Green
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cluster health is bad. Please check your environment and run the script again." -Colour Red
                    Exit
                }
                 # Check the health and sync status of the vSAN cluster
                if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful." -Colour Green
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization has failed. Check your environment and run the script again." -Colour Red
                    Exit
                }

                if ([float]$SDDCVer -lt [float]4.5) {
                    # Start vSphere HA to avoid triggering a "Cannot find vSphere HA master agent" error.
                    if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
                    }
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Not all VI workload domain vCenter Servers and its services are still not online." -Colour Red
                Exit
            }
        }
        #This is supposed to be only for VCF < 4.5, but due to bug in 4.5, incorporating this workaround
        foreach ($cluster in $ClusterDetails) {
            #Startup vSphere Cluster Services Virtual Machines in Virtual Infrastructure Workload Domain
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS startup will take some time. Please wait! " -Colour Yellow
        }

        $index = 1
        foreach ($cluster in $ClusterDetails) {
            # Waiting for vCLS VMs to be started for ($retries*10) seconds
            $counter = 0
            $retries = 30
            $sleep_time = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon" -cluster $cluster.name -folder "vcls" -silence).count
                if ( $powerOnVMcount -lt 3 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleep_time seconds until the next check."
                    start-sleep $sleep_time
                    $counter += 1
                }
                else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not started within the expected time. Stopping script execution!" -Colour Red
                Exit
            }
            [Array]$clustervclsvms = @()
            [Array]$clustervcfvms = @()
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch  virtual machines for a given vsphere cluster $($cluster.name)..."
            [Array]$clusterallvms = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "VM"
            #Write-PowerManagementLogMessage -Type INFO -Message "$clusterallvms"
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch  vCLS virtual machines for a given vsphere cluster $($cluster.name)..."
            [Array]$clustervclsvms = Get-VMToClusterMapping -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -folder "vcls"
            foreach ($vm in $clustervclsvms) {
                [Array]$clustervcfvms += $vm
            }
            $vcfvms += $vcServer.fqdn.Split(".")[0]
            $clustervcfvms += $vcServer.fqdn.Split(".")[0]
            Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch  customer virtual machines for a given vsphere cluster $($cluster.name)..."
            $clustercustomervms = $clusterallvms | ? { $vcfvms -notcontains $_ }



            if ($index -eq 1) {
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
                        Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still retrieving NSX-T Data Center information. Sleeping for $sleep_time seconds until the next check..."
                        start-sleep $sleep_time
                        $counter += 1
                    }
                    # Stop loop if we have FQDN for NSX-T VIP
                    if ( $($nsxtCluster.vipFqdn) ) { Break }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "SDDC Manager is still retrieving NSX-T Data Center information. Sleeping for $sleep_time seconds until the next check..."
                        start-sleep $sleep_time
                        $counter += 1
                    }
                }
                if ($counter -eq $retries) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "SDDC Manager did not manage to retrieve NSX-T Data Center information. Please check the LCM log file for errors. Stopping the script execution!" -Colour Red
                    Exit
                }
                $nsxtMgrfqdn = $nsxtCluster.vipFqdn

                $nsxMgrVIP | Add-Member -Force -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).username
                $nsxMgrVIP | Add-Member -Force -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.resource.domainName -eq $sddcDomain -and $_.credentialType -eq "API" })).password
                $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
                $nsxtNodes = @()
                foreach ($node in $nsxtNodesfqdn) {
                    [Array]$nsxtNodes += $node.Split(".")[0]
                    [Array]$vcfvms += $node.Split(".")[0]
                    [Array]$clustervcfvms += $node.Split(".")[0]

                }

                $NsxtStarted = 0
                foreach ($node in $nsxtNodes) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Trying to see if $node is already started"
                    $NsxtStarted += (Get-VMsWithPowerStatus -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -powerstate "poweredon" -pattern $node -silence).count
                }
                if (-not ($NsxtStarted -eq $nsxtNodes.count)) {
                    # Startup the NSX Manager Nodes for Virtual Infrastructure Workload Domain
                    Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
                    if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "NSX cluster is not in 'STABLE' state. Exiting!" -Colour Red
                        Exit
                    }
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "NSXT Manager is already started" -Colour Green
                }
            }

            # Gather NSX Edge Node Details and do the startup
            $nxtClusterEdgeNodes = @()
            Try {
                [Array]$nsxtEdgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $vcServer.fqdn)
                foreach ($node in $nsxtEdgeNodes) {
                    foreach ($element in $clusterallvms) {
                        if( $element -like $node) {
                            $nxtClusterEdgeNodes += $node
                            [Array]$clustervcfvms += $node
                            break
                        }
                    }
                    [Array]$vcfvms += $node
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot fetch information about NSX-T Edge nodes." -Colour Cyan
            }
            if ($nxtClusterEdgeNodes.count -ne 0) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nxtClusterEdgeNodes -timeout 600
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Edge nodes found. Skipping edge nodes startup for VSAN cluster '$($cluster.name)'!" -Colour Cyan
            }

            # End of startup
            $vcfvms_string = ""
            $vcfvms_string = ($clustervcfvms | select -Unique) -join "; "

            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "The following components have been started: $vcfvms_string , " -Colour Green
            if ([float]$SDDCVer -lt [float]4.5) {
                 Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability has been enabled by the script. Disable it per your environment's design." -Colour Cyan
            }
            Write-PowerManagementLogMessage -Type INFO -Message "Check the list above and start any additional VMs, that are required, before you proceed with workload startup!" -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs" -Colour Yellow
            Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600" -Colour Yellow
            if ([float]$SDDCVer -lt [float]4.5) {
                Write-PowerManagementLogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts through SDDC manager, disable it at this point." -Colour Cyan
            }
            if ([float]$SDDCVer -gt [float]4.4) {
                Write-PowerManagementLogMessage -Type INFO -Message "If you have disabled LockdownMode for the ESXi hosts in workload cluster, you can enable it back at this point." -Colour Cyan
            }
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "End of startup sequence for the cluster '$($cluster.name)'!" -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
            $index += 1
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}