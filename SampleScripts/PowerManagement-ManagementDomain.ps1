# Copyright 2023-2024 Broadcom. All Rights Reserved.
# SPDX-License-Identifier: BSD-2

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake / Sowjanya V
    .Organization:  Broadcom
    .Version:       1.1 (Build 1000)
    .Date:          2022-08-12
    ===============================================================================================================

    .CHANGE_LOG

    - 0.6.0   (Gary Blake / 2022-02-22) - Initial release
    - 1.0.0.1000   (Gary Blake / 2022-28-06) - GA version
    - 1.1.0.1000   (Sowjanya V / 2022-08-12) - Support for VCF 4.5

    ===============================================================================================================

    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup a Management Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Management Workload Domain

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -Shutdown
    Initiates a shutdown of the Management Workload Domain.
    Note that SDDC Manager should running in order to use the so if it is already stopped script could not be started with "Shutdown" option.
    In case SDDC manager is already stopped, please identify the step on which the script have stopped and
    continue shutdown manually, following the VCF documentation.

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -genjson
    Initiates a ManagementStartupInput.json generation that could be used for startup.
    Notes:
        File generated earlier may not have all needed details for startup, since the environment may have changed (e.g. ESXi hosts that vCenter Server is running on)
        The file will be generated in the current directory and any file with the same name "ManagementStartupInput.json" will be overwritten

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -Startup
    Initiates the startup of the Management Workload Domain

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -Startup -json .\startup.json
    Initiates the startup of the Management Workload Domain with startup.json file as input from current directory
#>

