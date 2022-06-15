Import-Module 'C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1'
$args = @( "/x" 
"(Get-UninstallRegistryKey -SoftwareName 'VMware*').PSChildName" 
"/qn")
Start-Process -FilePath msiexec.exe -Argumentlist $args


