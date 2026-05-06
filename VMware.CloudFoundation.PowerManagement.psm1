# © Broadcom. All Rights Reserved.
# The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-2

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Requires PowerShell 7.4 or later (Core edition only).
# Enable communication with self-signed certificates. Remove or gate this block if strict certificate
# validation is required in your environment.
$PSDefaultParameterValues["Invoke-RestMethod:SkipCertificateCheck"] = $true
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

# Script-scope logging state (initialized here; set by New-LogFile before first use).
$Script:LogFile = $null
$Script:LogOnly = $null
$Script:ConfiguredLogLevel = "INFO"
$Script:LogLevelHierarchy = @{
    "DEBUG"     = 0
    "INFO"      = 1
    "WARNING"   = 2
    "EXCEPTION" = 3
    "ERROR"     = 4
}

##########################################################################
#region Private functions
Function Get-Password {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword', 'Password',
        Justification = 'VCF credential APIs return plain-text passwords; SecureString conversion is deferred to the caller.'
    )]
    Param (
        [Parameter(Mandatory = $false)] [String]$Password,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    if ([String]::IsNullOrEmpty($Password)) {
        $secureString = Read-Host -Prompt "Enter the password for $User" -AsSecureString
        $Password = ConvertFrom-SecureString $secureString -AsPlainText
    }
    return $Password
}
Function Test-LogLevel {
    # Returns $true when MessageType meets or exceeds the configured log level threshold.
    Param (
        [Parameter(Mandatory = $true)] [ValidateSet("DEBUG", "INFO", "WARNING", "EXCEPTION", "ERROR")] [String]$ConfiguredLevel,
        [Parameter(Mandatory = $true)] [ValidateSet("DEBUG", "INFO", "WARNING", "EXCEPTION", "ERROR")] [String]$MessageType
    )

    return ($Script:LogLevelHierarchy[$MessageType] -ge $Script:LogLevelHierarchy[$ConfiguredLevel])
}
Function New-LogFile {

    <#
        .SYNOPSIS
        Creates the log file and sets Script:LogFile for this module session.

        .DESCRIPTION
        Establishes the logging infrastructure by creating a timestamped log file under the
        specified directory. Sets the script-scoped $Script:LogFile variable used by
        Write-LogMessage. Creates the directory if it does not exist.

        .PARAMETER Directory
        Directory in which to create the log file. Defaults to a "logs" sub-folder
        under $PSScriptRoot of the calling script.

        .PARAMETER Prefix
        Prefix for the log file name. The file will be named "{Prefix}-yyyy-MM-dd.log".

        .EXAMPLE
        New-LogFile -Directory $PSScriptRoot -Prefix "PowerManagement-WorkloadDomain"
        Creates "PowerManagement-WorkloadDomain-2026-05-06.log" in $PSScriptRoot.
    #>

    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $false)] [String]$Directory,
        [Parameter(Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Prefix = "PowerManagement"
    )

    if ([String]::IsNullOrWhiteSpace($Directory)) {
        $Directory = Join-Path -Path $PSScriptRoot -ChildPath "logs"
    }

    if (-not (Test-Path -Path $Directory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($Directory, "Create log directory")) {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }
    }

    $fileDate = Get-Date -Format "yyyy-MM-dd"
    $Script:LogFile = Join-Path -Path $Directory -ChildPath "$Prefix-$fileDate.log"

    if (-not (Test-Path -Path $Script:LogFile)) {
        if ($PSCmdlet.ShouldProcess($Script:LogFile, "Create log file")) {
            New-Item -ItemType File -Path $Script:LogFile | Out-Null
        }
    }
}
Function Write-LogMessage {

    <#
        .SYNOPSIS
        Writes a severity-colored message to the console and appends it to the log file.

        .DESCRIPTION
        Centralized logging for the VMware.CloudFoundation.PowerManagement module.
        Messages are color-coded by type on the console. All messages are written to
        $Script:LogFile when initialized. Screen output is filtered by $Script:ConfiguredLogLevel.

        .PARAMETER Message
        The text to log. Empty strings are accepted.

        .PARAMETER Type
        Severity level: DEBUG (Gray), INFO (Green), WARNING (Yellow), EXCEPTION (Cyan), ERROR (Red).
        Defaults to INFO.

        .PARAMETER SuppressOutputToScreen
        Suppresses console output; message is still written to the log file.

        .EXAMPLE
        Write-LogMessage -Type INFO -Message "Connected to '$Server'."

        .EXAMPLE
        Write-LogMessage -Type ERROR -Message "Cluster shutdown failed: $($_.Exception.Message)."

        .NOTES
        Write-Host is used here intentionally for severity-based color output. Do not use
        Write-Host elsewhere in this module; use Write-LogMessage instead.
    #>

    Param (
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter(Mandatory = $false)] [Switch]$SuppressOutputToScreen,
        [Parameter(Mandatory = $false)] [ValidateSet("DEBUG", "INFO", "WARNING", "EXCEPTION", "ERROR")] [String]$Type = "INFO"
    )

    $msgTypeToColor = @{
        "DEBUG"     = "Gray"
        "INFO"      = "Green"
        "WARNING"   = "Yellow"
        "EXCEPTION" = "Cyan"
        "ERROR"     = "Red"
    }
    $messageColor = $msgTypeToColor[$Type]
    $timeStamp = Get-Date -Format "yyyy-MM-dd_HH:mm:ss"
    $shouldDisplay = Test-LogLevel -ConfiguredLevel $Script:ConfiguredLogLevel -MessageType $Type

    if (-not $SuppressOutputToScreen -and $Script:LogOnly -ne "enabled" -and $shouldDisplay) {
        Write-Host -ForegroundColor $messageColor "[$Type]$Message"
        [Console]::Out.Flush()
    }

    if ($Script:LogFile -and -not [String]::IsNullOrWhiteSpace($Script:LogFile)) {
        $logLine = "[$timeStamp] ($Type) $Message"
        try {
            Add-Content -Path $Script:LogFile -Value $logLine -ErrorAction Stop
        } catch {
            # Silently skip file write failures to avoid masking the original error.
        }
    }
}
Function Test-ManagementEndpoint {

    # Tests TCP connectivity to a host on a given port using PS 7 Test-Connection.
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int32]$Port,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server
    )

    return Test-Connection -TargetName $Server -TcpPort $Port -Quiet
}
Function New-NsxApiHeader {

    # Builds a Basic Auth header hashtable for NSX Manager REST API calls.
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${User}:${Pass}"))
    return @{ Authorization = "Basic $encodedCreds"; "Content-Type" = "application/json" }
}
Function New-VcenterApiSession {

    # Obtains a vCenter REST API session token via POST /api/session and returns it.
    Param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("${User}:${Pass}"))
    $basicHeader = @{ Authorization = "Basic $encodedCreds" }
    return Invoke-RestMethod -Method POST -Uri "https://${Server}/api/session" -Headers $basicHeader
}