Param (
    # Pure shutdown parameters
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdown,
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
    # Shutdown and json generation
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $false, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")] [ValidateNotNullOrEmpty()] [Switch]$genjson,
    # Startup
    [Parameter (Mandatory = $false, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [String]$json,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [Switch]$startup
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
    Write-PowerManagementLogMessage -Type ERROR -Message " ERROR at Script Line $lineNumber"
    Write-PowerManagementLogMessage -Type ERROR -Message " Relevant Command: $lineText"
    Write-PowerManagementLogMessage -Type ERROR -Message " ERROR Message: $errorMessage"
    Write-Error -Message $errorMessage
}

# Customer Questions Section
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    $Global:ProgressPreference = 'SilentlyContinue'
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Management Domain" }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Management Domain" }
    }
    if ($PsBoundParameters.ContainsKey("startup")) {
        $defaultFile = "./ManagementStartupInput.json"
        $inputFile = $null
        if ($json) {
            Write-PowerManagementLogMessage -Type INFO -Message "The input JSON file provided."
            $inputFile = $json
        }
        elseif (Test-Path -Path $defaultFile -PathType Leaf) {
            Write-PowerManagementLogMessage -Type INFO -Message "No path to JSON provided in the command line. Using the auto-created input file ManagementStartupInput.json in the current directory."
            $inputFile = $defaultFile
        }
        if ([string]::IsNullOrEmpty($inputFile)) {
            Write-PowerManagementLogMessage -Type WARNING -Message "JSON input file is not provided. Cannot proceed! Exiting! "
            Exit
        }
        Write-Host "";
        $proceed = Read-Host "The following JSON file $inputFile will be used for the operation, please confirm (Yes or No)[default:No]"
        if (-Not $proceed) {
            Write-PowerManagementLogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence stopping script execution."
            Exit
        }
        else {
            if (($proceed -match "no") -or ($proceed -match "yes")) {
                if ($proceed -match "no") {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'."
                    Exit
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string, either 'Yes' or 'No'."
                Exit
            }
        }

        Write-PowerManagementLogMessage -Type INFO -Message "'$inputFile' is checked for correctness, proceeding with the execution."
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Pre-Checks
Try {
    $str1 = "$PSCommandPath "
    if ($server -and $user -and $pass) { $str2 = "-server $server -user $user -pass ******* " }
    if ($PsBoundParameters.ContainsKey("startup")) { $str2 = $str2 + " -startup" }
    if ($PsBoundParameters.ContainsKey("shutdown")) { $str2 = $str2 + " -shutdown" }
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    if ($PsBoundParameters.ContainsKey("genjson")) { $str2 = $str2 + " -genjson" }
    if ($json) { $str2 = $str2 + " -json $json" }
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1"
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2"
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage}
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
    Exit
}

# Shutdown procedure and json generation
if ($PsBoundParameters.ContainsKey("shutdown") -or $PsBoundParameters.ContainsKey("genjson")) {
    Try {
        # Check connection to SDDC Manager
        Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details."
        if (!(Test-EndpointConnection -server $server -Port 443)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with SDDC Manager ($server). Check the FQDN or IP address or the power state of '$server'."
            Exit
        }
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg }
        if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg}
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg}
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC Manager has been validated successfully."
            Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from the SDDC Manager inventory. It will take some time."
            $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
            # Check if we have single cluster in the MGMT domain
            if ($workloadDomain.clusters.id.count -gt 1) {
                Write-PowerManagementLogMessage -Type ERROR -Message "There are multiple clusters in Management domain. This script supports only a single cluster per domain. Exiting!"
                Exit
            }
            $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
            $vcfVersion = Get-VCFManager | select version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object {$_.matches.groups[0].value}

            $var = @{}
            $var["Domain"] = @{}
            $var["Domain"]["name"] = $workloadDomain.name
            $var["Domain"]["type"] = "MANAGEMENT"

            $var["Cluster"] = @{}
            $var["Cluster"]["name"] = $cluster.name

            # Check the SDDC Manager version if VCF less than or greater than VCF 5.0
            if ([float]$vcfVersion -lt [float]5.0) {
                # Gather vCenter Server Details and Credentials
                $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
                $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
                $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password
            } else {
                # Gather vCenter Server Details and Credentials
                $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
                $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).username
                $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" -and $_.resource.resourceId -eq $($workloadDomain.ssoId) }).password
            }
                # Test if VC is reachable, if it is already stopped, we could not continue with the shutdown sequence in automatic way.
            if (-Not (Test-EndpointConnection -server $vcServer.fqdn -Port 443) ) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Could not connect to $($vcServer.fqdn)! The script could not continue without a connection to the management vCenter Server. "
                Write-PowerManagementLogMessage -Type ERROR -Message "Please check the current state and resolve the issue or continue with the shutdown operation by following the documentation of VMware Cloud Foundation. Exiting!"
                Exit
            }
            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            if ($status -eq $True) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Currently we are not supporting VMware Tanzu enabled domains. Please try on other workload domains."
                Exit
            }
            if ($vcPass) {
                $vcPass_encrypted = $vcPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            }
            else {
                $vcPass_encrypted = $null
            }

            [Array]$allvms = @()
            [Array]$vcfvms = @()
            [Array]$vcfvms += $server.Split(".")[0]

            [Array]$vcfvms += ($vcServer.fqdn).Split(".")[0]

            $var["Server"] = @{}
            $var["Server"]["name"] = $vcServer.fqdn.Split(".")[0]
            $var["Server"]["fqdn"] = $vcServer.fqdn
            $var["Server"]["user"] = $vcUser
            $var["Server"]["password"] = $vcPass_encrypted

            $var["Hosts"] = @()
            # Gather ESXi Host Details for the Management Workload Domain
            $esxiWorkloadDomain = @()
            foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id }).fqdn) {
                $esxDetails = New-Object -TypeName PSCustomObject
                $esxDetails | Add-Member -Type NoteProperty -Name name -Value $esxiHost.Split(".")[0]
                $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
                $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).username
                $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).password
                $esxiWorkloadDomain += $esxDetails
                $esxi_block = @{}
                $esxi_block["name"] = $esxDetails.name
                $esxi_block["fqdn"] = $esxDetails.fqdn
                $esxi_block["user"] = $esxDetails.username
                $Pass = $esxDetails.password
                if ($Pass) {
                    $Pass_encrypted = $Pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                }
                else {
                    $Pass_encrypted = $null
                }
                $esxi_block["password"] = $Pass_encrypted
                $var["Hosts"] += $esxi_block
            }

            # Gather NSX Manager Cluster Details
            $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
            $nsxtMgrfqdn = $nsxtCluster.vipFqdn
            $nsxMgrVIP = New-Object -TypeName PSCustomObject
            $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).username
            $Pass = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).password
            if ($Pass) {
                $Pass_encrypted = $Pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            }
            else {
                $Pass_encrypted = $null
            }
            $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $Pass
            $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
            $nsxtNodes = @()
            foreach ($node in $nsxtNodesfqdn) {
                [Array]$nsxtNodes += $node.Split(".")[0]
                [Array]$vcfvms += $node.Split(".")[0]
            }
            $var["NsxtManager"] = @{}
            $var["NsxtManager"]["vipfqdn"] = $nsxtMgrfqdn
            $var["NsxtManager"]["nodes"] = $nsxtNodesfqdn
            $var["NsxtManager"]["user"] = $nsxMgrVIP.adminUser
            $var["NsxtManager"]["password"] = $Pass_encrypted

            # Gather NSX-T Edge Node Details
            $nsxManagerPowerOnVMs = 0
            foreach ($nsxtManager in $nsxtNodes) {
                $state = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch -silence
                if ($state) { $nsxManagerPowerOnVMs += 1 }
                # If we have all NSX-T managers running, or minimum 2 nodes up - query NSX-T for edges.
                if (($nsxManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxManagerPowerOnVMs -eq 2)) {
                    $statusOfNsxtClusterVMs = 'running'
                }
            }
            if ($statusOfNsxtClusterVMs -ne 'running') {
                Write-PowerManagementLogMessage -Type WARNING -Message "NSX Manager VMs have been stopped. NSX Edge VMs will not be handled automatically."
            }
            else {
                Try {
                    Write-PowerManagementLogMessage -Type INFO -Message "NSX Manager VMs are in running state. Trying to fetch information about the NSX Edge VMs..."
                    [Array]$edgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $VcServer.fqdn)
                    $edgenodesstring = $edgeNodes -join ","
                    Write-PowerManagementLogMessage -Type INFO -Message "The NSX Edge VMs are $edgenodesstring."
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Cannot fetch NSX Edge nodes information from NSX Manager '$nsxtMgrfqdn'. Exiting!"
                }
            }

            if ($edgeNodes.count -ne 0) {
                $nsxtEdgeNodes = $edgeNodes
                $var["NsxEdge"] = @{}
                $var["NsxEdge"]["nodes"] = New-Object System.Collections.ArrayList
                foreach ($val in $edgeNodes) {
                    $var["NsxEdge"]["nodes"].add($val) | out-null
                    [Array]$vcfvms += $val
                }
            }

            # Get SDDC VM name from vCenter Server
            $Global:sddcmVMName
            $Global:vcHost
            $vcHostUser = ""
            $vcHostPass = ""
            if ($vcServer.fqdn) {
                Write-PowerManagementLogMessage -Type INFO -Message "Getting SDDC Manager VM name ..."
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                Connect-VIServer -server $vcServer.fqdn -user $vcUser -password $vcPass | Out-Null
                #$sddcManagerIP = (Test-NetConnection -ComputerName $server).RemoteAddress.IPAddressToString
                $sddcManagerIP = (Get-VCFManager | Select-Object ipAddress).ipAddress
                $sddcmVMName = (Get-VM * | Where-Object { $_.Guest.IPAddress -eq $sddcManagerIP }).Name
                $vcHost = (get-vm | where Name -eq $vcServer.fqdn.Split(".")[0] | Select-Object VMHost).VMHost.Name
                $vcHostUser = (Get-VCFCredential -resourceType ESXI -resourceName $vcHost | Where-Object { $_.accountType -eq "USER" }).username
                $vcHostPass = (Get-VCFCredential -resourceType ESXI -resourceName $vcHost | Where-Object { $_.accountType -eq "USER" }).password
                $vcHostPass_encrypted = $vcHostPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            }

            #Backup DRS Automation level settings into JSON file
            [string]$level = ""
            [string]$level = Get-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            $var["Cluster"]["DrsAutomationLevel"] = [string]$level

            $var["Server"]["host"] = $vcHost
            $var["Server"]["vchostuser"] = $vcHostUser
            $var["Server"]["vchostpassword"] = $vcHostPass_encrypted

            $var["SDDC"] = @{}
            $var["SDDC"]["name"] = $sddcmVMName
            $var["SDDC"]["fqdn"] = $server
            $var["SDDC"]["user"] = $user
            $var["SDDC"]["password"] = $pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            $var["SDDC"]["version"] = $vcfVersion

            $var | ConvertTo-Json > ManagementStartupInput.json
            # Exit if json generation have selected
            if ($genjson) {
                if (Test-Path -Path "ManagementStartupInput.json" -PathType Leaf) {
                    $location = Get-Location
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################"
                    Write-PowerManagementLogMessage -Type INFO -Message "JSON generation is successful!"
                    Write-PowerManagementLogMessage -Type INFO -Message "ManagementStartupInput.json is created in the $location path."
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################"
                    Exit
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "JSON file is not created. Check for permissions in the $location path"
                    Exit
                }
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot obtain an access token from SDDC Manager ($server). Check your credentials."
            Exit
        }

        # Shutdown related code starts here
        if ([float]$vcfVersion -lt [float]4.5) {
            # Check if SSH is enabled on the ESXI hosts before proceeding with the shutdown procedure.
            Try {
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                    if (-Not $status) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it."
                        Exit
                    }
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it."
            }
        } else {
            #Lockdown mode - if enabled on any host, stop the script
            Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            #Check if hosts are out of maintenance mode before cluster shutdown
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $HostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if ($HostConnectionState  -eq "Maintenance") {
                    Write-PowerManagementLogMessage -Type ERROR -Message "$($esxiNode.fqdn) is in maintenance mode. Unable to shut down the cluster. Please take the host out of maintenance mode and run the script again."
                    Exit
                }
            }
        }

        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on virtual machines from server $($vcServer.fqdn)..."
        [Array]$allvms = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
        $customervms = @()
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on vCLS virtual machines from server $($vcServer.fqdn)..."
        [Array]$vclsvms += Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence
        foreach ($vm in $vclsvms) {
            [Array]$vcfvms += $vm
        }

        $customervms = $allvms | ? { $vcfvms -notcontains $_ }
        $vcfvms_string = $vcfvms -join "; "
        Write-PowerManagementLogMessage -Type INFO -Message "Management virtual machines covered by the script: '$($vcfvms_string)' ."
        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            Write-PowerManagementLogMessage -Type INFO -Message "Virtual machines not covered by the script: '$($customervms_string)' . Those VMs will be stopped in a random order if the 'shutdownCustomerVm' flag is passed."
        }

        # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
            $VMwareToolsNotRunningVMs = @()
            $VMwareToolsRunningVMs = @()
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if ( Test-EndpointConnection -server $vcServer.fqdn -Port 443 ) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                    Write-PowerManagementLogMessage -type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get VMwareTools Status."
                    foreach ($vm in $customervms) {
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
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unable to connect to vCenter Server '$($vcServer.fqdn)'. Command returned the following error: '$vcConnectError'."
                }
            }
            # Disconnect from the VC
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if ($VMwareToolsNotRunningVMs.count -ne 0) {
                $noToolsVMs = $VMwareToolsNotRunningVMs -join "; "
                Write-PowerManagementLogMessage -Type WARNING -Message "There are some non VCF maintained VMs where VMwareTools NotRunning, hence unable to shutdown these VMs:'$noToolsVMs'."
                Write-PowerManagementLogMessage -Type ERROR -Message "Unless these VMs are shutdown manually, we cannot proceed. Please shutdown manually and rerun the script."
                Exit
            }
        }

        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is passed to the script."
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down VMs not managed by SDDC Manager to put the host in maintenance mode."
                Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management VMs: '$customervms_string'."
                # Stop Customer VMs with one call to VC:
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $customervms -timeout 300
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is not passed to the script."
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down management VMs not managed by SDDC Manager: $($customervms_string) ." 
                Write-PowerManagementLogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shut down manually or the -shutdownCustomerVm option is present.  Take the necessary action and run the script again."
                Exit
            }
        }
        # Check if VMware Aria Operations for Logs exists in environment, if so it will shutdown the nodes.
        if (Test-VCFConnection -server $server) {
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                if (($vcfVrslcmDetails = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass)) {
                    if (Test-vRSLCMAuthentication -server $vcfVrslcmDetails.fqdn -user $vcfVrslcmDetails.adminUser -pass $vcfVrslcmDetails.adminPass) {
                        $productid = "vrli"
                        $vmlist = Get-vRSLCMEnvironmentVMs -server $server -user $user -pass $pass -productid $productid
                        if ($vmlist -ne $null) {
                            $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                            if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                                if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                                    if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                        Write-PowerManagementLogMessage -Type INFO -Message "Stopping the VMware Aria Operations for Logs nodes..."
                                        Stop-CloudComponent -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -nodes $vmlist -timeout 600     
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } 

        # Check if there are any running Virtual Machines on the Overlay Networks before shutting down Edge Cluster.
        if ($nsxtEdgeNodes) {
            if (Test-VCFConnection -server $server) {
                if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                    $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object {$_.type -eq "MANAGEMENT"}
                    if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                        if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                            if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                if (($vcfNsxDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain.name)) {
                                    if (Test-NSXTConnection -server $vcfNsxDetails.fqdn) {
                                        if (Test-NSXTAuthentication -server $vcfNsxDetails.fqdn -user $vcfNsxDetails.adminUser -pass $vcfNsxDetails.adminPass) {
                                            $nsx_segments = Get-NsxtSegment | Select-Object display_name, type | Where-Object { $_.type -eq "ROUTED" }
                                            foreach ($segment in $nsx_segments) {
                                                $segmentName = $segment.display_name
                                                $cloudvms = Get-VM | Get-NetworkAdapter | Where-Object { $_.NetworkName -eq $segmentName } | Select-Object Parent
                                            }
                                            $vmlist = $cloudvms.Parent
                                            $stopExecuted = $false
                                            foreach ($vm in $vmlist) {
                                                $vmName = $vm.Name
                                                $powerState = $vm.PowerState
                                                if ($powerState -eq "PoweredOn") {
                                                    Write-PowerManagementLogMessage -Type Error -Message "VM Name: $vmName, Power State: $powerState, Please power off the virtual machines connected to NSX Segments before you shutdown an NSX Edge Cluster"
                                                    $stopExecuted = $true
                                                }
                                                if (-not $stopExecuted) {
                                                    Write-PowerManagementLogMessage -Type INFO -Message "Stopping the NSX Edge nodes..."
                                                    Stop-CloudComponent -server $server -user $user -pass $pass -nodes $nsxtEdgeNodes -timeout 600
                                                    $stopExecuted = $true
                                                }
                                            }
                                        } else {
                                            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping shutdown..."
                                        }
                                    }
                                }
                            }
                        }
                    }
                }  
            }
        }
        
        #Stop NSX Manager nodes
        Write-PowerManagementLogMessage -Type INFO -Message "Stopping the NSX Manager nodes..."
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600


        #Check the vSAN health before SDDC manager is stopped
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-PowerManagementLogMessage -Type INFO -Message "vSAN cluster health is good."
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "The vSAN cluster isn't in a healthy state. Check the vSAN cluster status in vCenter Server '$($vcServer.fqdn)'. After you resolve the vSAN health issues, run the script again."
            Write-PowerManagementLogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue the shutdown workflow by following the documentation of VMware Cloud Foundation. "
            Write-PowerManagementLogMessage -Type ERROR -Message "The vSAN cluster isn't in a healthy state. Check the messages above for a solution."
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-PowerManagementLogMessage -Type INFO -Message "vSAN object resynchronization is successful."
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script... Wait until the vSAN object resynchronization is completed and run the script again."
            Exit
        }

        # Shut Down the SDDC Manager Virtual Machine in the Management Domain.
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600


        # Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable

        # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take time. Please wait!"
        $counter = 0
        $retries = 10
        $sleepTime = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount ) {
                Write-PowerManagementLogMessage -Type INFO -Message "Some vCLS VMs are still running. Sleeping for $sleepTime seconds until the next check..."
                Start-Sleep -s $sleepTime
                $counter += 1
            } else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not shut down within the expected time. Stopping the script execution... "
            Exit
        }

        # Workflow for VMware Cloud Foundation before version 4.5
        if ([float]$vcfVersion -le [float]4.5) {
            # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!"
            }

            # Set DRS Automation Level to Manual in the Management Domain
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level Manual
        }

        # Check if there are VMs running on a vSAN HCI Mesh
        $RemoteVMs = @()
        $RemoteVMs = Get-poweronVMsOnRemoteDS -server $vcServer.fqdn -user $vcUser -pass $vcPass -clustertocheck $cluster.name
        if($RemoteVMs.count -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "All remote VMs are powered off."
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Some remote VMs are still powered-on : $($RemoteVMs.Name). Cannot proceed until the powered-on VMs are shut down. Check your environment."
        }

        #Testing VSAN health after SDDC manager is stopped
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "vSAN cluster health is good."
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "The vSAN cluster isn't in a healthy state. Check the vSAN status in vCenter Server '$($vcServer.fqdn)'. After you resolve the vSAN issues, run the script again."
            Write-PowerManagementLogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue by following the documentation of VMware Cloud Foundation. "
            Write-PowerManagementLogMessage -Type ERROR -Message "The vSAN cluster isn't in a healthy state. Check the messages above for a solution."
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "VSAN object resynchronization is successful."
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script. Wait until the vSAN object resynchronization is completed and run the script again."
            Exit
        }

        if ([float]$vcfVersion -lt [float]4.5) {
            # Verify that there is only one VM running (vCenter Server) on the ESXis, then shutdown vCenter Server.
            $runningVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
            if ($runningVMs.count -gt 1 ) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed until the powered-on VMs are shut down. Shut them down them manually and continue with the shutdown operation by following documentation of VMware Cloud Foundation."
                Write-PowerManagementLogMessage -Type ERROR -Message "There are running VMs in environment: $($runningVMs). Exiting! "
            }
            else {
                Write-PowerManagementLogMessage -Type INFO -Message "There are no VMs in powered-on state. Hence, shutting down vCenter Server..."
                # Shutdown vCenter Server
                Stop-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -timeout 600
                if (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running") {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot stop vCenter Server on the host. Exiting!"
                }
            }
        }
        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        Write-PowerManagementLogMessage -Type INFO -Message "Checking that there are no running VMs on the ESXi hosts before stopping vSAN."
        $runningVMsPresent = $False
        $runningVMs = @()
        $runningVclsVMs = @()
        foreach ($esxiNode in $esxiWorkloadDomain) {
            if ([float]$vcfVersion -lt [float]4.5) {
                $runningVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -silence
            } else {
                $runningAllVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -silence
                [Array]$runningVclsVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)"
                [Array]$runningVclsVMs += $vcServer.fqdn.Split(".")[0]
                $runningVMs = $runningAllVMs | ? { $runningVclsVMs -notcontains $_ }
            }
            if ($runningVMs.count) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed until the powered-on VMs are shut down. Shut down them down manually and run the script again."
                Write-PowerManagementLogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn) VMs are:$($runningVMs) "
                $runningVMsPresent = $True
            }
        }
        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        if ($runningVMsPresent) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Some VMs on the ESXi hosts are still in powered-on state. Check the console log, stop the VMs and continue the shutdown operation manually."
        }
        # Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
        else {
            if ([float]$vcfVersion -lt [float]4.5) {
                # Disable cluster member updates from vCenter Server
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
                }
                # Run vSAN cluster preparation - should be done on one host per cluster
                # Sleeping 1 min before starting the preparation
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 60 seconds before preparing hosts for vSAN shutdown..."
                Start-Sleep -s 60
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
                # Putting hosts in maintenance mode
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before putting hosts in maintenance mode..."
                Start-Sleep -s 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
                }
                # End of shutdown
                Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence!"
                Write-PowerManagementLogMessage -Type INFO -Message "Shut down the ESXi hosts!"
            } else {

                # vSAN shutdown wizard automation.
                Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOff -mgmt

                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 60 seconds before checking ESXi hosts' shutdown status..."
                Start-Sleep -s 60

                $counter = 0
                $sleepTime = 60 # in seconds

                while ($counter -lt 1800)
                {
                    $successcount = 0
                    #Verify if all ESXi hosts are down in here to conclude End of Shutdown sequence
                    foreach ($esxiNode in $esxiWorkloadDomain) {
                        if (Test-EndpointConnection -server $esxiNode.fqdn -Port 443) {
                            Write-PowerManagementLogMessage -Type WARNING -Message "Some hosts are still up. Sleeping for 60 seconds before next check..."
                            break
                        } else {
                            $successcount++
                        }
                    }
                    if ($successcount -eq $esxiWorkloadDomain.count) {
                        Write-PowerManagementLogMessage -Type INFO -Message "All hosts have been shut down successfully!"
                        Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence!"
                        Exit
                    } else {
                        Start-Sleep -s $sleepTime
                        $counter += $sleepTime
                    }
                }
            }
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
        Exit
    }
}


