param (
    [string]$DomainName = "example.com",
    [string]$Password = "Admin1234!",
    [string]$TrustedRealm ="COMPUTE.INTERNAL"
)

$DCs=$DomainName -split '\.'
$DomainNetbiosName=$DCs[0].ToUpper()
$DCs = $DCs | Foreach {"dc=$_"}
$BaseDN=$DCs -join ','

# Set default action in case action arg is ommitted
if($Args[0] -eq $Null) {
    $Action = "Pre-Install"
} else {
    $Action = $Args[0]
}

function Install {
    if($Action -eq "Pre-Install") {
        $RegPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
        $KeyName = "Post-Install-Ad"
        $Command = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File $PSScriptRoot\ad.ps1 Post-Install -DomainName $DomainName -Password $Password -TrustedRealm $TrustedRealm"

        # config post install job first
        if (-not ((Get-Item -Path $RegPath).$KeyName )) {
            New-ItemProperty -Path $RegPath -Name $KeyName -Value $Command -PropertyType ExpandString
        }
        else {
            Set-ItemProperty -Path $RegPath -Name $KeyName -Value $Command -PropertyType ExpandString
        }

        Pre-Install
    }
    elseif($Action -eq "Post-Install") {
        Post-Install
    }
    else {
        'ERROR!'
    }
}

function Pre-Install {
    # config "encrypt types for Kerberos" on AD
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters"
    New-Item -Path $RegPath -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name "SupportedEncryptionTypes" -Value '2147483647' -PropertyType DWORD -Force | Out-Null

    # install Active Directory
    Install-windowsfeature -name AD-Domain-Services -IncludeManagementTools
    # Import-Module ADDSDeployment
    # create forest, this command require reboot, although -NoRebootOnCompletion:$true can help skip reboot
    # however, it is still needed for AD to reboot anyway, otherwise, when run New-ADOrganizationalUnit, it will fail!
    Install-ADDSForest -DomainName $DomainName `
        -SafeModeAdministratorPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
        -DomainMode WinThreshold -DomainNetbiosName $DomainNetbiosName -ForestMode WinThreshold -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" -SysvolPath "C:\Windows\SYSVOL" -CreateDnsDelegation:$false -InstallDns:$true -Force:$true
    # A forced reboot is comming...
}

function Post-Install {
    ksetup /addkdc $TrustedRealm

    netdom trust $TrustedRealm /Domain:$DomainName /add /realm /passwordt:$Password

    # add one or both following items:
#    ksetup /SetEncTypeAttr $TrustedRealm AES256-CTS-HMAC-SHA1-96 AES128-CTS-HMAC-SHA1-96
    ksetup /SetEncTypeAttr $TrustedRealm AES256-CTS-HMAC-SHA1-96

    # --------------------------------------------   OU: Services   --------------------------------------------- #

    # Remove OU "Services" recursively if exists
    # Get-ADOrganizationalUnit -Identity "OU=Services,$BaseDN" |
    # Set-ADObject -ProtectedFromAccidentalDeletion:$false -PassThru |
    # Remove-ADOrganizationalUnit -Confirm:$false -Recursive

    # Add OU "Services"
    New-ADOrganizationalUnit -Name "Services" -Path "$BaseDN"

    # -------------------------------------------   user: ranger   ------------------------------------------- #

    # Remove service account "ranger" if exists
    # Remove-ADUser -Identity "CN=ranger,OU=Services,$BaseDN" -Confirm:$false

    # Create service account "ranger"
    New-ADUser -Name "ranger" -OtherAttributes @{'title'="ranger"} -path "OU=Services,$BaseDN"
    Set-ADAccountPassword -Identity "CN=ranger,OU=Services,$BaseDN" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
    Set-ADUser -Identity "CN=ranger,OU=Services,$BaseDN" -PasswordNeverExpires $true
    Enable-ADAccount -Identity "CN=ranger,OU=Services,$BaseDN"

    # -------------------------------------------   user: hue   ------------------------------------------- #

    # Remove service account "hue" if exists
    # Remove-ADUser -Identity "CN=hue,OU=Services,$BaseDN" -Confirm:$false

    # Create service account "hue"
    New-ADUser -Name "hue" -OtherAttributes @{'title'="hue"} -path "OU=Services,$BaseDN"
    Set-ADAccountPassword -Identity "CN=hue,OU=Services,$BaseDN" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
    Set-ADUser -Identity "CN=hue,OU=Services,$BaseDN" -PasswordNeverExpires $true
    Enable-ADAccount -Identity "CN=hue,OU=Services,$BaseDN"

    # ----------------------------------------   user: domain-admin   --------------------------------------- #

    # Remove service account "domain-admin" if exists
    # Remove-ADUser -Identity "CN=domain-admin,OU=Services,$BaseDN" -Confirm:$false

    # Create service account "domain-admin"
    New-ADUser -Name "domain-admin" -OtherAttributes @{'title'="domain-admin"} -path "OU=Services,$BaseDN"
    Set-ADAccountPassword -Identity "CN=domain-admin,OU=Services,$BaseDN" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
    Set-ADUser -Identity "CN=domain-admin,OU=Services,$BaseDN" -PasswordNeverExpires $true
    Enable-ADAccount -Identity "CN=domain-admin,OU=Services,$BaseDN"

    # Add service account "domain-admin" to "Domain Admins", "Schema Admins", "Enterprise Admins" groups,
    # so as it has enough privileges to add EMR cluster nodes into AD domain.
    Add-ADGroupMember -Identity "Domain Admins" -Members "CN=domain-admin,OU=Services,$BaseDN"
    Add-ADGroupMember -Identity "Schema Admins" -Members "CN=domain-admin,OU=Services,$BaseDN"
    Add-ADGroupMember -Identity "Enterprise Admins" -Members "CN=domain-admin,OU=Services,$BaseDN"

    # ----------------------------------------   user: example-user-1   ----------------------------------------- #

    # Remove service account "example-user-1" if exists
    # Remove-ADUser -Identity "CN=example-user-1,CN=Users,$BaseDN" -Confirm:$false

    # Create normal domain user  "example-user-1"
    New-ADUser -Name "example-user-1" -OtherAttributes @{'title'="example-user-1"} -path "CN=Users,$BaseDN"
    Set-ADAccountPassword -Identity "CN=example-user-1,CN=Users,$BaseDN" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
    Set-ADUser -Identity "CN=example-user-1,CN=Users,$BaseDN" -PasswordNeverExpires $true
    Enable-ADAccount -Identity "CN=example-user-1,CN=Users,$BaseDN"

    # ---------------------------------------   user: example-user-2   ------------------------------------------ #

    # Remove service account "example-user-2" if exists
    # Remove-ADUser -Identity "CN=example-user-2,CN=Users,$BaseDN" -Confirm:$false

    # Create normal domain user  "example-user-2"
    New-ADUser -Name "example-user-2" -OtherAttributes @{'title'="example-user-2"} -path "CN=Users,$BaseDN"
    Set-ADAccountPassword -Identity "CN=example-user-2,CN=Users,$BaseDN" -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force)
    Set-ADUser -Identity "CN=example-user-2,CN=Users,$BaseDN" -PasswordNeverExpires $true
    Enable-ADAccount -Identity "CN=example-user-2,CN=Users,$BaseDN"
}

Install
