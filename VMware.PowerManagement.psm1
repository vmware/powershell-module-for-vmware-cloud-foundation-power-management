Function ShutdownStartup-SDDCComponent {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Shutdown/Startup the component on a given server
    
        .DESCRIPTION
        Shutdown/Startup the given component on the server ensuring all nodes of it are shutdown 
    
        .EXAMPLE
        PS C:\> ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02" -task Shutdown
        This example connects to management vCenter Server and shuts down the nodes sfo-m01-en01 and sfo-m01-en02

        .EXAMPLE
        PS C:\> ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02" -task Startup
        This example connects to management vCenter Server and powers on the nodes sfo-m01-en01 and sfo-m01-en02
    #>

    Param (
            [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
            [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
            [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
		    [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$timeout,
            [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String[]]$nodes,
            [Parameter(Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$task='Shutdown'
    )

    Try {

	    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
        Write-Output $server, $user, $pass, $nodes, $timeout

        if($task -eq "Shutdown") { 
	            if($nodes.Count -ne 0) {
                    foreach ($node in $nodes) {
			            $count=0
            
                        $vm_obj = Get-VMGuest -server $server -VM $node
                        Write-Output $node, $vm_obj
			            if($vm_obj.State -eq 'NotRunning'){
				            Write-Output "The VM $vm_obj is already in powered off state"

				            continue

			            }
			            Stop-VMGuest -server $server -VM $node -Confirm:$false
                        $vm_obj = Get-VMGuest -server $server -VM $node
                        Write-Output $vm_obj.State
                        Start-Sleep -Seconds 10
            
                        #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
			            while(( $vm_obj.State -ne 'NotRunning') -AND ($count -ne $timeout) ){
			                Start-Sleep -Seconds 1
                            Write-Output "Sleeping for 1 second"
				            $count = $count + 1
                            $vm_obj = Get-VMGuest -server $server -VM $node
                            Write-Output $vm_obj.State

			            }
			            if($count -eq $timeout) {
				            Write-Error "The VM did not get turned off with in stipulated timeout:$timeout value"	
                            #exit 			
			            } else {
				            Write-Output "The VM is successfully shutdown"
			            }
		            }
	            } 
        } elseif($task -eq "Startup") {
            	if($nodes.Count -ne 0) {
                    foreach ($node in $nodes) {
			            $count=0
            
                        $vm_obj = Get-VMGuest -server $server -VM $node
                        Write-Output $node, $vm_obj
			            if($vm_obj.State -eq 'Running'){
				            Write-Output "The VM $vm_obj is already in powered on state"

				            continue

			            }
			            Start-VM -VM $node -Confirm:$false
                        $vm_obj = Get-VMGuest -server $server -VM $node
                        Write-Output $vm_obj.State
                        Start-Sleep -Seconds 10
            
                        #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
			            while(( $vm_obj.State -ne 'Running') -AND ($count -ne $timeout) ){
							Start-Sleep -Seconds 1
                            Write-Output "Sleeping for 1 second"
				            $count = $count + 1
                            $vm_obj = Get-VMGuest -server $server -VM $node
                            Write-Output $vm_obj.State

			            }
			            if($count -eq $timeout) {
				            Write-Error "The VM did not get turned on with in stipulated timeout:$timeout value"	
                            break 			
			            } else {
				            Write-Output "The VM is successfully turned on"
			            }
		            }
	            } 

        } else {
            write-error("The task passed is neither Shutdown or Startup")
        }

    }  
        Catch {
			Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function ShutdownStartup-SDDCComponent

Function ShutdownStartup-ComponentOnHost {
    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Shutdown/Startup the component on a given host
    
        .DESCRIPTION
        Shutdown/Startup the given component matching the pattern on the host. If no pattern is 
        specified, the host in itself will be shutdown 
    
        .EXAMPLE
        PS C:\> ShutdownStartup-ComponentOnHost -server sfo-w01-esx01.sfo.rainpole.io 
        -user root -pass VMw@re1! -component NSXT-NODE 
        -nodeList "sfo-w01-en01", "sfo-w01-en02"
        This example connects to the esxi host and searches for all vm's matching the pattern 
        and shutdown the components
    #>

    Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
		    [Int]$timeout,
            [String]$pattern,
            [String]$task='Shutdown'
    )

    Try {

	    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
        Write-Output $server, $user, $pass, $nodes, $timeout
        #$nodes = Get-VM | select Name, PowerState | where Name -match $pattern
        if ($pattern) {
             $nodes = Get-VM -server $server | where Name -match $pattern | select Name, PowerState, VMHost | where VMHost -match $server
        } else {
            $nodes = @()
        }
        Write-Output $nodes.Name.Count


	
       if($task -eq 'Shutdown'){
	    if($nodes.Name.Count -ne 0) {
            foreach ($node in $nodes) {
			    $count=0
                
                $vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj
			    if($vm_obj.State -eq 'NotRunning'){
				    Write-Output "The VM $vm_obj is already in powered off state"

				    continue

			    }
        
			    Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server | Stop-VMGuest -Confirm:$false
                $vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj.State
            
                #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
			    while(( $vm_obj.State -ne 'NotRunning') -AND ($count -ne $timeout) ){
					Start-Sleep -Seconds 1
                    Write-Output "Sleeping for 1 second"
				    $count = $count + 1
                    $vm_obj = Get-VMGuest  -VM $node.Name | where VmUid -match $server
                    Write-Output $vm_obj.State

			    }
			    if($count -eq $timeout) {
				    Write-Error "The VM did not get turned off with in stipulated timeout:$timeout value"	
                    break 			
			    } else {
				    Write-Output "The VM is successfully shutdown"
			    }
		    }
		} elseif ($pattern) {
			Write-Output "There are no VM's matching the pattern"
	    } else {
            Write-Output "No Node is specified. Hence shutting down the ESXi host"
            Stop-VMHost -VMHost $server -Server $server -confirm:$false -RunAsync
        }

      } elseif ($task -eq 'Startup') {

      	    if($nodes.Name.Count -ne 0) {
				foreach ($node in $nodes) {
					$count=0
					
					$vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
					Write-Output $vm_obj
					if($vm_obj.State -eq 'Running'){
						Write-Output "The VM $vm_obj is already in powered on state"

						continue

			    }
        
			    Start-VM -VM $nodes.Name
                $vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj.State
            
                #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
			    while(( $vm_obj.State -ne 'Running') -AND ($count -ne $timeout) ){
			`	    Start-Sleep -Seconds 1
                    Write-Output "Sleeping for 1 second"
				    $count = $count + 1
                    $vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
                    Write-Output $vm_obj.State

			    }
			    if($count -eq $timeout) {
				    Write-Error "The VM did not get turned on with in stipulated timeout:$timeout value"	
                    break 			
			    } else {
				    Write-Output "The VM is successfully started"
			    }
		    }
		} elseif ($pattern) {
			Write-Output "There are no VM's matching the pattern"
	    } else {
            Write-Output "No Node is specified. Hence Starting the ESXi host"
            Start-VMHost -VMHost $server -Server $server -confirm:$false -RunAsync
        }

      } else {
            write-error("The task passed is neither Shutdown or Startup")
      }

    }  
        Catch {
            Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function ShutdownStartup-ComponentOnHost

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
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$mode
    )
	
	
	

    Try {
	
		$params = @{"online_state" = $mode;
			"online_state_reason" = "Maintenance";}
			
		$Global:myHeaders = createHeader $user $pass
		write-output $myHeaders
		
		$uri = "https://$server/casa/deployment/cluster/info"
		#https://xreg-vrops01.rainpole.io/casa/deployment/cluster/info

        #$response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body $json
		$response = Invoke-RestMethod -URI $uri -headers $myHeaders -ContentType application/json 
		write-output "------------------------------------"
		write-output $response
		write-output "------------------------------------"
        if($response.online_state -eq $mode) {
            Write-Output "The cluster is already in the $mode state"
        } else {
		
			$uri = "https://$server/casa/public/cluster/online_state"
			$response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body ($params | ConvertTo-Json)
			write-output "------------------------------------"
			write-output $response
			write-output "------------------------------------"
			if($response.StatusCode -lt 300) {
				Write-Output "The cluster is set to $mode mode"
			} else {
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

Function Verify-VMStatus {
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
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
		    [Int]$timeout,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pattern,
            [String]$status='Running'
    )

    Try {

	    Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
        Write-Output $server, $user, $pass, $nodes, $timeout
        #$nodes = Get-VM | select Name, PowerState | where Name -match $pattern
        
        $nodes = Get-VM | where Name -match $pattern | select Name, PowerState, VMHost
		if ($nodes.Name.Count -eq 0) {
            Write-output "No vm matching the pattern"
			#exit
        }
        Write-Output $nodes.Name.Count

	    #if($nodes.Name.Count -ne 0) {

		foreach ($node in $nodes) {	
			$vm_obj = Get-VMGuest -server $server -VM $node.Name | where VmUid -match $server
			Write-Output $vm_obj
			if($vm_obj.State -eq $status){
				Write-Output "The VM $vm_obj is is in the right power state"
				continue
			} else {
				Write-error "The VM $vm_obj is not in the right power state"
				#exit
			}
        }
    }  
        Catch {
            Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function Verify-VMStatus

Function Execute-OnEsx {

    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        Execute a given command on the esxi host
    
        .DESCRIPTION
        Execute the command on the given ESXi host. There are no direct 
        cmdlets to do the same. Hence written this function. If expected is
        not passed, then #exitstatus of 0 is considered as success 
    
        .EXAMPLE
        PS C:\> Execute-OnEsx -server "sfo01-w01-esx02.sfo.rainpole.io" -user "root" -pass "VMw@re123!" 
        -expected "Value of IgnoreClusterMemberListUpdates is 1" 
        -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
    #>

    Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$cmd,
            [String]$expected,
			[String]$timeout = 60
    )


    Try {
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
		$time_val = 0
        #$expected = "Value of IgnoreClusterMemberListUpdates is 1"

        $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force
        #Write-Output $session.SessionId 
        $out = Invoke-SSHCommand -index $session.SessionId -Command $cmd
        Write-Output $out.Output
		
		if($expected) {
			while($time_val -lt $timeout) {
				if($out.Output -match $expected) {
					Write-Output "Success. The recived and expected outputs are matching"
					break
				} else {
					$time_val = $time_val + 5
				}
			} 
			if($time_val -ge $timeout) {
				Write-Error "Failure. The received output is: $out.output \n The expexted output is $expected"
				#exit
			}
		} elseif ($out.exitStatus -eq 0) {
			Write-Output "Success. The command got successfully executed"
        } else  {
            Write-Error "Failure. The command could not be executed"
			#exit
        } 

    } Catch {
            Debug-CatchWriter -object $_
    } Finally {
            Remove-SSHSession -Index $session.SessionId
    }
}
Export-ModuleMember -Function Execute-OnEsx

Function Verify-VSANClusterMembers {

    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        This is to verify if a given ESXi host has all VSAN Cluster members listed
    
        .DESCRIPTION
		The command is  "esxcli vsan cluster get", the output has a field SubClusterMemberHostNames
		see if this has all the members listed
        
    
        .EXAMPLE
        PS C:\> Verify-VSANClusterMembers -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" 
        -members "sfo01-w01-esx01.sfo.rainpole.io" 

    #>

    Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
            [String[]]$members
    )


     Try {
		Connect-VIServer -server $server -user $user -pass $pass -protocol https
		$esxcli = Get-EsxCli -Server $server -VMHost (Get-VMHost $server) -V2
		$out =  $esxcli.vsan.cluster.get.Invoke()
		write-output($out.SubClusterMemberHostNames)
		write-output($members.gettype())
		write-output($out.SubClusterMemberHostNames.gettype())
		foreach($member in $members) {
			write-output($member)
			if($out.SubClusterMemberHostNames -match $member) {
				write-output("Host members match") 
			} else {
				write-error("Host members name don't match") 
				#exit
			}
		}
		

    } Catch {
            Debug-CatchWriter -object $_
    } Finally {
            Disconnect-VIServer -server $server -Confirm:$false
    }
}
Export-ModuleMember -Function Verify-VSANClusterMembers

Function Set-MaintainanceMode {

    <#
        .NOTES
        ===========================================================================
        Created by:  Sowjanya V
        Date:   03/15/2021
        Organization: VMware
        ===========================================================================
        
        .SYNOPSIS
        This is to set/unset maintainance mode on the host
    
        .DESCRIPTION
		The command is  "esxcli system maintenanceMode set -e false", to unset the 
		maintainance mode
		The command is  "esxcli system maintenanceMode set -e true", to set the 
		maintainance mode
    
        .EXAMPLE
        PS C:\> Set-MaintainanceMode -server "sfo01-w01-esx01.sfo.rainpole.io" -user "root" -pass "VMw@re123!" 
        -cmd "esxcli system maintenanceMode set -e false" 

    #>

    Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
			[Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$cmd
    )


    Try {
		Connect-VIServer -server $server -user $user -pass $pass -protocol https
		$host1 = Get-VMHost $server
		
		if($cmd -match "false") {
			
			if($host1.ConnectionState -eq "Maintenance") {

				Execute-OnEsx -server $server -user $user -pass $pass  -cmd $cmd
				Start-Sleep -s 10
				$count=1
				$host1 = Get-VMHost $server
				while($host1.ConnectionState -eq "Maintenance" -OR $count -le 5) {
					Start-Sleep -s 10
					$count = $count + 1
					$host1 = Get-VMHost $server
				}

			}
		
			if($host1.ConnectionState -eq "Maintenance") {
				write-error "The host could not be taken out of maintainance mode"
				#exit
			} else {
				write-output "The host was taken out of maintainance mode successfully"
			}
		} else {
			
			if($host1.ConnectionState -ne "Maintenance") {

				Execute-OnEsx -server $server -user $user -pass $pass  -cmd $cmd
				Start-Sleep -s 10
				$count=1
				$host1 = Get-VMHost $server
				while($host1.ConnectionState -ne "Maintenance" -OR $count -le 5) {
					Start-Sleep -s 10
					$count = $count + 1
					$host1 = Get-VMHost $server
				}

			}
		
			if($host1.ConnectionState -ne "Maintenance") {
				write-error "The host could not be put into maintainance mode"
				#exit
			} else {
				write-output "The host has been set to maintainance mode successfully"
			}
			
			
		}
		

    } Catch {
            Debug-CatchWriter -object $_
    } Finally {
            Disconnect-VIServer -server $server -Confirm:$false
    }
}
Export-ModuleMember -Function Set-MaintainanceMode

Function Connect-NSXTLocal {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Check to see if local url or nsx-t manager works fine
    
        .DESCRIPTION
        This is to ensure local url or nsx-t manager works fine after it is started
    
        .EXAMPLE
        PS C:\>Connect-NSXTLocal -url <url> 

    #>
          
    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$url
    )
    
    Try {
		#in core we do have -SkipCertificateCheck. No need of below block

		Ignore-CertificateError
		$response = Invoke-WebRequest -uri $url
		if($response.StatusCode -eq 200) {
			write-output "The URL is working"
		} else {
			write-error "The URL is not working"
			#exit
		}

    }
    Catch {
        $PSItem.InvocationInfo
		Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Connect-NSXTLocal

Function Get-VAMIServiceStatus {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Get the current status of the service on a given CI server
    
        .DESCRIPTION
        The status could be STARTED/STOPPED, check it out
    
        .EXAMPLE
        PS C:\>Get-VAMIServiceStatus -Server $server -User $user  -Pass $pass -service $service

    #>
	Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
			[Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$service,
			[string]$check_status
    )

    Try {
		#in core we do have -SkipCertificateCheck. No need of below block

		Connect-CisServer -server $server -user $user -pass $pass
		$vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
		$serviceStatus = $vMonAPI.get($service,0)
		$status = $serviceStatus.state
		if ($check_status) {
			if ($serviceStatus.state -eq $check_status) {
				write-output "The service:$service status:$status is matching"
			} else {
				write-error "The service:$service status_expected:$check_status   status_actual:$status is not matching"
				#exit
			}
		} else {
			return  $serviceStatus.state
		}
    } 
    Catch {
           Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-CisServer -Server $server -confirm:$false
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
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
			[Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$service,
			[string]$action
    )

    Try {


		Connect-CisServer -server $server -user $user -pass $pass
		$vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
		$serviceStatus = $vMonAPI.get($service,0)
		$status = $serviceStatus.state
		if ($status -match $action) {
			Write-output "The servic $service is $action successfully"
			return 0
		}
		if ($action -eq 'START') {
			Write-Output "Starting $service service ..."
			$vMonAPI.start($service)
			Start-Sleep -s 10
			$serviceStatus = $vMonAPI.get($service,0)
			$status = $serviceStatus.state
			if ($status -match $action) {
				write-output "The service:$service status:$status is matching"
			} else {
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
			} else {
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
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$server,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$user,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$pass,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
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

Function ShutdownStartupProduct-ViaVRSLCM
{
    <#
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
        PS C:\> ShutdownProduct_ViaVRSLCM -server <VRSLCM> -user <username> -pass <password> -product <VRA/VROPS/VRLI/VIDM> -mode <power-on/power-off>
        This example shutsdown a product via VRSLCM
        Sample URL formed on TB04 is as shown below
        Do Get on https://xreg-vrslcm01.rainpole.io/lcm/lcops/api/v2/environments
           and findout what is the id assosiated with Cross-Region Environment 

        $uri = "https://xreg-vrslcm01.rainpole.io/lcm/lcops/api/v2/environments/Cross-Region-Env1612043838679/products/vra/deployed-vms"

       

    #>
          
    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$server,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$user,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$pass,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$mode,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$product,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$env,
		[Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [int]$timeout
			

    )
    
    Try {
	
		write-output $server
		
        $env_id = Get-EnvironmentId -server $server -user $user -pass $pass -Name $env
		
		write-output $env_id
		
		$Global:myHeaders = createHeader $user $pass
		write-output $myHeaders
		$uri = "https://$server/lcm/lcops/api/v2/environments/$env_id/products/$product/$mode"

		
		write-output $uri
        $json = {}
        $response = Invoke-RestMethod -Method POST -URI $uri -headers $myHeaders -ContentType application/json -body $json
		
		write-output "------------------------------------"
		write-output $response
		write-output "------------------------------------"
        if($response.requestId) {
            Write-Output "Successfully initiated $mode on $product"
        } else {
            Write-Error "Unable to $mode on $product due to response "
			#exit
        }
		$id = $response.requestId
		#a893afc1-2035-4a9c-af91-0c55549e4e07
		$uri2 = "https://$server/lcm/request/api/v2/requests/$id"
		

		
		$count = 0
		while($count -le $timeout) {
			$count = $count + 60
			start-sleep -s 60
			$response2 = Invoke-RestMethod -Method GET -URI $uri2 -headers $myHeaders -ContentType application/json 
			if(($response2.state -eq 'COMPLETED') -or ($response2.state -eq 'FAILED')) {
				write-output $response2.state
				break
			}
		}
		if(($response2.state -eq 'COMPLETED') -and ($response2.errorCause -eq $null)) {
			write-output "The $mode on $product is successfull "
		} elseif (($response2.state -eq 'FAILED')) {
			write-output " could not $mode on $product because of "
			write-error $response2.errorCause.message
	    } else {
			write-error "could not $mode on $product within the timeout value"
		}
    }
    Catch {
       #$PSItem.InvocationInfo
	   Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function ShutdownStartupProduct-ViaVRSLCM

Function Set-DrsAutomationLevel {
    <#
        .NOTES
        ===========================================================================
        Created by:		Sowjanya V
        Date:			03/16/2021
        Organization:	VMware
        ===========================================================================
        
        .SYNOPSIS
        Set the automation level to manual or fully automated 
    
        .DESCRIPTION
        Set the automation level to manual or fully automated 
    
        .EXAMPLE
        PS C:\>Set-DrsAutomationLevel -Server $server -User $user  -Pass $pass -cluster <clustername> -level <Manual/FullyAutomated>

    #>
	Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
			[Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$cluster,
			[Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$level

    )

    Try {
        Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
		$out = Get-Cluster -Name $cluster
		if ($out.DrsAutomationLevel -eq $level) {
			write-Output "DrsAutomationLevel is already set to $level"
		} else {
			$task =  set-cluster -Cluster $cluster -DrsAutomationLevel $level -confirm:$false 
			if($task.DrsAutomationLevel -eq $level) {
				write-Output "DrsAutomationLevel is set to $level successfully"
			} else {
				write-Output "DrsAutomationLevel could not be set to $level"
			}
		}		
    } 
    Catch {
            Write-Error "An error occured. $_"
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
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

Function Test-VsanHealth {
<#
    .NOTES
    ===========================================================================
     Created by:    Sowjanya V
     Organization:  VMware

    ===========================================================================
    .DESCRIPTION
        This function demonstrates the use of vSAN Management API to retrieve
        the same information provided by the RVC command "vsan.health.health_summary"
		I used the same logic as used in the function "Get-VsanHealthSummary" written by william lam
    .PARAMETER Cluster
        The name of a vSAN Cluster
    .EXAMPLE
        Test-VsanHealth -Cluster sfo-m01-cl01 -Server sfo-m01-vc01 -user administrator@vsphere.local -pass VMw@re123!
#>
    param(
		[Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$server,
        [Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$user,
        [Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$pass,
        [Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$Cluster
    )
	Try {
		Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
		$vchs = Get-VSANView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"
		$cluster_view = (Get-Cluster -Name $Cluster).ExtensionData.MoRef
		$results = $vchs.VsanQueryVcClusterHealthSummary($cluster_view,$null,$null,$true,$null,$null,'defaultView')
		$healthCheckGroups = $results.groups
		$health_status = 'GREEN'

		$healthCheckResults = @()
		foreach($healthCheckGroup in $healthCheckGroups) {
			switch($healthCheckGroup.GroupHealth) {
				red {$healthStatus = "error"}
				yellow {$healthStatus = "warning"}
				green {$healthStatus = "passed"}
				info {$healthStatus = "passed"}
			}
			if($healthStatus -eq "red") {
				$health_status = 'RED'
			}
			$healtCheckGroupResult = [pscustomobject] @{
				HealthCHeck = $healthCheckGroup.GroupName
				Result = $healthStatus

			}
			$healthCheckResults+=$healtCheckGroupResult
		}
		Write-Host "`nOverall health:" $results.OverallHealth "("$results.OverallHealthDescription")"
		$healthCheckResults
		Write-Output ""
		if($health_status -eq 'GREEN' -and $results.OverallHealth -ne 'red'){	
			Write-Output "The VSAN Health is GOOD"
		} else {
			Write-Error "The VSAN Health is BAD"
			#exit
		}
	} Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function Test-VsanHealth

Function Test-ResyncingObjects {
<#
    .NOTES
    ===========================================================================
     Created by:    Sowjanya V
     Organization:  VMware

    ===========================================================================
    .DESCRIPTION
        This method is used to check if there are any resyncing objects are present before shutdown.
    .PARAMETER 
	Cluster
        The name of a vSAN Cluster
	Server	
		The name of the VC managing the cluster
	user
		The username of the server for login
	pass
		The password of the server for login
    .EXAMPLE
        Test-ResyncintObjects -cluster sfo-m01-cl01 -server "sfo-m01-vc01.sfo.rainpole.io" -user "administrator@vsphere.local" -pass "VMw@re123!"
#>
    param(
		[Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$server,
        [Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$user,
        [Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$pass,
        [Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[String]$Cluster
    )
	
	
	Try {
		Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
		$no_resyncing_objects = Get-VsanResyncingComponent -Server $server -cluster $Cluster
		write-output "The number of resyncing objects are"
		write-output $no_resyncing_objects
		if($no_resyncing_objects.count -eq 0){
			Write-Output "No resyncing objects"
		} else {
			Write-Error "There are some resyncing happening"
			#exit
		}
	} Catch {
        Debug-CatchWriter -object $_
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }

}
Export-ModuleMember -Function Test-ResyncingObjects

Function PowerOn-EsxiUsingILO {
<#
    .NOTES
    ===========================================================================
     Created by:    Sowjanya V
     Organization:  VMware

    ===========================================================================
    .DESCRIPTION
        This method is used to poweron the DELL ESxi server using ILO ip address using racadm 
		This is cli equivalent of admin console for DELL servers
    .PARAMETER 
	ilo_ip
        Out of Band Ipaddress
	user
		IDRAC console login user
	pass
		IDRAC console login password
    .EXAMPLE
        PowerOn-EsxiUsingILO -ilo_ip $ilo_ip  -ilo_user <drac_console_user>  -ilo_pass <drac_console_pass>
#>
    param(
		[Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ilo_ip,
		[Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ilo_user,
		[Parameter (Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ilo_pass
    )
	
	
	Try {

		$out = cmd /c "C:\Program Files\Dell\SysMgt\rac5\racadm" -r $ilo_ip -u $ilo_user -p $ilo_pass  --nocertwarn serveraction powerup
		if(  $out.contains("Server power operation successful") ) {
			Write-Output "Waiting for bootup to complete."
			Start-Sleep -Seconds 600
			Write-Output "bootup complete."
		} else {
			Write-Error "couldnot start the server"
			#exit
		}
	} Catch {
        Debug-CatchWriter -object $_
    }


}
Export-ModuleMember -Function PowerOn-EsxiUsingILO

Function createHeader {
    Param(
    [Parameter (Mandatory=$true)]
    [String] $user,
    [Parameter (Mandatory=$true)]
    [String] $pass
    )
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$pass))) # Create Basic Authentication Encoded Credentials
    $headers = @{"Accept" = "application/json"}
    $headers.Add("Authorization", "Basic $base64AuthInfo")
    
    Return $headers
}
Export-ModuleMember -Function createHeader

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
	[Parameter (Mandatory=$true)]
    [String] $server,
    [Parameter (Mandatory=$true)]
    [String] $user,
    [Parameter (Mandatory=$true)]
    [String] $pass
    )
	Try {
		$uri2 = "https://$server/api/v1/cluster/status"
		#$uri2="https://sfo-w01-nsx01.sfo.rainpole.io/api/v1/cluster/status"
		$myHeaders = createHeader $user $pass
		write-output $uri2
		write-output $myHeaders

		$response2 = Invoke-RestMethod -Method GET -URI $uri2 -headers $myHeaders -ContentType application/json 
		if($response2.mgmt_cluster_status.status -eq 'STABLE') {
			write-output "The cluster state is stable"
		} else {
			write-output "The cluster state is not stable"
		}
	} Catch {
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
        [Parameter (Mandatory = $false)] [ValidateSet("INFO", "ERROR", "WARNING", "EXCEPTION")] [String]$type = "INFO",
        [Parameter (Mandatory = $false)] [String]$Colour,
        [Parameter (Mandatory = $false)] [string]$Skipnewline
    )

    if (!$Colour) {
        $Colour = "Green"
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
    Add-Content -Path $logFile $logContent
}
Export-ModuleMember -Function Write-LogMessage

Function Debug-CatchWriter {
    Param (
        [Parameter(Mandatory = $true)]
        [PSObject]$object
    )

    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-LogMessage -Type EXCEPTION -Message "Error at Script Line $lineNumber" -Colour Red
    Write-LogMessage -Type EXCEPTION -Message "Relevant Command: $lineText" -Colour Red
    Write-LogMessage -Type EXCEPTION -Message "Error Message: $errorMessage" -Colour Red
}
Export-ModuleMember -Function Debug-CatchWriter

######### End Useful Script Functions ##########