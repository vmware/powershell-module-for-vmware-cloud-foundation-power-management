# Copyright 2023-2024 Broadcom. All Rights Reserved.
# SPDX-License-Identifier: BSD-2

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This PowerShell module should be considered entirely experimental. It is still in development & not tested beyond
# lab scenarios. It is recommended you don't use it for any production environment without testing extensively!

# Enable communication with self-signed certificates when using Powershell Core if you require all communications to be secure
# and do not wish to allow communication with self-signed certificates remove lines 16-40 before importing the module.

# Enable self-signed certificates
if ($PSEdition -EQ 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -EQ 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    if (-Not ([System.Management.Automation.PSTypeName]'TrustAllCertificatePolicy').Type) {
        Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertificatePolicy : ICertificatePolicy {
        public TrustAllCertificatePolicy() {}
        public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate certificate,
            WebRequest wRequest, int certificateProblem) {
            return true;
        }
    }
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertificatePolicy
    }
}
# End of "Enable self-signed certificates" section

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

Function Stop-CloudComponent {
    <#
        .SYNOPSIS
        Shutdown node(s) in a vCenter Server inventory

        .DESCRIPTION
        The Stop-CloudComponent cmdlet shutdowns the given node(s) in a vCenter Server inventory

        .EXAMPLE
        Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
        This example connects to a vCenter Server and shuts down the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
        This example connects to an ESXi Host and shuts down the nodes that match the pattern vCLS.*

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

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
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$timeout,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$noWait,
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$pattern
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Stop-CloudComponent cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                if ($PSCmdlet.ParameterSetName -EQ "Node") {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to shut down nodes '$nodes_string'..."
                    $nodes_string = $nodes -join "; "
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -EQ $node }) {
                                $vmObject = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vmObject.State -EQ 'NotRunning') {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' is already powered off."
                                    Continue
                                }
                                Write-PowerManagementLogMessage -Type INFO -Message "Attempting to shut down node '$node'..."
                                if ($PsBoundParameters.ContainsKey("noWait")) {
                                    Stop-VM -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                } else {
                                    Stop-VMGuest -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                    Write-PowerManagementLogMessage -Type INFO -Message "Waiting for node '$node' to shut down..."
                                    $sleepTime = 5
                                    While (($vmObject.State -ne 'NotRunning') -and ($count -le $timeout)) {
                                        Start-Sleep -s $sleepTime
                                        $count = $count + $sleepTime
                                        $vmObject = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                    }
                                    if ($count -gt $timeout) {
                                        Write-PowerManagementLogMessage -Type ERROR -Message "Node '$node' did not shut down within the expected timeout $timeout value."
                                    } else {
                                        Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' has shut down successfully."
                                    }
                                }
                            } else {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to find node '$node' in the inventory of server '$server'."
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -EQ "Pattern") {
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -Match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -Match $server
                    } else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vmObject = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -Match $server
                            if ($vmObject.State -EQ 'NotRunning') {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' is already powered off."
                                Continue
                            }
                            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to shut down node '$($node.name)'..."
                            if ($PsBoundParameters.ContainsKey("noWait")) {
                                Stop-VM -Server $server -VM $node.Name -Confirm:$false | Out-Null
                            } else {
                                Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -Match $server | Stop-VMGuest -Confirm:$false | Out-Null
                                $vmObject = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -Match $server
                                $sleepTime = 1
                                While (($vmObject.State -ne 'NotRunning') -and ($count -le $timeout)) {
                                    Start-Sleep -s $sleepTime
                                    $count = $count + $sleepTime
                                    $vmObject = Get-VMGuest -VM $node.Name | Where-Object VmUid -Match $server
                                }
                                if ($count -gt $timeout) {
                                    Write-PowerManagementLogMessage -Type ERROR -Message "Node '$($node.name)' did not shut down within the expected timeout $timeout value."
                                } else {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' has shut down successfully."
                                }
                            }
                        }
                    } elseif ($pattern) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "No nodes match pattern '$pattern' on host '$server'."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Stop-CloudComponent cmdlet."
    }
}
Export-ModuleMember -Function Stop-CloudComponent

Function Start-CloudComponent {
    <#
        .SYNOPSIS
        Startup node(s) in a vCenter Server inventory

        .DESCRIPTION
        The Start-CloudComponent cmdlet starts up the given node(s) in a vCenter Server inventory

        .EXAMPLE
        Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
        This example connects to a vCenter Server and starts up the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
        This example connects to an ESXi Host and starts up the nodes that match the pattern vCLS.*

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER timeout
        The timeout in seconds to wait for the cloud component to reach the desired connection state.

        .PARAMETER nodes
        The FQDNs of the list of cloud components to startup.

        .PARAMETER pattern
        The cloud components matching the pattern in the SDDC Manager inventory to be startup.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$timeout,
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$pattern
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Start-CloudComponent cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                if ($PSCmdlet.ParameterSetName -EQ "Node") {
                    $nodes_string = $nodes -join "; "
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to start nodes '$nodes_string'."
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -EQ $node }) {
                                $vmObject = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vmObject.State -EQ 'Running') {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' is already in powered on."
                                    Continue
                                }
                                Write-PowerManagementLogMessage -Type INFO -Message "Attempting to start up node '$node'..."
                                Start-VM -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                Start-Sleep -s 5
                                $sleepTime = 10
                                Write-PowerManagementLogMessage -Type INFO -Message "Waiting for node '$node' to start up..."
                                While (($vmObject.State -ne 'Running') -and ($count -le $timeout)) {
                                    Start-Sleep -s $sleepTime
                                    $count = $count + $sleepTime
                                    $vmObject = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                }
                                if ($count -gt $timeout) {
                                    Write-PowerManagementLogMessage -Type ERROR -Message "Node '$node' did not start up within the expected timeout $timeout value."
                                    Break
                                } else {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' has started successfully."
                                }
                            } else {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot find '$node' in the inventory of host '$server'."
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -EQ "Pattern") {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to host '$server' and attempting to start up nodes with pattern '$pattern'..."
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -Match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -Match $server
                    } else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vmObject = Get-VMGuest -server $server -VM $node.Name | Where-Object VmUid -Match $server
                            if ($vmObject.State -EQ 'Running') {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' is already powered on."
                                Continue
                            }

                            Start-VM -VM $node.Name | Out-Null
                            $sleepTime = 1
                            $vmObject = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -Match $server
                            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to start up node '$($node.name)'..."
                            While (($vmObject.State -ne 'Running') -AND ($count -le $timeout)) {
                                Start-Sleep -s $sleepTime
                                $count = $count + $sleepTime
                                $vmObject = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -Match $server
                            }
                            if ($count -gt $timeout) {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Node '$($node.name)' did not start up within the expected timeout $timeout value."
                            } else {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' has started successfully."
                            }
                        }
                    } elseif ($pattern) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "No nodes match pattern '$pattern' on host '$server'."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to host '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Start-CloudComponent cmdlet."
    }
}
Export-ModuleMember -Function Start-CloudComponent

Function Set-MaintenanceMode {
    <#
        .SYNOPSIS
        Enable or disable maintenance mode on an ESXi host.

        .DESCRIPTION
        The Set-MaintenanceMode cmdlet enables or disables maintenance mode on an ESXi host.

        .EXAMPLE
        Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state ENABLE
        This example places an ESXi host in maintenance mode.

        .EXAMPLE
        Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state DISABLE
        This example takes an ESXi host out of maintenance mode.

        .PARAMETER server
        The FQDN of the ESXi host.

        .PARAMETER user
        The username to authenticate to ESXi host.

        .PARAMETER pass
        The password to authenticate to ESXi host.

        .PARAMETER state
        The state of the maintenance mode to be set on ESXi host. Allowed states are "ENABLE" or "DISABLE".
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("ENABLE", "DISABLE")] [String]$state
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-MaintenanceMode cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state maintenance mode..."
                $hostStatus = (Get-VMHost -Server $server)
                if ($state -EQ "ENABLE") {
                    if ($hostStatus.ConnectionState -EQ "Connected") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Attempting to enter maintenance mode for '$server'..."
                        Get-View -Server $server -ViewType HostSystem -Filter @{"Name" = $server } | Where-Object { !$_.Runtime.InMaintenanceMode } | ForEach-Object { $_.EnterMaintenanceMode(0, $false, (New-Object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode = (New-Object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction = [VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction }) })) } | Out-Null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -EQ "Maintenance") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has entered maintenance mode successfully."
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' did not enter maintenance mode. Check your environment and try again."
                        }
                    } elseif ($hostStatus.ConnectionState -EQ "Maintenance") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already entered maintenance mode."
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected."
                    }
                }

                elseif ($state -EQ "DISABLE") {
                    if ($hostStatus.ConnectionState -EQ "Maintenance") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Attempting to exit maintenance mode for '$server'..."
                        $task = Set-VMHost -VMHost $server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Wait-Task $task | Out-Null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -EQ "Connected") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has exited maintenance mode successfully."
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "The host '$server' did not exit maintenance mode. Check your environment and try again."
                        }
                    } elseif ($hostStatus.ConnectionState -EQ "Connected") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already exited maintenance mode"
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-MaintenanceMode cmdlet."
    }
}
Export-ModuleMember -Function Set-MaintenanceMode

