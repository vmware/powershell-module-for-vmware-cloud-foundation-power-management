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
    Connects to the specified SDDC Manager and shutdown/startup a Management Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Management Workload Domain

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -Shutdown
    Initiates a shutdown of the Management Workload Domain.
    Note that SDDC Manager should running in order to use the so if it is already stopped script could not be started with "Shutdown" option.
    In case SDDC manager is already stopped, please identify the step on which the script have stopped and 
    continue shutdown manually, following the VCF documentation.

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -genjson
    Initiates a *.json generation that could be used for startup. Existing file in the same directory will be overwritten

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -Startup
    Initiates the startup of the Management Workload Domain

    .EXAMPLE
    PowerManagement-ManagementDomain.ps1 -Startup -json .\startup.json
    Initiates the startup of the Management Workload Domain with startup.json file as input from current directory
#>

Param (
    # Pure shutdown parameters
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdown,
    [Parameter (Mandatory = $false, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
    # Shutdown and json generation
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")]
    [Parameter (Mandatory = $true, ParameterSetName = "shutdown")] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true, ParameterSetName = "genjson")] [ValidateNotNullOrEmpty()] [Switch]$genjson,
    # Startup
    [Parameter (Mandatory = $false, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [String]$json,
    [Parameter (Mandatory = $true, ParameterSetName = "startup")] [ValidateNotNullOrEmpty()] [Switch]$startup
)

# Param (
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$server,
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$user,
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$pass,
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$shutdownCustomerVm,
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$genjson,
#     [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$json,
#     [Parameter (Mandatory = $false)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
# )

# Customer Questions Section 
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    $Global:ProgressPreference = 'SilentlyContinue'
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Management Domain" }
    else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Management Domain" }
    # if ($powerState -eq "Shutdown" -or $genjson) {
    #     # Check if we have all needed inputs for shutdown
    #     if (-Not $PsBoundParameters.ContainsKey("server") -or -Not $PsBoundParameters.ContainsKey("user") -or -Not $PsBoundParameters.ContainsKey("pass")) {
    #         Write-PowerManagementLogMessage -Type ERROR -Message "Missing one or more of the mandatory inputs 'Server', 'User', 'Password'. Exiting!" -Colour Red
    #         Exit
    #     }
    #     if (-Not $PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
    #         Write-Host "";
    #         $proceed_force = Read-Host "Would you like to gracefully shutdown customer deployed Virtual Machines not managed by SDDC Manager (Yes/No)? [No]"; Write-Host ""
    #         if ($proceed_force -Match "yes") {
    #             $PSBoundParameters.Add('shutdownCustomerVm', 'Yes')
    #             $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Management Domain."
    #         }
    #         else {
    #             $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Management Domain"
    #         }
    #     }
    #     else {
    #         $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines not managed by VCF running if deployed within the Management Domain"
    #     }

    #     # Write-Host "";
    #     # $regionalWSA = $False
    #     # $regionalWSAYesOrNo = Read-Host "Have you deployed a Standalone Workspace ONE Access instance (Yes/No)"
    #     # if ($regionalWSAYesOrNo -eq "yes") {
    #     #     $regionalWSA = Read-Host "Enter the Virtual Machine name for the Standalone Workspace ONE Access instance"
    #     #     Write-PowerManagementLogMessage -Type INFO -Message "The Standalone Workspace ONE Access instance Name is : $regionalWSA"
    #     #     if (([string]::IsNullOrEmpty($regionalWSA))) {
    #     #         Write-PowerManagementLogMessage -Type WARNING -Message "Regional WSA information is null, hence Exiting" -Colour Cyan
    #     #         Exit
    #     #     }
    #     # }
    # }
    if ($PsBoundParameters.ContainsKey("startup")) {
        $defaultFile = "./ManagementStartupInput.json"
        $inputFile = $null
        if ($json) {
            Write-PowerManagementLogMessage -Type INFO -Message "User has provided the input json file" -Colour Green
            $inputFile = $json
        }
        elseif (Test-Path -Path $defaultFile -PathType Leaf) {
            Write-PowerManagementLogMessage -Type INFO -Message "No path to json provided on the command line so script is using for auto created input json file ManagementStartupInput.json from current directory" -Colour Yellow
            $inputFile = $defaultFile
        } 
        if ([string]::IsNullOrEmpty($inputFile)) {
            Write-PowerManagementLogMessage -Type WARNING -Message "JSON input file is not provided, unable to proceed, hence exiting" -Colour Cyan
            Exit
        }
        Write-Host "";
        $proceed = Read-Host "The following JSON file $inputFile will be used for the operation, please confirm (Yes or No)[default:No]"
        if (-Not $proceed) {
            Write-PowerManagementLogMessage -Type WARNING -Message "None of the option is chosen. Default is `"No`", hence exiting script execution" -Colour Cyan
            Exit
        }
        else {
            if (($proceed -match "no") -or ($proceed -match "yes")) {
                if ($proceed -match "no") {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Exiting script execution as the input is No" -Colour Cyan
                    Exit
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string, either Yes or No" -Colour Cyan
                Exit
            }
        }

        Write-PowerManagementLogMessage -Type INFO -Message "$inputFile is checked for its correctness, moving on with execution"
    } 
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
}

# Pre-Checks
Try {
    $str1 = "$PSCommandPath "
    if ($server -and $user -and $pass) { $str2 = "-server $server -user $user -pass ******* " }
    if ($PsBoundParameters.ContainsKey("startup")) { $str2 = $str2 + " -startup" }
    if ($PsBoundParameters.ContainsKey("shutdown")) { $str2 = $str2 + " -shutdown" }
    if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $str2 = $str2 + " -shutdownCustomerVm" }
    if ($PsBoundParameters.ContainsKey("genjson")) { $str2 = $str2 + " -genjson" }
    if ($json) { $str2 = $str2 + " -json $json" }
    Write-PowerManagementLogMessage -Type INFO -Message "Script used: $str1" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Script syntax: $str2" -Colour Yellow
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile" -Colour Yellow
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage -Colour Yellow }

    if (-Not (Get-InstalledModule -Name Posh-SSH -MinimumVersion 3.0.4 -ErrorAction Ignore)) {
        Write-PowerManagementLogMessage -Type INFO -Message "Use the command 'Install-Module Posh-SSH -MinimumVersion 3.0.4' to install from PS Gallery" -Colour Yellow
        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to find Posh-SSH module with version 3.0.4 or greater. Exiting!" -Colour Red
        Exit
    }
    else {
        $ver = Get-InstalledModule -Name Posh-SSH -MinimumVersion 3.0.4
        Write-PowerManagementLogMessage -Type INFO -Message "The version of Posh-SSH found on the system is: $($ver.Version)" -Colour Green
    }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
    Exit
}

# Shutdown procedure and json generation
if ($PsBoundParameters.ContainsKey("shutdown") -or $PsBoundParameters.ContainsKey("genjson")) {
    Try {
        # Check connection to SDDC Manager 
        Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details"
        if (!(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to communicate with SDDC Manager ($server), check fqdn/ip address or power state of the '$server'" -Colour Red
            Exit
        }
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } 
        if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Cyan } 
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC Manager is validated successfully" -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from SDDC Manager inventory (May take some time)"
            $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
            $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

            $var = @{}
            $var["Domain"] = @{}
            $var["Domain"]["name"] = $workloadDomain.name
            $var["Domain"]["type"] = "MANAGEMENT"

            $var["Cluster"] = @{}
            $var["Cluster"]["name"] = $cluster.name

            # Gather vCenter Server Details and Credentials
            $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
            $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
            $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password
            # Test if VC is reachable, if it is already stopped, we could not continue with the shutdown sequence in automatic way.
            if (-Not (Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded ) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Could not connect to $($vcServer.fqdn)! Script could not continue without connection to the Management vCenter Server. " -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "Please check the current state and resolve the issue or continue with shutdown following the vCloud Foundation Documentation. Exiting!" -Colour Red
                Exit
            }
            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name 
            if ($status -eq $True) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Currently we are not supporting Tanzu enabled domains. Please try on other domains" -Colour Red
                Exit
            }
            if ($vcPass) {
                $vcPass_encrypted = $vcPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            }
            else {
                $vcPass_encrypted = $null
            }

            [Array]$allvms = @()
            [Array]$vcfvms = @()
            [Array]$vcfvms += $server.Split(".")[0]

            [Array]$vcfvms += ($vcServer.fqdn).Split(".")[0]

            # if ($regionalWSA) {
            #     [Array]$vcfvms += $regionalWSA
            # }

            $var["Server"] = @{}
            $var["Server"]["name"] = $vcServer.fqdn.Split(".")[0]
            $var["Server"]["fqdn"] = $vcServer.fqdn
            $var["Server"]["user"] = $vcUser
            $var["Server"]["password"] = $vcPass_encrypted

            $var["Hosts"] = @()
            # Gather ESXi Host Details for the Management Workload Domain
            $esxiWorkloadDomain = @()
            foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id }).fqdn) {
                $esxDetails = New-Object -TypeName PSCustomObject
                $esxDetails | Add-Member -Type NoteProperty -Name name -Value $esxiHost.Split(".")[0]
                $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
                $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).username
                $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).password
                $esxiWorkloadDomain += $esxDetails
                $esxi_block = @{}
                $esxi_block["name"] = $esxDetails.name
                $esxi_block["fqdn"] = $esxDetails.fqdn
                $esxi_block["user"] = $esxDetails.username
                $Pass = $esxDetails.password
                if ($Pass) {
                    $Pass_encrypted = $Pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                }
                else {
                    $Pass_encrypted = $null
                }
                $esxi_block["password"] = $Pass_encrypted
                $var["Hosts"] += $esxi_block
            }

            # Gather NSX Manager Cluster Details
            $nsxtCluster = Get-VCFNsxtCluster -id $workloadDomain.nsxtCluster.id
            $nsxtMgrfqdn = $nsxtCluster.vipFqdn
            $nsxMgrVIP = New-Object -TypeName PSCustomObject
            $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).username
            $Pass = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $nsxtMgrfqdn -and $_.credentialType -eq "API" })).password
            if ($Pass) {
                $Pass_encrypted = $Pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            }
            else {
                $Pass_encrypted = $null
            }
            $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $Pass
            $nsxtNodesfqdn = $nsxtCluster.nodes.fqdn
            $nsxtNodes = @()
            foreach ($node in $nsxtNodesfqdn) {
                [Array]$nsxtNodes += $node.Split(".")[0]
                [Array]$vcfvms += $node.Split(".")[0]
            }
            $var["NsxtManager"] = @{}
            $var["NsxtManager"]["vipfqdn"] = $nsxtMgrfqdn
            $var["NsxtManager"]["nodes"] = $nsxtNodesfqdn
            $var["NsxtManager"]["user"] = $nsxMgrVIP.adminUser
            $var["NsxtManager"]["password"] = $Pass_encrypted

            # Gather NSX-T Edge Node Details
            $nsxManagerPowerOnVMs = 0
            foreach ($nsxtManager in $nsxtNodes) {
                $state = Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch
                if ($state) { $nsxManagerPowerOnVMs += 1 }
                # If we have all NSX-T managers running, or minimum 2 nodes up - query NSX-T for edges.
                if (($nsxManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxManagerPowerOnVMs -eq 2)) { 
                    $statusOfNsxtClusterVMs = 'running'
                }
            }
            if ($statusOfNsxtClusterVMs -ne 'running') {
                Write-PowerManagementLogMessage -Type WARNING -Message "NSX-T Manager VMs have been stopped, so NSX-T Edge cluster VMs will not be handled in automatic way" -Colour Cyan
            }
            else { 
                Try {
                    [Array]$edgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $VcServer.fqdn)
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Unable to fetch nsx edge nodes information from NSX-T manager '$nsxtMgrfqdn'. Exiting!" -Colour Red
                }
            }

            if ($edgeNodes.count -ne 0) {
                $nsxtEdgeNodes = $edgeNodes
                $var["NsxEdge"] = @{}
                $var["NsxEdge"]["nodes"] = New-Object System.Collections.ArrayList
                foreach ($val in $edgeNodes) {
                    $var["NsxEdge"]["nodes"].add($val) | out-null
                    [Array]$vcfvms += $val
                }
            }

            # # Gather vRealize Suite Details
            # $vrslcm = New-Object -TypeName PSCustomObject
            # $vrslcm | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRSLCM).status
            # $vrslcm | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRSLCM).fqdn
            # $vrslcm | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API" })).username
            # $adminPassword = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "API" })).password
            # if ($adminPassword) {
            #     $adminPassword_encrypted = $adminPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            # }
            # else {
            #     $adminPassword_encrypted = $null
            # }
            # $vrslcm | Add-Member -Type NoteProperty -Name adminPassword -Value $adminPassword
            # $vrslcm | Add-Member -Type NoteProperty -Name rootUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH" })).username
            # $rootPassword = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrslcm.fqdn -and $_.credentialType -eq "SSH" })).password
            # if ($rootPassword) {
            #     $rootPassword_encrypted = $rootPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            # }
            # else {
            #     $rootPassword_encrypted = $null
            # }
            # $vrslcm | Add-Member -Type NoteProperty -Name rootPassword -Value $vrslcm.adminPassword

            # $var["Vrslcm"] = @{}
            # if ($vrslcm.fqdn) {
            #     $var["Vrslcm"]["name"] = $vrslcm.fqdn.Split(".")[0]
            # }
            # else {
            #     $var["Vrslcm"]["name"] = $null
            # }
            # $var["Vrslcm"]["fqdn"] = $vrslcm.fqdn
            # $var["Vrslcm"]["status"] = $vrslcm.status
            # $var["Vrslcm"]["adminUser"] = $vrslcm.adminUser
            # $var["Vrslcm"]["adminPassword"] = $adminPassword_encrypted
            # $var["Vrslcm"]["rootUser"] = $vrslcm.rootUser
            # $var["Vrslcm"]["rootPassword"] = $rootPassword_encrypted

            # $wsa = New-Object -TypeName PSCustomObject
            # $wsa | Add-Member -Type NoteProperty -Name status -Value (Get-VCFWSA).status
            # $wsa | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFWSA).loadBalancerFqdn
            # $wsa | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API" })).username
            # $wsaPassword = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $wsa.fqdn -and $_.credentialType -eq "API" })).password
            # if ($wsaPassword) {
            #     $wsaPassword_encrypted = $wsaPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            # }
            # else {
            #     $wsaPassword_encrypted = $null
            # }
            # $wsa | Add-Member -Type NoteProperty -Name adminPassword -Value $wsaPassword
            # $wsaNodes = @()
            # foreach ($node in (Get-VCFWSA).nodes.fqdn | Sort-Object) {
            #     [Array]$wsaNodes += $node.Split(".")[0]
            # }

            # $var["Wsa"] = @{}
            # if ($wsa.fqdn) {
            #     $var["Wsa"]["name"] = $wsa.fqdn.Split(".")[0]
            # }
            # else {
            #     $var["Wsa"]["name"] = $null
            # }
            # $var["Wsa"]["fqdn"] = $wsa.fqdn
            # $var["Wsa"]["status"] = $wsa.status
            # $var["Wsa"]["adminUser"] = $wsa.adminUser
            # $var["Wsa"]["adminPassword"] = $wsaPassword_encrypted
            # $var["Wsa"]["nodes"] = $wsaNodes

            # $vrops = New-Object -TypeName PSCustomObject
            # $vrops | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvROPS).status
            # $vrops | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvROPS).loadBalancerFqdn
            # $vrops | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API" })).username
            # $vropsPassword = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrops.fqdn -and $_.credentialType -eq "API" })).password
            # if ($vropsPassword) {
            #     $vropsPassword_encrypted = $vropsPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            # }
            # else {
            #     $vropsPassword_encrypted = $null
            # }

            # $vrops | Add-Member -Type NoteProperty -Name adminPassword -Value $vropsPassword
            # $vrops | Add-Member -Type NoteProperty -Name master -Value  ((Get-VCFvROPs).nodes | Where-Object { $_.type -eq "MASTER" }).fqdn
            # $vropsNodes = @()
            # foreach ($node in (Get-VCFvROPS).nodes.fqdn | Sort-Object) {
            #     [Array]$vropsNodes += $node.Split(".")[0]
            # }

            # $var["Vrops"] = @{}
            # if ($vrops.fqdn) {
            #     $var["Vrops"]["name"] = $vrops.fqdn.Split(".")[0]
            # }
            # else {
            #     $var["Vrops"]["name"] = $null
            # }
            # $var["Vrops"]["fqdn"] = $vrops.fqdn
            # $var["Vrops"]["status"] = $vrops.status
            # $var["Vrops"]["adminUser"] = $vrops.adminUser
            # $var["Vrops"]["adminPassword"] = $vropsPassword_encrypted
            # $var["Vrops"]["master"] = $vrops.master
            # $var["Vrops"]["nodes"] = $vropsNodes

            # $vra = New-Object -TypeName PSCustomObject
            # $vra | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRA).status
            # $vra | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRA).loadBalancerFqdn
            # $vraNodes = @()
            # foreach ($node in (Get-VCFvRA).nodes.fqdn | Sort-Object) {
            #     [Array]$vraNodes += $node.Split(".")[0]
            # }

            # $var["Vra"] = @{}
            # if ($vra.fqdn) {
            #     $var["Vra"]["name"] = $vra.fqdn.Split(".")[0]
            # }
            # else {
            #     $var["Vra"]["name"] = $null
            # }
            # $var["Vra"]["fqdn"] = $vra.fqdn
            # $var["Vra"]["status"] = $vra.status
            # $var["Vra"]["nodes"] = $vraNodes

            # $vrli = New-Object -TypeName PSCustomObject
            # $vrli | Add-Member -Type NoteProperty -Name status -Value (Get-VCFvRLI).status
            # $vrli | Add-Member -Type NoteProperty -Name fqdn -Value (Get-VCFvRLI).loadBalancerFqdn
            # $vrli | Add-Member -Type NoteProperty -Name adminUser -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API" })).username
            # $vrliPassword = (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $vrli.fqdn -and $_.credentialType -eq "API" })).password
            # $vrliPassword_encrypted = $null
            # if ($vrliPassword) {
            #     $vrliPassword_encrypted = $vrliPassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            # }
            # $vrli | Add-Member -Type NoteProperty -Name adminPassword -Value $vrliPassword
            # $vrliNodes = @()
            # foreach ($node in (Get-VCFvRLI).nodes.fqdn | Sort-Object) {
            #     [Array]$vrliNodes += $node.Split(".")[0]
            # }

            # $var["Vrli"] = @{}
            # if ($vrli.fqdn) {
            #     $var["Vrli"]["name"] = $vrli.fqdn.Split(".")[0]
            # }
            # else {
            #     $var["Vrli"]["name"] = $null
            # }
            # $var["Vrli"]["fqdn"] = $vrli.fqdn
            # $var["Vrli"]["status"] = $vrli.status
            # $var["Vrli"]["adminUser"] = $vrli.adminUser
            # $var["Vrli"]["adminPassword"] = $vrliPassword_encrypted
            # $var["Vrli"]["nodes"] = $vrliNodes

            # $var["RegionalWSA"] = @{}
            # $var["RegionalWSA"]["name"] = $regionalWSA

            # Get SDDC VM name from vCenter Server
            $Global:sddcmVMName
            $Global:vcHost
            $vcHostUser = ""
            $vcHostPass = ""
            if ($vcServer.fqdn) {
                Write-PowerManagementLogMessage -Type INFO -Message "Getting SDDC Manager VM Name "
                if ($DefaultVIServers) {
                    Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                }
                Connect-VIServer -server $vcServer.fqdn -user $vcUser -password $vcPass | Out-Null
                $sddcManagerIP = (Test-NetConnection -ComputerName $server).RemoteAddress.IPAddressToString
                $sddcmVMName = (Get-VM * | Where-Object { $_.Guest.IPAddress -eq $sddcManagerIP }).Name
                $vcHost = (get-vm | where Name -eq $vcServer.fqdn.Split(".")[0] | Select-Object VMHost).VMHost.Name
                $vcHostUser = (Get-VCFCredential -resourceType ESXI -resourceName $vcHost | Where-Object { $_.accountType -eq "USER" }).username
                $vcHostPass = (Get-VCFCredential -resourceType ESXI -resourceName $vcHost | Where-Object { $_.accountType -eq "USER" }).password
                $vcHostPass_encrypted = $vcHostPass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null

            }

            #2963366
            #Backup DRS Automation level settings into JSON file
            [string]$level = ""
            [string]$level = Get-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name
            $var["Cluster"]["DrsAutomationLevel"] = [string]$level

            $var["Server"]["host"] = $vcHost
            $var["Server"]["vchostuser"] = $vcHostUser
            $var["Server"]["vchostpassword"] = $vcHostPass_encrypted

            $var["SDDC"] = @{}
            $var["SDDC"]["name"] = $sddcmVMName
            $var["SDDC"]["fqdn"] = $server
            $var["SDDC"]["user"] = $user
            $var["SDDC"]["password"] = $pass | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString

            $var | ConvertTo-Json > ManagementStartupInput.json
            # Exit if json generation have selected
            if ($genjson) {
                if (Test-Path -Path "ManagementStartupInput.json" -PathType Leaf) {
                    $location = Get-Location
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "The generation of JSON is successful!"  -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "ManagementStartupInput.json is created in the $location path." -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################" -Colour Green
                    Exit
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Json file is not created, check for permissions in the $location path" -Colour Red
                    Exit
                }
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
            Exit
        }

        # Shutdown related code starts here
        # Check if SSH is enabled on the esxi hosts before proceeding with shutdown procedure
        Try {
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if (-Not $status) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
                    Exit
                }
            }
        }
        catch {
            Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to the host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
        }

        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch All PoweredOn virtual machines from the server $($vcServer.fqdn)"
        [Array]$allvms = Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass
        $customervms = @()
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch All PoweredOn vCLS virtual machines from the server $($vcServer.fqdn)"
        [Array]$vclsvms += Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)"
        foreach ($vm in $vclsvms) {
            [Array]$vcfvms += $vm
        }

        $customervms = $allvms | ? { $vcfvms -notcontains $_ }
        $vcfvms_string = $vcfvms -join "; "
        Write-PowerManagementLogMessage -Type INFO -Message "The SDDC manager managed virtual machines are: '$($vcfvms_string)' ." -Colour Cyan
        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            Write-PowerManagementLogMessage -Type INFO -Message "The SDDC manager non-managed customer virtual machines are: '$($customervms_string)' ." -Colour Cyan
        }

        $VMwareToolsNotRunningVMs = @()
        $VMwareToolsRunningVMs = @()
        foreach ($vm in $customervms) {
            $status = Get-VMwareToolsStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -vm $vm
            if ($status -eq "RUNNING") {
                [Array]$VMwareToolsRunningVMs += $vm
            }
            else {
                [Array]$VMwareToolsNotRunningVMs += $vm
            }
        }
        if (($VMwareToolsNotRunningVMs.count -ne 0) -and ($PsBoundParameters.ContainsKey("shutdownCustomerVm"))) {
            Write-PowerManagementLogMessage -Type WARNING -Message "There are some non VCF maintained virtual machines where VMWareTools NotRunning, hence unable to shutdown these VMs:$($VMwareToolsNotRunningVMs) ." -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "Unless these virtual machines are shutdown manually, we cannot proceed. Please, shutdown manually and rerun the script" -Colour Red
            Exit
        }

        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some virtual machines still in powered On state. Customer VM Shutdown option is set to true" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down Non VCF management virtual machines, to put host in maintenance mode" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management virtual machines: $($customervms_string) ." -Colour Cyan
                foreach ($vm in $customervms) {
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vm -timeout 300
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state. Customer VM Shutdown option is set to false" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down Non VCF management VMs: $($customervms_string) ." -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shutdown manually or the customer VM Shutdown option is set to true.  Please take the necessary action and rerun the script" -Colour Red
                Exit
            }
        }
        <#
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
                if ($vropsCollectorNodes) {
                    Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsCollectorNodes -timeout 600
                }
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
            }
            if ($($wsa.status -eq "ACTIVE")) {
                Request-PowerStateViaVRSLCM -server $vrslcm.fqdn -user $vrslcm.adminUser -pass $vrslcm.adminPassword -product VIDM -mode power-off -timeout 1800
            }
            if ($($vrslcm.status -eq "ACTIVE")) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm.fqdn.Split(".")[0] -timeout 600
            }
            if ($($vrli.status -eq "ACTIVE") -and $vrliNodes) {
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
            }
        }
        #>

        # Shutdown the NSX Edge Nodes
        #$checkServer = (Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded
        #if ($checkServer) {
        # # Shutdown Standalone WSA
        # if ($regionalWSA) {
        #     Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $regionalWSA -timeout 600
        # }
        # else {
        #     Write-PowerManagementLogMessage -Type WARNING -Message "No Standalone Workspace ONE Access instance present, skipping shutdown" -Colour Cyan
        # }
        if ($nsxtEdgeNodes) {
            Write-PowerManagementLogMessage -Type INFO -Message "Stopping NSX-T Edges..." -Colour Green
            Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping shutdown" -Colour Cyan
        }
        # }
        # else {
        #     Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping shutdown of $nsxtEdgeNodes" -Colour Cyan
        # }

        # Shutdown the NSX Manager Nodes
        Write-PowerManagementLogMessage -Type INFO -Message "Stopping NSX-T Managers..." -Colour Green
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600

        # Shut Down the SDDC Manager Virtual Machine in the Management Domain.
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Shut Down the vSphere Cluster Services Virtual Machines
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable

        # }
        # else {
        # Write-PowerManagementLogMessage -Type WARNING -Message "Looks like that $($vcServer.fqdn) may already be shutdown, skipping checking vSAN health for cluster $($cluster.name)" -Colour Cyan
        # }

        # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) shutdown will take time...please wait" -Colour Yellow
        $counter = 0
        $retries = 10
        $sleep_time = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount ) {
                Write-PowerManagementLogMessage -Type INFO -Message "There are still vCLS VMs running. Sleeping for $sleep_time seconds before next check."
                start-sleep $sleep_time
                $counter += 1
            }
            else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS vms did't get shutdown within stipulated timeout value. Stopping the script" -Colour Red
            Exit
        }
        
        # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
        if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
        }

        # Set DRS Automation Level to Manual in the Management Domain
        Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level Manual

        #bug-2925318
        # $checkServer = (Test-NetConnection -ComputerName $vcServer.fqdn -Port 443).TcpTestSucceeded
        # if ($checkServer) {
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-PowerManagementLogMessage -Type INFO -Message "VSAN Cluster health is Good." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN Cluster health is BAD. Please check vSAN status in vCenter Server '$($vcServer.fqdn)'. Once vSAN is fixed, please restart the script. Exiting!" -Colour Red
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            #Write-PowerManagementLogMessage -Type INFO -Message "VSAN Object Resync is successfully" -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "VSAN Object resync is running. Stopping the script. Please wait for a successfully vSAN resync and then start script again" -Colour Red
            Exit
        }

        # Verify that there is only one VM running (vCenter Server) on the ESXis, then shutdown vCenter Server.
        $runningVMs = Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass
        if ($runningVMs.count -gt 1 ) {
            Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state." -Colour Cyan
            Write-PowerManagementLogMessage -Type WARNING -Message "Unable to proceed unless they are shutdown. Kindly shutdown them manually and continue with shutdown by following VMware Cloud Foundation Documentation." -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "There are running VMs in environment: $($runningVMs). Exiting! " -Colour Red
        }
        else {
            # Shutdown vCenter Server
            Stop-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -timeout 600
            if (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running") {
                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to stop virtual center on the given host. Hence exiting" -Colour Red
            }
        }

        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        Write-PowerManagementLogMessage -Type INFO -Message "Check that there are no running VMs in the ESXi hosts, before stopping the vSAN..." -Colour Green
        $runningVMs = $False
        foreach ($esxiNode in $esxiWorkloadDomain) {
            $vms = Get-PoweredOnVMs -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
            if ($vms.count) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Looks like there are some VMs still in powered On state." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Unable to proceed unless they are shutdown. Kindly shutdown them manually and rerun the script" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn) VMs are:$($vms) " -Colour Cyan
                $runningVMs = $True
            }
            else {
            }
        } 
        if ($runningVMs) {
            Write-PowerManagementLogMessage -Type ERROR -Message "There are still VMs running on some ESXi host(s). Please check console log, stop the VMs and continue shutdown manually" -Colour Red
        }
        # Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
        else {
            # Disable cluster member updates from vCenter Server
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
            }
            # Run vSAN cluster preparation - should be done on one host per cluster
            # Sleeping 1 min before starting the preparation
            Write-PowerManagementLogMessage -Type INFO -Message "Sleeping 60 seconds before preparing hosts for vSAN shutdown..."
            Start-Sleep -s 60
            Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
            # Putting hosts in maintenance mode
            Write-PowerManagementLogMessage -Type INFO -Message "Sleeping 30 seconds before putting hosts in maintenance mode..."
            Start-Sleep -s 30
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
            }
            # End of shutdown
            Write-PowerManagementLogMessage -Type INFO -Message "End of Shutdown sequence!" -Colour Cyan
            Write-PowerManagementLogMessage -Type INFO -Message "Please shutdown ESXi hosts!" -Colour Cyan
        }
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
        Exit
    }
}


# Startup procedures
if ($PsBoundParameters.ContainsKey("startup")) {
    Try {
        $MgmtInput = Get-Content -Path $inputFile | ConvertFrom-JSON

        Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering System Details from json file"
        # Gather Details from SDDC Manager
        $workloadDomain = $MgmtInput.Domain.name
        #$workloadDomainType = $MgmtInput.Domain.type
        $cluster = New-Object -TypeName PSCustomObject
        $cluster | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Cluster.name

        #Get DRS automation level settings
        $DrsAutomationLevel = $MgmtInput.cluster.DrsAutomationLevel

        #Getting SDDC manager VM name
        $sddcmVMName = $MgmtInput.SDDC.name
        # $regionalWSA = $MgmtInput.RegionalWSA.name

        # Gather vCenter Server Details and Credentials
        $vcServer = New-Object -TypeName PSCustomObject
        $vcServer | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Server.name
        $vcServer | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Server.fqdn
        $vcUser = $MgmtInput.Server.user
        $temp_pass = convertto-securestring -string $MgmtInput.Server.password
        $temp_pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($temp_pass))))
        $vcPass = $temp_pass
        $vcHost = $MgmtInput.Server.host
        $vcHostUser = $MgmtInput.Server.vchostuser
        if ($MgmtInput.Server.vchostpassword) {
            $vchostpassword = convertto-securestring -string $MgmtInput.Server.vchostpassword
            $vchostpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vchostpassword))))
        }
        else {
            $vchostpassword = $null
        }
        $vcHostPass = $vchostpassword

        # # Gather vRealize Suite Details
        # $vrslcm = New-Object -TypeName PSCustomObject
        # $vrslcm | Add-Member -Type NoteProperty -Name status -Value $MgmtInput.Vrslcm.status
        # $vrslcm | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Vrslcm.fqdn
        # $vrslcm | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.Vrslcm.adminUser
        # if ($MgmtInput.Vrslcm.adminPassword) {
        #     $vrslcmadminpassword = convertto-securestring -string $MgmtInput.Vrslcm.adminPassword
        #     $vrslcmadminpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vrslcmadminpassword))))
        # }
        # else {
        #     $vrslcmadminpassword = $null
        # }
        # $vrslcm | Add-Member -Type NoteProperty -Name adminPassword -Value $vrslcmadminpassword
        # $vrslcm | Add-Member -Type NoteProperty -Name rootUser -Value $MgmtInput.Vrslcm.rootUser
        # if ($MgmtInput.Vrslcm.rootPassword) {
        #     $vrslcmrootpassword = convertto-securestring -string $MgmtInput.Vrslcm.rootPassword
        #     $vrslcmrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vrslcmrootpassword))))
        # }
        # else {
        #     $vrslcmrootpassword = $null
        # }
        # $vrslcm | Add-Member -Type NoteProperty -Name rootPassword -Value  $vrslcmrootpassword

        # $wsa = New-Object -TypeName PSCustomObject
        # $wsa | Add-Member -Type NoteProperty -Name status -Value $MgmtInput.Wsa.status
        # $wsa | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Wsa.fqdn
        # $wsa | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.Wsa.username
        # if ($MgmtInput.Wsa.password) {
        #     $wsapassword = convertto-securestring -string $MgmtInput.Wsa.password
        #     $wsapassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($wsapassword))))
        # }
        # else {
        #     $wsapassword = $null
        # }
        # $wsa | Add-Member -Type NoteProperty -Name adminPassword -Value $wsapassword
        # $wsaNodes = $MgmtInput.Wsa.nodes

        # $vrops = New-Object -TypeName PSCustomObject
        # $vrops | Add-Member -Type NoteProperty -Name status -Value $MgmtInput.Vrops.status
        # $vrops | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Vrops.fqdn
        # $vrops | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.Vrops.adminUser
        # if ($MgmtInput.Vrops.adminPassword) {
        #     $vropspassword = convertto-securestring -string $MgmtInput.Vrops.adminPassword
        #     $vropspassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vropspassword))))
        # }
        # else {
        #     $vropspassword = $null
        # }
        # $vrops | Add-Member -Type NoteProperty -Name adminPassword -Value $vropspassword
        # $vrops | Add-Member -Type NoteProperty -Name master -Value  $MgmtInput.Vrops.master
        # $vropsNodes = $MgmtInput.Vrops.nodes

        # $vra = New-Object -TypeName PSCustomObject
        # $vra | Add-Member -Type NoteProperty -Name status -Value $MgmtInput.Vra.status
        # $vra | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Vra.fqdn
        # $vraNodes = $MgmtInput.Vra.nodes


        # $vrli = New-Object -TypeName PSCustomObject
        # $vrli | Add-Member -Type NoteProperty -Name status -Value $MgmtInput.Vrli.status
        # $vrli | Add-Member -Type NoteProperty -Name fqdn -Value $MgmtInput.Vrli.fqdn
        # $vrli | Add-Member -Type NoteProperty -Name adminUser -Value  $MgmtInput.Vrli.adminUser
        # if ($MgmtInput.Vrli.adminPassword) {
        #     $vrlipassword = convertto-securestring -string $MgmtInput.Vrli.adminPassword
        #     $vrlipassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($vrlipassword))))
        # }
        # else {
        #     $vrlipassword = $null
        # }
        # $vrli | Add-Member -Type NoteProperty -Name adminPassword -Value $vrlipassword
        # $vrliNodes = $MgmtInput.Vrli.nodes

        # Gather ESXi Host Details for the Management Workload Domain
        $esxiWorkloadDomain = @()
        $workloadDomainArray = $MgmtInput.Hosts
        foreach ($esxiHost in $workloadDomainArray) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost.fqdn
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value $esxiHost.user
            if ($esxiHost.password) {
                $esxpassword = convertto-securestring -string $esxiHost.password
                $esxpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($esxpassword))))
            }
            else {
                $esxpassword = $null
            }
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value $esxpassword
            $esxiWorkloadDomain += $esxDetails
        }

        # Gather NSX Manager Cluster Details
        $nsxtCluster = $MgmtInput.NsxtManager
        $nsxtMgrfqdn = $MgmtInput.NsxtManager.vipfqdn
        $nsxMgrVIP = New-Object -TypeName PSCustomObject
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminUser -Value $MgmtInput.NsxtManager.user
        if ($MgmtInput.NsxtManager.password) {
            $nsxpassword = convertto-securestring -string $MgmtInput.NsxtManager.password
            $nsxpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($nsxpassword))))
        }
        else {
            $nsxpassword = $null
        }
        $nsxMgrVIP | Add-Member -Type NoteProperty -Name adminPassword -Value $nsxpassword
        $nsxtNodesfqdn = $MgmtInput.NsxtManager.nodes
        $nsxtNodes = @()
        foreach ($node in $nsxtNodesfqdn) {
            [Array]$nsxtNodes += $node.Split(".")[0]
        }


        # Gather NSX Edge Node Details
        $nsxtEdgeCluster = $MgmtInput.NsxEdge
        $nsxtEdgeNodes = $nsxtEdgeCluster.nodes
        # $nsxt_local_url = "https://$nsxtMgrfqdn/login.jsp?local=true"

        # Startup workflow starts here
        # Check if VC is running - if so, skip ESXi operations
        if (-Not (Test-NetConnection -ComputerName $vcServer.fqdn -Port 443 -WarningAction SilentlyContinue ).TcpTestSucceeded ) {
            Write-PowerManagementLogMessage -Type INFO -Message "Could not connect to $($vcServer.fqdn). Starting vSAN..."
            #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
            Try {
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                    if (-Not $status) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
                        Exit
                    }
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to SSH to the host $($esxiNode.fqdn), if SSH is not enabled, follow the steps mentioned in the doc to enable" -Colour Red
            }
    
            # Take hosts out of maintenance mode
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
            }
    
            # Prepare the vSAN cluster for startup - Performed on a single host only
            # We need some time before this setp setting hardsleep 30 sec
            Write-PowerManagementLogMessage -Type INFO -Message "Sleeping 30 seconds before starting vSAN..."
            Start-Sleep 30
            Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"
    
            # We need some time before this setp setting hardsleep 30 sec
            Write-PowerManagementLogMessage -Type INFO -Message "Sleeping 30 seconds before enabling vSAN updates..."
            Start-Sleep 30
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
            }
    
            Write-PowerManagementLogMessage -Type INFO -Message "Chgeck vSAN status for ESXi hosts." -Colour Green
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
            }

            # Startup the Management Domain vCenter Server
            Start-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.Name -timeout 600
            Start-Sleep 5
            if (-Not (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running")) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Unable to start virtual center on the given host. Hence exiting" -Colour Red
                Exit
            }
        }
        else {
            Write-PowerManagementLogMessage -Type INFO -Message "vCenter server '$($vcServer.fqdn)' is running - skipping vSAN startup!" -Colour Cyan
        }
        
        # Wait till VC is started, continue if it is already started
        Write-PowerManagementLogMessage -Type INFO -Message "Waiting for vCenter services on $($vcServer.fqdn) to start..."
        $retries = 20
        if ($DefaultVIServers) {
            Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
        }
        While ($retries) {
            Connect-VIServer -server $vcServer.fqdn -user $vcUser -pass $vcPass -ErrorAction SilentlyContinue | Out-Null
            if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                #Max wait time for services to come up is 10 mins.
                for ($i = 0; $i -le 10; $i++) {
                    $status = Get-VAMIServiceStatus -server $vcServer.fqdn -user $vcUser  -pass $vcPass -service 'vsphere-ui' -nolog
                    if ($status -eq "STARTED") {
                        break
                    }
                    else {
                        Write-PowerManagementLogMessage -Type INFO -Message "The services on Virtual Center is still starting. Please wait. Sleeping for 60 seconds..."
                        Start-Sleep 60
                    }
                }
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Write-PowerManagementLogMessage -Type INFO -Message "The Virtual Center API is still down. Please wait. Sleeping for 60 seconds..."
            Start-Sleep 60
            $retries -= 1
        }
        # Check if VC have been started in the above time period
        if (!$retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Timeout while waiting vCenter Server to start. Exiting!" -Colour Red
        }

        # Check vSAN Status
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN Cluster health is BAD. Please check and rerun the script" -Colour Red
            Exit
        }
        if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "VSAN Object resync is in progress. Please check and rerun the script" -Colour Red
            Exit
        }

        # Start vSphere HA
        if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'." -Colour Red
        }

        #2963366: restore the DRS Automation Level to the mode backed up for both the Management Domain Clusters during shutdown
        if ([string]::IsNullOrEmpty($DrsAutomationLevel)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "DrsAutomationLevel value seem empty in the json file. Exiting!" -Colour Red
            Exit
        }
        else {
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level $DrsAutomationLevel
        }

        # Startup the vSphere Cluster Services Virtual Machines in the Management Workload Domain
        Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
        # Waiting for vCLS VMs to be started for ($retries*10) seconds
        Write-PowerManagementLogMessage -Type INFO -Message "Retreat Mode has been set, vSphere Cluster Services Virtual Machines (vCLS) startup will take time...please wait" -Colour Yellow
        $counter = 0
        $retries = 10
        $sleep_time = 30
        while ($counter -ne $retries) {
            $powerOnVMcount = (Get-PoweredOnVMs -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
            if ( $powerOnVMcount -lt 3 ) {
                Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleep_time seconds before next check."
                start-sleep $sleep_time
                $counter += 1
            }
            else {
                Break
            }
        }
        if ($counter -eq $retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS vms did't get started within stipulated timeout value. Stopping the script" -Colour Red
            Exit
        }

        #Startup the SDDC Manager Virtual Machine in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Startup the NSX Manager Nodes in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "NSX-T Cluster is not in 'STABLE' state. Exiting!" -Colour Red
            Exit
        }

        # Startup the NSX Edge Nodes in the Management Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX-T Data Center Edge Nodes present, skipping startup" -Colour Cyan
        }

        # Startup the Standalone WSA in the Management Domain
        # if ($regionalWSA) {
        #     Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $regionalWSA -timeout 600
        # }
        # else {
        #     Write-PowerManagementLogMessage -Type WARNING -Message "No Standalone Workspace ONE Access instance is present, skipping startup" -Colour Cyan
        # }

        <#  Vrealize is not supported
        # Startup vRealize Suite
        if ($($WorkloadDomainType) -eq "MANAGEMENT") {
            if ($($vrslcm.status -eq "ACTIVE")) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrslcm.fqdn.Split(".")[0] -timeout 600
            }
            if ($($vrli.status -eq "ACTIVE") -and $vrliNodes) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vrliNodes -timeout 600
            }
            if ($($vrops.status -eq "ACTIVE") -and $vropsNodes) {
                Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsNodes -timeout 600
                # Sleep before start quering API - TODO needs better handling with a loop.
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping 5 min in order to allow vROps API to start..." -Colour Yellow
                Start-Sleep -s 300

                $vropsCollectorNodes = @()
                foreach ($node in (Get-vROPSClusterDetail -server $vrops.master -user $vrops.adminUser -pass $vrops.adminPassword | Where-Object {$_.role -eq "REMOTE_COLLECTOR"} | Select-Object name)) {
                    [Array]$vropsCollectorNodes += $node.name
                }
                if ($vropsCollectorNodes) {
                    Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $vropsCollectorNodes -timeout 600
                }
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
#>
        # End of startup
        Write-PowerManagementLogMessage -Type INFO -Message "Kindly Power On customer deployed Virtual Machines not managed by SDDC Manager manually" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "End of startup sequence. Please check your environment" -Colour Yellow
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
        Exit
    }
}