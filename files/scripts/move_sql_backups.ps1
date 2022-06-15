Import-Module NetTCPIP
Import-Module AWSPowerShell
Import-Module Microsoft.PowerShell.Security
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
# We need to get the contents of the folder to know the name of the subfolder.
# Technically there could be multiple but I haven't seen that happen. We will
# just use the first one.
$CredentialsList = (( Invoke-WebRequest -uri "http://169.254.169.254/latest/meta-data/iam/security-credentials" -UseBasicParsing ).Content.Split())[0]

# Get the credentials and turn the JSON text into an object.
$CredentialsObject = (Invoke-WebRequest -uri "http://169.254.169.254/latest/meta-data/iam/security-credentials/$($CredentialsList)" -UseBasicParsing).Content | ConvertFrom-Json

# Create/update a profile using the temporary access key and secret key
# we retrieved from the metadata.
Set-AWSCredential `
    -StoreAs InstanceProfile `
    -AccessKey $CredentialsObject.AccessKeyId `
    -SecretKey $CredentialsObject.SecretAccessKey `
    -SessionToken $CredentialsObject.Token

#GetsHostname
$hostname = ($env:ComputerName).ToLower()

$sourceDir = 'K:\SQLBACKUP'
$backup_dirs = (Get-ChildItem $sourceDir -Directory)

##Delete Files Older Than 7 days
$ToDeleteLimit = (Get-Date).AddDays(-3)

$s3prefix = "sql/backups/"

#Gets what environment to put in based on $hostname
if ($hostname.Substring(0, 1) -eq 'd') { $server_env = 'dev' }
if ($hostname.Substring(0, 1) -eq 'q') { $server_env = 'qa' }
if ($hostname.Substring(0, 1) -eq 'u') { $server_env = 'qa' }
if ($hostname.Substring(0, 1) -eq 'p') { $server_env = 'prod' }

#Gets IP Information to determine if in Shared-Services
$ips = (Get-NetIPAddress -AddressFamily IPV4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" }).IPAddress

if ($ips.count -eq 1) { $address = $ips }
if ($ips.count -gt 1) { $address = $ips[0] }

$second_octet = $address.Substring((($address.Substring(0, $address.IndexOf("."))).length + 1), ((($address.Substring(0, $address.IndexOf("."))).length + 1)))
if ($second_octet -eq "203") { $server_env = "shared-services" }

#S3 Bucket
$s3bucket = "sql-storage-$($server_env)-invh"

$File_list = @()

foreach ($dir in $backup_dirs)
{
    #Uncomment if you want to debug
    #$dir.name
    if (Test-Path "$($sourceDir)\$($dir.Name)\$($hostname)")
    {
        $database_dirs = Get-ChildItem "$($sourceDir)\$($dir.Name)\" -Directory
        $database_dirs.FullName
        foreach ($sdir in $database_dirs)
        {
            #Gathers File Info
            $file_check = Get-ChildItem $sdir.FullName -File
            $newprefix = ("$($s3prefix)$($server_env)/$($dir.Name)/$($sdir.Name)/").ToLower()
            $newprefix
            $sdir.FullName
            Write-S3Object -BucketName $s3bucket -Folder $sdir.FullName -KeyPrefix $newprefix  -Recurse
            foreach ($file in $file_check)
            {
                $item = "" | Select-Object Name
                $s3_item = $null

                $key_check = "$($newprefix)$($file.Name)"
                $s3_item = (Get-S3Object -BucketName $s3bucket -Key $key_check)
                if ($null -eq $s3_item)
                {
                    $item.Name = $file.FullName
                    $File_list += $item
                }

            }
            foreach ($missing in $File_list)
            {

                Get-ChildItem -Path $missing.FullName -File -Recurse | Select-Object Name, CreationTime | Where-Object { $_.FullName -ne $missing.Name -and $_.CreationTime -lt $ToDeleteLimit } | Remove-Item $_.FullName
            }

        }
    }
}

