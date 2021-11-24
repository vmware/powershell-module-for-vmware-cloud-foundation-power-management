    <#
        .SYNOPSIS
        Connects to the specified SDDC Manager and shutdown/startup a Management Domain

        .DESCRIPTION
        This script connects to the specified SDDC Manager and either shutdowns or startups a Management Domain

        .EXAMPLE
        PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
        Initiaites a shutdown of the Management Domain 'sfo-w01'

        .EXAMPLE
        PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.ioc
        Initiaites the startup of the Management Domain 'sfo-w01'
    #>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""

# Check that the FQDN of the SDDC Manager is valid
Try {
    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to connect to server: $server, check details and try again"
        Break
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Setup a log file and gather details from SDDC Manager
Try {
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

    Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"

        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $mgmtCluster = Get-VCFCluster | Where-Object { $_.id -eq ($managementDomain.clusters.id) }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
        #$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

        # Gather ESXi Host Details for the Managment Domain
        $esxiManagementDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
        {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password
            $esxiManagementDomain += $esxDetails
        }

        # Gather ESXi Host Details for the VI Workload Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
        {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password
            $esxiWorkloadDomain += $esxDetails
        }

        # Gather NSX Manager Cluster Details
        $nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $managementDomain.nsxtCluster.id}
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).password
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }



        $nsxMgrNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            $nsxMgr = New-Object -TypeName PSCustomObject
            $nsxMgr | Add-Member -Type NoteProperty -Name fqdn -Value $node
            $nsxMgr | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $node -and $_.credentialType -eq "API"})).username
            $nsxMgr | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $node -and $_.credentialType -eq "API"})).password
            $nsxMgrNodes += $nsxMgr
        }

        # Gather NSX Edge Node Details
        $nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $managementDomain.nsxtCluster.id})
        $nsxtEdgeNodesfqdn = $nsxtEdgeCluster.edgeNodes.hostname
        $nsxtEdgeNodes = @()
        foreach ($node in $nsxtEdgeNodesfqdn) {
            [Array]$nsxtEdgeNodes += $node.Split(".")[0]
        }

        # Gather vRealize Suite Details
        $vrslcm = New-Object -TypeName PSCustomObject
        $vrslcm | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRSLCM).status
        $vrslcm | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRSLCM).fqdn
        $vrslcm | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).password
        $vrslcm | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name rootPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).password

        $wsa = New-Object -TypeName PSCustomObject
        $wsa | Add-Member -Type NoteProperty -Name status -Value (Get-VCFWSA).status
        $wsa | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFWSA).loadBalancerFqdn
        $wsa | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).username
        $wsa | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).password
        $wsa | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "SSH"})).username
        $wsa | Add-Member -Type NoteProperty -Name rootPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "SSH"})).password
        $wsaNodes = @()
        $wsaNodesfqdn = (Get-VCFWSA).nodes.fqdn | Sort-Object
        foreach ($node in (Get-VCFWSA).nodes.fqdn | Sort-Object) {
            [Array]$wsaNodes += $node.Split(".")[0]
        }


        $vrops = New-Object -TypeName PSCustomObject
        $vrops | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvROPS).status
        $vrops | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvROPS).loadBalancerFqdn
        $vrops | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).username
        $vrops | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).password
        $vrops | Add-Member -Type NoteProperty -Name master -Value  ((Get-VCFvROPs).nodes | Where-Object {$_.type -eq "MASTER"}).fqdn
        $vropsNodes = @()
        foreach ($node in (Get-VCFvROPS).nodes.fqdn | Sort-Object) {
            [Array]$vropsNodes += $node.Split(".")[0]
        }

        $vra = New-Object -TypeName PSCustomObject
        $vra | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRA).status
        $vra | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRA).loadBalancerFqdn
        $vra | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vra.fqdn -and $_.credentialType -eq "API"})).username
        $vra | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vra.fqdn -and $_.credentialType -eq "API"})).password
        $vraNodes = @()
        foreach ($node in (Get-VCFvRA).nodes.fqdn | Sort-Object) {
            [Array]$vraNodes += $node.Split(".")[0]
        }

        $vrli = New-Object -TypeName PSCustomObject
        $vrli | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRLI).status
        $vrli | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRLI).loadBalancerFqdn
        $vrli | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).username
        $vrli | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).password
        $vrliNodes = @()
        foreach ($node in (Get-VCFvRLI).nodes.fqdn | Sort-Object) {
            [Array]$vrliNodes += $node.Split(".")[0]
        }

        #get SDDC VM name from Vcenter server
        if ($mgmtVcServer.fqdn) {
            Write-Output "Getting SDDC Manager Manager VM Name"
            Connect-VIServer -server $mgmtVcServer.fqdn -user $vcUser -password $vcPass | Out-Null
            $sddcmVMName = ((Get-VM * | Where-Object {$_.Guest.Hostname -eq $server}).Name)
        }

        $nsxt_local_url = "https://$nsxtNodesfqdn/login.jsp?local=true"


    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to connect to SDDC Manager $server" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        <#
        #Shut Down the vRealize Automation Virtual Machines in the Management Domain
        #ShutdownStartupProduct-ViaVRSLCM -server 'xreg-vrslcm01.rainpole.io' -product 'VRA' -user 'vcfadmin@local' -pass 'VMw@re123!' -mode "power-off" -env 'Cross' -timeout 1800
        $checkServer = Test-Connection -ComputerName $vrslcm.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            ShutdownStartupProduct-ViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product 'VRA' -mode "power-off" -env 'Cross' -timeout 1800
        }
        else {
            Write-LogMessage -Type ERROR -Message "unable to connect to VRSLCM server"
        }
