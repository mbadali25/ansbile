$server_info = (Get-WmiObject Win32_ComputerSystem)

$computer_info = (get-adcomputer $env:ComputerName -properties environment, patchgroup, monitoringexclusion, computersite, team, extensionattribute9, extensionattribute10, extensionattribute11, extensionattribute12, extensionattribute13, extensionattribute14, extensionattribute15)

#Token Info
[string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token

#Remove Variables If exists
(get-variable ec2_ip*) | Foreach-Object { Remove-Variable $_.Name }
if ($server_info.Manufacturer -eq "Amazon EC2")
{
    $InstanceId = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing)
    $instance_type = $(Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-type -UseBasicParsing)
    $avail_zone = $(Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/placement/availability-zone -UseBasicParsing)
    $ami_id = $(Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/ami-id -UseBasicParsing)
    ##Get MAC Address for getting interface IPs
    $mac = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs -UseBasicParsing)
    $ip_list = ((Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s -UseBasicParsing)).split("`n")
    for ($i = 0; $i -lt ($ip_list.count); $i++)
    {
        New-Variable -Name ec2_ip$($i) -Value $ip_list[$i]

    }

}
## Get Memory Settings to be used for SQL
$sql_memory = [math]::Round((((Get-WmiObject -Class Win32_OperatingSystem | Select-Object TotalVisibleMemorySize).TotalVisibleMemorySize) / 1024) * .85, 0)

## Get CPU Count to be used for SQL Max Degress of Parralelism Configuratoin
$cpu_count = ((Get-WmiObject -Class Win32_Processor | Select-Object NumberOfLogicalProcessors).NumberOfLogicalProcessors)


#Determines SQL Server Role by Server Name
if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "DB"){ $sql_role = "databaseserver" }

if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 5, 3) -eq "RGT"){ $sql_role = "databaseserver" }

if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "IS"){ $sql_role = "integrationsserver" }

if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "AS"){ $sql_role = "analysisserver" }

if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "RS"){ $sql_role = "reportingserver" }

if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 7, 5) -eq "BIUTL"){ $sql_role = "bi_utility" }

####Test Pending Reboot Function

function Test-RebootRequired
{
    $result = @{
        CBSRebootPending            = $false
        WindowsUpdateRebootRequired = $false
        FileRenamePending           = $false
        SCCMRebootPending           = $false
    }

    #Check CBS Registry
    $key = Get-ChildItem "HKLM:Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction Ignore
    if ($null -ne $key)
    {
        $result.CBSRebootPending = $true
    }

    #Check Windows Update
    $key = Get-Item "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction Ignore
    if ($null -ne $key)
    {
        $result.WindowsUpdateRebootRequired = $true
    }

    #Check PendingFileRenameOperations
    $prop = Get-ItemProperty "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction Ignore
    if ($null -ne $prop)
    {
        #PendingFileRenameOperations is not *must* to reboot?
        #$result.FileRenamePending = $true
    }

    #Return Reboot required
    return $result.ContainsValue($true)
}