Function Get-MaintenanceMode {
    <#
        .SYNOPSIS
        Get maintenance mode status on an ESXi host.

        .DESCRIPTION
        The Get-MaintenanceMode cmdlet gets the maintenance mode status on an ESXi host.

        .EXAMPLE
        Get-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1!
        This example returns the ESXi host maintenance mode status.

        .PARAMETER server
        The FQDN of the ESXi host.

        .PARAMETER user
        The username to authenticate to ESXi host.

        .PARAMETER pass
        The password to authenticate to ESXi host.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-MaintenanceMode cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                $hostStatus = (Get-VMHost -Server $server)
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'. The connection status is '$($hostStatus.ConnectionState)'."
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $hostStatus.ConnectionState
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-MaintenanceMode cmdlet."
    }
}
Export-ModuleMember -Function Get-MaintenanceMode

Function Set-DrsAutomationLevel {
    <#
        .SYNOPSIS
        Set the DRS automation level

        .DESCRIPTION
        The Set-DrsAutomationLevel cmdlet sets the automation level of the cluster based on the setting provided

        .EXAMPLE
        Set-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -level PartiallyAutomated
        Thi examples sets the DRS Automation level for the sfo-m01-cl01 cluster to Partially Automated

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster on which the DRS automation level settings are to be applied.

        .PARAMETER level
        The DRS automation level to be set. The value can be one amongst ("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled")] [String]$level
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-DrsAutomationLevel cmdlet."

        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                $drsStatus = Get-Cluster -Name $cluster -ErrorAction SilentlyContinue
                if ($drsStatus) {
                    if ($drsStatus.DrsAutomationLevel -EQ $level) {
                        Write-PowerManagementLogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$cluster' is already '$level'."
                    } else {
                        $drsStatus = Set-Cluster -Cluster $cluster -DrsAutomationLevel $level -Confirm:$false
                        if ($drsStatus.DrsAutomationLevel -EQ $level) {
                            Write-PowerManagementLogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$cluster' has been set to '$level' successfully."
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Failed to set the vSphere DRS automation level for cluster '$cluster' to '$level'."
                        }
                    }
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cluster '$cluster' not found on host '$server'. Check your environment and try again."
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-DrsAutomationLevel cmdlet."
    }
}
Export-ModuleMember -Function Set-DrsAutomationLevel


Function Set-VsanClusterPowerStatus {
    <#
        .SYNOPSIS
        PowerOff or PowerOn the vSAN Cluster

        .DESCRIPTION
        The Set-VsanClusterPowerStatus cmdlet either powers off or powers on a vSAN cluster

        .EXAMPLE
        Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOff
        This example powers off cluster sfo-m01-cl01

        Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOn
        This example powers on cluster sfo-m01-cl01

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER clusterName
        The name of the vSAN cluster on which the power settings are to be applied.

        .PARAMETER mgmt
        The switch used to ignore power settings if management domain information is passed.

        .PARAMETER PowerStatus
        The power state to be set for a given vSAN cluster. The value can be one amongst ("clusterPoweredOff", "clusterPoweredOn").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$clusterName,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$mgmt,
        [Parameter (Mandatory = $true)] [ValidateSet("clusterPoweredOff", "clusterPoweredOn")] [String]$powerStatus
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Starting the call to the Set-VsanClusterPowerStatus cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Connecting to '$server'..."
            if ($DefaultVIServer.Name -notcontains $server -or $DefaultVIServer.IsConnected -eq $false) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server' ..."
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass -ErrorVariable $vcConnectError | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Already connected to server '$server'."
            }
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Connected to server '$server' and setting the power status for cluster '$clusterName' to '$powerStatus'..."
                $clusterStatus = Get-VsanClusterPowerState -Cluster $clusterName -Server $server

                # Start cluster if it is powered off and not in the process of being powered on
                if ($powerStatus -eq "clusterPoweredOn") {
                    if ($null -eq $clusterStatus.TrackingTask) {
                        if ($clusterStatus.CurrentClusterPowerStatus -eq "clusterPoweredOn") {
                            Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Cluster is already powered on. Skipping the operation."
                            return
                        } else {
                            $powerActionReason = "Startup through VMware Cloud Foundation script."
                            try {
                                Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Starting cluster '$clusterName'..."
                                Start-VsanCluster -Cluster $clusterName -PowerOnReason $powerActionReason -Server $server -ErrorAction Stop | Out-Null
                            } catch {
                                $errorMessage = $_.Exception.Message
                                return $errorMessage
                            }
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "[$clusterName] There is an active power operation in progress. Skipping cluster '$clusterName'."
                        return "There is an active power operation in progress. Skipping cluster '$clusterName'."
                    }
                }

                # Stop cluster if it is powered on and not in the process of being powered off
                if ($powerStatus -eq "clusterPoweredOff") {
                    if ($null -eq $clusterStatus.TrackingTask) {
                        if ($clusterStatus.CurrentClusterPowerStatus -eq "clusterPoweredOff") {
                            Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Cluster is already powered off. Skipping the operation."
                            return
                        } else {
                            $powerActionReason = "Shutdown through VMware Cloud Foundation script."
                            try {
                                Write-PowerManagementLogMessage -Type DEBUG -Message "[$clusterName] Stopping cluster '$clusterName'..."
                                Stop-VsanCluster -Cluster $clusterName -PowerOffReason $powerActionReason -Server $server -ErrorAction Stop | Out-Null
                            } catch {
                                $errorMessage = $_.Exception.Message
                                return $errorMessage
                            }
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type WARNING -Message "[$clusterName] There is an active power operation in progress. Skipping cluster '$clusterName'."
                        return "There is an active power operation in progress. Skipping cluster '$clusterName'."
                    }
                }

                # Monitor power task progress if we are not stopping Management Domain
                if (-Not $mgmt) {
                    $clusterStatus = Get-VsanClusterPowerState -Cluster $clusterName -Server $server
                    if ($null -eq $clusterStatus.TrackingTask) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "[$clusterName] No task found for the power operation."
                        return
                    } else {
                        Write-PowerManagementLogMessage -Type DEBUG -Message "[$clusterName] Monitoring task '$($clusterStatus.TrackingTask)' for the power operation."
                    }
                    $task = Get-Task -Id $clusterStatus.TrackingTask -Server $server
                    $oldProgress = $($task.PercentComplete)
                    $counter = 0
                    $sleepTime = 30 # in seconds
                    $timeoutTime = 15 # in minutes
                    do {
                        # Make sure we are still connected to the server
                        if ($DefaultVIServer.Name -notcontains $server -or $DefaultVIServer.IsConnected -eq $false) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server' ..."
                            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass -ErrorVariable $vcConnectError | Out-Null
                        }
                        $task = Get-Task -Id $clusterStatus.TrackingTask -Server $server
                        if (-Not ($task.State -EQ "Error")) {
                            if ($counter -eq 0) { Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] The '$($task.Name)' task for cluster '$clusterName' is $($task.PercentComplete)% completed." }
                            if ($oldProgress -ne $($task.PercentComplete)) {
                                Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] The '$($task.Name)' task for cluster '$clusterName' is $($task.PercentComplete)% completed."
                                $oldProgress = $($task.PercentComplete)
                            } else {
                                Write-PowerManagementLogMessage -Type DEBUG -Message "[$clusterName] The '$($task.Name)' task for cluster '$clusterName' is still $($task.PercentComplete)% completed."
                            }
                        } else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "[$clusterName] The task '$($task.Name)' failed with error '$((Get-VsanClusterPowerState -Cluster $clusterName).LastErrorMessage)'."
                            break
                        }
                        Start-Sleep -s $sleepTime
                        $counter += $sleepTime
                    } while ($task.State -NE "Success" -and $task.State -NE "Error" -and $counter -lt $timeoutTime * 60)
                }
                # Show time out message if task is not completed within the time limit
                if ($counter -ge $timeoutTime * 60) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$clusterName] The $powerStatus task did not complete within the expected timeout of $timeoutTime minutes."
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "[$clusterName] Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "[$clusterName] Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "[$clusterName] Completed the call to the Set-VsanClusterPowerStatus cmdlet."
    }
}
Export-ModuleMember -Function Set-VsanClusterPowerStatus