x
        if (!$($WorkloadDomain.type) -eq "MANAGEMENT") {
            $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
            if ($checkServer -eq "True") {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
            }
        }


        # Shut Down the vRealize Operations Manager Virtual Machines in the Management Domain
        #SetClusterState-VROPS -server 'xreg-vrops01a.rainpole.io' -mode 'OFFLINE' -user 'admin' -pass 'VMw@re123!'
        #ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes xreg-vrops01a, xreg-vrops01b, xreg-vrops01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600
        #ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vropsc01a, sfo-vropsc01b -user administrator@vsphere.local -pass VMw@re123! -timeout 600

        SetClusterState-VROPS -server $vrops.master  -user $vrops.adminUser -pass $vrops.adminPassword -mode 'OFFLINE'
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
        ##############Don't know how to fetch sfo-vropsc01a

        #>

        #Shut Down the Clustered Workspace ONE Access Virtual Machines
        ShutdownStartupProduct-ViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product 'vidm' -mode "power-off" -env 'Cross' -timeout 1800

        #Shut Down the vRealize Suite Lifecycle Manager Virtual Machine in the Management Domain
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm -timeout 600
        }
        else {
            Write-LogMessage -Type ERROR -Message "unable to connect to Management VC"
        }

        #Shut Down the vRealize Log Insight Virtual Machines in the Management Domain #### this goes to vrealize suite
        #Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrli -timeout 600

        #Shut Down the Region-Specific Workspace ONE Access Virtual Machine in the Management Domain#######how to get region specific WSA
        ######Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrli -timeout 600

        #Shut Down the NSX-T Edge Nodes in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600


        #Shut Down the NSX-T Managers in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        #Shut Down the SDDC Manager Virtual Machine in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        #Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -mode 'disable'

        #Shut Down the vCenter Server Instance in the Management Domain
        Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level Manual

        ##If the management domain vCenter Server is not running on the first ESXi host in the default management cluster, migrate it there.###check how to do it
        # Check the health and sync status of the VSAN cluster
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
        }

        # Shutdown vCenter Server
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $mgmtVcServer.fqdn.Split(".")[0] -timeout 600
        Start-Sleep -Seconds 100
        if (Test-Connection -ComputerName sfo-m01-vc01.sfo.rainpole.io)
        {
            write-error "Unable to shutdown VC"
        }
        else {
            write-output "Successfully shutdown VC"
        }

        # Prepare the vSAN cluster for shutdown - Performed on a single host only
        Invoke-EsxCommand -server $esxiManagementDomain.fqdn[0] -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"

        # Disable vSAN cluster member updates and place host in maintenance mode
        foreach ($esxiNode in $esxiManagementDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
        }
            <#
        .SYNOPSIS
        Connects to the specified SDDC Manager and shutdown/startup a Management Domain

        .DESCRIPTION
        This script connects to the specified SDDC Manager and either shutdowns or startups a Virual Infrastructure Workload Domain

        .EXAMPLE
        PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
        Initiaites a shutdown of the Virual Infrastructure Workload Domain 'sfo-w01'

        .EXAMPLE
        PowerManagement-WorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Startup
        Initiaites the startup of the Virual Infrastructure Workload Domain 'sfo-w01'
    #>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""

