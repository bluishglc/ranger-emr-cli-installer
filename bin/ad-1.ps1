# config "encrypt types for Kerberos" on AD
reg import kerberos-encrytion-types.reg

# install Active Directory
Install-windowsfeature -name AD-Domain-Services -IncludeManagementTools

# create forest, this command require reboot, although -NoRebootOnCompletion:$true can help skip reboot
# however, it is still needed for AD to reboot anyway, otherwise, when run New-ADOrganizationalUnit, it will fail!
Install-ADDSForest -DomainName example.com -SafeModeAdministratorPassword (ConvertTo-SecureString 'Admin1234!' -AsPlainText -Force) -DomainMode WinThreshold -DomainNetbiosName ABC -ForestMode WinThreshold -DatabasePath "C:\Windows\NTDS" -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -CreateDnsDelegation:$false -InstallDns:$true -NoRebootOnCompletion:$true -Force:$true



# --------------------------------------  will be forced to reboot ...   ---------------------------------------- #

ksetup /addkdc CN-NORTH-1.COMPUTE.INTERNAL

netdom trust CN-NORTH-1.COMPUTE.INTERNAL /Domain:EXAMPLE.COM /add /realm /passwordt:Admin1234!


# add one or both following items:
ksetup /SetEncTypeAttr CN-NORTH-1.COMPUTE.INTERNAL AES256-CTS-HMAC-SHA1-96 AES128-CTS-HMAC-SHA1-96

# ------------------------------------------   ou: services   ------------------------------------------- #

# Remove OU "services" recursively if exists
# Get-ADOrganizationalUnit -Identity "OU=services,DC=EXAMPLE,DC=COM" |
# Set-ADObject -ProtectedFromAccidentalDeletion:$false -PassThru |
# Remove-ADOrganizationalUnit -Confirm:$false -Recursive

# Add OU "services"
New-ADOrganizationalUnit -Name "services" -Path "DC=EXAMPLE,DC=COM"

# -------------------------------------------   user: ranger   ------------------------------------------- #

# Remove service account "ranger" if exists
Remove-ADUser -Identity "CN=ranger,OU=services,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create service account "ranger"
New-ADUser -Name "ranger" -OtherAttributes @{'title'="ranger"} -path "OU=services,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=ranger,OU=services,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=ranger,OU=services,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=ranger,OU=services,DC=EXAMPLE,DC=COM"

# -------------------------------------------   user: hue   ------------------------------------------- #

# Remove service account "hue" if exists
Remove-ADUser -Identity "CN=hue,OU=services,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create service account "hue"
New-ADUser -Name "hue" -OtherAttributes @{'title'="hue"} -path "OU=services,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=hue,OU=services,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=hue,OU=services,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=hue,OU=services,DC=EXAMPLE,DC=COM"

# ----------------------------------------   user: domain-admin   --------------------------------------- #

# Remove service account "domain-admin" if exists
Remove-ADUser -Identity "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create service account "domain-admin"
New-ADUser -Name "domain-admin" -OtherAttributes @{'title'="domain-admin"} -path "OU=services,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM"

# Add service account "domain-admin" to "Domain Admins", "Schema Admins", "Enterprise Admins" groups,
# so as it has enough privileges to add EMR cluster nodes into AD domain.
Add-ADGroupMember -Identity "Domain Admins" -Members "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM"
Add-ADGroupMember -Identity "Schema Admins" -Members "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM"
Add-ADGroupMember -Identity "Enterprise Admins" -Members "CN=domain-admin,OU=services,DC=EXAMPLE,DC=COM"

# ---------------------------------------------   user: example-user-1   --------------------------------------------- #

# Remove service account "example-user-1" if exists
Remove-ADUser -Identity "CN=example-user-1,CN=Users,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create normal domain user  "example-user-1"
New-ADUser -Name "example-user-1" -OtherAttributes @{'title'="example-user-1"} -path "CN=Users,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=example-user-1,CN=Users,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=example-user-1,CN=Users,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=example-user-1,CN=Users,DC=EXAMPLE,DC=COM"

# ---------------------------------------------   user: example-user-2   --------------------------------------------- #

# Remove service account "example-user-2" if exists
Remove-ADUser -Identity "CN=example-user-2,CN=Users,DC=EXAMPLE,DC=COM" -Confirm:$false

# Create normal domain user  "example-user-2"
New-ADUser -Name "example-user-2" -OtherAttributes @{'title'="example-user-2"} -path "CN=Users,DC=EXAMPLE,DC=COM"
Set-ADAccountPassword -Identity "CN=example-user-2,CN=Users,DC=EXAMPLE,DC=COM" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText 'Admin1234!' -Force)
Set-ADUser -Identity "CN=example-user-2,CN=Users,DC=EXAMPLE,DC=COM" -PasswordNeverExpires $true
Enable-ADAccount -Identity "CN=example-user-2,CN=Users,DC=EXAMPLE,DC=COM"
