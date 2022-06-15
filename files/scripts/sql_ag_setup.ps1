Start-Transcript -Path C:\scripts\sql_ha_setup.log
Import-Module SQLServer
Import-Module DNSServer

$server1="$env:ComputerName"

$next_server_number = [int]$server1.substring($server1.length-2,2)+1

if ($next_server_number.length -lt 2) { $next_server_number = "0$($next_server_number)"}

$server2="$($server1.Substring(0,$server1.Length-2))$($next_server_number)"
$server2=$server2.replace("E01A","E01B")
$servers=  $server1,$server2

$servers

#Token Info
[string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token


$server_info = @()
$sql_server_ag_listener_ips = ""

# Sets up SQL AG Name
$first_num=$servers[0].substring($servers[0].length-2,2)
$second_num=$servers[1].substring($servers[1].length-2,2)
$cluster_number = [int]$first_num + [int]$second_num

if ($cluster_number.length -eq 1) {$cluster_number = "0$($cluster_number)"}

$first_half="$($env:ComputerName.Substring(0,$env:ComputerName.Length-8))"
$second_half = "$($env:ComputerName.Substring($first_half.length+1,($env:ComputerName.Substring($first_half.length+1 )).length-4 ))"
$clustername="$($first_half)$($second_half)CLU$($cluster_number)"

$sql_ag_name = "$($first_half)$($second_half)AG$($cluster_number)"

"SQL AG NAME $($sql_ag_name)"

$sql_listener_name = "$($first_half)$($second_half)DBL$($cluster_number)"

"SQL Listener NAME $($sql_listener_name)"

$database_name = "DeleteMe"
$sql_ag_test_path="SQLSERVER:\Sql\$($servers[0])\DEFAULT\AvailabilityGroups\$($sql_ag_name)"
$cluster_name="$($first_half)$($second_half)CLU01"
$back_up_path = "\\$($servers[0])\SQLBackup"
$local_back_up_path="K:\SQLBackup"
$log_folder  = "L:\SQLLOG\"
$data_folder ="D:\SQLDATA\"


#####################################################
# Starting Loop and Configuring Servers
#####################################################
 foreach($server in $servers)
{
 $item = "" | select server,ip

 if ($server -eq $env:ComputerName)
 {
   $instanceid = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing)
 }

else 
 {
         $instanceid= Invoke-Command -ComputerName $server -ScriptBlock {
         (([string]$token) = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token));
         ((Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing));
         } -OutVariable $instanceid
 }

 if ($instanceid.Count -gt 1) {$InstanceId=$InstanceId[1]}

 $ec2info = Get-EC2Instance -instanceid $InstanceId
 $sql_ag_cluster_ip=$ec2info.Instances.NetworkInterfaces.PrivateIpAddresses.PrivateIpAddress[2]

 $item.server = $server
 $item.ip = $sql_ag_cluster_ip
 $server_info+=$item
 $admin_check_query="select case (SELECT name FROM sys.server_principals WHERE TYPE = 'G' and name = 'BUILTIN\administrators') when 'BUILTIN\administrators' then 'true' else  'false' end as result"
 #### Add local Administrators to SQL Logi
 if ((invoke-sqlcmd -Query $admin_check_query).result -eq 'false')
 {
 $admin_query ="CREATE LOGIN [BUILTIN\administrators] FROM WINDOWS;EXEC master..sp_addsrvrolemember @loginame = N'BUILTIN\administrators', @rolename = N'sysadmin'"
 Invoke-Sqlcmd -ServerInstance $server -Query $admin_query
 }
}


####Configure CNO to be able to create Computer Accounts
<#
$ComputerGUID = [GUID](Get-ADObject -Filter 'DistinguishedName -eq "CN=Computer,CN=Schema,CN=Configuration,DC=corp,DC=invh,DC=com"' -SearchBase (Get-ADRootDSE).schemaNamingContext -prop schemaIDGUID).schemaIDGUID

$Path = [ADSI]"LDAP://OU=Servers,OU=IH,DC=corp,DC=invh,DC=com"
$ntaccount = New-Object System.Security.Principal.NTAccount("CORP\$($cluster_name)$")
$IdentityReference = $ntaccount.Translate([System.Security.Principal.SecurityIdentifier])

$Perms = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,"CreateChild","Allow",$ComputerGUID,"All",$([GUID]::Empty))
$Path.psbase.ObjectSecurity.AddAccessRule($Perms)