#endregion Private functions
##########################################################################
Function Stop-CloudComponent {
    <#
        .SYNOPSIS
        Shuts down a node or nodes in a vCenter inventory.

        .DESCRIPTION
        The Stop-CloudComponent cmdlet shuts down a node or nodes in a vCenter inventory.

        .EXAMPLE
        Stop-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -nodes [node_name, node_name]
        This example connects to a vCenter and shuts down the specified nodes after waiting the specified amount of seconds
        for the cloud component to reach the desired state.

        .EXAMPLE
        Stop-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -pattern [cloud_component_pattern]
        This example connects to a vCenter and shuts down the specified nodes which match the specified pattern after waiting
        the specified amount of seconds for the cloud component to reach the desired state.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER timeout
        The timeout in seconds to wait for the cloud component to reach the desired connection state.

        .PARAMETER noWait
        To shudown the cloud component and not wait for desired connection state change.

        .PARAMETER nodes
        The FQDNs of the list of cloud components to shutdown.

        .PARAMETER pattern
        The cloud components matching the pattern in the SDDC Manager inventory to be shutdown.
    #>

    Param (
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$Nodes,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$NoWait,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$Pattern,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$Timeout,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Stop-CloudComponent cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                if ($PSCmdlet.ParameterSetName -EQ "Node") {
                    $nodes_string = $Nodes -join "; "
                    Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to shut down nodes '$nodes_string'..."
                    if ($Nodes.Count -ne 0) {
                        foreach ($node in $Nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -EQ $node }) {
                                $vmObject = Get-VMGuest -Server $Server -VM $node -ErrorAction SilentlyContinue
                                if ($vmObject.State -EQ 'NotRunning') {
                                    Write-LogMessage -Type INFO -Message "Node '$node' is already powered off."
                                    Continue
                                }
                                Write-LogMessage -Type INFO -Message "Attempting to shut down node '$node'..."
                                if ($PsBoundParameters.ContainsKey("NoWait")) {
                                    Stop-VM -Server $Server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                } else {
                                    Stop-VMGuest -Server $Server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                    Write-LogMessage -Type INFO -Message "Waiting for node '$node' to shut down..."
                                    $sleepTime = 5
                                    While (($vmObject.State -ne 'NotRunning') -and ($count -le $Timeout)) {
                                        Start-Sleep -s $sleepTime
                                        $count = $count + $sleepTime
                                        $vmObject = Get-VMGuest -Server $Server -VM $node -ErrorAction SilentlyContinue
                                    }
                                    if ($count -gt $Timeout) {
                                        Write-LogMessage -Type ERROR -Message "Node '$node' did not shut down within the expected timeout $Timeout value."
                                    } else {
                                        Write-LogMessage -Type INFO -Message "Node '$node' has shut down successfully."
                                    }
                                }
                            } else {
                                Write-LogMessage -Type ERROR -Message "Unable to find node '$node' in the inventory of server '$Server'."
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -EQ "Pattern") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to shut down nodes with pattern '$Pattern'..."
                    if ($Pattern) {
                        $patternNodes = Get-VM -Server $Server | Where-Object Name -Match $Pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -Match $Server
                    } else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vmObject = Get-VMGuest -Server $Server -VM $node.Name | Where-Object VmUid -Match $Server
                            if ($vmObject.State -EQ 'NotRunning') {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' is already powered off."
                                Continue
                            }
                            Write-LogMessage -Type INFO -Message "Attempting to shut down node '$($node.name)'..."
                            if ($PsBoundParameters.ContainsKey("NoWait")) {
                                Stop-VM -Server $Server -VM $node.Name -Confirm:$false | Out-Null
                            } else {
                                Get-VMGuest -Server $Server -VM $node.Name | Where-Object VmUid -Match $Server | Stop-VMGuest -Confirm:$false | Out-Null
                                $vmObject = Get-VMGuest -Server $Server -VM $node.Name | Where-Object VmUid -Match $Server
                                $sleepTime = 1
                                While (($vmObject.State -ne 'NotRunning') -and ($count -le $Timeout)) {
                                    Start-Sleep -s $sleepTime
                                    $count = $count + $sleepTime
                                    $vmObject = Get-VMGuest -VM $node.Name | Where-Object VmUid -Match $Server
                                }
                                if ($count -gt $Timeout) {
                                    Write-LogMessage -Type ERROR -Message "Node '$($node.name)' did not shut down within the expected timeout $Timeout value."
                                } else {
                                    Write-LogMessage -Type INFO -Message "Node '$($node.name)' has shut down successfully."
                                }
                            }
                        }
                    } elseif ($Pattern) {
                        Write-LogMessage -Type WARNING -Message "No nodes match pattern '$Pattern' on host '$Server'."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Stop-CloudComponent cmdlet."
    }
}
Export-ModuleMember -Function Stop-CloudComponent
Function Start-CloudComponent {
    <#
        .SYNOPSIS
        Starts up a node or nodes in a vCenter inventory.

        .DESCRIPTION
        The Start-CloudComponent cmdlet starts up a node or nodes in a vCenter inventory.

        .EXAMPLE
        Start-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -nodes [node_name, node_name]
        This example connects to a vCenter and starts up the specified nodes after waiting the specified amount of seconds
        for the cloud component to reach the desired state.

        .EXAMPLE
        Start-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -pattern [cloud_component_pattern]
        This example connects to a vCenter and starts up the specified nodes which match the specified pattern after waiting
        the specified amount of seconds for the cloud component to reach the desired state.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER timeout
        The timeout in seconds to wait for the cloud component to reach the desired connection state.

        .PARAMETER nodes
        The FQDNs of the list of cloud components to startup.

        .PARAMETER pattern
        The cloud components matching the pattern in the SDDC Manager inventory to be startup.
    #>

    Param (
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$Nodes,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$Pattern,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$Timeout,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Start-CloudComponent cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                if ($PSCmdlet.ParameterSetName -EQ "Node") {
                    $nodes_string = $Nodes -join "; "
                    Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to start nodes '$nodes_string'."
                    if ($Nodes.Count -ne 0) {
                        foreach ($node in $Nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -EQ $node }) {
                                $vmObject = Get-VMGuest -Server $Server -VM $node -ErrorAction SilentlyContinue
                                if ($vmObject.State -EQ 'Running') {
                                    Write-LogMessage -Type INFO -Message "Node '$node' is already in powered on."
                                    Continue
                                }
                                Write-LogMessage -Type INFO -Message "Attempting to start up node '$node'..."
                                Start-VM -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                Start-Sleep -s 5
                                $sleepTime = 10
                                Write-LogMessage -Type INFO -Message "Waiting for node '$node' to start up..."
                                While (($vmObject.State -ne 'Running') -and ($count -le $Timeout)) {
                                    Start-Sleep -s $sleepTime
                                    $count = $count + $sleepTime
                                    $vmObject = Get-VMGuest -Server $Server -VM $node -ErrorAction SilentlyContinue
                                }
                                if ($count -gt $Timeout) {
                                    Write-LogMessage -Type ERROR -Message "Node '$node' did not start up within the expected timeout $Timeout value."
                                    Break
                                } else {
                                    Write-LogMessage -Type INFO -Message "Node '$node' has started successfully."
                                }
                            } else {
                                Write-LogMessage -Type ERROR -Message "Cannot find '$node' in the inventory of host '$Server'."
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -EQ "Pattern") {
                    Write-LogMessage -Type INFO -Message "Connected to host '$Server' and attempting to start up nodes with pattern '$Pattern'..."
                    if ($Pattern) {
                        $patternNodes = Get-VM -Server $Server | Where-Object Name -Match $Pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -Match $Server
                    } else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vmObject = Get-VMGuest -server $Server -VM $node.Name | Where-Object VmUid -Match $Server
                            if ($vmObject.State -EQ 'Running') {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' is already powered on."
                                Continue
                            }

                            Start-VM -VM $node.Name | Out-Null
                            $sleepTime = 1
                            $vmObject = Get-VMGuest -Server $Server -VM $node.Name | Where-Object VmUid -Match $Server
                            Write-LogMessage -Type INFO -Message "Attempting to start up node '$($node.name)'..."
                            While (($vmObject.State -ne 'Running') -AND ($count -le $Timeout)) {
                                Start-Sleep -s $sleepTime
                                $count = $count + $sleepTime
                                $vmObject = Get-VMGuest -Server $Server -VM $node.Name | Where-Object VmUid -Match $Server
                            }
                            if ($count -gt $Timeout) {
                                Write-LogMessage -Type ERROR -Message "Node '$($node.name)' did not start up within the expected timeout $Timeout value."
                            } else {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' has started successfully."
                            }
                        }
                    } elseif ($Pattern) {
                        Write-LogMessage -Type WARNING -Message "No nodes match pattern '$Pattern' on host '$Server'."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to host '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Start-CloudComponent cmdlet."
    }
}
Export-ModuleMember -Function Start-CloudComponent
Function Set-MaintenanceMode {
    <#
        .SYNOPSIS
        Sets maintenance mode on an ESX host.

        .DESCRIPTION
        The Set-MaintenanceMode cmdlet enables or disables maintenance mode on an ESX host.

        .EXAMPLE
        Set-MaintenanceMode -server [esx_fqdn] -user [admin_username] -pass [admin_password] -state [maintenance_mode_state]
        This example places an ESX host in the specified maintenance mode state.

        .PARAMETER server
        The FQDN of the ESX host.

        .PARAMETER user
        The username to authenticate to ESX host.

        .PARAMETER pass
        The password to authenticate to ESX host.

        .PARAMETER state
        The state of the maintenance mode to be set on ESX host.
        The value can be one of the following ("ENABLE" or "DISABLE").
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateSet("ENABLE", "DISABLE")] [String]$State,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Set-MaintenanceMode cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to $State maintenance mode..."
                $hostStatus = (Get-VMHost -Server $Server)
                if ($State -EQ "ENABLE") {
                    if ($hostStatus.ConnectionState -EQ "Connected") {
                        Write-LogMessage -Type INFO -Message "Attempting to enter maintenance mode for '$Server'..."
                        Get-View -Server $Server -ViewType HostSystem -Filter @{"Name" = $Server } | Where-Object { !$_.Runtime.InMaintenanceMode } | ForEach-Object { $_.EnterMaintenanceMode(0, $false, (New-Object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode = (New-Object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction = [VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction }) })) } | Out-Null
                        $hostStatus = (Get-VMHost -Server $Server)
                        if ($hostStatus.ConnectionState -EQ "Maintenance") {
                            Write-LogMessage -Type INFO -Message "Host '$Server' has entered maintenance mode successfully."
                        } else {
                            Write-LogMessage -Type ERROR -Message "Host '$Server' did not enter maintenance mode. Check your environment and try again."
                        }
                    } elseif ($hostStatus.ConnectionState -EQ "Maintenance") {
                        Write-LogMessage -Type INFO -Message "Host '$Server' has already entered maintenance mode."
                    } else {
                        Write-LogMessage -Type ERROR -Message "Host '$Server' is not currently connected."
                    }
                }

                elseif ($State -EQ "DISABLE") {
                    if ($hostStatus.ConnectionState -EQ "Maintenance") {
                        Write-LogMessage -Type INFO -Message "Attempting to exit maintenance mode for '$Server'..."
                        $task = Set-VMHost -VMHost $Server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Wait-Task $task | Out-Null
                        $hostStatus = (Get-VMHost -Server $Server)
                        if ($hostStatus.ConnectionState -EQ "Connected") {
                            Write-LogMessage -Type INFO -Message "Host '$Server' has exited maintenance mode successfully."
                        } else {
                            Write-LogMessage -Type ERROR -Message "The host '$Server' did not exit maintenance mode. Check your environment and try again."
                        }
                    } elseif ($hostStatus.ConnectionState -EQ "Connected") {
                        Write-LogMessage -Type INFO -Message "Host '$Server' has already exited maintenance mode"
                    } else {
                        Write-LogMessage -Type ERROR -Message "Host '$Server' is not currently connected."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Set-MaintenanceMode cmdlet."
    }
}
Export-ModuleMember -Function Set-MaintenanceMode
Function Get-MaintenanceMode {
    <#
        .SYNOPSIS
        Returns the maintenance mode status of a specified ESX host.

        .DESCRIPTION
        The Get-MaintenanceMode cmdlet returns the maintenance mode status of a specified ESX host.

        .EXAMPLE
        Get-MaintenanceMode -server [esx_fqdn] -user [admin_username] -pass [admin_password]
        This example returns the ESX host maintenance mode status.

        .PARAMETER server
        The FQDN of the ESX host.

        .PARAMETER user
        The username to authenticate to ESX host.

        .PARAMETER pass
        The password to authenticate to ESX host.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-MaintenanceMode cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                $hostStatus = (Get-VMHost -Server $Server)
                Write-LogMessage -Type INFO -Message "Connected to server '$Server'. The connection status is '$($hostStatus.ConnectionState)'."
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $hostStatus.ConnectionState
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-MaintenanceMode cmdlet."
    }
}
Export-ModuleMember -Function Get-MaintenanceMode
Function Set-DrsAutomationLevel {
    <#
        .SYNOPSIS
        Sets the vSphere Distributed Resource Scheduler automation level.

        .DESCRIPTION
        The Set-DrsAutomationLevel cmdlet sets the automation level of the cluster based on the setting provided.

        .EXAMPLE
        Set-DrsAutomationLevel -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -level [drs_level]
        This example sets the vSphere Distributed Resource Scheduler Automation level for the specified cluster to the specified DRS level.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER level
        The vSphere Distributed Resource Scheduler automation level to be set.
        The value can be one of the following ("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled")] [String]$Level,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Set-DrsAutomationLevel cmdlet."

        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                $drsStatus = Get-Cluster -Name $Cluster -ErrorAction SilentlyContinue
                if ($drsStatus) {
                    if ($drsStatus.DrsAutomationLevel -EQ $Level) {
                        Write-LogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$Cluster' is already '$Level'."
                    } else {
                        $drsStatus = Set-Cluster -Cluster $Cluster -DrsAutomationLevel $Level -Confirm:$false
                        if ($drsStatus.DrsAutomationLevel -EQ $Level) {
                            Write-LogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$Cluster' has been set to '$Level' successfully."
                        } else {
                            Write-LogMessage -Type ERROR -Message "Failed to set the vSphere DRS automation level for cluster '$Cluster' to '$Level'."
                        }
                    }
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Write-LogMessage -Type ERROR -Message "Cluster '$Cluster' not found on host '$Server'. Check your environment and try again."
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Set-DrsAutomationLevel cmdlet."
    }
}
Export-ModuleMember -Function Set-DrsAutomationLevel
Function Set-VsanClusterPowerStatus {
    <#
        .SYNOPSIS
        Set the power status of a vSAN cluster.

        .DESCRIPTION
        The Set-VsanClusterPowerStatus cmdlet sets the power status of a vSAN cluster.

        .EXAMPLE
        Set-VsanClusterPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -PowerStatus [power_status]
        This example connects to a vCenter instance and puts the specified cluster in a specified power status.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER clustername
        The name of the cluster.

        .PARAMETER mgmt
        The switch used to ignore power settings if management domain information is passed.

        .PARAMETER PowerStatus
        The power state to be set for a given vSAN cluster.
        The value can be one of the following ("clusterPoweredOff", "clusterPoweredOn").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ClusterName,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Mgmt,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateSet("clusterPoweredOff", "clusterPoweredOn")] [String]$PowerStatus,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Set-VsanClusterPowerStatus cmdlet."

        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {

                Import-Module VMware.VimAutomation.Storage
                $vsanClient = [VMware.VimAutomation.Storage.Interop.V1.Service.StorageServiceFactory]::StorageCoreService.ClientManager.GetClientByConnectionId($DefaultVIServer.Id)
                $vsanClusterPowerSystem = $vsanClient.VsanViewService.GetVsanViewById("VsanClusterPowerSystem-vsan-cluster-power-system")

                # Populate the needed spec:
                $spec = [VMware.Vsan.Views.PerformClusterPowerActionSpec]::new()

                $spec.powerOffReason = "Shutdown through VMware Cloud Foundation script"
                $spec.targetPowerStatus = $PowerStatus

                $Cluster = Get-Cluster $ClusterName

                # TODO - Add check if there is task ID returned
                $powerActionTask = $vsanClusterPowerSystem.PerformClusterPowerAction($Cluster.ExtensionData.MoRef, $spec)
                $task = Get-Task -Id $powerActionTask
                $counter = 0
                $sleepTime = 10 # in seconds
                if (-Not $Mgmt) {
                    do {
                        $task = Get-Task -Id $powerActionTask
                        if (-Not ($task.State -EQ "Error")) {
                            Write-LogMessage -Type INFO -Message "$PowerStatus task is $($task.PercentComplete)% completed."
                        }
                        Start-Sleep -s $sleepTime
                        $counter += $sleepTime
                    } while ($task.State -EQ "Running" -and ($counter -lt 1800))

                    if ($task.State -EQ "Error") {
                        if ($task.ExtensionData.Info.Error.Fault.FaultMessage -like "VMware.Vim.LocalizableMessage") {
                            Write-LogMessage -Type ERROR -Message "'$($PowerStatus)' task exited with a localized error message. Go to the vSphere Client for details and to take the necessary actions."
                        } else {
                            Write-LogMessage -Type WARN -Message "'$($PowerStatus)' task exited with the Message:$($task.ExtensionData.Info.Error.Fault.FaultMessage) and Error: $($task.ExtensionData.Info.Error)."
                            Write-LogMessage -Type ERROR -Message "Go to the vSphere Client for details and to take the necessary actions."
                        }
                    }

                    if ($task.State -EQ "Success") {
                        Write-LogMessage -Type INFO -Message "$PowerStatus task is completed successfully."
                    } else {
                        Write-LogMessage -Type ERROR -Message "$PowerStatus task is blocked in $($task.State) state."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Set-VsanClusterPowerStatus cmdlet."
    }
}
Export-ModuleMember -Function Set-VsanClusterPowerStatus
Function Invoke-VxrailClusterShutdown {
    <#
        .SYNOPSIS
        Invoke the shutdown command on a VxRail Cluster.

        .DESCRIPTION
        The Invoke-VxrailClusterShutdown cmdlet powers off a VxRail cluster.
        The cmdlet will perform a dry run test prior to initiating a shutdown command on a VxRail cluster.

        .EXAMPLE
        Invoke-VxrailClusterShutdown -server [vxrail_manager_fqdn] -user [admin_username] -pass [admin_password]
        This example powers off a Vxrail cluster which the VxRail Manager controls.

        .PARAMETER server
        The FQDN of the VxRail Manager.

        .PARAMETER user
        The username to authenticate to the SSO service in which the VxRail is registered to.

        .PARAMETER pass
        The password for the admin username to authenticate to the SSO service in which the VxRail is registered to.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Invoke-VxrailClusterShutdown cmdlet."

        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }

            # Prepare VxRail rest API headers and payload
            $payloadTest = @{ dryrun = 'true' } | ConvertTo-Json
            $payloadRun = @{ dryrun = 'false' } | ConvertTo-Json
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $Pass))) # Create Basic Authentication Encoded Credentials
            $headers = @{"Content-Type" = "application/json" }
            $headers.Add("Authorization", "Basic $base64AuthInfo")
            $uri = "https://$Server/rest/vxm/v1/cluster/shutdown"

            Write-LogMessage -Type INFO -Message "Starting VxRail cluster shutdown dry run."
            $respond = Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -Body $payloadTest -UseBasicParsing -SkipCertificateCheck
            if ($respond.StatusCode -EQ "202" -or $respond.StatusCode -EQ "200") {
                $requestID = $respond.content | ConvertFrom-Json
                Write-LogMessage -Type INFO -Message "VxRail cluster shutdown request accepted(ID:$($requestID.request_id))"
                $uri2 = "https://$Server/rest/vxm/v1/requests/$($requestID.request_id)"
                $loopCounter = 0
                $loopCounterLimit = 13
                while ($loopCounter -lt $loopCounterLimit) {
                    $respond2 = Invoke-WebRequest -Method GET -Uri $uri2 -Headers $headers -UseBasicParsing -SkipCertificateCheck
                    if ($respond2.StatusCode -EQ "202" -or $respond2.StatusCode -EQ "200") {
                        $checkProgress = $respond2.content | ConvertFrom-Json
                        if ($checkProgress.state -Match "COMPLETED" -or $checkProgress.state -Match "FAILED" ) {
                            break
                        }
                    }
                    Start-Sleep -s 10
                    $loopCounter += 1
                }

                if ($checkProgress.extension.passed -match "true") {
                    Write-LogMessage -Type INFO -Message "VxRail cluster shutdown dry run: SUCCEEDED."
                    Write-LogMessage -Type INFO -Message "Starting VxRail cluster shutdown."

                    $respond = Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -Body $payloadRun -UseBasicParsing -SkipCertificateCheck
                    if ($respond.StatusCode -EQ "202" -or $respond.StatusCode -EQ "200") {
                        return $true
                    } else {
                        Write-LogMessage -Type ERROR -Message "VxRail cluster shutdown: FAILED"
                    }
                } else {
                    $errorMsg = ""
                    $checkProgress = $respond2.content | ConvertFrom-Json
                    $parsingError = $checkProgress.extension.status
                    foreach ($errorElement in $parsingError) {
                        if ($errorElement.checkResult -match "FAILED") {
                            $errorMsg = $errorMsg + "Label: $($errorElement.label),($($errorElement.checkResult)) `nMessage: $($errorElement.message)`n"
                        }
                    }
                    Write-LogMessage -Type ERROR -Message "VxRail cluster shutdown dry run: FAILED `n $errorMsg"
                }
            } else {
                Write-LogMessage -Type ERROR -Message "VxRail cluster shutdown: FAILED"
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Invoke-VxrailClusterShutdown cmdlet."
    }
}
Export-ModuleMember -Function Invoke-VxrailClusterShutdown
Function Get-poweronVMsOnRemoteDS {
    <#
        .SYNOPSIS
        Returns a list of virtual machines that reside on a specified vSAN datastore.

        .DESCRIPTION
        The Get-poweronVMsOnRemoteDS cmdlet returns a list of virtual machines that reside on a specified vSAN datastore in a specified cluster.

        .EXAMPLE
        Get-poweronVMsOnRemoteDS -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -clustertocheck [cluster_name]
        This example returns a list of virtual machines that reside on a specified vSAN datastore hosted in a specified cluster.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER clusterToCheck
        The name of the remote cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$ClusterToCheck,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-poweronVMsOnRemoteDS cmdlet."

        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                $TotalvSANDatastores = @()
                $RemotevSANdatastores = @()
                $TotalvSANDatastores = (Get-Cluster -Name $ClusterToCheck | Get-Datastore | Where-Object { $_.Type -EQ "vSAN" }).Name
                $RemotevSANdatastores = ((get-vsanClusterConfiguration -Cluster $ClusterToCheck).RemoteDatastore).Name
                $LocalvSANDatastores = $TotalvSANDatastores | Where-Object { $_ -notin $RemotevSANdatastores }
                [Array]$PoweredOnVMs = @()
                foreach ($localds in $LocalvSANDatastores) {
                    foreach ($Cluster in (Get-Cluster).Name) {
                        if ($Cluster -ne $ClusterToCheck ) {
                            $MountedvSANdatastores = ((get-vsanClusterConfiguration -Cluster $Cluster).RemoteDatastore).Name
                            foreach ($datastore in $MountedvSANdatastores) {
                                if ($datastore -EQ $localds) {
                                    $datastoreID = Get-Datastore $datastore | ForEach-Object { $_.ExtensionData.MoRef }
                                    $vms = (Get-Cluster -name $Cluster | get-vm | Where-Object { $_.PowerState -EQ "PoweredOn" }) | Where-Object { $vm = $_; $datastoreID | Where-Object { $vm.DatastoreIdList -contains $_ } }
                                    if ($vms) {
                                        Write-LogMessage -Type INFO -Message "Remote VMs with names $vms are running on cluster '$Cluster' and datastore '$datastore.' `n"
                                        [Array]$PoweredOnVMs += $vms
                                    }
                                }
                            }
                        }
                    }
                }
                return $PoweredOnVMs
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-poweronVMsOnRemoteDS cmdlet."
    }
}
Export-ModuleMember -Function Get-poweronVMsOnRemoteDS
Function Test-LockdownMode {
    <#
        .SYNOPSIS
        Test if ESX hosts in a cluster are in lockdown mode.

        .DESCRIPTION
        The Test-LockdownMode cmdlet tests if ESX hosts in a specified cluster are in lockdown mode.

        .EXAMPLE
        Test-LockdownMode -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
        This example checks if any of the ESX hosts in the specified cluster are in lockdown mode.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Test-LockdownMode cmdlet."

        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                $hostsInCluster = @()
                $hostsInCluster = Get-Cluster -Name $Cluster | Get-VMHost
                $hostsWithLockdown = ""
                if ($hostsInCluster.count -ne 0) {
                    foreach ($esxiHost in $hostsInCluster) {
                        Write-LogMessage -Type INFO -Message "Checking lockdown mode for $esxiHost ...."
                        $lockdownStatus = (Get-VMHost -Name $esxiHost).ExtensionData.Config.LockdownMode
                        if ($null -EQ $lockdownStatus) {
                            $checkServer = (Test-ManagementEndpoint -Server $esxiHost -Port 443)
                            if ($checkServer) {
                                Write-LogMessage -Type ERROR -Message "Cannot fetch information about lockdown mode for ESXi host $esxiHost!"
                            } else {
                                Write-LogMessage -Type WARNING -Message "Cannot fetch information about lockdown mode. Host $esxiHost is not reachable."
                                Write-LogMessage -Type ERROR -Message "Check the status on the ESXi host $esxiHost!"
                            }
                        } else {
                            if ($lockdownStatus -ne "lockdownDisabled") {
                                Write-LogMessage -Type WARNING -Message "Lockdown mode is enabled for ESXi host $esxiHost"
                                $hostsWithLockdown += ", $esxiHost"
                            }
                        }
                    }
                } else {
                    Write-LogMessage -Type ERROR -Message "Cluster $Cluster is not present on server $Server. Check the input to the cmdlet."
                }
                if ([string]::IsNullOrEmpty($hostsWithLockdown)) {
                    Write-LogMessage -Type INFO -Message "Cluster $Cluster does not have ESXi hosts in lockdown mode."
                } else {
                    Write-LogMessage -Type INFO -Message "The following ESXi hosts are in lockdown mode: $hostsWithLockdown. Disable lockdown mode to continue."
                    Write-LogMessage -Type ERROR -Message "Some hosts are in lockdown mode. Disable lockdown mode to continue."
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Test-LockdownMode cmdlet."
    }
}
Export-ModuleMember -Function Test-LockdownMode
Function Get-VMRunningStatus {
    <#
        .SYNOPSIS
        Returns the status of virtual machines with a specified pattern in the VM name.

        .DESCRIPTION
        The Get-VMRunningStatus cmdlet returns the status of virtual machines with a specified pattern in the VM name on a specified ESX host.

        .EXAMPLE
        Get-VMRunningStatus -server [esx_fqdn] -user [admin_username] -pass [admin_password] -pattern [vm_name_pattern]
        This example connects to an ESX host and searches for all virtual machines matching the pattern and gets their running status.

        .PARAMETER server
        The FQDN of the ESX host.

        .PARAMETER user
        The username to authenticate to ESX host.

        .PARAMETER pass
        The password to authenticate to ESX host.

        .PARAMETER pattern
        The pattern to match set of virtual machines.

        .PARAMETER Status
        The state of the virtual machine to be tested against.
        The value can be one of the following ("Running", "NotRunning").
        The default value is "Running".
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Pattern,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $false)] [ValidateSet("Running", "NotRunning")] [String]$Status = "Running",
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-VMRunningStatus cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to host '$Server' and checking if nodes named '$Pattern' are in the '$($status.ToUpper())' state..."
                $Nodes = Get-VM | Where-Object Name -Match $Pattern | Select-Object Name, PowerState, VMHost
                if ($Nodes.Name.Count -EQ 0) {
                    Write-LogMessage -Type ERROR -Message "Cannot find nodes matching pattern '$Pattern' in the inventory of host '$Server'."
                } else {
                    foreach ($node in $Nodes) {
                        $vmObject = Get-VMGuest -server $Server -VM $node.Name -ErrorAction SilentlyContinue | Where-Object VmUid -Match $Server
                        if ($vmObject.State -EQ $status) {
                            Write-LogMessage -Type INFO -Message "Node $($node.Name) is in '$($status.ToUpper()) state.'"
                            return $true
                        } else {

                            Write-LogMessage -Type INFO -Message "Node $($node.Name) is not in '$($status.ToUpper()) state'."
                            return $false
                        }
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-VMRunningStatus cmdlet."
    }
}
Export-ModuleMember -Function Get-VMRunningStatus
Function Test-VsanHealth {
    <#
        .SYNOPSIS
        Tests the vSAN health of a for a specified cluster.

        .DESCRIPTION
        The Test-VsanHealth cmdlet returns the vSAN health of a specified cluster.

        .EXAMPLE
        Test-VsanHealth -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
        This example connects to a vCenter and checks the state of the vSAN cluster health for a specified cluster.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Test-VsanHealth cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to check the vSAN cluster health..."
                $count = 1
                $flag = 0
                While ($count -lt 5) {
                    Try {
                        $Error.clear()
                        Get-vSANView -Server $Server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -erroraction stop | Out-Null
                        if (-Not $Error) {
                            $flag = 1
                            Break
                        }
                    } Catch {
                        Write-LogMessage -Type INFO -Message "The vSAN health service is yet to come up, please wait ..."
                        Start-Sleep -s 60
                        $count += 1
                    }
                }

                if (-Not $flag) {
                    Write-LogMessage -Type ERROR -Message "Cannot run the Test-VsanHealth cmdlet because the vSAN health service is not running."
                } else {
                    Start-Sleep -s 60
                    $vchs = Get-VSANView -Server $Server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
                    $cluster_view = (Get-Cluster -Name $Cluster).ExtensionData.MoRef
                    $results = $vchs.VsanQueryVcClusterHealthSummary($cluster_view, $null, $null, $true, $null, $null, 'defaultView')
                    $healthCheckGroups = $results.groups
                    $health_status = 'GREEN'
                    $healthCheckResults = @()
                    foreach ($healthCheckGroup in $healthCheckGroups) {
                        Switch ($healthCheckGroup.GroupHealth) {
                            red { $healthStatus = "error" }
                            yellow { $healthStatus = "warning" }
                            green { $healthStatus = "passed" }
                            info { $healthStatus = "passed" }
                        }
                        if ($healthStatus -EQ "red") {
                            $health_status = 'RED'
                        }
                        $healthCheckGroupResult = [pscustomobject] @{
                            HealthCHeck = $healthCheckGroup.GroupName
                            Result      = $healthStatus
                        }
                        $healthCheckResults += $healthCheckGroupResult
                    }
                    if ($health_status -EQ 'GREEN' -and $results.OverallHealth -ne 'red') {
                        Write-LogMessage -Type INFO -Message "The vSAN health status for $Cluster is good."
                        return 0
                    } else {
                        Write-LogMessage -Type ERROR -Message "The vSAN health status for $Cluster is bad."
                        return 1
                    }
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Test-VsanHealth cmdlet."
    }
}
Export-ModuleMember -Function Test-VsanHealth
Function Test-VsanObjectResync {
    <#
        .SYNOPSIS
        Test the vSAN object resync status for a specified cluster.

        .DESCRIPTION
        The Test-VsanObjectResync cmdlet returns the vSAN object resync status for a specified cluster.

        .EXAMPLE
        Test-VsanObjectResync -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
        This example connects to a vCenter and checks the status of object syncing for a specified vSAN cluster.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Test-VsanObjectResync cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to check the resynchronization status... "
                $noResyncingObjects = Get-VsanResyncingComponent -Server $Server -cluster $Cluster -ErrorAction Ignore
                Write-LogMessage -Type INFO -Message "Number of resynchronizing objects: $noResyncingObjects."
                if ($noResyncingObjects.count -EQ 0) {
                    Write-LogMessage -Type INFO -Message "No resynchronizing objects."
                    return 0
                } else {
                    Write-LogMessage -Type ERROR -Message "Resynchronizing objects in progress..."
                    return 1
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Test-VsanObjectResync cmdlet."
    }
}
Export-ModuleMember -Function Test-VsanObjectResync
Function Get-VMsWithPowerStatus {
    <#
        .SYNOPSIS
        Returns a list of virtual machines that are in a specified power state.

        .DESCRIPTION
        The Get-VMsWithPowerStatus cmdlet returns a list of virtual machines that are in a specified power state on a specified vCenter or ESX host.

        .EXAMPLE
        Get-VMsWithPowerStatus -server [esx_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state]
        This example connects to the specified ESX host and returns the list of all powered on virtual machines.

        .EXAMPLE
        Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern] -exactmatch
        This example connects to a vCenter instance and returns a powered on VM with a specified name.

        .EXAMPLE
        Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern]
        This example connects to a vCenter instance and returns all powered on virtual machines matching the pattern.

        .EXAMPLE
        Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern] -silence
        This example connects to a vCenter instance and returns all powered on virtual machines matching the pattern and suppressing log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER powerstate
        The power state of the virtual machines.
        The value can be one of the following ("poweredon","poweredoff").

        .PARAMETER pattern
        The pattern to match virtual machine names.

        .PARAMETER exactMatch
        The switch to match exact virtual machine name.

        .PARAMETER silence
        The switch to supress selected log messages.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$ExactMatch,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pattern = $null ,
        [Parameter (Mandatory = $true)] [ValidateSet("poweredon", "poweredoff")] [String]$PowerState,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {

        if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Starting the call to the Get-VMsWithPowerStatus cmdlet." }
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Connecting to '$Server'..." }
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Connected to server '$Server' and attempting to get the list of virtual machines..." }
                if ($Pattern) {
                    if ($PSBoundParameters.ContainsKey('ExactMatch') ) {
                        $noOfVMs = get-vm -Server $Server | Where-Object Name -EQ $Pattern | Where-Object PowerState -EQ $PowerState
                    } else {
                        $noOfVMs = get-vm -Server $Server | Where-Object Name -Match $Pattern | Where-Object PowerState -EQ $PowerState
                    }
                } else {
                    $noOfVMs = get-vm -Server $Server | Where-Object PowerState -EQ $PowerState
                }
                if ($noOfVMs.count -EQ 0) {
                    if (-Not $Silence) { Write-LogMessage -Type INFO -Message "No virtual machines in the $PowerState state." }
                } else {
                    $noOfVMsString = $noOfVMs -join ","
                    if (-Not $Silence) { Write-LogMessage -Type INFO -Message "The virtual machines in the $PowerState state are: $noOfVMsString" }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                Return $noOfVMs
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Completed the call to the Get-VMsWithPowerStatus cmdlet." }
    }
}
Export-ModuleMember -Function Get-VMsWithPowerStatus
Function Get-VamiServiceStatus {
    <#
        .SYNOPSIS
        Returns the status of a specified service on a vCenter instance.

        .DESCRIPTION
        The Get-VamiServiceStatus cmdlet returns the status of a specified service on a vCenter instance. The status returns either STARTED/STOPPED.


        .EXAMPLE
        Get-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name]
        This example connects to the specified vCenter instance and returns the status of the specified service.

        .EXAMPLE
        Get-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -nolog
        This example connects to the specified vCenter instance and returns the status of the specified service without log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER nolog
        The switch to supress selected log messages.

        .PARAMETER service
        The name of the service to check status for.
        The value can be one of the following ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$NoLog,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$Service,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        if (-Not $NoLog) {
            Write-LogMessage -Type INFO -Message "Starting the call to the Get-VamiServiceStatus cmdlet."
        }
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            if (-Not $NoLog) {
                Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            }
            $retries = 20
            $flag = 0
            While ($retries) {
                Try {
                    $sessionToken = New-VcenterApiSession -Server $Server -User $User -Pass $Pass
                    if ($sessionToken) {
                        $flag = 1
                        break
                    }
                } Catch {
                    # Session not ready yet.
                }
                Start-Sleep -s 60
                $retries -= 1
                if (-Not $NoLog) {
                    Write-LogMessage -Type INFO -Message "Connecting to the vCenter REST API endpoint might take some time. Please wait."
                }
            }
            if ($flag) {
                $headers = @{ "vmware-api-session-id" = $sessionToken; "Content-Type" = "application/json" }
                $response = Invoke-RestMethod -Method GET -Uri "https://${Server}/api/vcenter/services/${Service}" -Headers $headers
                return $response.state
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Testing the connection to server '$Server' has failed. Check your details and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        if (-Not $NoLog) {
            Write-LogMessage -Type INFO -Message "Completed the call to the Get-VamiServiceStatus cmdlet."
        }
    }
}
Export-ModuleMember -Function Get-VamiServiceStatus
Function Set-VamiServiceStatus {
    <#
        .SYNOPSIS
        Starts, stops, or restarts a service on a vCenter instance.

        .DESCRIPTION
        The Set-VamiServiceStatus cmdlet starts, stops, or restarts a specified management appliance service on a specified vCenter instance.

        .EXAMPLE
        Set-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -state [service_state]
        This example connects to a vCenter instance and puts the specified service in a specified service state.

        .EXAMPLE
        Set-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -state [service_state] -nolog
        This example connects to a vCenter instance and puts the specified service in a specified service state without log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER state
        The state of the service.
        The value can be one of the following ("start", "stop", "restart").

        .PARAMETER nolog
        The switch to supress selected log messages.

        .PARAMETER service
        The name of the service.
        The values can be one amongst ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$NoLog,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$Service,
        [Parameter (Mandatory = $true)] [ValidateSet("start", "stop", "restart")] [String]$State,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        if (-Not $NoLog) {
            Write-LogMessage -Type INFO -Message "Starting the call to the Set-VamiServiceStatus cmdlet."
        }
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            if (-Not $NoLog) {
                Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            }
            $sessionToken = New-VcenterApiSession -Server $Server -User $User -Pass $Pass
            $headers = @{ "vmware-api-session-id" = $sessionToken; "Content-Type" = "application/json" }
            switch ($State) {
                "start" {
                    Invoke-RestMethod -Method POST -Uri "https://${Server}/api/vcenter/services/${Service}/start" -Headers $headers | Out-Null
                    $response = Invoke-RestMethod -Method GET -Uri "https://${Server}/api/vcenter/services/${Service}" -Headers $headers
                    if ($response.state -EQ "STARTED") {
                        if (-Not $NoLog) { Write-LogMessage -Type INFO -Message "Service '$Service' is successfully started." }
                    } else {
                        Write-LogMessage -Type ERROR -Message "Could not start service '$Service'."
                    }
                }
                "stop" {
                    Invoke-RestMethod -Method POST -Uri "https://${Server}/api/vcenter/services/${Service}/stop" -Headers $headers | Out-Null
                    $response = Invoke-RestMethod -Method GET -Uri "https://${Server}/api/vcenter/services/${Service}" -Headers $headers
                    if ($response.state -EQ "STOPPED") {
                        if (-Not $NoLog) { Write-LogMessage -Type INFO -Message "Service '$Service' is successfully stopped." }
                    } else {
                        Write-LogMessage -Type ERROR -Message "Could not stop service '$Service'."
                    }
                }
                "restart" {
                    Invoke-RestMethod -Method POST -Uri "https://${Server}/api/vcenter/services/${Service}/restart" -Headers $headers | Out-Null
                    $response = Invoke-RestMethod -Method GET -Uri "https://${Server}/api/vcenter/services/${Service}" -Headers $headers
                    if ($response.state -EQ "STARTED") {
                        if (-Not $NoLog) { Write-LogMessage -Type INFO -Message "Service '$Service' is successfully restarted." }
                    } else {
                        Write-LogMessage -Type ERROR -Message "Could not restart service '$Service'."
                    }
                }
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Testing the connection to server '$Server' has failed. Check your details and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        if (-Not $NoLog) {
            Write-LogMessage -Type INFO -Message "Completed the call to the Set-VamiServiceStatus cmdlet."
        }
    }
}
Export-ModuleMember -Function Set-VamiServiceStatus
Function Set-VsphereHA {
    <#
        .SYNOPSIS
        Sets vSphere High Availability to enabled or disabled for a specified cluster.

        .DESCRIPTION
        Set vSphere High Availability to enabled or disabled

        .EXAMPLE
        The Set-VsphereHA cmdlet sets vSphere High Availability to enabled or disabled for a specified cluster.
        This example connects to a vCenter instance and sets the specified cluster in to a enabled/active vSphere High Availability state.

        .EXAMPLE
        Set-VsphereHA -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -disableHA
        This example connects to a vCenter instance and sets the specified cluster in to a disabled/stopped vSphere High Availability state.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER enableHA
        The switch to enable vSphere High Availability.

        .PARAMETER disableHA
        The switch to disable vSphere High Availability.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $true, ParameterSetName = "disable")] [Switch]$DisableHA,
        [Parameter (Mandatory = $true, ParameterSetName = "enable")] [Switch]$EnableHA,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Set-VsphereHA cmdlet."
        if ($(Test-ManagementEndpoint -Server $Server -Port 443)) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server'... ..."
                $retryCount = 0
                $completed = $false
                $SecondsDelay = 10
                $Retries = 60
                if ($EnableHA) {
                    if ($(get-cluster -Name $Cluster).HAEnabled) {
                        Write-LogMessage -Type INFO -Message "vSphere High Availability is already enabled on the vSAN cluster. "
                        return $true
                    } else {
                        Write-LogMessage -Type INFO -Message "Enabling vSphere High Availability for cluster '$Cluster'..."
                        Set-Cluster -Server $Server -Cluster $Cluster -HAEnabled:$true -Confirm:$false | Out-Null
                        While (-Not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-LogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress."
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep -s 5
                            $runningTasks = get-task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-LogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep -s $SecondsDelay
                                continue
                            } else {
                                $completed = $true
                                if ($(get-cluster -Name $Cluster).HAEnabled) {
                                    Write-LogMessage -Type INFO -Message "vSphere High Availability for cluster '$Cluster' changed to 'Enabled'."
                                    return $true
                                } else {
                                    Write-LogMessage -Type WARNING -Message "Failed to set vSphere High Availability for cluster '$Cluster' to 'Enabled'."
                                    return $false
                                }
                            }
                        }
                    }
                }
                if ($DisableHA) {
                    if (!$(get-cluster -Name $Cluster).HAEnabled) {
                        Write-LogMessage -Type INFO -Message "vSphere High Availability is already disabled on the vSAN cluster. "
                        return $true
                    } else {
                        Write-LogMessage -Type INFO -Message "Disabling vSphere High Availability for cluster '$Cluster'."
                        Set-Cluster -Server $Server -Cluster $Cluster -HAEnabled:$false -Confirm:$false | Out-Null
                        While (-Not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-LogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress."
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep -s 5
                            $runningTasks = get-task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-LogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep -s $SecondsDelay
                                continue
                            } else {
                                $completed = $true
                                if (!$(get-cluster -Name $Cluster).HAEnabled) {
                                    Write-LogMessage -Type INFO -Message "Disabled vSphere High Availability for cluster '$Cluster'."
                                    return $true
                                } else {
                                    Write-LogMessage -Type WARNING -Message "Failed to disable vSphere High Availability for cluster '$Cluster'."
                                    return $false
                                }
                            }
                        }
                    }
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Set-VsphereHA cmdlet."
    }

}
Export-ModuleMember -Function Set-VsphereHA
Function Get-DrsAutomationLevel {
    <#
        .SYNOPSIS
        Returns the vSphere Distributed Resource Scheduler (DRS) setting configured on the vCenter for a specified cluster.

        .DESCRIPTION
        The Get-DrsAutomationLevel cmdlet returns the vSphere Distributed Resource Scheduler (DRS) setting configured on the vCenter for a specified cluster.

        .EXAMPLE
        Get-DrsAutomationLevel -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
        This example connects to the vCenter and returns the DRS settings configured for a specified cluster.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-DrsAutomationLevel cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server'... ..."
                $ClusterData = Get-Cluster -Name $Cluster
                if ($ClusterData.DrsEnabled) {
                    $clsdrsvalue = $ClusterData.DrsAutomationLevel
                    Write-LogMessage -Type INFO -Message "The cluster DRS value: $clsdrsvalue."
                } else {
                    Write-LogMessage -Type INFO -Message "vSphere DRS is not enabled on the cluster $Cluster."
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $clsdrsvalue
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-DrsAutomationLevel cmdlet."
    }

}
Export-ModuleMember -Function Get-DrsAutomationLevel
Function Set-Retreatmode {
    <#
        .SYNOPSIS
        Sets retreat mode for vSphere Cluster Services (vCLS) virtual machines on a cluster.

        .DESCRIPTION
        The Set-Retreatmode cmdlet enables or disables retreat mode for the vSphere Cluster Services (vCLS) virtual machines.

        .EXAMPLE
        Set-Retreatmode -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -mode [retreat_mode]
        This example places the vSphere Cluster virtual machines (vCLS) in the specified retreat mode in a specified cluster.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER mode
        The name of the retreat mode.
        The value can be one of the following ("enable", "disable").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("enable", "disable")] [String]$Mode,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Set-Retreatmode cmdlet."
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$Server'..."
                # vCLS retreat mode via advanced settings is deprecated in vSphere 9.0. Skip on vSphere 9+.
                $vCenterMajorVersion = [int]($DefaultVIServer.Version -split '\.')[0]
                if ($vCenterMajorVersion -ge 9) {
                    Write-LogMessage -Type WARNING -Message "vCLS retreat mode is not supported on vSphere 9.0 and later. Skipping Set-Retreatmode for server '$Server'."
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                    return
                }
                $cluster_id = Get-Cluster -Name $Cluster | Select-Object -Property Id
                $cluster_id.Id -match 'domain-c.*' | Out-Null
                $domain_id = $Matches[0]
                $advanced_setting = "config.vcls.clusters.$domain_id.enabled"
                if (Get-AdvancedSetting -Entity $Server -Name $advanced_setting) {
                    Write-LogMessage -Type INFO -Message "Advanced setting $advanced_setting is present."
                    if ($Mode -EQ 'enable') {
                        Get-AdvancedSetting -Entity $Server -Name $advanced_setting | Set-AdvancedSetting -Value 'false' -Confirm:$false | Out-Null
                        Write-LogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false."
                    } else {
                        Get-AdvancedSetting -Entity $Server -Name $advanced_setting | Set-AdvancedSetting -Value 'true' -Confirm:$false | Out-Null
                        Write-LogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true."
                    }
                } else {
                    if ($Mode -EQ 'enable') {
                        New-AdvancedSetting -Entity $Server -Name $advanced_setting -Value 'false' -Confirm:$false | Out-Null
                        Write-LogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false."
                    } else {
                        New-AdvancedSetting -Entity $Server -Name $advanced_setting -Value 'true' -Confirm:$false | Out-Null
                        Write-LogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Set-Retreatmode cmdlet."
    }

}
Export-ModuleMember -Function Set-Retreatmode
Function Get-VMToClusterMapping {
    <#
        .SYNOPSIS
        Returns a list of all virtual machines that are running on a cluster.

        .DESCRIPTION
        The Get-VMToClusterMapping cmdlet returns a list of all virtual machines that are running on a specified cluster.

        .EXAMPLE
        Get-VMToClusterMapping -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -folder [folder_name]
        This example returns all virtual machines in a specified folder on a specified cluster.

        .EXAMPLE
        Get-VMToClusterMapping -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -folder [folder_name] -powerstate [power_state]
        This example returns only the virtual machines in a specified folder on a specified cluster for a specified power state.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER folder
        The name of the folder to search for virtual machines.

        .PARAMETER silence
        The switch to supress selected log messages.

        .PARAMETER powerstate
        The powerstate of the virtual machines.
        The value can be one of the following ("poweredon","poweredoff").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$Cluster,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Folder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$Silence,
        [Parameter (Mandatory = $false)] [ValidateSet("poweredon", "poweredoff")] [String]$PowerState

    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Starting the call to the Get-VMToClusterMapping cmdlet." }
        $checkServer = (Test-ManagementEndpoint -Server $Server -Port 443)
        if ($checkServer) {
            if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Connecting to '$Server'..." }
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $Server -Protocol https -User $User -Password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Connected to server '$Server'..." }
                foreach ($clus in $Cluster) {
                    if ($PowerState) {
                        $VMs += get-vm -location $clus | Where-Object { (Get-VM -location $Folder) -contains $_ } | Where-Object PowerState -EQ $PowerState
                    } else {
                        $VMs += get-vm -location $clus | Where-Object { (Get-VM -location $Folder) -contains $_ }
                    }
                }
                $clustersstring = $Cluster -join ","
                if (-Not $Silence) { Write-LogMessage -Type INFO -Message "The list of VMs on cluster $clustersstring is $VMs" }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $VMs

            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to server '$Server'. Check your environment and try again."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again"
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        if (-Not $Silence) { Write-LogMessage -Type INFO -Message "Completed the call to the Get-VMToClusterMapping cmdlet." }
    }

}
Export-ModuleMember -Function Get-VMToClusterMapping
Function Wait-ForStableNsxtClusterStatus {
    <#
        .SYNOPSIS
        Returns the cluster status of an NSX Manager after a restart.

        .DESCRIPTION
        The `Wait-ForStableNsxtClusterStatus` cmdlet returns the cluster status of an NSX manager after a restart.

        .EXAMPLE
        Wait-ForStableNsxtClusterStatus -server [nsx_manager_fqdn] -user [admin_username] -pass [admin_password]
        This example gets the cluster status of the NSX Cluster.

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Wait-ForStableNsxtClusterStatus cmdlet."
        Write-LogMessage -Type INFO -Message "Waiting the cluster to become 'STABLE' for NSX Manager '$Server'... This could take up to 20 min."
        # Create NSX-T header
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $User, $Pass))) # Create Basic Authentication Encoded Credentials
        $headers = @{"Accept" = "application/json" }
        $headers.Add("Authorization", "Basic $base64AuthInfo")
        $uri = "https://$Server/api/v1/cluster/status"
        $retryCount = 0
        $completed = $false
        $response = $null
        $SecondsDelay = 30
        $Retries = 20
        $aditionalWaitMultiplier = 3
        $successfulConnections = 0
        While (-Not $completed) {
            # Check iteration number
            if ($retrycount -ge $Retries) {
                Write-LogMessage -Type WARNING -Message "Request to '$uri' failed after $retryCount attempts."
                return $false
            }
            $retryCount++
            # Retry connection if NSX Manager is not online
            Try {
                $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ContentType application/json -TimeoutSec 60
            } Catch {
                Write-LogMessage -Type INFO -Message "Could not connect to NSX Manager '$Server'! Sleeping $($SecondsDelay * $aditionalWaitMultiplier) seconds before next attempt."
                Start-Sleep -s $($SecondsDelay * $aditionalWaitMultiplier)
                continue
            }
            $successfulConnections++
            if ($response.mgmt_cluster_status.status -ne 'STABLE') {
                Write-LogMessage -Type INFO -Message "Expecting NSX Manager cluster state 'STABLE', present state: $($response.mgmt_cluster_status.status)"
                # Add longer sleep during fiest several attempts to avoid locking the NSX-T account just after power-on
                if ($successfulConnections -lt 4) {
                    Write-LogMessage -Type INFO -Message "Sleeping for $($SecondsDelay * $aditionalWaitMultiplier) seconds before next check..."
                    Start-Sleep -s $($SecondsDelay * $aditionalWaitMultiplier)
                } else {
                    Write-LogMessage -Type INFO -Message "Sleeping for $SecondsDelay seconds until the next check..."
                    Start-Sleep -s $SecondsDelay
                }
            } else {
                $completed = $true
                Write-LogMessage -Type INFO -Message "The state of the NSX Manager cluster '$Server' is 'STABLE'."
                return $true
            }
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Wait-ForStableNsxtClusterStatus cmdlet."
    }
}
Export-ModuleMember -Function Wait-ForStableNsxtClusterStatus
Function Get-EdgeNodeFromNSXManager {
    <#
        .SYNOPSIS
        Returns a list of NSX Edge nodes from NSX.

        .DESCRIPTION
        The Get-EdgeNodeFromNSXManager cmdlet returns a list of NSX Edge nodes from NSX.

        .EXAMPLE
        Get-EdgeNodeFromNSXManager -server [nsx_fqdn] -user [admin_username] -pass [admin_password]
        This example returns a list of NSX Edge nodes from NSX.

        .EXAMPLE
        Get-EdgeNodeFromNSXManager -server [nsx_fqdn] -user [admin_username] -pass [admin_password] -VCfqdn [vcenter_fqdn]
        This example returns a list of NSX Edge nodes from a specified vCenter.

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.

        .PARAMETER VCfqdn
        The FQDN of the vCenter.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$VCfqdn
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-EdgeNodeFromNSXManager cmdlet."
        if ( Test-ManagementEndpoint -Server $Server -Port 443 ) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            $headers = New-NsxApiHeader -User $User -Pass $Pass

            # Detect NSX version to select the correct transport nodes API path.
            $nsxVersion = (Invoke-RestMethod -Method GET -Uri "https://${Server}/api/v1/node/version" -Headers $headers).product_version
            $nsxMajorVersion = [int]($nsxVersion -split '\.')[0]

            # Fetch compute managers to correlate vCenter FQDN to an ID.
            $computeManagers = (Invoke-RestMethod -Method GET -Uri "https://${Server}/api/v1/fabric/compute-managers" -Headers $headers).results
            $computeResourceId = ($computeManagers | Where-Object { $_.display_name -match $VCfqdn }).id

            $edgeNodesList = @()
            if ($nsxMajorVersion -ge 9) {
                # NSX 9.0+ uses the Policy API for transport nodes.
                $transportNodes = (Invoke-RestMethod -Method GET -Uri "https://${Server}/policy/api/v1/infra/sites/default/enforcement-points/default/edge-transport-nodes" -Headers $headers).results
                foreach ($resource in $transportNodes) {
                    if ($resource.node_deployment_info.deployment_config.vm_deployment_config.vc_id -match $computeResourceId) {
                        [Array]$edgeNodesList += $resource.display_name
                    }
                }
            } else {
                # NSX 3.x / 4.x (VCF 5.x) uses the v1 management plane API.
                $transportNodes = (Invoke-RestMethod -Method GET -Uri "https://${Server}/api/v1/transport-nodes" -Headers $headers).results
                foreach ($resource in $transportNodes) {
                    if ($resource.node_deployment_info.resource_type -EQ "EdgeNode") {
                        if ($resource.node_deployment_info.deployment_config.vm_deployment_config.vc_id -match $computeResourceId) {
                            [Array]$edgeNodesList += $resource.display_name
                        }
                    }
                }
            }
            return $edgeNodesList
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-EdgeNodeFromNSXManager cmdlet."
    }
}
Export-ModuleMember -Function Get-EdgeNodeFromNSXManager
Function Get-NSXTComputeManagers {
    <#
        .SYNOPSIS
        Returns the list of all NSX Compute Managers connected to NSX.

        .DESCRIPTION
        The Get-NSXTComputeManagers cmdlet returns the list of all NSX Compute Managers connected to NSX.

        .EXAMPLE
        Get-NSXTComputeManagers -server [nsx_fqdn] -user [admin_username] -pass [admin_password]
        This example returns the list of all NSX Compute Managers connected to NSX.

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-NSXTComputeManagers cmdlet."
        if ( Test-ManagementEndpoint -Server $Server -Port 443 ) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            $headers = New-NsxApiHeader -User $User -Pass $Pass
            $computeManagers = (Invoke-RestMethod -Method GET -Uri "https://${Server}/api/v1/fabric/compute-managers" -Headers $headers).results
            return $computeManagers.server
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-NSXTComputeManagers cmdlet."
    }
}
Export-ModuleMember -Function Get-NSXTComputeManagers
Function Get-TanzuEnabledClusterStatus {
    <#
        .SYNOPSIS
        Returns the Tanzu status of a specified cluster.

        .DESCRIPTION
        The Get-TanzuEnabledClusterStatus checks if a specified cluster has Tanzu enabled.

        .EXAMPLE
        Get-TanzuEnabledClusterStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
        This example returns status (True/False) if the specified cluster has Tanzu enabled.

        .PARAMETER server
        The FQDN of the vCenter.

        .PARAMETER user
        The username to authenticate to vCenter.

        .PARAMETER pass
        The password to authenticate to vCenter.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Cluster,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$Pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$User
    )

    $Pass = Get-Password -User $User -Password $Pass

    Try {
        Write-LogMessage -Type INFO -Message "Starting the call to the Get-TanzuEnabledClusterStatus cmdlet."
        if ( Test-ManagementEndpoint -Server $Server -Port 443 ) {
            Write-LogMessage -Type INFO -Message "Connecting to '$Server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -server $Server -user $User -password $Pass | Out-Null
            if ($DefaultVIServer.Name -EQ $Server) {
                # Retrieve the cluster MoRef ID, then query the namespace-management REST API.
                $clusterMoRef = (Get-Cluster -Name $Cluster).ExtensionData.MoRef.Value
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                $sessionToken = New-VcenterApiSession -Server $Server -User $User -Pass $Pass
                $headers = @{ "vmware-api-session-id" = $sessionToken; "Content-Type" = "application/json" }
                Try {
                    $response = Invoke-RestMethod -Method GET -Uri "https://${Server}/api/vcenter/namespace-management/clusters/${clusterMoRef}" -Headers $headers -ErrorAction Stop
                    if ($response) {
                        Write-LogMessage -Type INFO -Message "vSphere with Tanzu is enabled."
                        return $True
                    }
                } Catch {
                    Write-LogMessage -Type INFO -Message "vSphere with Tanzu is not enabled."
                    return $False
                }
            } else {
                Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check the console output for more details."
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Connection to '$Server' has failed. Check your environment and try again."
        }
    } Catch {
        Write-LogMessage -Type ERROR -Message "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)."
    } Finally {
        Write-LogMessage -Type INFO -Message "Completed the call to the Get-TanzuEnabledClusterStatus cmdlet."
    }
}
Export-ModuleMember -Function Get-TanzuEnabledClusterStatus
Export-ModuleMember -Function New-LogFile
Export-ModuleMember -Function Write-LogMessage