# Function Set-VsanClusterPowerStatus {
#     <#
#         .SYNOPSIS
#         PowerOff or PowerOn the vSAN Cluster

#         .DESCRIPTION
#         The Set-VsanClusterPowerStatus cmdlet either powers off or powers on a vSAN cluster

#         .EXAMPLE
#         Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOff
#         This example powers off cluster sfo-m01-cl01

#         Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOn
#         This example powers on cluster sfo-m01-cl01

#         .PARAMETER server
#         The FQDN of the vCenter Server.

#         .PARAMETER user
#         The username to authenticate to vCenter Server.

#         .PARAMETER pass
#         The password to authenticate to vCenter Server.

#         .PARAMETER clusterName
#         The name of the vSAN cluster on which the power settings are to be applied.

#         .PARAMETER mgmt
#         The switch used to ignore power settings if management domain information is passed.

#         .PARAMETER PowerStatus
#         The power state to be set for a given vSAN cluster. The value can be one amongst ("clusterPoweredOff", "clusterPoweredOn").
#     #>

#     Param (
#         [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
#         [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
#         [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
#         [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$clusterName,
#         [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$mgmt,
#         [Parameter (Mandatory = $true)] [ValidateSet("clusterPoweredOff", "clusterPoweredOn")] [String]$powerStatus
#     )

#     $pass = Get-Password -User $user -Password $pass

#     Try {
#         Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VsanClusterPowerStatus cmdlet."
#         # TODO - Add check for current state of the cluster. Do not run the set command if cluster is already in the desired state.
#         $checkServer = (Test-EndpointConnection -server $server -Port 443)
#         if ($checkServer) {
#             Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
#             if ($DefaultVIServers) {
#                 Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
#             }
#             Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
#             if ($DefaultVIServer.Name -EQ $server) {

#                 Import-Module VMware.VimAutomation.Storage
#                 $vsanClient = [VMware.VimAutomation.Storage.Interop.V1.Service.StorageServiceFactory]::StorageCoreService.ClientManager.GetClientByConnectionId($DefaultVIServer.Id)
#                 $vsanClusterPowerSystem = $vsanClient.VsanViewService.GetVsanViewById("VsanClusterPowerSystem-vsan-cluster-power-system")

#                 # Populate the needed spec:
#                 $spec = [VMware.Vsan.Views.PerformClusterPowerActionSpec]::new()

#                 $spec.powerOffReason = "Shutdown through VMware Cloud Foundation script"
#                 $spec.targetPowerStatus = $powerStatus

#                 $cluster = Get-Cluster $clusterName

#                 # TODO - Add check if there is task ID returned
#                 $powerActionTask = $vsanClusterPowerSystem.PerformClusterPowerAction($cluster.ExtensionData.MoRef, $spec)
#                 $task = Get-Task -Id $powerActionTask
#                 $counter = 0
#                 $sleepTime = 30 # in seconds
#                 if (-Not $mgmt) {
#                     do {
#                         $task = Get-Task -Id $powerActionTask
#                         if (-Not ($task.State -EQ "Error")) {
#                             Write-PowerManagementLogMessage -Type INFO -Message "$powerStatus task is $($task.PercentComplete)% completed."
#                         }
#                         Start-Sleep -s $sleepTime
#                         $counter += $sleepTime
#                     } while ($task.State -EQ "Running" -and ($counter -lt 1800))

#                     if ($task.State -EQ "Error") {
#                         if ($task.ExtensionData.Info.Error.Fault.FaultMessage -like "VMware.Vim.LocalizableMessage") {
#                             Write-PowerManagementLogMessage -Type ERROR -Message "'$($powerStatus)' task exited with a localized error message. Go to the vSphere Client for details and to take the necessary actions."
#                         } else {
#                             Write-PowerManagementLogMessage -Type WARN -Message "'$($powerStatus)' task exited with the Message:$($task.ExtensionData.Info.Error.Fault.FaultMessage) and Error: $($task.ExtensionData.Info.Error)."
#                             Write-PowerManagementLogMessage -Type ERROR -Message "Go to the vSphere Client for details and to take the necessary actions."
#                         }
#                     }

#                     if ($task.State -EQ "Success") {
#                         Write-PowerManagementLogMessage -Type INFO -Message "$powerStatus task is completed successfully."
#                     } else {
#                         Write-PowerManagementLogMessage -Type ERROR -Message "$powerStatus task is blocked in $($task.State) state."
#                     }
#                 }
#                 Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null

#             } else {
#                 Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
#             }
#         } else {
#             Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
#         }
#     } Catch {
#         Debug-CatchWriterForPowerManagement -object $_
#     } Finally {
#         Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VsanClusterPowerStatus cmdlet."
#     }
# }
# Export-ModuleMember -Function Set-VsanClusterPowerStatus

Function Invoke-VxrailClusterShutdown {
    <#
        .SYNOPSIS
        Invoke the shut down command on a VxRail cluster.

        .DESCRIPTION
        The cmdlet will perform a dry run test prior to initiate a shutdown command on a VxRail cluster.

        .EXAMPLE
        Invoke-VxrailClusterShutdown -server sfo-w01-vxrm.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example powers off a VxRail cluster cluster which is managed by the VxRail Manager sfo-w01-vxrm.sfo.rainpole.io controls.

    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Invoke-VxrailClusterShutdown cmdlet."

        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }

            # Prepare VxRail rest API headers and payload
            $payloadTest = @{ dryrun = 'true' } | ConvertTo-Json
            $payloadRun = @{ dryrun = 'false' } | ConvertTo-Json
            $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass))) # Create Basic Authentication Encoded Credentials
            $headers = @{"Content-Type" = "application/json" }
            $headers.Add("Authorization", "Basic $base64AuthInfo")
            $uri = "https://$server/rest/vxm/v1/cluster/shutdown"

            Write-PowerManagementLogMessage -Type INFO -Message "Starting VxRail cluster shutdown dry run."
            $respond = Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -Body $payloadTest -UseBasicParsing -SkipCertificateCheck
            if ($respond.StatusCode -EQ "202" -or $respond.StatusCode -EQ "200") {
                $requestID = $respond.content | ConvertFrom-Json
                Write-PowerManagementLogMessage -Type INFO -Message "VxRail cluster shutdown request accepted(ID:$($requestID.request_id))"
                $uri2 = "https://$server/rest/vxm/v1/requests/$($requestID.request_id)"
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
                    Write-PowerManagementLogMessage -Type INFO -Message "VxRail cluster shutdown dry run: SUCCEEDED."
                    Write-PowerManagementLogMessage -Type INFO -Message "Starting VxRail cluster shutdown."

                    $respond = Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -Body $payloadRun -UseBasicParsing -SkipCertificateCheck
                    if ($respond.StatusCode -EQ "202" -or $respond.StatusCode -EQ "200") {
                        return $true
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "VxRail cluster shutdown: FAILED"
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
                    Write-PowerManagementLogMessage -Type ERROR -Message "VxRail cluster shutdown dry run: FAILED `n $errorMsg"
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "VxRail cluster shutdown: FAILED"
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Invoke-VxrailClusterShutdown cmdlet."
    }
}
Export-ModuleMember -Function Invoke-VxrailClusterShutdown

