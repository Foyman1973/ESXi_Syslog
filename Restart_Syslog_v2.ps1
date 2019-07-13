<#
	.NOTES
		========================================================================
		Windows PowerShell Source File
		Created with SAPIEN Technologies PrimalScript 2017
		
		NAME: Restart_Syslog_v2.ps1
		
		AUTHOR: Jason Foy , DaVita Inc.
		DATE  : 12/15/2017
		
		COMMENT: Checks LogInsight for recent HOSTD events, restarts Host syslog if none are found
		
		==========================================================================
#>


$vCenterList = "C:\Transfer\Dropbox\Scripts\Powershell\VMware\CONTROL\vCenterList.csv"
$vCenterFilter = "PROD"
$vRLIlogin = "C:\Transfer\Dropbox\Scripts\Powershell\VMware\CONTROL\vRLIInstances.csv"
$retryTest = 10
$thresholdMinutes = 15
$rootAPI = "https://loginsight.davita.corp/api/v1/"
$baseDate = get-date -date "1/1/1970 00:00:00"

# ==============================================================================================
# ==============================================================================================
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$Version = "2.1.153"
$ScriptName = $MyInvocation.MyCommand.Name
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$StartTime = Get-Date
$Date = Get-Date -Format g
$dateSerial = Get-Date -Format yyyyMMdd
$reportFolder = Join-Path -Path $scriptPath -ChildPath "logfiles"
if(!(Test-Path $reportFolder)){New-Item -ItemType directory -Path $reportFolder|Out-Null}
$traceFile = Join-Path -Path $reportFolder -ChildPath "SysLog_Restart-$dateSerial.log"
$TrackingFile = Join-Path -Path $scriptPath -ChildPath "ESX-Syslog-Tracking.csv"
Clear-Host
Start-Transcript -Append -Path $traceFile
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started $Date"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-ThisScript{
	[CmdletBinding()]
	param([string]$myExitReason)
	Write-Host $myExitReason
	Stop-Transcript
	Exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Check-PowerCLIv3{
	$pCLIpresent=$false
	Get-Module -Name VMware* -ListAvailable | Import-Module -ErrorAction SilentlyContinue
	Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
	try{$myVersion = Get-PowerCLIVersion;$pCLIpresent=$true}
	catch{}
	return $pCLIpresent
}
Write-Host "Checking PowerCLI Snap-in..."
if(!(Check-PowerCLIv3)){Write-Host "No PowerCLI Installed" -ForegroundColor Red;Exit-ThisScript}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-BearerToken{
	[OutputType([string])]
	param([Parameter(Mandatory = $true)][string]$myURI,
		[Parameter(Mandatory = $true)][hashtable]$myHeader,
		[Parameter(Mandatory = $true)][string]$myUserName,
		[Parameter(Mandatory = $true)][securestring]$myHash,
		[Parameter(Mandatory = $true)][string]$myProvider)
	Write-Host "Retrieving bearer token from API..."
	$sessionData = Invoke-RestMethod -Method Post -Uri $myURI -Headers $jsonHeader -Body $(ConvertTo-Json(@{"username"=$myUserName;"password"=$([Runtime.InteropServices.Marshal]::PtrToStringAuto(([Runtime.InteropServices.Marshal]::SecureStringToBSTR($myHash))));"provider"=$myProvider}))
	$bearerString = "Bearer $($sessionData.sessionId)"
	return $bearerString
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Test-RESTsession{
	param([Parameter(Mandatory = $true)][string]$myURI,
		[Parameter(Mandatory = $true)][hashtable]$myHeader)
	$validSession = $false
	$error.Clear()
	Write-Host	"Testing session..." -ForegroundColor Cyan
	try{
		$thisSessionTest = Invoke-RestMethod -Method GET -Uri $myURI -Headers $myHeader -ErrorAction SilentlyContinue
		if($thisSessionTest){$validSession = $true}
	}
	Catch{
		switch ($error.exception.message){
			'The remote server returned an error: (440).'{
				Write-Host "LoginTimeout, logging back in"
				$x=1
				do{
					$authHeader = @{"Authorization"=$(Get-BearerToken -myURI $sessionURI -myHeader $jsonHeader -myUserName $vRLIuser -myHash $vRLIpass -myProvider $vRLIprovider)}
					if(Test-RESTsession -myURI $sessionURI -myHeader $authHeader){$validSession = $true}
					$x++
				}
				until($validSession -or ($x -ge $retryTest))
				if( -not $validSession){Write-Host "Unable to get valid session.  ERR: $($error.Exception)";Exit-ThisScript}
				else{$Error.Clear()}
			}
			'The remote server returned an error: (401) Unauthorized.'{
				Write-Host "Unauthorized, Logging In"
				$x=1
				do{
					$authHeader = @{"Authorization"=$(Get-BearerToken -myURI $sessionURI -myHeader $jsonHeader -myUserName $vRLIuser -myHash $vRLIpass -myProvider $vRLIprovider)}
					if(Test-RESTsession -myURI $sessionURI -myHeader $authHeader){$validSession = $true}
					$x++
				}
				until($validSession -or ($x -ge $retryTest))
				if( -not $validSession){Write-Host "Unable to get valid session.  ERR: $($error.Exception)";Exit-ThisScript}
				else{$Error.Clear()}
			}
			'The remote server returned an error: (404) Not Found.'{Write-Host "Bad URI String"}
			'The remote server returned an error: (400) Bad Request.'{Write-Host "Bad Request"}
			default {Write-Host "Unhandled Error: $($error.Exception)"}
		}
	}
	return $validSession
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
if(Test-Path $vCenterList){Write-Host "Loading vCenter List:" $vCenterList;$vCenters = Import-Csv $vCenterList -Delimiter ","}
else{Write-Host "Missing vCenter List File" -ForegroundColor Red;Exit-ThisScript}
if(Test-Path $vRLIlogin){
	$vRLICredentials = Import-Csv $vRLIlogin -Delimiter ","
	$vRLIuser = $vRLICredentials.ID
	$vRLIpass = ConvertTo-SecureString -String $vRLICredentials.HASH
	$vRLIprovider = $vRLICredentials.Provider
}
else{Write-Host "Missing vRLI Credentials List File" -ForegroundColor Red;Exit-ThisScript}
Write-Host "Importing Syslog Tracking: $TrackingFile"
if(!(Test-Path $TrackingFile)){New-Item $TrackingFile -type file|Out-Null}
Import-Csv $TrackingFile -Delimiter ","|%{$hostTracking[$_.HostName]=@([int]$_.RestartCount,[datetime]$_.LastRestart)}
Set-Variable -Name authHeader -Value @{} -Option AllScope
$sessionURI = "$($rootAPI)sessions"
$jsonHeader = @{"Content-Type"="application/json"}
$authHeader = @{"Authorization"=$(Get-BearerToken -myURI $sessionURI -myHeader $jsonHeader -myUserName $vRLIuser -myHash $vRLIpass -myProvider $vRLIprovider)}
$myReport = @()

$vCenterCount = $vCenterList.Count
$vCenterFailed = 0
foreach($vCenter in $vCenters){
	$thisvCenter = $vCenter.Name
	$hostList = $null
	if($vCenter.CLASS -eq $vCenterFilter){
		Write-Host ("+"*80);Write-Host "Connecting to vCenter $thisvCenter...." -ForegroundColor White;Write-Host ("+"*80)
		$vConn = Connect-VIServer $vCenter.NAME -Credential (New-Object System.Management.Automation.PSCredential $vCenter.ADMIN, (ConvertTo-SecureString $vCenter.HASH2))
		if($vConn){
			$hostList = Get-VMHost|?{($_.ConnectionState -eq "connected") -or ($_.ConnectionState -eq "maintenance")}
			$hostCount = $hostList.Count
			foreach ($vmHost in $hostList){
				$thisURL = $rootAPI+"events/source/CONTAINS%20$($vmHost.Name)/appname/CONTAINS%20hostd?limit=1&order-by-direction=DESC&view=SIMPLE"
				$row=""|select HostName,vCenter,LogStatus,EventDelta,ServiceRestart
				Write-Host "Host:" $vmHost.Name -ForegroundColor Yellow
				$thisStatus = "GOOD";$thisAction = "FAILED"
				if(Test-RESTsession -myURI $sessionURI -myHeader $authHeader){
					$thisLogSet = Invoke-RestMethod -Method GET -Uri $thisURL -Headers $authHeader -ErrorAction SilentlyContinue
					$newDate = $basedate.AddMinutes((($thisLogSet.results.timestamp)/1000)/60)
					$eventSpan = (New-TimeSpan -Start $newDate -End ((Get-Date).ToUniversalTime())).TotalMinutes
					if($eventSpan -gt $thresholdMinutes){
						Write-Host "*** Too Long! *** " $eventSpan -ForegroundColor Red
						$thisStatus="OFFLINE"
						$Error.Clear()
					    $EsxCli = Get-EsxCli -VMhost $vmHost
		            	try{
		            		$myResult = $EsxCli.system.syslog.reload()}
		            	catch{$myResult = $Error}
		            	if($Error.Count -eq 0){$thisAction = "RELOAD SENT:$($myResult)"}
		            	else{$thisAction = $Error.exception.message}
		            	Write-Host "ACTION:" $thisAction
# 		            	if($hostTracking.ContainsKey($vmHost.Name)){$hostTracking[$vmHost.Name]=@($(($hostTracking[$vmHost.Name]).RestartCount)+1,$(Get-Date))}
# 		            	else{$hostTracking.Add(1,$(Get-Date))}
					}
					else{Write-Host "Close Enough: " $eventSpan -ForegroundColor Green}
					$row.HostName = $vmHost
					$row.vCenter = $thisvCenter
					$row.LogStatus = $thisStatus
					$row.EventDelta = $eventSpan
					$row.ServiceRestart = $thisAction
					$myReport+=$row
				}
			}
			Write-Host "Disconnecting vCenter $thisvCenter"
            Disconnect-VIServer $vConn -Confirm:$false
		}
		else{Write-Host "Failed to connect to vCenter $thisvCenter" -ForegroundColor Red;$vCenterFailed++}
	}
}
# Write-Host "Writing to Tracking file..."
# $hostTracking.GetEnumerator()|%{$row=""|select HostName,RestartCount,LastRestart;$row.HostName=$_.HostName;$row.RestartCount=($_.HostName).RestartCount;$row.LastRestart=($_.HostName).LastRestart;$trackingFileOut+=$row}
# $trackingFileOut|Export-Csv -NoTypeInformation $TrackingFile
$stopwatch.Stop()
$Elapsed = [math]::Round(($stopwatch.elapsedmilliseconds)/1000,1)
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Script Completed in $Elapsed second(s)"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Exit-ThisScript -myExitReason "*** Script Completed Normally ***"
