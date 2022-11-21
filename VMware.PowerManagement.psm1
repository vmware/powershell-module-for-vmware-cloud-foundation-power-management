# PowerShell module for Power Management of VMware Cloud Foundation

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This PowerShell module should be considered entirely experimental. It is still in development & not tested beyond
# lab scenarios. It is recommended you don't use it for any production environment without testing extensively!

# Enable communication with self-signed certificates when using Powershell Core if you require all communications to be secure
# and do not wish to allow communication with self-signed certificates remove lines 16-40 before importing the module.

# Enable self-signed certificates 
if ($PSEdition -eq 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -eq 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertificatePolicy').Type) {
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
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$timeout,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$noWait,
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$pattern
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Stop-CloudComponent cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    $nodes_string = $nodes -join "; "
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to shut down nodes '$nodes_string'..."
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -eq $node }) {
                                $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vm_obj.State -eq 'NotRunning') {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' is already powered off." -Colour Cyan
                                    Continue
                                }
                                Write-PowerManagementLogMessage -Type INFO -Message "Attempting to shut down node '$node'..."
                                if ($PsBoundParameters.ContainsKey("noWait")) {
                                    Stop-VM -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                }
                                else {
                                    Stop-VMGuest -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                    Write-PowerManagementLogMessage -Type INFO -Message "Waiting for node '$node' to shut down..."
                                    $sleepTime = 5
                                    While (($vm_obj.State -ne 'NotRunning') -and ($count -le $timeout)) {
                                        Start-Sleep -Seconds $sleepTime
                                        $count = $count + $sleepTime
                                        $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                    }
                                    if ($count -gt $timeout) {
                                        Write-PowerManagementLogMessage -Type ERROR -Message "Node '$node' did not shut down within the expected timeout $timeout value."	-Colour Red			
                                    }
                                    else {
                                        Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' has shut down successfully." -Colour Green
                                    }
                                }
                            }
                            else {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to find node '$node' in the inventory of server '$server'." -Colour Red
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -eq "Pattern") {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to shut down nodes with pattern '$pattern'..."
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $server
                    }
                    else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            if ($vm_obj.State -eq 'NotRunning') {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' is already powered off." -Colour Cyan
                                Continue
                            }
                            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to shut down node '$($node.name)'..."
                            if ($PsBoundParameters.ContainsKey("noWait")) {
                                Stop-VM -Server $server -VM $node.Name -Confirm:$false | Out-Null
                            }
                            else {
                                Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server | Stop-VMGuest -Confirm:$false | Out-Null
                                $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                                $sleepTime = 1
                                While (($vm_obj.State -ne 'NotRunning') -and ($count -le $timeout)) {
                                    Start-Sleep -Seconds $sleepTime
                                    $count = $count + $sleepTime
                                    $vm_obj = Get-VMGuest -VM $node.Name | Where-Object VmUid -match $server
                                }
                                if ($count -gt $timeout) {
                                    Write-PowerManagementLogMessage -Type ERROR -Message "Node '$($node.name)' did not shut down within the expected timeout $timeout value."	-Colour Red
                                }
                                else {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' has shut down successfully." -Colour Green
                                }
                            }
                        }
                    }
                    elseif ($pattern) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "No nodes match pattern '$pattern' on host '$server'." -Colour Cyan
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Stop-CloudComponent cmdlet." -Colour Yellow
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
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$timeout,
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$pattern
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Start-CloudComponent cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    $nodes_string = $nodes -join "; "
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to start nodes '$nodes_string'."
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count = 0
                            if (Get-VM | Where-Object { $_.Name -eq $node }) {
                                $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vm_obj.State -eq 'Running') {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' is already in powered on." -Colour Green
                                    Continue
                                }
                                Write-PowerManagementLogMessage -Type INFO -Message "Attempting to start up node '$node'..."
                                Start-VM -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                Start-Sleep -Seconds 5
                                $sleepTime = 10
                                Write-PowerManagementLogMessage -Type INFO -Message "Waiting for node '$node' to start up..."
                                While (($vm_obj.State -ne 'Running') -and ($count -le $timeout)) {
                                    Start-Sleep -Seconds $sleepTime
                                    $count = $count + $sleepTime
                                    $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                }
                                if ($count -gt $timeout) {
                                    Write-PowerManagementLogMessage -Type ERROR -Message "Node '$node' did not start up within the expected timeout $timeout value." -Colour Red
                                    Break 			
                                } 
                                else {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Node '$node' has started successfully." -Colour Green
                                }
                            }
                            else {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot find '$node' in the inventory of host '$server'." -Colour Red
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -eq "Pattern") {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connected to host '$server' and attempting to start up nodes with pattern '$pattern'..."
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $server
                    }
                    else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count = 0
                            $vm_obj = Get-VMGuest -server $server -VM $node.Name | Where-Object VmUid -match $server
                            if ($vm_obj.State -eq 'Running') {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' is already powered on." -Colour Green
                                Continue
                            }

                            Start-VM -VM $node.Name | Out-Null
                            $sleepTime = 1
                            $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to start up node '$($node.name)'..."
                            While (($vm_obj.State -ne 'Running') -AND ($count -le $timeout)) {
                                Start-Sleep -Seconds $sleepTime
                                $count = $count + $sleepTime
                                $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            }
                            if ($count -gt $timeout) {
                                Write-PowerManagementLogMessage -Type ERROR -Message "Node '$($node.name)' did not start up within the expected timeout $timeout value."	-Colour Red
                            }
                            else {
                                Write-PowerManagementLogMessage -Type INFO -Message "Node '$($node.name)' has started successfully." -Colour Green
                            }
                        }
                    }
                    elseif ($pattern) {
                        Write-PowerManagementLogMessage -Type WARNING -Message "No nodes match pattern '$pattern' on host '$server'." -Colour Cyan
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to host '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Start-CloudComponent cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Start-CloudComponent

Function Set-MaintenanceMode {
    <#
        .SYNOPSIS
        Enable or disable maintenance mode on an ESXi host
    
        .DESCRIPTION
        The Set-MaintenanceMode cmdlet enables or disables maintenance mode on an ESXi host 
    
        .EXAMPLE
        Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state ENABLE
        This example places an ESXi host in maintenance mode

        .EXAMPLE
        Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state DISABLE
        This example takes an ESXi host out of maintenance mode
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("ENABLE", "DISABLE")] [String]$state
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-MaintenanceMode cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state maintenance mode..."
                $hostStatus = (Get-VMHost -Server $server)
                if ($state -eq "ENABLE") {
                    if ($hostStatus.ConnectionState -eq "Connected") {
                        Write-PowerManagementLogMessage -type INFO -Message "Attempting to enter maintenance mode for '$server'..."
                        Get-View -Server $server -ViewType HostSystem -Filter @{"Name" = $server } | Where-Object { !$_.Runtime.InMaintenanceMode } | ForEach-Object { $_.EnterMaintenanceMode(0, $false, (new-object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode = (new-object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction = [VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction }) })) } | Out-Null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has entered maintenance mode successfully." -Colour Green
                        }
                        else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' did not enter maintenance mode. Check your environment and try again." -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already entered maintenance mode." -Colour Green
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected." -Colour Red
                    }
                }

                elseif ($state -eq "DISABLE") {
                    if ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-PowerManagementLogMessage -type INFO -Message "Attempting to exit maintenance mode for '$server'..."
                        $task = Set-VMHost -VMHost $server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Wait-Task $task | out-null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Connected") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has exited maintenance mode successfully." -Colour Green
                        }
                        else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "The host '$server' did not exit maintenance mode. Check your environment and try again." -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Connected") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already exited maintenance mode" -Colour Yellow
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected." -Colour Red
                    }
                }
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    } 
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    } 
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-MaintenanceMode cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Set-MaintenanceMode


