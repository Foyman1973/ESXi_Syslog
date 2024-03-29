<#
	.NOTES
		========================================================================
		Windows PowerShell Source File

		NAME: Restart_Syslog_v2.ps1

		AUTHOR: Jason Foy , DaVita Inc.
		DATE  : 12/15/2017

		COMMENT: Checks LogInsight for recent HOSTD events, restarts Host syslog if none are found

		==========================================================================
#>
Clear-Host
$baseDate = get-date -date "1/1/1970 00:00:00"
# ==============================================================================================
# ==============================================================================================
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$Version = "2.1.154"
$ScriptName = $MyInvocation.MyCommand.Name
$scriptPath = Split-Path $MyInvocation.MyCommand.Path
$Date = Get-Date -Format g
# $dateSerial = Get-Date -Format yyyyMMdd
$reportFolder = Join-Path -Path $scriptPath -ChildPath "logfiles"
if(!(Test-Path $reportFolder)){New-Item -ItemType directory -Path $reportFolder|Out-Null}
$traceFile = Join-Path -Path $reportFolder -ChildPath "SysLog_Restart.trace"
$TrackingFile = Join-Path -Path $scriptPath -ChildPath "ESX-Syslog-Tracking.csv"
Start-Transcript -Append -Path $traceFile
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started $Date"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Exit-Script{
	[CmdletBinding()]
	param([string]$myExitReason)
	Write-Host $myExitReason
	Stop-Transcript
	exit
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function Get-PowerCLI{
	$pCLIpresent=$false
	Get-Module -Name VMware.VimAutomation.Core -ListAvailable | Import-Module -ErrorAction SilentlyContinue
	try{$pCLIpresent=((Get-Module VMware.VimAutomation.Core).Version.Major -ge 10)}
	catch{}
	return $pCLIpresent
}
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

if(!(Get-PowerCLI)){Write-Host "* * * * No PowerCLI Installed or version too old. * * * *" -ForegroundColor Red;Exit-Script}
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
$configFile = Join-Path -Path $scriptPath -ChildPath "config.xml"
if(!(Test-Path $configFile)){Write-Host "! ! ! Missing CONFIG.XML file ! ! !";Exit-Script}
[xml]$XMLfile = Get-Content $configFile -Encoding UTF8
$RequiredConfigVersion = "1"
if($XMLFile.Data.Config.Version -lt $RequiredConfigVersion){Write-Host "Config version is too old!";Exit-Script}
$DEV_MODE=$false;if($XMLFile.Data.Config.DevMode.value -eq "TRUE"){$DEV_MODE=$true;Write-Host "DEV_MODE ENABLED" -ForegroundColor Green}else{Write-Host "DEV_MODE DISABLED" -ForegroundColor red}
$SendMail=$false;if($XMLFile.Data.Config.SendMail.value -eq "TRUE"){$SendMail=$true;Write-Host "SENDMAIL ENABLED" -ForegroundColor Green}else{Write-Host "SENDMAIL DISABLED" -ForegroundColor red}
if($DEV_MODE){
	$vCenterList = $XMLFile.Data.Config.vCenterList_TEST.value
	$FROM = $XMLFile.Data.Config.FROM_TEST.value
	$TO = $XMLFile.Data.Config.TO_TEST.value
	$reportTitle = "DEV $reportTitle"
}
else{
	$vCenterList = $XMLFile.Data.Config.vCenterList.value
	$FROM = $XMLFile.Data.Config.FROM.value
	$TO = $XMLFile.Data.Config.TO.value
}
$SMTP = $XMLFile.Data.Config.SMTP.value
$reportTitle = $XMLFile.Data.Config.ReportTitle.value
$subject = "$reportTitle $(Get-Date -Format yyyy-MMM-dd)"
$vCenterFilter = $XMLFile.Data.Config.vCenterFilter.value
$vRLIlogin = $XMLFile.Data.Config.vRLIlogin.value
$retryTest = $XMLFile.Data.Config.retryTest.value
$thresholdMinutes = $XMLFile.Data.Config.thresholdMinutes.value
$rootAPI = $XMLFile.Data.Config.rootAPI.value
if(Test-Path $vCenterList){Write-Host "Loading vCenter List:" $vCenterList;$vCenters = Import-Csv $vCenterList -Delimiter ","}
else{Write-Host "Missing vCenter List File" -ForegroundColor Red;Exit-Script}
if(Test-Path $vRLIlogin){
	$vRLICredentials = Import-Csv $vRLIlogin -Delimiter ","
	$vRLIuser = $vRLICredentials.ID
	$vRLIpass = ConvertTo-SecureString -String $vRLICredentials.HASH
	$vRLIprovider = $vRLICredentials.Provider
}
else{Write-Host "Missing vRLI Credentials List File" -ForegroundColor Red;Exit-Script}
Write-Host "Importing Syslog Tracking: $TrackingFile"
if(!(Test-Path $TrackingFile)){New-Item $TrackingFile -type file|Out-Null}
Import-Csv $TrackingFile -Delimiter ","|ForEach-Object{$hostTracking[$_.HostName]=@([int]$_.RestartCount,[datetime]$_.LastRestart)}
Set-Variable -Name authHeader -Value @{} -Option AllScope
$sessionURI = "$($rootAPI)sessions"
$jsonHeader = @{"Content-Type"="application/json"}
$authHeader = @{"Authorization"=$(Get-BearerToken -myURI $sessionURI -myHeader $jsonHeader -myUserName $vRLIuser -myHash $vRLIpass -myProvider $vRLIprovider)}
$myReport = @()
$vCenterCount = $vCenterList.Count
Write-Host "Found $vCenterCount vCenter instances"
$vCenterFailed = 0
foreach($vCenter in $vCenters){
	$thisvCenter = $vCenter.Name
	$hostList = $null
	if($vCenter.CLASS -eq $vCenterFilter){
		Write-Host ("+"*80);Write-Host "Connecting to vCenter $thisvCenter...." -ForegroundColor White;Write-Host ("+"*80)
		$vConn = Connect-VIServer $vCenter.NAME -Credential (New-Object System.Management.Automation.PSCredential $vCenter.ADMIN, (ConvertTo-SecureString $vCenter.HASH2))
		if($vConn){
			$hostList = Get-VMHost|Where-Object{($_.ConnectionState -eq "connected") -or ($_.ConnectionState -eq "maintenance")}
			$hostCount = $hostList.Count
			Write-Host "Found $hostCount Hosts to check"
			foreach ($vmHost in $hostList){
				$thisURL = $rootAPI+"events/source/CONTAINS%20$($vmHost.Name)/appname/CONTAINS%20hostd?limit=1&order-by-direction=DESC&view=SIMPLE"
				$row=""|Select-Object HostName,vCenter,LogStatus,EventDelta,ServiceRestart
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
if($SendMail){
	$reportHTML = $myReport|ConvertTo-Html HostName,vCenter,LogStatus,EventDelta,ServiceRestart -Head $XMLfile.Data.Config.TableFormats.Blue.value -Body "<h4>Audit Items</h4>"
	Send-MailMessage -Subject $subject -From $FROM -To $TO -Body $reportHTML -BodyAsHtml -SmtpServer $SMTP
}
$stopwatch.Stop()
$Elapsed = [math]::Round(($stopwatch.elapsedmilliseconds)/1000,1)
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Script Completed in $Elapsed second(s)"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Exit-Script -myExitReason "*** Script Completed Normally ***"
