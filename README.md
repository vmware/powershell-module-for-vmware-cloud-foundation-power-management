# **Description:**
This is a library of scripts written in powershell to do the functional testing following Startup and shutdown guide, available at the following location.  
https://docs.vmware.com/en/VMware-Validated-Design/6.2/sddc-shutdown-and-startup/GUID-79F77366-24C6-4F19-812D-08C2EFFBA363.html

# How to Use:
Download the code by doing git cloning  
    git clone https://gitlab.eng.vmware.com/cloud_foundation/dey-team/pweiss-team/lmahadevan-team/shutdownandstartup.git

You will have two files downloaded. One **VMware.PowerManagement.psm1** file which is library of functions and another is the launcher file **Testcases.ps1**, which has all test cases.  

The module file (.psm1 extension) has to be put in the path where PowerShell modules are accessed on the server where you have downloaded the code.  

Execute the below PowerShell command  
 **$env:PSModulePath**  
Try this path **“C:\Program Files\WindowsPowerShell\Modules”**. If not, search in all the other paths to figure out where is VMware.PowerCLI module resides. In that path, create a folder by the name VMware.PowerManagement and then add the .psm1 into this folder   

Once done, in the PowerShell window, see if you could import this new module by executing the command   
``` 
Import-Module VMware.PowerManagement
```

Now edit the **Testcases.ps1** file to provide information about your testbed and run it. This will shut down the VI Workload domain in your testbed . 

In the Testcaes file, you see some options, listed below are the usages of the same . 

**Custom Cmdlets are:**
``` 
    ShutdownStartup-SDDCComponent <=> Shutdown/Startup the component on a given server . 
    ShutdownStartup-ComponentOnHost <=> Shutdown/Startup list of all vms matching a pattern on a given host . 
    Execute-OnEsx <=> Execute a given command on the esxi host . 
```

**Options used are:**
```
 -Server <=> refers to Management or Workload VC or Esxi host on which we are initiating shutdown of components . 
 -Nodes <=> refers to list of comma separated VM's to be shutdown on the VC or host . 
 -User <=> Username to login to the server . 
 -Pass <=> Password to login to the server . 
 -timeout <=> Max time to wait for shutdown/startup to complete. Default is 120 . 
 -pattern <=> Patten to search list of VMs.  
 -task <=> By default it is "Shutdown" if you want to do startup please use "Startup" . 
 -command <=> command to be executed on esxi host . 
 -expected <=> Any string to be matched in the received output, if not given status=0 signifies pass case.  
 ```