Function Get-MaintenanceMode {
    <#
        .SYNOPSIS
        Get maintenance mode status on an ESXi host

        .DESCRIPTION
        The Get-MaintenanceMode cmdlet gets maintenance mode status on an ESXi host

        .EXAMPLE
        Get-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1!
        This example returns ESXi host maintenance mode status
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-MaintenanceMode cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state maintenance mode..."
                $hostStatus = (Get-VMHost -Server $server)
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                return $hostStatus.ConnectionState
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-MaintenanceMode cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-MaintenanceMode


Function Get-HostStatus {
    <#
        .SYNOPSIS
        This is used to get ESXi host status [Up/Down]

        .DESCRIPTION
        The Get-HostStatus cmdlet checks if all hosts are up and out of maintainance mode after start,
        if status is passed as UP and TCP connection is not happening in case of DOWN status


        .EXAMPLE
        Get-HostStatus -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -status UP
        This example places an ESXi host in maintenance mode

        .EXAMPLE
        Get-HostStatus -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -status DOWN
        This example takes an ESXi host out of maintenance mode
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("UP", "DOWN")] [String]$status
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-HostStatus cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state maintenance mode..."
                $hostStatus = (Get-VMHost -Server $server)
                if ($state -eq "UP") {
                    if ($hostStatus.ConnectionState -eq "Connected") {
                        Write-PowerManagementLogMessage -type INFO -Message "Attempting to enter maintenance mode for '$server'..."
                        Get-View -Server $server -ViewType HostSystem -Filter @{"Name" = $server } | Where-Object { !$_.Runtime.InMaintenanceMode } | ForEach-Object { $_.EnterMaintenanceMode(0, $false, (new-object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode = (new-object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction = [VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction }) })) } | Out-Null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Maintenance") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has entered maintenance mode successfully." -Colour Green
                        }
                        else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' did not enter maintenance mode. Check your environment and try again." -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already entered maintenance mode." -Colour Green
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected." -Colour Red
                    }
                } else {
                    if ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-PowerManagementLogMessage -type INFO -Message "Attempting to exit maintenance mode for '$server'..."
                        $task = Set-VMHost -VMHost $server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Wait-Task $task | out-null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Connected") {
                            Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has exited maintenance mode successfully." -Colour Green
                        }
                        else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "The host '$server' did not exit maintenance mode. Check your environment and try again." -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Connected") {
                        Write-PowerManagementLogMessage -Type INFO -Message "Host '$server' has already exited maintenance mode" -Colour Yellow
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Host '$server' is not currently connected." -Colour Red
                    }
                }
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-HostStatus cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-HostStatus

