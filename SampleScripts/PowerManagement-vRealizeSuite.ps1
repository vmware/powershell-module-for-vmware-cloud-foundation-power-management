<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         Cloud Infrastructure Business Group (CIBG)
    .Organization:  VMware
    .Version:       1.0 (Build 001)
    .Date:          2021-11-23
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2021-11-23) - Initial script creation

    ===============================================================================================================

    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup the vRealize Suite components

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups the vRealize Suite components

    .EXAMPLE
    PowerManagement-vRealizeSuite.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerState Shutdown
    Initiaites a shutdown of the the vRealize Suite components

    .EXAMPLE
    PowerManagement-vRealizeSuite.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerState Startup
    Initiaites the startup of the the vRealize Suite components
#>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""
$str1 = "$PSCommandPath -server $server -user $user -pass $pass -powerState $powerState"
Write-LogMessage -Message "The execution command is:  $str1" -colour "Yellow"

# Check that the FQDN of the SDDC Manager is valid 
Try {
    if (!(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue)) {
        Write-Error "Unable to communicate with SDDC Manager ($server), check fqdn/ip address"
        Break
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ($StatusMsg) {
            Write-LogMessage -Type INFO -Message "Connection to SDDC manager is validated successfully"
        }
        elseif ($ErrorMsg) {
            if ($ErrorMsg -match "4\d\d") {
                Write-LogMessage -Type ERROR -Message "The authentication/authorization failed, please check credentials once again and then retry" -colour Red
                Break
            }
            else {
                Write-Error $ErrorMsg
                Break
            }
        }
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
    if ($StatusMsg) { Write-LogMessage -Type INFO -Message $StatusMsg } if ($WarnMsg) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ($ErrorMsg) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
        # Gather Details from SDDC Manager
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq $workloadDomain.id})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

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
        $wsaNodes = @()
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
    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        # Shutdown vRealize Suite
        if ($($WorkloadDomain.type) -eq "MANAGEMENT") {
            if ($($vra.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VRA -mode power-off -timeout 1800
            }
            if ($($vrops.status -eq "ACTIVE")) {
                $vropsCollectorNodes = @()
                Set-vROPSClusterState -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword -mode OFFLINE
                foreach ($node in (Get-vROPSClusterDetail -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword | Where-Object {$_.role -eq "REMOTE_COLLECTOR"} | Select-Object name)) {
                    [Array]$vropsCollectorNodes += $node.name
                }
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsCollectorNodes -timeout 600
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
            }
            if ($($wsa.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VIDM -mode power-off -timeout 1800
            }
            if ($($vrslcm.status -eq "ACTIVE")) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm.fqdn.Split(".")[0] -timeout 600
            }
            if ($($vrli.status -eq "ACTIVE")) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
            }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($powerState -eq "Startup") {
        # Startup vRealize Suite
        if ($($WorkloadDomain.type) -eq "MANAGEMENT") {
            if ($($vrslcm.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm.fqdn.Split(".")[0] -timeout 600
            }
            if ($($vrli.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
            }
            if ($($vrops.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
                $vropsCollectorNodes = @()
                foreach ($node in (Get-vROPSClusterDetail -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword | Where-Object {$_.role -eq "REMOTE_COLLECTOR"} | Select-Object name)) {
                    [Array]$vropsCollectorNodes += $node.name
                }
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsCollectorNodes -timeout 600
            }
            if ($($wsa.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VIDM -mode power-on -timeout 1800
            }
            if ($($vra.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VRA -mode power-on -timeout 1800
            }
            if ($($vrops.status -eq "ACTIVE")) {
                Set-vROPSClusterState -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword -mode ONLINE
            }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}