####Get Drive Letters for SQL Server
if ($null -ne $sql_role)
{    

    ## The Disk Values are stored in extension attribute 11-15 in the computer account in active directory
    ## extensionattribute9 - user database drive info
    ## extensionattribute10 - system database drive info
    ## extensionattribute11 - sql tlog drive info
    ## extensionattribute12 - sql backup drive info  
    ## extensionattribute13 - tempdb drive info 
    ## extensionattribute14 - instance storage 0 drive info    
    ## extensionattribute15 - instance storage 1 drive info   
    $user_db_info = if ($null -ne $computer_info.extensionattribute9) { $computer_info.extensionattribute9.split(',') }
    $system_db_info = if ($null -ne $computer_info.extensionattribute10) { $computer_info.extensionattribute10.split(',') }
    $system_tlog_info = if ($null -ne $computer_info.extensionattribute11) { $computer_info.extensionattribute11.split(',') }
    $sql_backup_info = if ($null -ne $computer_info.extensionattribute12) { $computer_info.extensionattribute12.split(',') }
    $temp_db_info = if ( $null -ne $computer_info.extensionattribute13){ $computer_info.extensionattribute13.split(',') }
    $instance_storage_0_info = if ($null -ne $computer_info.extensionattribute14){ $computer_info.extensionattribute14.split(',') }
    $instance_storage_1_info = if ($null -ne $computer_info.extensionattribute15){ $computer_info.extensionattribute15.split(',') }

    ## Set EC2 Volume Variables
    $user_db_volume_id = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[0] }
    $system_db_volume_id = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[0] }
    $sql_tlog_volume_id = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[0] }
    $sql_backup_volume_id = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[0] }
    $temp_db_volume_id = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[0] }
    $instance_storage_0_volume_id = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[0] }
    $instance_storage_1_volume_id = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[0] }
  
    $user_db_volume_serial = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[1] }
    $system_db_volume_serial = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[1] }
    $sql_tlog_volume_serial = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[1] }
    $sql_backup_volume_serial = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[1] }
    $temp_db_volume_serial = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[1] }
    $instance_storage_0_volume_serial = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[1] }
    $instance_storage_1_volume_serial = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[1] }

    $user_db_volume_label = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[2] }
    $system_db_volume_label = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[2] }
    $sql_tlog_volume_label = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[2] }
    $sql_backup_volume_label = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[2] }
    $temp_db_volume_label = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[2] }
    $instance_storage_0_volume_label = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[2] }
    $instance_storage_1_volume_label = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[2] }

    $user_db_volume_letter = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[3] }
    $system_db_volume_letter = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[3] }
    $sql_tlog_volume_letter = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[3] }
    $sql_backup_volume_letter = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[3] }
    $temp_db_volume_letter = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[3] }
    $instance_storage_0_volume_letter = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[3] }
    $instance_storage_1_volume_letter = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[3] }

    $user_db_disk_number = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[4] }
    $system_db_disk_number = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[4] }
    $sql_tlog_disk_number = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[4] }
    $sql_backup_disk_number = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[4] }
    $temp_db_disk_number = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[4] }
    $instance_storage_0_disk_number = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[4] }
    $instance_storage_1_disk_number = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[4] }

    $user_db_volume_mount = if ($null -eq $user_db_info) { "Not Installed" } else { $user_db_info[5] }
    $system_db_volume_mount = if ($null -eq $system_db_info) { "Not Installed" } else { $system_db_info[5] }
    $sql_tlog_volume_mount = if ($null -eq $system_tlog_info) { "Not Installed" } else { $system_tlog_info[5] }
    $sql_backup_volume_mount = if ($null -eq $sql_backup_info) { "Not Installed" } else { $sql_backup_info[5] }
    $temp_db_volume_mount = if ($null -eq $temp_db_info) { "Not Installed" } else { $temp_db_info[5] }
    $instance_storage_0_volume_mount = if ($null -eq $instance_storage_0_info) { "Not Installed" } else { $instance_storage_0_info[5] }
    $instance_storage_1_volume_mount = if ($null -eq $instance_storage_1_info) { "Not Installed" } else { $instance_storage_1_info[5] }

    #Check if MS SQL Database is installed and Gets Edition and Version
    #Use Powershell Module if Installed

    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL') -eq $true)
    {
        #Load Registry Value to Get SQL Edition and Version using Default Instance Name
        $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').MSSQLSERVER
        $sql_version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Version
        $sql_edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition
        $sql_patch_level = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").PatchLevel
    }

    #Checks if MS SQL Analysis Server is installed and Gets Edition and Version
    if ($null -eq $sql_version -and $null -eq $sql_edition -and (Test-Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\OLAP') -eq $true)
    {
        #Load Registry Value to Get SQL Edition and Version using Default Instance Name
        $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\OLAP').MSSQLSERVER
        $sql_version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Version
        $sql_edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition
        $sql_patch_level = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").PatchLevel

    }
    #Checks if MS SQL Reporting Server is installed and Gets Edition and Version
    if ( $null -eq $sql_version -and $null -eq $sql_edition -and (Test-Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\RS') -eq $true)
    {
        #Load Registry Value to Get SQL Edition and Version using Default Instance Name
        $p = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\RS').MSSQLSERVER
        $sql_version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Version
        $sql_edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").Edition
        $sql_patch_level = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").PatchLevel
    }
    elseif ($null -eq $sql_version -and $null -eq $sql_edition)
    {
        $sql_version = "Not Installed"
        $sql_edition = "Not Installed"
    }

}

#Checks for Pending Reboot
$pending_reboot = Test-RebootRequired

if ($null -eq $instance_type) { $instance_type = "NA" }
if ($null -eq $ami_id) { $ami_id = "NA" }
if ($null -eq $avail_zone) { $avail_zone = "NA" }

@{
    local_facts = @{
        instance_id           = $InstanceId
        instance_type         = $instance_type
        avail_zone            = $avail_zone
        ami_id                = $ami_id
        server_environment    = $computer_info.environment
        patch_group           = $computer_info.patchgroup
        datadog_exclusion     = $computer_info.monitoringexclusion
        computer_site         = $computer_info.computersite
        server_owner          = $computer_info.team
        server_pending_reboot = $pending_reboot
        primary_ip            = $ec2_ip0
        secondary_ip          = $ec2_ip1
        tertiary_ip           = $ec2_ip2
    }
    sql_facts   = @{
        sql_max_memory_reccomendation        = $sql_memory
        sql_server_role                      = $sql_role
        edw_max_degrees_of_parallelism       = ($cpu_count / 2)
        max_degrees_of_parallelism           = ($cpu_count / 4)
        sql_userdb_drive_letter              = $user_db_volume_letter
        sql_userdb_drive_label               = $user_db_volume_label
        sql_userdb_volume_id                 = $user_db_volume_id
        sql_userdb_volume_serial             = $user_db_volume_serial
        sql_userdb_volume_mount              = $user_db_volume_mount
        sql_userdb_disk_number               = $user_db_disk_number
        sql_systemdb_drive_letter            = $system_db_volume_letter
        sql_systemdb_drive_label             = $system_db_volume_label
        sql_systemdb_volume_id               = $system_db_volume_id
        sql_systemdb_volume_serial           = $system_db_volume_serial
        sql_systemdb_volume_mount            = $system_db_volume_mount
        sql_systemdb_disk_number             = $system_db_disk_number
        sql_sqltlog_drive_letter             = $sql_tlog_volume_letter
        sql_sqltlog_drive_label              = $sql_tlog_volume_label
        sql_sqltlog_volume_id                = $sql_tlog_volume_id
        sql_sqltlog_volume_serial            = $sql_tlog_volume_serial
        sql_sqltlog_volume_mount             = $sql_tlog_volume_mount
        sql_sqltlog_disk_number              = $sql_tlog_disk_number
        sql_sqlbackup_drive_letter           = $sql_backup_volume_letter
        sql_sqlbackup_drive_label            = $sql_backup_volume_label
        sql_sqlbackup_volume_id              = $sql_backup_volume_id
        sql_sqlbackup_volume_serial          = $sql_backup_volume_serial
        sql_sqlbackup_volume_mount           = $sql_backup_volume_mount
        sql_sqlbackup_disk_number            = $sql_backup_disk_number
        sql_tempdb_drive_letter              = $temp_db_volume_letter
        sql_tempdb_drive_label               = $temp_db_volume_label
        sql_tempdb_volume_id                 = $temp_db_volume_id
        sql_tempdb_volume_serial             = $temp_db_volume_serial
        sql_tempdb_volume_mount              = $temp_db_volume_mount
        sql_tempdb_disk_number               = $temp_db_disk_number
        sql_instance_storage_0_drive_label   = $instance_storage_0_volume_label
        sql_instance_storage_0_volume_id     = $instance_storage_0_volume_id
        sql_instance_storage_0_volume_serial = $instance_storage_0_volume_serial
        sql_instance_storage_0_volume_mount  = $instance_storage_0_volume_mount
        sql_instance_storage_0_disk_number   = $instance_storage_0_disk_number
        sql_instance_storage_0_drive_letter  = $instance_storage_0_volume_letter
        sql_instance_storage_1_drive_letter  = $instance_storage_1_volume_letter
        sql_instance_storage_1_drive_label   = $instance_storage_1_volume_label
        sql_instance_storage_1_volume_id     = $instance_storage_1_volume_id
        sql_instance_storage_1_volume_serial = $instance_storage_1_volume_serial
        sql_instance_storage_1_volume_mount  = $instance_storage_1_volume_mount
        sql_instance_storage_1_disk_number   = $instance_storage_1_disk_number
        sql_version                          = $sql_version
        sql_edition                          = $sql_edition
        sql_patch_level                      = $sql_patch_level
    }

}

