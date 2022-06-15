$id=(Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object{ $_.Extensions | Where-Object{ ($_.Oid.FriendlyName -eq 'Certificate Template Information') -and ($_.Format(0) -match "RDPAuth") }}).Thumbprint
wmic /namespace:\\root\CIMV2\TerminalServices PATH Win32_TSGeneralSetting Set SSLCertificateSHA1Hash="$($id)"
Restart-Service -Name TermService -force
