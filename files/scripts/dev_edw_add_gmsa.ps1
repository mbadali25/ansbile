$accounts="gMSAdevSQLIS","gMSAdevSQLAS","gMSAdevSQLsvc","gMSAdevSQLagnt"

#Pulls Local Computer Name
$computername=$env:COMPUTERNAME

#Adds Windows Feature If it isn't there and installs them if they aren't
if (!((get-windowsfeature | where {$_.Name -eq 'RSAT-AD-PowerShell'}).InstallState -eq "Installed")) {Add-WindowsFeature RSAT-AD-Powershell}

#Gets Computer info from AD
$adcomputer=Get-ADComputer $computername

#Loop through all accounts
foreach($account in $accounts)
{

### List existing principals Manageing it
$existinglist=(Get-ADServiceAccount -Identity $account -Properties * | select *).PrincipalsAllowedToRetrieveManagedPassword

##Add new computer to exisitng list 
$existinglist += $adcomputer.DistinguishedName

##Initializes Array for new list
$newlist=@()

$newlist+=$adcomputer.DistinguishedName
foreach ($item in $existinglist)
{
 #Removes Dead accounts
 if ($item -notlike "S-1-5*")
 {
 #$item
  $newlist+= "$($item.Substring(3,$item.IndexOf(',')-3))$"
 }
}
  
  #Allows Computer Account to Manage the password for the GMSA Account
  Set-ADServiceAccount $account -PrincipalsAllowedToRetrieveManagedPassword $newlist
 

}
