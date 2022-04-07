# PowerShell module for Power Management of VMware Cloud Foundation

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This PowerShell module should be considered entirely experimental. It is still in development & not tested beyond
# lab scenarios. It is recommended you don't use it for any production environment without testing extensively!

# Enable communication with self-signed cerificates when using Powershell Core if you require all communications to be secure
# and do not wish to allow communication with self-signed cerificates remove lines 23-35 before importing the module.

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
        Write-LogMessage -Type INFO -Message "Starting run of the Stop-CloudComponent cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to shutdown nodes '$nodes'"
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count=0
                            if (Get-VM | Where-Object {$_.Name -eq $node}) {
                                $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vm_obj.State -eq 'NotRunning') {
                                    Write-LogMessage -Type INFO -Message "Node '$node' is already in Powered Off state" -Colour Cyan
                                    Continue
                                }
                                Write-LogMessage -Type INFO -Message "Attempting to shutdown node '$node'"
                                if ($PsBoundParameters.ContainsKey("noWait")) {
                                    Stop-VM -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                }
                                else {
                                    Stop-VMGuest -Server $server -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                    Write-LogMessage -Type INFO -Message "Waiting for node '$node' to shut down"
                                    While (($vm_obj.State -ne 'NotRunning') -and ($count -ne $timeout)) {
                                        Start-Sleep -Seconds 5
                                        $count = $count + 1
                                        $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                    }
                                    if ($count -eq $timeout) {
                                        Write-LogMessage -Type ERROR -Message "Node '$node' did not shutdown within the stipulated timeout: $timeout value"	-Colour Red			
                                    }
                                    else {
                                        Write-LogMessage -Type INFO -Message "Node '$node' has shutdown successfully" -Colour Green
                                    }
                                }
                            }
                            else {
                                Write-LogMessage -Type ERROR -Message "Unable to find node $node in inventory of server $server" -Colour Red
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -eq "Pattern") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to shutdown nodes with pattern '$pattern'"
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $server
                    }
                    else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count=0
                            $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            if ($vm_obj.State -eq 'NotRunning') {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' is already in Powered Off state" -Colour Cyan
                                Continue
                            }
                            Write-LogMessage -Type INFO -Message "Attempting to shutdown node '$($node.name)'"
                            if ($PsBoundParameters.ContainsKey("noWait")) {
                                Stop-VM -Server $server -VM $node.Name -Confirm:$false | Out-Null
                            }
                            else {
                                Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server | Stop-VMGuest -Confirm:$false | Out-Null
                                $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                                While (($vm_obj.State -ne 'NotRunning') -and ($count -ne $timeout)) {
                                    Start-Sleep -Seconds 1
                                    $count = $count + 1
                                    $vm_obj = Get-VMGuest -VM $node.Name | Where-Object VmUid -match $server
                                }
                                if ($count -eq $timeout) {
                                    Write-LogMessage -Type ERROR -Message "Node '$($node.name)' did not shutdown within the stipulated timeout: $timeout value"	-Colour Red
                                }
                                else {
                                    Write-LogMessage -Type INFO -Message "Node '$($node.name)' has shutdown successfully" -Colour Green
                                }
                            }
                        }
                    }
                    elseif ($pattern) {
                        Write-LogMessage -Type WARNING -Message "There are no nodes matching the pattern '$pattern' on host $server" -Colour Cyan
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
		Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Stop-CloudComponent cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting run of Start-CloudComponent cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to start nodes '$nodes'"
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                                $count=0
                            if (Get-VM | Where-Object {$_.Name -eq $node}) {
                                $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if($vm_obj.State -eq 'Running'){
                                    Write-LogMessage -Type INFO -Message "Node '$node' is already in Powered On state" -Colour Green
                                    Continue
                                }
                                Write-LogMessage -Type INFO -Message "Attempting to startup node '$node'"
                                Start-VM -VM $node -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                Start-Sleep -Seconds 5
                                Write-LogMessage -Type INFO -Message "Waiting for node '$node' to start up"
                                While (($vm_obj.State -ne 'Running') -and ($count -ne $timeout)) {
                                    Start-Sleep -Seconds 10
                                    $count = $count + 1
                                    $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                }
                                if ($count -eq $timeout) {
                                    Write-LogMessage -Type ERROR -Message "Node '$node' did not startup within the stipulated timeout: $timeout value" -Colour Red
                                    Break 			
                                } 
                                else {
                                    Write-LogMessage -Type INFO -Message "Node '$node' has started successfully" -Colour Green
                                }
                            }
                            else {
                                Write-LogMessage -Type ERROR -Message "Unable to find $node in inventory of server $server" -Colour Red
                            }
                        }
                    }
                }

                if ($PSCmdlet.ParameterSetName -eq "Pattern") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to startup nodes with pattern '$pattern'"
                    if ($pattern) {
                        $patternNodes = Get-VM -Server $server | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $server
                    }
                    else {
                        $patternNodes = @()
                    }
                    if ($patternNodes.Name.Count -ne 0) {
                        foreach ($node in $patternNodes) {
                            $count=0
                            $vm_obj = Get-VMGuest -server $server -VM $node.Name | Where-Object VmUid -match $server
                            if ($vm_obj.State -eq 'Running') {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' is already in Powered On state" -Colour Green
                                Continue
                            }

                            Start-VM -VM $node.Name | Out-Null
                            $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            Write-LogMessage -Type INFO -Message "Attempting to startup node '$($node.name)'"
                            While (($vm_obj.State -ne 'Running') -AND ($count -ne $timeout)) {
                                Start-Sleep -Seconds 1
                                $count = $count + 1
                                $vm_obj = Get-VMGuest -Server $server -VM $node.Name | Where-Object VmUid -match $server
                            }
                            if ($count -eq $timeout) {
                                Write-LogMessage -Type ERROR -Message "Node '$($node.name)' did not startup within the stipulated timeout: $timeout value"	-Colour Red
                            }
                            else {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' has started successfully" -Colour Green
                            }
                        }
                    }
                    elseif ($pattern) {
                        Write-LogMessage -Type WARNING -Message "There are no nodes matching the pattern '$pattern' on host $server" -Colour Cyan
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
		Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Start-CloudComponent cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting run of Set-MaintenanceMode cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state maintenance mode"
                $hostStatus = (Get-VMHost -Server $server)
                if ($state -eq "ENABLE") {
                    if ($hostStatus.ConnectionState -eq "Connected") {
                        Write-LogMessage -type INFO -Message "Attempting to enter maintenance mode for $server"
                        Get-View -Server $server -ViewType HostSystem -Filter @{"Name" = $server }| Where-Object {!$_.Runtime.InMaintenanceMode} | ForEach-Object {$_.EnterMaintenanceMode(0, $false, (new-object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode=(new-object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction=[VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction})}))} | Out-Null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Maintenance") {
                            Write-LogMessage -Type INFO -Message "The host $server has entered maintenance mode successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The host $server did not enter maintenance mode, verify and try again" -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-LogMessage -Type INFO -Message "The host $server has already entered maintenance mode" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The host $server is not currently connected" -Colour Red
                    }
                }

                elseif ($state -eq "DISABLE") {
                    if ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-LogMessage -type INFO -Message "Attempting to exit maintenance mode for $server"
                        $task = Set-VMHost -VMHost $server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Wait-Task $task | out-null
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Connected") {
                            Write-LogMessage -Type INFO -Message "The host $server has exited maintenance mode successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The host $server did not exit maintenance mode, verify and try again" -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Connected") {
                        Write-LogMessage -Type INFO -Message "The host $server has already exited maintenance mode" -Colour Cyan
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The host $server is not currently connected" -Colour Red
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    } 
    Catch {
        Debug-CatchWriter -object $_
    } 
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Set-MaintenanceMode cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Set-MaintenanceMode

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
        Write-LogMessage -Type INFO -Message "Starting run of Set-DrsAutomationLevel cmdlet" -Colour Yellow

        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $drsStatus = Get-Cluster -Name $cluster -ErrorAction SilentlyContinue
                if ($drsStatus) {
                    if ($drsStatus.DrsAutomationLevel -eq $level) {
                        Write-LogMessage -Type INFO -Message "The DRS automation level for cluster '$cluster' is already set to '$level'" -Colour Cyan
                    }
                    else {
                        $drsStatus = Set-Cluster -Cluster $cluster -DrsAutomationLevel $level -Confirm:$false 
                        if ($drsStatus.DrsAutomationLevel -eq $level) {
                            Write-LogMessage -Type INFO -Message "The DRS automation level for cluster '$cluster' has been set to '$level' successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The DRS automation level for cluster '$cluster' could not be set to '$level'" -Colour Red
                        }
                    }
                    Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                else {
                    Write-LogMessage -Type ERROR -Message "Cluster '$cluster' not found on server '$server', please check your details and try again" -Colour Red
                }
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server '$server' failed, please check your details and try again" -Colour Red
        }
    } 
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Set-DrsAutomationLevel cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Set-DrsAutomationLevel

