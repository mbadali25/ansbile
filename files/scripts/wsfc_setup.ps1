$server1="$env:ComputerName"

$next_server_number = [int]$server1.substring($server1.length-2,2)+1

if ($next_server_number.length -lt 2) { $next_server_number = "0$($next_server_number)"}

$server2="$($server1.Substring(0,$server1.Length-2))$($next_server_number)"
$server2=$server2.replace("E01A","E01B")
$servers=  $server1,$server2

Start-Transcript -Path C:\scripts\wsfc_setup.log
Install-WindowsFeature Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools
Install-WindowsFeature RSAT-DNS-Server -IncludeManagementTools
Import-Module DNSServer

#Gets EC2 Instance ID

$serverinfo = @()
$clusternodes= ""
$clusterips = ""
$ADGroup = "SQLClusters"
write-host "Server variable"
$servers
$file_share_witness_path="\\corp.invh.com\files\Infrastructure\filesharewiteness"

#Token Info
[string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token


foreach($server in $servers)
{
 $item = "" | select server,ip

 if ($server -eq $env:ComputerName)
 {
   $instanceid = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing)
 }
 else {
 $instanceid= Invoke-Command -ComputerName $server -ScriptBlock {
 (([string]$token) = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token));
 ((Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing));
 } -OutVariable $instanceid
 }
 if ($instanceid.Count -gt 1) {$InstanceId=$InstanceId[1]}
 
 $ec2info = Get-EC2Instance -InstanceId $instanceid
 $clusterip=$ec2info.Instances.NetworkInterfaces.PrivateIpAddresses.PrivateIpAddress[1]
 
 $item.server = $server
 $item.ip = $clusterip
 $serverinfo+=$item
}

$first_num=$servers[0].substring($servers[0].length-2,2)
$second_num=$servers[1].substring($servers[1].length-2,2)
$cluster_number = [int]$first_num + [int]$second_num

if ($cluster_number.length -eq 1) {$cluster_number = "0$($cluster_number)"}

$first_half="$($env:ComputerName.Substring(0,$env:ComputerName.Length-8))"
$second_half = "$($env:ComputerName.Substring($first_half.length+1,($env:ComputerName.Substring($first_half.length+1 )).length-4 ))"
$clustername="$($first_half)$($second_half)CLU$($cluster_number)"
$ad_clustername = "$($clustername)$"

$ClusterOU="CN=$($clustername),OU=SQLClusterAccounts,OU=AWS,OU=datacenter,OU=Servers,OU=IH,DC=corp,DC=invh,DC=com"

