Save-Module -Name VMware.PowerCLI -Path $DownloadDir -Repository PSGallery
Save-Module -Name PowerVCF -Path $DownloadDir -Repository PSGallery
Save-Module -Name Posh-SSH -Path $DownloadDir -Repository PSGallery
Save-Module -Name PowerValidatedSolutions -Path $DownloadDir -Repository PSGallery
Save-Module -Name VMware.CloudFoundation.PowerManagement -Path $DownloadDir -Repository PSGallery
cd $DownloadDir
tar -zcvf OfflineModules.tar.gz *
