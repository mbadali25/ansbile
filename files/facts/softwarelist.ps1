#Powershell
$software = get-wmiobject -class Win32_Product | select-object name,version,vendor 
$software_count = ($software | measure).count
$software_list=$software

$jsonBase = @{}
$arra=@{}
$software= New-Object System.Collections.ArrayList
$software_list| % {
$software.add(@{'name'=$_.name;'version'=$_.version;'vendor'=$_.vendor})> $null

}
$sl= @{"software_list"=$software}
$arra.add("local_facts",$sl)
$jsonBase.Add("local",$arra)

#$results | out-file "C:\scripts\facts\$($env:Computername)_windows_software.fact"
$jsonBase | convertto-json -Depth 25 -Compress
 