Function Get-poweronVMsOnRemoteDS {
    <#
        .SYNOPSIS
        Get a list of VMs that reside on a vSAN HCI Mesh datastore hosted in a specified cluster

        .DESCRIPTION
        The Get-poweronVMsOnRemoteDS cmdlet returns a list of VMs that reside on a vSAN HCI Mesh datastore hosted in a specified cluster

        .EXAMPLE
        Get-poweronVMsOnRemoteDS -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -clustertocheck sfo-m01-cl01
        This example returns the list of VMs that reside on a vSAN HCI Mesh datastore hosted in cluster sfo-m01-cl01.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER clusterToCheck
        The name of the remote cluster on which virtual machines are hosted.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$clusterToCheck
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-poweronVMsOnRemoteDS cmdlet."

        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                $TotalvSANDatastores = @()
                $RemotevSANdatastores = @()
                $TotalvSANDatastores = (Get-Cluster -Name $clusterToCheck | Get-Datastore | Where-Object { $_.Type -EQ "vSAN" }).Name
                $RemotevSANdatastores = ((Get-VsanClusterConfiguration -Cluster $clusterToCheck).RemoteDatastore).Name
                $LocalvSANDatastores = $TotalvSANDatastores | Where-Object { $_ -notin $RemotevSANdatastores }
                [Array]$PoweredOnVMs = @()
                foreach ($localds in $LocalvSANDatastores) {
                    foreach ($cluster in (Get-Cluster).Name) {
                        if ($cluster -ne $clusterToCheck ) {
                            $MountedvSANdatastores = ((Get-VsanClusterConfiguration -Cluster $cluster).RemoteDatastore).Name
                            foreach ($datastore in $MountedvSANdatastores) {
                                if ($datastore -EQ $localds) {
                                    $datastoreID = Get-Datastore $datastore | ForEach-Object { $_.ExtensionData.MoRef }
                                    $vms = (Get-Cluster -Name $cluster | Get-VM | Where-Object { $_.PowerState -EQ "PoweredOn" }) | Where-Object { $vm = $_; $datastoreID | Where-Object { $vm.DatastoreIdList -contains $_ } }
                                    if ($vms) {
                                        Write-PowerManagementLogMessage -Type INFO -Message "Remote VMs with names $vms are running on cluster '$cluster' and datastore '$datastore.' `n"
                                        [Array]$PoweredOnVMs += $vms
                                    }
                                }
                            }
                        }
                    }
                }
                return $PoweredOnVMs
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-poweronVMsOnRemoteDS cmdlet."
    }
}
Export-ModuleMember -Function Get-poweronVMsOnRemoteDS

Function Test-LockdownMode {
    <#
        .SYNOPSIS
        Check if some of the ESXi hosts in the specified cluster is in lockdown mode.

        .DESCRIPTION
        The Test-LockdownMode cmdlet returns an error if an ESXi host in the cluster is in lockdown mode.

        .EXAMPLE
        Test-LockdownMode -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01
        This example checks if some of the ESXi hosts in the cluster sfo-m01-cl01 is in lockdown mode.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster to be checked for locked down ESXi hosts if any.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Starting the call to the Test-LockdownMode cmdlet."

        $checkServer = (Test-EndpointConnection -server $server -port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                if ($DefaultVIServers.Name -notcontains $server) {
                    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Already connected to server '$server'."
                }
            } else {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            }
            if ($DefaultVIServers.Name -contains $server) {
                $hostsInCluster = @()
                $hostsInCluster = Get-Cluster -Server $server -Name $cluster | Get-VMHost
                $hostsWithLockdown = ""
                if ($hostsInCluster.count -ne 0) {
                    foreach ($esxiHost in $hostsInCluster) {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Checking lockdown mode for $esxiHost ...."
                        $lockdownStatus = (Get-VMHost -Server $server -Name $esxiHost).ExtensionData.Config.LockdownMode
                        if ($lockdownStatus -EQ $null) {
                            $checkServer = (Test-EndpointConnection -server $esxiHost -port 443)
                            if ($checkServer) {
                                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot fetch information about lockdown mode for ESXi host $esxiHost!"
                            } else {
                                Write-PowerManagementLogMessage -Type WARNING -Message "[$cluster] Cannot fetch information about lockdown mode. Host $esxiHost is not reachable."
                                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Check the status on the ESXi host $esxiHost!"
                            }
                        } else {
                            if ($lockdownStatus -ne "lockdownDisabled") {
                                Write-PowerManagementLogMessage -Type WARNING -Message "[$cluster] Lockdown mode is enabled for ESXi host $esxiHost"
                                $hostsWithLockdown += ", $esxiHost"
                            }
                        }
                    }
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cluster $cluster is not present on server $server. Check the input to the cmdlet."
                }
                if ([string]::IsNullOrEmpty($hostsWithLockdown)) {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] he following ESXi hosts are in lockdown mode: $hostsWithLockdown. Disable lockdown mode to continue."
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Cluster $cluster does not have ESXi hosts in lockdown mode."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Some hosts are in lockdown mode. Disable lockdown mode to continue."
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Connection to '$server' has failed. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Completed the call to the Test-LockdownMode cmdlet."
    }
}
Export-ModuleMember -Function Test-LockdownMode

