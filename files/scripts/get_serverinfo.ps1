#Gets Computer Name
$ComputerName = $env:ComputerName

#Get PDC Serer
$pdc=(Get-ADForest |Select-Object -ExpandProperty RootDomain |Get-ADDomain |Select-Object -Property PDCEmulator).PDCEmulator

#clears varialbes created
(get-variable instance_storage_temp_db*) | ForEach-Object { remove-Variable $_.Name }

#Token Info
[string]$token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT -Uri http://169.254.169.254/latest/api/token

###Checks to see if its AWS

$serverinfo = (Get-WmiObject Win32_ComputerSystem)
if ($serverinfo.Manufacturer -eq "Amazon EC2")
{
    $InstanceId = (Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing)
    $OwnerTag = Get-EC2Tag | Where-Object { $_.ResourceId -eq $InstanceId -and $_.Key -eq "Owner" }
    $EnvironmentTag = Get-EC2Tag | ` Where-Object { $_.ResourceId -eq $InstanceId -and $_.Key -eq 'Environment' }
    $EnvironmentTag.Value= $EnvironmentTag.Value.Replace("$($OwnerTag.Value)-","")
    $PatchGroupTag = Get-EC2Tag | ` Where-Object { $_.ResourceId -eq $InstanceId -and $_.Key -eq 'Patch Group' }
    $DatadogExclusionTag = Get-EC2Tag | Where-Object { $_.ResourceId -eq $InstanceId -and $_.Key -eq "DatadogExclusion" }
    
    
     
    #Determines SQL Server Role by Server Name
    if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "DB"){ $sql_role = "databaseserver" }

    if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "IS"){ $sql_role = "integrationsserver" }

    if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "AS"){ $sql_role = "analysisserver" }

    if (($env:COMPUTERNAME).Substring(($env:COMPUTERNAME).Length - 4, 2) -eq "RS"){ $sql_role = "reportingserver" }

    # Get Drives for SQL Server
    ###########################
    if ($null -ne $sql_role)
    {
        ## Get Volume Info
        $ec2_disk_info = ((Get-EC2Instance -InstanceId $InstanceId).instances).BlockDeviceMappings
        $volumeids = ($ec2_disk_info).ebs.volumeid
        $volumes = (get-ec2volume -VolumeId $volumeids)

        ## The Disk Values are stored in extension attribute 11-15 in the computer account in active directory
        ## extensionattribute9 - user database drive info
        ## extensionattribute10 - system database drive info
        ## extensionattribute11 - sql tlog drive info
        ## extensionattribute12 - sql backup drive info  
        ## extensionattribute13 - tempdb drive info 
        ## extensionattribute14 - instance storage 0 drive info    
        ## extensionattribute15 - instance storage 1 drive info                   
        foreach ($volume in $volumes)
        { 
            $drivelabel = ( $volume.tags | Where-Object { $_.key -eq "DriveLabel" }).Value
            $driveletter = ( $volume.tags | Where-Object { $_.key -eq "DriveLetter" }).Value
            $disk_info = (get-disk | Where-Object { $_.AdapterSerialNumber -eq ($volume.VolumeId).Replace('-', '') })
            if ( $drivelabel.contains('USERDB'))
            {

                $user_db_volume_id = ($volume.VolumeId)
                $user_db_volume_serial = ($volume.VolumeId).Replace('-', '')
                $user_db_volume_label = $drivelabel
                $user_db_volume_letter = $driveletter
                $user_db_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $user_db_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute9 = "$($user_db_volume_id),$($user_db_volume_serial),$($user_db_volume_label),$($user_db_volume_letter),$($user_db_disk_number),$($user_db_volume_mount)" }
            }
            if ( $drivelabel.contains('SYSTEMDB'))
            {

                $system_db_volume_id = ($volume.VolumeId).Replace('-', '')
                $system_db_volume_label = $drivelabel
                $system_db_volume_serial = ($volume.VolumeId).Replace('-', '')
                $system_db_volume_label = $drivelabel
                $system_db_volume_letter = $driveletter
                $system_db_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $system_db_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute10 = "$($system_db_volume_id),$($system_db_volume_serial),$($system_db_volume_label),$($system_db_volume_letter),$($system_db_disk_number),$($system_db_volume_mount)" }
            }
            if ( $drivelabel.contains('SQLTLOG'))
            {

                $sql_tlog_volume_id = ($volume.VolumeId)
                $sql_tlog_volume_serial = ($volume.VolumeId).Replace('-', '')
                $sql_tlog_volume_label = $drivelabel
                $sql_tlog_volume_letter = $driveletter
                $sql_tlog_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $sql_tlog_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute11 = "$($sql_tlog_volume_id),$($sql_tlog_volume_serial),$($sql_tlog_volume_label),$($sql_tlog_volume_letter),$($sql_tlog_disk_number),$($sql_tlog_volume_mount)" }
            }
            if ( $drivelabel.contains('SQLBACKUP'))
            {

                $sql_backup_volume_id = ($volume.VolumeId)
                $sql_backup_volume_serial = ($volume.VolumeId).Replace('-', '')
                $sql_backup_volume_label = $drivelabel
                $sql_backup_volume_letter = $driveletter
                $sql_backup_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $sql_backup_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute12 = "$($sql_backup_volume_id),$($sql_backup_volume_serial),$($sql_backup_volume_label),$($sql_backup_volume_letter),$($sql_backup_disk_number),$($sql_backup_volume_mount)" }
            }
            if ( $drivelabel.contains('TEMPDB'))
            {

                $temp_db_volume_id = ($volume.VolumeId)
                $temp_db_volume_serial = ($volume.VolumeId).Replace('-', '')
                $temp_db_volume_label = $drivelabel
                $temp_db_volume_letter = $driveletter
                $temp_db_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $temp_db_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute13 = "$($temp_db_volume_id),$($temp_db_volume_serial),$($temp_db_volume_label),$($temp_db_volume_letter),$($temp_db_disk_number),$($temp_db_volume_mount)" }
            }
       
        }
    }

        # Get Drives for SQL Server
    ###########################
    if ($null -eq $sql_role)
    {
        ## Get Volume Info
        $ec2_disk_info = ((Get-EC2Instance -InstanceId $InstanceId).instances).BlockDeviceMappings
        $volumeids = ($ec2_disk_info).ebs.volumeid
        $volumes = (get-ec2volume -VolumeId $volumeids)

        ## The Disk Values are stored in extension attribute 11-15 in the computer account in active directory
        ## extensionattribute9 - user database drive info
        ## extensionattribute10 - system database drive info
        ## extensionattribute11 - sql tlog drive info
        ## extensionattribute12 - sql backup drive info  
        ## extensionattribute13 - tempdb drive info 
        ## extensionattribute14 - instance storage 0 drive info    
        ## extensionattribute15 - instance storage 1 drive info                   
        foreach ($volume in $volumes)
        { 
            $drivelabel = ( $volume.tags | Where-Object { $_.key -eq "DriveLabel" }).Value
            $driveletter = ( $volume.tags | Where-Object { $_.key -eq "DriveLetter" }).Value
            $disk_info = (get-disk | Where-Object { $_.AdapterSerialNumber -eq ($volume.VolumeId).Replace('-', '') })
            if ( $driveletter.contains('D'))
            {

                $volume_1_volume_id = ($volume.VolumeId)
                $volume_1_volume_serial = ($volume.VolumeId).Replace('-', '')
                $volume_1_volume_label = $drivelabel
                $volume_1_volume_letter = $driveletter
                $volume_1_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $volume_1_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute9 = "$($volume_1_volume_id),$($volume_1_volume_serial),$($volume_1_volume_label),$($volume_1_volume_letter),$($volume_1_disk_number),$($volume_1_volume_mount)" }
            }
            if ( $driveletter.contains('E'))
            {

                $volume_2_volume_id = ($volume.VolumeId).Replace('-', '')
                $volume_2_volume_label = $drivelabel
                $volume_2_volume_serial = ($volume.VolumeId).Replace('-', '')
                $volume_2_volume_label = $drivelabel
                $volume_2_volume_letter = $driveletter
                $volume_2_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $volume_2_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute10 = "$($volume_2_volume_id),$($volume_2_volume_serial),$($volume_2_volume_label),$($volume_2_volume_letter),$($volume_2_disk_number),$($volume_2_volume_mount)" }
            }
            if ( $driveletter.contains('F'))
            {

                $volume_3_volume_id = ($volume.VolumeId)
                $volume_3_volume_serial = ($volume.VolumeId).Replace('-', '')
                $volume_3_volume_label = $drivelabel
                $volume_3_volume_letter = $driveletter
                $volume_3_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $volume_3_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute11 = "$($volume_3_volume_id),$($volume_3_volume_serial),$($volume_3_volume_label),$($volume_3_volume_letter),$($volume_3_disk_number),$($volume_3_volume_mount)" }
            }
            if ( $driveletter.contains('G'))
            {
            6
                $volume_4_volume_id = ($volume.VolumeId)
                $volume_4_volume_serial = ($volume.VolumeId).Replace('-', '')
                $volume_4_volume_label = $drivelabel
                $volume_4_volume_letter = $driveletter
                $volume_4_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $volume_4_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute12 = "$($volume_4_volume_id),$($volume_4_volume_serial),$($volume_4_volume_label),$($volume_4_volume_letter),$($volume_4_disk_number),$($volume_4_volume_mount)" }
            }
            if ( $driveletter.contains('H'))
            {

                $volume_5_volume_id = ($volume.VolumeId)
                $volume_5_volume_serial = ($volume.VolumeId).Replace('-', '')
                $volume_5_volume_label = $drivelabel
                $volume_5_volume_letter = $driveletter
                $volume_5_volume_mount = ($ec2_disk_info | Where-Object { $_.ebs.volumeid -eq ($volume.VolumeId) }).DeviceName
                $volume_5_disk_number = $disk_info.Number
                get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute13 = "$($volume_5_volume_id),$($volume_5_volume_serial),$($volume_5_volume_label),$($volume_5_volume_letter),$($volume_5_disk_number),$($volume_5_volume_mount)" }
            }
       
        }
    }

    if (!($drivelabel.contains('TEMPDB')) -and (get-disk | Select-Object Number, Model | Where-Object { $_.Model.contains("Amazon EC2 NVMe") }))
    {
        $instance_storage_disk_info = (get-disk | Select-Object Number, Model | Where-Object { $_.Model.contains("Amazon EC2 NVMe") })


        for ($i = 0; $i -lt ($instance_storage_disk_info.Number.count); $i++)
        {
            if ($i -eq 0){ $instance_storage_drive_letter = "T" } else { $instance_storage_drive_letter = "U" } 

            New-Variable -Name instance_storage_temp_db_volume_id_$($i) -Value "NA"
            New-Variable -Name instance_storage_temp_db_volume_serial_$($i) -Value "NA"
            New-Variable -Name instance_storage_temp_db_volume_label_$($i) -Value "Temporary Storage $($i)"
            New-Variable -Name instance_storage_temp_db_volume_letter_$($i) -Value $instance_storage_drive_letter 
            New-Variable -Name instance_storage_temp_db_volume_mount_$($i) -Value "NA"
            New-Variable -Name instance_storage_temp_db_disk_number_$($i) -Value $instance_storage_disk_info[$i].number

            $instance_storage_data = "$($(get-variable "instance_storage_temp_db_volume_id_$($i)").value),$($(get-variable "instance_storage_temp_db_volume_serial_$($i)").Value),$($(get-variable "instance_storage_temp_db_volume_label_$($i)").value),$($(get-variable "instance_storage_temp_db_volume_letter_$($i)").value),$($(get-variable "instance_storage_temp_db_disk_number_$($i)").value),$($(get-variable "instance_storage_temp_db_volume_mount_$($i)").value)"
                
            if ($i -eq 0 ) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute14 = $instance_storage_data } }
            if ($i -eq 1 ) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{extensionattribute15 = $instance_storage_data } }

        }
           
    }
}


#Comptuer Site Function
function Get-ComputerSite($ComputerName)
{
    $site = cmd /c "nltest /server:$ComputerName /dsgetsite"
    if ($LASTEXITCODE -eq 0){ $site[0] }
}
$ComputerSite = Get-ComputerSite $ComputerName

if ($null -ne $InstanceId) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{InstanceId = $InstanceId } }

if ($null -ne $EnvironmentTag) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{environment = $EnvironmentTag.value } }

if ($null -ne $PatchGroupTag) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{patchgroup = $PatchGroupTag.value } }

if ($null -ne $ComputerSite) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{ComputerSite = $ComputerSite } }

if ($null -ne $DatadogExclusionTag) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{monitoringexclusion = $DatadogExclusionTag.value } }

if ($null -ne $OwnerTag) { get-adcomputer $ComputerName | set-adobject -Server $pdc -replace @{team = $OwnerTag.value } }


