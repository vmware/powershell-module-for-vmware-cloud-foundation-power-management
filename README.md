# **Description:**
This is a library of scripts written in powershell to do the functional testing following Startup and shutdown guide, available at the following location.  
https://docs.vmware.com/en/VMware-Cloud-Foundation/4.3/vcf-operations/GUID-65F5FE47-5831-4C72-B0DB-9D0C537446E2.html

# How to Use:
Download the code by doing git cloning  
    git clone https://gitlab.eng.vmware.com/cloud_foundation/dey-team/pweiss-team/lmahadevan-team/shutdownandstartup.git

There is one library file, **VMware.PowerManagement.psm1** which has collection of functions and there is a folder by name SampleScripts, which contains list of powershell script files. Each powershell script is used to shutdown/startup respective domains.  
SampleScripts folder contains :
```
ManagementStartupInput.json -- Provide input about ManagementDomain hosts and VC server When SDDC is down as part of shutdown sequence
PowerManagement-ManagementDomain.ps1  -- To Shutdown/Startup Management Domain
PowerManagement-Tanzu.ps1  -- To Shutdown/Startup Tanzu workload Domain
PowerManagement-WorkloadDomain.ps1  -- To Shutdown/Startup Virtual Infrastructure Workload Domain
PowerManagement-vRealizeSuite.ps1  -- To Shutdown/Startup Vreliaze Suite components.
```

The module file (.psm1 extension) has to be imported to access the functions. Execute the below PowerShell command to import.
``` 
Import-Module VMware.PowerManagement.psm1
```


In the Powershell script files, you see some options, listed below are the usages of the same. 

**Custom Cmdlets are:**
``` 
    Start-CloudComponent <=> Startup the component on a given server . 
    Stop-CloudComponent <=> Shutdown the component on a given server. 
    Execute-OnEsx <=> Execute a given command on the esxi host . 
```

**Options used are:**
```
 -server <=> refers to Management or Workload VC or Esxi host on which we are initiating shutdown/startup of components . 
 -nodes <=> refers to list of comma separated VM's to be shutdown on the VC or host . 
 -user <=> Username to login to the server . 
 -pass <=> Password to login to the server . 
 -force <=> The Foce parameter is used as a consent to shutdown non VCF management vm's automatically while putting host 
            in maintenence mode
 -timeout <=> Max time to wait for shutdown/startup to complete. Default is 120 . 
 -pattern <=> Pattern to search list of VMs.  
 -command <=> command to be executed on esxi host . 
 -expected <=> Any string to be matched in the received output, if not given status=0 signifies pass case.  
 ```