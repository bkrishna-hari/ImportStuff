workflow ImportData-CreateVolumes-TriggerAzCopy
{
    # Asset Names
    $ContainersAssetName = "ImportData-Containers"
    $ExcludeContainersAssetName = "ImportData-ExcludeContainers"
    $ImportDataSVAsAssetName = "ImportData-SVAs"
    $ImportDataAzCopyInitiatedSVAsAssetName = "ImportData-AzCopyInitiatedSVAs"
    
    #New Instance Name format
    $NewVirtualDeviceName = "importsva"
    $NewVMServiceName = "importvmservice"
    $NewVMName = "importvm"
    
    #VM inputs
    $VolumeSize = 1000000000000  # 107374182400
    
    # Storage ContainerName
    $ScriptContainer = 'import-scriptcontainer'
    
    # Storage Account Url
    $SourceBlob = "https://StorageAccountName.blob.core.windows.net/"
    
    #common inputs
    $SLEEPTIMEOUTSMALL = 5
    $SLEEPTIMEOUTMEDIUM = 30
    $SLEEPTIMEOUTLARGE = 60
    
    # Fetch all Automation Variable data
    Write-Output "Fetching Assets info"    
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
    
    $VmAndSvaStorageAccountName = Get-AutomationVariable –Name "ImportData-StorageAccountName" 
    if ($VmAndSvaStorageAccountName -eq $null) 
    { 
        throw "The StorageAccountName asset has not been created in the Automation service."  
    }
	$SourceBlob = $SourceBlob.Replace("StorageAccountName", $VmAndSvaStorageAccountName)
    
    $VmAndSvaStorageAccountKey = Get-AutomationVariable –Name "ImportData-StorageAccountKey" 
    if ($VmAndSvaStorageAccountKey -eq $null) 
    { 
        throw "The StorageAccountKey asset has not been created in the Automation service."  
    }
    $SourceStorageAccountKey = $VmAndSvaStorageAccountKey
    
    $AutomationAccountName = Get-AutomationVariable –Name "ImportData-AutomationAccountName"
    if ($AutomationAccountName -eq $null) 
    { 
        throw "The AutomationAccountName asset has not been created in the Automation service."  
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
    
    # Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential      
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName          
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
    }
    
    #Connect to StorSimple 
    Write-Output "Connecting to StorSimple"                
    $StorSimpleResource = Select-AzureStorSimpleResource -ResourceName $ResourceName -RegistrationKey $StorSimRegKey
    If ($StorSimpleResource -eq $null)
    {
        throw "Unable to connect to StorSimple"
    }
    
    # Set Current Storage Account for the subscription
    Write-Output "Setting the storage account for the subscription"
    try {
        Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccountName $VmAndSvaStorageAccountName
    }
    catch {
        throw "Unable to set the storage account for the subscription"
    }

    # Fetch DummySVAs asset variable
    $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)

    If (($AssetList | Where-Object {$_.Name -match $ContainersAssetName}) -eq $null) 
    {    
        # Attempting to read Volumes info by container name
        Write-Output "Attempting to fetch Containers in Storage Account ($VmAndSvaStorageAccountName)"
        $ContainerCollection = (Get-AzureStorageContainer | select -ExpandProperty Name) -Join ","
        If (($ContainerCollection -eq $null) -or ($ContainerCollection.Count -eq 0)) {
            throw "No Container available in Storage Account($VmAndSvaStorageAccountName)"
        }
    }
    else {
        $ContainerCollection = ($AssetList | Where-Object {$_.Name -match $ContainersAssetName}).Value 
    }
    
    $ContainerArrayList = InlineScript 
    {
        $ContainerCollection = $Using:ContainerCollection
        $containsers = @()
        If ($ContainerCollection.ToString().Contains(',') -eq $true) {
            $containsers += $ContainerCollection.Split(",").Trim()
        }
        else {
            $containsers += $ContainerCollection
        }
        # Output for InlineScript
        $containsers
    }
    
    $ContainerVolumeList = @()
    $ContainerVolumeList = InlineScript
    {
        $ContainerVolumeData = @()
        $ContainerArrayList = $Using:ContainerArrayList
        
        # Attempting to read list of blobs
        foreach ($ContainerName in $ContainerArrayList)
        {
            $ContainerProp = @{ ContainerName=$ContainerName; VolumeList=@(); HasBlobs=$false }
            $NewContainerObj = New-Object PSObject -Property $ContainerProp
            $ContainerVolumeData += $NewContainerObj
            $CurrentContainerData = $NewContainerObj
            
            $BlobCollection = @()
            $BlobCollection = (Get-AzureStorageBlob -Container $ContainerName | Select -ExpandProperty Name) -Join ","
            If (($BlobCollection -eq $null) -or ($BlobCollection.Count -eq 0))
            {
                # No blob(s) available in Container ($ContainerName)
                $CurrentContainerData.HasBlobs = $false
                continue;
            }
            
            $BlobArrayList = @()
            if($BlobCollection.ToString().Contains(',') -eq $True) {
                $BlobArrayList += $BlobCollection.Split(",").Trim() 
            }
            else {
                $BlobArrayList += $BlobCollection
            }
            
            # Fetch Volumes from blobs
            $Volumes = @()
            foreach ($BlobName in $BlobArrayList)
            {
                if(($BlobName.ToString().Contains('/')) -eq $True) {
                    $CurrentContainerData.HasBlobs = $true
                    $VolumeName = $BlobName.Split("/")[0].Trim()
                    
                    If ($Volumes -notcontains @($VolumeName -Join ",")) {
                        $Volumes += $VolumeName -Join ","
                        $CurrentContainerData.VolumeList += $VolumeName -Join ","
                    }
                }
                else {
                    $CurrentContainerData.HasBlobs = $false
                    $CurrentContainerData.VolumeList = $null
                }
            }
            
            # Set Volume list in ascending order
            If ($CurrentContainerData.VolumeList -ne $null) {
                $CurrentContainerData.VolumeList = ($CurrentContainerData.VolumeList | Sort)
            }
        }
        # Output for InlineScript
        $ContainerVolumeData
    }
    
    # Final Exclude Container list
    $ContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $true})
    
    $AzCopyInitiatedSvaAssetValue = $null
    If (($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}) -ne $null) {
        $AzCopyInitiatedSvaAssetValue = ($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}).Value
        Write-Output "Asset value: $AzCopyInitiatedSvaAssetValue"
    }
    
    Write-Output "Create ImportData-CreateVolumes-TriggerAzCopy object"
    $ImportInfraList = InlineScript 
    {
        $AzCopyInitiatedSvaAssetValue = $Using:AzCopyInitiatedSvaAssetValue
        $ContainerList = $Using:ContainerList
        $NewVirtualDeviceName = $Using:NewVirtualDeviceName
        $NewVMServiceName = $Using:NewVMServiceName
        $NewVMName = $Using:NewVMName
        
        $InfraList = @()
        $InfraLoopIndex = 1    # DONOT CHANGE THIS INDEX
        foreach ($data in $ContainerList)
        {
            $InfraVirtualDeviceName = ($NewVirtualDeviceName + $InfraLoopIndex)
            $InfraVMServiceName = ($NewVMServiceName + $InfraLoopIndex)
            $InfraVMName = ($NewVMName + $InfraLoopIndex)
            
            If (($AzCopyInitiatedSvaAssetValue -eq $null) -or ($AzCopyInitiatedSvaAssetValue.Contains($InfraVirtualDeviceName)) -eq $false) 
            {
                $InfraProp=@{ VirtualDeviceName=$InfraVirtualDeviceName; VMName=$InfraVMName; VMServiceName=$InfraVMServiceName; IsSVAOnline=$false; IsVMReady=$false; VMWinRMUri=$null; IQN=$null; ContainerName=$data.ContainerName; VolumeList=$data.VolumeList; HasBlobs=$data.HasBlobs; DriveList=$null; IsAzCopyInitiated=$false }
                $NewInfraObj = New-Object PSObject -Property $InfraProp
                $InfraList += $NewInfraObj
            }        
            $InfraLoopIndex += 1
        }
        # Output for InlineScript
        $InfraList
    }
    
    If ($ImportInfraList -eq $null) {
        Write-Output "No SVAs are available to Create Volumes and Iinitiate AzCopy"
    }
    elseIf ($ImportInfraList.Count -eq 0) {
        Write-Output "Volumes Creation and AzCopy Initiation completed successfully"
    }
    else
    {
        Write-Output "Check whether SVAs & VMs are online or not"
        foreach ($InfraData in $ImportInfraList)
        {
            $CurrentInfraData = $InfraData
            $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
            $VMServiceName = $CurrentInfraData.VMServiceName
            $VMName = $CurrentInfraData.VMName
            
            $AzureDevice = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
            if ($AzureDevice -eq $null -or $AzureDevice.Status -ne "Online") {
                throw "SVA ($VirtualDeviceName) either does not exist or in Offline"
            }
            
            $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
            If ($AzureVM -eq $null -or $AzureVM.Status -ne "ReadyRole") {
                throw "VM ($VMName) either does not exist or not Ready state"
            }
            <#
            # Update the VM Agent to reflect its installation on Azure
            InlineScript 
            {
                $VMName = $Using:VMName
                $VMServiceName = $Using:VMServiceName
                
                $AzureVM = Get-AzureVM –ServiceName $VMServiceName -Name $VMName
                Write-Output "Updating VM Agent on $VMName"
                $AzureVM.VM.ProvisionGuestAgent = $true
                try {
                    $result = Update-AzureVM -Name $VMName –VM $AzureVM.VM -ServiceName $VMServiceName
                }
                catch {
                    throw "Unable to set VM ($VMName) agent property for VM on $VMName"
                }
            }
            #>
        }
        
        #connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
        Write-Output "Fetching VMs WinRMUri"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VMName = $CurrentInfraData.VMName
            $VMServiceName = $CurrentInfraData.VMServiceName
            
            # Connecting to VM ($VMName) - ServiceName ($VMServiceName)
            #$VMWinRMUri = Connect-AzureVM -AzureSubscriptionName $SubscriptionName -ServiceName $VMServiceName -VMName $VMName -AzureOrgIdCredential $AzureCredential
            $VMWinRMUri = InlineScript {
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
            if($VMWinRMUri -eq $null) {
                throw "Unable to connect to VM ($VMName)" 
            }
            InlineScript {
                $CurrentInfraData = $Using:CurrentInfraData
                $VMWinRMUri = $Using:VMWinRMUri
                $CurrentInfraData.VMWinRMUri = $VMWinRMUri
            }
        }
        
        # Fetch existing ACR details
        $AvailableACRList = Get-AzureStorSimpleAccessControlRecord
        
        #connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
        Write-Output "Initiating to create ACR, Volume Container & Volumes"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VMName = $data.VMName 
            $VMWinRMUri = $data.VMWinRMUri
            $AcrName = $VMName
            
            If ($CurrentInfraData.VMWinRMUri -ne $null)
            {
                Write-Output "Fetch VM ($VMName) IQN"
                $VMIQN = InlineScript
                {
                    Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock {
                        param([Int]$SLEEPTIMEOUTSMALL)
                        
                        # Install AzCopy
                        $source = "http://aka.ms/downloadazcopy"
                        $destination = "C:\Users\Public\Downloads\AzCopy.msi" 
                        $AzCopyPath = "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
                        
                        # Check whether AzCopy available or not
                        #If ((Test-Path $AzCopyPath) -eq $false) { 
                            Invoke-WebRequest $source -OutFile $destination
                            
                            #wait till the file is downloaded
                            while ($true)
                            {
                                $checkForFile = (Test-Path $destination)
                                if ($checkForFile) {
                                    break
                                }
                                else {
                                    Start-Sleep -s $SLEEPTIMEOUTSMALL
                                }                        
                            }
                            
                            # Execute the AzCopy exe
                            Start-Process "C:\Windows\System32\msiexec.exe" -ArgumentList "/i $destination /qn" -wait            
                        #}
                        
                        #Starting the iSCSI service 
                        Start-Service msiscsi
                        Start-Sleep -s $SLEEPTIMEOUTSMALL
                        Set-Service msiscsi -StartupType "Automatic"
                        
                        #getting initiator
                        $IQN = (Get-InitiatorPort).NodeAddress
                        # Output for inline script
                        $IQN
                    } -Argumentlist $Using:SLEEPTIMEOUTSMALL
                }
                
                If ($VMIQN -eq $NUll) {
                    throw "Unable to fetch the ACR of VM ($VMName)"
                }
                else 
                {
                    Write-Output "Adding ACR ($AcrName) to the resource"
                    If (($AvailableACRList | Where-Object { $_.Name -eq $AcrName }) -eq $null) 
                    {
                        $AcrCreation=New-AzureStorSimpleAccessControlRecord -ACRName $AcrName -IQNInitiatorName $VMIQN -WaitForComplete
                        If ($AcrCreation -eq $null) {
                            throw "ACR ($AcrName) could not be added to the resource"
                        }
                    }
                    
                    InlineScript 
                    {
                        $VMIQN = $Using:VMIQN
                        $AcrName = $Using:AcrName
                        $CurrentInfraData = $Using:CurrentInfraData
                        $CurrentInfraData.IQN = $VMIQN
                        $VmAndSvaStorageAccountName = $Using:VmAndSvaStorageAccountName
                        $VmAndSvaStorageAccountKey = $Using:VmAndSvaStorageAccountKey
                        $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
                        $VolumeContainerName = $CurrentInfraData.ContainerName
                        $VolumeSize = $Using:VolumeSize
                        
                        # Fetch ACR Details
                        $Acr = Get-AzureStorSimpleAccessControlRecord -ACRName $AcrName
                        
                        # Create Storage Account Credential
                        $sac = Get-AzureStorSimpleStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName -ErrorAction:SilentlyContinue 
                        If ($sac -eq $null) {
                            $sac = New-SSStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName -StorageAccountKey $VmAndSvaStorageAccountKey -UseSSL $false -ErrorAction:SilentlyContinue -WaitForComplete
                            if ($sac -eq $null) {
                                throw "Unable to create a Storage Account Credential ($VmAndSvaStorageAccountName)"
                            }
                        }
                        
                        # Check whether VolumeContainer exists or not
                        Write-Output "Initating to create Volume Container ($VolumeContainerName) on Device ($VirtualDeviceName)"
                        $volcon = Get-AzureStorSimpleDeviceVolumeContainer -Name $VolumeContainerName -DeviceName $VirtualDeviceName
                        If ($volcon -eq $null) {
                            $volcon = Get-AzureStorSimpleStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName | New-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName -BandWidthRateInMbps 0 -WaitForComplete
                            If ($volcon -eq $null) {
                                throw "Unable to create a Volume container ($VolumeContainerName) on Device ($VirtualDeviceName)"
                            }
                        }
                        
                        # Fetch existing volume list
                        $volumelist = Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName | Get-AzureStorSimpleDeviceVolume -DeviceName $VirtualDeviceName
                        
                        Write-Output "Initiating to create Volumes in Volume Container ($VolumeContainerName)"
                        foreach ($VolumeName in $CurrentInfraData.VolumeList)
                        {
                            If (($volumelist.Count -eq 0) -or (($volumelist | Where-Object {$_.Name -match $VolumeName}) -eq $null)) 
                            {
                                $vol = Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName | New-AzureStorSimpleDeviceVolume -DeviceName $VirtualDeviceName -VolumeName $VolumeName -Size $VolumeSize -AccessControlRecords $Acr -VolumeAppType PrimaryVolume -Online $True -EnableDefaultBackup $True -EnableMonitoring $False -WaitForComplete
                                if ($vol -eq $null) {
                                    throw "Unable to create a Volume ($VolumeName) in Device ($VirtualDeviceName)"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        
        Write-Output "Create the iSCSI target portal and mount the volumes, return the Drive letters of the mounted StorSimple volumes"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
            $VMServiceName = $CurrentInfraData.VMServiceName
            $VMName = $data.VMName
            $VMIQN = $CurrentInfraData.IQN
            $VMWinRMUri = $CurrentInfraData.VMWinRMUri
            
            If ($VMIQN -ne $null)
            {
                # Fetching IQN of the SVA
                $SVAVm = Get-AzureVm -ServiceName $VirtualDeviceName -Name $VirtualDeviceName
                If ($SVAVm -eq $null) {
                    throw "Unable to get Azure VM ($VMName)"
                }
                
                $SVAIp = $SVAVm.IpAddress
                If ($SVAIp -eq $null) {
                    throw "Unable to get the IP Address of Azure VM ($VMName)"
                }
                
                $SVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                If ($SVA -eq $null) {
                    throw "Unable to get the SVA ($VirtualDeviceName)"
                }
                
                $SVAIqn = $SVA.TargetIQN
                If ($SVAIqn -eq $null) {
                    Write-Output "Unable to fetch IQN of the SVA ($VirtualDeviceName)"
                }

                #create the iSCSI target portal and mount the volumes, return the drive letters of the mounted StorSimple volumes
                Write-Output "Mounting StorSimple volumes on the VM ($VMName)"
                $drives = InlineScript
                {
                    Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock { 
                        param([String]$SVAIp, [String]$SVAIqn, [Int]$SLEEPTIMEOUTMEDIUM, [Int]$SLEEPTIMEOUTSMALL)
                            
                            $newportal = New-IscsiTargetPortal -TargetPortalAddress $SVAIp                                
                            If ($newportal -eq $null) {
                                throw "Unable to create a new iSCSI target portal"
                            }
                            
                            $connection = Connect-IscsiTarget -NodeAddress $SVAIqn -IsPersistent $true -ErrorAction:SilentlyContinue
                            $sess = Get-IscsiSession
                            If ($sess -eq $null) {
                                throw "Unable to connect the iSCSI target"
                            }
                            
                            Update-StorageProviderCache
                            Update-HostStorageCache
                            
                            $drivescollection = (Get-Volume | where FileSystemLabel -match "STORSIMPLE*" | Select DriveLetter)
                            If ($drivescollection -eq $null)
                            {
                                Get-Disk  | Where-Object {$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsOffline $false
                                Get-Disk  | Where-Object {$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsReadOnly $false
                                Start-Sleep -s $SLEEPTIMEOUTSMALL
                                
                                # Initialize-Disk partition
                                $RawPartitionDisk = (Get-Disk | Where-Object {$_.Model -match 'STORSIMPLE*'}) #  -and $_.PartitionStyle -eq 'raw'
                                foreach ($disk in $RawPartitionDisk)
                                {
                                    If ($disk.PartitionStyle -eq 'raw') {
                                        $output = $disk | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "StorSimpleDisk" -Confirm:$false
                                    }
                                    else {
                                        $output = $disk | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel "StorSimpleDisk" -Confirm:$false
                                    }
                                    # Waiting for Disk format to be finished
                                    Start-Sleep -s $SLEEPTIMEOUTSMALL
                                }
                            }
                            #Output for InlineScript
                            ((Get-Volume | where FileSystemLabel -match "STORSIMPLE*" | Select DriveLetter).DriveLetter | Sort)
                    } -Argumentlist $Using:SVAIp,$Using:SVAIqn,$Using:SLEEPTIMEOUTMEDIUM,$Using:SLEEPTIMEOUTSMALL
                }
                
                $DriveList = InlineScript
                {
                    $drives = $Using:drives
                    $list = @()
                    If ($drives.ToString().Contains(',') -eq $True) {
                        $list += $drives.Split(",")
                    }
                    else {
                        $list += $drives
                    }
                    # Output for InlineScript
                    $list
                }
                
                if ($DriveList -eq $null) {
                    throw "Unable to get the StorSimple drives on VM ($VMName)"
                }
                elseIf ($DriveList.Count -ne $CurrentInfraData.VolumeList.Count) {
                    Write-Output "Drive list:"
                    $DriveList
                    Write-Output "Volume list:"
                    $CurrentInfraData.VolumeList
                    throw "Volumes and Drives are mismatched on Device ($VirtualDeviceName)"
                }
                else {
                    InlineScript {
                        $DriveList = $Using:DriveList
                        $CurrentInfraData = $Using:CurrentInfraData
                        $CurrentInfraData.DriveList = $DriveList
                    }
                }
            }
        }
        
        #Copy the blobs in the respective Drive
        #Do not remove the logging parameter from the AzCopy command as that will be used to get the progress
        #the script uses VM agent to run the AzCopy command, Invoke-Command doesn't work - it'll throw a system out of memory exception for large files
        Write-Output "Attempting to trigger AzCopy on each VM"
        InlineScript
        {
            $SourceBlob = $Using:SourceBlob
            $SourceStorageAccountKey = $Using:SourceStorageAccountKey
            $StorageAccountName = $Using:VmAndSvaStorageAccountName
            $StorageAccountKey = $Using:VmAndSvaStorageAccountKey
            $AutomationAccountName = $Using:AutomationAccountName
            $ImportDataAzCopyInitiatedSVAsAssetName = $Using:ImportDataAzCopyInitiatedSVAsAssetName
            $ImportInfraList = $Using:ImportInfraList
            $SLEEPTIMEOUTLARGE = $Using:SLEEPTIMEOUTLARGE
            $AssetList = $Using:AssetList
            $ScriptContainer = $Using:ScriptContainer
            
            foreach ($data in $ImportInfraList)
            {
                <#If ($data.DriveList -eq $null -or $data.VolumeList -eq $null) {
                    Write-Output "Skipped VM: "
                    $data.VMName
                    continue
                }#>
                
                $CurrentInfraData = $data
                $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
                $VMServiceName = $CurrentInfraData.VMServiceName
                $VMName = $CurrentInfraData.VMName
                $VolumeContainerName = $CurrentInfraData.ContainerName
                $DriveList = $CurrentInfraData.DriveList
                $VolumeList = $CurrentInfraData.VolumeList
                
                $AzCopyLoopIndex = 0
                while ($AzCopyLoopIndex -lt $DriveList.Count)
                {
                    $DriveName = $DriveList[$AzcopyLoopIndex]
                    $drive = $DriveName + ":\"
                    $VolumeName = $VolumeList[$AzCopyLoopIndex]
                    If ($DriveList.Count -eq 1) {
                        $VolumeName = $VolumeList
                    }
                    
                    $logpath = "C:\Users\Public\Documents\AzCopy-" + $VolumeName + "-" + $DriveName + ".log"
                    Write-Output " "
                    Write-Output "VolumeName: $VolumeName"
                    Write-Output "Log file path: $logpath"
                    Write-Output "Initiating AzCopy on $drive drive"
                    $ScriptName = 'script-' + $VolumeName + "-" + $DriveName + '.ps1'
                    $Journalfile = "C:\Users\Public\Documents\journalfolder-" + $VolumeName + "-" + $DriveName + "\"
                    
                    If ($SourceBlob.substring($SourceBlob.Length - 1) -eq "/") {
                        $ContainerSourceBlobUrl = $SourceBlob + $VolumeContainerName + '/' + $VolumeName
                    }
                    else {
                        $ContainerSourceBlobUrl = $SourceBlob + '/' + $VolumeContainerName + '/' + $VolumeName
                    }
                  
                    $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
                    if ($context -eq $null) {
                        throw "Unable to create a new storage context"
                    }
                    
                    $container = Get-AzureStorageContainer -Name $ScriptContainer -Context $context -ErrorAction:SilentlyContinue
                    if ($container -eq $null) {
                        $newcontainer = New-AzureStorageContainer -Name $ScriptContainer -Context $context
                        if ($newcontainer -eq $null) {
                            throw "Unable to create a container to store the script ($ScriptContainer)"
                        }
                    }
                    
                    $text = "cd 'C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\'
If ((Test-Path '$logpath') -eq `$false) { .\AzCopy.exe /Source:$ContainerSourceBlobUrl /Dest:$drive /SourceKey:$SourceStorageAccountKey /Z:'$Journalfile' /S /V:'$logpath' }"  
                    
                    $Scriptfilename = "C:\file-" + $VolumeName + "-" + $DriveName + ".ps1"
                    $text | Set-Content $Scriptfilename 
                    $uri = Set-AzureStorageBlobContent -Blob $ScriptName -Container $ScriptContainer -File $Scriptfilename -context $context -Force
                    if ($uri -eq $null) {
                        throw "Unable to Write script to the container ($Scriptfilename)"
                    }
                    $sasuri = New-AzureStorageBlobSASToken -Container $ScriptContainer -Blob $ScriptName -Permission r -FullUri -Context $context
                    if ($sasuri -eq $null) {
                        throw "Unable to get the URI for the script ($ScriptContainer)"
                    }
                    $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName       
                    if ($AzureVM -eq $null) {
                        throw "Unable to access the Azure VM ($VMName)"
                    }
                    $extension = $AzureVM.ResourceExtensionStatusList | Where-Object {$_.HandlerName -eq "Microsoft.Compute.CustomScriptExtension"}
                    if ($extension -ne $null) {
                        Write-Output "Uninstalling custom script extension" 
                        $result = Set-AzureVMCustomScriptExtension -Uninstall -ReferenceName CustomScriptExtension -VM $AzureVM | Update-AzureVM
                    }
                           
                    Write-Output "Installing custom script extension" 
                    $result = Set-AzureVMExtension -ExtensionName CustomScriptExtension -VM $AzureVM -Publisher Microsoft.Compute -Version 1.4 | Update-AzureVM    
                                         
                    Write-Output "Running script on the VM"         
                    $result = Set-AzureVMCustomScriptExtension -VM $AzureVM -FileUri $sasuri -Run $ScriptName | Update-AzureVM
                   
                    $AzCopyLoopIndex += 1
                }
                
                # Update Import Infra Status
                $CurrentInfraData.IsAzCopyInitiated = $true
                Write-Output "Completed AzCopy script on VM ($VMName)"
        
                # Fetch DummySVAs asset variable
                $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)               
                If ($AssetList -ne $null -and ($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}) -ne $null) {
                    # Set ImportData-ExcludeContainers asset data 
                    $AssetVal =  ($AssetList | Where-Object { $_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}).Value.Replace(",delimiter", "")
                    $AssetVal = $AssetVal + "," + $VirtualDeviceName + ",delimiter"
                    $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataAzCopyInitiatedSVAsAssetName -Encrypted $false -Value $AssetVal
                }
                else {
                    # Create ImportData-ExcludeContainers asset data 
                    $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataAzCopyInitiatedSVAsAssetName -Value ($VirtualDeviceName + ",delimiter") -Encrypted $false
                }
            }
        }
    }
    
    Write-Output " "
    Write-Output "******************************** Result ******************************** "
    $ImportInfraList
    
    Write-Output " "
    Write-Output "*************************    Operation Completed     ********************************"
}
