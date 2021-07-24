
# Enable communication with self signed certs when using Powershell Core, if you require all communications to be secure and do not wish to
# allow communication with self signed certs remove lines 31-52 before importing the module

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
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/13/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Shutdown the nodes on a given server
    
        .DESCRIPTION
        The Stop-CloudComponent cmdlet shutdowns the given nodes on the server provided 
    
        .EXAMPLE
        PS C:\> Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
        This example connects to management vCenter Server and shuts down the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        PS C:\> Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
        This example connects to the ESXi Host and shuts down the nodes that match the pattern vCLS.*
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
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Stop-CloudComponent cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Stop-CloudComponent cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Stop-CloudComponent

Function Start-CloudComponent {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/13/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Startup the nodes on a given server
    
        .DESCRIPTION
        The Start-CloudComponent cmdlet starts up the given nodes on the server provided 
    
        .EXAMPLE
        PS C:\> Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
        This example connects to management vCenter Server and starts up the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        PS C:\> Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
        This example connects to the ESXi Host and starts up the nodes that match the pattern vCLS.*
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
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Start-CloudComponent cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Start-CloudComponent cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Start-CloudComponent

Function Set-MaintenanceMode {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/21/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        This is to set/unset maintenance mode on the host
    
        .DESCRIPTION
        The Set-MaintenanceMode cmdlet puts a host in maintenance mode or takes it out of maintenance mode 
    
        .EXAMPLE
        PS C:\> Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state ENABLE
        This example places the host in maintenance mode

       .EXAMPLE
        PS C:\> Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state DISABLE
        This example removes a host from maintenance mode
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateSet("ENABLE", "DISABLE")] [String]$state
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Set-MaintenanceMode cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Set-MaintenanceMode cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Set-MaintenanceMode

Function Get-VMRunningStatus {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/07/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Get running status of all the VM's matching the pattern on a given host
    
        .DESCRIPTION
        The Get-VMRunningStatus cmdlet gets the runnnig status of the given nodes matching the pattern on the host
    
        .EXAMPLE
        PS C:\> Get-VMRunningStatus -server sfo-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -pattern "^vCLS*"
        This example connects to the esxi host and searches for all vm's matching the pattern and their running status
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pattern,
        [Parameter (Mandatory = $false)] [ValidateSet("Running","NotRunning")] [String]$status="Running"
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Get-VMRunningStatus cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Get-VMRunningStatus cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VMRunningStatus

Function Invoke-EsxCommand {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/22/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Execute a given command on the esxi host
    
        .DESCRIPTION
        The Invoke-EsxCommand cmdlet executes a given command on a given ESXi host. If expected is
        not passed, then #exitstatus of 0 is considered as success 
    
        .EXAMPLE
        PS C:\> Invoke-EsxCommand -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$cmd,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$expected
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Invoke-EsxCommand cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Invoke-EsxCommand cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Invoke-EsxCommand

Function Get-VsanClusterMember {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Get list of VSAN Cluster members listed from a given ESXi host 
    
        .DESCRIPTION
		The Get-VsanClusterMember cmdlet uses the command "esxcli vsan cluster get", the output has a field SubClusterMemberHostNames
		see if this has all the members listed
    
        .EXAMPLE
        PS C:\> Get-VsanClusterMember -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -members "sfo01-w01-esx01.sfo.rainpole.io"
        This example connects to sfo01-w01-esx01.sfo.rainpole.io and checkahs that -members are listed
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$members
    )

     Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Get-VsanClusterMember cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Get-VsanClusterMember cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VsanClusterMember

Function Test-VsanHealth {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/13/2021
        Organization: VMware
        ===========================================================================
    
        .SYNOPSIS
        Check the health of the VSAN cluster
        
        .DESCRIPTION
        The Test-VsanHealth cmdlet checks the healh of the VSAN cluster
        
        .EXAMPLE
        PS C:\> Test-VsanHealth -cluster sfo-m01-cl01 -server sfo-m01-vc01 -user administrator@vsphere.local -pass VMw@re1!
        This example connects to Management Domain vCenter Server and checks the health of the VSAN cluster
    #>
    
    Param (
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Test-VsanHealth cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Test-VsanHealth cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanHealth
    
Function Test-VsanObjectResync {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V / Gary Blake (Enhancements)
        Date:   07/13/2021
        Organization: VMware
        ===========================================================================

        .SYNOPSIS
        Check object sync for VSAN cluster
        
        .DESCRIPTION
        The Test-VsanObjectResync cmdlet checks for resyncing of objects on the VSAN cluster
        
        .EXAMPLE
        PS C:\> Test-VsanObjectResync -cluster sfo-m01-cl01 -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example connects to Management Domain vCenter Server and checks the status of object syncing of the VSAN cluster
    #>
    Param(
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$cluster
    )
    
    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Test-VsanObjectResync cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Test-VsanObjectResync cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-VsanObjectResync

Function Test-WebUrl {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V / Gary Blake (Enhancements)
        Date:			07/24/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Test connection to a url 
    
        .DESCRIPTION
        The Test-WebUrl cmdlet tests the connection to the provided url
    
        .EXAMPLE
        PS C:\> Test-WebUrl -url "https://sfo-w01-nsx01.sfo.rainpole.io/login.jsp?local=true"
    #>
          
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$url
    )
    
    Try {
        Write-LogMessage -Type INFO -Message  "Starting Exeuction of Test-WebUrl cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Test-WebUrl cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Test-WebUrl

Function Get-VAMIServiceStatus {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Get the status of the service on a given CI server
    
        .DESCRIPTION
        Get the current status of the service on a given CI server. The status could be STARTED/STOPPED
    
        .EXAMPLE
        PS C:\> Get-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re123! -service 'wcp' -check_status 'STARTED'
        This example connects to tanzu workload domain VC, uses check_status parameter and tries to see if 'wcp' service is 'STARTED' or not.

        PS C:\> Get-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re123! -service 'wcp' -action 'STOP'
        This example connects to tanzu workload domain VC, uses action parameter and tries to STOP the 'wcp' service.

        PS C:\> Get-VAMIServiceStatus -server sfo-w01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re123! -service 'wcp' -action 'START'
        This example connects to tanzu workload domain VC, uses action parameter and tries to START the 'wcp' service.

    #>
	Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service,
        [Parameter (ParameterSetName = 'action', Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$action,
		[Parameter (ParameterSetName = 'checkStatus', Mandatory = $true)] [ValidateSet("STARTED", "STOPPED")] [String]$checkStatus
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Get-VAMIServiceStatus cmdlet" -Colour Yellow
        $checkServer = Test-Connection -ComputerName $server -Quiet -Count 1
        if ($checkServer -eq "True") {
            Write-LogMessage -Type INFO -Message "Attempting to connect to server '$server'"
            Connect-CisServer -Server $server -User $user -Password $pass | Out-Null
            if ($DefaultCisServers.Name -eq $server) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service,0)
                #$status = $serviceStatus.state
                if ($PSCmdlet.ParameterSetName -eq "action") {
                    if ($serviceStatus.state -match $action) {
                        Write-LogMessage -Type INFO -Message "The service $service is $action successfully" -Colour Yellow
                        Return 0
                    }
                    if ($action -eq 'START') {
                        Write-LogMessage -Type INFO -Message "Starting $service service ..." -Colour Yellow
                        $vMonAPI.start($service)
                    }
                    elseif ($action -eq 'STOP') {
                        Write-LogMessage -Type INFO -Message "Stopping $service service ..." -Colour Yellow
                        $vMonAPI.start($service)
                    }
                    Start-Sleep -s 10
                    #$serviceStatus = $vMonAPI.get($service,0)
                    #$status = $serviceStatus.state
                    if ($serviceStatus.state -match $action) {
                        Write-LogMessage -Type INFO -Message "The service:$service status:$status is matching" -Colour Yellow
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "The service:$service status_expected:$action   status_actual:$status is not matching" -Colour Red
                    }
                }
                if ($PSCmdlet.ParameterSetName -eq "checkStatus") {
                    Write-LogMessage -Type INFO -Message "Checking the service '$service' status is $checkStatus"
                    if ($serviceStatus.state -eq $checkStatus) {
                        Write-LogMessage -Type INFO -Message "Service: $service Expected Status: $checkStatus Actual Status: $($serviceStatus.state)" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message  "Service: $service Expected Status: $checkStatus Actual Status: $($serviceStatus.state)" -Colour Red
                    }
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Get-VAMIServiceStatus cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Get-VAMIServiceStatus

Function StartStop-VAMIServiceStatus {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        START/STOP the service on a given CI server
    
        .DESCRIPTION
        START/STOP the service on a given CI server
    
        .EXAMPLE
        PS C:\>StartStop-VAMIServiceStatus -Server $server -User $user  -Pass $pass -service $service -action <START/STOP>
    #>

	Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$service,
		[Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$action
    )

    Try {
		Connect-CisServer -server $server -user $user -pass $pass
		$vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
		$serviceStatus = $vMonAPI.get($service,0)
		$status = $serviceStatus.state
		if ($status -match $action) {
			Write-output "The servic $service is $action successfully"
			Return 0
		}
		if ($action -eq 'START') {
			Write-Output "Starting $service service ..."
			$vMonAPI.start($service)
			Start-Sleep -s 10
			$serviceStatus = $vMonAPI.get($service,0)
			$status = $serviceStatus.state
			if ($status -match $action) {
				write-output "The service:$service status:$status is matching"
			}
            else {
				write-error "The service:$service status_expected:$action   status_actual:$status is not matching"
				#exit
			}
		}
		if ($action -eq 'STOP') {
			Write-Output "Stoping $service service ..."
			$vMonAPI.stop($service)
			Start-Sleep -s 10
			$serviceStatus = $vMonAPI.get($service,0)	
			$status = $serviceStatus.state			
			if ($status -match $action) {
				write-output "The service:$service status:$status is matching"
			}
            else {
				write-error "The service:$service status_expected:$action   status_actual:$status is not matching"
				#exit
			}
		}
    } 
    Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
        Disconnect-CisServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function StartStop-VAMIServiceStatus

Function SetClusterState-VROPS {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Get status of all the VM's matching the pattern on a given host
    
        .DESCRIPTION
        Get status of the given component matching the pattern on the host. If no pattern is 
        specified 
    
        .EXAMPLE
        PS C:\> Verify-VMStatus -server sfo-w01-esx01.sfo.rainpole.io 
        -user root -pass VMw@re1! -pattern "^vCLS*"
        This example connects to the esxi host and searches for all vm's matching the pattern 
        and its status
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$mode
    )
	
    Try {
		$params = @{"online_state" = $mode;
			"online_state_reason" = "Maintenance";}
			
		$Global:myHeaders = createHeader $user $pass
		Write-Output $myHeaders
		
		$uri = "https://$server/casa/deployment/cluster/info"
		#https://xreg-vrops01.rainpole.io/casa/deployment/cluster/info

        #$response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body $json
		$response = Invoke-RestMethod -URI $uri -Headers $myHeaders -ContentType application/json 
		Write-Output "------------------------------------"
		Write-Output $response
		Write-Output "------------------------------------"
        if ($response.online_state -eq $mode) {
            Write-Output "The cluster is already in the $mode state"
        }
        else {
			$uri = "https://$server/casa/public/cluster/online_state"
			$response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body ($params | ConvertTo-Json)
			Write-Output "------------------------------------"
			Write-Output $response
			Write-Output "------------------------------------"
			if ($response.StatusCode -lt 300) {
				Write-Output "The cluster is set to $mode mode"
			}
            else {
				Write-Error "The cluster state could not be set"
			}
			#exit
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function SetClusterState-VROPS

Function Get-EnvironmentId {
 <#
    .NOTES
    ===========================================================================
    Created by:		Sowjanya V
    Date:			03/16/2021
    Organization:	VMware
    ===========================================================================
    
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
		[Parameter (Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$Name
    )
    
    Try {
		#write-output "11. $server, $user, $pass, $Name  "
		$Global:myHeaders = createHeader $user $pass
		#write-output $Global:myHeaders
        $uri = "https://$server/lcm/lcops/api/v2/environments"
		#write-output "1. $uri"
        $response = Invoke-RestMethod -Method GET -URI $uri -headers $myHeaders -ContentType application/json 
		#write-output "2." $response
        $env_id = $response  | foreach-object -process { if($_.environmentName -match $Name) { $_.environmentId }} 
        #write-output "3." $env_id
		return $env_id
    }
    Catch {
       $PSItem.InvocationInfo
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
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Get-EnvironmentId cmdlet" -Colour Yellow
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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Get-EnvironmentId cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Request-StartStopViaVRSLCM
New-Alias -Name ShutdownStartupProduct-ViaVRSLCM -Value Request-StartStopViaVRSLCM
Export-ModuleMember -Alias ShutdownStartupProduct-ViaVRSLCM  -Function Request-StartStopViaVRSLCM

Function Set-DrsAutomationLevel {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V / Gary Blake (Enhancements)
        Date:			07/22/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Set the DRS automation level
    
        .DESCRIPTION
        The Set-DrsAutomationLevel cmdlet sets the automation level of the cluster based on the setting provided 
    
        .EXAMPLE
        PS C:\> Set-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -cluster sfo-m01-cl01 -level PartiallyAutomated
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
        Write-LogMessage -Type INFO -Message "Starting Exeuction of Set-DrsAutomationLevel cmdlet" -Colour Yellow

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
        Write-LogMessage -Type INFO -Message "Finishing Exeuction of Set-DrsAutomationLevel cmdlet" -Colour Yellow
    }
}
Export-ModuleMember -Function Set-DrsAutomationLevel

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
        Write-Host -ForegroundColor $Colour " $Yype $Message" 
    }
    $logContent = '[' + $timeStamp + '] ' + $Yype + ' ' + $Message
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



########## Can be removed after testing ##########

