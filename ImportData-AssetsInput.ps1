<#
.DESCRIPTION
    This runbook creates all assets which required for Import process.
     
.ASSETS 
    AzureCredential [Windows PS Credential]:
        A credential containing an Org Id username, password with access to this Azure subscription
        Multi Factor Authentication must be disabled for this credential
         
    AzureSubscriptionName: The name of the Azure Subscription
    ResourceName: The name of the StorSimple resource
    StorSimRegKey: The registration key for the StorSimple manager
    StorageAccountName: The storage account name in which the script will be stored
    StorageAccountKey: The access key for the storage account
    TargetDeviceName: The Device on which the volume containers from the source device will change ownership and are transferred to the target device
    VnetName: The name of the Virtual network in which the Virtual device & Virtual machine will be created
	VDServiceEncryptionKey: Virtual device service encryption key 
    MailSmtpServer: The name of the SmtpServer
    MailPortNo (Optional): Port number of the SmtpServer. Optional, when the port no is 25 (Default)
    MailTo: A comma separated string of To email addresses
    MailCc (Optional): A comma separated string of CC email addresses
    AutomationAccountName: The name of the Automation account name
    
.NOTES:
	Multi Factor Authentication must be disabled to execute this runbook

#>
workflow ImportData-AssetsInput
{
    Param
    (
        [parameter(Mandatory=$true, Position=1, HelpMessage="The name of the Azure Subscription")]
        [String]$AzureSubscriptionName,
        
        [parameter(Mandatory=$true, Position=2, HelpMessage="The name of the StorSimple resource")]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceName,
        
        [parameter(Mandatory=$true, Position=3, HelpMessage="The registration key for the StorSimple manager")]
        [ValidateNotNullOrEmpty()]
        [string]$StorSimRegKey,
        
        [parameter(Mandatory=$true, Position=4, HelpMessage="The storage account name in which import data is resided")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,
        
        [parameter(Mandatory=$true, Position=5, HelpMessage="The access key for the storage account")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountKey,
        
        [parameter(Mandatory=$true, Position=6, HelpMessage="The name of the Target device (Physical / Virtual device)")]
		[ValidateNotNullOrEmpty()]
        [String]$TargetDeviceName,
        
        [parameter(Mandatory=$true, Position=7, HelpMessage="The name of the Virtual network in which the Virtual device & Virtual machine will be created")]
		[ValidateNotNullOrEmpty()]
        [String]$VnetName,
        
        [parameter(Mandatory=$true, Position=8, HelpMessage="Virtual Device Service Encryption Key")]
		[ValidateNotNullOrEmpty()]
        [String]$VDServiceEncryptionKey,
        
        [parameter(Mandatory=$true, Position=9, HelpMessage="The name of the SmtpServer")]
        [ValidateNotNullOrEmpty()]
        [string]$MailSmtpServer,
        
        [parameter(Mandatory=$false, Position=10, HelpMessage="Port number (Optional) of SmtpServer. Optional, when the port no is 25 (Default)")]
        [ValidateRange(0,10)]
        [Int]$MailSmtpPortNo=25,
        
        [parameter(Mandatory=$true, Position=11, HelpMessage="A comma separated string of To email addresses")]
        [ValidateNotNullOrEmpty()]
        [string]$MailTo,
        
        [parameter(Mandatory=$false, Position=12, HelpMessage="A comma separated string of Cc email addresses (Optional)")]
        [string]$MailCc,
        
        [parameter(Mandatory=$true, Position=13, HelpMessage="The name of the Aumation account name")]
        [String]$AutomationAccountName
    )
	
    # Set empty string if input is null   
    If ([string]::IsNullOrEmpty($MailCc) -eq $true) {
        $MailCc = ""
    }
    
    # Add all assets to collection object
    $NewAssetList = @()
    $AssetProp = @{ Name="AzureSubscriptionName"; Value=$AzureSubscriptionName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="ResourceName"; Value=$ResourceName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="StorSimRegKey"; Value=$StorSimRegKey; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="StorageAccountName"; Value=$StorageAccountName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="StorageAccountKey"; Value=$StorageAccountKey; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="TargetDeviceName"; Value=$TargetDeviceName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="VnetName"; Value=$VnetName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="VDServiceEncryptionKey"; Value=$VDServiceEncryptionKey; IsMandatory=$true; IsEncrypted=$true; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="MailSmtpServer"; Value=$MailSmtpServer; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="MailSmtpPortNo"; Value=$MailSmtpPortNo; IsMandatory=$false; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="MailTo"; Value=$MailTo; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="MailCc"; Value=$MailCc; IsMandatory=$false; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
    
    $AssetProp = @{ Name="AutomationAccountName"; Value=$AutomationAccountName; IsMandatory=$true; IsEncrypted=$false; }
    $AssetObj = New-Object PSObject -Property $AssetProp
    $NewAssetList += $AssetObj
	
    # Validate all mandatory parameters
    Write-Output "Validating all mandatory assets"
    InlineScript 
    {
        $NewAssetList = $Using:NewAssetList
        $ErrorMessage = [string]::Empty
        
        foreach ($NewAssetData in $NewAssetList) {
            If ($NewAssetData.IsMandatory -and [string]::IsNullOrEmpty($NewAssetData.Value)) { 
                $ErrorMessage += "$($NewAssetData.Name) cannot be blank. `n" 
            }
        }
        
        # Display message
        If ([string]::IsNullOrEmpty($ErrorMessage) -eq $false) {
            throw $ErrorMessage
        }
    }
    
    # Fetch basic Azure automation variables
    $AzureCredential = Get-AutomationPSCredential -Name "AzureCredential"
    If ($AzureCredential -eq $null) 
    {
        throw "The AzureCredential asset has not been created in the Automation service."  
    }
    
    # Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureRmAccount -Credential $AzureCredential      
    $AzureSubscription = Get-AzureRmSubscription -SubscriptionName $AzureSubscriptionName | Set-AzureRmContext  
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
    }
    
    # Read automation account resource group
    Write-Output "Reading automation account's resource group name"
    try {
        $ResourceGroupName = (Get-AzureRmAutomationAccount | where AutomationAccountName -eq $AutomationAccountName).ResourceGroupName
    }
    catch {
        throw "Failed to read automation account's resource group name"
    }
    # Fetch asset list in Automation account
    Write-Output "Fetching all existing assets info"
    try {
        $AssetList = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName)
    }
    catch {
        throw "The Automation account ($AutomationAccountName) is not found."
    }
    
    Write-Output "Initiating to create/update asset(s)"
    foreach ($NewAssetData in $NewAssetList)
    {
        $AssetVariableName = $NewAssetData.Name
        $AssetValue = $NewAssetData.Value
        $IsEncrypted = $NewAssetData.IsEncrypted
		
        # Print asset name & value
        Write-Output "$AssetVariableName : $AssetValue"
        
        If ($AssetList -ne $null -and (($AssetList) | Where-Object {$_.Name -eq $AssetVariableName}) -ne $null) {
            $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetVariableName -ResourceGroupName $ResourceGroupName -Value $AssetValue -Encrypted $IsEncrypted 
            Write-Output "$AssetVariableName asset updated"
        }
        elseIf ($AssetList -ne $null) {
            $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetVariableName -Value $AssetValue -Encrypted $IsEncrypted -ResourceGroupName $ResourceGroupName
            Write-Output "$AssetVariableName asset created"
        }
    }
}