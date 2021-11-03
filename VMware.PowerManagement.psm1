<#
    Script Module : VMware.PowerManagement
    Version       : 1.0
    Authors        : Sowjanya V, Gary Blake - Cloud Infrastructure Business Group
#>

# Enable communication with self signed certs when using Powershell Core, if you require all communications to be secure and do not wish to
# Allow communication with self signed certs remove lines 31-52 before importing the module

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
        Shutdown node(s) on a given server
    
        .DESCRIPTION
        The Stop-CloudComponent cmdlet shutdowns the given node(s) on the server provided 
    
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
        [Parameter (ParameterSetName = 'Node', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
        [Parameter (ParameterSetName = 'Pattern', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$pattern
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Stop-CloudComponent cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to shutdown nodes '$nodes'"
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                            $count=0
                            if ($checkVm =  Get-VM | Where-Object {$_.Name -eq $node}) {
                                $vm_obj = Get-VMGuest -Server $server -VM $node -ErrorAction SilentlyContinue
                                if ($vm_obj.State -eq 'NotRunning') {
                                    Write-LogMessage -Type INFO -Message "Node '$node' is already in Powered Off state" -Colour Cyan
                                    Continue
                                }
                                Write-LogMessage -Type INFO -Message "Attempting to shutdown node '$node'"
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
                    elseif ($pattern) {
                        Write-LogMessage -Type WARNING -Message "There are no nodes matching the pattern '$pattern' on host $server" -Colour Yellow
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Stop-CloudComponent cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Stop-CloudComponent

Function Start-CloudComponent {
    <#
        .SYNOPSIS
        Startup node(s) on a given server
    
        .DESCRIPTION
        The Start-CloudComponent cmdlet starts up the given node(s) on the server provided 
    
        .EXAMPLE
        Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
        This example connects to a vCenter Server and starts up the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Start-CloudComponent cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                if ($PSCmdlet.ParameterSetName -eq "Node") {
                    Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to start nodes '$nodes'"
                    if ($nodes.Count -ne 0) {
                        foreach ($node in $nodes) {
                                $count=0
                            if ($checkVm =  Get-VM | Where-Object {$_.Name -eq $node}) {
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
                                    Write-LogMessage -Type ERROR -Message "Node '$node' did not get turned on within the stipulated timeout: $timeout value" -Colour Red
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
                                Write-LogMessage -Type ERROR -Message "Node '$($node.name)' did not start up within the stipulated timeout: $timeout value"	-Colour Red
                            }
                            else {
                                Write-LogMessage -Type INFO -Message "Node '$($node.name)' has started successfully" -Colour Green
                            }
                        }
                    }
                    elseif ($pattern) {
                        Write-LogMessage -Type WARNING -Message "There are no nodes matching the pattern '$pattern' on host $server" -Colour Yellow
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Start-CloudComponent cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Start-CloudComponent

Function Set-MaintenanceMode {
    <#
        .SYNOPSIS
        Enable or Disable maintenance mode on an ESXi host
    
        .DESCRIPTION
        The Set-MaintenanceMode cmdlet place an ESXi host in maintenance mode or takes it out of maintenance mode 
    
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Set-MaintenanceMode cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to $state Maintenance mode"
                $hostStatus = (Get-VMHost -Server $server)
                if ($state -eq "ENABLE") {
                    if ($hostStatus.ConnectionState -eq "Connected") {
                        Write-LogMessage -Type INFO -Message "Attempting to place $server into Maintenance mode"
                        Get-View -ViewType HostSystem -Filter @{"Name" = $server }|?{!$_.Runtime.InMaintenanceMode}|%{$_.EnterMaintenanceMode(0, $false, (new-object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode=(new-object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction=[VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction})}))}
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Maintenance") {
                            Write-LogMessage -Type INFO -Message "The host $server has been placed in Maintenance mode successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The host $server was not placed in Maintenance mode, verify and try again" -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-LogMessage -Type INFO -Message "The host $server is already in Maintenance mode" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The host $server is not currently connected" -Colour Red
                    }
                }

                elseif ($state -eq "DISABLE") {
                    if ($hostStatus.ConnectionState -eq "Maintenance") {
                        Write-LogMessage -Type INFO -Message "Attempting to take $server out of Maintenance mode"
                        $task = Set-VMHost -VMHost $server -State "Connected" -RunAsync -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        $vmhost = Wait-Task $task
                        $hostStatus = (Get-VMHost -Server $server)
                        if ($hostStatus.ConnectionState -eq "Connected") {
                            Write-LogMessage -Type INFO -Message "The host $server has been taken out of Maintenance mode successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The host $server was not taken out of Maintenance mode, verify and try again" -Colour Red
                        }
                    }
                    elseif ($hostStatus.ConnectionState -eq "Connected") {
                        Write-LogMessage -Type INFO -Message "The host $server is already out of Maintenance mode" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The host $server is not currently connected" -Colour Red
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Set-MaintenanceMode cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Set-DrsAutomationLevel cmdlet" -Colour Yellow

        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                $drsStatus = Get-Cluster -Name $cluster -ErrorAction SilentlyContinue
                if ($drsStatus) {
                    if ($drsStatus.DrsAutomationLevel -eq $level) {
                        Write-LogMessage -Type INFO -Message "The DRS Automation Level for cluster '$cluster' is already set to '$level'" -Colour Cyan
                    }
                    else {
                        $drsStatus = Set-Cluster -Cluster $cluster -DrsAutomationLevel $level -Confirm:$false 
                        if ($drsStatus.DrsAutomationLevel -eq $level) {
                            Write-LogMessage -Type INFO -Message "The DRS Automation Level for cluster '$cluster' has been set to '$level' successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Type ERROR -Message "The DRS Automation Level for cluster '$cluster' could not be set to '$level'" -Colour Red
                        }
                    }
                    Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                else {
                    Write-LogMessage -Type ERROR -Message "Cluster '$cluster' not found on server '$server', please check your details and try again" -Colour Red
                }
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server '$server', due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Set-DrsAutomationLevel cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Get-VMRunningStatus cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
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
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Get-VMRunningStatus cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VMRunningStatus

Function Invoke-EsxCommand {
    <#
        .SYNOPSIS
        Execute a given command on an ESXi host
    
        .DESCRIPTION
        The Invoke-EsxCommand cmdlet executes a given command on a given ESXi host. If expected is
        not passed, then #exitstatus of 0 is considered as success 
    
        .EXAMPLE
        Invoke-EsxCommand -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cmd,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$expected
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Invoke-EsxCommand cmdlet" -Colour Yellow
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
        $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force -WarningAction SilentlyContinue
        if ($session) {
            Write-LogMessage -Type INFO -Message "Attempting to execute command '$cmd' on server '$server'"
            $commandOutput = Invoke-SSHCommand -Index $session.SessionId -Command $cmd
            $timeoutValue = 0
            if ($expected) {
                Write-LogMessage -Type INFO -Message "Command '$cmd' executed with expected output on server '$server' successfully" -Colour Green
            }
            elseif ($commandOutput.exitStatus -eq 0) {
                Write-LogMessage -Type INFO -Message "Success. The command got successfully executed" -Colour Green
            }
            else  {
                Write-LogMessage -Type ERROR -Message "Failure. The command could not be executed" -Colour Red
            }
            Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
            Remove-SSHSession -Index $session.SessionId | Out-Null   
        }
        else {
            Write-LogMessage -Type ERROR -Message "Not connected to server '$server', due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing Execution of Invoke-EsxCommand cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Invoke-EsxCommand

Function Get-VsanClusterMember {
    <#
        .SYNOPSIS
        Get list of VSAN cluster members from a given ESXi host 
    
        .DESCRIPTION
		The Get-VsanClusterMember cmdlet uses the command "esxcli vsan cluster get", the output has a field SubClusterMemberHostNames
		to see if this has all the members listed
    
        .EXAMPLE
        Get-VsanClusterMember -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -members "sfo01-w01-esx01.sfo.rainpole.io"
        This example connects to an ESXI host and checks that all members are listed
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$members
    )

     Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Get-VsanClusterMember cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and checking VSAN Cluster members are present"
                $esxcli = Get-EsxCli -Server $server -VMHost (Get-VMHost $server) -V2
                $out =  $esxcli.vsan.cluster.get.Invoke()
                foreach ($member in $members) {
                    if ($out.SubClusterMemberHostNames -eq $member) {
                        Write-LogMessage -Type INFO -Message "VSAN Cluster Host member '$member' matches" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type INFO -Message "VSAN Cluster Host member '$member' does not match" -Colour Red
                    }
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Get-VsanClusterMember cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VsanClusterMember

Function Test-VsanHealth {
    <#
        .SYNOPSIS
        Check the health of the VSAN cluster
        
        .DESCRIPTION
        The Test-VsanHealth cmdlet checks the healh of the VSAN cluster
        
        .EXAMPLE
        Test-VsanHealth -cluster sfo-m01-cl01 -server sfo-m01-vc01 -user administrator@vsphere.local -pass VMw@re1!
        This example connects to a vCenter Server and checks the health of the VSAN cluster
    #>
    
    Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Test-VsanHealth cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to check the VSAN cluster health"
                $vchs = Get-VSANView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
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
                    Write-LogMessage -Type INFO -Message "The VSAN Health Status for $cluster is GOOD" -Colour Green
                }
                else {
                    Write-LogMessage -Type ERROR -Message "The VSAN Health Status for $cluster is BAD" -Colour Red
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Test-VsanHealth cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanHealth
    
Function Test-VsanObjectResync {
    <#
        .SYNOPSIS
        Check object sync for VSAN cluster
        
        .DESCRIPTION
        The Test-VsanObjectResync cmdlet checks for resyncing of objects on the VSAN cluster
        
        .EXAMPLE
        Test-VsanObjectResync -cluster sfo-m01-cl01 -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example connects to a vCenter Server and checks the status of object syncing for the VSAN cluster
    #>
    Param(
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )
    
    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Test-VsanObjectResync cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-VIServer -Server $server -Protocol https -User $user -Password $pass | Out-Null
            if ($DefaultVIServer.Name -eq $server) {
                Write-LogMessage -Type INFO -Message "Connected to server '$server' and attempting to check the VSAN cluster health"
                $no_resyncing_objects = Get-VsanResyncingComponent -Server $server -cluster $cluster
                Write-LogMessage -Type INFO -Message "The number of resyncing objects are $no_resyncing_objects"
                if ($no_resyncing_objects.count -eq 0){
                    Write-LogMessage -Type INFO -Message "No resyncing objects" -Colour Green
                }
                else {
                    Write-LogMessage -Type ERROR -Message "There are some resyncing happening" -Colour Red
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Test-VsanObjectResync cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanObjectResync

Function Test-WebUrl {
    <#
        .SYNOPSIS
        Test connection to a url 
    
        .DESCRIPTION
        The Test-WebUrl cmdlet tests the connection to the provided url
    
        .EXAMPLE
        Test-WebUrl -url "https://sfo-w01-nsx01.sfo.rainpole.io/login.jsp?local=true"
        This example tests a connection to the login page for NSX Manager
    #>
          
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$url
    )
    
    Try {
        Write-LogMessage -Type INFO -Message  "Starting Execution of Test-WebUrl cmdlet" -Colour Yellow
        Write-LogMessage -Type INFO -Message "Attempting connect to url '$url'"
		$response = Invoke-WebRequest -uri $url -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		if ($response.StatusCode -eq 200) {
            Write-LogMessage -Type INFO -Message "Response Code: $($response.StatusCode) for URL '$url' - SUCCESS" -Colour Green
		}
        else {
            Write-LogMessage -Type ERROR -Message "Response Code: $($response.StatusCode) for URL '$url'" -Colour Red
		}
    }
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing Execution of Test-WebUrl cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-WebUrl

Function Get-VamiServiceStatus {
    <#
        .SYNOPSIS
        Get the status of the service on a given vCenter Server
    
        .DESCRIPTION
        The Get-VamiServiceStatus cmdlet gets the current status of the service on a given vCenter Server. The status can be STARTED/STOPPED
    
        .EXAMPLE
        Get-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -checkStatus STARTED
        This example connects to a vCenter Server and checks the wcp service is STARTED
    #>
	Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service,
		[Parameter (Mandatory = $true)] [ValidateSet("STARTED", "STOPPED")] [String]$checkStatus
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Get-VAMIServiceStatus cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-CisServer -Server $server -User $user -Password $pass | Out-Null
            if ($DefaultCisServers.Name -eq $server) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service,0)
                Write-LogMessage -Type INFO -Message "Checking the service '$service' status is $checkStatus"
                if ($serviceStatus.state -eq $checkStatus) {
                    Write-LogMessage -Type INFO -Message "Service: $service Expected Status: $checkStatus Actual Status: $($serviceStatus.state)" -Colour Green
                }
                else {
                    Write-LogMessage -Type ERROR -Message  "Service: $service Expected Status: $checkStatus Actual Status: $($serviceStatus.state)" -Colour Red
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-CisServer -Server $server -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Get-VAMIServiceStatus cmdlet" -Colour Yellow
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
        Set-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action STOP
        This example connects to a vCenter Server and attempts to STOP the wcp service

        .EXAMPLE
        Set-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action START
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Get-VAMIServiceStatus cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-CisServer -Server $server -User $user -Password $pass | Out-Null
            if ($DefaultCisServers.Name -eq $server) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service,0)                
                if ($serviceStatus.state -match $action) {
                    Write-LogMessage -Type INFO -Message "The service $service is $action successfully" -Colour Yellow
                }
                if ($action -eq 'START') {
                    Write-LogMessage -Type INFO -Message "Attempting to Start $service service ..." -Colour Yellow
                    $vMonAPI.start($service)
                }
                elseif ($action -eq 'STOP') {
                    Write-LogMessage -Type INFO -Message "Attempting to Stop $service service ..." -Colour Yellow
                    $vMonAPI.stop($service)
                }
                Start-Sleep -s 10
                if ($serviceStatus.state -match $action) {
                    Write-LogMessage -Type INFO -Message "The service: $service status: $status is matching" -Colour Yellow
                }
                else {
                    Write-LogMessage -Type ERROR -Message "The service: $service status_expected: $action status_actual: $status is not matching" -Colour Red
                }
                Write-LogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-CisServer -Server $server -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Get-VAMIServiceStatus cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Starting Execution of Set-vROPSClusterState cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
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
                    $response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body ($params | ConvertTo-Json)
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
                Write-LogMessage -Type ERROR -Message  "Not connected to server $server, due to an incorrect user name or password. Verify your credentials and try again" -Colour Red
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
        Write-LogMessage -Type INFO -Message "Finishing Execution of Set-vROPSClusterState cmdlet" -Colour Yellow
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
    $response
}
Export-ModuleMember -Function Get-vROPSClusterDetail 

Function Get-EnvironmentId {
 <#
    .SYNOPSIS
    Cross Region Envionment or globalenvironment Id of any product in VRSLCM need to be found

    .DESCRIPTION
    This is to fetch right environment id for cross region env, which is needed for shutting down the VRA components via VRSLCM
    This also fetches the global environment id for VIDM

    .EXAMPLE
    PS C:\>Get_EnvironmentId -host <VRSLCM> -user <username> -pass <password> -product <VRA/VROPS/VRLI/VIDM>
    This example shows how to fetch environment id for cross region VRSLCM
    Sample URL formed on TB04 is as shown below -- vcfadmin@local VMw@re123!
    Do Get on https://xreg-vrslcm01.rainpole.io/lcm/lcops/api/v2/environments
        and findout what is the id assosiated with Cross-Region Environment      
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

Function Request-StartStopViaVRSLCM
{
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Shutting down VRA or VIDM via VRSLCM
    
        .DESCRIPTION
        There function is used to shutdown or startup VRA or VIDM components via VRSLCM. 

        .EXAMPLE
        PS C:\> Request-StartStopViaVRSLCM -server xreg-vrslcm01.rainpole.io -user 'vcfadmin@local' -pass 'VMw@re123!' -env "global" -product 'vidm' -mode "power-on"
        In this example we connect to VRSLCM and are starting either VIDM component 

        PS C:\> Request-StartStopViaVRSLCM -server xreg-vrslcm01.rainpole.io -user 'vcfadmin@local' -pass 'VMw@re123!' -env "global" -product 'vidm' -mode "power-off"
        In this example we connect to VRSLCM and gracefully shutdown VIDM component 

        PS C:\> Request-StartStopViaVRSLCM -server xreg-vrslcm01.rainpole.io -user 'vcfadmin@local' -pass 'VMw@re123!' -env "Cross" -product 'VRA' -mode "power-on"
        In this example we connect to VRSLCM and are starting either VRA component 

        PS C:\> Request-StartStopViaVRSLCM -server xreg-vrslcm01.rainpole.io -user 'vcfadmin@local' -pass 'VMw@re123!' -env "Cross" -product 'VRA' -mode "power-off"
        In this example we connect to VRSLCM and gracefully shutdown VRA component 
    #>
          
    Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$mode,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$product,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$env,
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [Int]$timeout
    )
    
    Try {
        Write-LogMessage -Type INFO -Message "Starting Execution of Get-EnvironmentId cmdlet" -Colour Yellow
		#Write-Output $server
        $env_id = Get-EnvironmentId -server $server -user $user -pass $pass -Name $env
		#Write-Output $env_id
		
		$Global:myHeaders = createHeader $user $pass
		#Write-Output $myHeaders
		$uri = "https://$server/lcm/lcops/api/v2/environments/$env_id/products/$product/$mode"

		
		#Write-Output $uri
        $json = {}
        $response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body $json
		
		#Write-Output "------------------------------------"
		#Write-Output $response
		#Write-Output "------------------------------------"
        if ($response.requestId) {
            Write-LogMessage -Type INFO -Message "Successfully initiated $mode on $product" -Colour Yellow
        }
        else {
            Write-LogMessage -Type ERROR -Message "Unable to $mode on $product due to response " -Colour Red
        }
		$id = $response.requestId
		#a893afc1-2035-4a9c-af91-0c55549e4e07
		$uri2 = "https://$server/lcm/request/api/v2/requests/$id"
		
		$count = 0
		While ($count -le $timeout) {
			$count = $count + 60
			Start-Sleep -s 60
			$response2 = Invoke-RestMethod -Method GET -URI $uri2 -headers $myHeaders -ContentType application/json 
			if (($response2.state -eq 'COMPLETED') -or ($response2.state -eq 'FAILED')) {
                Write-LogMessage -Type INFO -Message "The API has exited with the following state" -Colour Yellow
                Write-LogMessage -Type INFO -Message $response2.state -Colour Yellow
				Break
			}
		}
		if (($response2.state -eq 'COMPLETED') -and ($response2.errorCause -eq $null)) {
            Write-LogMessage -Type INFO -Message "The $mode on $product is successfull" -Colour Yellow
		}
        elseif (($response2.state -eq 'FAILED')) {
            Write-LogMessage -Type ERROR -Message "Could not $mode on $product because of" -Colour Red
            Write-LogMessage -Type ERROR -Message $response2.errorCause.message -Colour Red
	    }
        else {
            Write-LogMessage -Type ERROR -Message "Could not $mode on $product within the timeout value" -Colour Red
		}
    }
    Catch {
       #$PSItem.InvocationInfo
	   Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing Execution of Get-EnvironmentId cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Request-StartStopViaVRSLCM
New-Alias -Name ShutdownStartupProduct-ViaVRSLCM -Value Request-StartStopViaVRSLCM
Export-ModuleMember -Alias ShutdownStartupProduct-ViaVRSLCM  -Function Request-StartStopViaVRSLCM


<#Function ShutdownStartupProduct-ViaVRSLCM
{
    
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Shutting down VRA or VROPS via VRSLCM
    
        .DESCRIPTION
        There are no POWER CLI or POWER SHELL cmdlet to power off the products via VRSLCM. Hence writing my own
    
        .EXAMPLE
        PS C:\> ShutdownProduct_ViaVRSLCM -host <VRSLCM> -user <username> -pass <password> -component <VRA/VROPS/VRLI/VIDM>
        This example shutsdown a product via VRSLCM
        Sample URL formed on TB04 is as shown below
        Do Get on https://xreg-vrslcm01.rainpole.io/lcm/lcops/api/v2/environments
           and findout what is the id assosiated with Cross-Region Environment 

        $uri = "https://xreg-vrslcm01.rainpole.io/lcm/lcops/api/v2/environments/Cross-Region-Env1612043838679/products/vra/deployed-vms"

    
    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$host,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$user,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$pass,
        [string]$on,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$product

    )
    
    Try {
        $env_id = Get-EnvironmentId -user $user -pass $pass -host $host -Name "Cross"
		
		write-output $env_id
		
		$Global:myHeaders = createHeader $user $pass
		write-output $myHeaders
		if($on) {
			$uri = "https://$host/lcm/lcops/api/v2/environments/$env_id/products/$product/power-on"
            $success_msg = "The $product is successfully started"
            $failure_msg = "The $product could not be started within the timeout value"
            $succ_init_msg = "Successfully initiated startup of the product $product"
            $fail_init_msg = "Unable to starup $product due to response"

		} else {
			$uri = "https://$host/lcm/lcops/api/v2/environments/$env_id/products/$product/power-off"
            $success_msg = "The $product is successfully shutdown"
            $failure_msg = "The $product could not be shutdown within the timeout value"
            $succ_init_msg = "Successfully initiated shutdown of the product $product"
            $fail_init_msg = "Unable to shutdown $product due to response"
		}
		write-output $uri
        $json = {}
        $response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body $json
		
		write-output "------------------------------------"
		write-output $response
		write-output "------------------------------------"
        if($response.requestId) {
            Write-Output $succ_init_msg
        } else {
            Write-Error $fail_init_msg
			#exit
        }
		$id = $response.requestId
		$uri2 = "https://$host/lcm/request/api/v2/requests/$id"
		$count = 0
		$timeout = 1800
		while($count -le $timeout) {
			$count = $count + 60
			start-sleep -s 60
			$response2 = Invoke-RestMethod -Method GET -URI $uri2 -headers $myHeaders -ContentType application/json 
			if(($response2.state -eq 'COMPLETED') ) {
				break
			}
		}
		if(($response2.state -eq 'COMPLETED') -and ($response2.errorCause -eq $null) ) {
			write-output $success_msg
		} else {
			write-output $failure_msg
		}
    }
    Catch {
       $PSItem.InvocationInfo
	   Debug-CatchWriter -object $_
    }
}
#>

Function PowerOn-EsxiUsingILO {
    <#
        .NOTES
        ===========================================================================
        Created by:    Sowjanya V
        Organization:  VMware

    ===========================================================================
    .DESCRIPTION
        This method is used to poweron the DELL ESxi server using ILO ip address using racadm cli. This is cli equivalent of admin console for DELL servers

    .EXAMPLE
        PowerOn-EsxiUsingILO -ilo_ip $ilo_ip  -ilo_user <drac_console_user>  -ilo_pass <drac_console_pass>
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
        } elseif (Test-path  $default_path) {
            Write-LogMessage -Type INFO -Message "The racadm.exe is present in the default path" -Colour Yellow
        } else {
            Write-LogMessage -Type Error -Message "The racadm.exe is not present in $exe_path or the default path $default_path" -Colour Red
        }
		$out = cmd /c $default_path -r $ilo_ip -u $ilo_user -p $ilo_pass  --nocertwarn serveraction powerup
		if ( $out.contains("Server power operation successful")) {
            Write-LogMessage -Type INFO -Message "power-on on host $ilo_ip is successfully initiated" -Colour Yellow
			Start-Sleep -Seconds 600
            Write-LogMessage -Type INFO -Message "bootup complete." -Colour Yellow
		}
        else {
            Write-LogMessage -Type Error -Message "Couldn't poweron the server $ilo_ip" -Colour Red
		}
	}
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of PowerOn-EsxiUsingILO cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function PowerOn-EsxiUsingILO

Function Ignore-CertificateError {
	add-type @"
		using System.Net;
		using System.Security.Cryptography.X509Certificates;
		public class TrustAllCertsPolicy : ICertificatePolicy {
			public bool CheckValidationResult(
				ServicePoint srvPoint, X509Certificate certificate,
				WebRequest request, int certificateProblem) {
				return true;
			}
		}
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}
Export-ModuleMember -Function Ignore-CertificateError

Function Get-NSXTMgrClusterStatus {
    <#
        .NOTES
        ===========================================================================
        Created by:    Sowjanya V
        Organization:  VMware

        ===========================================================================
        .DESCRIPTION
            This method is used to fetch the cluster status of nsx manager after restart
        .PARAMETER 
        server
            The nsxt manager hostname
        user
            nsx manager login user
        pass
            nsx manager login password
        .EXAMPLE
            Get-NSXTMgrClusterStatus -server $server  -user $user  -pass $pass
            sample url - "https://sfo-m01-nsx01.sfo.rainpole.io/api/v1/cluster/status"
    #>

	Param(
	    [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String] $pass
    )
    
	Try {
		$uri2 = "https://$server/api/v1/cluster/status"
		#$uri2="https://sfo-w01-nsx01.sfo.rainpole.io/api/v1/cluster/status"
		$myHeaders = createHeader $user $pass
		write-output $uri2
		write-output $myHeaders

		$response2 = Invoke-RestMethod -Method GET -URI $uri2 -headers $myHeaders -ContentType application/json 
		if ($response2.mgmt_cluster_status.status -eq 'STABLE') {
			Write-Output "The cluster state is stable"
		}
        else {
			Write-Output "The cluster state is not stable"
		}
	} 
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Get-NSXTMgrClusterStatus

######### Start Useful Script Functions ##########

Function Start-SetupLogFile ($path, $scriptName) {
    $filetimeStamp = Get-Date -Format "MM-dd-yyyy_hh_mm_ss"
    $Global:logFile = $path + '\logs\' + $scriptName + '-' + $filetimeStamp + '.log'
    $logFolder = $path + '\logs'
    $logFolderExists = Test-Path $logFolder
    if (!$logFolderExists) {
        New-Item -ItemType Directory -Path $logFolder | Out-Null
    }
    New-Item -Type File -Path $logFile | Out-Null
    $logContent = '[' + $filetimeStamp + '] Beginning of Log File'
    Add-Content -Path $logFile $logContent | Out-Null
}
Export-ModuleMember -Function Start-SetupLogFile

Function Write-LogMessage {
    Param (
        [Parameter (Mandatory = $true)] [AllowEmptyString()] [String]$Message,
        [Parameter (Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION")] [String]$Type,
        [Parameter (Mandatory = $false)] [String]$Colour,
        [Parameter (Mandatory = $false)] [string]$Skipnewline
    )

    if (!$Colour) {
        $Colour = "White"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    if ($Skipnewline) {
        Write-Host -NoNewline -ForegroundColor $Colour " $Type $Message"        
    }
    else {
        Write-Host -ForegroundColor $Colour " $Type $Message" 
    }
    $logContent = '[' + $timeStamp + '] ' + $Type + ' ' + $Message
    if ($logFile) {
        Add-Content -Path $logFile $logContent
    }
}
Export-ModuleMember -Function Write-LogMessage

Function Debug-CatchWriter {
    Param (
        [Parameter (Mandatory = $true)] [PSObject]$object
    )

    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-LogMessage -Type EXCEPTION -Message "Error at Script Line $lineNumber" -Colour Red
    Write-LogMessage -Type EXCEPTION -Message "Relevant Command: $lineText" -Colour Red
    Write-LogMessage -Type EXCEPTION -Message "Error Message: $errorMessage" -Colour Red
}
Export-ModuleMember -Function Debug-CatchWriter

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