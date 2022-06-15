## Import Modules
Import-Module SQLServer

## Variables
$restore_path = "K:\SQLBackup"
$sql_instance = "$env:ComputerName"

## Get Backup Files
$backups = Get-ChildItem -Path $restore_path -File

foreach ($backup in $backups)
{
 ## Pulls Database Name From Backup
 $db_name = $backup.Name.Substring($backup.Name.indexof("_")+1).substring(0,($backup.Name.Substring($backup.Name.indexof("_")+1)).indexof("_FULL"))

 ## Restores the database with options ReplaceDatabase, AutoRelocateFile
 Restore-SqlDatabase -BackupFile $backup.FullName -Database $db_name -ReplaceDatabase -ServerInstance $sql_instance -AutoRelocateFile

}
