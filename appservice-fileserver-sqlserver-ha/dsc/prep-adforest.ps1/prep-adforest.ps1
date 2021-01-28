configuration prep-adforest 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory,xDisk, xNetworking, cDisk, PSDesiredStateConfiguration, xDNS
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)
    $dnsFilePath = Join-Path $env:systemdrive "xdnsout\dnsIPs.txt"

    Node localhost
    {
        xExportClientDNSAddressesToFile ExportDNSServers
		{
			OutputFilePath = $dnsFilePath
		}
	
		WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"	
            DependsOn = '[xExportClientDNSAddressesToFile]ExportDNSServers'	
        }
<#
		WindowsFeature DnsTools
		{
			Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
		}
#>
        Script script1
		{
      	    SetScript =  { 
				Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false}
			DependsOn = "[WindowsFeature]DNS"
        }

        xDnsServerAddress DnsServerAddress 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
            DependsOn = "[WindowsFeature]DNS"
        }

        xWaitforDisk Disk2
        {
             DiskNumber = 2
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
             DependsOn = '[xDnsServerAddress]DnsServerAddress'
        }

        cDiskNoRestart ADDataDisk
        {
            DiskNumber = 2
            DriveLetter = "F"
            DependsOn = '[xWaitforDisk]Disk2'
        }

        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
			DependsOn= "[cDiskNoRestart]ADDataDisk"
        }  

		WindowsFeature ADAdminCenter 
        { 
            Ensure = "Present" 
            Name = "RSAT-AD-AdminCenter"
			DependsOn = "[WindowsFeature]ADDSInstall"
        }
		
		WindowsFeature ADDSTools 
        { 
            Ensure = "Present" 
            Name = "RSAT-ADDS-Tools"
			DependsOn = "[WindowsFeature]ADDSInstall"
        }  

        xADDomain FirstDS 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
			DependsOn = "[WindowsFeature]ADDSInstall"
        } 

        xAddDNSForwardersFromFile AddDNSForwarders
		{
			DNSIPsFilePath = $dnsFilePath
			DependsOn = '[xADDomain]FirstDS'
		}

        LocalConfigurationManager 
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }
   }
} 