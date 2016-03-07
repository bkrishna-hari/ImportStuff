workflow ImportData-Failover
{
    # Asset Names    
    $ImportDataAzCopyInitiatedSVAsAssetName = "ImportData-AzCopyInitiatedSVAs"
    $ImportDataFailoverCompletedDevicesAssetName = "ImportData-FailoverCompletedDevices"
    $ImportDataFailoverDataAssetName = "ImportData-FailoverData"
    $ImportDataFailoverScheduleName = "Import-FailoverHourlySchedule"
    $ImportDataFailoverRunbookName = "ImportData-Failover"
    
    
    #New Instance Name format
    $NewVirtualDeviceName = "importsva"
    $NewVMServiceName = "importvmservice"
    $NewVMName = "importvm"
    
    $SLEEPTIMEOUT = 60
    $SLEEPTIMEOUTSMALL = 10
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
    
    $StorSimRegKey = Get-AutomationVariable -Name "ImportData-StorSimRegKey"
    if ($StorSimRegKey -eq $null) 
    { 
        throw "The StorSimRegKey asset has not been created in the Automation service."  
    }

    $ResourceName = Get-AutomationVariable –Name "ImportData-ResourceName" 
    if ($ResourceName -eq $null) 
    { 
        throw "The ResourceName asset has not been created in the Automation service."  
    }
    
    $AutomationAccountName = Get-AutomationVariable –Name "ImportData-AutomationAccountName"
    if ($AutomationAccountName -eq $null) 
    { 
        throw "The AutomationAccountName asset has not been created in the Automation service."  
    }
    
    $TargetDeviceName = Get-AutomationVariable –Name "ImportData-TargetDeviceName" 
    if ($ResourceName -eq $null) 
    { 
        throw "The TargetDeviceName asset has not been created in the Automation service."  
    }
    
    $VMPassword = "StorSim1"
    $VMUserName = "hcstestuser"
    $VMCredential = InlineScript
    {        
        $password = ConvertTo-SecureString $Using:VMPassword –AsPlainText –Force
        $cred = New-Object -Typename System.Management.Automation.PSCredential -ArgumentList $Using:VMUserName, $password
        # Output for InlineScript
        $cred
    }
    If ($VMCredential -eq $null) 
    {
        throw "The VMCredential asset has not been created in the Automation service."  
    }
    
    
    #Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName          
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
    }
    
    #Connect to StorSimple Resource
    Write-Output "Connecting to StorSimple Resource $ResourceName"
    $StorSimpleResource = Select-AzureStorSimpleResource -ResourceName $ResourceName -RegistrationKey $StorSimRegKey
    If ($StorSimpleResource -eq $null)
    {
        throw "Unable to connect to the StorSimple resource $ResourceName"
    }
    
    $TargetDevice = Get-AzureStorSimpleDevice -DeviceName $TargetDeviceName
    If (($TargetDevice -eq $null) -or ($TargetDevice.Status -ne "Online"))
    {
        throw "Target device $TargetDeviceName does not exist or in Offline"
    }
    
    <#$ImportDataAzCopyInitiatedSVAs = Get-AutomationVariable –Name $ImportDataAzCopyInitiatedSVAsAssetName
    If ($ImportDataAzCopyInitiatedSVAs -eq $null)
    {
        throw "No Devices are available to initiate failover"
    }
    
    Write-Output "Fetching list of SVAs"
    $VirDeviceList = $ImportDataAzCopyInitiatedSVAs.Replace(",delimiter", '').Split(',')    
    If (($VirDeviceList -eq $null) -or ($VirDeviceList.Count -eq 0))
    {
        throw "No Virtual Devices avilable"
    }#>
    
    <## Fetch all automation Assets
    $VirDeviceList = $null
    $FailoverCompletedDeviceList = $null
    $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)
    
    # Fetch AzCopyInitiatedDeviceList
    If (($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}) -ne $null) 
    {
        $VirDeviceList = ($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}).Value.Replace(",delimiter", '').Split(',')
    }
    
    If ($VirDeviceList -eq $null -or $VirDeviceList.Count -eq 0)
    {
        throw "Either all Virtual devices failover completed or AzCopy cannot start"
    }
    
    # Fetch Failover completed Devices
    If (($AssetList | Where-Object {$_.Name -match $ImportDataFailoverCompletedDevicesAssetName}) -eq $null) 
    {
        $FailoverCompletedDeviceList = ($AssetList | Where-Object {$_.Name -match $ImportDataFailoverCompletedDevicesAssetName}).Value.Replace(",delimiter", '').Split(',')
    }#>
    
    $ImportDataAzCopyInitiatedSVAs = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataAzCopyInitiatedSVAsAssetName -ErrorAction:SilentlyContinue).Value
    If ($ImportDataAzCopyInitiatedSVAs -eq $null -or $ImportDataAzCopyInitiatedSVAs.Length -eq 0)
    {
        throw "Either all Virtual devices failover completed or AzCopy cannot start"
    }
    
    # Set Devices list for Failover
    $VirDeviceList = $ImportDataAzCopyInitiatedSVAs.Replace(",delimiter", '').Split(',')
    
    $FailoverCompletedDeviceList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverCompletedDevicesAssetName -ErrorAction:SilentlyContinue).Value
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
            #Output for InlineScript
            $list
        }
        
        $VirDeviceList = $FilteredFailoverCompletedDevices
    }
    
    Write-Output "Attempting to initiate Failover process"
    $IsFailoverInProgress = $true
    $FailoverSuccessVirDevices = @()
    $VirDeviceImport = @()
    $IterationIndex = 1
    
    # Read Virtual device Import data from assets if exists
    $assetObj = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverDataAssetName -ErrorAction:SilentlyContinue)
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
        
        $VirtualDevices = $PendingVirtualDevices.Split(",").Trim()
    }
    
    <#Write-Output " "
    If ($IterationIndex -gt 1) {
        $CurrentTime = Get-Date
        $CheckIndex = ($IterationIndex - 1)
        Write-Output "********************************* Checking - $CheckIndex *********************************"
    }
    else {
        Write-Output "********************************* Device Failover Initiated *********************************"
    }#>
    Write-Output "`n `n ********************************* Device Failover Initiated *********************************"
    $VirtualDevicesByCommaSeparated = $VirtualDevices -Join "," 
    #Write-Output " "
    Write-Output "`n Virtual deives: $VirtualDevicesByCommaSeparated"
    foreach ($VirDeviceName in $VirtualDevices)
    {
        #Write-Output " "
        Write-Output "`n Virtual device name: $VirDeviceName"
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
            throw " Unable to fetch Current Virtual Device Import Data"
        }
        
        Write-Output "Initiated to check whether SVA & VM are online or not"
        $Device = Get-AzureStorSimpleDevice -DeviceName $VirDeviceName
        If ($Device -eq $null) {
            throw "  Virtual Device ($VirDeviceName) does not exist"
        }
        elseIf ($Device.Status -ne "Online") {
            throw "  Virtual Device ($VirDeviceName) is not started"
        }
         
        # Set VMServiceName
        $VMServiceName = $VirDeviceName.replace($NewVirtualDeviceName, $NewVMServiceName)
        $AzureVM = (Get-AzureVM -ServiceName $VMServiceName | Where Name -ne $VirDeviceName) | Select -First 1
        If ($AzureVM -eq $null) {
            throw "  VM ($VMName) does not exist in Service ($VirDeviceName)"
        }
        elseIf ($AzureVM.Status -ne "ReadyRole") {
            throw "  VM ($VMName) is not started"
        }
        
        # Set VMName
        $VMName = $AzureVM.Name
        
        #Connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
		Write-Output "Fetching VM ($VMName) WinRMUri"
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
            throw "  Unable to fetch VM ($VMName) WinRMUri"
        }
        
        If ($CurrentDeviceImportData.VolumeContainer -eq $null) {
            Write-Output "Fetching Volume Containers in Device ($VirDeviceName)"
            $VolumeContainer = (Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirDeviceName) | Select -First 1
        }
        else {
            $VolumeContainer = $CurrentDeviceImportData.VolumeContainer
            $VolContName= $CurrentDeviceImportData.VolumeContainerName 
        }
        If ($VolumeContainer -eq $null -or $VolumeContainer.Count -eq 0) {
            throw "  No Volume containers available on Device ($VirDeviceName)"
            #Write-Output "No Volume containers are available. It might be device failover completed"
        }
        elseIf ($VolumeContainer -ne $null -and $VolumeContainer.VolumeCount -eq 0) {
            throw "  No Volumes available on Device ($VirDeviceName) and VolumeContainer ($VolumeContainerName)"
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
            throw "No Volume Container available on Device ($VirDeviceName)"
        }
        
        # Fetch Volumes data
        If ($CurrentDeviceImportData.VolumeList -eq $null) {
            Write-Output "Fetching Volumes in Volume Container ($VolumeContainerName)"
            $VolumeList = InlineScript 
            {
                $CurrentDeviceImportData = $Using:CurrentDeviceImportData
                $VirDeviceName = $using:VirDeviceName
                $VolumeContainerName = $Using:VolumeContainerName
                $CurrentDeviceImportData.VolumeList = (Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirDeviceName -VolumeContainerName $VolumeContainerName | Get-AzureStorSimpleDeviceVolume -DeviceName $VirDeviceName)
                $CurrentDeviceImportData.VolumeList
                #((Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirDeviceName -VolumeContainerName $VolumeContainerName | Get-AzureStorSimpleDeviceVolume -DeviceName $VirDeviceName).Name | Sort) -Join ","
            }
        }
        else {
            $VolumeList = $CurrentDeviceImportData.VolumeList
        }
        If ($VolumeList -eq $null) {
            throw "  No Volumes available in Volume Container ($VolumeContainerName) on Device ($VirDeviceName)"
        }
        
        # Read Volume Names from object
        if ($VolumeList.Name.Count -gt 1) {
            $Volumes = (($VolumeList.Name | Sort) -Join ",").Split(",").Trim()
        }
        else {
            $Volumes = ($VolumeList.Name)
        }
        
        # Fetch "StroSimpleDisk" Labeled Drives from AzureVM
        If ($CurrentDeviceImportData.DriveLetters -eq $null) 
        {
            Write-Output "Fetching Drives in VM"
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
            
            If ($DriveLetters -eq $null -or$DriveLetters -eq "") {
                throw " No drives available in VM ($VMName)"
            }
        
			Write-Output "Drive letters: $DriveLetters"
            
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
        $Drives = $DriveLetters.Split(",").Trim()
        
        # Check whether Volumes count & Drives count same or not
        If ($Volumes.Count -ne $Drives.Count) {
            Write-Output "  Drives list: $DriveLetters"
            Write-OUtput "  Volumes list:"
            $Volumes
            throw "  Volumes and Drives are mismatched on Device ($VirDeviceName)"
        }

        # Create AzCopyStatus Object
        $AzCStatus = 0
        $AzCopyDriveState = @()
        if($CurrentDeviceImportData.AzCopyJobStatus -eq $true) {
            Write-Output "AzCopy execution is already completed"
            $AzCStatus = 2
        }
        else {
            Write-Output "Initiated to check whether AzCopy process completed or not"
            
            for ($propIndex=0; $propIndex -lt $Volumes.Count; $propIndex++)
            {
                If ($Volumes.Count -eq 1) { 
                    $VolName = $Volumes
                }
                else {
                    $VolName = $Volumes[$propIndex]
                }
                $Prop = @{ VolumeName=$VolName; Drive=$Drives[$propIndex]; Status=$AzCStatus }
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
                    param([String]$LogFilePath)
                    
                    If (Test-Path $LogFilePath) {
                        # AzCopy log file available
                        $LogStatus = 1
                        
                        $StartDate = (Get-ItemProperty -Path $LogFilePath).LastWriteTime
                        $EndDate = Get-Date
                        $LastWriteTimeInHours = (NEW-TIMESPAN -Start $StartDate -End $EndDate).Hours
                        $LastWriteTimeInMinutes = (NEW-TIMESPAN -Start $StartDate -End $EndDate).Minutes
                        
                        If ($LastWriteTimeInHours -ge 1 -or $LastWriteTimeInMinutes -ge 1)
                        {
                            $TransferSummaryTag = "Transfer summary:"                        
                            $SummaryContent = Select-String $LogFilePath -pattern $TransferSummaryTag
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
                    # Output
                    $LogStatus
                } -Argumentlist $Using:LogFilePath
            }
            
            #Write-Output "AzCopy Status: $AzCopyProgressState"$DriverStatus = "CHKDSK execution in progress"
            $DriverStatus = "In progress"
            If ($AzCopyProgressState -eq 2) {
                $DriverStatus = "Completed"
            }
            Write-Output "Drive: $drivename  Log filename: $LogFilePath  Status: $DriverStatus"
                        
            InlineScript
            {
                # Update Current Volume AzCopy state
                $CurrentAzCopyDriveState = $Using:CurrentAzCopyDriveState
                $AzCopyProgressState = $Using:AzCopyProgressState
                $CurrentAzCopyDriveState.Status = $AzCopyProgressState
            }
            
            #If ($AzCopyDriveState[$index].Status -ne 2) {
            #    $index = $AzCopyDriveState.Count
            #    #Write-Output "AzCopy still running for $drivename-drive"
            #}
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
                    Write-Output "AzCopy process is completed"
                }
                #elseIf ($CurrentDeviceImportData.AzCopyJobStatus -eq $true -and $IsAzCopyCompleted -eq $true) {
                #    Write-Output "AzCopy process is already completed"
                #}
            }
        }
        
        # Volumes Backup (Cloud snapshot) & Virtual Device Failover
        InlineScript
        {
            $AutomationAccountName = $Using:AutomationAccountName
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
            
            #If ($CurrentDeviceImportData.AzCopyJobStatus -eq $false) {
            #    Write-Output "AzCopy process still in progress on Device ($VirDeviceName). Skipped Backup process"
            #}
            #else
            If ($CurrentDeviceImportData.AzCopyJobStatus -eq $true -and $CurrentDeviceImportData.BackupJobStatus -eq $true) {
                Write-Output "Backup jobs are already completed"
            }
            elseIf($CurrentDeviceImportData.AzCopyJobStatus -eq $true -and $IsBackupJobCompleted -eq $false)
            {
                If ($CurrentDeviceImportData.BackupJobIds -eq $null) 
                {
                    Write-Output "Attempting to initiate backup"
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
                    Write-Output "  Initiate Backup for all Volumes in Volume Container ($VolumeContainerName)"
                    foreach ($BackupPolicy in $BackupPolicies)
                    {
                        $backupjob = Start-AzureStorSimpleDeviceBackupJob -DeviceName $VirDeviceName -BackupPolicyId  $BackupPolicy.InstanceId -BackupType CloudSnapshot
                        If ($backupjob -eq $null) {
                            throw "  Unable to take a backup for Volume ($BackupPolicy.Name)"
                        }
                    }
                    
                    $jobIDs = $null                    
                    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($jobIDs -eq $null)
                    {
                        If ($elapsed.Elapsed.Minutes -gt 20) {
                            throw "  Timeout for executing getting the job ID exceeded"
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
                    
                    # Delay for each backup job initiate-time
                    Start-Sleep -s $SLEEPTIMEOUTLARGE # $SLEEPTIMEOUT
                }
                else {
                    Write-Output "Backup Jobs are already initiated"
                    $jobIDs = $CurrentDeviceImportData.BackupJobIds
                }
                
                If ($BackupPolicies.Count -gt 0 -and $jobIDs -ne $null -and $jobIDs.Count -gt $BackupPolicies.Count) {
                    $CurrentDeviceImportData.BackupJobIds = $jobIDs
                    Write-Output "  Warning: Jobs are more than Backup policies"
                }
                If ($BackupPolicies.Count -gt 0 -and $jobIDs.Count -ne $BackupPolicies.Count) {
                    #$jobsCount = $jobIDs.Count
                    $policiesCount = $BackupPolicies.Count
                    Write-Output "  Backup policies count & Jobs count are mismatched"
                    Write-Output "  Total Backup Policies: ($policiesCount)"
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
                            #$checkForSuccess=$false
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
                    Write-Output "  Backup Jobs completed successfully on Device ($VirDeviceName)"
                    
                    # Update BackupJobs status for VirtualDevice
                    $CurrentDeviceImportData.BackupJobStatus = $true
                }
                else {
                    throw "  Backup Jobs unsuccessful on Device ($VirDeviceName)"
                }
            }
            
            # Attempting to initiate Failover process
            <#If ($IsBackupJobsRunning) {
                Write-Output "Backup initiated on Device ($VirDeviceName). Device failover skipped"
            }
            elseIf ($CurrentDeviceImportData.BackupJobStatus -eq $false) {
                Write-Output "Backup not initiated on Device ($VirDeviceName). Device failover skipped"
            }
            else#>
            If ($CurrentDeviceImportData.BackupJobStatus -eq $true -and $CurrentDeviceImportData.FailoverJobStatus -eq $true) {
                Write-Output "Device failover is already completed on Device ($VirDeviceName)"
            }
            elseIf($CurrentDeviceImportData.BackupJobStatus -eq $true -and $CurrentDeviceImportData.FailoverJobStatus -eq $false)
            {
                If ($CurrentDeviceImportData.FailoverJobId -eq $null)
                {
                    # Attempting to initiate Device Failover on Volume Container ($VolumeContainerName)                        
                    Write-Output "Attempting to initiate device failover" 
                    $jobID = (Get-AzureStorSimpleFailoverVolumeContainers -DeviceName $VirDeviceName) | Where-Object {$_.IsDCGroupEligibleForDR -eq $True -and $_.DCGroup.Name -match $CurrentDeviceImportData.VolumeContainerName} |  Start-AzureStorSimpleDeviceFailoverJob -DeviceName $VirDeviceName -TargetDeviceName  $TargetDeviceName  -Force 
                    
                    If ($jobID -eq $null) {
                        throw "  Device failover couldn't be initiated on Device ($DeviceName)"
                    }
                    
                    $CurrentDeviceImportData.FailoverJobId = $jobID
                    
                    # Delay for each Device failover job initiate-time
                    Start-Sleep -s $SLEEPTIMEOUTLARGE # $SLEEPTIMEOUT
                }
                else {
                    Write-Output "Device failover is already initaited"
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
                    Write-Output "  Device failover completed successfully on Device ($VirDeviceName)"
                    
                    # Update FailoverJob status for VirtualDevice
                    $CurrentDeviceImportData.FailoverJobStatus = $true
                    $FailoverSuccessVirDevices += $VirDeviceName
                    
                    # Fetch ImportData-FailoverCompletedDevices asset variable
                    $asset = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverCompletedDevicesAssetName -ErrorAction:SilentlyContinue)               
                    If ($asset -ne $null) {
                        # Set asset ImportData-FailoverCompletedDevices value 
                        $AssetVal =  $asset.Value.Replace(",delimiter", "")
                        $AssetVal = $AssetVal + "," + $VirDeviceName + ",delimiter"
                        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverCompletedDevicesAssetName -Encrypted $false -Value $AssetVal
                    }
                    else {
                        # Create new ImportData-FailoverCompletedDevices asset
                        $AssetVal = ($VirDeviceName + ",delimiter")
                        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverCompletedDevicesAssetName -Value $AssetVal -Encrypted $false
                    }
                }
                else {
                    throw "  Device failover unsuccessful on Device ($VirDeviceName)"
                }
            }
        }
    }
    
    $TotalFailoverDeivceCount = InlineScript
    {
        $VirDeviceImport = $Using:VirDeviceImport
        $devicecount = 0
        foreach ($DeviceData in $VirDeviceImport) {
            If ($DeviceData.FailoverJobStatus) {
                $devicecount += 1
            }
        }            
        # Output for InlineScript
        $devicecount
    }
    
    # Check whether all Devices failover completed or not
    $TotalDeviceCount = $VirDeviceImport.Count
    $IsFailoverInProgress =  $TotalFailoverDeivceCount -ne $TotalDeviceCount
    
    Write-Output "`n Result: "
    Write-Output "  Total Devices: $TotalDeviceCount"
    Write-Output "  Total Completed Failover Devices: $TotalFailoverDeivceCount"
    If ($IsFailoverInProgress) 
    {
        Write-Output "`n `n Failover Info: "
        $VirtualDevices
        
        Write-Output "`n `n Failover process still running"
        $asset = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverDataAssetName -ErrorAction:SilentlyContinue)
        If ($asset -ne $null) {
            # Set asset ImportData-FailoverDataAssetName value
            $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverDataAssetName -Encrypted $false -Value $VirDeviceImport
        }
        else {
            # Create new ImportData-FailoverDataAssetName asset
            $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataFailoverDataAssetName -Value $VirDeviceImport -Encrypted $false
        }
    }
    else {
        Write-Output "`n `n All Virtual Devices Failover completed successfully"
        Unregister-AzureAutomationScheduledRunbook -AutomationAccountName $AutomationAccountName -RunbookName $ImportDataFailoverRunbookName -ScheduleName $ImportDataFailoverScheduleName -Force -ErrorAction:SilentlyContinue
    }
    
    $IterationIndex += 1
    
    Write-Output "Job Completed"
}