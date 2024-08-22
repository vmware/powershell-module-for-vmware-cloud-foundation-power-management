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
    PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -genJson
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
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")] [ValidateNotNullOrEmpty()] [Switch]$genJson,
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
if(($PSBoundParameters.ContainsKey("shutdown") -or $PSBoundParameters.ContainsKey("genJson"))) {
    $pass = Get-Password -User $user -Password $pass
}

# Error Handling (script scope function)
Function Write-DebugMessage {
    Param (
        [Parameter (Mandatory = $true)] [PSObject]$object
    )
    $ErrorActionPreference = 'Stop'
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-LogMessage -Type ERROR -Message " ERROR at Script Line $lineNumber"
    Write-LogMessage -Type ERROR -Message " Relevant Command: $lineText"
    Write-LogMessage -Type ERROR -Message " ERROR Message: $errorMessage"
    Write-Error -Message $errorMessage
}

# Customer Questions Section
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    $Global:ProgressPreference = 'SilentlyContinue'
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Management Domain" }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Management Domain" }
    }
    if ($PsBoundParameters.ContainsKey("startup")) {
        $defaultFile = "./ManagementStartupInput.json"
        $inputFile = $null
        if ($json) {
            Write-LogMessage -Type INFO -Message "The input JSON file provided."
            $inputFile = $json
        } elseif (Test-Path -Path $defaultFile -PathType Leaf) {
            Write-LogMessage -Type INFO -Message "No path to JSON provided in the command line. Using the auto-created input file ManagementStartupInput.json in the current directory."
            $inputFile = $defaultFile
        }
        if ([string]::IsNullOrEmpty($inputFile)) {
            Write-LogMessage -Type WARNING -Message "JSON input file is not provided. Cannot proceed! Exiting! "
            Exit
        }
        Write-Host ""
        $proceed = Read-Host "The following JSON file $inputFile will be used for the operation, please confirm (Yes or No)[default:No]"
        if (-Not $proceed) {
            Write-LogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence stopping script execution."
            Exit
        } else {
            if (($proceed -match "no") -or ($proceed -match "yes")) {
                if ($proceed -match "no") {
                    Write-LogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'."
                    Exit
                }
            } else {
                Write-LogMessage -Type WARNING -Message "Pass the right string, either 'Yes' or 'No'."
                Exit
            }
        }
        Write-LogMessage -Type INFO -Message "'$inputFile' is checked for correctness, proceeding with the execution."
    }
} Catch {
    Write-DebugMessage -object $_
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
    Write-LogMessage -Type INFO -Message "Script used: $str1"
    Write-LogMessage -Type INFO -Message "Script syntax: $str2"
    if (-Not $null -eq $customerVmMessage) { Write-LogMessage -Type INFO -Message $customerVmMessage }
} Catch {
    Write-DebugMessage -object $_
    Exit
}

