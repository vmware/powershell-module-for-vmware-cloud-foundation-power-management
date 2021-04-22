
#Start vSAN and the ESXi Hosts in the Management Domain


#Start the vSphere Cluster Services in the Management Domain

#Start the vCenter Server Instance in the Management Domain

#Set DRS Automation Level of the Management Domain to Automatic


#Start the SDDC Manager Virtual Machine in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io  -node sfo-vcf01 -user administrator@vsphere.local -pass VMw@re123!  -timeout 150 -task "Startup"

#Start the NSX-T Manager Virtual Machines in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-nsx01a, sfo-m01-nsx01b, sfo-m01-nsx01c -user administrator@vsphere.local -pass VMw@re123!  -timeout 600 -task "Startup"
#login to local ip of nsxt manager to see if it is reachable
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
Connect-NSXTLocal -url "https://sfo-m01-nsx01.sfo.rainpole.io/login.jsp?local=true"

#There is something pending, like NSXT local system->cluster->applicance status ---- need to check same available

#Start the NSX-T Edge Nodes in the Management Domain
ShutdownStartup-SDDCComponent -server sfo-m01-vc01.sfo.rainpole.io -nodes sfo-m01-en01, sfo-m01-en02 -user administrator@vsphere.local -pass VMw@re123!  -task "Startup" -timeout 600

#Start the Region-Specific Workspace ONE Access Virtual Machine in the Management Domain

#Start the vRealize Log Insight Virtual Machines in the Management Domain

#Start the vRealize Suite Lifecycle Manager Virtual Machine in the Management Domain

#Start the Cross-Region Workspace ONE Access Virtual Machines in the Management Domain

#Start the vRealize Operations Manager Virtual Machines in the Management Domain

#Start the vRealize Automation Virtual Machines in the Management Domain