# ==============================================================================================
# 
# Microsoft PowerShell Source File -- Created with SAPIEN Technologies PrimalScript 2012
# 
# NAME: Reset_Syslog.ps1
# 
# AUTHOR: Jason Foy , DaVita Inc.
# DATE  : 4/20/2015
# 
# COMMENT: Reset SysLog service on selected ESX hosts
# 
# ==============================================================================================

# $vCenterList = @{"sea-vctr01.davita.corp"="\\sea-vctrads01.davita.corp\e$\SYSLOG_DATA\"}
$vCenterList = @{"sea1w2vcvms01.davita.corp"="\\sea1w2vcvms01.davita.corp\e$\SYSLOG\";"sea1w1vcvms01.davita.corp"="\\sea1w1vcvms01.davita.corp\e$\SYSLOG\";"den3w1vcvms01.davita.corp"="\\den3w1vcvms01.davita.corp\e$\SYSLOG\"}
$TargetFile = "syslog.log"
$Drift = (-6) # Negative hours!

$ReportTitle = "ESX SysLog Audit Report"
$SMTP = "mmnlb.davita.com"
$From = "VMReports@davita.com"
# $To = "VMwareAlerts@davita.com"
$To = "jason.foy@davita.com"
# ==============================================================================================
# ==============================================================================================
$Version = "1.0.5"
$Subject = "$ReportTitle $(Get-Date -Format ""dd-MMM-yyyy HHmm"")"
$ScriptName = $MyInvocation.MyCommand.Name
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path
$ReadFile = "$ScriptPath\Reset_Syslog_Servers.csv"
$CompName = Get-Content env:computername
$Date = Get-Date -Format g
$TrackingFile = "$ScriptPath\ESX-Syslog-Tracking.csv"
$Tracking = @{}
$report = @()
$HostList = @{}
$FileList = @()
$FileCount = 0
$FolderDEL = 0
$Body = @()
$a = "<style type=""text/css"">"
$a = $a + "body{font-family:calibri;font-size:10pt;font-weight:normal;color:black;}"
$a = $a + "th{text-align:center; background-color:#00417c; color:#FFFFFF; font-weight:bold; font-size:12px;}"
$a = $a + "td{background-color:#F5F5F5; font-weight:normal; font-size:10px; padding: 3px 10px 3px 10px;}"
$a = $a + "</style>"
$Norm = "<style type=""text/css""> body{font-family:calibri;font-size:10pt;font-weight:normal;color:black;} th{text-align:center; background-color:#00417c; color:#FFFFFF; font-weight:bold; font-size:12px;} td{background-color:#F5F5F5; font-weight:normal; font-size:10px; padding: 3px 10px 3px 10px;}</style>"
$Risk = "<style type=""text/css""> body{font-family:calibri;font-size:10pt;font-weight:normal;color:black;} th{text-align:center; background-color:#00417c; color:#FFFFFF; font-weight:bold; font-size:12px;} td{background-color:#F5F5F5; font-weight:normal; font-size:10px; padding: 3px 10px 3px 10px;}</style>"
$Warn = "<style type=""text/css""> body{font-family:calibri;font-size:10pt;font-weight:normal;color:black;} th{text-align:center; background-color:#00417c; color:#FFFFFF; font-weight:bold; font-size:12px;} td{background-color:#F5F5F5; font-weight:normal; font-size:10px; padding: 3px 10px 3px 10px;}</style>"
Clear-Host
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host ""
Write-Host `t`t"$scriptName v$Version"
Write-Host `t`t"Started "(Get-Date -Format g)
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
$vmsnapin = Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
$Error.Clear()
Write-Host `t"Checking PowerCLI Snap-in..." -NoNewline
if ($vmsnapin -eq $null){Add-PSSnapin VMware.VimAutomation.Core
	if ($error.Count -eq 0){Write-Host `t`t"[ " -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host " ]"}
	else{Write-Host `t`t"[ " -NoNewline;Write-Host "ERROR" -ForegroundColor Red -NoNewline;Write-Host " ]"
		Exit}}
else{Write-Host `t`t"[ " -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host " ]"}
$Error.Clear()
$stop_watch = [Diagnostics.Stopwatch]::StartNew()
Write-Host `t"Importing Syslog Tracking: $TrackingFile"
Write-Host `t"Import File..." -NoNewline
if(Test-Path $TrackingFile){
	Write-Host `t`t`t`t"[ " -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host " ]" }
else{$return = New-Item $TrackingFile -type file
	Write-Host `t`t`t`t"[ " -NoNewline;Write-Host "NEW" -ForegroundColor Green -NoNewline;Write-Host " ]"}
Import-Csv $TrackingFile|%{$Tracking[$_.Host]=[int]$_.Count}
$SvcRestart=0;$SvcCheck=0;$DelCount=0;$FolderDEL=0
foreach ($vCenter in $vCenterList.Keys){
    $SyslogPath = $vCenterList[$vCenter]
    Write-Host `t"Reviewing Syslog Path: $SyslogPath"
    $FileList = Get-ChildItem -filter $TargetFile -recurse -path $SyslogPath | where {($_.LastWriteTime -lt ((get-date).AddHours($Drift)))}|Select Name,Directory,LastWriteTime
    $FileCount = $FileList.Length
    Write-Host `t"Files to Process: " -NoNewline
    if ($FileCount -gt 0){
    	Write-Host `t`t`t"[ " -NoNewline;Write-Host $FileCount -ForegroundColor Red -NoNewline;Write-Host " ]"
        Write-Host `t"Connecting to vCenter $vCenter...." -NoNewline -ForegroundColor Yellow
        $vConn = Connect-viserver $vCenter -Force -erroraction 'silentlycontinue'
        if ($vConn){
        	Write-Host `t`t"[ " -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host " ]"
            Write-Host `t"Gathering Host List...." -NoNewline
            $vmHostList = Get-VMHostNetworkAdapter -VMKernel -VMHost (get-vmhost|Where-Object { ($_.connectionstate -eq "connected") -or ($_.connectionstate -eq "maintenance")})|where{($_.Name -eq "vmk0")}|select IP,VMhost
            foreach($key in $vmHostList){$HostList.Add( $key.IP, $key.VMHost)}
            Write-Host `t`t`t"[ " -NoNewline;Write-Host $vmHostList.Length -ForegroundColor Red -NoNewline;Write-Host " ]"
	        $x=0
	        Write-Host `t"Processing Folder List...." -NoNewline
	        $FileList|%{
			Write-Progress -Id 1 -Activity "Processing Folders" -Status "$x of $FileCount" -PercentComplete ($x/$FileCount*100) -currentOperation "[ $FileDir ]"
            $FileName = $_.Name
            $FileDir = ($_.Directory).ToString()
            $HostIP = $fileDir.replace($SyslogPath,"")
            $FileWrite = $_.LastWriteTime
            $HostExists = $HostList.ContainsKey($HostIP)
            if($HostExists){
            	$SvcCheck++
            	$action = "restart"
            	$HostName = ($HostList[$HostIP].Name).ToString()
            	if($Tracking.ContainsKey($HostName)){$tmpCount = $Tracking[$HostName];$tmpCount++;$Tracking[$HostName]=$tmpCount}
            	else{$tmpCount=1;$Tracking.Add($HostName,$tmpCount)}
            	$EsxCli = Get-EsxCli -VMhost $HostName
            	try{
            		$return = $EsxCli.system.syslog.reload()}
            	catch{$return = $Error[0]}
            	if($Error.Count -eq 0){$SvcRestart++}
            	else{$ErrCount++}
            }
            Else{
            	$DelCount++
            	$HostName = "N/A"
				$action = "delete"
            	try{
            		Remove-Item -Path $FileDir -Recurse -Force -ErrorAction Stop}
            	catch{$return = $Error[0]}
            	if($Error.Count -eq 0){$FolderDEL++}
            	else{$ErrCount++}
           	}
	        $x++
	        $row = New-Object psobject
	        $row|Add-Member -Name "vCenter" -MemberType NoteProperty -Value $vCenter
	        $row|Add-Member -Name "HostIP" -MemberType NoteProperty -Value $HostIP
	        $row|Add-Member -Name "HostName" -MemberType NoteProperty -Value $HostName
	        $row|Add-Member -Name "HostExists" -MemberType NoteProperty -Value $HostExists
	        $row|Add-Member -Name "Folder" -MemberType NoteProperty -Value $FileDir
	        $row|Add-Member -Name "LastWrite" -MemberType NoteProperty -Value $FileWrite
	        $row|Add-Member -Name "Action" -MemberType NoteProperty -Value $action
	        $row|Add-Member -Name "History" -MemberType NoteProperty -Value $tmpCount
	        $row|Add-Member -Name "Result" -MemberType NoteProperty -Value $return
	        $report+=$row
        	}
        	Write-Host `t`t"[ " -NoNewline;Write-Host $FileCount -ForegroundColor Red -NoNewline;Write-Host " ]"
        	$report=$report|ConvertTo-Html vCenter,HostIP,HostName,HostExists,Folder,LastWrite,Action,History,Result -head $a -body "<H2>Actions for $vCenter</H2><hr>"
        	$Body+=$report
	        Write-Host `t"Disconnect from vCenter $vCenter...." -NoNewline -ForegroundColor Yellow
	        Disconnect-VIServer * -Confirm:$false
	        Write-Host `t`t"[ " -NoNewline;Write-Host "OK" -ForegroundColor Green -NoNewline;Write-Host " ]"
        }
        else{Write-Host `t`t"[ " -NoNewline;Write-Host "ERROR" -ForegroundColor Red -NoNewline;Write-Host " ]"}
    }
    Else{
    	Write-Host `t`t"[ " -NoNewline;Write-Host "0" -ForegroundColor Green -NoNewline;Write-Host " ]"
    	$report = ConvertTo-Html -head $a -body "<H2>Actions for $vCenter</H2><hr></br>No Issues found for $vCenter</br>"
    	$Body+=$report
    }
}
Write-Host `t"Saving Tracking Data... " -NoNewline
$Output = $Tracking.GetEnumerator()|%{New-Object psobject -Property (@{Host=$_.Name;Count=$_.Value})}
$Output|Export-Csv -NoTypeInformation $TrackingFile
Write-Host "[ " -NoNewline;Write-Host $TrackingFile -ForegroundColor Red -NoNewline;Write-Host " ]"
$MailStop = [Diagnostics.Stopwatch]::StartNew()
$MsgBody = "<hr>$ScriptName&emsp;v$Version [$CompName]</br>"
$MsgBody += "Start time&emsp;&emsp;&emsp;&emsp;&emsp;:&emsp;$Date</br>"
$MsgBody += "Services Checked/Restarted&emsp;:&emsp;$SvcCheck/$SvcRestart</br>"
$MsgBody += "Folders Attempt/Success&emsp;&emsp;:&emsp;$DelCount/$FolderDEL</br><hr>"
$Body = $MsgBody + $Body
Write-Host `t"Generating Email..." -NoNewline
# $att = New-Object system.Net.Mail.Attachment($File)
$mail = New-Object system.Net.Mail.SmtpClient($SMTP)
$msg =  New-Object system.Net.Mail.MailMessage
$msg.from = $From
$msg.subject = $Subject
$msg.body = $Body
$msg.IsBodyHtml = 1
# $msg.attachments.Add($att)
$msg.To.Add($To)
if(($FileCount+$FolderDEL) -ne 0){$msg.Priority = [System.Net.Mail.MailPriority]::High}
$mail.send($msg)
$MailStop.Stop()
$Elapsed = ($MailStop.elapsedmilliseconds)/1000
Write-Host `t`t`t"[" -NoNewline;Write-Host "SENT ($Elapsed seconds)" -ForegroundColor Green -NoNewline;Write-Host "]"
$stop_watch.Stop()
$Elapsed = ($stop_watch.elapsedmilliseconds)/1000
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ("="*80) -ForegroundColor DarkGreen
Write-Host ""
Write-Host `t`t"Script Completed in $Elapsed second(s)"
Write-Host `t`t"Resets :`t$SvcRestart of $SvcCheck"
Write-Host `t`t"Deletes:`t$FolderDEL of $DelCount"
Write-Host ""
Write-Host ("="*80) -ForegroundColor DarkGreen
exit
