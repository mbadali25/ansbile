param (
    [Parameter(Mandatory=$true,
    HelpMessage="Please enter in account Name")]
    [string]$GMSAAccount
)

$folders="D:\SQLDATA","S:\Program Files","L:\SQLLOG","T:\TEMPDB","U:\TEMPDB","K:\SQLBackup","D:\OLAP","T:\OLAP","U:\OLAP","L:\OLAP"

foreach($folder in $folders)
{
    foreach($user in $GMSAAccount)
    {
	if (Test-Path $folder)
	{
          $command ="icacls " + '"'+ "$($folder)" + '"'+ " /grant " + '"'+ "$($user)" + '":(OI)(CI)F /T' 
          $run="cmd /c " + "'" + "$($command)" + "'"
          Invoke-Expression -Command $run
	}
    }


}
