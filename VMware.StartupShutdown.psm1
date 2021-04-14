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
        PS C:\> ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -user 
        adminstrator@vsphere.local -pass VMw@re1! -component NSXT-NODE 
        -nodeList "sfo-w01-en01", "sfo-w01-en02"
        This example connects to management VC and shutdown the component NSX-T by 
        shutting down all the dependent components
    #>

    Param (
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$server,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$user,
            [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][String]$pass,
      [Int]$timeout,
            [String[]]$nodes,
            [String]$task='Shutdown'           
    )

    Try {
     Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
        Write-Output $server, $user, $pass, $nodes, $timeout
 
        if($task -eq "Shutdown") { 
             if($nodes.Count -ne 0) {
                    foreach ($node in $nodes) {
               $count=0
            
                        $vm_obj = Get-VMGuest -VM $node
                        Write-Output $node, $vm_obj
               if($vm_obj.State  -eq  'NotRunning'){
                Write-Output "The VM $vm_obj is already in powered off state"

                continue

               }
               Stop-VMGuest  -VM  $node  -Confirm:$false
                        $vm_obj = Get-VMGuest -VM $node
                        Write-Output $vm_obj.State
                        Start-Sleep  -Seconds  10
            
                        #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
               while(( $vm_obj.State -ne  'NotRunning') -AND ($count -ne $timeout) ){
                       Start-Sleep  -Seconds  1
                            Write-Output "Sleeping for 1 second"
                $count = $count + 1
                            $vm_obj = Get-VMGuest -VM $node
                            Write-Output $vm_obj.State

               }
               if($count -eq $timeout) {
                Write-Error "The VM did not get turned off with in stipulated timeout:$timeout value" 
                            break    
               } else {
                Write-Output "The VM is successfully shutdown"
               }
              }
             } 
        } elseif($task -eq "startup") {
             if($nodes.Count -ne 0) {
                    foreach ($node in $nodes) {
               $count=0
            
                        $vm_obj = Get-VMGuest -VM $node
                        Write-Output $node, $vm_obj
               if($vm_obj.State  -eq  'Running'){
                Write-Output "The VM $vm_obj is already in powered on state"

                continue

               }
               Start-VM  -VM  $node -Confirm:$false
                        $vm_obj = Get-VMGuest -VM $node
                        Write-Output $vm_obj.State
                        Start-Sleep  -Seconds  10
            
                        #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
               while(( $vm_obj.State -ne  'Running') -AND ($count -ne $timeout) ){
                       Start-Sleep  -Seconds  1
                            Write-Output "Sleeping for 1 second"
                $count = $count + 1
                            $vm_obj = Get-VMGuest -VM $node
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
            Write-Error "An error occured. $_"
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
            [String[]]$pattern="",
            [String]$task='Shutdown'
    )

    Try {

     Connect-VIServer -Server $server -Protocol https -User $user -Password $pass
        Write-Output $server, $user, $pass, $nodes, $timeout
        #$nodes = Get-VM | select Name, PowerState | where Name -match $pattern
        if ($pattern -eq "") {
             $nodes = Get-VM | where Name -match $pattern | select Name, PowerState, VMHost | where VMHost -match $server
        } else {
            $nodes = @()
        }
        Write-Output $nodes


 
       if($task -eq 'Shutdown'){
     if($nodes.Count -ne 0) {
            foreach ($node in $nodes) {
       $count=0
                
                $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj
       if($vm_obj.State  -eq  'NotRunning'){
        Write-Output "The VM $vm_obj is already in powered off state"

        continue

       }
        
       Get-VMGuest -VM $node.Name | where VmUid -match $server | Stop-VMGuest  -Confirm:$false
                $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj.State
            
                #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
       while(( $vm_obj.State -ne  'NotRunning') -AND ($count -ne $timeout) ){
               Start-Sleep  -Seconds  1
                    Write-Output "Sleeping for 1 second"
        $count = $count + 1
                    $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                    Write-Output $vm_obj.State

       }
       if($count -eq $timeout) {
        Write-Error "The VM did not get turned off with in stipulated timeout:$timeout value" 
                    break    
       } else {
        Write-Output "The VM is successfully shutdown"
       }
      }
     } else {
            Write-Output "No Node is specified. Hence shutting down the ESXi host"
            Stop-VMHost -VMHost $server -Server $server -confirm:$false -RunAsync
        }

      } elseif ($task -eq 'Startup') {

           if($nodes.Count -ne 0) {
            foreach ($node in $nodes) {
       $count=0
                
                $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj
       if($vm_obj.State  -eq  'Running'){
        Write-Output "The VM $vm_obj is already in powered on state"

        continue

       }
        
       Get-VMGuest -VM $node.Name | where VmUid -match $server | Start-VM  -Confirm:$false
                $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                Write-Output $vm_obj.State
            
                #Get-VMGuest -VM $node | where $_.State -eq "NotRunning"
       while(( $vm_obj.State -ne  'Running') -AND ($count -ne $timeout) ){
               Start-Sleep  -Seconds  1
                    Write-Output "Sleeping for 1 second"
        $count = $count + 1
                    $vm_obj = Get-VMGuest -VM $node.Name | where VmUid -match $server
                    Write-Output $vm_obj.State

       }
       if($count -eq $timeout) {
        Write-Error "The VM did not get turned on with in stipulated timeout:$timeout value" 
                    break    
       } else {
        Write-Output "The VM is successfully started"
       }
      }
     } else {
            Write-Output "No Node is specified. Hence Starting the ESXi host"
            Start-VMHost -VMHost $server -Server $server -confirm:$false -RunAsync
        }

      } else {
            write-error("The task passed is neither Shutdown or Startup")
      }

    }  
        Catch {
            Write-Error "An error occured. $_"
    }
    Finally {
            Disconnect-VIServer -Server $server -confirm:$false
    }
}
Export-ModuleMember -Function ShutdownStartup-ComponentOnHost

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
        not passed, then exitstatus of 0 is considered as success 
    
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
            [String]$expected
    )


    Try {
        $password = ConvertTo-SecureString $pass -AsPlainText -Force
        $Cred = New-Object System.Management.Automation.PSCredential ($user, $password)
        #$expected = "Value of IgnoreClusterMemberListUpdates is 1"

        $session = New-SSHSession -ComputerName  $server -Credential $Cred -Force
        #Write-Output $session.SessionId 
        $out = Invoke-SSHCommand -index $session.SessionId -Command $cmd
        Write-Output $out


        if(($expected -AND $out.output -match $expected) -OR ($out.ExitStatus -eq 0)) {
            Write-Output "Success. The recived and expected outputs are matching"
        } elseif (($expected -AND $out.output -match $expected)) {

        }  else {
            Write-Error "Failure. The received output is: $out.output \n The expexted output is $expected"
        } 

        
    } Catch {
            Write-Error "An error occured. $_"
    } Finally {
            Remove-SSHSession -Index $session.SessionId
    }
}
Export-ModuleMember -Function Execute-OnEsx
