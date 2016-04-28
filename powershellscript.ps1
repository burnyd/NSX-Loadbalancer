#creates the VM string name

$testlb = "sometestlb"

#Creates a simple one liner for loop to clone the VM twice

$sometest = 1..2 | Foreach {New-vm -ResourcePool homecluster -Name testlb$_ -Template Ubuntu14 | start-vm}

#insert some sort of wait becauase this may take a while before getting a vsphere mob ID. I used 10 minutes because my nfs share is ungodly slow at cloning.

Start-sleep -s 10

#Creates a array called idnumbers.  This will create a vm-xxx and vm-xx depending on how many times the for loop occurs.  Since NSX manager tracks the MOB id and not the vm name
we have to get this and put it in a array unfortunately.  

$idnumbers = (Get-VM $testlb*).id | % {$_.substring($_.indexof('-')+1)}

#The next part is connecting to the NSX manager API.  I took a lot of how to do this from Chris Wahls blog
I pretty much tried over and over different ways without much success lulz.

#Requires -Version 4.0

<#  
.SYNOPSIS  Creates a virtual network tier for VMware NSX
.DESCRIPTION Creates a virtual network tier for VMware NSX
.NOTES  Author:  Chris Wahl, @ChrisWahl, WahlNetwork.com
.PARAMETER NSX
	NSX Manager IP or FQDN
.PARAMETER NSXPassword
	NSX Manager credentials with administrative authority
.PARAMETER NSXUsername
	NSX Manager username with administrative authority
.PARAMETER JSONPath
	Path to your JSON configuration file
.PARAMETER vCenter
	vCenter Server IP or FQDN
.PARAMETER NoAskCreds
	Use your current login credentials for vCenter
.EXAMPLE
	PS> Create-NSXTier -NSX nsxmgr.tld -vCenter vcenter.tld -JSONPath "c:\path\prod.json"
#>

[CmdletBinding()]
Param(
	[Parameter(Mandatory=$true,Position=0,HelpMessage="NSX Manager IP or FQDN")]
	[ValidateNotNullorEmpty()]
	[String]$NSX,
	[Parameter(Mandatory=$true,Position=1,HelpMessage="NSX Manager credentials with administrative authority")]
	[ValidateNotNullorEmpty()]
	[System.Security.SecureString]$NSXPassword,
	[Parameter(Mandatory=$true,Position=2,HelpMessage="Path to your JSON configuration file")]
	[ValidateNotNullorEmpty()]
	[String]$JSONPath,
	[Parameter(Mandatory=$true,Position=3,HelpMessage="vCenter Server IP or FQDN")]
	[ValidateNotNullorEmpty()]
	[String]$vCenter,
	[String]$NSXUsername = "admin",
	[Parameter(HelpMessage="Use your current login credentials for vCenter")]
	[Switch]$NoAskCreds
	)

# Create NSX authorization string and store in $head
$nsxcreds = New-Object System.Management.Automation.PSCredential "admin",$NSXPassword
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NSXUsername+":"+$($nsxcreds.GetNetworkCredential().password)))
$head = @{"Authorization"="Basic $auth"}
$uri = "https://$nsx"

#############################################################################################################################################
# Create load balancer I am using edge-31 but you can use whichever edge-id you want to use.  Also creating keep alives and other things before registering the VIP																									#
#############################################################################################################################################


#Create the application profile.

	foreach ($_ in $idnumbers) {
		$body += "<loadBalancer>
<applicationProfile>
<applicationProfileId>applicationProfile-1</applicationProfileId>
<name>https</name>
<insertXForwardedFor>true</insertXForwardedFor>
<sslPassthrough>false</sslPassthrough>
<template>HTTPS</template>
<serverSslEnabled>false</serverSslEnabled>
</applicationProfile>
</loadBalancer>

		
		}

Write-Host 
	try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/edge-31/loadbalancer/config/applicationprofiles/" -Body $body -Method:Post -Headers $head -ContentType "application/xml" -TimeoutSec 180 -ErrorAction:Stop} catch {Failure}
	if ($r.StatusDescription -match "Created") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully created"
		}
	else {
		$body
		throw "Was not able to create router. API status description was not `"created`""
		}



#Create load balancer pool

#Need to figure out how to loop this for each pool member in the array.

	foreach ($_ in $idnumbers) {
		$body += "<loadBalancer>
    <pool>
        <poolId>pool-1</poolId>
        <name>test-pool</name>
        <algorithm>round-robin</algorithm>
        <transparent>true</transparent>
        <monitorId>monitor-3</monitorId>
        <member>
            <memberId>$idnumbers.[0]</memberId>
            <groupingObjectName>linux1</groupingObjectName>
            <groupingObjectId>$idnumbers.[0]</groupingObjectId>
            <weight>1</weight>
            <monitorPort>443</monitorPort>
            <port>443</port>
            <maxConn>0</maxConn>
            <minConn>0</minConn>
            <condition>disabled</condition>
            <name>linux1</name>
        </member>
        <member>
            <memberId>$idnumbers.[1]</memberId>
            <groupingObjectId>$idnumbers.[1]</groupingObjectId>
            <groupingObjectName>linux2</groupingObjectName>
            <weight>1</weight>
            <monitorPort>443</monitorPort>
            <port>443</port>
            <maxConn>0</maxConn>
            <minConn>0</minConn>
            <condition>disabled</condition>
            <name>linux2</name>
        </member>
    </pool>
</loadBalancer>
		}

Write-Host 
	try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/edge-31/loadbalancer/loadbalancer/config/pools" -Body $body -Method:Post -Headers $head -ContentType "application/xml" -TimeoutSec 180 -ErrorAction:Stop} catch {Failure}
	if ($r.StatusDescription -match "Created") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully created"
		}
	else {
		$body
		throw "Was not able to create router. API status description was not `"created`""
		}


#Create virtual servers..

$virtualip = "10.0.99.5"

$body += "<loadBalancer>
    <virtualServer>
        <virtualServerId>virtualServer-2</virtualServerId>
        <name>test</name>
        <enabled>true</enabled>
        <ipAddress>$virtualip</ipAddress>
        <protocol>http</protocol>
        <port>443</port>
        <connectionLimit>0</connectionLimit>
        <connectionRateLimit>0</connectionRateLimit>
        <defaultPoolId>pool-1</defaultPoolId>
        <applicationProfileId>applicationProfile-1</applicationProfileId>
        <enableServiceInsertion>false</enableServiceInsertion>
        <accelerationEnabled>false</accelerationEnabled>
    </virtualServer>
</loadBalancer>
 
}


Write-Host 
	try {$r = Invoke-WebRequest -Uri "$uri/api/4.0/edges/edge-31/loadbalancer/loadbalancer/config/virtualservers" -Body $body -Method:Post -Headers $head -ContentType "application/xml" -TimeoutSec 180 -ErrorAction:Stop} catch {Failure}
	if ($r.StatusDescription -match "Created") {Write-Host -BackgroundColor:Black -ForegroundColor:Green "Status: Successfully created"
		}
	else {
		$body
		throw "Was not able to create router. API status description was not `"created`""
		}


function Failure {
	$global:helpme = $body
	$global:helpmoref = $moref
	$global:result = $_.Exception.Response.GetResponseStream()
	$global:reader = New-Object System.IO.StreamReader($global:result)
	$global:responseBody = $global:reader.ReadToEnd();
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "Status: A system exception was caught."
	Write-Host -BackgroundColor:Black -ForegroundColor:Red $global:responsebody
	Write-Host -BackgroundColor:Black -ForegroundColor:Red "The request body has been saved to `$global:helpme"
	break
}