#Checks to see if cluster exists
try
{
 if ((Get-ADComputer $clustername -ErrorAction SilentlyContinue).Enabled -eq $true) { Get-Cluster $clustername }
 if ((Get-ADComputer $clustername -ErrorAction SilentlyContinue).Enabled -eq $false)
  {
    Write-Host "Cluster is disabled and inactive"
    Write-Host "Starts Cluster Service"
    foreach ($server in $servers)
    {
        if ((Get-Service -Name ClusSvc -ComputerName $server ).Status) { if($env:ComputerName -ne $server) {Invoke-Command -ComputerName $server -ScriptBlock { Start-Service -Name ClusSvc }}
    }
    
     #Flatten Cluster IPs
     foreach($ip in $serverinfo.ip) { $clusterips+="'"+ "$($ip)" + "'"+","}

     #Flatten Cluster Nodess
     foreach($node in $servers) { $clusternodes+="$($node),"}

     #Removes Trailing , on end of ClusterIps
     $clusterips=$clusterips.Substring(0,$clusterips.Length-1)

      #Removes Trailing , on end of ClusterNodes
     $clusternodes=$clusternodes.Substring(0,$clusternodes.Length-1)

     #Create Winodws Cluster
     $cluster_command = "New-Cluster -Name '"+"$ClusterOU"+"' -Node $clusternodes -NoStorage -StaticAddress $clusterips"

     #Creates the cluster
     Invoke-Expression $cluster_command

     #Configures Quorum Settings
     Set-ClusterQuorum -FileShareWitness $file_share_witness_path

     #Configures Permissions , allowing nodes to have full access to CNO
    foreach($server in $servers)
    {
    $cnopath = "AD:\$($ClusterOU)"
    $acl = Get-Acl -Path $cnopath
    $computer = get-adcomputer $server
    $sid = [System.Security.Principal.SecurityIdentifier] $computer.SID
    $identity = [System.Security.Principal.IdentityReference] $SID
    $adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericAll"
    $type = [System.Security.AccessControl.AccessControlType] "Allow"
    $inheritanceType = [DirectoryServices.ActiveDirectorySecurityInheritance]::All
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type,$inheritanceType)
    $acl.AddAccessRule($ace)
    Set-Acl -Path $cnopath -AclObject $acl
    }
    #Sets CNO TTL to 60 Seconds
    Get-ClusterResource "Cluster Name" | Set-ClusterParameter -Name HostRecordTTL -Value 60


    #Get PDC Serer
    $pdc=(Get-ADForest |Select-Object -ExpandProperty RootDomain |Get-ADDomain |Select-Object -Property PDCEmulator).PDCEmulator


    #Gets Active Cluster IP
    start-sleep -Seconds 3
    $active_cno_ip = ((Get-ClusterResource | where {$_.ResourceType -eq 'IP Address' -and $_.State -eq 'Online'}) | Get-ClusterParameter | where {$_.Name -eq 'Address'}).value

    #Checks if DNS Record Exists
    try {
    Get-DnsServerResourceRecord -ComputerName $pdc -Name $clustername -ZoneName "corp.invh.com" -ErrorAction SilentlyContinue
    Remove-DnsServerResourceRecord -ComputerName $pdc -Name $clustername -ZoneName "corp.invh.com" -RRType A -Force
    Add-DnsServerResourceRecordA -ComputerName $pdc -Name $clustername -ZoneName "corp.invh.com" -AllowUpdateAny -IPv4Address $active_cno_ip -TimeToLive 00:01:00
    }
    catch {

    Add-DnsServerResourceRecordA -ComputerName $pdc -Name $clustername -ZoneName "corp.invh.com" -AllowUpdateAny -IPv4Address $active_cno_ip -TimeToLive 00:01:00

    }


  }
 }
}
catch {
 Write-Host "Cluster Object Doesn't Exists"

 #Flatten Cluster IPs
 foreach($ip in $serverinfo.ip) { $clusterips+="'"+ "$($ip)" + "'"+","}

 #Flatten Cluster Nodess
 foreach($node in $servers) { $clusternodes+="$($node),"}

 #Removes Trailing , on end of ClusterIps
 $clusterips=$clusterips.Substring(0,$clusterips.Length-1)

  #Removes Trailing , on end of ClusterNodes
 $clusternodes=$clusternodes.Substring(0,$clusternodes.Length-1)

 #Create Winodws Cluster
 $cluster_command = "New-Cluster -Name '"+"$ClusterOU"+"' -Node $clusternodes -NoStorage -StaticAddress $clusterips"

 #Creates the cluster
 Invoke-Expression $cluster_command

 #Configures Quorum Settings
 Set-ClusterQuorum -FileShareWitness $file_share_witness_path

 #Configures Permissions , allowing nodes to have full access to CNO
foreach($server in $servers)
{
$cnopath = "AD:\$($ClusterOU)"
$acl = Get-Acl -Path $cnopath
$computer = get-adcomputer $server
$sid = [System.Security.Principal.SecurityIdentifier] $computer.SID
$identity = [System.Security.Principal.IdentityReference] $SID
$adRights = [System.DirectoryServices.ActiveDirectoryRights] "GenericAll"
$type = [System.Security.AccessControl.AccessControlType] "Allow"
$inheritanceType = [DirectoryServices.ActiveDirectorySecurityInheritance]::All
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity,$adRights,$type,$inheritanceType)
$acl.AddAccessRule($ace)
Set-Acl -Path $cnopath -AclObject $acl
}
 #Sets CNO TTL to 60 Seconds
 Get-ClusterResource "Cluster Name" | Set-ClusterParameter -Name HostRecordTTL -Value 60


#Get PDC Serer
$pdc=(Get-ADForest |Select-Object -ExpandProperty RootDomain |Get-ADDomain |Select-Object -Property PDCEmulator).PDCEmulator

#Gets Active Cluster IP
start-sleep -Seconds 3
$active_cno_ip = ((Get-ClusterResource | where {$_.ResourceType -eq 'IP Address' -and $_.State -eq 'Online'}) | Get-ClusterParameter | where {$_.Name -eq 'Address'}).value
Add-DnsServerResourceRecordA -ComputerName $pdc -Name $clustername -ZoneName "corp.invh.com" -AllowUpdateAny -IPv4Address $active_cno_ip -TimeToLive 00:01:00
}

#Add Cluster to SQLClusters ADGroup

Add-ADGroupMember -Identity $ADGroup -Members $ad_clustername

Stop-Transcript


