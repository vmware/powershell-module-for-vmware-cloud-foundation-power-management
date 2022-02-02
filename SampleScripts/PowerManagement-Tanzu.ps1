<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake / Sowjanya V
    .Group:         Cloud Infrastructure Business Group (CIBG)
    .Organization:  VMware
    .Version:       1.0 (Build 001)
    .Date:          2021-11-30
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2021-11-30) - Initial script creation

    ===============================================================================================================

    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdown/startup a Tanzu Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Tanzu Workload Domain

    .EXAMPLE
    PowerManagement-Tanzu.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Shutdown
    Initiates a shutdown of the Tanzu Workload Domain 'sfo-w01'

    .EXAMPLE
    PowerManagement-Tanzu.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain sfo-w01 -powerState Startup
    Initiates the startup of the Tanzu Workload Domain 'sfo-w01'
#>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
        [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)

Clear-Host; Write-Host ""
$str1 = "$PSCommandPath -server $server -user $user -pass $pass -powerState $powerState -sddcDomain $sddcDomain"
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
        elseif ( $ErrorMsg ) {
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
    Write-LogMessage -Type INFO -Message "Setting up the log file to path ($logfile)"
    Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
        # Gather Details from SDDC Manager
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id)})
        $vcUser = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).username
        $vcPass = (Get-VCFCredential | Where-Object {$_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO"}).password

        # Gather ESXi Host Details for the Tanzu Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object {$_.domain.id -eq $workloadDomain.id}).fqdn)
        {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({$_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER"})).password 
            $esxiWorkloadDomain += $esxDetails
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
        # Change the DRS Automation Level to Partially Automated for the VI Workload Domain Clusters
        if ((Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) -eq "True") {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
        }

        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP

        $clusterPattern = "^SupervisorControlPlaneVM.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1800
        }

        $clusterPattern = "^.*-tkc01-.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1800
        }

        $clusterPattern = "^harbor.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 1800
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Execute the Statup procedures
Try {
    if ($powerState -eq "Startup") {
        # Startup the vSphere with Tanzu Virtual Machines
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action START

        # Change the DRS Automation Level to Fully Automated for the VI Workload Domain Clusters
        if ((Test-Connection -ComputerName $vcServer.fqdn -Quiet -Count 1) -eq "True") {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}