# Check that the FQDN of the SDDC Manager is valid
Try {
    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to connect to server: $server, check details and try again"
        Break
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Setup a log file and gather details from SDDC Manager
Try {
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

    Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"

        # Gather Details from SDDC Manager
        $managementDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $mgmtCluster = Get-VCFCluster | Where-Object { $_.id -eq ($managementDomain.clusters.id) }
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
        #$members = (Get-VCFHost | Where-Object {$_.cluster.id -eq $cluster.id} | Select-Object fqdn).fqdn

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
        $mgmtVcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($managementDomain.id)})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

        # Gather ESXi Host Details for the Managment Domain
        $esxiManagementDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
        {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password
            $esxiManagementDomain += $esxDetails
        }

        # Gather ESXi Host Details for the VI Workload Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $managementDomain.id}).fqdn)
        {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password
            $esxiWorkloadDomain += $esxDetails
        }

        # Gather NSX Manager Cluster Details
        $nsxtCluster = Get-VCFNsxtCluster | Where-Object {$_.id -eq $managementDomain.nsxtCluster.id}
        $nsxtMgrfqdn = $nsxtCluster.vipFqdn
        $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).username
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API"})).password
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }



        $nsxMgrNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            $nsxMgr = New-Object -TypeName PSCustomObject
            $nsxMgr | Add-Member -Type NoteProperty -Name fqdn -Value $node
            $nsxMgr | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $node -and $_.credentialType -eq "API"})).username
            $nsxMgr | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $node -and $_.credentialType -eq "API"})).password
            $nsxMgrNodes += $nsxMgr
        }

        # Gather NSX Edge Node Details
        $nsxtEdgeCluster = (Get-VCFEdgeCluster | Where-Object {$_.nsxtCluster.id -eq $managementDomain.nsxtCluster.id})
        $nsxtEdgeNodesfqdn = $nsxtEdgeCluster.edgeNodes.hostname
        $nsxtEdgeNodes = @()
        foreach ($node in $nsxtEdgeNodesfqdn) {
            [Array]$nsxtEdgeNodes += $node.Split(".")[0]
        }

        # Gather vRealize Suite Details
        $vrslcm = New-Object -TypeName PSCustomObject
        $vrslcm | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRSLCM).status
        $vrslcm | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRSLCM).fqdn
        $vrslcm | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API"})).password
        $vrslcm | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).username
        $vrslcm | Add-Member -Type NoteProperty -Name rootPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH"})).password

        $wsa = New-Object -TypeName PSCustomObject
        $wsa | Add-Member -Type NoteProperty -Name status -Value (Get-VCFWSA).status
        $wsa | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFWSA).loadBalancerFqdn
        $wsa | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).username
        $wsa | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API"})).password
        $wsa | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "SSH"})).username
        $wsa | Add-Member -Type NoteProperty -Name rootPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "SSH"})).password
        $wsaNodes = @()
        $wsaNodesfqdn = (Get-VCFWSA).nodes.fqdn | Sort-Object
        foreach ($node in (Get-VCFWSA).nodes.fqdn | Sort-Object) {
            [Array]$wsaNodes += $node.Split(".")[0]
        }


        $vrops = New-Object -TypeName PSCustomObject
        $vrops | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvROPS).status
        $vrops | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvROPS).loadBalancerFqdn
        $vrops | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).username
        $vrops | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API"})).password
        $vrops | Add-Member -Type NoteProperty -Name master -Value  ((Get-VCFvROPs).nodes | Where-Object {$_.type -eq "MASTER"}).fqdn
        $vropsNodes = @()
        foreach ($node in (Get-VCFvROPS).nodes.fqdn | Sort-Object) {
            [Array]$vropsNodes += $node.Split(".")[0]
        }

        $vra = New-Object -TypeName PSCustomObject
        $vra | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRA).status
        $vra | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRA).loadBalancerFqdn
        $vra | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vra.fqdn -and $_.credentialType -eq "API"})).username
        $vra | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vra.fqdn -and $_.credentialType -eq "API"})).password
        $vraNodes = @()
        foreach ($node in (Get-VCFvRA).nodes.fqdn | Sort-Object) {
            [Array]$vraNodes += $node.Split(".")[0]
        }

        $vrli = New-Object -TypeName PSCustomObject
        $vrli | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRLI).status
        $vrli | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRLI).loadBalancerFqdn
        $vrli | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).username
        $vrli | Add-Member -Type NoteProperty -Name adminPassword -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API"})).password
        $vrliNodes = @()
        foreach ($node in (Get-VCFvRLI).nodes.fqdn | Sort-Object) {
            [Array]$vrliNodes += $node.Split(".")[0]
        }

        #get SDDC VM name from Vcenter server
        if ($mgmtVcServer.fqdn) {
            Write-Output "Getting SDDC Manager Manager VM Name"
            Connect-VIServer -server $mgmtVcServer.fqdn -user $vcUser -password $vcPass | Out-Null
            $sddcmVMName = ((Get-VM * | Where-Object {$_.Guest.Hostname -eq $server}).Name)
        }

        $nsxt_local_url = "https://$nsxtNodesfqdn/login.jsp?local=true"

    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to connect to SDDC Manager $server" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        <#
        #Shut Down the vRealize Automation Virtual Machines in the Management Domain
        #ShutdownStartupProduct-ViaVRSLCM -server 'xreg-vrslcm01.rainpole.io' -product 'VRA' -user 'vcfadmin@local' -pass 'VMw@re123!' -mode "power-off" -env 'Cross' -timeout 1800
        $checkServer = Test-Connection -ComputerName $vrslcm.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            ShutdownStartupProduct-ViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product 'VRA' -mode "power-off" -env 'Cross' -timeout 1800
        }
        else {
            Write-LogMessage -Type ERROR -Message "unable to connect to VRSLCM server"
        }
        <#
        if (!$($WorkloadDomain.type) -eq "MANAGEMENT") {
            $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
            if ($checkServer -eq "True") {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
            }
        }


        # Shut Down the vRealize Operations Manager Virtual Machines in the Management Domain
        #SetClusterState-VROPS -server 'xreg-vrops01a.rainpole.io' -mode 'OFFLINE' -user 'admin' -pass 'VMw@re123!'
        #ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes xreg-vrops01a, xreg-vrops01b, xreg-vrops01c -user administrator@vsphere.local -pass VMw@re123! -timeout 600
        #ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-vropsc01a, sfo-vropsc01b -user administrator@vsphere.local -pass VMw@re123! -timeout 600

        SetClusterState-VROPS -server $vrops.master  -user $vrops.adminUser -pass $vrops.adminPassword -mode 'OFFLINE'
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
        ##############Don't know how to fetch sfo-vropsc01a

        #>

        #Shut Down the Clustered Workspace ONE Access Virtual Machines
        $checkServer = Test-Connection -ComputerName $vrslcm.fqdn -Quiet -Count 1
        ShutdownStartupProduct-ViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product 'vidm' -mode "power-off" -env 'Cross' -timeout 1800

        #Shut Down the vRealize Suite Lifecycle Manager Virtual Machine in the Management Domain
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm -timeout 600
        }
        else {
            Write-LogMessage -Type ERROR -Message "unable to connect to Management VC"
        }

        #Shut Down the vRealize Log Insight Virtual Machines in the Management Domain #### this goes to vrealize suite
        #Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrli -timeout 600

        #Shut Down the Region-Specific Workspace ONE Access Virtual Machine in the Management Domain#######how to get region specific WSA
        ######Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrli -timeout 600

        #Shut Down the NSX-T Edge Nodes in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600


        #Shut Down the NSX-T Managers in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        #Shut Down the SDDC Manager Virtual Machine in the Management Domain
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        #Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -mode 'disable'

        #Shut Down the vCenter Server Instance in the Management Domain
        Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level Manual

        ##If the management domain vCenter Server is not running on the first ESXi host in the default management cluster, migrate it there.###check how to do it
        # Check the health and sync status of the VSAN cluster
        $checkServer = Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
            Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking VSAN health for cluster $($cluster.name)" -Colour Cyan
        }

        # Shutdown vCenter Server
        Stop-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $mgmtVcServer.fqdn.Split(".")[0] -timeout 600
        Start-Sleep -Seconds 100
        if (Test-Connection -ComputerName sfo-m01-vc01.sfo.rainpole.io)
        {
            write-error "Unable to shutdown VC"
        }
        else {
            write-output "Successfully shutdown VC"
        }

        # Prepare the vSAN cluster for shutdown - Performed on a single host only
        Invoke-EsxCommand -server $esxiManagementDomain.fqdn[0] -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"

        # Disable vSAN cluster member updates and place host in maintenance mode
        foreach ($esxiNode in $esxiManagementDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($powerState -eq "Startup") {

        # Take hosts out of maintenance mode
        foreach ($esxiNode in $esxiManagementDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
        }

        # Prepare the vSAN cluster for startup - Performed on a single host only
        Invoke-EsxCommand -server $esxiManagementDomain.fqdn[0] -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

        foreach ($esxiNode in $esxiManagementDomain) {
            Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
        }


        # Startup the Management Domain vCenter Server
        Start-CloudComponent -server $esxiManagementDomain.fqdn[0] -pattern $mgmtVcServer.name -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -timeout 500 -task "Startup"
        Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($mgmtVcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)
        Test-VsanHealth -cluster $mgmtCluster.name -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass
        Test-ResyncingObjects -cluster $mgmtCluster.name -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass

        if ( get-cluster -name $mgmtCluster.name | select HAEnabled)
        {
            Set-Cluster -Name $mgmtCluster.name -HAEnabled:$false
            if ( get-cluster -name $mgmtCluster.name | select HAEnabled )
            {
                Write-LogMessage -Type INFO -Message "Successfully disabled HA"
            }
            Set-Cluster -Name $mgmtCluster.name -HAEnabled:$true
            if ( get-cluster -name $mgmtCluster.name | select HAEnabled )
            {
                Write-LogMessage -Type INFO -Message "Successfully enabled HA"
            }
            Write-LogMessage -Type INFO -Message "Successfully restarted HA"
        } else {
            Write-LogMessage -Type INFO -Message "HA is not enabled"
        }

        Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level FullyAutomated


        #Startup the vSphere Cluster Services Virtual Machines in the Management Domain
        Set-Retreatmode -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -mode 'enable'


        #Start the SDDC Manager Virtual Machine
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Startup the NSX Manager Nodes in the Management Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        Connect-NSXTLocal -url $nsxt_local_url
        Get-NSXTMgrClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword


        # Startup the NSX Edge Nodes in the Management Domain
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            if ($nsxtEdgeNodes) {
                Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
            }
            else {
                Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
            }
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($mgmtVcServer.fqdn) is not power on, skipping startup of $nsxtEdgeNodes" -Colour Cyan
            Exit
        }


        #Start the vRealize Suite Lifecycle Manager Virtual Machine
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -node $vrslcm.name  -timeout 150 -task "Startup"

        #Start the Clustered Workspace ONE Access Virtual Machines
        Start-CloudComponent -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword  -product 'vidm' -mode "power-on"  -env "global" -timeout 1800
        foreach ($node in $wsaNodesfqdn) {
            Execute-OnEsx -server $node -user $rootUser -pass $rootPassword -cmd 'echo "Domain rainpole.io" >> /etc/resolv.conf;  echo "search rainpole.io sfo.rainpole.io" >> /etc/resolv.conf' -timeout 600
        }
        Start-CloudComponent -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword  -product 'vidm' -mode "health-check" -env "global"  -timeout 300

    }
}
Catch {
    Debug-CatchWriter -object $_
}
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($powerState -eq "Startup") {

        # Take hosts out of maintenance mode
        foreach ($esxiNode in $esxiManagementDomain) {
            Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
        }

        # Prepare the vSAN cluster for startup - Performed on a single host only
        Invoke-EsxCommand -server $esxiManagementDomain.fqdn[0] -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

        foreach ($esxiNode in $esxiManagementDomain) {
            Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
        }


        # Startup the Management Domain vCenter Server
        Start-CloudComponent -server $esxiManagementDomain.fqdn[0] -pattern $mgmtVcServer.name -user $esxiManagementDomain.username[0] -pass $esxiManagementDomain.password[0] -timeout 500 -task "Startup"
        Write-LogMessage -Type INFO -Message "Waiting for vCenter services to start on $($mgmtVcServer.fqdn) (may take some time)"
        Do {} Until (Connect-VIServer -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue)
        Test-VsanHealth -cluster $mgmtCluster.name -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass
        Test-ResyncingObjects -cluster $mgmtCluster.name -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass

        if ( get-cluster -name $mgmtCluster.name | select HAEnabled)
        {
            Set-Cluster -Name $mgmtCluster.name -HAEnabled:$false
            if ( get-cluster -name $mgmtCluster.name | select HAEnabled )
            {
                Write-LogMessage -Type INFO -Message "Successfully disabled HA"
            }
            Set-Cluster -Name $mgmtCluster.name -HAEnabled:$true
            if ( get-cluster -name $mgmtCluster.name | select HAEnabled )
            {
                Write-LogMessage -Type INFO -Message "Successfully enabled HA"
            }
            Write-LogMessage -Type INFO -Message "Successfully restarted HA"
        } else {
            Write-LogMessage -Type INFO -Message "HA is not enabled"
        }

        Set-DrsAutomationLevel -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -level FullyAutomated


        #Startup the vSphere Cluster Services Virtual Machines in the Management Domain
        Set-Retreatmode -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -cluster $mgmtCluster.name -mode 'enable'


        #Start the SDDC Manager Virtual Machine
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Startup the NSX Manager Nodes in the Management Domain
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        Connect-NSXTLocal -url $nsxt_local_url
        Get-NSXTMgrClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword


        # Startup the NSX Edge Nodes in the Management Domain
        $checkServer = Test-Connection -ComputerName $mgmtVcServer.fqdn -Quiet -Count 1
        if ($checkServer -eq "True") {
            if ($nsxtEdgeNodes) {
                Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
            }
            else {
                Write-LogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
            }
        }
        else {
            Write-LogMessage -Type WARNING -Message "Looks like that $($mgmtVcServer.fqdn) is not power on, skipping startup of $nsxtEdgeNodes" -Colour Cyan
            Exit
        }


        #Start the vRealize Suite Lifecycle Manager Virtual Machine
        Start-CloudComponent -server $mgmtVcServer.fqdn -user $vcUser -pass $vcPass -node $vrslcm.name  -timeout 150 -task "Startup"

        #Start the Clustered Workspace ONE Access Virtual Machines
        Start-CloudComponent -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword  -product 'vidm' -mode "power-on"  -env "global" -timeout 1800
        foreach ($node in $wsaNodesfqdn) {
            Execute-OnEsx -server $node -user $rootUser -pass $rootPassword -cmd 'echo "Domain rainpole.io" >> /etc/resolv.conf;  echo "search rainpole.io sfo.rainpole.io" >> /etc/resolv.conf' -timeout 600
        }
        Start-CloudComponent -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword  -product 'vidm' -mode "health-check" -env "global"  -timeout 300

    }
}
Catch {
    Debug-CatchWriter -object $_
}