$Perms = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($IdentityReference,"ReadProperty","Allow",$([GUID]::Empty),"All",$([GUID]::Empty))
$Path.psbase.ObjectSecurity.AddAccessRule($Perms)

$Path.psbase.commitchanges()

#/* Check the results */

(Get-Acl "ad:\OU=Servers,OU=IH,DC=corp,DC=invh,DC=com").Access | where-object { $_.IdentityReference -eq "CORP\$($cluster_name)$" }

#/* Check the returned ObjectType GUID is Computer */

$RawGuid = ([guid]'bf967a86-0de6-11d0-a285-00aa003049e2').toByteArray();
Get-ADObject -Filter {schemaIDGUID -eq $rawGuid} -SearchBase (Get-ADRootDSE).schemaNamingContext -prop schemaIDGUID | Select-Object Name,@{Name='schemaIDGUID';Expression={[guid]$_.schemaIDGUID}}
########################################################################
#>
#get subnet mask
$subnet_mask = (gwmi -computer .  -class "win32_networkadapterconfiguration" | Where-Object {$_.defaultIPGateway -ne $null}).IPSubnet[0]

 #Flatten Cluster IPs
 foreach($ip in $server_info.ip) { $sql_server_ag_listener_ips+="$($ip)/$($subnet_mask),"}

 #Removes Trailing , on end of ClusterIps
 $sql_server_ag_listener_ips=$sql_server_ag_listener_ips.Substring(0,$sql_server_ag_listener_ips.Length-1)
 $sql_server_ag_listener_ips=$sql_server_ag_listener_ips.Split(',')

#Query to create filler database to create SQL Availability Group
$query="
CREATE DATABASE [$($database_name)]
 CONTAINMENT = NONE
 ON  PRIMARY
( NAME = N'$($database_name)', FILENAME = N'$($data_folder)$($database_name).mdf' , SIZE = 1048576KB , FILEGROWTH = 262144KB )
 LOG ON
( NAME = N'$($database_name)_log', FILENAME = N'$($log_folder)$($database_name)_log.ldf' , SIZE = 524288KB , FILEGROWTH = 131072KB )
GO

USE [master]
GO
ALTER DATABASE [$($database_name)] SET RECOVERY FULL WITH NO_WAIT
GO
ALTER AUTHORIZATION ON DATABASE::[$($database_name)] TO [sa]
GO "

# Test if place holder database exists
$check_db_query ="IF DB_ID('" + $database_name  + "') IS NOT NULL select 'true' as result else select 'false' as result"
  
if ((Invoke-Sqlcmd -Query $check_db_query ).resul -ne 'true')
{
Invoke-SqlCmd -Query $query
}
    
#Checks if the AG has been setup
  