Function Get-VMRunningStatus {
    <#
        .SYNOPSIS
        Gets the running state of a virtual machine
    
        .DESCRIPTION
        The Get-VMRunningStatus cmdlet gets the runnnig status of the given nodes matching the pattern on an ESXi host
    
        .EXAMPLE
        Get-VMRunningStatus -server sfo-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -pattern "^vCLS*"
        This example connects to an ESXi host and searches for all virtual machines matching the pattern and gets their running status
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pattern,
        [Parameter (Mandatory = $false)] [ValidateSet("Running","NotRunning")] [String]$Status="Running"
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Get-VMRunningStatus cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and checking nodes named '$pattern' are in a '$($status.ToUpper())' state"
                $nodes = Get-VM | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost
                if ($nodes.Name.Count -eq 0) {
                    Write-LogMessage -Type ERROR -Message "Unable to find nodes matching the pattern '$pattern' in inventory of server $server" -Colour Red
                }
                else {
                    foreach ($node in $nodes) {	
                        $vm_obj = Get-VMGuest -server $server -VM $node.Name -ErrorAction SilentlyContinue | Where-Object VmUid -match $server
                        if ($vm_obj.State -eq $status){
                            Write-LogMessage -Type INFO -Message "Node $($node.Name) in correct running state '$($status.ToUpper())'" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "Node $($node.Name) in incorrect running state '$($status.ToUpper())'" -Colour Red
                        }
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }  
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Get-VMRunningStatus cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting run of Invoke-EsxCommand cmdlet" -Colour Yellow
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
        $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force -WarningAction SilentlyContinue
        if ($session) {
            Write-LogMessage -Type INFO -Message "Attempting to run command '$cmd' on server '$server'"
            #bug-2925496, default value was only 60 seconds, so increased it 900 as per IVO's suggestion
            $commandOutput = Invoke-SSHCommand -Index $session.SessionId -Command $cmd -Timeout 900
            #bug-2948041, was only checking $expected is passed but was not parsing it, did that so against command output.
            if ($expected ) {
                if (($commandOutput.Output -match $expected)) {
                    Write-LogMessage -Type INFO -Message "Command '$cmd' ran with expected output on server '$server' successfully" -Colour Green
                } else {
                    Write-LogMessage -Type ERROR -Message "Failure. The `"$($expected)`" is not present in `"$($commandOutput.Output)`" output" -Colour Red
                }
            }
            elseif ($commandOutput.exitStatus -eq 0) {
                Write-LogMessage -Type INFO -Message "Success. The command ran successfully" -Colour Green
            }
            else  {
                Write-LogMessage -Type ERROR -Message "Failure. The command could not be run" -Colour Red
            }
            Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
            Remove-SSHSession -Index $session.SessionId | Out-Null   
        }
        else {
            Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Invoke-EsxCommand cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Invoke-EsxCommand

Function Get-VsanClusterMember {
    <#
        .SYNOPSIS
        Get list of vSAN cluster members from a given ESXi host 
    
        .DESCRIPTION
		The Get-VsanClusterMember cmdlet uses the command "esxcli vsan cluster get", the output has a field SubClusterMemberHostNames
		to see if this has all the members listed
    
        .EXAMPLE
        Get-VsanClusterMember -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -members "sfo01-w01-esx01.sfo.rainpole.io"
        This example connects to an ESXi host and checks that all members are listed
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$members
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Get-VsanClusterMember cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and checking vSAN cluster members are present"
                $esxcli = Get-EsxCli -Server $server -VMHost (Get-VMHost $server) -V2
                $out =  $esxcli.vsan.cluster.get.Invoke()
                foreach ($member in $members) {
                    if ($out.SubClusterMemberHostNames -eq $member) {
                        Write-LogMessage -Type INFO -Message "vSAN cluster member '$member' matches" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type INFO -Message "vSAN cluster member '$member' does not match" -Colour Red
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message  "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Get-VsanClusterMember cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VsanClusterMember

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
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Test-VsanHealth cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to check the vSAN Cluster Health"
                $count = 1
                $flag = 0
                While ($count -ne 5) {
                    Try {
                        $Error.clear()
                        Get-vSANView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system" -erroraction stop | Out-Null
                        if(-Not $Error) {
                            $flag = 1
                            Break
                        }
                    }
                    Catch {
                        Write-LogMessage -Type INFO -Message "vSAN Health Service is yet to come up, kindly wait"
                        Start-Sleep -s 60
                        $count += 1
                    }
                }

                if (-Not $flag) {
                    Write-LogMessage -Type ERROR -Message "Unable to run Test-VsanHealth cmdlet because vSAN Health Service is not running" -Colour Red
                }
                else {
                    Start-Sleep -s 60
                    $vchs = Get-VSANView -Server $server -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
                    $cluster_view = (Get-Cluster -Name $cluster).ExtensionData.MoRef
                    $results = $vchs.VsanQueryVcClusterHealthSummary($cluster_view,$null,$null,$true,$null,$null,'defaultView')
                    $healthCheckGroups = $results.groups
                    $health_status = 'GREEN'
                    $healthCheckResults = @()
                    foreach ($healthCheckGroup in $healthCheckGroups) {
                        Switch ($healthCheckGroup.GroupHealth) {
                            red {$healthStatus = "error"}
                            yellow {$healthStatus = "warning"}
                            green {$healthStatus = "passed"}
                            info {$healthStatus = "passed"}
                        }
                        if ($healthStatus -eq "red") {
                            $health_status = 'RED'
                        }
                        $healtCheckGroupResult = [pscustomobject] @{
                            HealthCHeck = $healthCheckGroup.GroupName
                            Result = $healthStatus
                            }
                            $healthCheckResults+=$healtCheckGroupResult
                            }
                    if ($health_status -eq 'GREEN' -and $results.OverallHealth -ne 'red'){
                        Write-LogMessage -Type INFO -Message "The vSAN Health Status for $cluster is GOOD" -Colour Green
                        return 0
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The vSAN Health Status for $cluster is BAD" -Colour Red
                        return 1
                    }
                    Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                    Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Test-VsanHealth cmdlet" -Colour Yellow
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
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )
    
    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Test-VsanObjectResync cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to check status of resync"
                $no_resyncing_objects = Get-VsanResyncingComponent -Server $server -cluster $cluster -ErrorAction Ignore
                Write-LogMessage -Type INFO -Message "The number of resyncing objects are $no_resyncing_objects"
                if ($no_resyncing_objects.count -eq 0){
                    Write-LogMessage -Type INFO -Message "No resyncing objects" -Colour Green
                    return 0
                }
                else {
                    Write-LogMessage -Type ERROR -Message "Resyncing of objects in progress" -Colour Red
                    return 1
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red 
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Test-VsanObjectResync cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanObjectResync

Function Get-PoweredOnVMsCount {
    <#
        .SYNOPSIS
        Check how many virtual machines are in a powered on state

        .DESCRIPTION
        The Get-PoweredOnVMsCount cmdlet checks how many virtual machines are in a powered on state on a given host

        .EXAMPLE
        Get-PoweredOnVMsCount -server sfo01-m01-esx01.sfo.rainpole.io -user root -pass VMw@re1!
        This example connects to a ESXi host and returns the count of powered on virtual machines
    #>

    Param(
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$false)] [ValidateNotNullOrEmpty()] [String]$pattern = $null
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Get-PoweredOnVMsCount cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -type INFO -Message "Connected to server '$server' and attempting to count number of powered on virtual machines"
                if ($pattern) {
                    $no_powered_on_vms =  get-vm -Server $server | Where-Object Name -match $pattern  | where PowerState -eq "PoweredOn"
                }
                else {
                    $no_powered_on_vms =  get-vm -Server $server | where PowerState -eq "PoweredOn"
                }
                if ($no_powered_on_vms.count -eq 0){
                    Write-LogMessage -type INFO -Message "No virtual machines in a powered on state"
                }
                else {
                    Write-LogMessage -type INFO -Message "There are virtual machines in a powered on state: $no_powered_on_vms"
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                Return $no_powered_on_vms.count
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Get-PoweredOnVMsCount cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-PoweredOnVMsCount

Function Test-WebUrl {
    <#
        .SYNOPSIS
        Test connection to a URL
    
        .DESCRIPTION
        The Test-WebUrl cmdlet tests the connection to the provided URL
    
        .EXAMPLE
        Test-WebUrl -url "https://sfo-m01-nsx01.sfo.rainpole.io/login.jsp?local=true"
        This example tests a connection to the login page for NSX Manager
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$url
    )
    
    Try {
        Write-LogMessage -Type INFO -Message  "Starting run of Test-WebUrl cmdlet" -Colour Yellow
        Write-LogMessage -Type INFO -Message "Attempting connect to URL '$url'"
        $count = 1
        $StatusCode = ""
        While ($count -ne 6) {
            Try {
                $response = Invoke-WebRequest -uri $url
                $StatusCode = $response.StatusCode
                Break
            }
            Catch {
                start-sleep -s 20
                $count += 1
            }
        }
		if ($StatusCode -eq 200) {
            Write-LogMessage -Type INFO -Message "Response Code: $($StatusCode) for URL '$url' - SUCCESS" -Colour Green
		}
        else {
            Write-LogMessage -Type ERROR -Message "Response Code: $($StatusCode) for URL '$url'" -Colour Red
		}
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Test-WebUrl cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-WebUrl

#bug-2925594, Here method name was get, but actually functionality was verify, so made expected argument optional, also now it returns the function
Function Get-VamiServiceStatus {
    <#
        .SYNOPSIS
        Get the status of the service on a given vCenter Server
    
        .DESCRIPTION
        The Get-VamiServiceStatus cmdlet gets the current status of the service on a given vCenter Server. The status can be STARTED/STOPPED
    
        .EXAMPLE
        Get-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp
        This example connects to a vCenter Server and returns the wcp service status
    #>

	Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Get-VAMIServiceStatus cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            #bug-2925594  and bug-2925501 and bug-2925511
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
                Write-LogMessage -Type INFO -Message "Getting Service status is taking time, Please wait." -colour Yellow
            }
            if ($flag) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service,0)
                if (-Not $checkStatus) {
                    return $serviceStatus.state
                }
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message  "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        } 
    } 
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
        Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        Write-LogMessage -Type INFO -Message "Finishing run of Get-VAMIServiceStatus cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VAMIServiceStatus

Function Set-VamiServiceStatus {
    <#
        .SYNOPSIS
        Starts/Stops the service on a given vCenter Server
    
        .DESCRIPTION
        The Set-VamiServiceStatus cmdlet starts or stops the service on a given vCenter Server.
    
        .EXAMPLE
        Set-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action STOP
        This example connects to a vCenter Server and attempts to STOP the wcp service

        .EXAMPLE
        Set-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action START
        This example connects to a vCenter Server and attempts to START the wcp service
    #>

	Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service,
        [Parameter (Mandatory = $true)] [ValidateSet("START", "STOP")] [String]$action
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Set-VAMIServiceStatus cmdlet" -Colour Yellow
        if ((Test-NetConnection -ComputerName $server).PingSucceeded) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($action -eq "START") { $requestedState = "STARTED"} elseif ($action -eq "STOP") { $requestedState = "STOPPED" }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
            if ($DefaultCisServers.Name -eq $server) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service,0)                
                if ($serviceStatus.state -match $requestedState) {
                    Write-LogMessage -Type INFO -Message "The service $service is already set to '$requestedState'" -Colour Cyan
                }
                else {
                    if ($action -eq "START") {
                        Write-LogMessage -Type INFO -Message "Attempting to START the '$service' service"
                        $vMonAPI.start($service)
                    }
                    elseif ($action -eq "STOP") {
                        Write-LogMessage -Type INFO -Message "Attempting to STOP the '$service' service"
                        $vMonAPI.stop($service)
                    }
                    Do {
                        $serviceStatus = $vMonAPI.Get($service,0)
                    } Until ($serviceStatus -match $requestedState)
                    if ($serviceStatus.state -match $requestedState) {
                        Write-LogMessage -Type INFO -Message "Service '$service' has been '$requestedState' Successfully" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "Service '$service' has NOT been '$requestedState'. Actual status: $($serviceStatus.state)" -Colour Red
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message  "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
        Write-LogMessage -Type INFO -Message "Finishing run of Set-VAMIServiceStatus cmdlet" -Colour Yellow
    } 
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Set-VAMIServiceStatus

Function Set-vROPSClusterState {
    <#
        .SYNOPSIS
        Set the status of the vRealize Operations Manager cluster
    
        .DESCRIPTION
        The Set-vROPSClusterState cmdlet sets the status of the vRealize Operations Manager cluster
    
        .EXAMPLE
        Set-vROPSClusterState -server xint-vrops01a.rainpole.io -user admin -pass VMw@re1! -mode OFFLINE
        This example takes the vRealize Operations Manager cluster offline

        .EXAMPLE
        Set-vROPSClusterState -server xint-vrops01a.rainpole.io -user admin -pass VMw@re1! -mode ONLINE
        This example places the vRealize Operations Manager cluster online
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("ONLINE", "OFFLINE", "RESTART")] [String]$mode
    )
	
    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Set-vROPSClusterState cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            $vropsHeader = createHeader $user $pass
            $statusUri = "https://$server/casa/deployment/cluster/info"
            $clusterStatus = Invoke-RestMethod -Method GET -URI $statusUri -Headers $vropsHeader -ContentType application/json
            if ($clusterStatus) {
                if ($clusterStatus.online_state -eq $mode ) {
                    Write-LogMessage -Type INFO -Message "The vRealize Operations Manager cluster is already in the $mode state"
                }
                else {
                    $params = @{"online_state" = $mode; "online_state_reason" = "Maintenance Window";}
                    $uri = "https://$server/casa/public/cluster/online_state"
                    $response = Invoke-RestMethod -Method POST -URI $uri -headers $vropsHeader -ContentType application/json -body ($params | ConvertTo-Json)
                    Write-LogMessage -Type INFO -Message "The vRealize Operations Manager cluster is set to $mode state, waiting for operation to complete"
                    Do {
                        Start-Sleep 5
                        $response = Invoke-RestMethod -Method GET -URI $statusUri -Headers $vropsHeader -ContentType application/json
                        if ($response.online_state -eq $mode) { $finished = $true }
                    } Until ($finished)
                    Write-LogMessage -Type INFO -Message "The vRealize Operations Manager cluster is now $mode"
                }
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message  "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Set-vROPSClusterState cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Set-vROPSClusterState

Function Get-vROPSClusterDetail {
    <#
        .SYNOPSIS
        Get the details of the vRealize Operations Manager cluster
    
        .DESCRIPTION
        The Get-vROPSClusterDetail cmdlet gets the details of the vRealize Operations Manager cluster 
    
        .EXAMPLE
        Get-vROPSClusterDetail -server xint-vrops01.rainpole.io -user root -pass VMw@re1!
        This example gets the details of the vRealize Operations Manager cluster
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    $vropsHeader = createHeader $user $pass
    $uri = "https://$server/casa/cluster/status"
    $response = Invoke-RestMethod -URI $uri -Headers $vropsHeader -ContentType application/json
    $response.'nodes_states'
}
Export-ModuleMember -Function Get-vROPSClusterDetail 

Function Get-EnvironmentId {
    <#
        .SYNOPSIS
        Obtain the Environment ID from vRealize Suite Lifecycle Manager

        .DESCRIPTION
        The Get-EnvironmentId cmdlet obtains the Environment ID from vRealize Suite Lifecycle Manager

        .EXAMPLE
        Get-EnvironmentId server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -all
        This example shows how to obtain all Environment IDs

        .EXAMPLE
        Get-EnvironmentId server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -product vra
        This example shows how to obtain the Environment ID for vRealize Automation 

        .EXAMPLE
        Get-EnvironmentId server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -name xint-env
        This example shows how to obtain the Environment ID based on the environemnt name 
    #>

    Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (ParameterSetName = 'Environments', Mandatory=$false)] [ValidateNotNullOrEmpty()] [Switch]$all,
		[Parameter (ParameterSetName = 'Name', Mandatory=$false)] [ValidateNotNullOrEmpty()] [String]$name,
        [Parameter (ParameterSetName = 'Product', Mandatory=$false)] [ValidateSet("vidm", "vra", "vrops", "vrli")] [String]$product
    )
    
    Try {
		$vrslcmHeaders = createHeader $user $pass
        $uri = "https://$server/lcm/lcops/api/v2/environments"
        $response = Invoke-RestMethod -Method GET -URI $uri -headers $vrslcmHeaders -ContentType application/json
        if ($PsBoundParameters.ContainsKey("name")) {
            $envId = $response | foreach-object -process { if($_.environmentName -match $name) { $_.environmentId }} 
            Return $envId
        }
        if ($PsBoundParameters.ContainsKey("product")){
            $envId = $response | foreach-object -process { if($_.products.id -match $product) { $_.environmentId }}
            Return $envId
        }
        else {
            $response
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Get-EnvironmentId

Function Request-PowerStateViaVRSLCM {
    <#
        .SYNOPSIS
        Power On/Off via vRealize Suite Lifecycle Manager

        .DESCRIPTION
        The Request-PowerStateViaVRSLCM cmdlet is used to shutdown or startup vRealize Automation or Workspace ONE Access via vRealize Suite Lifecycle Manager

        .EXAMPLE
        Request-PowerStateViaVRSLCM -server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -product VRA -mode power-off
        In this example we are stopping vRealize Automation

        .EXAMPLE
        Request-PowerStateViaVRSLCM -server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -product VRA -mode power-on
        In this example we are starting vRealize Automation

        .EXAMPLE
        Request-PowerStateViaVRSLCM -server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -product VIDM -mode power-off
        In this example we are stopping Workspace ONE Access

        .EXAMPLE
        Request-PowerStateViaVRSLCM -server xint-vrslcm01.rainpole.io -user vcfadmin@local -pass VMw@re1! -product VIDM -mode power-on
        In this example we are starting Workspace ONE Access
    #>

    Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory=$true)] [ValidateSet("power-on", "power-off")] [String]$mode,
        [Parameter (Mandatory=$true)] [ValidateSet("VRA", "VIDM")] [String]$product,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [Int]$timeout
    )
    
    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Request-PowerStateViaVRSLCM" -Colour Yellow
		Write-LogMessage -Type INFO -Message "Obtaining the vRealize Suite Lifecycle Manager Environment ID for '$product'"
        $environmentId = Get-EnvironmentId -server $server -user $user -pass $pass -product $product
		$vrslcmHeaders = createHeader $user $pass
		$uri = "https://$server/lcm/lcops/api/v2/environments/$environmentId/products/$product/$mode"
        $json = {}
        $response = Invoke-RestMethod -Method POST -URI $uri -headers $vrslcmHeaders -ContentType application/json -body $json
        Start-Sleep 10
        if ($response.requestId) {
            Write-LogMessage -Type INFO -Message "Initiated $mode for $product Successfully" -Colour Green
        }
        else {
            Write-LogMessage -Type ERROR -Message "Unable to $mode for $product due to response" -Colour Red
        }
		$id = $response.requestId
		$uri = "https://$server/lcm/request/api/v2/requests/$id"
        Do {
            $requestStatus = (Invoke-RestMethod -Method GET -URI $uri -headers $vrslcmHeaders -ContentType application/json | Where-Object {$_.vmid -eq $id}).state
        } 
        Until ($requestStatus -ne "INPROGRESS")
        if ($requestStatus -eq "COMPLETED") {
            Write-LogMessage -Type INFO -Message "The $mode of $product completed successfully" -Colour Green
        }
        elseif ($requestStatus -ne "FAILED") {
            Write-LogMessage -Type ERROR -Message "Could not $mode of $product because of $($response.errorCause.message)" -Colour Red
        }
        Write-LogMessage -Type INFO -Message "Finishing run of Request-PowerStateViaVRSLCM" -Colour Yellow
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Request-PowerStateViaVRSLCM

Function Start-EsxiUsingILO {
    <#
        .SYNOPSIS
        Power On/Off via DellEMC Server

        .DESCRIPTION
        This method is used to poweron the DellEMC Server using ILO IP address using racadm cli. This is cli equivalent of admin console for DELL servers

        .EXAMPLE
        PowerOn-EsxiUsingILO -ilo_ip $ilo_ip -ilo_user <drac_console_user> -ilo_pass <drac_console_pass>
        This example connects to out of band ip address powers on the ESXi host
    #>

    Param (
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$ilo_ip,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$ilo_user,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$ilo_pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$exe_path
    )
	
	Try {
        $default_path = 'C:\Program Files\Dell\SysMgt\rac5\racadm.exe'
        if (Test-path $exe_path) {
            Write-LogMessage -Type INFO -Message "The racadm.exe is present in $exe_path" -Colour Yellow
            $default_path = $exe_path
        }
        elseif (Test-path  $default_path) {
            Write-LogMessage -Type INFO -Message "The racadm.exe is present in the default path" -Colour Yellow
        }
        else {
            Write-LogMessage -Type Error -Message "The racadm.exe is not present in $exe_path or the default path $default_path" -Colour Red
        }
		$out = cmd /c $default_path -r $ilo_ip -u $ilo_user -p $ilo_pass  --nocertwarn serveraction powerup
		if ( $out.contains("Server power operation successful")) {
            Write-LogMessage -Type INFO -Message "power on of host $ilo_ip is successfully initiated" -Colour Yellow
			Start-Sleep -Seconds 600
            Write-LogMessage -Type INFO -Message "bootup complete." -Colour Yellow
		}
        else {
            Write-LogMessage -Type Error -Message "Could not power on the server $ilo_ip" -Colour Red
		}
	}
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of PowerOn-EsxiUsingILO cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Start-EsxiUsingILO

Function Restart-VsphereHA {
    <#
        .SYNOPSIS
        Restart vSphere High Availability

        .DESCRIPTION
        Restart vSphere High Availability to avoid "Cannot find vSphere HA master agent error".

        .EXAMPLE
        Restart-VsphereHA -server $server -user $user -pass $pass -cluster $cluster
        This example restarts vSphere High Availability if enabled
    #>

	Param(
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $cluster
    )

	Try {
        Write-LogMessage -Type INFO -Message "Starting run of Restart-VsphereHA cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server'"
                $HAStatus = Get-Cluster -Name $cluster | Select-Object HAEnabled
                if ($HAStatus) {
                    Write-LogMessage -type INFO -Message "vSphere High Availability is enabled on the vSAN cluster, restarting vSphere High Availability"
                    Set-Cluster -Cluster $cluster -HAEnabled:$false -Confirm:$false | Out-Null
                    $var1 = get-cluster -Name $cluster | Select-Object HAEnabled
                    if (-Not  $var1) {
                        Write-LogMessage -Type INFO -Message "vSphere High Availability is disabled"
                    }
                    Start-Sleep -s 5
                    Set-Cluster -Cluster $cluster -HAEnabled:$true -Confirm:$false | Out-Null
                    $var2 = get-cluster -Name $cluster | Select-Object HAEnabled
                    if ($var2) {
                        Write-LogMessage -type INFO -Message 'vSphere High Availability is enabled. vSphere High Availability is restarted'  -Colour GREEN
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
	}
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Restart-VsphereHA cmdlet" -Colour Yellow
    }

}
Export-ModuleMember -Function Restart-VsphereHA

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
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $cluster,
        [Parameter (Mandatory=$true)] [ValidateSet("enable", "disable")] [String] $mode
    )

	Try {
        Write-LogMessage -Type INFO -Message "Starting run of Set-Retreatmode cmdlet" -Colour Yellow
        $checkServer = (Test-NetConnection -ComputerName $server).PingSucceeded
        if ($checkServer) {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server'"
                $cluster_id = Get-Cluster -Name $cluster | select-object -property Id
                $domain_out = $cluster_id.Id -match 'domain-c.*'
                $domain_id = $Matches[0]
                $advanced_setting = "config.vcls.clusters.$domain_id.enabled"
                if (Get-AdvancedSetting -Entity $server -Name  $advanced_setting) {
                    Write-LogMessage -Type INFO -Message "The advanced setting $advanced_setting is present"
                    if ($mode -eq 'enable') {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'false' -Confirm:$false | out-null
                        Write-LogMessage -Type INFO -Message "The value of advanced setting $advanced_setting is set to false"  -Colour Green
                    }
                    else {
                        Get-AdvancedSetting -Entity $server -Name $advanced_setting | Set-AdvancedSetting -Value 'true' -Confirm:$false  | Out-Null
                        Write-LogMessage -Type INFO -Message "The value of advanced setting $advanced_setting is set to true" -Colour Green
                    }
                }
                else {
                    if ($mode -eq 'enable') {
                    New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'false' -Confirm:$false  | Out-Null
                    Write-LogMessage -Type INFO -Message "The value of advanced setting $advanced_setting is set to false" -Colour Green
                    }
                    else {
                    New-AdvancedSetting -Entity $server -Name $advanced_setting -Value 'true' -Confirm:$false  | Out-Null
                    Write-LogMessage -Type INFO -Message "The value of advanced setting $advanced_setting is set to true" -Colour Green
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer  -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
	}
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Set-Retreatmode cmdlet" -Colour Yellow
    }

}
Export-ModuleMember -Function Set-Retreatmode

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
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $pass
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Wait-ForStableNsxtClusterStatus" -Colour Yellow
        Write-LogMessage -Type INFO -Message "Waiting the cluster to become 'STABLE' for NSX Manager '$server'. This could take up to 20 min, please be patient"
        $uri = "https://$server/api/v1/cluster/status"
        $nsxHeaders = createHeader $user $pass
        $retryCount = 0
        $completed = $false
        $response = $null
        $SecondsDelay = 30
        $Retries = 20
        $aditionalWaitMultiplier = 3
        $successfulConnecitons = 0
        While (-not $completed) {
            # Check iteration number
            if ($retrycount -ge $Retries) {
                Write-LogMessage -Type Warning -Message "Request to $uri failed after $retryCount attempts." -Colour Cyan
                return $false
            }
            $retrycount++
            # Retry connection if NSX Manager is not online
            Try {
                $response = Invoke-RestMethod -Method GET -URI $uri -headers $nsxHeaders -ContentType application/json
            } Catch {
                Write-LogMessage -Type INFO -Message "Could not connect to NSX Manager '$server'. Sleeping $($SecondsDelay * $aditionalWaitMultiplier) seconds before next attempt"
                Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                continue
            }
            $successfulConnecitons++
            if ($response.mgmt_cluster_status.status -ne 'STABLE') {
                Write-LogMessage -Type INFO -Message "Expecting NSX Manager cluster state as 'STABLE', was: $($response.mgmt_cluster_status.status)"
                # Add longer sleep during fiest several attempts to avoid locking the NSX-T account just after power-on
                if ($successfulConnecitons -lt 4) {
                    Write-LogMessage -Type INFO -Message "Sleeping for $($SecondsDelay * $aditionalWaitMultiplier) seconds before next check..."
                    Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                }
                else {
                    Write-LogMessage -Type INFO -Message "Sleeping for $SecondsDelay seconds before next check..."
                    Start-Sleep $SecondsDelay
                }
            }
            else {
                $completed = $true
                Write-LogMessage -Type INFO -Message "The NSX Manager cluster '$server' state is 'STABLE'" -Colour GREEN
                return $true
            }
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Wait-ForStableNsxtClusterStatus" -Colour Yellow
    }
}
Export-ModuleMember -Function Wait-ForStableNsxtClusterStatus


Function Wait-ForActiveNodeStatus {
    <#
        .SYNOPSIS
        Fetch status of NSX Manager nodes

        .DESCRIPTION
        The Wait-ForActiveNodeStatus cmdlet fetches the cluster status of NSX Manager nodes after restart

        .EXAMPLE
        Wait-ForActiveNodeStatus -server sfo-m01-nsx01.sfo.rainpole.io -user admin -pass VMw@re1!VMw@re1! -node sfo-m01-nsx01a
        This example gets the node status of sfo-m01-nsx01a of the NSX Management Cluster
    #>

	Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $node
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Wait-ForActiveNodeStatus" -Colour Yellow
        Write-LogMessage -Type INFO -Message "Waiting the node to become 'Active' for NSX Manager '$server'. This could take up to 20 min, please be patient"
        $uri = "https://$server/api/v1/cluster/status"
        $nsxHeaders = createHeader $user $pass
        $retryCount = 0
        $completed = $false
        $response = $null
        $SecondsDelay = 30
        $Retries = 20
        $aditionalWaitMultiplier = 3
        $successfulConnecitons = 0
        While (-not $completed) {
            # Check iteration number
            if ($retrycount -ge $Retries) {
                Write-LogMessage -Type Warning -Message "Request to $uri failed after $retryCount attempts." -Colour Cyan
                return $false
            }
            $retrycount++
            # Retry connection if NSX Manager is not online
            Try {
                $response = Invoke-RestMethod -Method GET -URI $uri -headers $nsxHeaders -ContentType application/json
            } Catch {
                Write-LogMessage -Type INFO -Message "Could not connect to NSX Manager '$server'. Sleeping $($SecondsDelay * $aditionalWaitMultiplier) seconds before next attempt"
                Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                continue
            }
            $successfulConnecitons++
            if ($response.mgmt_cluster_status.status -ne 'STABLE') {
                Write-LogMessage -Type INFO -Message "Expecting NSX Manager cluster state as 'STABLE', was: $($response.mgmt_cluster_status.status)"
                # Add longer sleep during fiest several attempts to avoid locking the NSX-T account just after power-on
                if ($successfulConnecitons -lt 4) {
                    Write-LogMessage -Type INFO -Message "Sleeping for $($SecondsDelay * $aditionalWaitMultiplier) seconds before next check..."
                    Start-Sleep $($SecondsDelay * $aditionalWaitMultiplier)
                }
                else {
                    Write-LogMessage -Type INFO -Message "Sleeping for $SecondsDelay seconds before next check..."
                    Start-Sleep $SecondsDelay
                }
            }
            else {
                $completed = $true
                Write-LogMessage -Type INFO -Message "The NSX Manager cluster '$server' state is 'STABLE'" -Colour GREEN
                return $true
            }
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing run of Wait-ForActiveNodeStatus" -Colour Yellow
    }
}
Export-ModuleMember -Function Wait-ForActiveNodeStatus

######### Start Useful Script Functions ##########

Function createHeader  {
    Param (
        [Parameter (Mandatory=$true)] [String] $user,
        [Parameter (Mandatory=$true)] [String] $pass
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$pass))) # Create Basic Authentication Encoded Credentials
    $headers = @{"Accept" = "application/json"}
    $headers.Add("Authorization", "Basic $base64AuthInfo")
    
    Return $headers
}
Export-ModuleMember -Function createHeader

######### End Useful Script Functions ##########
