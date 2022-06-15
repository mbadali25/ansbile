$TLS12Protocol = [System.Net.SecurityProtocolType] 'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol

if ( (Get-PSRepository) -eq $null) {Register-PSRepository -Default}
if ((Get-PSRepository PSGallery).InstallationPolicy) { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted }
$psnuget= (get-packageprovider -Name Nuget).Version
$psnugetversion= "$($psnuget.Major).$($psnuget.Minor).$($psnuget.Build).$($psnuget.Revision)"
$psget= (get-packageprovider -Name PowerShellGet).Version
$psgetversion= "$($psnuget.Major).$($psnuget.Minor).$($psnuget.Build).$($psnuget.Revision)"

If ($psnugetversion -lt (Find-PackageProvider -Name Nuget).version) { Install-PackageProvider -Name PowerShellGet -Force }
If ($psgetversion -lt (Find-PackageProvider -Name PowerShellGet).version) { Install-PackageProvider -Name Nuget -Force }
