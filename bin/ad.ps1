
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://raw.githubusercontent.com/bluishglc/ranger-emr-cli-installer/master/bin/ad-1.ps1","ad-1.ps1")
$WebClient.DownloadFile("https://raw.githubusercontent.com/bluishglc/ranger-emr-cli-installer/master/bin/ad-2.ps1","ad-2.ps1")
$WebClient.DownloadFile("https://raw.githubusercontent.com/bluishglc/ranger-emr-cli-installer/master/conf/ad/kerberos-encrytion-types.reg","kerberos-encrytion-types.reg")

workflow Install-AD {
    ad-1.ps1
    Restart-Computer -Wait
    ad-2.ps1
}

Install-AD