# Shutdown procedure and json generation
if ($PsBoundParameters.ContainsKey("shutdown") -or $PsBoundParameters.ContainsKey("genjson")) {
    Try {
        # Check connection to SDDC Manager
        Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details."
        if (!(Test-EndpointConnection -server $server -Port 443)) {
            Write-LogMessage -Type ERROR -Message "Cannot communicate with SDDC Manager ($server). Check the FQDN or IP address or the power state of '$server'."
            Exit
        }
        $statusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $statusMsg ) { Write-LogMessage -Type INFO -Message $statusMsg }
        if ( $warnMsg ) { Write-LogMessage -Type WARNING -Message $warnMsg }
        if ( $errorMsg ) { Write-LogMessage -Type ERROR -Message $errorMsg }
        if ($accessToken) {
            Write-LogMessage -Type INFO -Message "Connection to SDDC Manager has been validated successfully."
            Write-LogMessage -Type INFO -Message "Gathering system details from the SDDC Manager inventory. It will take some time."
            $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }

            # Check if we have single cluster in the MGMT domain
            $vcfVersion = Get-VCFManager | Select-Object version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object { $_.matches.groups[0].value }

            if ($workloadDomain.clusters.id.count -gt 1) {
                Write-LogMessage -Type INFO -Message "More than one cluster exists in the management domain."
                $mgmtClusterIds = @()
                $mgmtClusterIds = (Get-VCFWorkloadDomain | Select-Object Type -ExpandProperty clusters | Where-Object { $_.type -eq "MANAGEMENT" }).id
                foreach ($clusterId in $mgmtClusterIds) {
                    $clusterId = (Get-VCFCluster | Select-Object name, id, isdefault | Where-Object { $_.id -eq $clusterId })
                    $clusterNameExtra = $clusterId.name
                    if (!$isDefault) {
                        $answer = Read-Host -Prompt "Shutdown cluster $clusterNameExtra. Do you want to continue? Y/N"
                        if ($answer -Match "N") {
                            Write-LogMessage -Type WARNING "Cancelling shutdown of $clusterName. Exiting..."
                            Exit
                        } else {
                            Write-LogMessage -Type INFO "Shutting down $clusterName..."
                        }
                        # Shut Down the vSphere Cluster Services Virtual Machines
                        $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                        if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                            if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                                if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                    # Set DRS Automation Level to Manual in the Management Domain
                                    Set-DrsAutomationLevel -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -level Manual
                                    if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                        # TODO Fix variable name and matching condition
                                        $listOfVMsNotVcls = (Get-VM -Location $clusterNameExtra | Select-Object Name, PowerState, @{N = "ToolsStatus"; E = { $_.ExtensionData.Guest.ToolsStatus } } | Where-Object { $_.name -inotmatch "vCLS" -and $_.PowerState -eq "PoweredOn" })
                                        $vmNames = $listOfVMsNotVcls.Name
                                        $toolsStatus = $listOfVMsNotVcls.ToolsStatus
                                        foreach ($vmName in $vmNames) {
                                            if ($toolsStatus[$vmNames.IndexOf($vmName)] -eq "toolsOK") {
                                                Stop-CloudComponent -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -nodes $vmName -timeout 300
                                            } else {
                                                Write-Error "Unable to shutdown virtual machines $vmName. VMware Tools is not running, Please shutdown the virtual machines before retrying. Exiting..."
                                                Exit
                                            }
                                        }

                                        # Shut Down the vSphere Cluster Services Virtual Machines
                                        Set-Retreatmode -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -mode enable
                                        $counter = 0
                                        $retries = 10
                                        Write-LogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take time. Please wait..."

                                        while ($counter -ne $retries) {
                                            if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                                $powerOnVMcount = (Get-VM -Location $clusterNameExtra | Where-Object { $_.name -match "vCLS" }).count
                                                if ( $powerOnVMcount ) {
                                                    Write-LogMessage -Type INFO -Message "Some vCLS virtual machines are still running. Sleeping for $sleepTime seconds until the next check..."
                                                    Start-Sleep -s $sleepTime
                                                    Break
                                                }
                                            }
                                        }
                                        if ($counter -eq $retries) {
                                            Write-LogMessage -Type ERROR -Message "vCLS virtual machines were not shut down within the expected time. Exiting... "
                                            Exit
                                        }

                                        # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
                                        if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                            if (!$(Set-VsphereHA -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -disableHA)) {
                                                Write-LogMessage -Type ERROR -Message "Unable to disable vSphere High Availability for cluster '$clusterName'. Exiting..."
                                                Exit
                                            }
                                        }
                                        if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                            $remoteVMs = @()
                                            $remoteVMs = Get-PowerOnVMsOnRemoteDS $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -clustertocheck $clusterName
                                            Write-LogMessage -Type INFO -Message "All remote virtual machines are powered off."
                                        } else {
                                            Write-LogMessage -Type ERROR -Message "Some remote virtual machines are still powered-on : $($remoteVMs.Name). Unable to proceed until these are are shutdown. Exiting..."
                                            Exit
                                        }
                                        # Testing VSAN health
                                        if ( (Test-VsanHealth -cluster $clusterNameExtra -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) -eq 0) {
                                            Write-LogMessage -Type INFO -Message "vSAN cluster is in a healthy state."
                                        } else {
                                            Write-LogMessage -Type ERROR -Message "vSAN cluster is in an unhealthy state. Check the vSAN status in cluster '$($clusterName)'. Retry after resolving the vSAN health state. Exiting..."
                                            Exit
                                        }
                                        if ((Test-VsanObjectResync -cluster $clusterNameExtra -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) -eq 0) {
                                            Write-LogMessage -Type INFO -Message "vSAN object resynchronization successful."
                                        } else {
                                            Write-LogMessage -Type ERROR -Message "vSAN object resynchronization is running.  Retry after the vSAN object resynchronization is completed. Exiting..."
                                            Exit
                                        }
                                        # Checks SSH Status, if SSH service is not started, SSH will be started
                                        if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                            if ([float]$vcfVersion -lt [float]4.5) {
                                                # Disable cluster member updates from vCenter Server
                                                $esxiHosts = (Get-VCFHost | Select-Object fqdn -ExpandProperty cluster | Where-Object { $_.id -eq $clusterId.id }).fqdn
                                                foreach ($esxi in $esxiHosts) {
                                                    if (-Not (Test-VsphereConnection -server $esxiNode)) {
                                                        Write-LogMessage -Type ERROR "ESXi host $esxi is not accessible. Exiting..."
                                                        Exit
                                                    } else {
                                                        $password = (Get-VCFCredential -resourceName $esxi | Select-Object password)
                                                        $esxiHostPassword = $password.password[1]
                                                        $status = Get-SSHEnabledStatus -server $esxi -user root -pass $esxiHostPassword
                                                        if (-Not $status) {
                                                            if (Test-vSphereAuthentication -server $esxi -user root -pass $esxiHostPassword) {
                                                                Write-LogMessage -Type WARNING "SSH is not enabled on ESXi host $esx. Enabling SSH..."
                                                                Get-VmHostService -VMHost $esxi | Where-Object { $_.key -eq "TSM-SSH" } | Start-VMHostService
                                                                Start-Sleep -s 10
                                                                Write-LogMessage -Type INFO "Setting ESXi host $esxi to ignoreClusterMemberListUpdates..."
                                                                Invoke-EsxCommand -server $esxi -user root -pass $esxiHostPassword -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
                                                            } else {
                                                                Write-LogMessage -Type ERROR "Unable to authenticate to ESXi host $esxi. Exiting..."
                                                                Exit
                                                            }
                                                        } else {
                                                            if (Test-vSphereAuthentication -server $esxi -user root -pass $esxiHostPassword) {
                                                                Write-LogMessage -Type INFO "Setting ESXi host $esxi to ignoreClusterMemberListUpdates..."
                                                                Invoke-EsxCommand -server $esxi -user root -pass $esxiHostPassword -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
                                                            } else {
                                                                Write-LogMessage -Type ERROR "Unable to authenticate to ESXi host $esxi. Exiting..."
                                                                Exit
                                                            }
                                                        }
                                                    }
                                                }
                                                # Run vSAN cluster preparation on one ESXi host per cluster.
                                                Write-LogMessage -Type INFO -Message "Pausing for 60 seconds before preparing ESXi hosts for vSAN shutdown..."
                                                Start-Sleep -s 60
                                                $password = (Get-VCFCredential -resourceName $esxiHosts[0] | Select-Object password)
                                                $esxiHostPassword = $password.password[1]
                                                Invoke-EsxCommand -server $esxiHosts[0] -user root -pass $esxiHostPassword -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
                                                # Putting hosts in maintenance mode
                                                Write-LogMessage -Type INFO -Message "Pausing for 30 seconds before putting ESXi hosts in maintenance mode..."
                                                Start-Sleep -s 30
                                                foreach ($esxiNode in $esxiHosts) {
                                                    $password = (Get-VCFCredential -resourceName $esxi | Select-Object password)
                                                    $esxiHostPassword = $password.password[1]
                                                    Set-MaintenanceMode -server $esxiNode -user root -pass $esxiHostPassword -state ENABLE
                                                }
                                                # End of shutdown
                                                Write-LogMessage -Type INFO -Message "End of the shutdown sequence!"
                                                Write-LogMessage -Type INFO -Message "You can now shut down the ESXi hosts."
                                            } else {
                                                # vSAN shutdown wizard automation.
                                                Set-VsanClusterPowerStatus -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -PowerStatus clusterPoweredOff -mgmt
                                                Write-LogMessage -Type INFO -Message "Pausing for 60 seconds before checking ESXi hosts' shutdown status..."
                                                Start-Sleep -s 60
                                                $counter = 0
                                                $sleepTime = 60 # in seconds
                                                while ($counter -lt 1800) {
                                                    $successCount = 0
                                                    # Verify all ESXi hosts are shut down to conclude the sequence
                                                    foreach ($esxiNode in $esxiHosts) {
                                                        if (Test-VsphereConnection -server $esxiNode) {
                                                            Write-LogMessage -Type WARNING -Message "Some ESXi hosts are still up. Pausing for $sleepTime seconds before next check..."
                                                            Break
                                                        } else {
                                                            $successCount++
                                                        }
                                                    }
                                                    if ($successCount -eq $esxiWorkloadDomain.count) {
                                                        Write-LogMessage -Type INFO -Message "All ESXi hosts have been shut down successfully!"
                                                        Write-LogMessage -Type INFO -Message "Successfully completed the shutdown sequence!"
                                                        Exit
                                                    } else {
                                                        Start-Sleep -s $sleepTime
                                                        $counter += $sleepTime
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Write-LogMessage -Type INFO -Message "A single cluster exists in the management domain."
                $cluster = Get-VCFCluster | Where-Object { $_.domain.id -eq $workloadDomain.id }
            }

            $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

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

            # Test if the vCenter Server instance is reachable, if it is already stopped, do not continue with the shutdown sequence in automatic way.
            if (-Not (Test-EndpointConnection -server $vcServer.fqdn -Port 443) ) {
                Write-LogMessage -Type WARNING -Message "Could not connect to $($vcServer.fqdn)! The script could not continue without a connection to the management vCenter Server. "
                Write-LogMessage -Type ERROR -Message "Please check the current state and resolve the issue or continue with the shutdown operation by following the documentation of VMware Cloud Foundation. Exiting!"
                Exit
            }

            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            if ($status -eq $True) {
                Write-LogMessage -Type ERROR -Message "Currently we are not supporting VMware Tanzu enabled domains. Exiting..."
                Exit
            }

            if ($vcPass) {
                $vcPassEncrypted = $vcPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            } else {
                $vcPassEncrypted = $null
            }

            [Array]$allVMs = @()
            [Array]$vcfVMs = @()
            # Checks to see if the server parameter is provided as an IP address or FQDN.
            if ($server -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                $fqdn = (Get-VCFManager | Select-Object fqdn, ipAddress | Where-Object { $_.ipAddress -eq $server }).fqdn
                [Array]$vcfVMs += $fqdn.Split(".")[0]
            } else {
                [Array]$vcfVMs += $server.Split(".")[0]
            }

            [Array]$vcfVMs += ($vcServer.fqdn).Split(".")[0]

            $var["Server"] = @{}
            $var["Server"]["name"] = $vcServer.fqdn.Split(".")[0]
            $var["Server"]["fqdn"] = $vcServer.fqdn
            $var["Server"]["user"] = $vcUser
            $var["Server"]["password"] = $vcPassEncrypted

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
                $esxiPass = $esxDetails.password
                if ($esxiPass) {
                    $esxiPassEncrypted = $esxiPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                } else {
                    $esxiPassEncrypted = $null
                }
                $esxi_block["password"] = $esxiPassEncrypted
                $var["Hosts"] += $esxi_block
            }

            # Gather NSX Manager Cluster Details
            $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
            $nsxtManagerFQDN = $nsxtCluster.vipFqdn
            $nsxtManagerVIP = New-Object -TypeName PSCustomObject
            $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.credentialType -eq "API" })).username
            $nsxtManagerPass = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtManagerFQDN -and $_.credentialType -eq "API" })).password
            if ($nsxtManagerPass) {
                $nsxtManagerPassEncrypted = $nsxtManagerPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            } else {
                $nsxtManagerPassEncrypted = $null
            }
            $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $nsxmgrPass
            $nsxtNodesFQDN = $nsxtCluster.nodes.fqdn
            $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $nsxmgrPass
            $nsxtNodesFQDN = $nsxtCluster.nodes.fqdn
            $nsxtNodes = @()
            foreach ($node in $nsxtNodesFQDN) {
            foreach ($node in $nsxtNodesFQDN) {
                [Array]$nsxtNodes += $node.Split(".")[0]
                [Array]$vcfVMs += $node.Split(".")[0]
                [Array]$vcfVMs += $node.Split(".")[0]
            }
            $var["NsxtManager"] = @{}
            $var["NsxtManager"]["vipfqdn"] = $nsxtManagerFQDN
            $var["NsxtManager"]["nodes"] = $nsxtNodesFQDN
            $var["NsxtManager"]["user"] = $nsxtManagerVIP.adminUser
            $var["NsxtManager"]["password"] = $nsxManagerPassEncrypted

            # Gather NSX-T Edge Node Details
            $nsxtManagerPowerOnVMs = 0
            $nsxtManagerPowerOnVMs = 0
            foreach ($nsxtManager in $nsxtNodes) {
                $state = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch -silence
                if ($state) { $nsxtManagerPowerOnVMs += 1 }
                # If we have all NSX-T managers running, or minimum 2 nodes up - query NSX-T for edges.
                if (($nsxtManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxtManagerPowerOnVMs -eq 2)) {
                    $statusOfNsxtClusterVMs = 'running'
                }
            }
            if ($statusOfNsxtClusterVMs -ne 'running') {
                Write-LogMessage -Type WARNING -Message "NSX Manager VMs have been stopped. NSX Edge VMs will not be handled automatically."
            } else {
                Try {
                    Write-LogMessage -Type INFO -Message "NSX Manager VMs are in running state. Trying to fetch information about the NSX Edge VMs..."
                    [Array]$edgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword -VCfqdn $VcServer.fqdn)
                    $edgeNodesToString = $edgeNodes -join ","
                    Write-LogMessage -Type INFO -Message "The NSX Edge VMs are $edgeNodesToString."
                } catch {
                    Write-LogMessage -Type ERROR -Message "Something went wrong! Cannot fetch NSX Edge nodes information from NSX Manager '$nsxtManagerFQDN'. Exiting!"
                    Write-LogMessage -Type INFO -Message "The NSX Edge VMs are $edgeNodesToString."
                } Catch {
                    Write-LogMessage -Type ERROR -Message "Something went wrong! Cannot fetch NSX Edge nodes information from NSX Manager '$nsxtManagerFQDN'. Exiting!"
                }
            }

            if ($edgeNodes.count -ne 0) {
                $nsxtEdgeNodes = $edgeNodes
                $var["NsxEdge"] = @{}
                $var["NsxEdge"]["nodes"] = New-Object System.Collections.ArrayList
                foreach ($val in $edgeNodes) {
                    $var["NsxEdge"]["nodes"].add($val) | Out-Null
                    [Array]$vcfVMs += $val
                }
            }

            # Get SDDC VM name from vCenter Server
            $Global:sddcmVMName
            $Global:vcHost
            $vcHostUser = ""
            $vcHostPass = ""
            if ($vcServer.fqdn) {
                Write-LogMessage -Type INFO -Message "Getting SDDC Manager VM name ..."
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                Connect-VIServer -server $vcServer.fqdn -user $vcUser -password $vcPass | Out-Null
                $sddcManagerIP = (Get-VCFManager | Select-Object ipAddress).ipAddress
                $sddcmVMName = (Get-VM * | Where-Object { $_.Guest.IPAddress -eq $sddcManagerIP }).Name
                $vcHost = (get-vm | Where-Object Name -EQ $vcServer.fqdn.Split(".")[0] | Select-Object VMHost).VMHost.Name
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
                    Write-LogMessage -Type INFO -Message "#############################################################"
                    Write-LogMessage -Type INFO -Message "JSON generation is successful!"
                    Write-LogMessage -Type INFO -Message "ManagementStartupInput.json is created in the $location path."
                    Write-LogMessage -Type INFO -Message "#############################################################"
                    Exit
                } else {
                    Write-LogMessage -Type ERROR -Message "JSON file is not created. Check for permissions in the $location path"
                    Exit
                }
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Cannot obtain an access token from SDDC Manager ($server). Check your credentials."
            Exit
        }

        # Shutdown related code starts here
        if ([float]$vcfVersion -lt [float]4.5) {
            # Check if SSH is enabled on the ESXI hosts before proceeding with the shutdown procedure.
            Try {
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    if (Test-VsphereConnection -server $esxiNode) {
                        $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                        if (-Not $status) {
                            Write-LogMessage -Type ERROR -Message "Unable to establish an SSH connection to ESXi host $($esxiNode.fqdn). SSH is not enabled. Exiting..."
                            Exit
                        }
                    } else {
                        Write-LogMessage -Type ERROR -Message "Unable to connect to ESXi host $($esxiNode.fqdn). Exiting..."
                        Exit
                    }
                }
            } Catch {
                Write-LogMessage -Type ERROR -Message $_.Exception.Message
                Exit
            }
        } else {
            #Lockdown mode - if enabled on any host, stop the script
            Test-LockdownMode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            #Check if hosts are out of maintenance mode before cluster shutdown
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $HostConnectionState = Get-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if ($HostConnectionState -eq "Maintenance") {
                    Write-LogMessage -Type ERROR -Message "$($esxiNode.fqdn) is in maintenance mode. Unable to shut down the cluster. Please take the host out of maintenance mode and run the script again."
                    Exit
                }
            }
        }

        if (Test-VCFConnection -server $server) {
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                $allWorkloadvCenters = @()
                $allWorkloadvCenters = (Get-VCFWorkloadDomain | Select-Object type -ExpandProperty vcenters | Where-Object { $_.type -eq "VI" }).fqdn
                if ($allWorkloadvCenters) {
                    $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                    if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                        if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                            if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                $allWorkloadvCenters | ForEach-Object {
                                    $vm = $_.Split('.')[0]
                                    $isPoweredOn = (Get-VM | Select-Object Name, PowerState | Where-Object { $_.name -eq $vm }).PowerState
                                    if ($isPoweredOn -eq "PoweredOn") {
                                        $answer = Read-Host -Prompt "Workload domain vCenter Server instance $vm is powered on. Do you want to continue shutdown of the management domain? Y/N"
                                        if ($answer -Match 'N') {
                                            Write-LogMessage -Type ERROR "Please shutdown the workload domain vCenter Server instance $vm and retry. Exiting..."
                                            Exit
                                        } else {
                                            Write-LogMessage -Type INFO "Continuing with the shutdown of the management domain."
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Write-LogMessage -Type INFO -Message "Trying to fetch all powered-on virtual machines from server $($vcServer.fqdn)..."
        [Array]$allVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
        $customerVMs = @()

        Write-LogMessage -Type INFO -Message "Trying to fetch all powered-on vCLS virtual machines from server $($vcServer.fqdn)..."
        [Array]$vclsvms += Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence
        foreach ($vm in $vclsvms) {
            [Array]$vcfVMs += $vm
        }

            Write-LogMessage -Type INFO -Message "Fetching all powered on vSAN File Services virtual machines from vCenter Server instance $($vcenter)..."
            [Array]$vsanFsVMs += Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(vSAN File)" -silence
        foreach ($vm in $vsanFsVMs) {
            [Array]$vcfVMs += $vm
        }

        $customerVMs = $allVMs | Where-Object { $vcfVMs -notcontains $_ }
        $vcfVMs_string = $vcfVMs -join "; "
        Write-LogMessage -Type INFO -Message "Management virtual machines covered by the script: '$($vcfVMs_string)' ."
        if ($customerVMs.count -ne 0) {
            $customerVMs_string = $customerVMs -join "; "
            Write-LogMessage -Type INFO -Message "Virtual machines not covered by the script: '$($customerVMs_string)' . Those VMs will be stopped in a random order if the 'shutdownCustomerVm' flag is passed."
        }

        # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
            $VMwareToolsNotRunningVMs = @()
            $VMwareToolsRunningVMs = @()
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if ( Test-EndpointConnection -server $vcServer.fqdn -Port 443 ) {
                Write-LogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                    Write-LogMessage -Type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get VMwareTools Status."
                    foreach ($vm in $customerVMs) {
                        Write-LogMessage -Type INFO -Message "Checking VMwareTools Status for '$vm'..."
                        $vm_data = Get-VM -Name $vm
                        if ($vm_data.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
                            [Array]$VMwareToolsRunningVMs += $vm
                        } else {
                            [Array]$VMwareToolsNotRunningVMs += $vm
                        }
                    }
                } else {
                    Write-LogMessage -Type ERROR -Message "Unable to connect to vCenter Server '$($vcServer.fqdn)'. Command returned the following error: '$vcConnectError'."
                }
            }
            # Disconnect from the VC
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if ($VMwareToolsNotRunningVMs.count -ne 0) {
                $noToolsVMs = $VMwareToolsNotRunningVMs -join "; "
                Write-LogMessage -Type WARNING -Message "There are some non VCF maintained VMs where VMwareTools NotRunning, hence unable to shutdown these VMs:'$noToolsVMs'."
                Write-LogMessage -Type ERROR -Message "Unless these VMs are shutdown manually, we cannot proceed. Please shutdown manually and rerun the script."
                Exit
            }
        }

        if ($customerVMs.count -ne 0) {
            $customerVMs_string = $customerVMs -join "; "
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                Write-LogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is passed to the script."
                Write-LogMessage -Type WARNING -Message "Hence shutting down VMs not managed by SDDC Manager to put the host in maintenance mode."
                Write-LogMessage -Type WARNING -Message "The list of Non VCF management VMs: '$customerVMs_string'."
                # Stop Customer VMs with one call to VC:
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $customerVMs -timeout 300
            } else {
                Write-LogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is not passed to the script."
                Write-LogMessage -Type WARNING -Message "Hence not shutting down management VMs not managed by SDDC Manager: $($customerVMs_string) ."
                Write-LogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shut down manually or the -shutdownCustomerVm option is present.  Take the necessary action and run the script again."
                Exit
            }
        }
        # TODO - Make sure that this code could be reached. Add a switch to enable vRLI shutdown
        # Check if VMware Aria Operations for Logs exists in environment, if so it will shutdown the nodes.
        if (Test-VCFConnection -server $server) {
            # TODO - Fix exception if there is no vRSLCM installed in the environment
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                if (($vcfVrslcmDetails = Get-vRSLCMServerDetail -fqdn $server -username $user -password $pass)) {
                    if (Test-vRSLCMAuthentication -server $vcfVrslcmDetails.fqdn -user $vcfVrslcmDetails.adminUser -pass $vcfVrslcmDetails.adminPass) {
                        $productid = "vrli"
                        $vmList = Get-vRSLCMEnvironmentVMs -server $server -user $user -pass $pass -productid $productid
                        if ($null -ne $vmList) {
                            $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                            if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                                if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                                    if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                        Write-LogMessage -Type INFO -Message "Stopping the VMware Aria Operations for Logs nodes..."
                                        Stop-CloudComponent -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -nodes $vmList -timeout 600
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        # TODO - Find the right spot for this code. Fix may required.
        # Check if there are any running Virtual Machines on the Overlay Networks before shutting down Edge Cluster.
        if ($nsxtEdgeNodes) {
            if (Test-VCFConnection -server $server) {
                if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                    $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                    if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                        if (Test-vSphereConnection -server $($vcfVcenterDetails.fqdn)) {
                            if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                                if (($vcfNsxDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain.name)) {
                                    if (Test-NSXTConnection -server $vcfNsxDetails.fqdn) {
                                        if (Test-NSXTAuthentication -server $vcfNsxDetails.fqdn -user $vcfNsxDetails.adminUser -pass $vcfNsxDetails.adminPass) {
                                            $nsx_segments = Get-NsxtSegment | Select-Object display_name, type | Where-Object { $_.type -eq "ROUTED" }
                                            foreach ($segment in $nsx_segments) {
                                                $segmentName = $segment.display_name
                                                $cloudVMs = Get-VM | Get-NetworkAdapter | Where-Object { $_.NetworkName -eq $segmentName } | Select-Object Parent
                                                $cloudVMs = Get-VM | Get-NetworkAdapter | Where-Object { $_.NetworkName -eq $segmentName } | Select-Object Parent
                                            }
                                            $vmList = $cloudVMs.Parent
                                            $vmList = $cloudVMs.Parent
                                            $stopExecuted = $false
                                            foreach ($vm in $vmList) {
                                            foreach ($vm in $vmList) {
                                                $vmName = $vm.Name
                                                $powerState = $vm.PowerState
                                                if ($powerState -eq "PoweredOn") {
                                                    Write-LogMessage -Type Error -Message "VM Name: $vmName, Power State: $powerState, Please power off the virtual machines connected to NSX Segments before you shutdown an NSX Edge Cluster"
                                                    $stopExecuted = $true
                                                }
                                                if (-not $stopExecuted) {
                                                    Write-LogMessage -Type INFO -Message "Stopping the NSX Edge nodes..."
                                                    Stop-CloudComponent -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -nodes $nsxtEdgeNodes -timeout 600
                                                    $stopExecuted = $true
                                                }
                                            }
                                        } else {
                                            Write-LogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping shutdown..."
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
        Write-LogMessage -Type INFO -Message "Stopping the NSX Manager nodes..."
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600


        #Check the vSAN health before SDDC manager is stopped
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-LogMessage -Type INFO -Message "vSAN cluster health is good."
        } else {
            Write-LogMessage -Type WARNING -Message "The vSAN cluster isn't in a healthy state. Check the vSAN cluster status in vCenter Server '$($vcServer.fqdn)'. After you resolve the vSAN health issues, run the script again."
            Write-LogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue the shutdown workflow by following the documentation of VMware Cloud Foundation. "
            Write-LogMessage -Type ERROR -Message "The vSAN cluster isn't in a healthy state. Check the messages above for a solution."
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-LogMessage -Type INFO -Message "vSAN object resynchronization is successful."
        } else {
            Write-LogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script... Wait until the vSAN object resynchronization is completed and run the script again."
            Exit
        }

        # Shut Down the SDDC Manager Virtual Machine in the Management Domain.
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600


        # Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable

        # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
        Write-LogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take time. Please wait!"
        $counter = 0
        $retries = 10
        $sleepTime = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount ) {
                Write-LogMessage -Type INFO -Message "Some vCLS VMs are still running. Sleeping for $sleepTime seconds until the next check..."
                Start-Sleep -s $sleepTime
                $counter += 1
            } else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-LogMessage -Type ERROR -Message "The vCLS VMs were not shut down within the expected time. Stopping the script execution... "
            Exit
        }

        # Workflow for VMware Cloud Foundation before version 4.5
        if ([float]$vcfVersion -le [float]4.5) {
            # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                Write-LogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!"
            }

            # Set DRS Automation Level to Manual in the Management Domain
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level Manual
        }

        # Check if there are VMs running on a vSAN HCI Mesh
        $remoteVMs = @()
        $remoteVMs = Get-PowerOnVMsOnRemoteDS -server $vcServer.fqdn -user $vcUser -pass $vcPass -clustertocheck $cluster.name
        if ($remoteVMs.count -eq 0) {
            Write-LogMessage -Type INFO -Message "All remote VMs are powered off."
        } else {
            Write-LogMessage -Type ERROR -Message "Some remote VMs are still powered-on : $($remoteVMs.Name). Cannot proceed until the powered-on VMs are shut down. Check your environment."
        }

        #Testing VSAN health after SDDC manager is stopped
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-LogMessage -Type INFO -Message "vSAN cluster health is good."
        } else {
            Write-LogMessage -Type WARNING -Message "The vSAN cluster isn't in a healthy state. Check the vSAN status in vCenter Server '$($vcServer.fqdn)'. After you resolve the vSAN issues, run the script again."
            Write-LogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue by following the documentation of VMware Cloud Foundation. "
            Write-LogMessage -Type ERROR -Message "The vSAN cluster isn't in a healthy state. Check the messages above for a solution."
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-LogMessage -Type INFO -Message "VSAN object resynchronization is successful."
        } else {
            Write-LogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script. Wait until the vSAN object resynchronization is completed and run the script again."
            Exit
        }

        if ([float]$vcfVersion -lt [float]4.5) {
            # Verify that there is only one VM running (vCenter Server) on the ESXis, then shutdown vCenter Server.
            $runningVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
            if ($runningVMs.count -gt 1 ) {
                Write-LogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                Write-LogMessage -Type WARNING -Message "Cannot proceed until the powered-on VMs are shut down. Shut them down them manually and continue with the shutdown operation by following documentation of VMware Cloud Foundation."
                Write-LogMessage -Type ERROR -Message "There are running VMs in environment: $($runningVMs). Exiting! "
            } else {
                Write-LogMessage -Type INFO -Message "There are no VMs in powered-on state. Hence, shutting down vCenter Server..."
                # Shutdown vCenter Server
                Stop-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -timeout 600
                if (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running") {
                    Write-LogMessage -Type ERROR -Message "Cannot stop vCenter Server on the host. Exiting!"
                }
            }
        }
        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        Write-LogMessage -Type INFO -Message "Checking that there are no running VMs on the ESXi hosts before stopping vSAN."
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
                $runningVMs = $runningAllVMs | Where-Object { $runningVclsVMs -notcontains $_ }
            }
            if ($runningVMs.count) {
                Write-LogMessage -Type WARNING -Message "Some VMs are still in powered-on state."
                Write-LogMessage -Type WARNING -Message "Cannot proceed until the powered-on VMs are shut down. Shut down them down manually and run the script again."
                Write-LogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn) VMs are:$($runningVMs) "
                $runningVMsPresent = $True
            }
        }
        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        if ($runningVMsPresent) {
            Write-LogMessage -Type ERROR -Message "Some VMs on the ESXi hosts are still in powered-on state. Check the console log, stop the VMs and continue the shutdown operation manually."
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
                Write-LogMessage -Type INFO -Message "Sleeping for 60 seconds before preparing hosts for vSAN shutdown..."
                Start-Sleep -s 60
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
                # Putting hosts in maintenance mode
                Write-LogMessage -Type INFO -Message "Sleeping for 30 seconds before putting hosts in maintenance mode..."
                Start-Sleep -s 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
                }
                # End of shutdown
                Write-LogMessage -Type INFO -Message "End of the shutdown sequence!"
                Write-LogMessage -Type INFO -Message "Shut down the ESXi hosts!"
            } else {

                # vSAN shutdown wizard automation.
                Set-VsanClusterPowerStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -PowerStatus clusterPoweredOff -mgmt

                Write-LogMessage -Type INFO -Message "Sleeping for 60 seconds before checking ESXi hosts' shutdown status..."
                Start-Sleep -s 60

                $counter = 0
                $sleepTime = 60 # in seconds
                $maxSecondsToWait = 1800 # 30 minutes
                #TODO - Add better reporting which hosts are still up
                while ($counter -lt $maxSecondsToWait) {
                    $successCount = 0
                    #Verify if all ESXi hosts are down in here to conclude End of Shutdown sequence
                    foreach ($esxiNode in $esxiWorkloadDomain) {
                        if (Test-EndpointConnection -server $esxiNode.fqdn -Port 443) {
                            Write-LogMessage -Type WARNING -Message "Some hosts are still up. Sleeping for 60 seconds before next check..."
                            break
                        } else {
                            $successCount++
                        }
                    }
                    if ($successCount -eq $esxiWorkloadDomain.count) {
                        Write-LogMessage -Type INFO -Message "All hosts have been shut down successfully!"
                        Write-LogMessage -Type INFO -Message "End of the shutdown sequence!"
                        Exit
                    } else {
                        Start-Sleep -s $sleepTime
                        $counter += $sleepTime
                    }
                }
            }
        }
    } Catch {
        Write-DebugMessage -object $_
        Exit
    }
}


# Startup procedures
if ($PsBoundParameters.ContainsKey("startup")) {
    Try {
        $MgmtInput = Get-Content -Path $inputFile | ConvertFrom-Json
        Write-LogMessage -Type INFO -Message "Gathering system details from JSON file..."
        # Gather Details from SDDC Manager
        $workloadDomain = $MgmtInput.Domain.name
        $cluster = New-Object -TypeName PSCustomObject
        $cluster | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Cluster.name

        #Get DRS automation level settings
        $drsAutomationLevel = $MgmtInput.cluster.DrsAutomationLevel

        #Getting SDDC manager VM name
        $sddcmVMName = $MgmtInput.SDDC.name
        $vcfVersion = $MgmtInput.SDDC.version

        # Gather vCenter Server Details and Credentials
        $vcServer = New-Object -TypeName PSCustomObject
        $vcServer | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Server.name
        $vcServer | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Server.fqdn
        $vcUser = $MgmtInput.Server.user
        $temp_pass = ConvertTo-SecureString -String $MgmtInput.Server.password
        $temp_pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($temp_pass))))
        $vcPass = $temp_pass
        $vcHost = $MgmtInput.Server.host
        $vcHostUser = $MgmtInput.Server.vchostuser
        if ($MgmtInput.Server.vchostpassword) {
            $vcHostPassword = ConvertTo-SecureString -String $MgmtInput.Server.vchostpassword
            $vcHostPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vcHostPassword))))
        } else {
            $vcHostPassword = $null
        }
        $vcHostPass = $vcHostPassword

        # Gather ESXi Host Details for the Management Workload Domain
        $esxiWorkloadDomain = @()
        $workloadDomainArray = $MgmtInput.Hosts
        foreach ($esxiHost in $workloadDomainArray) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost.fqdn
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value $esxiHost.user
            if ($esxiHost.password) {
                $esxPassword = ConvertTo-SecureString -String $esxiHost.password
                $esxPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($esxPassword))))
            } else {
                $esxPassword = $null
            }
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value $esxPassword
            $esxiWorkloadDomain += $esxDetails
        }

        # Gather NSX Manager Cluster Details
        $nsxtCluster = $MgmtInput.NsxtManager
        $nsxtManagerFQDN = $MgmtInput.NsxtManager.vipfqdn
        $nsxtManagerVIP = New-Object -TypeName PSCustomObject
        $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.NsxtManager.user
        if ($MgmtInput.NsxtManager.password) {
            $nsxPassword = ConvertTo-SecureString -String $MgmtInput.NsxtManager.password
            $nsxPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($nsxPassword))))
        } else {
            $nsxPassword = $null
        }
        $nsxtManagerVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $nsxPassword
        $nsxtNodesFQDN = $MgmtInput.NsxtManager.nodes
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesFQDN) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }


        # Gather NSX Edge Node Details
        $nsxtEdgeCluster = $MgmtInput.NsxEdge
        $nsxtEdgeNodes = $nsxtEdgeCluster.nodes

        # Startup workflow starts here
        # Check if VC is running - if so, skip ESXi operations
        if (-Not (Test-EndpointConnection -server $vcServer.fqdn -Port 443 -WarningAction SilentlyContinue )) {
            Write-LogMessage -Type INFO -Message "Could not connect to $($vcServer.fqdn). Starting vSAN..."
            if ([float]$vcfVersion -gt [float]4.4) {
                #TODO add check if hosts are up and running. If so, do not display this message
                Write-Host ""
                $proceed = Read-Host "Please start all the ESXi host belonging to the cluster '$($cluster.name)' and wait for the host console to come up. Once done, please enter yes."
                if (-Not $proceed) {
                    Write-LogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence, stopping script execution..."
                    Exit
                } else {
                    if (($proceed -match "no") -or ($proceed -match "yes")) {
                        if ($proceed -match "no") {
                            Write-LogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'..."
                            Exit
                        }
                    } else {
                        Write-LogMessage -Type WARNING -Message "Pass the right string - either 'Yes' or 'No'."
                        Exit
                    }
                }

                foreach ($esxiNode in $esxiWorkloadDomain) {
                    if (!(Test-EndpointConnection -server $esxiNode.fqdn -Port 443)) {
                        Write-LogMessage -Type ERROR -Message "Cannot communicate with host $($esxiNode.fqdn). Check the FQDN or IP address, or the power state of '$($esxiNode.fqdn)'."
                        Exit
                    }
                }
            } else {
                #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
                Try {
                    foreach ($esxiNode in $esxiWorkloadDomain) {
                        if (Test-VsphereConnection -server $esxiNode) {
                            $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                            if (-Not $status) {
                                Write-LogMessage -Type ERROR -Message "Unable to establish an SSH connection to ESXi host $($esxiNode.fqdn). SSH is not enabled. Exiting..."
                                Exit
                            }
                        } else {
                            Write-LogMessage -Type ERROR -Message "Unable to connect to ESXi host $($esxiNode.fqdn). Exiting..."
                            Exit
                        }
                    }
                } Catch {
                    Write-LogMessage -Type ERROR -Message $_.Exception.Message
                    Exit
                }

                # Take hosts out of maintenance mode
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
                }
            }
            if ([float]$vcfVersion -lt [float]4.5) {
                # Prepare the vSAN cluster for startup - Performed on a single host only
                # We need some time before this step, setting hard sleep 30 sec
                Write-LogMessage -Type INFO -Message "Sleeping for 30 seconds before starting vSAN..."
                Start-Sleep -s 30
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

                # We need some time before this step, setting hard sleep 30 sec
                Write-LogMessage -Type INFO -Message "Sleeping for 30 seconds before enabling vSAN updates..."
                Start-Sleep -s 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                }

                Write-LogMessage -Type INFO -Message "Checking vSAN status of the ESXi hosts."
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                }

                # Startup the Management Domain vCenter Server
                Start-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.Name -timeout 600
                Start-Sleep -s 5
                if (-Not (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running")) {

                    Write-LogMessage -Type Warning -Message "Cannot start vCenter Server on the host. Check if vCenter Server is located on host $vcHost. "
                    Write-LogMessage -Type Warning -Message "Start vCenter Server manually and run the script again."
                    Write-LogMessage -Type ERROR -Message "Could not start vCenter Server on host $vcHost. Check the console log for more details."
                    Exit
                }
            }
        } else {
            Write-LogMessage -Type INFO -Message "vCenter Server '$($vcServer.fqdn)' is running. Skipping vSAN startup!"
        }

        # Wait till VC is started, continue if it is already up and running
        Write-LogMessage -Type INFO -Message "Waiting for the vCenter Server services on $($vcServer.fqdn) to start..."
        $retries = 20
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
                        break
                    } else {
                        Write-LogMessage -Type INFO -Message "The services on vCenter Server are still starting. Please wait. Sleeping for 60 seconds..."
                        Start-Sleep -s 60
                    }
                }
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Write-LogMessage -Type INFO -Message "The vCenter Server API is still not accessible. Please wait. Sleeping for 60 seconds..."
            Start-Sleep -s 60
            $retries -= 1
        }
        # Check if VC have been started in the above time period
        if (!$retries) {
            Write-LogMessage -Type ERROR -Message "Timeout while waiting vCenter Server to start. Exiting!"
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
            Write-LogMessage -Type ERROR -Message "vSAN cluster health is bad. Check your environment and run the script again."
            Exit
        }
        # Check vSAN Status
        if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-LogMessage -Type ERROR -Message "vSAN object resynchronization is in progress. Check your environment and run the script again."
            Exit
        }

        #Start workflow for VCF prior version 4.5
        if ([float]$vcfVersion -lt [float]4.5) {
            # Start vSphere HA
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
                Write-LogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'."
            }

            # Restore the DRS Automation Level to the mode backed up for Management Domain Cluster during shutdown
            if ([string]::IsNullOrEmpty($drsAutomationLevel)) {
                Write-LogMessage -Type ERROR -Message "The DrsAutomationLevel value in the JSON file is empty. Exiting!"
                Exit
            } else {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level $drsAutomationLevel
            }
        }

        # Startup the vSphere Cluster Services Virtual Machines in the Management Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
        # Waiting for vCLS VMs to be started for ($retries*10) seconds
        Write-LogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS virtual machines startup will take some time. Please wait."
        $counter = 0
        $retries = 10
        $sleepTime = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence).count
            if ( $powerOnVMcount -lt 3 ) {
                Write-LogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleepTime seconds until the next check."
                Start-Sleep -s $sleepTime
                $counter += 1
            } else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-LogMessage -Type ERROR -Message "The vCLS virtual machines did not start within the expected time. Stopping script execution..."
            Exit
        }

        #Startup the SDDC Manager Virtual Machine in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600
        # TODO - Add check for SDDC Manager status

        # Startup the NSX Manager Nodes in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtManagerFQDN -user $nsxtManagerVIP.adminUser -pass $nsxtManagerVIP.adminPassword)) {
            Write-LogMessage -Type ERROR -Message "The NSX Manager cluster is not in 'STABLE' state. Exiting!"
            Exit
        }

        # Startup the NSX Edge Nodes in the Management Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        } else {
            Write-LogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping startup..."
        }
        if (-Not (Test-VCFConnection -server $server )) {
            Write-LogMessage -Type INFO -Message "Could not connect to $server..."
        }
        if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
            $mgmtClusterIds = @()
            $mgmtClusterIds = (Get-VCFWorkloadDomain | Select-Object Type -ExpandProperty clusters | Where-Object { $_.type -eq "MANAGEMENT" }).id
            # Checks to see how many Clusters are in Management Domain
            if ($mgmtClusterIds.Count -ge 2) {
                foreach ($clusterId in $mgmtClusterIds) {
                    $clusterId = (Get-VCFCluster | Select-Object name, id, isdefault | Where-Object { $_.id -eq $clusterId })
                    $clusterName = $clusterId.name
                    $isDefault = $clusterId.isDefault
                    if (!$isDefault) {
                        $answer = Read-Host -Prompt "Start up cluster $clusterName, Do you want to continue? Y/N"
                        if ($answer -Match 'N') {
                            Write-LogMessage -Type WARNING "Cancelled start up of $clusterName. Exiting..."
                            Exit
                        } else {
                            Write-LogMessage -Type INFO "Will Move Forward with start up of $clusterName"
                        }
                        $esxiHosts = (Get-VCFHost | Select-Object fqdn -ExpandProperty cluster | Where-Object { $_.id -eq $clusterId.id }).fqdn
                        foreach ($esxiNode in $esxiHosts) {
                            if (-Not (Test-VsphereConnection -server $esxiNode)) {
                                Write-LogMessage -Type WARNING "ESXi host $esxiNode is not powered on...."
                            } else {
                                $password = (Get-VCFCredential -resourceName $esxiNode | Select-Object password)
                                $esxiHostPassword = $password.password[1]
                                $status = Get-SSHEnabledStatus -server $esxiNode -user root -pass $esxiHostPassword
                                if (-Not $status) {
                                    if (Test-vSphereAuthentication -server $esxi -user root -pass $esxiHostPassword) {
                                        Write-LogMessage -Type WARNING "SSH is not enabled on $esxiNode, enabling it now..."
                                        Get-VmHostService -VMHost $esxiNode | Where-Object { $_.key -eq "TSM-SSH" } | Start-VMHostService
                                        Start-Sleep -s 10
                                        Write-LogMessage -Type INFO "Attempting to Set Maintenance Mode on $esxiNode to DISABLE"
                                        Set-MaintenanceMode -server $esxiNode -user root -pass $esxiHostPassword -state DISABLE
                                        Start-Sleep -s 120
                                    } else {
                                        Write-LogMessage -Type ERROR "Unable to authenticate to $esxiNode. Exiting..."
                                        Exit
                                    }
                                } else {
                                    if (Test-vSphereAuthentication -server $esxi -user root -pass $esxiHostPassword) {
                                        Write-LogMessage -Type INFO "Attempting to Set Maintenance Mode on $esxiNode to DISABLE"
                                        Set-MaintenanceMode -server $esxiNode -user root -pass $esxiHostPassword -state DISABLE
                                        Start-Sleep -s 120
                                    } else {
                                        Write-LogMessage -Type ERROR "Unable to authenticate to $esxiNode. Exiting..."
                                        Exit
                                    }
                                }
                            }
                        }
                        Write-LogMessage -Type INFO -Message "Pausing for 30 seconds while hosts come out of maintenance mode..."
                        Start-Sleep -s 30
                        if ([float]$vcfVersion -lt [float]4.5) {
                            # Prepare the vSAN cluster for startup - Performed on a single host only
                            # We need some time before this step, setting hard sleep 30 sec
                            Write-LogMessage -Type INFO -Message "Pausing for 30 seconds before starting vSAN..."
                            $password = (Get-VCFCredential -resourceName $esxiHosts[0] | Select-Object password)
                            $esxiHostPassword = $password.password[1]
                            Invoke-EsxCommand -server $esxiHosts[0] -user root -pass $esxiHostPassword -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"
                            # We need some time before this step, setting hard sleep 30 sec
                            Write-LogMessage -Type INFO -Message "Pausing for 30 seconds before enabling vSAN updates..."
                            Start-Sleep -s 30
                            foreach ($esxi in $esxiHosts) {
                                $password = (Get-VCFCredential -resourceName $esxi | Select-Object password)
                                $esxiHostPassword = $password.password[1]
                                if (Test-vSphereAuthentication -server $esxi -user root -pass $esxiHostPassword) {
                                    Write-LogMessage -Type INFO -Message "Set hosts to ignoreClusterMemberListUpdates"
                                    Invoke-EsxCommand -server $esxi -user root -pass $esxiHostPassword -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                                }
                            }

                            Write-LogMessage -Type INFO -Message "Checking vSAN status of the ESXi hosts..."
                            foreach ($esxiNode in $esxiHosts) {
                                $password = (Get-VCFCredential -resourceName $esxi | Select-Object password)
                                $esxiHostPassword = $password.password[1]
                                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                            }
                        }
                        $domain = Get-VCFWorkloadDomain | Select-Object name, type | Where-Object { $_.type -eq "MANAGEMENT" }
                        if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name)) {
                            if (Test-vSphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {

                                # Start the vSAN cluster wizard.
                                if ([float]$vcfVersion -gt [float]4.5) {
                                    # Lockdown mode check
                                    Test-LockdownMode -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName
                                    # Restart cluster using wizard
                                    Set-VsanClusterPowerStatus -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -PowerStatus clusterPoweredOn
                                }
                                # Check vSAN Status
                                if ( (Test-VsanHealth -cluster $clusterName -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) -ne 0) {
                                    Write-LogMessage -Type WARNING -Message "vSAN cluster is in an unhealthy state. Check the vSAN status in cluster '$($clusterName)'. Retry after resolving the vSAN health state. Exiting..."
                                    Exit
                                }
                                if ( (Test-VsanObjectResync -cluster $clusterName -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) -ne 0) {
                                    Write-LogMessage -Type ERROR -Message "vSAN object resynchronization failed. Check your environment and run the script again."
                                    Exit
                                }

                                # Start workflow for VCF prior version 4.5
                                # Start vSphere HA
                                if (!$(Set-VsphereHA -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -enableHA)) {
                                    Write-LogMessage -Type ERROR -Message "Unable to enable vSphere High Availability for cluster '$cluster'. Exiting..."
                                    Exit
                                }

                                # Restore the DRS Automation Level to the mode backed up for Management Domain Cluster during shutdown
                                if ([string]::IsNullOrEmpty($drsAutomationLevel)) {
                                    Write-LogMessage -Type ERROR -Message "Unable to enable Drs Automation Level for cluster '$cluster'. Exiting..."
                                    Exit
                                } else {
                                    Set-DrsAutomationLevel -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -level $drsAutomationLevel
                                }

                                # Startup the vSphere Cluster Services Virtual Machines in the Management Workload Domain
                                Set-Retreatmode -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -cluster $clusterName -mode disable
                                # Waiting for vCLS VMs to be started for ($retries*10) seconds
                                $counter = 0
                                $retries = 10
                                $sleepTime = 30
                                while ($counter -ne $retries) {
                                    $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence).count
                                    if ( $powerOnVMcount -lt 3 ) {
                                        Write-LogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS virtual machines startup will take some time. Please wait..."
                                        Start-Sleep -s $sleepTime
                                        $counter += 1
                                    } else {
                                        Break
                                    }
                                }
                                if ($counter -eq $retries) {
                                    Write-LogMessage -Type ERROR -Message "vCLS virtual machines did not start within the expected time. Exiting..."
                                    Exit
                                }
                            }
                        }
                    }
                }
            }
        }

        Write-LogMessage -Type INFO -Message "##################################################################################"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-LogMessage -Type INFO -Message "vSphere vSphere High Availability has been enabled by the script. Please disable it according to your environment's design."
        }
        Write-LogMessage -Type INFO -Message "Check your environment and start any additional virtual machines that you host in the management domain."
        Write-LogMessage -Type INFO -Message "Use the following command to automatically start VMs"
        Write-LogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-LogMessage -Type WARNING -Message "If you have enabled SSH for the ESXi hosts in management domain, disable it at this point."
            Write-LogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts in management domain, disable it at this point."
        }
        if ([float]$vcfVersion -gt [float]4.4) {
            Write-LogMessage -Type WARNING -Message "If you have disabled lockdown mode for the ESXi hosts in management domain, enable it back at this point."
            Write-LogMessage -Type INFO -Message "If you have disabled lockdown mode for the ESXi hosts in management domain, enable it back at this point."
        }
        Write-LogMessage -Type INFO -Message "##################################################################################"
        Write-LogMessage -Type INFO -Message "End of the startup sequence!"
        Write-LogMessage -Type INFO -Message "##################################################################################"
    } Catch {
        Write-DebugMessage -object $_
        Exit
    }
}
        Write-LogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-LogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts in management domain, disable it at this point."
        }
        if ([float]$vcfVersion -gt [float]4.4) {
            Write-LogMessage -Type INFO -Message "If you have disabled lockdown mode for the ESXi hosts in management domain, enable it back at this point."
        }
        Write-LogMessage -Type INFO -Message "##################################################################################"
        Write-LogMessage -Type INFO -Message "End of the startup sequence!"
        Write-LogMessage -Type INFO -Message "##################################################################################"
    } Catch {
        Write-DebugMessage -object $_
        Exit
    }
}
        Write-LogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600"
        if ([float]$vcfVersion -lt [float]4.5) {
            Write-LogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts in management domain, disable it at this point."
        }
        if ([float]$vcfVersion -gt [float]4.4) {
            Write-LogMessage -Type INFO -Message "If you have disabled lockdown mode for the ESXi hosts in management domain, enable it back at this point."
        }
        Write-LogMessage -Type INFO -Message "##################################################################################"
        Write-LogMessage -Type INFO -Message "End of the startup sequence!"
        Write-LogMessage -Type INFO -Message "##################################################################################"
    } Catch {
        Write-DebugMessage -object $_
        Exit
    }
}
