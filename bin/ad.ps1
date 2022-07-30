# install Active Directory
Install-windowsfeature -name AD-Domain-Services -IncludeManagementTools

# create forest, this command require reboot, although -NoRebootOnCompletion:$true can help skip reboot
# however, it is still needed for AD to reboot anyway.
Install-ADDSForest -DomainName example.com -SafeModeAdministratorPassword (ConvertTo-SecureString 'Admin1234!' -AsPlainText -Force) -DomainMode WinThreshold -DomainNetbiosName ABC -ForestMode WinThreshold -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -CreateDnsDelegation:$false -InstallDns:$true -NoRebootOnCompletion:$false -Force:$true

ksetup /addkdc CN-NORTH-1.COMPUTE.INTERNAL

netdom trust CN-NORTH-1.COMPUTE.INTERNAL /Domain:EXAMPLE.COM /add /realm /passwordt:Admin1234!

# need config "encrypt types for Kerberos" on AD (it seems UI only),
# add one or both following items:
ksetup /SetEncTypeAttr CN-NORTH-1.COMPUTE.INTERNAL AES256-CTS-HMAC-SHA1-96 AES128-CTS-HMAC-SHA1-96

# ------------------------------------------   ou: Service Accounts   ------------------------------------------- #

# Remove OU "Service Accounts" recursively if exists
# Get-ADOrganizationalUnit -Identity "OU=Service Accounts,DC=EXAMPLE,DC=COM" |
# Set-ADObject -ProtectedFromAccidentalDeletion:$false -PassThru |
# Remove-ADOrganizationalUnit -Confirm:$false -Recursive

# Add OU "Service Accounts"
New-ADOrganizationalUnit -Name "Service Accounts" -Path "DC=EXAMPLE,DC=COM"

# -------------------------------------------   user: ranger-binder   ------------------------------------------- #

# Remove service account "ranger-binder" if exists
Remove-ADUser -Identity "CN=ranger-binder,OU=Service Accounts,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create service account "ranger-binder"
New-ADUser -Name "ranger-binder" -OtherAttributes @{'title'="ranger-binder"} -path "OU=Service Accounts,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=ranger-binder,OU=Service Accounts,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=ranger-binder,OU=Service Accounts,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=ranger-binder,OU=Service Accounts,DC=EXAMPLE,DC=COM"

# ----------------------------------------   user: emr-ad-domain-joiner   --------------------------------------- #

# Remove service account "emr-ad-domain-joiner" if exists
Remove-ADUser -Identity "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create service account "emr-ad-domain-joiner"
New-ADUser -Name "emr-ad-domain-joiner" -OtherAttributes @{'title'="emr-ad-domain-joiner"} -path "OU=Service Accounts,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM"

# Add service account "emr-ad-domain-joiner" to "Domain Admins", "Schema Admins", "Enterprise Admins" groups,
# so as it has enough privileges to add EMR cluster nodes into AD domain.
Add-ADGroupMember -Identity "Domain Admins" -Members "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM"
Add-ADGroupMember -Identity "Schema Admins" -Members "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM"
Add-ADGroupMember -Identity "Enterprise Admins" -Members "CN=emr-ad-domain-joiner,OU=Service Accounts,DC=EXAMPLE,DC=COM"

# ---------------------------------------------   user: ad-user-1   --------------------------------------------- #

# Remove service account "emr-ad-domain-joiner" if exists
Remove-ADUser -Identity "CN=ad-user-1,CN=Users,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create normal domain user  "ad-user-1"
New-ADUser -Name "ad-user-1" -OtherAttributes @{'title'="ad-user-1"} -path "CN=Users,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=ad-user-1,CN=Users,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=ad-user-1,CN=Users,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=ad-user-1,CN=Users,DC=EXAMPLE,DC=COM"
