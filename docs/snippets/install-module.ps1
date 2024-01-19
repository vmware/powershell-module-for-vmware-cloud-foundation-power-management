Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name VMware.PowerCLI -MinimumVersion 13.0.0 -Repository PSGallery
Install-Module -Name PowerVCF -MinimumVersion 2.4.0 -Repository PSGallery
Install-Module -Name PowerValidatedSolutions -MinimumVersion 2.8.0 -Repository PSGallery
Install-Module -Name Posh-SSH -MinimumVersion 3.0.8 -Repository PSGallery
Install-Module -Name VMware.CloudFoundation.PowerManagement -Repository PSGallery