if (!(Test-Path $sql_ag_test_path))
{
foreach( $server in $servers)
{
  #Query to check to see if SQL Always on is enabled
  $always_on_check = "declare @IsHadrEnabled as sql_variant
set @IsHadrEnabled = (select SERVERPROPERTY('IsHadrEnabled'))
select @IsHadrEnabled as IsHadrEnabled,
case @IsHadrEnabled
when 0 then 'The Always On availability groups is disabled'
when 1 then 'The Always On availability groups is enabled'
else 'Invalid Input'
end as 'Hadr'"
   if ( (invoke-sqlcmd -Query $always_on_check).ishadrenabled -ne 1)
   {
   Enable-SqlAlwaysOn -ServerInstance $server -Force
   #Restarts SQL Server Service after change
   Invoke-Command -ComputerName $server -ScriptBlock { Restart-Service MSSQLSERVER -Force}
   }
   # Create HADR Endpoint
   if (!(test-path "SQLSERVER:\sql\$server\DEFAULT\Endpoints\Endpoint_AG"))
   {
 New-SqlHADREndpoint -Path "SQLSERVER:\SQL\$($server)\DEFAULT" -Name "Endpoint_AG" -Port 5022 -EncryptionAlgorithm Aes -Encryption Required

 # Start HADR Endpoint
 Set-SqlHADREndpoint -Path "SQLSERVER:\SQL\$($server)\DEFAULT\Endpoints\Endpoint_AG" -State Started
 Invoke-Sqlcmd -ServerInstance $server -Query "GRANT CONNECT ON ENDPOINT::Endpoint_AG TO [BUILTIN\administrators];"
   }

}

#####################################################
# End of Loop and Configuring Servers
#####################################################

# Backup my database and its log on the primary
Backup-SqlDatabase -Database $database_name -BackupFile "$($local_back_up_path)\$($database_name).bak" -ServerInstance $servers[0] -BackupAction Database

Backup-SqlDatabase -Database $database_name -BackupFile "$($local_back_up_path)\$($database_name).tlog" -ServerInstance "$($servers[0])" -BackupAction Log

# Restore the database and log on the secondary (using NO RECOVERY)
Restore-SqlDatabase -Database $database_name -BackupFile "$($back_up_path)\$($database_name).bak" -ServerInstance "$($servers[1])" -RestoreAction Database -NoRecovery

Restore-SqlDatabase -Database $database_name -BackupFile "$($back_up_path)\$($database_name).tlog" -ServerInstance "$($servers[1])" -RestoreAction Log -NoRecovery

# Create an in-memory representation of the primary replica.
$primaryReplica = New-SqlAvailabilityReplica -Name $servers[0] -EndpointURL "TCP://$($servers[0]).corp.invh.com:5022" -AvailabilityMode "SynchronousCommit" -FailoverMode "Automatic" -Version 13 -AsTemplate -SeedingMode Automatic

# Create an in-memory representation of the secondary replica.
$secondaryReplica = New-SqlAvailabilityReplica -Name $servers[1] -EndpointURL "TCP://$($servers[1]).corp.invh.com:5022" -AvailabilityMode "SynchronousCommit" -FailoverMode "Automatic" -Version 13 -AsTemplate -SeedingMode Automatic

# Create the availability group`
New-SqlAvailabilityGroup -Name "$($sql_ag_name)" -Path "SQLSERVER:\SQL\$($servers[0])\DEFAULT" -AvailabilityReplica @($primaryReplica,$secondaryReplica) -Database "$($database_name)"  -AutomatedBackupPreference None -DtcSupportEnabled -DatabaseHealthTrigger -FailureConditionLevel OnAnyQualifiedFailureCondition

# Join the secondary replica to the availability group.
Join-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\$($servers[1])\DEFAULT" -Name "$($sql_ag_name)"

# Sleep for 15 seconds
Start-Sleep -Seconds 15

# Join the secondary database to the availability group.
Add-SqlAvailabilityDatabase -Path "SQLSERVER:\SQL\$($servers[1])\DEFAULT\AvailabilityGroups\$($sql_ag_name)" -Database "$($database_name)"

#Configure SQL Server AG Listener
New-SqlAvailabilityGroupListener -Name $sql_listener_name -StaticIp $sql_server_ag_listener_ips[0],$sql_server_ag_listener_ips[1] -Path "SQLSERVER:\Sql\$($servers[0])\DEFAULT\AvailabilityGroups\$($sql_ag_name)"


#Configures Cluster Resource
$wsfc_sql_resource="$($sql_ag_name)_$($sql_listener_name)"

Get-ClusterResource $wsfc_sql_resource | set-clusterparameter -Name HostRecordTTL -Value 30
Get-ClusterResource $wsfc_sql_resource  | set-clusterparameter -Name RegisterAllProvidersIP -Value 0
Get-ClusterResource $wsfc_sql_resource  | set-clusterparameter -Name PublishPTRRecords -Value 1

Stop-ClusterResource -Name "$($sql_ag_name)_$($sql_listener_name)"
Start-ClusterResource -Name "$($sql_ag_name)_$($sql_listener_name)"
Start-ClusterResource -name $sql_ag_name
#Get IP of Active Member for Role
$active_cno_ip=(get-clusterresource | where {$_.name -like "$($sql_ag_name)_1*" -and $_.state -eq "Online"} | get-clusterparameter -Name Address).value

#Get PDC Serer
$pdc=(Get-ADForest |Select-Object -ExpandProperty RootDomain |Get-ADDomain |Select-Object -Property PDCEmulator).PDCEmulator
#Publich DNS
Add-DnsServerResourceRecordA -ComputerName $pdc -Name $sql_listener_name -ZoneName "corp.invh.com" -AllowUpdateAny -IPv4Address $active_cno_ip -TimeToLive 00:01:00
}

else
{
   Write-Host "SQL Availability Group Already is setup"
}

stop-transcript