Function Set-DrsAutomationLevel {
    <#
        .SYNOPSIS
        Set the DRS automation level
    
        .DESCRIPTION
        The Set-DrsAutomationLevel cmdlet sets the automation level of the cluster based on the setting provided 
    
        .EXAMPLE
        Set-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -level PartiallyAutomated
        Thi examples sets the DRS Automation level for the sfo-m01-cl01 cluster to Partially Automated
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled")] [String]$level
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-DrsAutomationLevel cmdlet." -Colour Yellow

        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $drsStatus = Get-Cluster -Name $cluster -ErrorAction SilentlyContinue
                if ($drsStatus) {
                    if ($drsStatus.DrsAutomationLevel -eq $level) {
                        Write-PowerManagementLogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$cluster' is already '$level'." -Colour Green
                    }
                    else {
                        $drsStatus = Set-Cluster -Cluster $cluster -DrsAutomationLevel $level -Confirm:$false 
                        if ($drsStatus.DrsAutomationLevel -eq $level) {
                            Write-PowerManagementLogMessage -Type INFO -Message "The vSphere DRS automation level for cluster '$cluster' has been set to '$level' successfully." -Colour Green
                        }
                        else {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Failed to set the vSphere DRS automation level for cluster '$cluster' to '$level'." -Colour Red
                        }
                    }
                    Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cluster '$cluster' not found on host '$server'. Check your environment and try again." -Colour Red
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    } 
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-DrsAutomationLevel cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Set-DrsAutomationLevel


Function Set-VsanClusterPowerStatus {
    <#
        .SYNOPSIS
        PowerOff or PowerOn the vSAN Cluster

        .DESCRIPTION
        The Set-VsanClusterPowerStatus cmdlet either PowerOff or PowerOn the vSAN Cluster

        .EXAMPLE
        Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOff
        This example poweroff the cluster sfo-m01-cl01

        Set-VsanClusterPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -PowerStatus clusterPoweredOn
        This example poweron the cluster sfo-m01-cl01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$clustername,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$mgmt,
        [Parameter (Mandatory = $true)] [ValidateSet("clusterPoweredOff", "clusterPoweredOn")] [String]$PowerStatus
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VsanClusterPowerStatus cmdlet." -Colour Yellow

        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {

                Import-Module VMware.VimAutomation.Storage
                $vsanClient = [VMware.VimAutomation.Storage.Interop.V1.Service.StorageServiceFactory]::StorageCoreService.ClientManager.GetClientByConnectionId($DefaultVIServer.Id)
                $vsanClusterPowerSystem = $vsanClient.VsanViewService.GetVsanViewById("VsanClusterPowerSystem-vsan-cluster-power-system")

                # Populate the needed spec:
                $spec = [VMware.Vsan.Views.PerformClusterPowerActionSpec]::new()

                $spec.powerOffReason = "VCF Automatic"
                $spec.targetPowerStatus = $PowerStatus

                $cluster = Get-Cluster $clustername


                $powerActionTask = $vsanClusterPowerSystem.PerformClusterPowerAction($cluster.ExtensionData.MoRef, $spec)
                $task = Get-Task -Id $powerActionTask
                $counter = 0
                $sleepTime = 10 # in seconds
                if (-not $mgmt) {
                    do
                    {
                        $task = Get-Task -Id $powerActionTask
                        if (-Not ($task.State -eq "Error")) {
                            Write-PowerManagementLogMessage -Type INFO -Message "$PowerStatus task is $($task.PercentComplete)% completed"
                        }
                        Start-Sleep $sleepTime
                        $counter += $sleepTime
                    } while($task.State -eq "Running" -and ($counter -lt 1800))

                    if ($task.State -eq "Error"){
                        if ($task.ExtensionData.Info.Error.Fault.FaultMessage -like "VMware.Vim.LocalizableMessage")  {
                            Write-PowerManagementLogMessage -Type ERROR -Message "'$($PowerStatus)' task exited with localized error message. Kindly check vCenter UI for details and take necessary action" -Colour Red
                        } else {
                            Write-PowerManagementLogMessage -Type WARN -Message "'$($PowerStatus)' task exited with the Message:$($task.ExtensionData.Info.Error.Fault.FaultMessage) and Error: $($task.ExtensionData.Info.Error)" -Colour Cyan
                            Write-PowerManagementLogMessage -Type ERROR -Message "Kindly check vCenter UI for details and take necessary action" -Colour Red
                        }
                    }

                    if ($task.State -eq "Success"){
                        Write-PowerManagementLogMessage -Type INFO -Message "$PowerStatus task is completed successfully" -colour GREEN
                    } else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "$PowerStatus task is stuck at $($task.State) state"
                    }
                }
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null

            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VsanClusterPowerStatus cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Set-VsanClusterPowerStatus


Function Get-poweronVMsOnRemoteDS {
    <#
        .SYNOPSIS
        Get the list of remote powered on VM's for a given cluster

        .DESCRIPTION
        Get the list of VM's which are on the remote datastore for a given cluster

        .EXAMPLE
        Get-poweronVMsOnRemoteDS -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -clustertocheck sfo-m01-cl01
        Get the list of remote powered on VMs for the cluster sfo-m01-cl01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$clustertocheck
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-poweronVMsOnRemoteDS cmdlet." -Colour Yellow

        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $TotalvSANDatastores = @()
                $RemotevSANdatastores = @()
                $TotalvSANDatastores = (Get-Cluster -Name $clustertocheck | Get-Datastore | Where-Object { $_.Type -eq "vSAN" }).Name
                $RemotevSANdatastores = ((get-vsanClusterConfiguration -Cluster $clustertocheck).RemoteDatastore).Name
                $LocalvSANDatastores = $TotalvSANDatastores | Where-Object { $_ -notin $RemotevSANdatastores }
                [Array]$PoweredOnVMs = @()
                foreach ($localds in $LocalvSANDatastores) {
                    foreach ($cluster in (Get-Cluster).Name) {
                        if ($cluster -ne $clustertocheck ) {
                            $MountedvSANdatastores = ((get-vsanClusterConfiguration -Cluster $cluster).RemoteDatastore).Name
                            foreach ($datastore in $MountedvSANdatastores) {
                                if ($datastore -eq $localds) {
                                    $datastoreID = Get-Datastore $datastore | ForEach-Object { $_.ExtensionData.MoRef }
                                    $vms = (Get-Cluster -name $cluster | get-vm | Where-Object { $_.PowerState -eq "PoweredOn" }) | Where-Object { $vm = $_; $datastoreID | Where-Object { $vm.DatastoreIdList -contains $_ } }
                                    if ($vms) {
                                        Write-PowerManagementLogMessage -Type INFO -Message "Remote VMs Named: $vms are running on cluster: '$cluster' and datastore: '$datastore' `n"
                                        [Array]$PoweredOnVMs += $vms
                                    }
                                }
                            }
                        }
                    }
                }
                return $PoweredOnVMs
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-poweronVMsOnRemoteDS cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-poweronVMsOnRemoteDS


Function Test-LockdownMode {
    <#
        .SYNOPSIS
        Check if there is an ESXi host in the cluster with Lockdown mode enabled

        .DESCRIPTION
        The Test-LockdownMode function will return error if there is ESXi host in the cluster with Lockdown Mode enabled.

        .EXAMPLE
        Test-LockdownMode -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01
        Check Lockdown mode for ESXi hosts in the cluster sfo-m01-cl01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Test-LockdownMode cmdlet." -Colour Yellow

        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $hostsInCluster = @()
				$hostsInCluster = Get-Cluster -Name $cluster | Get-VMHost
				$hostsWithLockdown = ""
				if ($hostsInCluster.count -ne 0) {
                    foreach ($esxiHost in $hostsInCluster) {
                        Write-PowerManagementLogMessage -Type INFO -Message "Checking Lockdown mode for $esxiHost ...." -Colour Yellow
                        $lockdownStatus = (Get-VMHost -Name $esxiHost).ExtensionData.Config.LockdownMode
                        if ($lockdownStatus -eq $null) {
                            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to fetch Lockdown mode info as ESXi host $esxiHost! could be down, please check" -Colour RED
                        } else {
                            if ($lockdownStatus -ne "lockdownDisabled") {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Lockdown mode is enabled for ESXi host $esxiHost" -Colour Cyan
                                $hostsWithLockdown += ", $esxiHost"
                            }
                        }
                    }
                } else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "looks like cluster $cluster is not present on a given server $server, kindly check" -Colour Red
                }
				if ([string]::IsNullOrEmpty($hostsWithLockdown))  {
				    Write-PowerManagementLogMessage -Type INFO -Message "No hosts found to have Lockdown mode enabled, So continuing" -Colour GREEN
				} else {
				    Write-PowerManagementLogMessage -Type ERROR -Message "The following hosts have Lockdown mode enabled: $hostsWithLockdown. Please disable it in order to continue." -Colour Red
				}
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Test-LockdownMode cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Test-LockdownMode


Function Get-VMRunningStatus {
    <#
        .SYNOPSIS
        Gets the running state of a virtual machine
    
        .DESCRIPTION
        The Get-VMRunningStatus cmdlet gets the running status of the given nodes matching the pattern on an ESXi host
    
        .EXAMPLE
        Get-VMRunningStatus -server sfo-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -pattern "^vCLS*"
        This example connects to an ESXi host and searches for all virtual machines matching the pattern and gets their running status
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pattern,
        [Parameter (Mandatory = $false)] [ValidateSet("Running", "NotRunning")] [String]$Status = "Running"
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMRunningStatus cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to host '$server' and checking if nodes named '$pattern' are in the '$($status.ToUpper())' state..."
                $nodes = Get-VM | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost
                if ($nodes.Name.Count -eq 0) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot find nodes matching pattern '$pattern' in the inventory of host '$server'." -Colour Red
                }
                else {
                    foreach ($node in $nodes) {	
                        $vm_obj = Get-VMGuest -server $server -VM $node.Name -ErrorAction SilentlyContinue | Where-Object VmUid -match $server
                        if ($vm_obj.State -eq $status) {
                            Write-PowerManagementLogMessage -Type INFO -Message "Node $($node.Name) is in '$($status.ToUpper()) state.'"
                            return $true
                        }
                        else {

                            Write-PowerManagementLogMessage -Type INFO -Message "Node $($node.Name) is not in '$($status.ToUpper()) state'."
                            return $false
                        }
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }  
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMRunningStatus cmdlet." -Colour Yellow
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
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cmd,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$expected
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Invoke-EsxCommand cmdlet." -Colour Yellow
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
        $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force -WarningAction SilentlyContinue
        if ($session) {
            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to run command '$cmd' on server '$server'..."
            $commandOutput = Invoke-SSHCommand -Index $session.SessionId -Command $cmd -Timeout 900
            if ($expected ) {
                if (($commandOutput.Output -match $expected)) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Command '$cmd' completed with  expected output on server '$server'." -Colour Green
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Failure. The `"$($expected)`" is not present in `"$($commandOutput.Output)`" output" -Colour Red
                }
            }
            elseif ($commandOutput.exitStatus -eq 0) {
                Write-PowerManagementLogMessage -Type INFO -Message "Success. The command completed successfully." -Colour Green
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Failure. The command could not be run." -Colour Red
            }
            Remove-SSHSession -Index $session.SessionId | Out-Null   
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Invoke-EsxCommand cmdlet." -Colour Yellow
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
        In the above example, it tries to ssh to esxi host and if success, returns true
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-SSHEnabledStatus cmdlet." -Colour Yellow
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Attempting to open an SSH connection to server '$server'..."
            $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($session) {
                Write-PowerManagementLogMessage -Type INFO -Message "SSH is enabled on '$server'." -Colour Green
                Remove-SSHSession -Index $session.SessionId | Out-Null
                return $True
            }
            else {
                Write-PowerManagementLogMessage -Type INFO -Message "SSH is not enabled '$server'."
                return $False
            }
        } else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with server '$server'. Check the FQDN or IP address or power state of the server." -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-SSHEnabledStatus cmdlet" -Colour Yellow
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
        This example connects to a vCenter Server and checks the state of the vSAN cluster health
    #>
    
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Test-VsanHealth cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to check the vSAN cluster health..."
                $count = 1
                $flag = 0
                While ($count -ne 5) {
                    Try {
                        $Error.clear()
                        Get-vSANView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -erroraction stop | Out-Null
                        if (-Not $Error) {
                            $flag = 1
                            Break
                        }
                    }
                    Catch {
                        Write-PowerManagementLogMessage -Type INFO -Message "The vSAN health service is yet to come up, please wait ..."
                        Start-Sleep -s 60
                        $count += 60
                    }
                }

                if (-Not $flag) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot run the Test-VsanHealth cmdlet because the vSAN health service is not running." -Colour Red
                }
                else {
                    Start-Sleep -s 60
                    $vchs = Get-VSANView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
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
                        if ($healthStatus -eq "red") {
                            $health_status = 'RED'
                        }
                        $healthCheckGroupResult = [pscustomobject] @{
                            HealthCHeck = $healthCheckGroup.GroupName
                            Result      = $healthStatus
                        }
                        $healthCheckResults += $healthCheckGroupResult
                    }
                    if ($health_status -eq 'GREEN' -and $results.OverallHealth -ne 'red') {
                        Write-PowerManagementLogMessage -Type INFO -Message "The vSAN health status for $cluster is good." -Colour Green
                        return 0
                    }
                    else {
                        Write-PowerManagementLogMessage -Type ERROR -Message "The vSAN health status for $cluster is bad." -Colour Red
                        return 1
                    }
                    Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Test-VsanHealth cmdlet." -Colour Yellow
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
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )
    
    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Test-VsanObjectResync cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server' and attempting to check the resynchronization status... "
                $no_resyncing_objects = Get-VsanResyncingComponent -Server $server -cluster $cluster -ErrorAction Ignore
                Write-PowerManagementLogMessage -Type INFO -Message "Number of resynchronizing objects: $no_resyncing_objects."
                if ($no_resyncing_objects.count -eq 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "No resynchronizing objects." -Colour Green
                    return 0
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Resynchronizing objects in progress..." -Colour Red
                    return 1
                }
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red 
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Test-VsanObjectResync cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanObjectResync

Function Get-VMsWithPowerStatus {
    <#
        .SYNOPSIS
        Return list of virtual machines that are in a given power state

        .DESCRIPTION
        The Get-VMsWithPowerStatus cmdlet return list of virtual machines virtual machines are in a given powerstate on a given server/host

        .EXAMPLE
        Get-VMsWithPowerStatus -server sfo01-m01-esx01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon"
        This example connects to a ESXi host and returns the list of powered on virtual machines

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon" -pattern "sfo-wsa01" -exactmatch
        This example connects to a management virtual center and searches for a VM sfo-wsa01 in a particular powerstate and returns the matching VMs

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon"  -pattern "vcls"
        This example connects to a management virtual center and returns the list of powered on vCLS virtual machines

        Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon"  -pattern "vcls" -silence
        This example connects to a management virtual center and returns the list of powered on vCLS virtual machines
        but supresses all the log messages in the method
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("poweredon","poweredoff")] [String]$powerstate,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pattern = $null ,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$exactMatch,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$silence
    )

    Try {

        if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMsWithPowerStatus cmdlet." -Colour Yellow}
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
           if(-not $silence) { Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."}
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if(-not $silence) {Write-PowerManagementLogMessage -type INFO -Message "Connected to server '$server' and attempting to get the list of virtual machines..."}
                    if ($pattern) {
                        if ($PSBoundParameters.ContainsKey('exactMatch') ) {
                            $no_of_vms = get-vm -Server $server | Where-Object Name -EQ $pattern  | Where-Object PowerState -eq $powerstate
                        }
                        else {
                            $no_of_vms = get-vm -Server $server | Where-Object Name -match $pattern  | Where-Object PowerState -eq $powerstate
                        }
                    }
                    else {
                        $no_of_vms = get-vm -Server $server | Where-Object PowerState -eq $powerstate
                    }
                    if ($no_of_vms.count -eq 0) {
                        if(-not $silence) {Write-PowerManagementLogMessage -type INFO -Message "No virtual machines in the $powerstate state."}
                    }
                    else {
                        $no_of_vms_string = $no_of_vms -join ","
                        if(-not $silence) {Write-PowerManagementLogMessage -type INFO -Message "The virtual machines in the $powerstate state: $no_of_vms_string"}
                    }
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                    Return $no_of_vms
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMsWithPowerStatus cmdlet." -Colour Yellow}
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
        This example connects to a vCenter Server and returns the wcp service status

        Get-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -nolog
        This example connects to a vCenter Server and returns the wcp service status and also suppress any log messages inside the function
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$nolog,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service
    )

    Try {
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VAMIServiceStatus cmdlet." -Colour Yellow
        }
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            if (-Not $nolog) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            $retries = 20
            $flag = 0
            While ($retries) {
                Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
                if ($DefaultCisServers.Name -eq $server) {
                    $flag = 1
                    break
                }
                Start-Sleep 60
                $retries -= 1
                if (-Not $nolog) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to VAMI Service Console is taking some time. Please wait." -Colour Yellow
                }
            }
            if ($flag) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service, 0)
                return $serviceStatus.state
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message  "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message  "Testing the connection to server '$server' has failed. Check your details and try again." -Colour Red
        } 
    } 
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        if (-Not $nolog) {
            # Write-PowerManagementLogMessage -Type INFO -Message "Disconnecting from host '$server'..."
        }
        Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VAMIServiceStatus cmdlet." -Colour Yellow
        }
    }
}
Export-ModuleMember -Function Get-VAMIServiceStatus

Function Set-VamiServiceStatus {
    <#
        .SYNOPSIS
        Start/Stop/Restart the status of the service on a given vCenter Server

        .DESCRIPTION
        The Set-VamiServiceStatus cmdlet will Start/Stop/Restart the service on a given vCenter Server.

        .EXAMPLE
        Set-VamiServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -service wcp -state "start"
        This example connects to a vCenter Server and starts the wcp service

        Set-VamiServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -nolog -state "restart"
        This example connects to a vCenter Server and restarts the wcp service and also suppress any log messages inside the function
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("start", "stop", "restart")] [String]$state,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$nolog,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service
    )

    Try {
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VamiServiceStatus cmdlet." -Colour Yellow
        }
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            if (-Not $nolog) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            $retries = 20
            $flag = 0
            While ($retries) {
                Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
                if ($DefaultCisServers.Name -eq $server) {
                    $flag = 1
                    break
                }
                Start-Sleep 60
                $retries -= 1
                if (-Not $nolog) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Connecting to VAMI Service Console is taking some time. Please wait." -Colour Yellow
                }
            }
            if ($flag) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                if ($state -eq "start") {
                    $vMonAPI.Start($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if($serviceStatus.state -eq "STARTED") {
                        if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "'$service' service is successfully started" -Colour Yellow
                        }
                    } else {
                         Write-PowerManagementLogMessage -Type ERROR -Message "'$service' service is could not be started" -Colour Red
                    }
                } elseif ($state -eq "stop") {
                    $vMonAPI.Stop($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if($serviceStatus.state -eq "STOPPED") {
                        if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "'$service' service is successfully stopped" -Colour Yellow
                        }
                    } else {
                         Write-PowerManagementLogMessage -Type ERROR -Message "'$service' service is could not be stopped" -Colour Red
                    }
                } else {
                    $vMonAPI.ReStart($service)
                    $serviceStatus = $vMonAPI.Get($service, 0)
                    if($serviceStatus.state -eq "STARTED") {
                         if (-Not $nolog) {
                            Write-PowerManagementLogMessage -Type INFO -Message "'$service' service is successfully restarted" -Colour Yellow
                         }
                    } else {
                         Write-PowerManagementLogMessage -Type ERROR -Message "'$service' service is could not be restarted" -Colour Red
                    }
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message  "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message  "Testing the connection to server '$server' has failed. Check your details and try again." -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        if (-Not $nolog) {
            # Write-PowerManagementLogMessage -Type INFO -Message "Disconnecting from host '$server'..."
        }
        Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
        if (-Not $nolog) {
            Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VamiServiceStatus cmdlet." -Colour Yellow
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
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster,
        [Parameter (Mandatory = $true, ParameterSetName = "enable")] [Switch] $enableHA,
        [Parameter (Mandatory = $true, ParameterSetName = "disable")] [Switch] $disableHA
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-VsphereHA cmdlet." -Colour Yellow
        if ($(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'... ..."
                $retryCount = 0
                $completed = $false
                $SecondsDelay = 10
                $Retries = 60
                if ($enableHA) {
                    if ($(get-cluster -Name $cluster).HAEnabled) {
                        Write-PowerManagementLogMessage -type INFO -Message "vSphere High Availability is already enabled on the vSAN cluster. "
                        return $true
                    }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "Enabling vSphere High Availability for cluster '$cluster'..."
                        Set-Cluster -Server $server -Cluster $cluster -HAEnabled:$true -Confirm:$false | Out-Null
                        While (-not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress." -Colour Cyan
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep 5
                            $runningTasks = get-task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep $SecondsDelay
                                continue
                            }
                            else {
                                $completed = $true
                                if ($(get-cluster -Name $cluster).HAEnabled) {
                                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability for cluster '$cluster' changed to 'Enabled'." -Colour Green
                                    return $true
                                }
                                else {
                                    Write-PowerManagementLogMessage -Type WARNING -Message "Failed to set vSphere High Availability for cluster '$cluster' to 'Enabled'." -Colour Cyan
                                    return $false
                                }
                            }
                        }
                    }
                }
                if ($disableHA) {
                    if (!$(get-cluster -Name $cluster).HAEnabled) {
                        Write-PowerManagementLogMessage -type INFO -Message "vSphere High Availability is already disabled on the vSAN cluster. "
                        return $true
                    }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "Disabling vSphere High Availability for cluster '$cluster'."
                        Set-Cluster -Server $server -Cluster $cluster -HAEnabled:$false -Confirm:$false | Out-Null
                        While (-not $completed) {
                            # Check iteration number
                            if ($retrycount -ge $Retries) {
                                Write-PowerManagementLogMessage -Type WARNING -Message "Set vSphere High Availability timeouted after $($SecondsDelay * $Retries) seconds. There are still reconfiguratons in progress." -Colour Cyan
                                return $false
                            }
                            $retryCount++
                            # Get running tasks
                            Start-Sleep 5
                            $runningTasks = get-task -Status Running
                            if (($runningTasks -match "Update vSAN configuration") -or ($runningTasks -match "Configuring vSphere HA")) {
                                Write-PowerManagementLogMessage -Type INFO -Message "vSphere High Availability configuration changes are not applied. Sleeping for $SecondsDelay seconds..."
                                Start-Sleep $SecondsDelay
                                continue
                            }
                            else {
                                $completed = $true
                                if (!$(get-cluster -Name $cluster).HAEnabled) {
                                    Write-PowerManagementLogMessage -Type INFO -Message "Disabled vSphere High Availability for cluster '$cluster'." -Colour Green
                                    return $true
                                }
                                else {
                                    Write-PowerManagementLogMessage -Type WARNING -Message "Failed to disable vSphere High Availability for cluster '$cluster'." -Colour Cyan
                                    return $false
                                }
                            }
                        }
                    }
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again." -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-VsphereHA cmdlet." -Colour Yellow
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
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-DrsAutomationLevel cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'... ..."
                $ClusterData = Get-Cluster -Name $cluster
                if ($ClusterData.DrsEnabled) {
                    $clsdrsvalue = $ClusterData.DrsAutomationLevel
                    Write-PowerManagementLogMessage -type INFO -Message "The cluster DRS value: $clsdrsvalue."
                }
                else {
                    Write-PowerManagementLogMessage -type INFO -Message "vSphere DRS is not enabled on the cluster $cluster."
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                return $clsdrsvalue
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-DrsAutomationLevel cmdlet." -Colour Yellow
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
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster,
        [Parameter (Mandatory = $true)] [ValidateSet("enable", "disable")] [String] $mode
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Set-Retreatmode cmdlet." -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                $cluster_id = Get-Cluster -Name $cluster | select-object -property Id
                $domain_out = $cluster_id.Id -match 'domain-c.*'
                $domain_id = $Matches[0]
                $advanced_setting = "config.vcls.clusters.$domain_id.enabled"
                if (Get-AdvancedSetting -Entity $server -Name  $advanced_setting) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is present."
                    if ($mode -eq 'enable') {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'false' -Confirm:$false | out-null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false."  -Colour Green
                    }
                    else {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'true' -Confirm:$false  | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true." -Colour Green
                    }
                }
                else {
                    if ($mode -eq 'enable') {
                        New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'false' -Confirm:$false  | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to false." -Colour Green
                    }
                    else {
                        New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'true' -Confirm:$false  | Out-Null
                        Write-PowerManagementLogMessage -Type INFO -Message "Advanced setting $advanced_setting is set to true." -Colour Green
                    }
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Set-Retreatmode cmdlet." -Colour Yellow
    }

}
Export-ModuleMember -Function Set-Retreatmode

Function Get-VMToClusterMapping {
    <#
        .SYNOPSIS
        Get the list of all Virtual Machines which are mapped for a given vSphere Clusters

        .DESCRIPTION
        The Get-VMToClusterMapping cmdlet gets all Virtual Machines belonging to a given  vSphere Clusters

        .EXAMPLE
        Get-VMToClusterMapping -server $server -user $user -pass $pass -cluster $cluster -folder "VCLS"
        This example gets all virtual machines (vCLS) belonging to a given vSphere Clusters $cluster

        Get-VMToClusterMapping -server $server -user $user -pass $pass -cluster $cluster -folder "VCLS" -powerstate "poweredon"
        This example gets all virtual machines (vCLS) belonging to a given vSphere Clusters $cluster in the powered on state only

    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]] $cluster,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $folder,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch] $silence,
        [Parameter (Mandatory = $false)] [ValidateSet("poweredon","poweredoff")] [String] $powerstate

    )

    Try {
        if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-VMToClusterMapping cmdlet." -Colour Yellow}
        $checkServer = (Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded
        if ($checkServer) {
            if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."}
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."}
                foreach ($clus in $cluster) {
                    if ($powerstate) {
                        $VMs += get-vm -location $clus  | where {(Get-VM -location $folder) -contains $_} | where PowerState -eq $powerstate
                    } else {
                        $VMs += get-vm -location $clus  | where  {(Get-VM -location $folder) -contains $_}
                    }
                }
                $clustersstring = $cluster -join ","
                if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "list of VM's mapped to cluster $clustersstring is $VMs"}
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
                return $VMs

            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot connect to server '$server'. Check your environment and try again." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        if(-not $silence) {Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-VMToClusterMapping cmdlet." -Colour Yellow}
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
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Wait-ForStableNsxtClusterStatus cmdlet." -Colour Yellow
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
        While (-not $completed) {
            # Check iteration number
            if ($retrycount -ge $Retries) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Request to '$uri' failed after $retryCount attempts." -Colour Cyan
                return $false
            }
            $retryCount++
            # Retry connection if NSX Manager is not online
            Try {
                $response = Invoke-RestMethod -Method GET -URI $uri -headers $headers -ContentType application/json -TimeoutSec 60
            }
            Catch {
                Write-PowerManagementLogMessage -Type INFO -Message "Could not connect to NSX Manager '$server'! Sleeping $($SecondsDelay * $aditionalWaitMultiplier) seconds before next attempt."
                Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                continue
            }
            $successfulConnections++
            if ($response.mgmt_cluster_status.status -ne 'STABLE') {
                Write-PowerManagementLogMessage -Type INFO -Message "Expecting NSX Manager cluster state 'STABLE', present state: $($response.mgmt_cluster_status.status)"
                # Add longer sleep during fiest several attempts to avoid locking the NSX-T account just after power-on
                if ($successfulConnections -lt 4) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for $($SecondsDelay * $aditionalWaitMultiplier) seconds before next check..."
                    Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                }
                else {
                    Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for $SecondsDelay seconds until the next check..."
                    Start-Sleep $SecondsDelay
                }
            }
            else {
                $completed = $true
                Write-PowerManagementLogMessage -Type INFO -Message "The state of the NSX Manager cluster '$server' is 'STABLE'." -Colour Green
                return $true
            }
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Wait-ForStableNsxtClusterStatus cmdlet." -Colour Yellow
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
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String] $VCfqdn
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-EdgeNodeFromNSXManager cmdlet." -Colour Yellow
        if (( Test-NetConnection -ComputerName $server -Port 443 ).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultNSXTServers) {
                Disconnect-NSXTServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-NsxTServer -server $server -user $user -password $pass | Out-Null
            $edge_nodes_list = @()
            if ($DefaultNsxTServers.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                #get transport nodes info
                $transport_nodes_var = Get-NSXtService com.vmware.nsx.transport_nodes
                $transport_nodes_list = $transport_nodes_var.list().results
                #get compute managers info
                $compute_manager_var = Get-NsXtService com.vmware.nsx.fabric.compute_managers
                $compute_manager_list = $compute_manager_var.list().results
                foreach ($compute_resource in $compute_manager_list) {
                    if ($compute_resource.display_name -match $VCfqdn) {
                        $compute_resource_id = $compute_resource.id
                    }
                }
                foreach ($resource in $transport_nodes_list) {
                    if ($resource.node_deployment_info.resource_type -eq "EdgeNode") {
                        if ($resource.node_deployment_info.deployment_config.GetStruct('vm_deployment_config').GetFieldValue("vc_id") -match $compute_resource_id) {
                            [Array]$edge_nodes_list += $resource.display_name
                        }
                    }
                }
                Disconnect-NSXTServer * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $edge_nodes_list
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details." -Colour Red
            }

        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-EdgeNodeFromNSXManager cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-EdgeNodeFromNSXManager

Function Get-NSXTComputeManger {
    <#
        .SYNOPSIS
        This method reads list of compute managers mapped to NSX-T from from NSX manager

        .DESCRIPTION
        The Get-NSXTComputeManger used to read  list of compute managers mapped to NSX-T from NSX manager

        .EXAMPLE
        Get-NSXTComputeManger -server $server -user $user -pass $pass
        This example returns list of compute manager mapped to the given server $server
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-NSXTComputeManger cmdlet." -Colour Yellow
        if (( Test-NetConnection -ComputerName $server -Port 443 ).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultNSXTServers) {
                Disconnect-NSXTServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-NsxTServer -server $server -user $user -password $pass | Out-Null
            if ($DefaultNsxTServers.Name -eq $server) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connected to server '$server'..."
                #get compute managers info
                $compute_manager_var = Get-NsXtService com.vmware.nsx.fabric.compute_managers
                $compute_manager_list = $compute_manager_var.list().results.server
                Disconnect-NSXTServer * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
                return $compute_manager_list
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details." -Colour Red
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-NSXTComputeManger cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-NSXTComputeManger


Function Get-TanzuEnabledClusterStatus {
    <#
        .SYNOPSIS
        This method checks if the Cluster is Tanzu enabled

        .DESCRIPTION
        The Get-TanzuEnabledClusterStatus used to check if the given Cluster is Tanzu enabled

        .EXAMPLE
        Get-TanzuEnabledClusterStatus -server $server -user $user -pass $pass -cluster $cluster -SDDCManager $SDDCManager -SDDCuser $SDDCuser -SDDCpass $SDDCpass
        This example returns True if the given cluster is Tanzu enabled else false
    #>

    Param(
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String] $cluster
    )

    Try {
        Write-PowerManagementLogMessage -Type INFO -Message "Starting the call to the Get-TanzuEnabledClusterStatus cmdlet." -Colour Yellow
        if (( Test-NetConnection -ComputerName $server -Port 443 ).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$server'..."
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -server $server -user $user -password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $out = get-wmcluster -cluster $cluster -server $server -ErrorVariable ErrorMsg -ErrorAction SilentlyContinue
                if ($out.count -gt 0) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere with Tanzu is enabled." -Colour Green
                    return $True
                }
                elseif (([string]$ErrorMsg -match "does not have Workloads enabled") -or ([string]::IsNullOrEmpty($ErrorMsg))) {
                    Write-PowerManagementLogMessage -Type INFO -Message "vSphere with Tanzu is not enabled."
                    return $False
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot fetch information related to vSphere with Tanzu. ERROR message from 'get-wmcluster' command: '$ErrorMsg'" -Colour Red
                }
            }
            else {
                Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check the console output for more details." -Colour Red
            }

        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Connection to '$server' has failed. Check your environment and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
    Finally {
        Write-PowerManagementLogMessage -Type INFO -Message "Completed the call to the Get-TanzuEnabledClusterStatus cmdlet." -Colour Yellow
    }
}
Export-ModuleMember -Function Get-TanzuEnabledClusterStatus

######### Start Useful Script Functions ##########
Function Write-PowerManagementLogMessage {
    Param (
        [Parameter (Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter (Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION")] [String]$type,
        [Parameter (Mandatory = $false)] [String]$Colour,
        [Parameter (Mandatory = $false)] [String]$Skipnewline
    )
    $ErrorActionPreference = 'Stop'
    if (!$Colour) {
        $Colour = "White"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    if ($Skipnewline) {
        Write-Host -NoNewline -ForegroundColor $Colour " $type $Message"
    }
    else {
        Write-Host -ForegroundColor $colour " $Type $Message"
    }
    $logContent = '[' + $timeStamp + '] ' + $Type + ' ' + $Message
    # Log into file only case we have a "$logFile" variable
    if ($logFile) {
        Add-Content -Path $logFile $logContent
    }
    if ($type -match "ERROR") {
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
    Write-PowerManagementLogMessage -message " ERROR at Script Line $lineNumber" -Colour Red
    Write-PowerManagementLogMessage -message " Relevant Command: $lineText" -Colour Red
    Write-PowerManagementLogMessage -message " ERROR Message: $errorMessage" -Colour Red
    Write-Error -Message $errorMessage
}
Export-ModuleMember -Function Debug-CatchWriterForPowerManagement
######### End Useful Script Functions ##########