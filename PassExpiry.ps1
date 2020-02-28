<#	
	.NOTES
	===========================================================================
	 Created on:   	3/27/2018 7:37 PM
     Modified last: 2/5/2020
	 Created by:   	Bradley Wyatt
     Modified by:   Richard Poole
	 Version: 	    1.0.1
	 Notes:
	The variables you should change are the SMTP Host, From Email and Expireindays. I suggest keeping the DirPath
	SMTPHOST: The smtp host it will use to send mail
	FromEmail: Who the script will send the e-mail from
	ExpireInDays: Amount of days before a password is set to expire it will look for, in my example I have 7. Any password that will expire in 7 days or less will start sending an email notification 

	Run the script manually first as it will ask for credentials to send email and then safely store them for future use.
    The body has been modified and enabled to handle HTML code along with a sample of how to attach images and embed them in the email for assurances it isn't a phishing email.
	===========================================================================
	.DESCRIPTION
		This script will send an e-mail notification to users where their password is set to expire soon. It includes step by step directions for them to 
		change it on their own.

		It will look for the users e-mail address in the emailaddress attribute and if it's empty it will use the proxyaddress attribute as a fail back. 

		The script will log each run at $DirPath\log.txt
#>

#VARs

#SMTP Host
$SMTPHost = "smtp.office365.com"
#Who is the e-mail from
$FromEmail = "AdminSupport@domussapientiae.com"
#Password expiry days
$expireindays = 15

#Program File Path
$DirPath = "C:\Automation\PasswordExpiry"

