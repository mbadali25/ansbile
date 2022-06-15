#Format Drives
$InstanceId = (Invoke-WebRequest http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing).content

$volumeids=((Get-EC2Instance -InstanceId $InstanceId).instances).BlockDeviceMappings.ebs.volumeid

$volumes=(get-ec2volume -VolumeId $volumeids)
foreach($volume in $volumes)
{
	$drivelabel = ( $volume.tags | where {$_.key -eq "DriveLabel"}).Value
	$driveletter = ($volume.tags | where {$_.key -eq "DriveLetter"}).Value
	$adapterserialnumber = ($volume.VolumeId).Replace('-','')

	if ($driveletter -ne "C") 
	{ 
	    
		$partition = (get-disk | where {$_.AdapterSerialNumber -eq $adapterserialnumber -and $_.Number -ne 0})
	
	if ($partition.PartitionStyle -eq 'raw')    
	{ 
		Initialize-Disk -Number $partition.Number -PartitionStyle GPT | New-Partition -DriveLetter $driveletter -UseMaximumSize  | Format-Volume -FileSystem NTFS `
		-NewFileSystemLabel $drivelabel -Confirm:$false `
		-AllocationUnitSize 65536
		}
	if ($partition.PartitionStyle -eq 'MBR') { $partition | set-disk -partitionstyle GPT}
	if ($partition.PartitionStyle -eq 'GPT') 
		{
			$partition | New-Partition -DriveLetter $driveletter `
			-UseMaximumSize | Format-Volume -FileSystem NTFS `
			-NewFileSystemLabel $drivelabel -Confirm:$false  -AllocationUnitSize 65536
		}
		
		
	}
}
