<#
.DESCRIPTION
    This runbook logons to the Virtual machine and verifies AzCopy status, if it's in progress then skips all other steps.
    This runbook verifies AzCopy status if it's completed then initiates a backup from an existing (default) backup policy and skips Failover operation. 
    This runbook verifies Snapshot status, if it's completed then initiates a failover operation of volume container groups otherwise the failover operation skipped.
    This runbook verifies above three steps, if any one of the stage is not completed then it creates an automation schedule and adding an association between a runbook and a schedule
        otherwise it removes an association between a runbook and a schedule if creates and deletes all un-wanted automation variables & shutdown the Virutal device, Virtual machine. 
    This runbook repeats the above steps until whole import process completes.  
	
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
    AutomationAccountName: The name of the Automation account name
    
.NOTES:
    Multi Factor Authentication must be disabled to execute this runbook

#>

workflow ImportData-Failover
{
    # Asset Names
    $ImportDataContainersAssetName = "Import-Containers"
    $ImportDataSVAsAssetName = "Import-SVAs"
    $ImportDataConfigCompletedSVAsAssetName = "Import-ConfigrationCompletedDevices"
    $ImportDataAzCopyInitiatedSVAsAssetName = "Import-AzCopyInitiatedSVAs"
    $ImportDataFailoverCompletedDevicesAssetName = "Import-FailoverCompletedDevices"
    $ImportDataFailoverDataAssetName = "Import-FailoverData"
    $ImportDataFailoverScheduleName = "Import-HourlySchedule"
    $ImportDataFailoverRunbookName = "ImportData-Failover"  # Do NOT CHANGE THIS VALUE
    $NewVirtualDeviceNameAssetName = "Import-NewVirtualDeviceName"
    $NewVMServiceNameAssetName = "Import-NewVMServiceName"
    $NewVMNameAssetName = "Import-NewVMName"
    
    $SLEEPTIMEOUTSMALL = 10
    $SLEEPTIMEOUT = 60
    $SLEEPTIMEOUTLARGE = 300
    
    # Fetch all Automation Variable data
    Write-Output "Fetch Assets Info"    
    $AzureCredential = Get-AutomationPSCredential -Name "AzureCredential"
    If ($AzureCredential -eq $null) 
    {
        throw "The AzureCredential asset has not been created in the Automation service."  
    }
 
    $SubscriptionName = Get-AutomationVariable –Name "AzureSubscriptionName"
    if ($SubscriptionName -eq $null)
    { 
        throw "The AzureSubscriptionName asset has not been created in the Automation service."  
    }
   
    $StorSimRegKey = Get-AutomationVariable -Name "StorSimRegKey"
    if ($StorSimRegKey -eq $null)
    { 
        throw "The StorSimRegKey asset has not been created in the Automation service."  
    }

    $ResourceName = Get-AutomationVariable –Name "ResourceName" 
    if ($ResourceName -eq $null)
    { 
        throw "The ResourceName asset has not been created in the Automation service."  
    }
    
    $AutomationAccountName = Get-AutomationVariable –Name "AutomationAccountName"
    if ($AutomationAccountName -eq $null)
    { 
        throw "The AutomationAccountName asset has not been created in the Automation service."  
    }
    
    $TargetDeviceName = Get-AutomationVariable –Name "TargetDeviceName" 
    if ($ResourceName -eq $null)
    { 
        throw "The TargetDeviceName asset has not been created in the Automation service."  
    }
 
    # New Instance Name format
    $NewVirtualDeviceName = Get-AutomationVariable –Name $NewVirtualDeviceNameAssetName
    if ($NewVirtualDeviceName -eq $null)
    {
        throw "The NewVirtualDeviceName asset has not been created in the Automation service."
    }
	
    $NewVMName = Get-AutomationVariable –Name $NewVMNameAssetName
    if ($NewVMName -eq $null)
    { 
        throw "The NewVMName asset has not been created in the Automation service."
    }
	
    $NewVMServiceName = Get-AutomationVariable –Name $NewVMServiceNameAssetName
    if ($NewVMServiceName -eq $null)
    { 
        throw "The NewVMServiceName asset has not been created in the Automation service."  
    }
    
    $VMPassword = "StorSim1"
    $VMUserName = "hcstestuser"
    $VMCredential = InlineScript
    {        
        $password = ConvertTo-SecureString $Using:VMPassword –AsPlainText –Force
        $cred = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList $Using:VMUserName, $password
        # Output of InlineScript
        $cred
    }
    If ($VMCredential -eq $null) 
    {
        throw "The VMCredential asset has not been created in the Automation service."  
    }
    
    
    # Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName
    $AzureAccount = Add-AzureRmAccount -Credential $AzureCredential
    $AzureSubscription = Get-AzureRmSubscription –SubscriptionName $SubscriptionName | Select-AzureRmSubscription
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
    }
    
    # Connect to StorSimple Resource
    Write-Output "Connecting to StorSimple Resource $ResourceName"
    $StorSimpleResource = Select-AzureStorSimpleResource -ResourceName $ResourceName -RegistrationKey $StorSimRegKey
    If ($StorSimpleResource -eq $null)
    {
        throw "Unable to connect to the StorSimple resource $ResourceName"
    }
    
    # Read automation account resource group
    Write-Output "Reading automation account's resource group name"
    try {
        $ResourceGroupName = (Get-AzureRmAutomationAccount | where AutomationAccountName -eq $AutomationAccountName).ResourceGroupName
    }
    catch [Exception] {
        Write-Output $_.Exception.Message
        throw "Failed to read automation account's resource group"
    }
    
    $TargetDevice = Get-AzureStorSimpleDevice -DeviceName $TargetDeviceName
    If (($TargetDevice -eq $null) -or ($TargetDevice.Status -ne "Online"))
    {
        throw "Target device ($TargetDeviceName) does not exist or in Offline state"
    }
    
    $ImportDataAzCopyInitiatedSVAs = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataAzCopyInitiatedSVAsAssetName -ErrorAction:SilentlyContinue).Value
    if ([string]::IsNullOrEmpty($ImportDataAzCopyInitiatedSVAs) -eq $true)
    {
        Unregister-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -RunbookName $ImportDataFailoverRunbookName -ScheduleName $ImportDataFailoverScheduleName -Force -ErrorAction:SilentlyContinue
        throw "All Virtual devices failover either completed or AzCopy does not started"
    }
    
    # Set Devices list for Failover
    $VirDeviceList = $ImportDataAzCopyInitiatedSVAs.Replace(",delimiter", '').Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
    
    $FailoverCompletedDeviceList = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverCompletedDevicesAssetName -ErrorAction:SilentlyContinue).Value
    If ($FailoverCompletedDeviceList -ne $null)
    {
        $FilteredFailoverCompletedDevices = InlineScript
        {
            $list = @()
            $VirDeviceList = $Using:VirDeviceList
            $FailoverCompletedDeviceList = $Using:FailoverCompletedDeviceList
            foreach($DeviceName in $VirDeviceList) {
                If ($FailoverCompletedDeviceList.Contains($DeviceName) -eq $false) {
                    $list += $DeviceName
                }
            }
            # Output of InlineScript
            $list
        }
        
        $VirDeviceList = $FilteredFailoverCompletedDevices
    }
    
    Write-Output "Attempting to initiate Failover process"
    $IsFailoverInProgress = $true
    $FailoverSuccessVirDevices = @()
    $VirDeviceImport = @()
    
    # Read Virtual device Import data from assets if exists
    $assetObj = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverDataAssetName -ErrorAction:SilentlyContinue)
    If ($assetObj -ne $null) {
        $VirDeviceImport = $assetObj.Value
    }    
    
    $VirtualDevices = @()
    if($VirDeviceImport -eq $null -or $VirDeviceImport.Count -eq 0) {
        # Assign all virtual device list
        $VirtualDevices = $VirDeviceList
    }
    else {
        # Assign only pending virtual device list
        $PendingVirtualDevices = @()
        foreach ($VirDeviceImportData in $VirDeviceImport) {
            If ($VirDeviceImportData.FailoverJobStatus -eq $false) {
                $PendingVirtualDevices += $VirDeviceImportData.VirDeviceName
            }
        }
        
        $VirtualDevices = $PendingVirtualDevices.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
    }
    
    $VirtualDevicesByCommaSeparated = $VirtualDevices -Join ","
    Write-Output "Virtual devices: $VirtualDevicesByCommaSeparated"
    
    foreach ($VirDeviceName in $VirtualDevices)
    {
        Write-Output "`nVirtual Device name : $VirDeviceName"
        If (($VirDeviceImport.Count -eq 0) -or (($VirDeviceImport | Where-Object { $_.VirDeviceName -eq $VirDeviceName }) -eq $null)) {
            # Add New Device ($VirDeviceName)
            $DeviceProp = @{ VirDeviceName=$VirDeviceName; AzureVM=$null; VMWinRMUri=$null; VolumeContainer=$null; VolumeContainerName=$null; VolumeList=$null; DriveLetters=$null; AzCopyJobStatus=$false; BackupJobStatus=$false; BackupJobIds=$null; FailoverJobStatus=$false; FailoverJobId=$null }
            $NewDeviceObj = New-Object PSObject -Property $DeviceProp
            $VirDeviceImport += $NewDeviceObj
            $CurrentDeviceImportData = $NewDeviceObj
        }
        else {
            # Device ($VirDeviceName) already added
            $CurrentDeviceImportData = ($VirDeviceImport | Where-Object { $_.VirDeviceName -eq $VirDeviceName })
        }
        
        If ($CurrentDeviceImportData -eq $null) {
            throw " Unable to fetch Current Virtual device info"
        }
        
        Write-Output " Initiated to check whether Virtual device & Virtual machine are online or not"
        $Device = Get-AzureStorSimpleDevice -DeviceName $VirDeviceName
        If ($Device -eq $null) {
            throw "  Virtual Device ($VirDeviceName) does not exist"
        }
        elseIf ($Device.Status -ne "Online") {
            throw "  Virtual Device ($VirDeviceName) is not online"
        }
         
        # Set VMServiceName
        $VMServiceName = $VirDeviceName.Replace($NewVirtualDeviceName, $NewVMServiceName)
        $VMName = $VirDeviceName.Replace($NewVirtualDeviceName, $NewVMName)
        $AzureVM = (Get-AzureVM -ServiceName $VMServiceName -Name $VMName) #(Get-AzureVM -ServiceName $VMServiceName | Where Name -ne $VirDeviceName) | Select -First 1
        If ($AzureVM -eq $null) {
            throw "  VM ($VMName) does not exist in Service ($VirDeviceName)"
        }
        elseIf ($AzureVM.Status -ne "ReadyRole") {
            throw "  VM ($VMName) is not in ready state"
        }
        
        # Set VMName
        $VMName = $AzureVM.Name
        
        # Connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
        Write-Output " Fetching Virtual machine ($VMName) windows remote management uri"
        $VMWinRMUri = InlineScript 
        {
            # Get the Azure certificate for remoting into this VM
            $winRMCert = (Get-AzureVM -ServiceName $Using:VMServiceName -Name $Using:VMName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint   
            $AzureX509cert = Get-AzureCertificate -ServiceName $Using:VMServiceName -Thumbprint $winRMCert -ThumbprintAlgorithm sha1
	
            # Add the VM certificate into the LocalMachine
            if ((Test-Path Cert:\LocalMachine\Root\$winRMCert) -eq $false)
            {
                # "VM certificate is not in local machine certificate store - adding it"
                $certByteArray = [System.Convert]::fromBase64String($AzureX509cert.Data)
                $CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList (,$certByteArray)
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
                $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                $store.Add($CertToImport)
                $store.Close()
            }
			
            # Return the WinRMUri so that it can be used to connect to the VM
            Get-AzureWinRMUri -ServiceName $Using:VMServiceName -Name $Using:VMName 
        }
        If ($VMWinRMUri -eq $null) {
            throw "  Unable to fetch Virtual machine ($VMName) windows remote management uri"
        }
        
        If ($CurrentDeviceImportData.VolumeContainer -eq $null) {
            Write-Output " Fetching Volume containers on Device ($VirDeviceName)"
            $VolumeContainer = (Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirDeviceName) | Select -First 1
        }
        else {
            $VolumeContainer = $CurrentDeviceImportData.VolumeContainer
            $VolContName= $CurrentDeviceImportData.VolumeContainerName 
        }
        If ($VolumeContainer -eq $null -or $VolumeContainer.Count -eq 0) {
            throw "  No Volume containers found on Device ($VirDeviceName)"
            #Write-Output "No Volume containers are available. It might be device failover completed"
        }
        elseIf ($VolumeContainer -ne $null -and $VolumeContainer.VolumeCount -eq 0) {
            throw "  No Volumes found (Virtual device : $VirDeviceName    Volume container : $VolumeContainerName)"
        }
        
        If ($CurrentDeviceImportData.VolumeContainer -eq $null) {
            InlineScript
            {
                $AzureVM = $Using:AzureVM
                $VMWinRMUri = $Using:VMWinRMUri
                $VolumeContainer = $Using:VolumeContainer
                $CurrentDeviceImportData = $Using:CurrentDeviceImportData
                
                # Set VolumeContainer Name
                $VolContName = $VolumeContainer.Name
                
                # Update current device details
                $CurrentDeviceImportData.AzureVM = $AzureVM
                $CurrentDeviceImportData.VMWinRMUri = $VMWinRMUri
                $CurrentDeviceImportData.VolumeContainer = $VolumeContainer
                $CurrentDeviceImportData.VolumeContainerName = $VolContName
            }
        }
        
        If ($CurrentDeviceImportData.VolumeContainerName -ne $null -and $CurrentDeviceImportData.VolumeContainerName.Length -gt 0) {
            $VolumeContainerName = $CurrentDeviceImportData.VolumeContainerName
            $VolumeContainer = $CurrentDeviceImportData.VolumeContainer
        }
        
        If ($VolumeContainerName -eq $null -or $VolumeContainerName.Length -eq 0) {
            throw "  No Volume Container available on Virtual device ($VirDeviceName)"
        }
        
        # Fetch Volumes data
        If ($CurrentDeviceImportData.VolumeList -eq $null) {
            Write-Output " Fetching Volumes in Volume container ($VolumeContainerName)"
            $VolumeList = InlineScript 
            {
                $CurrentDeviceImportData = $Using:CurrentDeviceImportData
                $VirDeviceName = $using:VirDeviceName
                $VolumeContainerName = $Using:VolumeContainerName
                $CurrentDeviceImportData.VolumeList = (Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirDeviceName -VolumeContainerName $VolumeContainerName | Get-AzureStorSimpleDeviceVolume -DeviceName $VirDeviceName)
                $CurrentDeviceImportData.VolumeList
            }
        }
        else {
            $VolumeList = $CurrentDeviceImportData.VolumeList
        }
        If ($VolumeList -eq $null) {
            throw "  No Volumes available in Volume Container ($VolumeContainerName) on Virtual device ($VirDeviceName)"
        }
        
        # Read Volume Names from object
        if ($VolumeList.Name.Count -gt 1) {
            $Volumes = (($VolumeList.Name | Sort) -Join ",").Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
        }
        else {
            $Volumes = ($VolumeList.Name)
        }
        
        # Fetch "StroSimpleDisk" Labeled drives from AzureVM
        If ($CurrentDeviceImportData.DriveLetters -eq $null) 
        {
            Write-Output " Fetching Drive letters"
            $RetryCount = 0
            while ($RetryCount -lt 2)
            {
                try
                {
                    $DriveLetters = InlineScript
                    {
                        Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock {
                            ((Get-Volume | where FileSystemLabel -match "STORSIMPLE*" | Select DriveLetter).DriveLetter | Sort) -Join ","
                        }
                    }
                } catch [Exception] {
                    Write-Output $_.Exception.GetType().FullName;
                    Write-Output $_.Exception.Message;
                }
                
                if ($DriveLetters -eq $null -or $DriveLetters.Length -eq 0) {
                    if ($RetryCount -eq 0) {
                        Write-Output "  Retrying for drive letters of the mounted StorSimple volumes"
                    }
                    else {
                        Write-Output "  Unable to read the StorSimple drives"
                    }
                    
                    # Sleep for 10 seconds before trying again
                    Start-Sleep -s $SLEEPTIMEOUTSMALL
                    $RetryCount += 1
                }
                else {
                    $RetryCount = 2 # To stop the iteration; similar as 'break' statement
                }
            }
            
            If ($DriveLetters -eq $null -or $DriveLetters -eq "") {
                throw "  No StorSimple drives found in Virtual machine ($VMName)"
            }
        
            Write-Output "  Drives: $DriveLetters"
            
            InlineScript {
                $CurrentDeviceImportData =$Using:CurrentDeviceImportData
                $DriveLetters = $Using:DriveLetters
                $CurrentDeviceImportData.DriveLetters = $DriveLetters 
            }
        }
        else {
            $DriveLetters = $CurrentDeviceImportData.DriveLetters.Value
        }
        
        # Read Driveletters from object
        $Drives = $DriveLetters.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
        
        # Check whether Volumes count & Drives count same or not
        If ($Volumes.Count -ne $Drives.Count) {
            Write-Output "`n  Drives list: $DriveLetters"
            Write-Output "  Volumes list: $($Volumes -join ',')"
            throw "  Volumes and Drives are mismatched on Virtual device ($VirDeviceName) and Virtual machine ($VMName)"
        }

        # Create AzCopyStatus Object
        $AzCpStatus = 0
        $AzCopyDriveState = @()
        if($CurrentDeviceImportData.AzCopyJobStatus -eq $true) {
            Write-Output " AzCopy execution already completed"
            $AzCpStatus = 2
        }
        else {
            Write-Output "`n Initiated to check whether AzCopy process completed or not"
            
            for ($propIndex=0; $propIndex -lt $Volumes.Count; $propIndex++)
            {
                If ($Volumes.Count -eq 1) { 
                    $VolName = $Volumes
                }
                else {
                    $VolName = $Volumes[$propIndex]
                }
                $Prop = @{ VolumeName=$VolName; Drive=$Drives[$propIndex]; Status=$AzCpStatus }
                $NewObj = New-Object PSObject -Property $Prop
                $AzCopyDriveState += $NewObj
            }
        }
        
        for ($index=0; (($CurrentDeviceImportData.AzCopyJobStatus -ne $true) -and ($index -lt $AzCopyDriveState.Count)); $index++)
        {
            # Fetch Current AzCopy Volume object and update status
            $CurrentAzCopyDriveState = $AzCopyDriveState[$index]
            
            $drivename = $AzCopyDriveState[$index].Drive
            $VolName = $AzCopyDriveState[$index].VolumeName 
            $DrvName = $AzCopyDriveState[$index].Drive
            $LogFilePath = "C:\Users\Public\Documents\AzCopy-" + $VolName + "-" + $DrvName + ".log"
            
            $AzCopyProgressState=InlineScript 
            {
                Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock {
                    param([string]$LogFilePath)
                    
                    If (Test-Path $LogFilePath) {
                        # AzCopy log file available
                        $LogStatus = 1
                        
                        $StartDate = (Get-ItemProperty -Path $LogFilePath).LastWriteTime
                        $EndDate = Get-Date
                        $LastWriteTimeInHours = (NEW-TIMESPAN -Start $StartDate -End $EndDate).Hours
                        $LastWriteTimeInMinutes = (NEW-TIMESPAN -Start $StartDate -End $EndDate).Minutes
                        
                        If ($LastWriteTimeInHours -ge 1 -or $LastWriteTimeInMinutes -ge 1)
                        {
                            $TransferSummaryTag = "Transfer summary:"    # DONOT CHANGE THIS VALUE
                            $SummaryContent = Select-String $LogFilePath -pattern $TransferSummaryTag -AllMatches
                            If (($SummaryContent -ne $null -and $SummaryContent.ToString().Contains($TransferSummaryTag))) {
                                # Log file & Summary info found in the log file
                                $LogStatus = 2
                            }
                            else {
                                # Log file found but summary not available.. May have a chance of AzCopy is still in progress..
                                $LogStatus = 3
                            }
                        }
                        else {
                            # AzCopy still in progress
                            $LogStatus = 4
                        }
                    }
                    else {
                        # AzCopy log file not found in specified location
                        $LogStatus = 5
                    }
                    # Output of InlineScript
                    $LogStatus
                } -Argumentlist $Using:LogFilePath
            }
            
            # Write-Output "AzCopy Status: $AzCopyProgressState"$DriverStatus = "AzCopy process in progress"
            $DriverStatus = "In progress"
            If ($AzCopyProgressState -eq 2) {
                $DriverStatus = "Completed"
            }
            
            Write-Output " Drive: $drivename `n Status: $DriverStatus `n Log file: $LogFilePath `n"
                        
            InlineScript
            {
                # Update Current Volume AzCopy state
                $CurrentAzCopyDriveState = $Using:CurrentAzCopyDriveState
                $AzCopyProgressState = $Using:AzCopyProgressState
                $CurrentAzCopyDriveState.Status = $AzCopyProgressState
            }
        }
        
        # Update AzCopyJobStatus for VirtualDevice if AzCopy completes for all Drives
        If ($CurrentDeviceImportData.AzCopyJobStatus -eq $false)
        {
            InlineScript 
            {
                $AzCopyDriveState = $Using:AzCopyDriveState
                $CurrentDeviceImportData = $Using:CurrentDeviceImportData
                
                $PendingAzCopyDriveList = ($AzCopyDriveState | Where-Object {$_.Status -ne 2})
                $IsAzCopyCompleted = ($PendingAzCopyDriveList -eq $null)
                
                If ($CurrentDeviceImportData.AzCopyJobStatus -eq $false -and $IsAzCopyCompleted -eq $true) {
                    $CurrentDeviceImportData.AzCopyJobStatus = $true
                    Write-Output " AzCopy process is completed"
                }
            }
        }
        else {
            Write-Output "AzCopy process still running..."
        }
        
        # Initiate Volumes Backup (Cloud snapshot) & Virtual Device Failover
        InlineScript
        {
            $AutomationAccountName = $Using:AutomationAccountName
            $ResourceGroupName = $Using:ResourceGroupName
            $ImportDataFailoverCompletedDevicesAssetName = $Using:ImportDataFailoverCompletedDevicesAssetName
            $TargetDeviceName = $Using:TargetDeviceName
            $VirDeviceName = $Using:VirDeviceName
            $AzCopyDriveState = $Using:AzCopyDriveState
            $VirDeviceImport = $Using:VirDeviceImport
            $VolumeContainerName = $Using:VolumeContainerName
            $Volumes = $Using:Volumes
            $CurrentDeviceImportData = $Using:CurrentDeviceImportData
            $FailoverSuccessVirDevices = $Using:FailoverSuccessVirDevices                
            
            $SLEEPTIMEOUTSMALL = $Using:SLEEPTIMEOUTSMALL
            $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
            $SLEEPTIMEOUTLARGE = $Using:SLEEPTIMEOUTLARGE
            
            $CurrentTime = Get-Date
            $BackupPolicies = @()
            
            $IsBackupJobCompleted = $CurrentDeviceImportData.BackupJobStatus
            
            If ($CurrentDeviceImportData.AzCopyJobStatus -eq $true -and $CurrentDeviceImportData.BackupJobStatus -eq $true) {
                Write-Output " Backup jobs already completed"
            }
            elseIf($CurrentDeviceImportData.AzCopyJobStatus -eq $true -and $IsBackupJobCompleted -eq $false)
            {
                If ($CurrentDeviceImportData.BackupJobIds -eq $null) 
                {
                    Write-Output " Initiating to trigger Snapshot"
                    Write-Output "  Fetching default backup policies"
                    # Fetch Volume Backup policy Info
                    foreach ($VolumeName in $Volumes)
                    {
                        $BackupPolicyName = $VolumeName + "_Default"
                        $policy = Get-AzureStorSimpleDeviceBackupPolicy -DeviceName $VirDeviceName -BackupPolicyName $BackupPolicyName
                        If ($policy -eq $null) {
                            throw "  No Default backup policy available for Volume ($VolumeName) on Device ($VirDeviceName)"
                        }
                        else {
                            $BackupPolicies += $policy
                        }
                    }
                    If ($BackupPolicies -eq $null -or $BackupPolicies.Count -eq 0) {
                        throw "  No Default backup policies are available"
                    }
                    
                    # Start the BackupJob
                    Write-Output " Initiate Backup for all Volumes in Volume Container ($VolumeContainerName)"
                    foreach ($BackupPolicy in $BackupPolicies)
                    {
                        $backupjob = Start-AzureStorSimpleDeviceBackupJob -DeviceName $VirDeviceName -BackupPolicyId  $BackupPolicy.InstanceId -BackupType CloudSnapshot
                        If ($backupjob -eq $null) {
                            throw "  Unable to take a backup for Volume $($BackupPolicy.Name)"
                        }
                    }
                    
                    $jobIDs = $null                    
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($jobIDs -eq $null)
                    {
                        If ($elapsed.Elapsed.Minutes -gt 20) {
                            throw "  Timeout for getting the backup job id exceeded"
                        }
                        
                        # Sleep for 5 secs
                        Start-Sleep -s $SLEEPTIMEOUTSMALL
                                        
                        $jobIDs = (Get-AzureStorSimpleJob -DeviceName $VirDeviceName -Status:Running -Type ManualBackup -From $CurrentTime).InstanceId
                        
                        $jobIDsReady = $true
                        foreach ($ID in $jobIDs)
                        {
                            If ($ID -eq $null) {
                                $jobIDsReady = $false
                                break
                            }
                        }
                        
                        If ($jobIDsReady -ne $true) {
                            continue
                        }
                        
                        If ($jobIDs.Count -eq $BackupPolicies.Count) {
                            # Set Backup JobIDs in current device object
                            $CurrentDeviceImportData.BackupJobIds = $jobIDs
                            break
                        }
                    }
                    
                    # Delay for each backup job
                    Start-Sleep -s $SLEEPTIMEOUTLARGE # $SLEEPTIMEOUT
                }
                else {
                    Write-Output " Backup jobs already initiated, check whether it is completed or not..."
                    $jobIDs = $CurrentDeviceImportData.BackupJobIds
                }
                
                If ($BackupPolicies.Count -gt 0 -and $jobIDs -ne $null -and $jobIDs.Count -gt $BackupPolicies.Count) {
                    $CurrentDeviceImportData.BackupJobIds = $jobIDs
                    Write-Output "  Warning: Jobs are more than Backup policies"
                }
                If ($BackupPolicies.Count -gt 0 -and $jobIDs.Count -ne $BackupPolicies.Count) {
                    $policiesCount = $BackupPolicies.Count
                    Write-Output "`n  Backup policies count & Jobs count are mismatched"
                    Write-Output "  Total Backup policies: ($policiesCount)"
                    Write-Output "  Jobs $($jobIDs.Count) list: "
                    $jobIDs
                }
                
                #Write-Output "Waiting for backups to finish"
                $BackupJobState = @()
                foreach ($id in $jobIDs)
                {
                    $BackupJobProp = @{ JobID=$id; IsRunning=$true; IsSuccess=$true }
                    $NewBackupJobObj = New-Object PSObject -Property $BackupJobProp
                    $BackupJobState += $NewBackupJobObj
                    $CurrentBackupJobState = $NewBackupJobObj
                    
                    # Check BackupJob Status
                    $status = Get-AzureStorSimpleJob -InstanceId $id
                    Start-Sleep -s $SLEEPTIMEOUTSMALL
                    If ($status.Status -ne "Running") {
                        $CurrentBackupJobState.IsRunning = $false
                        If ( $status.Status -ne "Completed") {
                            $CurrentBackupJobState.IsSuccess = $false
                        }
                    }
                }
                
                $IsBackupJobsRunning = (($BackupJobState | Where-Object {$_.IsRunning -eq $true}) -ne $null)
                $checkForSuccess = (($BackupJobState | Where-Object {$_.IsSuccess -eq $false}) -eq $null)
                If($IsBackupJobsRunning) {
                    Write-Output "  Backup jobs are still running..."
                }
                elseIf ($checkForSuccess) {
                    Write-Output " Backup jobs completed successfully on Device ($VirDeviceName)"
                    
                    # Update BackupJobs status for VirtualDevice
                    $CurrentDeviceImportData.BackupJobStatus = $true
                }
                else {
                    throw " Backup jobs unsuccessful on Device ($VirDeviceName)"
                }
            }
            
            # Attempting to initiate Failover process
            If ($CurrentDeviceImportData.BackupJobStatus -eq $true -and $CurrentDeviceImportData.FailoverJobStatus -eq $true) {
                Write-Output " Device failover already completed"
            }
            elseIf($CurrentDeviceImportData.BackupJobStatus -eq $true -and $CurrentDeviceImportData.FailoverJobStatus -eq $false)
            {
                If ($CurrentDeviceImportData.FailoverJobId -eq $null)
                {
                    # Attempting to initiate Device Failover on Volume Container ($VolumeContainerName)                        
                    Write-Output " Initating to trigger Device failover" 
                    $jobID = (Get-AzureStorSimpleFailoverVolumeContainers -DeviceName $VirDeviceName) | Where-Object {$_.IsDCGroupEligibleForDR -eq $True -and $_.DCGroup.Name -match $CurrentDeviceImportData.VolumeContainerName} |  Start-AzureStorSimpleDeviceFailoverJob -DeviceName $VirDeviceName -TargetDeviceName  $TargetDeviceName  -Force 
                    
                    If ($jobID -eq $null) {
                        throw "  Device failover can not be initiated on Device ($DeviceName)"
                    }
                    
                    $CurrentDeviceImportData.FailoverJobId = $jobID
                    
                    # Delay for each Device failover job initiate-time
                    Start-Sleep -s $SLEEPTIMEOUTLARGE # $SLEEPTIMEOUT
                }
                else {
                    Write-Output " Device failover already initaited"
                    $jobID = $CurrentDeviceImportData.FailoverJobId
                }
                
                #wait until the failover is complete
                $checkForSuccess=$true
                $IsFailoverJobRunning=$true
                # Check FailoverJob Status
                $status = Get-AzureStorSimpleJob -InstanceId $jobID 
                Start-Sleep -s $SLEEPTIMEOUTSMALL
                if ( $status.Status -ne "Running" ) {
                    $IsFailoverJobRunning = $false
                    if ( $status.Status -ne "Completed") {
                        $checkForSuccess=$false
                    }
                }
                
                If ($IsFailoverJobRunning) {
                    Write-Output "  Device failover job is still running..."
                }
                elseIf ($checkForSuccess) {
                    Write-Output "  Device failover completed successfully"
                    
                    # Update FailoverJob status for VirtualDevice
                    $CurrentDeviceImportData.FailoverJobStatus = $true
                    $FailoverSuccessVirDevices += $VirDeviceName
                    
                    # Fetch Import-FailoverCompletedDevices asset variable
                    $asset = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverCompletedDevicesAssetName -ErrorAction:SilentlyContinue)               
                    If ($asset -ne $null) {
                        # Set asset Import-FailoverCompletedDevices value 
                        $AssetVal =  $asset.Value -replace ",delimiter", ""
                        $AssetVal = $AssetVal + "," + $VirDeviceName + ",delimiter"
                        $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverCompletedDevicesAssetName -Encrypted $false -Value $AssetVal
                    }
                    else {
                        # Create new Import-FailoverCompletedDevices asset
                        $AssetVal = ($VirDeviceName + ",delimiter")
                        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverCompletedDevicesAssetName -Value $AssetVal -Encrypted $false
                    }
					
                    # Add all devices & VMs which are to be Turn on when the process starts & Turn off in the end 
                    $SystemList = @()
                    $SVAProp = @{ SystemType="Virtual device"; Name=$VirDeviceName; ServiceName=$VirDeviceName; }
                    $SVAObj = New-Object PSObject -Property $SVAProp
                    $SystemList += $SVAObj
                    $VMProp = @{ SystemType="Virtual machine"; Name=$Using:VMName; ServiceName=$Using:VMServiceName; }
                    $VMObj = New-Object PSObject -Property $VMProp
                    $SystemList += $VMObj
					
                    Write-Output "Attempting to shutdown the Virtual device & Virtual machine"
                    foreach ($SystemInfo in $SystemList)
                    {
                        $RetryCount = 0
                        while ($RetryCount -lt 2)
                        {   
                            $Result = Stop-AzureVM -ServiceName $ServiceName -Name $Name -Force
                            if ($Result.OperationStatus -eq "Succeeded")
                            {
                                Write-Output "  $SystemType ($Name) succcessfully turned off"   
                                break
                            }
                            else
                            {
                                if ($RetryCount -eq 0) {
                                    Write-Output "  Retrying for $SystemType ($Name) shutdown"
                                }
                                else {
                                    Write-Output "  Unable to stop the $SystemType ($Name)"
                                }
                                             
                                Start-Sleep -s $SLEEPTIMEOUTSMALL
                                $RetryCount += 1   
                            }
                        }
                    }
                }
                else {
                    throw " Device ($VirDeviceName) failover unsuccessful"
                }
            }
        }
    }
    
    $InProgressDevices = @()
    $FailoverCompletedDevices = @()
	foreach ($DeviceData in $VirDeviceImport) {
        If ($DeviceData.FailoverJobStatus) {
            $FailoverCompletedDevices += $DeviceData.VirDeviceName
       }
        else {
            $InProgressDevices += $DeviceData.VirDeviceName
        }
    }
    
    # Check whether all Devices failover completed or not
    $TotalDeviceCount = $VirDeviceImport.Count
    $IsFailoverInProgress =  ($FailoverCompletedDevices.Count) -ne ($VirDeviceImport.Count)
    
    Write-Output "`n`n Failover status: "
    Write-Output "  Total Devices count: $($VirDeviceImport.Count)"
    Write-Output "  Total Failover completed devices count: $($FailoverCompletedDevices.Count)"
    Write-Output "  Total Failover In-progress devices count: $($InProgressDevices.Count)"
    Write-output "  Failover In-progress Devices: $($InProgressDevices -Join ',')"
    Write-output "  Failover Completed Devices: $($FailoverCompletedDevices -Join ',')"
    If ($IsFailoverInProgress)
    {
        # Gets Automation runbooks and associated schedules.
        $asset = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverDataAssetName -ErrorAction:SilentlyContinue)
        If ($asset -ne $null) {
            Write-Output "Update an automation variable for Import-Data object"
            # Set asset Import-FailoverDataAssetName value
            $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverDataAssetName -Encrypted $false -Value $VirDeviceImport
        }
        else {
            Write-Output "Create a new automation variable for Import-Data object"
            # Create new Import-FailoverDataAssetName asset
            $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataFailoverDataAssetName -Value $VirDeviceImport -Encrypted $false
        }

        # Gets an Automation schedule info
        Write-Output "Fetch schedule info"
        $ScheduleInfo = Get-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverScheduleName -ResourceGroupName $ResourceGroupName -ErrorAction:SilentlyContinue
		
        if ($ScheduleInfo -eq $null) {
            Write-Output "  Attempting to create an automation schedule"
            $StartTime = (Get-Date).AddHours(1)
            
            # Create Import-HourlySchedule
            $NewScheudleInfo = New-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverScheduleName -StartTime $StartTime -HourInterval 1 -ResourceGroupName $ResourceGroupName -ErrorAction:SilentlyContinue
            if ($NewScheudleInfo -eq $null) {
                throw "Unable to create an automation schedule"
            }
			
            $ScheduleInfo = $NewScheudleInfo
            Write-Output "  Automation schedule ($ImportDataFailoverScheduleName) created scuccessfully"
        }
        else {
            Write-Output "  Automation schedule ($ImportDataFailoverScheduleName) already created"
        }
		
       $IsSchedulerEnabled = $ScheduleInfo.IsEnabled
       if ($ScheduleInfo -ne $null -and $IsSchedulerEnabled -eq $false) {
            Write-Output "  Attempting to enable automation schedule ($ImportDataFailoverScheduleName)"
            $ScheduleInfo = Set-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverScheduleName -IsEnabled $true -ResourceGroupName $ResourceGroupName
        }
        else {
            Write-Output "  Automation schedule already enabled"
        }
		
        $ScheduledRunbookInfo = (Get-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -ScheduleName $ImportDataFailoverScheduleName -RunbookName $ImportDataFailoverRunbookName -ErrorAction:SilentlyContinue)
        if ($ScheduledRunbookInfo -eq $null) {
            Write-Output "  Attempting to add an association between a runbook and a schedule"			
            $RegisterRunbook = Register-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverRunbookName -ScheduleName $ImportDataFailoverScheduleName -ResourceGroupName $ResourceGroupName
        }
        else {
            Write-Output "  An assocation between a runbook and a schedule already added"
        }
        
        Write-Output "`n`nFailover process still in progress..."
    }
    else {
        Write-Output "Attempting to remove automation schedule"
        
        # Un-register Runbook from schedule
        Write-Output "  Removes an association between a runbook and a schedule" 
        $UnregisterRunbook = Unregister-AzureRmAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -RunbookName $ImportDataFailoverRunbookName -ScheduleName $ImportDataFailoverScheduleName -Force -ErrorAction:SilentlyContinue

        Write-Output "  Deletes an automation schedule"
        $RemoveSchedule = Remove-AzureRmAutomationSchedule -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverScheduleName -ResourceGroupName $ResourceGroupName -Force -ErrorAction:SilentlyContinue
		
        # Delete all un wanted assets
        Write-Output "  Initiating to delete un-wanted automation variables"
        $UnWantedAssetList = @( $ImportDataContainersAssetName, $ImportDataSVAsAssetName, $ImportDataConfigCompletedSVAsAssetName, $ImportDataAzCopyInitiatedSVAsAssetName, $ImportDataFailoverCompletedDevicesAssetName, $ImportDataFailoverDataAssetName, $NewVirtualDeviceNameAssetName, $NewVMServiceNameAssetName, $NewVMNameAssetName )
        foreach ($AssetName in $UnWantedAssetList) {
            Write-Output "  Deletes $AssetName automation variable"
            Remove-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -Name $AssetName -Force -ResourceGroupName $ResourceGroupName -ErrorAction:SilentlyContinue
        }
        
        Write-Output "`n`n All Virtual Devices failover successfully completed"
    }
}
