workflow importdata-AssetsInfra
{
    Param
    (
        [parameter(Mandatory=$true, Position=1, HelpMessage="The name of the Azure Subscription")]
        [String]$AzureSubscriptionName,
        
        [parameter(Mandatory=$true, Position=2, HelpMessage="The storage account name in which the script will be stored")]
        [String]$StorageAccountName,
        
        [parameter(Mandatory=$true, Position=3, HelpMessage="The access key for the storage account")]
        [String]$StorageAccountKey,
        
        [parameter(Mandatory=$true, Position=4, HelpMessage="")]
        [String]$ResourceName,
        
        [parameter(Mandatory=$true, Position=5, HelpMessage="")]
        [String]$StorSimRegKey,
        
        [parameter(Mandatory=$true, Position=6, HelpMessage="")]
        [String]$TargetDeviceName,
        
        [parameter(Mandatory=$true, Position=7, HelpMessage="")]
        [String]$VnetName,
        
        [parameter(Mandatory=$true, Position=8, HelpMessage="")]
        [String]$VDServiceEncryptionKey,
        
        [parameter(Mandatory=$true, Position=9, HelpMessage="")]
        [string]$MailSmtpServer,
        
        [parameter(Mandatory=$false, Position=10, HelpMessage="")]
        [string]$SmtpPortNo,
        
        [parameter(Mandatory=$true, Position=11, HelpMessage="")]
        [string]$MailTo,
        
        [parameter(Mandatory=$false, Position=12, HelpMessage="")]
        [string]$MailCc,
        
        [parameter(Mandatory=$true, Position=13)]
        [String]$AutomationAccountName
    )
    
    # Fetch basic Azure automation variables
    $AzureCredential = Get-AutomationPSCredential -Name "AzureCredential"
    If ($AzureCredential -eq $null) 
    {
        throw "The AzureCredential asset has not been created in the Automation service."  
    }
    
    $SubscriptionName = $AzureSubscriptionName# Get-AutomationVariable –Name "AzureSubscriptionName"
    if ($SubscriptionName -eq $null) 
    { 
        throw "The AzureSubscriptionName asset has not been created in the Automation service."  
    }
    
    # Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential      
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName          
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
    }
    
    # Fetch DummySVAs asset variable
    try {
        $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)
    }
    catch {
        throw "The Automation account ($AutomationAccountName) was not found."
    }
    
    # AssetName
    $AssetPrefix = "ImportData"
    
    $AssetName = "AzureSubscriptionName"
    $AssetValue = $AzureSubscriptionName
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-AutomationAccountName"
    $AssetValue = $AutomationAccountName 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-ResourceName"
    $AssetValue = $ResourceName 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-StorageAccountName"
    $AssetValue = $StorageAccountName 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-StorageAccountKey"
    $AssetValue = $StorageAccountKey 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-StorSimRegKey"
    $AssetValue = $StorSimRegKey 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-TargetDeviceName"
    $AssetValue = $TargetDeviceName 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-VnetName"
    $AssetValue = $VnetName 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-VDServiceEncryptionKey"
    $AssetValue = $VDServiceEncryptionKey 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-MailSmtpServer"
    $AssetValue = $MailSmtpServer 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-MailPort"
    $AssetValue = $SmtpPortNo 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-MailTo"
    $AssetValue = $MailTo 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
    
    $AssetName = "$AssetPrefix-MailCc"
    $AssetValue = $MailCc 
    If (($AssetList | Where-Object {$_.Name -eq $AssetName}) -ne $null) {
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Encrypted $false -Value $AssetValue
        Write-Output "Asset ($AssetName) updated"
    }
    else {
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Value $AssetValue -Encrypted $false
        Write-Output "Asset ($AssetName) created"
    }
}