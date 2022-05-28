# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake / Sowjanya V
    .Group:         Cloud Infrastructure Business Group (CIBG)
    .Organization:  VMware
    .Version:       1.0 (Build 001)
    .Date:          2022-02-22
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2022-02-22) - Initial release

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


Try {
    Clear-Host; Write-Host ""
    $Global:ProgressPreference = 'SilentlyContinue'
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    $str1 = "$PSCommandPath "
    $str2 = "-server $server -user $user -pass ******* -sddcDomain $sddcDomain -powerState $powerState"
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"

    if (!(Test-NetConnection -ComputerName $server).PingSucceeded) {
        Write-Error "Unable to communicate with SDDC Manager ($server), check fqdn/ip address."
        Exit
    }
    else {
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ($StatusMsg) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC manager is validated successfully"
        }
        elseif ($ErrorMsg) {
            if ($ErrorMsg -match "4\d\d") {
                Write-PowerManagementLogMessage -Type ERROR -Message "The authentication/authorization failed, please check credentials once again and then retry." -colour Red
                Exit
            }
            else {
                Write-Error $ErrorMsg
                Exit
            }
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Gather details from SDDC Manager
Try {
    Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
        # Gather Details from SDDC Manager
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
        $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

        # Gather ESXi Host Details for the Tanzu Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id }).fqdn) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).password 
            $esxiWorkloadDomain += $esxDetails
        } 
    }
    else {
        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        # Change the DRS Automation Level to Partially Automated for the VI Workload Domain Clusters
        if ((Test-NetConnection -ComputerName $vcServer.fqdn).PingSucceeded) {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated
        }

        # Stop the WCP service
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP

        # Stop the Supervisor Control Plane Virtual Machines
        $clusterPattern = "^SupervisorControlPlaneVM.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        # Stop the Tanzu Cluster Virtual Machines
        $clusterPattern = "^.*-tkc01-.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        # Stop the Harbour Registry Virtual Machines
        $clusterPattern = "^harbor.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300 -noWait
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Startup procedures
Try {
    if ($powerState -eq "Startup") {
        # Startup the vSphere with Tanzu Virtual Machines
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action START
        Write-PowerManagementLogMessage -Type INFO -Message "Workload Management will be started automatically by the WCP service, this will take some time"

        # Change the DRS Automation Level to Fully Automated for the VI Workload Domain Clusters
        if ((Test-NetConnection -ComputerName $vcServer.fqdn).PingSucceeded) {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
        }
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}