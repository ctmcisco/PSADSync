Write-Host 'Installing necessary PowerShell modules...'
$null = Install-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
$null = Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
Install-Module Pester -verbose -Force -Confirm:$false