$Date = Get-Date
#Check if program dir is present
$DirPathCheck = Test-Path -Path $DirPath
If (!($DirPathCheck))
{
	Try
	{
		#If not present then create the dir
		New-Item -ItemType Directory $DirPath -Force
	}
	Catch
	{
		$_ | Out-File ($DirPath + "\" + "Log.txt") -Append
	}
}
#CredObj path
$CredObj = ($DirPath + "\" + "EmailExpiry.cred")
#Check if CredObj is present
$CredObjCheck = Test-Path -Path $CredObj
If (!($CredObjCheck))
{
	"$Date - INFO: creating cred object" | Out-File ($DirPath + "\" + "Log.txt") -Append
	#If not present get office 365 cred to save and store
	$Credential = Get-Credential -Message "Please enter your Office 365 credential that you will use to send e-mail from $FromEmail. If you are not using the account $FromEmail make sure this account has 'Send As' rights on $FromEmail."
	#Export cred obj
	$Credential | Export-CliXml -Path $CredObj
}

Write-Host "Importing Cred object..." -ForegroundColor Yellow
$Cred = (Import-CliXml -Path $CredObj)


# Get Users From AD who are Enabled, Passwords Expire and are Not Currently Expired
"$Date - INFO: Importing AD Module" | Out-File ($DirPath + "\" + "Log.txt") -Append
Import-Module ActiveDirectory
"$Date - INFO: Getting users" | Out-File ($DirPath + "\" + "Log.txt") -Append
$users = Get-Aduser -properties Name, PasswordNeverExpires, PasswordExpired, PasswordLastSet, EmailAddress -filter { (Enabled -eq 'True') -and (PasswordNeverExpires -eq 'False') } | Where-Object { $_.PasswordExpired -eq $False }

$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

# Process Each User for Password Expiry
foreach ($user in $users)
{
	$Name = (Get-ADUser $user | ForEach-Object { $_.Name })
	Write-Host "Working on $Name..." -ForegroundColor White
	Write-Host "Getting e-mail address for $Name..." -ForegroundColor Yellow
	$emailaddress = $user.emailaddress
	If (!($emailaddress))
	{
		Write-Host "$Name has no E-Mail address listed, looking at their proxyaddresses attribute..." -ForegroundColor Red
		Try
		{
			$emailaddress = (Get-ADUser $user -Properties proxyaddresses | Select-Object -ExpandProperty proxyaddresses | Where-Object { $_ -cmatch '^SMTP' }).Trim("SMTP:")
		}
		Catch
		{
			$_ | Out-File ($DirPath + "\" + "Log.txt") -Append
		}
		If (!($emailaddress))
		{
			Write-Host "$Name has no email addresses to send an e-mail to!" -ForegroundColor Red
			#Don't continue on as we can't email $Null, but if there is an e-mail found it will email that address
			"$Date - WARNING: No email found for $Name" | Out-File ($DirPath + "\" + "Log.txt") -Append
		}
		
	}
	#Get Password last set date
	$passwordSetDate = (Get-ADUser $user -properties * | ForEach-Object { $_.PasswordLastSet })
	#Check for Fine Grained Passwords
	$PasswordPol = (Get-ADUserResultantPasswordPolicy $user)
	if (($PasswordPol) -ne $null)
	{
		$maxPasswordAge = ($PasswordPol).MaxPasswordAge
	}
	
	$expireson = $passwordsetdate + $maxPasswordAge
	$today = (get-date)
	#Gets the count on how many days until the password expires and stores it in the $daystoexpire var
	$daystoexpire = (New-TimeSpan -Start $today -End $Expireson).Days
	
	If (($daystoexpire -ge "0") -and ($daystoexpire -lt $expireindays))
	{
		"$Date - INFO: Sending expiry notice email to $Name" | Out-File ($DirPath + "\" + "Log.txt") -Append
		Write-Host "Sending Password expiry email to $name" -ForegroundColor Yellow
		
		$SmtpClient = new-object system.net.mail.smtpClient
		$MailMessage = New-Object system.net.mail.mailmessage
		
		#Who is the e-mail sent from
		$mailmessage.From = $FromEmail
		#SMTP server to send email
		$SmtpClient.Host = $SMTPHost
		#SMTP SSL
		$SMTPClient.EnableSsl = $true
		#SMTP credentials
		$SMTPClient.Credentials = $cred
        #Enable HTML
        $mailmessage.IsBodyHtml = $true
		#Send e-mail to the users email
		$mailmessage.To.add("$emailaddress")
		#Email subject
		$mailmessage.Subject = "Your password will expire in $daystoexpire days"
		#Notification email on delivery / failure
		$MailMessage.DeliveryNotificationOptions = ("onSuccess", "onFailure")
		#Send e-mail with high priority
		$MailMessage.Priority = "High"
        $attach1 = new-object Net.Mail.Attachment("C:\Automation\PasswordExpiry\content_files\image002.jpg")
        $attach2 = new-object Net.Mail.Attachment("C:\Automation\PasswordExpiry\content_files\image003.jpg")
        $mailmessage.Attachments.Add($attach1)
        $mailmessage.Attachments.Add($attach2)
		$mailmessage.Body =
		"<img src=image002.jpg width=100 height=100><br>
Dear $Name,<br><br>

Your password will expire in $daystoexpire days. Please change your password as soon as possible to prevent any interruption accessing your DomusSapientiae account!<br><br>

Review the <a href=https://domussapientiae.sharepoint.com/Policies/Information%20Services/password%20policy%20and%20procedure.pdf>Password Policy</a> for instructions on changing your password. We also recommend using the instructions in the Password Policy document to setup Self-Service Password reset.<br><br>

If you are a remote user, you will want to be sure to follow the instructions for remote users, so that your computer password gets updated with your account password.<br><br>

If you have concerns please email <a href=emailto:AdminSupport@domussapientiae.com>AdminSupport@domussapientiae.com</a> for assistance.<br>
<img src=image003.jpg width=200 height=40>
"
		Write-Host "Sending E-mail to $emailaddress..." -ForegroundColor Green
		Try
		{
			$smtpclient.Send($mailmessage)
		}
		Catch
		{
			$_ | Out-File ($DirPath + "\" + "Log.txt") -Append
		}
	}
	Else
	{
		"$Date - INFO: Password for $Name not expiring for $daystoexpire days" | Out-File ($DirPath + "\" + "Log.txt") -Append
		Write-Host "Password for $Name does not expire for $daystoexpire days" -ForegroundColor White
	}
}