# Startup procedures
if ($PsBoundParameters.ContainsKey("startup")) {
    Try {
        $MgmtInput = Get-Content -Path $inputFile | ConvertFrom-JSON
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from JSON file..."
        # Gather Details from SDDC Manager
        $workloadDomain = $MgmtInput.Domain.name
        $cluster = New-Object -TypeName PSCustomObject
        $cluster | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Cluster.name

        #Get DRS automation level settings
        $DrsAutomationLevel = $MgmtInput.cluster.DrsAutomationLevel

        #Getting SDDC manager VM name
        $sddcmVMName = $MgmtInput.SDDC.name
        $vcfVersion = $MgmtInput.SDDC.version

        # Gather vCenter Server Details and Credentials
        $vcServer = New-Object -TypeName PSCustomObject
        $vcServer | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Server.name
        $vcServer | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Server.fqdn
        $vcUser = $MgmtInput.Server.user
        $temp_pass = convertto-securestring -string $MgmtInput.Server.password
        $temp_pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($temp_pass))))
        $vcPass = $temp_pass
        $vcHost = $MgmtInput.Server.host
        $vcHostUser = $MgmtInput.Server.vchostuser
        if ($MgmtInput.Server.vchostpassword) {
            $vchostpassword = convertto-securestring -string $MgmtInput.Server.vchostpassword
            $vchostpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vchostpassword))))
        }
        else {
            $vchostpassword = $null
        }
        $vcHostPass = $vchostpassword

        # Gather ESXi Host Details for the Management Workload Domain
        $esxiWorkloadDomain = @()
        $workloadDomainArray = $MgmtInput.Hosts
        foreach ($esxiHost in $workloadDomainArray) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost.fqdn
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value $esxiHost.user
            if ($esxiHost.password) {
                $esxpassword = convertto-securestring -string $esxiHost.password
                $esxpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($esxpassword))))
            }
            else {
                $esxpassword = $null
            }
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value $esxpassword
            $esxiWorkloadDomain += $esxDetails
        }

        # Gather NSX Manager Cluster Details
        $nsxtCluster = $MgmtInput.NsxtManager
        $nsxtMgrfqdn = $MgmtInput.NsxtManager.vipfqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.NsxtManager.user
        if ($MgmtInput.NsxtManager.password) {
            $nsxpassword = convertto-securestring -string $MgmtInput.NsxtManager.password
            $nsxpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($nsxpassword))))
        }
        else {
            $nsxpassword = $null
        }
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $nsxpassword
        $nsxtNodesfqdn = $MgmtInput.NsxtManager.nodes
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }


        # Gather NSX Edge Node Details
        $nsxtEdgeCluster = $MgmtInput.NsxEdge
        $nsxtEdgeNodes = $nsxtEdgeCluster.nodes

        # Startup workflow starts here
        # Check if VC is running - if so, skip ESXi operations
        if (-Not (Test-EndpointConnection -server $vcServer.fqdn -Port 443 -WarningAction SilentlyContinue )) {
            Write-PowerManagementLogMessage -Type INFO -Message "Could not connect to $($vcServer.fqdn). Starting vSAN..."
            if ([float]$vcfVersion -gt [float]4.4) {
                #TODO add check if hosts are up and running. If so, do not display this message
                Write-Host "";
                $proceed = Read-Host "Please start all the ESXi host belonging to the cluster '$($cluster.name)' and wait for the host console to come up. Once done, please enter yes."
                if (-Not $proceed) {
                    Write-PowerManagementLogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence, stopping script execution..."
                    Exit
                }
                else {
                    if (($proceed -match "no") -or ($proceed -match "yes")) {
                        if ($proceed -match "no") {
                            Write-PowerManagementLogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'..."
                            Exit
                        }
                    }
                    else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string - either 'Yes' or 'No'."
                        Exit
                    }
                }

                foreach ($esxiNode in $esxiWorkloadDomain) {
                    if (!(Test-EndpointConnection -server $esxiNode.fqdn -Port 443)) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with host $($esxiNode.fqdn). Check the FQDN or IP address, or the power state of '$($esxiNode.fqdn)'."
                        Exit
                    }
                }
            } else {
                #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
                Try {
                    foreach ($esxiNode in $esxiWorkloadDomain) {
                        $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if (-Not $status) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it."
                            Exit
                        }
                    }
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it."
                }

                # Take hosts out of maintenance mode
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
                }
            }
            if ([float]$vcfVersion -lt [float]4.5) {
                # Prepare the vSAN cluster for startup - Performed on a single host only
                # We need some time before this step, setting hard sleep 30 sec
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before starting vSAN..."
                Start-Sleep -s 30
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

                # We need some time before this step, setting hard sleep 30 sec
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before enabling vSAN updates..."
                Start-Sleep -s 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                }

                Write-PowerManagementLogMessage -Type INFO -Message "Checking vSAN status of the ESXi hosts."
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                }

                # Startup the Management Domain vCenter Server
                Start-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.Name -timeout 600
                Start-Sleep -s 5
                if (-Not (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running")) {

                    Write-PowerManagementLogMessage -Type Warning -Message "Cannot start vCenter Server on the host. Check if vCenter Server is located on host $vcHost. "
                    Write-PowerManagementLogMessage -Type Warning -Message "Start vCenter Server manually and run the script again."
                    Write-PowerManagementLogMessage -Type ERROR -Message "Could not start vCenter Server on host $vcHost. Check the console log for more details."
                    Exit
                }
            }
        }
        else {
            Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server '$($vcServer.fqdn)' is running. Skipping vSAN startup!"
        }

        # Wait till VC is started, continue if it is already up and running
        Write-PowerManagementLogMessage -Type INFO -Message "Waiting for the vCenter Server services on $($vcServer.fqdn) to start..."
        $retries = 20
        if ($DefaultVIServers) {
            Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        }
        While ($retries) {
            Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue | Out-Null
            if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                #Max wait time for services to come up is 10 mins.
                for ($i = 0; $i -le 10; $i++) {
                    $status = Get-VAMIServiceStatus -server $vcServer.fqdn -user $vcUser  -pass $vcPass -service 'vsphere-ui' -nolog
                    if ($status -eq "STARTED") {
                        break
                    }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "The services on vCenter Server are still starting. Please wait. Sleeping for 60 seconds..."
                        Start-Sleep -s 60
                    }
                }
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Write-PowerManagementLogMessage -Type INFO -Message "The vCenter Server API is still not accessible. Please wait. Sleeping for 60 seconds..."
            Start-Sleep -s 60
            $retries -= 1
        }
        # Check if VC have been started in the above time period
        if (!$retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Timeout while waiting vCenter Server to start. Exiting!"
        }

        #Restart Cluster Via Wizard
        if ([float]$vcfVersion -gt [float]4.4) {
            # Lockdown mode check
            Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            # Start VSAN Cluster wizard
            Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOn
        }
        # Check vSAN Status
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN cluster health is bad. Check your environment and run the script again."
            Exit
        }
        # Check vSAN Status
        if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is in progress. Check your environment and run the script again."
            Exit
        }

        #Start workflow for VCF prior version 4.5
        if ([float]$vcfVersion -lt [float]4.5) {
            # Start vSphere HA
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'."
            }

            # Restore the DRS Automation Level to the mode backed up for Management Domain Cluster during shutdown
            if ([string]::IsNullOrEmpty($DrsAutomationLevel)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The DrsAutomationLevel value in the JSON file is empty. Exiting!"
                Exit
            }
            else {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level $DrsAutomationLevel
            }
        }

        # Startup the vSphere Cluster Services Virtual Machines in the Management Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
        # Waiting for vCLS VMs to be started for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS virtual machines startup will take some time. Please wait."
        $counter = 0
        $retries = 10
        $sleepTime = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence).count
            if ( $powerOnVMcount -lt 3 ) {
                Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleepTime seconds until the next check."
                Start-Sleep -s $sleepTime
                $counter += 1
            } else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS virtual machines did not start within the expected time. Stopping script execution..."
            Exit
        }

        #Startup the SDDC Manager Virtual Machine in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Startup the NSX Manager Nodes in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The NSX Manager cluster is not in 'STABLE' state. Exiting!"
            Exit
        }

        # Startup the NSX Edge Nodes in the Management Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping startup..."
        }

        # End of startup
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-PowerManagementLogMessage -Type INFO -Message "vSphere vSphere High Availability has been enabled by the script. Please disable it according to your environment's design."
        }
        Write-PowerManagementLogMessage -Type INFO -Message "Check your environment and start any additional virtual machines that you host in the management domain."
        Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs"
        Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-PowerManagementLogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts in management domain, disable it at this point."
        }
        if ([float]$vcfVersion -gt [float]4.4) {
            Write-PowerManagementLogMessage -Type INFO -Message "If you have disabled lockdown mode for the ESXi hosts in management domain, enable it back at this point."
        }
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
        Write-PowerManagementLogMessage -Type INFO -Message "End of the startup sequence!"
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################"
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
        Exit
    }
}