Function Get-PoweredOnHostsInCluster {
    <#
        .SYNOPSIS
        Check if some of the ESXi hosts in the specified cluster are not connected.

        .DESCRIPTION
        The Get-PoweredOnHostsInCluster cmdlet returns an error if an ESXi host in the cluster is not communicating with the vCenter.

        .EXAMPLE
        Get-PoweredOnHostsInCluster -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -Pass VMw@re1! -cluster sfo-m01-cl01
        This example checks if some of the ESXi hosts in the cluster sfo-m01-cl01 does not communicate with vCenter.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster to be checked.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Starting the call to the Get-PoweredOnHostsInCluster cmdlet."

        $checkServer = (Test-EndpointConnection -server $server -port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Connecting to '$server'..."
            if ($DefaultVIServers) {
                if ($DefaultVIServers.Name -notcontains $server) {
                    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Already connected to server '$server'."
                }
            } else {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            }
            if ($DefaultVIServers.Name -contains $server) {
                Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Connected to server '$server' and attempting to get the list of virtual machines..."
                # Get list of all ESXi hosts in the cluster and return the ones that are powerdOn
                $hostsInCluster = @()
                $hostsInCluster = Get-Cluster -Server $server -Name $cluster | Get-VMHost
                $poweredOnHosts = @()
                if ($hostsInCluster.count -ne 0) {
                    $poweredOnHosts = $hostsInCluster | Where-Object { $_.PowerState -eq "PoweredOn" }
                    return $poweredOnHosts
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Could not find any ESXi hosts in '$cluster' on server '$server'. Check the input to the cmdlet."
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Connection to '$server' has failed. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type DEBUG -Message "[$cluster] Completed the call to the Get-PoweredOnHostsInCluster cmdlet."
    }
}
Export-ModuleMember -Function Get-PoweredOnHostsInCluster

Function Get-VMRunningStatus {
    <#
        .SYNOPSIS
        Gets the running state of a virtual machine

        .DESCRIPTION
        The Get-VMRunningStatus cmdlet gets the running status of the given nodes matching the pattern on an ESXi host

        .EXAMPLE
        Get-VMRunningStatus -server sfo-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -pattern "^vCLS*"
        This example connects to an ESXi host and searches for all virtual machines matching the pattern and gets their running status

        .PARAMETER server
        The FQDN of the ESXi host.

        .PARAMETER user
        The username to authenticate to ESXi host.

        .PARAMETER pass
        The password to authenticate to ESXi host.

        .PARAMETER pattern
        The pattern to match set of virtual machines.

        .PARAMETER Status
        The state of the virtual machine to be tested against. The value can be one amongst ("Running", "NotRunning"). The default value is "Running".
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pattern,
        [Parameter (Mandatory = $false)] [ValidateSet("Running", "NotRunning")] [String]$Status = "Running"
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMRunningStatus cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to host '$server' and checking if nodes named '$pattern' are in the '$($status.ToUpper())' state..."
                $nodes = Get-VM | Where-Object Name -Match $pattern | Select-Object Name, PowerState, VMHost
                if ($nodes.Name.Count -EQ 0) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot find nodes matching pattern '$pattern' in the inventory of host '$server'."
                } else {
                    foreach ($node in $nodes) {
                        $vmObject = Get-VMGuest -Server $server -VM $node.Name -ErrorAction SilentlyContinue | Where-Object VmUid -Match $server
                        if ($vmObject.State -EQ $status) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Node $($node.Name) is in '$($status.ToUpper()) state.'"
                            return $true
                        } else {

                            Write-PowerManagementLogMessage -Type INFO -Message "Node $($node.Name) is not in '$($status.ToUpper()) state'."
                            return $false
                        }
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMRunningStatus cmdlet."
    }
}
Export-ModuleMember -Function Get-VMRunningStatus

Function Invoke-EsxCommand {
    <#
        .SYNOPSIS
        Run a given command on an ESXi host

        .DESCRIPTION
        The Invoke-EsxCommand cmdlet runs a given command on a given ESXi host. If expected is
        not passed, then #exitstatus of 0 is considered as success

        .EXAMPLE
        Invoke-EsxCommand -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"

        .PARAMETER server
        The FQDN of the ESXi host.

        .PARAMETER user
        The username to authenticate to ESXi host.

        .PARAMETER pass
        The password to authenticate to ESXi host.

        .PARAMETER cmd
        The command to be exectued on the ESXi host.

        .PARAMETER expected
        The expected output to be compared against output returned from the command execution.
        #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cmd,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$expected
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Invoke-EsxCommand cmdlet."
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
        $session = New-SSHSession -ComputerName $server -Credential $Cred -Force -WarningAction SilentlyContinue
        if ($session) {
            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to run command '$cmd' on server '$server'..."
            $commandOutput = Invoke-SSHCommand -Index $session.SessionId -Command $cmd -TimeOut 900
            if ($expected ) {
                if (($commandOutput.Output -match $expected)) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Command '$cmd' completed with  expected output on server '$server'."
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Failure. The `"$($expected)`" is not present in `"$($commandOutput.Output)`" output"
                }
            } elseif ($commandOutput.exitStatus -EQ 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "Success. The command completed successfully."
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Failure. The command could not be run."
            }
            Remove-SSHSession -Index $session.SessionId | Out-Null
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Invoke-EsxCommand cmdlet."
    }
}
Export-ModuleMember -Function Invoke-EsxCommand

Function Get-SSHEnabledStatus {
    <#
        .SYNOPSIS
        Check if SSH is enabled on the given host

        .DESCRIPTION
        The Get-SSHEnabledStatus cmdlet creates a new SSH session to the given host to see if SSH is enabled. It returns true if SSH enabled.

        .EXAMPLE
        Get-SSHEnabledStatus -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1!
        In the above example, it tries to ssh to ESXi host and if success, returns true.

        .PARAMETER server
        The FQDN of the ESXi host.

        .PARAMETER user
        The username to authenticate to ESXi host.

        .PARAMETER pass
        The password to authenticate to ESXi host.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-SSHEnabledStatus cmdlet."
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to open an SSH connection to server '$server'..."
            $session = New-SSHSession -ComputerName $server -Credential $Cred -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($session) {
                Write-PowerManagementLogMessage -Type INFO -Message "SSH is enabled on '$server'."
                Remove-SSHSession -Index $session.SessionId | Out-Null
                return $True
            } else {
                Write-PowerManagementLogMessage -Type INFO -Message "SSH is not enabled '$server'."
                return $False
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with server '$server'. Check the power state of the server."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-SSHEnabledStatus cmdlet"
    }
}
Export-ModuleMember -Function Get-SSHEnabledStatus

Function Test-VsanHealth {
    <#
        .SYNOPSIS
        Check the vSAN cluster health

        .DESCRIPTION
        The Test-VsanHealth cmdlet checks the state of the vSAN cluster health

        .EXAMPLE
        Test-VsanHealth -cluster sfo-m01-cl01 -server sfo-m01-vc01 -user administrator@vsphere.local -pass VMw@re1!
        This example connects to a vCenter Server and checks the state of the vSAN cluster health.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the vSAN cluster on which health has to be checked.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Starting the call to the Test-VsanHealth cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connecting to '$server'..."
            if ($DefaultVIServers) {
                if ($DefaultVIServers.Name -notcontains $server) {
                    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Already connected to server '$server'."
                }
            } else {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connected to server '$server' and attempting to check the vSAN cluster health..."
                $count = 1
                $flag = 0
                While ($count -lt 5) {
                    Try {
                        $Error.clear()
                        Get-VsanView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -ErrorAction stop | Out-Null
                        if (-Not $Error) {
                            $flag = 1
                            Break
                        }
                    } Catch {
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] The vSAN health service is yet to come up, please wait ..."
                        Start-Sleep -s 60
                        $count += 1
                    }
                }

                if (-Not $flag) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot run the Test-VsanHealth cmdlet because the vSAN health service is not running."
                } else {
                    Start-Sleep -s 60
                    $vchs = Get-VsanView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
                    $cluster_view = (Get-Cluster -Name $cluster).ExtensionData.MoRef
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
                        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] The vSAN health status for $cluster is good."
                        return 0
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] The vSAN health status for $cluster is bad."
                        return 1
                    }
                    #Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Completed the call to the Test-VsanHealth cmdlet."
    }
}
Export-ModuleMember -Function Test-VsanHealth

Function Test-VsanObjectResync {
    <#
        .SYNOPSIS
        Check object sync for vSAN cluster

        .DESCRIPTION
        The Test-VsanObjectResync cmdlet checks for resyncing of objects on the vSAN cluster

        .EXAMPLE
        Test-VsanObjectResync -cluster sfo-m01-cl01 -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example connects to a vCenter Server and checks the status of object syncing for the vSAN cluster

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the vSAN cluster on which object resynchronization status has to be checked.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Starting the call to the Test-VsanObjectResync cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connecting to '$server'..."
            if ($DefaultVIServers) {
                if ($DefaultVIServers.Name -notcontains $server) {
                    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Already connected to server '$server'."
                }
            } else {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            }
            if ($DefaultVIServer.Name -contains $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Connected to server '$server' and attempting to check the resynchronization status... "
                $noResyncingObjects = Get-VsanResyncingComponent -Server $server -Cluster $cluster -ErrorAction Ignore
                Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Number of resynchronizing objects: $noResyncingObjects."
                if ($noResyncingObjects.count -EQ 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] No resynchronizing objects."
                    return 0
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Resynchronizing objects in progress..."
                    return 1
                }
                # Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "[$cluster] Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "[$cluster] Completed the call to the Test-VsanObjectResync cmdlet."
    }
}
Export-ModuleMember -Function Test-VsanObjectResync

Function Get-VMsWithPowerStatus {
    <#
        .SYNOPSIS
        Get a list of virtual machines that are in a specified power state.

        .DESCRIPTION
        The Get-VMsWithPowerStatus cmdlet returns a list of virtual machines that are in a specified power state on a specified vCenter Server or ESXi host.

        .EXAMPLE
        Get-VMsWithPowerStatus -server sfo01-m01-esx01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon"
        This example connects to an ESXi host and returns the list of powered-on virtual machines.

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon" -pattern "sfo-wsa01" -exactmatch
        This example connects to a vCenter Server instance and returns a powered-on VM with name sfo-wsa01.

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon" -pattern "vcls"
        This example connects to a vCenter Server instance and returns the list of powered-on vCLS virtual machines.

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon" -pattern "vcls" -silence
        This example connects to a vCenter Server instance and returns the list of powered-on vCLS virtual machines
        without log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER powerstate
        The powerstate of the virtual machines. The values can be one amongst ("poweredon","poweredoff").

        .PARAMETER pattern
        The pattern to match virtual machine names.

        .PARAMETER exactMatch
        The switch to match exact virtual machine name.

        .PARAMETER silence
        The switch to supress selected log messages.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("poweredon", "poweredoff")] [String]$powerState,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pattern = $null ,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$exactMatch,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$silence
    )

    $pass = Get-Password -User $user -Password $pass

    Try {

        if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMsWithPowerStatus cmdlet." }
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..." }
            if ($DefaultVIServers) {
                if ($DefaultVIServers.Name -notcontains $server) {
                    #Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                } else {
                    if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Already connected to server '$server'." }
                }
            } else {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            }
            if ($DefaultVIServers.Name -contains $server) {
                Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
                if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to get the list of virtual machines..." }
                if ($pattern) {
                    if ($PSBoundParameters.ContainsKey('exactMatch') ) {
                        $noOfVMs = Get-VM -Server $server | Where-Object Name -EQ $pattern | Where-Object PowerState -EQ $powerState
                    } else {
                        $noOfVMs = Get-VM -Server $server | Where-Object Name -Match $pattern | Where-Object PowerState -EQ $powerState
                    }
                } else {
                    $noOfVMs = Get-VM -Server $server | Where-Object PowerState -EQ $powerState
                }
                if ($noOfVMs.count -EQ 0) {
                    if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "No virtual machines in the $powerState state." }
                } else {
                    $noOfVMsString = $noOfVMs -join ","
                    if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "The virtual machines in the $powerState state are: $noOfVMsString" }
                }
                # Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                Return $noOfVMs
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMsWithPowerStatus cmdlet." }
    }
}
Export-ModuleMember -Function Get-VMsWithPowerStatus

Function Get-VamiServiceStatus {
    <#
        .SYNOPSIS
        Get the status of the service on a given vCenter Server

        .DESCRIPTION
        The Get-VamiServiceStatus cmdlet gets the current status of the service on a given vCenter Server. The status can be STARTED/STOPPED

        .EXAMPLE
        Get-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -service wcp
        This example connects to a vCenter Server instance and returns the wcp service status.

        Get-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -nolog
        This example connects to a vCenter Server instance and returns the wcp service status without log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER nolog
        The switch to supress selected log messages.

        .PARAMETER service
        The name of the service. The values can be one amongst ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$nolog,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VAMIServiceStatus cmdlet."
        }
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            if (-Not $nolog) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            $retries = 20
            $flag = 0
            While ($retries) {
                Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
                if ($DefaultCisServers.Name -EQ $server) {
                    $flag = 1
                    break
                }
                Start-Sleep -s 60
                $retries -= 1
                if (-Not $nolog) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to the vSphere Automation API endpoint might take some time. Please wait."
                }
            }
            if ($flag) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service, 0)
                return $serviceStatus.state
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Testing the connection to server '$server' has failed. Check your details and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VAMIServiceStatus cmdlet."
        }
    }
}
Export-ModuleMember -Function Get-VAMIServiceStatus

Function Set-VamiServiceStatus {
    <#
        .SYNOPSIS
        Start/Stop/Restart a specified management appliance service on a specified vCenter Server instance.

        .DESCRIPTION
        The Set-VamiServiceStatus cmdlet starts/stops/restarts a specified management appliance service on a specified vCenter Server instance.

        .EXAMPLE
        Set-VamiServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -service wcp -state "start"
        This example connects to a vCenter Server instance and starts the wcp service.

        Set-VamiServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -nolog -state "restart"
        This example connects to a vCenter Server instance and restarts the wcp service without log messages in the output.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER state
        The state of the servcie. The values can be one amongst ("start", "stop", "restart").

        .PARAMETER nolog
        The switch to supress selected log messages.

        .PARAMETER service
        The name of the service. The values can be one amongst ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").

    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("start", "stop", "restart")] [String]$state,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$nolog,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VamiServiceStatus cmdlet."
        }
        # TODO check if 443 is the default communication port
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            if (-Not $nolog) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            $retries = 20
            $flag = 0
            While ($retries) {
                Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
                if ($DefaultCisServers.Name -EQ $server) {
                    $flag = 1
                    break
                }
                Start-Sleep -s 60
                $retries -= 1
                if (-Not $nolog) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to the vSphere Automation API endpoint might take some time. Please wait."
                }
            }
            if ($flag) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                if ($state -EQ "start") {
                    $vMonAPI.Start($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if ($serviceStatus.state -EQ "STARTED") {
                        if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Service '$service' is successfully started."
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not start service '$service'."
                    }
                } elseif ($state -EQ "stop") {
                    $vMonAPI.Stop($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if ($serviceStatus.state -EQ "STOPPED") {
                        if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Service '$service' is successfully stopped."
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not stop service '$service'."
                    }
                } else {
                    $vMonAPI.ReStart($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if ($serviceStatus.state -EQ "STARTED") {
                        if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Service '$service' is successfully restarted."
                        }
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Could not restart service '$service'."
                    }
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Testing the connection to server '$server' has failed. Check your details and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VamiServiceStatus cmdlet."
        }
    }
}
Export-ModuleMember -Function Set-VamiServiceStatus

Function Set-VsphereHA {
    <#
        .SYNOPSIS
        Set vSphere High Availability

        .DESCRIPTION
        Set vSphere High Availability to enabled or disabled

        .EXAMPLE
        Set-VsphereHA -server $server -user $user -pass $pass -cluster $cluster -enable
        This example sets vSphere High Availability to enabled/active

        Set-VsphereHA -server $server -user $user -pass $pass -cluster $cluster -disable
        This example sets vSphere High Availability to disabled/stopped

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER enableHA
        The switch to enable vSphere High Availability.

        .PARAMETER disableHA
        The switch to disable vSphere High Availability.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster,
        [Parameter (Mandatory = $true, ParameterSetName = "enable")] [Switch] $enableHA,
        [Parameter (Mandatory = $true, ParameterSetName = "disable")] [Switch] $disableHA
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VsphereHA cmdlet."
        if ($(Test-EndpointConnection -server $server -Port 443)) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'... ..."
                $retryCount = 0
                $completed = $false
                $SecondsDelay = 10
                $Retries = 60
                if ($enableHA) {
                    if ($(Get-Cluster -Name $cluster).HAEnabled) {
                        Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability is already enabled on the vSAN cluster. "
                        return $true
                    } else {
                        Write-PowerManagementLogMessage -Type INFO -Message "Enabling vSphere High Availability for cluster '$cluster'..."
                        Set-Cluster -Server $server -Cluster $cluster -HAEnabled:$true -Confirm:$false | Out-Null
                        While (-Not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress."
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep -s 5
                            $runningTasks = Get-Task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep -s $SecondsDelay
                                continue
                            } else {
                                $completed = $true
                                if ($(Get-Cluster -Name $cluster).HAEnabled) {
                                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability for cluster '$cluster' changed to 'Enabled'."
                                    return $true
                                } else {
                                    Write-PowerManagementLogMessage -Type WARNING -Message "Failed to set vSphere High Availability for cluster '$cluster' to 'Enabled'."
                                    return $false
                                }
                            }
                        }
                    }
                }
                if ($disableHA) {
                    if (!$(Get-Cluster -Name $cluster).HAEnabled) {
                        Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability is already disabled on the vSAN cluster. "
                        return $true
                    } else {
                        Write-PowerManagementLogMessage -Type INFO -Message "Disabling vSphere High Availability for cluster '$cluster'."
                        Set-Cluster -Server $server -Cluster $cluster -HAEnabled:$false -Confirm:$false | Out-Null
                        While (-Not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress."
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep -s 5
                            $runningTasks = Get-Task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep -s $SecondsDelay
                                continue
                            } else {
                                $completed = $true
                                if (!$(Get-Cluster -Name $cluster).HAEnabled) {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Disabled vSphere High Availability for cluster '$cluster'."
                                    return $true
                                } else {
                                    Write-PowerManagementLogMessage -Type WARNING -Message "Failed to disable vSphere High Availability for cluster '$cluster'."
                                    return $false
                                }
                            }
                        }
                    }
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VsphereHA cmdlet."
    }

}
Export-ModuleMember -Function Set-VsphereHA

Function Get-DrsAutomationLevel {
    <#
        .SYNOPSIS
        Get the DRS setting configured on the server for a given cluster

        .DESCRIPTION
        Get-DrsAutomationLevel method returns the DRS setting configured on the server for a given cluster

        .EXAMPLE
        Get-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -cluster sfo-m01-cl01
        This example connects to the management vcenter server and returns the drs settings configured on the management cluster

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-DrsAutomationLevel cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'... ..."
                $ClusterData = Get-Cluster -Name $cluster
                if ($ClusterData.DrsEnabled) {
                    $clsdrsvalue = $ClusterData.DrsAutomationLevel
                    Write-PowerManagementLogMessage -Type INFO -Message "The cluster DRS value: $clsdrsvalue."
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere DRS is not enabled on the cluster $cluster."
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $clsdrsvalue
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-DrsAutomationLevel cmdlet."
    }

}
Export-ModuleMember -Function Get-DrsAutomationLevel

Function Set-Retreatmode {
    <#
        .SYNOPSIS
        Enable/Disable retreat mode for vSphere Cluster

        .DESCRIPTION
        The Set-Retreatmode cmdlet enables or disables retreat mode for the vSphere Cluster virtual machines

        .EXAMPLE
        Set-Retreatmode -server $server -user $user -pass $pass -cluster $cluster -mode enable
        This example places the vSphere Cluster virtual machines (vCLS) in the retreat mode

        .EXAMPLE
        Set-Retreatmode -server $server -user $user -pass $pass -cluster $cluster -mode disable
        This example takes places the vSphere Cluster virtual machines (vCLS) out of retreat mode

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER mode
        The name of the retreat mode. The value is one amongst ("enable", "disable").
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("enable", "disable")] [String] $mode
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-Retreatmode cmdlet."
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                $cluster_id = Get-Cluster -Name $cluster | Select-Object -Property Id
                $domainOut = $cluster_id.Id -match 'domain-c.*'
                $domain_id = $Matches[0]
                $advanced_setting = "config.vcls.clusters.$domain_id.enabled"
                if (Get-AdvancedSetting -Entity $server -Name $advanced_setting) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is present."
                    if ($mode -EQ 'enable') {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'false' -Confirm:$false | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false."
                    } else {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'true' -Confirm:$false | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true."
                    }
                } else {
                    if ($mode -EQ 'enable') {
                        New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'false' -Confirm:$false | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false."
                    } else {
                        New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'true' -Confirm:$false | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true."
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-Retreatmode cmdlet."
    }

}
Export-ModuleMember -Function Set-Retreatmode

Function Get-VMToClusterMapping {
    <#
        .SYNOPSIS
        Get a list of all virtual Machines that are running in a specified cluster.

        .DESCRIPTION
        The Get-VMToClusterMapping cmdlet returns a list of all virtual machines that are running on a specified cluster.

        .EXAMPLE
        Get-VMToClusterMapping -server $server -user $user -pass $pass -cluster $cluster -folder "VCLS"
        This example returns all virtual machines in folder VCLS on a cluster $cluster.

        Get-VMToClusterMapping -server $server -user $user -pass $pass -cluster $cluster -folder "VCLS" -powerstate "poweredon"
        This example returns only the powered-on virtual machines in folder VCLS on a cluster $cluster.

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster.

        .PARAMETER folder
        The name of the folder to search for virtual machines.

        .PARAMETER silence
        The switch to supress selected log messages.

        .PARAMETER powerstate
        The powerstate of the virtual machines. The values can be one amongst ("poweredon","poweredoff").

    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]] $cluster,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $folder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch] $silence,
        [Parameter (Mandatory = $false)] [ValidateSet("poweredon", "poweredoff")] [String] $powerState

    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMToClusterMapping cmdlet." }
        $checkServer = (Test-EndpointConnection -server $server -Port 443)
        if ($checkServer) {
            if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..." }
            if ($DefaultVIServers) {
                #Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..." }
                foreach ($clus in $cluster) {
                    if ($powerState) {
                        $VMs += Get-VM -Location $clus | Where-Object { (Get-VM -Location $folder) -contains $_ } | Where-Object PowerState -EQ $powerState
                    } else {
                        $VMs += Get-VM -Location $clus | Where-Object { (Get-VM -Location $folder) -contains $_ }
                    }
                }
                $clustersstring = $cluster -join ","
                if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "The list of VMs on cluster $clustersstring is $VMs" }
                #Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $VMs

            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        if (-Not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMToClusterMapping cmdlet." }
    }

}
Export-ModuleMember -Function Get-VMToClusterMapping

Function Wait-ForStableNsxtClusterStatus {
    <#
        .SYNOPSIS
        Fetch cluster status of NSX Manager

        .DESCRIPTION
        The Wait-ForStableNsxtClusterStatus cmdlet fetches the cluster status of NSX manager after a restart

        .EXAMPLE
        Wait-ForStableNsxtClusterStatus -server sfo-m01-nsx01.sfo.rainpole.io -user admin -pass VMw@re1!VMw@re1!
        This example gets the cluster status of the sfo-m01-nsx01.sfo.rainpole.io NSX Management Cluster

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Wait-ForStableNsxtClusterStatus cmdlet."
        Write-PowerManagementLogMessage -Type INFO -Message "Waiting the cluster to become 'STABLE' for NSX Manager '$server'... This could take up to 20 min."
        # Create NSX-T header
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $pass))) # Create Basic Authentication Encoded Credentials
        $headers = @{"Accept" = "application/json" }
        $headers.Add("Authorization", "Basic $base64AuthInfo")
        $uri = "https://$server/api/v1/cluster/status"
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
                Write-PowerManagementLogMessage -Type WARNING -Message "Request to '$uri' failed after $retryCount attempts."
                return $false
            }
            $retryCount++
            # Retry connection if NSX Manager is not online
            Try {
                $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ContentType application/json -TimeoutSec 60
            } Catch {
                Write-PowerManagementLogMessage -Type INFO -Message "Could not connect to NSX Manager '$server'! Sleeping $($SecondsDelay * $aditionalWaitMultiplier) seconds before next attempt."
                Start-Sleep -s $($SecondsDelay * $aditionalWaitMultiplier)
                continue
            }
            $successfulConnections++
            if ($response.mgmt_cluster_status.status -ne 'STABLE') {
                Write-PowerManagementLogMessage -Type INFO -Message "Expecting NSX Manager cluster state 'STABLE', present state: $($response.mgmt_cluster_status.status)"
                # Add longer sleep during fiest several attempts to avoid locking the NSX-T account just after power-on
                if ($successfulConnections -lt 4) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for $($SecondsDelay * $aditionalWaitMultiplier) seconds before next check..."
                    Start-Sleep -s $($SecondsDelay * $aditionalWaitMultiplier)
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for $SecondsDelay seconds until the next check..."
                    Start-Sleep -s $SecondsDelay
                }
            } else {
                $completed = $true
                Write-PowerManagementLogMessage -Type INFO -Message "The state of the NSX Manager cluster '$server' is 'STABLE'."
                return $true
            }
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Wait-ForStableNsxtClusterStatus cmdlet."
    }
}
Export-ModuleMember -Function Wait-ForStableNsxtClusterStatus

Function Get-EdgeNodeFromNSXManager {
    <#
        .SYNOPSIS
        This method reads edge node virtual machine names from NSX manager

        .DESCRIPTION
        The Get-EdgeNodeFromNSXManager used to read edge node virtual machine names from NSX manager

        .EXAMPLE
        Get-EdgeNodeFromNSXManager -server $server -user $user -pass $pass
        This example returns list of edge nodes virtual machines name

        .EXAMPLE
        Get-EdgeNodeFromNSXManager -server $server -user $user -pass $pass -VCfqdn $VCfqdn
        This example returns list of edge nodes virtual machines name from a given virtual center only

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.

        .PARAMETER VCfqdn
        The FQDN of the vCenter Server.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $VCfqdn
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-EdgeNodeFromNSXManager cmdlet."
        if ( Test-EndpointConnection -server $server -Port 443 ) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultNSXTServers) {
                if ($DefaultNsxTServers.Name -ne $server -or $DefaultNSXTServers.IsConnected -eq $false) {
                    Disconnect-NsxtServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                    Connect-NsxtServer -Server $server -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "Already connected to server '$server'..."
                }
            } else {
                Connect-NsxtServer -Server $server -User $user -Password $pass | Out-Null
            }
            $edge_nodes_list = @()
            if ($DefaultNsxTServers.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                #get transport nodes info
                $transport_nodes_var = Get-NsxtService com.vmware.nsx.transport_nodes
                $transport_nodes_list = $transport_nodes_var.list().results
                #get compute managers info
                $compute_manager_var = Get-NsxtService com.vmware.nsx.fabric.compute_managers
                $compute_manager_list = $compute_manager_var.list().results
                foreach ($compute_resource in $compute_manager_list) {
                    if ($compute_resource.display_name -match $VCfqdn) {
                        $compute_resource_id = $compute_resource.id
                    }
                }
                foreach ($resource in $transport_nodes_list) {
                    if ($resource.node_deployment_info.resource_type -EQ "EdgeNode") {
                        if ($resource.node_deployment_info.deployment_config.GetStruct('vm_deployment_config').GetFieldValue("vc_id") -match $compute_resource_id) {
                            [Array]$edge_nodes_list += $resource.display_name
                        }
                    }
                }
                # Disconnect-NsxtServer * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $edge_nodes_list
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details."
            }

        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-EdgeNodeFromNSXManager cmdlet."
    }
}
Export-ModuleMember -Function Get-EdgeNodeFromNSXManager

Function Get-NSXTComputeManagers {
    <#
        .SYNOPSIS
        Get the list of compute managers connected to a specified NSX Manager.

        .DESCRIPTION
        The Get-NSXTComputeManagers cmdlet returns the list of compute managers connected to a specified NSX Manager.

        .EXAMPLE
        Get-NSXTComputeManagers -server $server -user $user -pass $pass
        This example returns the list of compute managers mapped to NSX Manager $server.

        .PARAMETER server
        The FQDN of the NSX Manager.

        .PARAMETER user
        The username to authenticate to NSX Manager.

        .PARAMETER pass
        The password to authenticate to NSX Manager.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-NSXTComputeManagers cmdlet."
        if ( Test-EndpointConnection -server $server -port 443 ) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultNSXTServers) {
                if ($DefaultNsxTServers.Name -ne $server -or $DefaultNSXTServers.IsConnected -eq $false) {
                    Disconnect-NsxtServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                    Connect-NsxtServer -Server $server -User $user -Password $pass | Out-Null
                } else {
                    Write-PowerManagementLogMessage -Type INFO -Message "Already connected to server '$server'..."
                }
            } else {
                Connect-NsxtServer -Server $server -User $user -Password $pass | Out-Null
            }
            if ($DefaultNsxTServers.Name -EQ $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                # Get compute managers info
                $compute_manager_var = Get-NsxtService com.vmware.nsx.fabric.compute_managers
                $compute_manager_list = $compute_manager_var.list().results.server
                # Disconnect-NsxtServer * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $compute_manager_list
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details."
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again."
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-NSXTComputeManagers cmdlet."
    }
}
Export-ModuleMember -Function Get-NSXTComputeManagers

Function Get-TanzuEnabledClusterStatus {
    <#
        .SYNOPSIS
        This method checks if the Cluster is Tanzu enabled

        .DESCRIPTION
        The Get-TanzuEnabledClusterStatus used to check if the given Cluster is Tanzu enabled

        .EXAMPLE
        Get-TanzuEnabledClusterStatus -server $server -user $user -pass $pass -cluster $cluster
        This example returns True if the given cluster is Tanzu enabled else false

        .PARAMETER server
        The FQDN of the vCenter Server.

        .PARAMETER user
        The username to authenticate to vCenter Server.

        .PARAMETER pass
        The password to authenticate to vCenter Server.

        .PARAMETER cluster
        The name of the cluster.
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster
    )

    $pass = Get-Password -User $user -Password $pass

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-TanzuEnabledClusterStatus cmdlet."
        if ( Test-EndpointConnection -server $server -Port 443 ) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -EQ $server) {
                $out = Get-WMCluster -Cluster $cluster -Server $server -ErrorVariable ErrorMsg -ErrorAction SilentlyContinue
                if ($out.count -gt 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere with Tanzu is enabled."
                    return $True
                } elseif (([string]$ErrorMsg -match "does not have Workloads enabled") -or ([string]::IsNullOrEmpty($ErrorMsg))) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere with Tanzu is not enabled."
                    return $False
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot fetch information related to vSphere with Tanzu. ERROR message from 'get-wmcluster' command: '$ErrorMsg'"
                }
            } else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details."
            }

        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again"
        }
    } Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-TanzuEnabledClusterStatus cmdlet."
    }
}
Export-ModuleMember -Function Get-TanzuEnabledClusterStatus

######### Start Useful Script Functions ##########
Function Write-PowerManagementLogMessage {
    <#
    .SYNOPSIS
    This cmdlet is used for logging messages.

    .DESCRIPTION
    This cmdlet is used for logging messages on the console.

    .EXAMPLE
    Write-PowerManagementLogMessage -Type ERROR -message "Error message"
    Logs as a error message and uses the assigned color.

    Write-PowerManagementLogMessage -Type WARNING -message "Warning message"
    Logs as a warning message and uses the assigned color.

    Write-PowerManagementLogMessage -Type INFO -message "Info message"
    Logs as a info message and uses the assigned color.

    Write-PowerManagementLogMessage -Type EXCEPTION -message "Exception message"
    Logs as an exception message and uses the assigned color.

    Write-PowerManagementLogMessage -Type INFO -message "Exception message" -colour Cyan
    Logs as an exception message and uses the the specified color.

    .PARAMETER Message
    The message to be logged on the console.

    .PARAMETER Type
    The type of the log message. The value can be one amongst ("INFO", "ERROR", "WARNING", "EXCEPTION").

    .PARAMETER Colour
    The colour of the log message. This will override the default color for the log type.

    .PARAMETER Skipnewline
    This is used to skip new line while logging message.
    #>
    Param (
        [Parameter (Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter (Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION", "DEBUG")] [String]$Type,
        [Parameter (Mandatory = $false)] [String]$Colour,
        [Parameter (Mandatory = $false)] [String]$SkipnewLine
    )
    $ErrorActionPreference = 'Stop'

    if (!$colour) {
        switch ($type) {
            "INFO" {
                $colour = "Green"
            }
            "WARNING" {
                $colour = "Yellow"
            }
            "ERROR" {
                $colour = "Red"
            }
            "EXCEPTION" {
                $colour = "Magenta"
            }
            "DEBUG" {
                $colour = "Cyan"
            }
            default {
                $colour = "White"
            }
        }
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    # Log debug messages but do not print them on the console if the debug flag is not set
    if ($type -match "DEBUG") {
        if ($Debug) {
            Write-Host -NoNewline -ForegroundColor White " [$timeStamp]"
            if ($skipNewLine) {
                Write-Host -NoNewline -ForegroundColor $colour " $type $message"
            } else {
                Write-Host -ForegroundColor $colour " $type $message"
            }
        }
        $logContent = '[' + $timeStamp + '] ' + $type + ' ' + $message
        Add-Content -Path $logFile $logContent
        return
    }

    Write-Host -NoNewline -ForegroundColor White " [$timeStamp]"
    if ($skipNewLine) {
        Write-Host -NoNewline -ForegroundColor $colour " $type $message"
    } else {
        Write-Host -ForegroundColor $colour " $type $message"
    }

    $logContent = '[' + $timeStamp + '] ' + $type + ' ' + $message
    Add-Content -Path $logFile $logContent

    if ($type -match "ERROR") {
        $erroLogFile = $logFile -replace '.log$', '_Error.log'
        Add-Content -Path $erroLogFile $logContent
        Write-Error -Message $Message
    }
}
Export-ModuleMember -Function Write-PowerManagementLogMessage

Function Debug-CatchWriterForPowerManagement {
    Param (
        [Parameter (Mandatory = $true)] [PSObject]$object
    )
    $ErrorActionPreference = 'Stop'
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-PowerManagementLogMessage -Message " ERROR at Script Line $lineNumber" -Colour Red
    Write-PowerManagementLogMessage -Message " Relevant Command: $lineText" -Colour Red
    Write-PowerManagementLogMessage -Message " ERROR Message: $errorMessage" -Colour Red
    Write-Error -Message $errorMessage
}

######### End Useful Script Functions ##########
