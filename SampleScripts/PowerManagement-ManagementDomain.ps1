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
    .Version:       1.0 (Build 1000)
    .Date:          2022-28-06
    ===============================================================================================================

    .CHANGE_LOG

    - 0.6.0   (Gary Blake / 2022-02-22) - Initial release
    - 1.0.0.1000   (Gary Blake / 2022-28-06) - GA version

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
    Initiates a ManagementStartupInput.json generation that could be used for startup.
    Notes:
        File generated earlier may not have all needed details for startup, since the environment may have changed (e.g. ESXi hosts that vCenter Server is running on)
        The file will be generated in the current directory and any file with the same name "ManagementStartupInput.json" will be overwritten

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

# Customer Questions Section 
Try {
    Clear-Host; Write-Host ""
    Start-SetupLogFile -Path $PSScriptRoot -ScriptName $MyInvocation.MyCommand.Name
    Write-PowerManagementLogMessage -Type INFO -Message "Setting up the log file to path $logfile"
    $Global:ProgressPreference = 'SilentlyContinue'
    if ($PsBoundParameters.ContainsKey("shutdown")) {
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { $customerVmMessage = "Process WILL gracefully shutdown customer deployed Virtual Machines, if deployed within the Management Domain" }
        else { $customerVmMessage = "Process WILL NOT gracefully shutdown customer deployed Virtual Machines not managed by VCF, if deployed within the Management Domain" }
    }
    if ($PsBoundParameters.ContainsKey("startup")) {
        $defaultFile = "./ManagementStartupInput.json"
        $inputFile = $null
        if ($json) {
            Write-PowerManagementLogMessage -Type INFO -Message "The input JSON file provided." -Colour Green
            $inputFile = $json
        }
        elseif (Test-Path -Path $defaultFile -PathType Leaf) {
            Write-PowerManagementLogMessage -Type INFO -Message "No path to JSON provided in the command line. Using the auto-created input file ManagementStartupInput.json in the current directory." -Colour Yellow
            $inputFile = $defaultFile
        } 
        if ([string]::IsNullOrEmpty($inputFile)) {
            Write-PowerManagementLogMessage -Type WARNING -Message "JSON input file is not provided. Cannot proceed! Exiting! " -Colour Cyan
            Exit
        }
        Write-Host "";
        $proceed = Read-Host "The following JSON file $inputFile will be used for the operation, please confirm (Yes or No)[default:No]"
        if (-Not $proceed) {
            Write-PowerManagementLogMessage -Type WARNING -Message "None of the options is selected. Default is 'No', hence stopping script execution." -Colour Cyan
            Exit
        }
        else {
            if (($proceed -match "no") -or ($proceed -match "yes")) {
                if ($proceed -match "no") {
                    Write-PowerManagementLogMessage -Type WARNING -Message "Stopping script execution because the input is 'No'." -Colour Cyan
                    Exit
                }
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Pass the right string, either 'Yes' or 'No'." -Colour Cyan
                Exit
            }
        }

        Write-PowerManagementLogMessage -Type INFO -Message "'$inputFile' is checked for correctness, proceeding with the execution."
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
    if (-Not $null -eq $customerVmMessage) { Write-PowerManagementLogMessage -Type INFO -Message $customerVmMessage -Colour Yellow }
}
Catch {
    Debug-CatchWriterForPowerManagement -object $_
    Exit
}

# Shutdown procedure and json generation
if ($PsBoundParameters.ContainsKey("shutdown") -or $PsBoundParameters.ContainsKey("genjson")) {
    Try {
        # Check connection to SDDC Manager 
        Write-PowerManagementLogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to gather system details."
        if (!(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot communicate with SDDC Manager ($server). Check the FQDN or IP address or the power state of '$server'." -Colour Red
            Exit
        }
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } 
        if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Cyan } 
        if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        if ($accessToken) {
            Write-PowerManagementLogMessage -Type INFO -Message "Connection to SDDC Manager has been validated successfully." -Colour Green
            Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from the SDDC Manager inventory. It will take some time."
            $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.type -eq "MANAGEMENT" }
            # Check if we have single cluster in the MGMT domain
            if ($workloadDomain.clusters.id.count -gt 1) {
                Write-PowerManagementLogMessage -Type ERROR -Message "There are multiple clusters in Management domain. This script supports only a single cluster per domain. Exiting!" -Colour Red
                Exit
            }
            $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }
            $SDDCVer = Get-vcfmanager | select version | Select-String -Pattern '\d+\.\d+' -AllMatches | ForEach-Object {$_.matches.groups[0].value}

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
                Write-PowerManagementLogMessage -Type WARNING -Message "Could not connect to $($vcServer.fqdn)! The script could not continue without a connection to the management vCenter Server. " -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "Please check the current state and resolve the issue or continue with the shutdown operation by following the documentation of VMware Cloud Foundation. Exiting!" -Colour Red
                Exit
            }
            $status = Get-TanzuEnabledClusterStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name 
            if ($status -eq $True) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Currently we are not supporting VMware Tanzu enabled domains. Please try on other workload domains." -Colour Red
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
                $state = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern $nsxtManager -exactMatch -silence
                if ($state) { $nsxManagerPowerOnVMs += 1 }
                # If we have all NSX-T managers running, or minimum 2 nodes up - query NSX-T for edges.
                if (($nsxManagerPowerOnVMs -eq $nsxtNodes.count) -or ($nsxManagerPowerOnVMs -eq 2)) { 
                    $statusOfNsxtClusterVMs = 'running'
                }
            }
            if ($statusOfNsxtClusterVMs -ne 'running') {
                Write-PowerManagementLogMessage -Type WARNING -Message "NSX Manager VMs have been stopped. NSX Edge VMs will not be handled automatically." -Colour Cyan
            }
            else { 
                Try {
                    Write-PowerManagementLogMessage -Type INFO -Message "NSX Manager VMs have been in Running State. Trying to fetch NSX Edge VMs."
                    [Array]$edgeNodes = (Get-EdgeNodeFromNSXManager -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword -VCfqdn $VcServer.fqdn)
                    Write-PowerManagementLogMessage -Type INFO -Message "The NSX Edge VMs are" + ($edgeNodes -join ",")
                }
                catch {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Something went wrong! Cannot fetch NSX Edge nodes information from NSX Manager '$nsxtMgrfqdn'. Exiting!" -Colour Red
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

            # Get SDDC VM name from vCenter Server
            $Global:sddcmVMName
            $Global:vcHost
            $vcHostUser = ""
            $vcHostPass = ""
            if ($vcServer.fqdn) {
                Write-PowerManagementLogMessage -Type INFO -Message "Getting SDDC Manager VM name ..."
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
            $var["SDDC"]["version"] = $SDDCVer

            $var | ConvertTo-Json > ManagementStartupInput.json
            # Exit if json generation have selected
            if ($genjson) {
                if (Test-Path -Path "ManagementStartupInput.json" -PathType Leaf) {
                    $location = Get-Location
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################" -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "JSON generation is successful!"  -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "ManagementStartupInput.json is created in the $location path." -Colour Green
                    Write-PowerManagementLogMessage -Type INFO -Message "#############################################################" -Colour Green
                    Exit
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "JSON file is not created. Check for permissions in the $location path" -Colour Red
                    Exit
                }
            }
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot obtain an access token from SDDC Manager ($server). Check your credentials." -Colour Red
            Exit
        }

        # Shutdown related code starts here
        # Check if SSH is enabled on the esxi hosts before proceeding with shutdown procedure
        Try {
            foreach ($esxiNode in $esxiWorkloadDomain) {
                $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                if (-Not $status) {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                    Exit
                }
            }
        }
        catch {
            Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
        }

        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on virtual machines from server $($vcServer.fqdn)..."
        [Array]$allvms = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
        $customervms = @()
        Write-PowerManagementLogMessage -Type INFO -Message "Trying to fetch all powered-on vCLS virtual machines from server $($vcServer.fqdn)..."
        [Array]$vclsvms += Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence
        foreach ($vm in $vclsvms) {
            [Array]$vcfvms += $vm
        }

        $customervms = $allvms | ? { $vcfvms -notcontains $_ }
        $vcfvms_string = $vcfvms -join "; "
        Write-PowerManagementLogMessage -Type INFO -Message "Management virtual machines covered by the script: '$($vcfvms_string)' ." -Colour Cyan
        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            Write-PowerManagementLogMessage -Type INFO -Message "Virtual machines not covered by the script: '$($customervms_string)' . Those VMs will be stopped in a random order if the 'shutdownCustomerVm' flag is passed." -Colour Cyan
        }

        # Check if VMware Tools are running in the customer VMs - if not we could not stop them gracefully
        if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) { 
            $VMwareToolsNotRunningVMs = @()
            $VMwareToolsRunningVMs = @()
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if (( Test-NetConnection -ComputerName $vcServer.fqdn -Port 443 ).TcpTestSucceeded) {
                Write-PowerManagementLogMessage -Type INFO -Message "Connecting to '$($vcServer.fqdn)' ..."
                Connect-VIServer -Server $vcServer.fqdn -Protocol https -User $vcUser -Password $vcPass -ErrorVariable $vcConnectError | Out-Null
                if ($DefaultVIServer.Name -eq $vcServer.fqdn) {
                    Write-PowerManagementLogMessage -type INFO -Message "Connected to server '$($vcServer.fqdn)' and trying to get VMwareTools Status."
                    foreach ($vm in $customervms) {
                        Write-PowerManagementLogMessage -type INFO -Message "Checking VMwareTools Status for '$vm'..."
                        $vm_data = Get-VM -Name $vm
                        if ($vm_data.ExtensionData.Guest.ToolsRunningStatus -eq "guestToolsRunning") {
                            [Array]$VMwareToolsRunningVMs += $vm
                        }
                        else {
                            [Array]$VMwareToolsNotRunningVMs += $vm
                        }
                    }
                }
                else {
                    Write-PowerManagementLogMessage -Type ERROR -Message "Unable to connect to vCenter Server '$($vcServer.fqdn)'. Command returned the following error: '$vcConnectError'." -Colour Red
                }
            }
            # Disconnect from the VC
            if ($DefaultVIServers) {
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
            }
            if ($VMwareToolsNotRunningVMs.count -ne 0) {
                $noToolsVMs = $VMwareToolsNotRunningVMs -join "; "
                Write-PowerManagementLogMessage -Type WARNING -Message "There are some non VCF maintained VMs where VMwareTools NotRunning, hence unable to shutdown these VMs:'$noToolsVMs'." -Colour cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "Unless these VMs are shutdown manually, we cannot proceed. Please shutdown manually and rerun the script." -Colour Red
                Exit
            }
        }

        if ($customervms.count -ne 0) {
            $customervms_string = $customervms -join "; "
            if ($PsBoundParameters.ContainsKey("shutdownCustomerVm")) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is passed to the script." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence shutting down VMs not managed by SDDC Manager to put the host in maintenance mode." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "The list of Non VCF management VMs: '$customervms_string'." -Colour Cyan
                # Stop Customer VMs with one call to VC:
                Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $customervms -timeout 300
            }
            else {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state. -shutdownCustomerVm is not passed to the script." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Hence not shutting down management VMs not managed by SDDC Manager: $($customervms_string) ." -Colour Cyan
                Write-PowerManagementLogMessage -Type ERROR -Message "The script cannot proceed unless these VMs are shut down manually or the -shutdownCustomerVm option is present.  Take the necessary action and run the script again." -Colour Red
                Exit
            }
        }

        if ($nsxtEdgeNodes) {
            Write-PowerManagementLogMessage -Type INFO -Message "Stopping the NSX Edge nodes..." -Colour Green
            Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping shutdown..." -Colour Cyan
        }

        #Stop NSX-T Manager nodes
        Write-PowerManagementLogMessage -Type INFO -Message "Stopping the NSX Manager nodes..." -Colour Green
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600


        #Test VSAN health before SDDC manager is down, needed for VSAN 4.5
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "vSAN cluster health is good." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "vSAN cluster health is bad. Check the vSAN status in vCenter Server '$($vcServer.fqdn)'. Once vSAN is fixed, run the script again." -Colour Cyan
            Write-PowerManagementLogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue by following the documentation of VMware Cloud Foundation. " -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN cluster health is bad. Check the messages above for a solution." -Colour Red
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "VSAN object resynchronization is successful." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script. Wait until the vSAN object resynchronization completes and run script again." -Colour Red
            Exit
        }

        # Shut Down the SDDC Manager Virtual Machine in the Management Domain.
        Stop-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        #Need to place if block in here
        if ([float]$SDDCVer -lt 4.5) {

            # Shut Down the vSphere Cluster Services Virtual Machines
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode enable

            # Waiting for vCLS VMs to be stopped for ($retries*10) seconds
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS shutdown will take time. Please wait!" -Colour Yellow
            $counter = 0
            $retries = 10
            $sleep_time = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)").count
                if ( $powerOnVMcount ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "Some vCLS VMs are still running. Sleeping for $sleep_time seconds until the next check..."
                    start-sleep $sleep_time
                    $counter += 1
                }
                else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS VMs were not shut down within the expected time. Stopping the script execution... " -Colour Red
                Exit
            }

            # Stop vSphere HA to avoid "orphaned" VMs during vSAN shutdown
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -disableHA)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not disable vSphere High Availability for cluster '$cluster'. Exiting!" -Colour Red
            }

            # Set DRS Automation Level to Manual in the Management Domain
            Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level Manual
        }

        #Testing VSAN health after SDDC manager is down
        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "vSAN cluster health is good." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "vSAN cluster health is bad. Check the vSAN status in vCenter Server '$($vcServer.fqdn)'. Once vSAN is fixed, run the script again." -Colour Cyan
            Write-PowerManagementLogMessage -Type WARNING -Message "If the script has reached ESXi vSAN shutdown previously, this error is expected. Continue by following the documentation of VMware Cloud Foundation. " -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN cluster health is bad. Check the messages above for a solution." -Colour Red
            Exit
        }
        if ((Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -eq 0) {
            Write-PowerManagementLogMessage -Type INFO -Message "VSAN object resynchronization is successful." -Colour Green
        }
        else {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is running. Stopping the script. Wait until the vSAN object resynchronization completes and run script again." -Colour Red
            Exit
        }

        # Verify that there is only one VM running (vCenter Server) on the ESXis, then shutdown vCenter Server.
        $runningVMs = Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -silence
        if ($runningVMs.count -gt 1 ) {
            Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state." -Colour Cyan
            Write-PowerManagementLogMessage -Type WARNING -Message "Cannot proceed unless the power-on VMs are shut down. Shut them down them manually and continue with the shutdown operation by following documentation of VMware Cloud Foundation." -Colour Cyan
            Write-PowerManagementLogMessage -Type ERROR -Message "There are running VMs in environment: $($runningVMs). Exiting! " -Colour Red
        }
        else {
            Write-PowerManagementLogMessage -Type INFO -Message "There are no VM's in the powered-on state, hence shutting down Virtual Center."
            # Shutdown vCenter Server
            Stop-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -timeout 600
            if (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running") {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot stop vCenter Server on the host. Exiting!" -Colour Red
            }
        }

        # Verify that there are no running VMs on the ESXis and shutdown the vSAN cluster.
        Write-PowerManagementLogMessage -Type INFO -Message "Checking that there are no running VMs on the ESXi hosts before stopping vSAN." -Colour Green
        $runningVMs = $False
        foreach ($esxiNode in $esxiWorkloadDomain) {
            $vms = Get-VMsWithPowerStatus -powerstate "poweredon" -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -silence
            if ($vms.count) {
                Write-PowerManagementLogMessage -Type WARNING -Message "Some VMs are still in powered-on state." -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "Cannot to proceed unless the powered-on VMs are shut down. Shut down them down manually and run the script again" -Colour Cyan
                Write-PowerManagementLogMessage -Type WARNING -Message "ESXi with VMs running: $($esxiNode.fqdn) VMs are:$($vms) " -Colour Cyan
                $runningVMs = $True
            }
        } 
        if ($runningVMs) {
            Write-PowerManagementLogMessage -Type ERROR -Message "There are still running VMs on some ESXi host(s). Check the console log, stop the VMs and continue the shutdown operation manually." -Colour Red
        }
        # Actual vSAN and ESXi shutdown happens here - once we are sure that there are no VMs running on hosts
        else {
            if ([float]$SDDCVer -lt 4.5) {
                # Disable cluster member updates from vCenter Server
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 1 /VSAN/IgnoreClusterMemberListUpdates"
                }
                # Run vSAN cluster preparation - should be done on one host per cluster
                # Sleeping 1 min before starting the preparation
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 60 seconds before preparing hosts for vSAN shutdown..."
                Start-Sleep -s 60
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster preparation is done" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py prepare"
                # Putting hosts in maintenance mode
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before putting hosts in maintenance mode..."
                Start-Sleep -s 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state ENABLE
                }
                # End of shutdown
                Write-PowerManagementLogMessage -Type INFO -Message "End of the shutdown sequence!" -Colour Cyan
                Write-PowerManagementLogMessage -Type INFO -Message "Please shut down the ESXi hosts!" -Colour Cyan
            } else {
                #lock in mode API call comes here
                #VSAN cluster wizard automation comes in here
                #Verify if all ESXi hosts are down in here to conclude End of Shutdown sequence
            }
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
        Write-PowerManagementLogMessage -Type INFO -Message "Gathering system details from JSON file..."
        # Gather Details from SDDC Manager
        $workloadDomain = $MgmtInput.Domain.name
        $cluster = New-Object -TypeName PSCustomObject
        $cluster | Add-Member -Type NoteProperty -Name Name -Value $MgmtInput.Cluster.name

        #Get DRS automation level settings
        $DrsAutomationLevel = $MgmtInput.cluster.DrsAutomationLevel

        #Getting SDDC manager VM name
        $sddcmVMName = $MgmtInput.SDDC.name
        $SDDCVer = $MgmtInput.SDDC.version

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

        # Startup workflow starts here
        # Check if VC is running - if so, skip ESXi operations
        if (-Not (Test-NetConnection -ComputerName $vcServer.fqdn -Port 443 -WarningAction SilentlyContinue ).TcpTestSucceeded ) {
            Write-PowerManagementLogMessage -Type INFO -Message "Could not connect to $($vcServer.fqdn). Starting vSAN..."
            if ([float]$SDDCVer -gt 4.4) {
                #Add logic here to inform customers to start all the ESXi hosts manually, create an interactive wait prompt.
            }
            #Check if SSH is enabled on the esxi hosts before proceeding with startup procedure
            Try {
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    $status = Get-SSHEnabledStatus -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password
                    if (-Not $status) {
                        Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
                        Exit
                    }
                }
            }
            catch {
                Write-PowerManagementLogMessage -Type ERROR -Message "Cannot open an SSH connection to host $($esxiNode.fqdn). If SSH is not enabled, follow the steps in the documentation to enable it." -Colour Red
            }
    
            # Take hosts out of maintenance mode
            foreach ($esxiNode in $esxiWorkloadDomain) {
                Set-MaintenanceMode -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -state DISABLE
            }

            if ([float]$SDDCVer -lt 4.5) {
                # Prepare the vSAN cluster for startup - Performed on a single host only
                # We need some time before this step, setting hard sleep 30 sec
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before starting vSAN..."
                Start-Sleep 30
                Invoke-EsxCommand -server $esxiWorkloadDomain.fqdn[0] -user $esxiWorkloadDomain.username[0] -pass $esxiWorkloadDomain.password[0] -expected "Cluster reboot/poweron is completed successfully!" -cmd "python /usr/lib/vmware/vsan/bin/reboot_helper.py recover"

                # We need some time before this step, setting hard sleep 30 sec
                Write-PowerManagementLogMessage -Type INFO -Message "Sleeping for 30 seconds before enabling vSAN updates..."
                Start-Sleep 30
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Value of IgnoreClusterMemberListUpdates is 0" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
                }

                Write-PowerManagementLogMessage -Type INFO -Message "Checking vSAN status of the ESXi hosts." -Colour Green
                foreach ($esxiNode in $esxiWorkloadDomain) {
                    Invoke-EsxCommand -server $esxiNode.fqdn -user $esxiNode.username -pass $esxiNode.password -expected "Local Node Health State: HEALTHY" -cmd "esxcli vsan cluster get"
                }

                # Startup the Management Domain vCenter Server
                Start-CloudComponent -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.Name -timeout 600
                Start-Sleep 5
                if (-Not (Get-VMRunningStatus -server $vcHost -user $vcHostUser -pass $vcHostPass -pattern $vcServer.fqdn.Split(".")[0] -Status "Running")) {

                    Write-PowerManagementLogMessage -Type Warning -Message "Cannot start vCenter Server on the host. Check if vCenter Server is located on host $vcHost. " -Colour Red
                    Write-PowerManagementLogMessage -Type Warning -Message "Start vCenter Server manually and run the script again." -Colour Red
                    Write-PowerManagementLogMessage -Type ERROR -Message "Could not start vCenter Server on host $vcHost. Check the console log for more details." -Colour Red
                    Exit
                }
            }
        }
        else {
            Write-PowerManagementLogMessage -Type INFO -Message "vCenter Server '$($vcServer.fqdn)' is running. Skipping vSAN startup!" -Colour Cyan
        }

        #########if version block ends here##################################################################
        
        # Wait till VC is started, continue if it is already started
        Write-PowerManagementLogMessage -Type INFO -Message "Waiting for the vCenter Server services on $($vcServer.fqdn) to start..."
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
                        Write-PowerManagementLogMessage -Type INFO -Message "The services on vCenter Server are still starting. Please wait. Sleeping for 60 seconds..."
                        Start-Sleep 60
                    }
                }
                Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
                break
            }
            Write-PowerManagementLogMessage -Type INFO -Message "The vCenter Server API is still not accessible. Please wait. Sleeping for 60 seconds..."
            Start-Sleep 60
            $retries -= 1
        }
        # Check if VC have been started in the above time period
        if (!$retries) {
            Write-PowerManagementLogMessage -Type ERROR -Message "Timeout while waiting vCenter Server to start. Exiting!" -Colour Red
        }

        #Restart Cluster Via Wizard
        if ([float]$SDDCVer -gt 4.4) {
             #Restart Cluster Via Wizard
        }
        # Check vSAN Status
        if ( (Test-VsanObjectResync -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN object resynchronization is in progress. Check your environment and run the script again." -Colour Red
            Exit
        }

        if ( (Test-VsanHealth -cluster $cluster.name -server $vcServer.fqdn -user $vcUser -pass $vcPass) -ne 0) {
            Write-PowerManagementLogMessage -Type ERROR -Message "vSAN cluster health is bad. Check your environment and run the script again." -Colour Red
            Exit
        }

        #Restart Cluster Via Wizard
        if ([float]$SDDCVer -gt 4.4) {
             ####lockinmode setting reversal

            # Start vSphere HA
            if (!$(Set-VsphereHA -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -enableHA)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "Could not enable vSphere High Availability for cluster '$cluster'." -Colour Red
            }

            # Restore the DRS Automation Level to the mode backed up for Management Domain Cluster during shutdown
            if ([string]::IsNullOrEmpty($DrsAutomationLevel)) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The DrsAutomationLevel value in the JSON file is empty. Exiting!" -Colour Red
                Exit
            }
            else {
                Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level $DrsAutomationLevel
            }

            # Startup the vSphere Cluster Services Virtual Machines in the Management Workload Domain
            Set-Retreatmode -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -mode disable
            # Waiting for vCLS VMs to be started for ($retries*10) seconds
            Write-PowerManagementLogMessage -Type INFO -Message "vCLS retreat mode has been set. vCLS virtual machines startup will take some time. Please wait" -Colour Yellow
            $counter = 0
            $retries = 10
            $sleep_time = 30
            while ($counter -ne $retries) {
                $powerOnVMcount = (Get-VMsWithPowerStatus -powerstate "poweredon" -server $vcServer.fqdn -user $vcUser -pass $vcPass -pattern "(^vCLS-\w{8}-\w{4}-\w{4}-\w{4}-\w{12})|(^vCLS\s*\(\d+\))|(^vCLS\s*$)" -silence).count
                if ( $powerOnVMcount -lt 3 ) {
                    Write-PowerManagementLogMessage -Type INFO -Message "There are $powerOnVMcount vCLS virtual machines running. Sleeping for $sleep_time seconds until the next check."
                    start-sleep $sleep_time
                    $counter += 1
                }
                else {
                    Break
                }
            }
            if ($counter -eq $retries) {
                Write-PowerManagementLogMessage -Type ERROR -Message "The vCLS virtual machines did not start within the expected time. Stopping script execution." -Colour Red
                Exit
            }
        }

        #Startup the SDDC Manager Virtual Machine in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $sddcmVMName -timeout 600

        # Startup the NSX Manager Nodes in the Management Workload Domain
        Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtNodes -timeout 600
        if (!(Wait-ForStableNsxtClusterStatus -server $nsxtMgrfqdn -user $nsxMgrVIP.adminUser -pass $nsxMgrVIP.adminPassword)) {
            Write-PowerManagementLogMessage -Type ERROR -Message "NSX Manager cluster is not in 'STABLE' state. Exiting!" -Colour Red
            Exit
        }

        # Startup the NSX Edge Nodes in the Management Workload Domain
        if ($nsxtEdgeNodes) {
            Start-CloudComponent -server $vcServer.fqdn -user $vcUser -pass $vcPass -nodes $nsxtEdgeNodes -timeout 600
        }
        else {
            Write-PowerManagementLogMessage -Type WARNING -Message "No NSX Edge nodes present. Skipping startup..." -Colour Cyan
        }

        # End of startup
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "vSphere vSphere High Availability has been enabled by the script. Please disable it per your environment's design." -Colour Cyan
        Write-PowerManagementLogMessage -Type INFO -Message "Check your environment and start any additional virtual machines that you host in the management domain." -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "Use the following command to automatically start VMs" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "Start-CloudComponent -server $($vcServer.fqdn) -user $vcUser -pass $vcPass -nodes <comma separated customer vms list> -timeout 600" -Colour Yellow
        Write-PowerManagementLogMessage -Type INFO -Message "If you have enabled SSH for the ESXi hosts in management domain, you disable it at this point." -Colour Cyan
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "End of the startup sequence!" -Colour Green
        Write-PowerManagementLogMessage -Type INFO -Message "##################################################################################" -Colour Green
    }
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
        Exit
    }
}