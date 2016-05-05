<#
.DESCRIPTION
    This runbook fetches Storage container details
    This runbook fetches Virtual machine's windows remote management uri
    This runbook installs AzCopy and reads Access control records details (IQNInitiator Name)
    This runbook creates Volume container and Volumes
    This runbook logons to the Virtual machine and mount the StorSimple volumes.
    This runbook creates a script whcih contains AzCopy command and stores it in a storage account.
    This runbook triggers above script by using CustomScriptExtension command.    
    This runbook repeats the above steps until whole import process completes.
     
.ASSETS 
    AzureCredential [Windows PS Credential]:
        A credential containing an Org Id username, password with access to this Azure subscription
        Multi Factor Authentication must be disabled for this credential
         
    AzureSubscriptionName: The name of the Azure Subscription
    ResourceName: The name of the StorSimple resource
    StorSimRegKey: The registration key for the StorSimple manager
    StorageAccountName: The name of teh storage account in which the containers are to be imported and the script will be stored.
    StorageAccountKey: The access key for the storage account
    TargetDeviceName: The Device on which the volume containers from the source device will change ownership and are transferred to the target device
    VolumeSize: The size of volume which will be in gigabyte(s)
    AutomationAccountName: The name of the Automation account name
    
.NOTES:
    Multi Factor Authentication must be disabled to execute this runbook

#>

workflow ImportData-CreateVolumes-TriggerAzCopy
{
    # Asset Names
    $ContainersAssetName = "Import-Containers"
    $ImportDataSVAsAssetName = "Import-SVAs"
    $ImportDataAzCopyInitiatedSVAsAssetName = "Import-AzCopyInitiatedSVAs"
    
    # Storage ContainerName
    $ScriptContainer = 'import-scriptcontainer'
    
    # Storage Account Url
    $SourceBlob = "https://StorageAccountName.blob.core.windows.net/"
    
    #common inputs
    $SLEEPTIMEOUTSMALL = 5
    $SLEEPTIMEOUT = 60
    
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
    
    $VmAndSvaStorageAccountName = Get-AutomationVariable –Name "StorageAccountName" 
    if ($VmAndSvaStorageAccountName -eq $null) 
    { 
        throw "The StorageAccountName asset has not been created in the Automation service."  
    }
    $SourceBlob = $SourceBlob.Replace("StorageAccountName", $VmAndSvaStorageAccountName)
    
    $VmAndSvaStorageAccountKey = Get-AutomationVariable –Name "StorageAccountKey" 
    if ($VmAndSvaStorageAccountKey -eq $null) 
    { 
        throw "The StorageAccountKey asset has not been created in the Automation service."  
    }
    $SourceStorageAccountKey = $VmAndSvaStorageAccountKey
    
    [long]$VolumeSize = Get-AutomationVariable –Name "VolumeSize" 
    if ($VolumeSize -eq $null) 
    { 
        throw "The VolumeSize asset has not been created in the Automation service."  
    }
    [long]$VolumeSizeInBytes = ($VolumeSize * 1073741824) # Conversion from gigabyte(s) to byte(s)
	
    $AutomationAccountName = Get-AutomationVariable –Name "AutomationAccountName"
    if ($AutomationAccountName -eq $null) 
    { 
        throw "The AutomationAccountName asset has not been created in the Automation service."  
    }
 
    # New Instance Name format
    $NewVirtualDeviceName = Get-AutomationVariable –Name "Import-NewVirtualDeviceName"
    if ($NewVirtualDeviceName -eq $null)
    {
        throw "The NewVirtualDeviceName asset has not been created in the Automation service."
    }
	
    $NewVMName = Get-AutomationVariable –Name "Import-NewVMName"
    if ($NewVMName -eq $null)
    { 
        throw "The NewVMName asset has not been created in the Automation service."
    }
	
    $NewVMServiceName = Get-AutomationVariable –Name "Import-NewVMServiceName"
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
    
    # Connect to StorSimple 
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
    catch [Exception] {
        Write-Output $_.Exception.Message
        throw "Unable to set the storage account for the subscription"
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

    # Fetch all asset info
    Write-Output "Fetching all existing assets info"
    try {
        $AssetList = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName)
    }
    catch [Exception] {
        Write-Output $_.Exception.Message
        throw "The Automation account ($AutomationAccountName) is not found."
    }

    If (($AssetList | Where-Object {$_.Name -match $ContainersAssetName}) -eq $null) 
    {    
        # Attempting to read Volumes info by container name
        Write-Output "Attempting to fetch Containers in Storage Account ($VmAndSvaStorageAccountName)"
        $ContainerCollection = (Get-AzureStorageContainer | select -ExpandProperty Name) -Join ","
        If (($ContainerCollection -eq $null) -or ($ContainerCollection.Count -eq 0)) {
            throw "No Container available in Storage Account ($VmAndSvaStorageAccountName)"
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
            $containsers += $ContainerCollection.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
        }
        else {
            $containsers += $ContainerCollection
        }
        # Output of InlineScript
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
                $BlobArrayList += $BlobCollection.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) 
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
        # Output of InlineScript
        $ContainerVolumeData
    }
    
    # Final Exclude Container list
    $ContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $true})
    
    $AzCopyInitiatedSvaAssetValue = $null
    If (($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}) -ne $null) {
        $AzCopyInitiatedSvaAssetValue = ($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}).Value
        $value = $AzCopyInitiatedSvaAssetValue.Replace(",delimiter", "").Trim()
        Write-Output "AzCopy started Virtual machine list: $AzCopyInitiatedSvaAssetValue"
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
        # Output of InlineScript
        $InfraList
    }
    
    If ($ImportInfraList -eq $null) {
        throw "No Virtual device is available to initiate import process"
    }
    else
    {
        Write-Output "`nCheck whether Virtual device & Virtual machine are online or not"
        foreach ($InfraData in $ImportInfraList)
        {
            $CurrentInfraData = $InfraData
            $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
            $VMServiceName = $CurrentInfraData.VMServiceName
            $VMName = $CurrentInfraData.VMName
            
            Write-Output " Virtual device : $VirtualDeviceName"
            Write-Output " Virtual machine : $VMName"
            Write-Output " Service name : $VMServiceName`n"
            
            $AzureDevice = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
            if ($AzureDevice -eq $null -or $AzureDevice.Status -ne "Online") {
                throw "Virtual device ($VirtualDeviceName) either does not exist or in offline state"
            }
            
            $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
            If ($AzureVM -eq $null -or $AzureVM.Status -ne "ReadyRole") {
                throw "Virtual machine ($VMName) either does not exist or not in ready state"
            }
        }
        
        # Connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
        Write-Output "`nFetching Virtual machine's windows remote management uri"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VMName = $CurrentInfraData.VMName
            $VMServiceName = $CurrentInfraData.VMServiceName
            
            Write-Output " Virtual machine : $VMName"
            Write-Output " Service name : $VMServiceName`n"

            # Connecting to VM ($VMName) - ServiceName ($VMServiceName)
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
                throw "Unable to connect to Virtual machine ($VMName)" 
            }
            InlineScript {
                $CurrentInfraData = $Using:CurrentInfraData
                $VMWinRMUri = $Using:VMWinRMUri
                $CurrentInfraData.VMWinRMUri = $VMWinRMUri
            }
        }
        
        # Fetch existing ACR details
        $AvailableACRList = Get-AzureStorSimpleAccessControlRecord
        
        # Connect to azure vm to get the windows remote management uri which will be used while calling the Invoke-Command commandlet
        Write-Output "`nAttempting to create ACR, Volume Container & Volumes"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VMName = $data.VMName 
            $VMWinRMUri = $data.VMWinRMUri
            $AcrName = $VMName
            
            If ($CurrentInfraData.VMWinRMUri -ne $null)
            {
                Write-Output "`n Virtual machine : $VMName"
                Write-Output "  Installing AzCopy software and reading Initiator name of the Virtual machine"
                $VMIQN = InlineScript
                {
                    Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock {
                        param([Int]$SLEEPTIMEOUTSMALL)
                        
                        # Install AzCopy
                        $source = "http://aka.ms/downloadazcopy"
                        $destination = "C:\Users\Public\Downloads\AzCopy.msi" 
                        $AzCopyPath = "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
                        
                        Invoke-WebRequest $source -OutFile $destination
                        
                        # Wait till the file is downloaded
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
                        
                        # Starting the iSCSI service 
                        Start-Service msiscsi
                        Start-Sleep -s $SLEEPTIMEOUTSMALL
                        Set-Service msiscsi -StartupType "Automatic"
                        
                        # Getting initiator address
                        $IQN = (Get-InitiatorPort).NodeAddress
                        # Output of inlineScript
                        $IQN
                    } -Argumentlist $Using:SLEEPTIMEOUTSMALL
                }
                
                If ($VMIQN -eq $NUll) {
                    throw "  Unable to fetch the ACR of VM ($VMName)"
                }
                else 
                {
                    Write-Output "  Initiator name : $VMIQN`n"
                    Write-Output "  Adding ACR ($AcrName) to the resource"
                    If (($AvailableACRList | Where-Object { $_.Name -eq $AcrName }) -eq $null) 
                    {
                        $AcrCreation=New-AzureStorSimpleAccessControlRecord -ACRName $AcrName -IQNInitiatorName $VMIQN -WaitForComplete
                        If ($AcrCreation -eq $null) {
                            throw "  Unable to create ACR ($AcrName) InitiatorName ($VMIQN) to the resource"
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
                        $VolumeSizeInBytes = $Using:VolumeSizeInBytes
                        # Fetch ACR Details
                        $Acr = Get-AzureStorSimpleAccessControlRecord -ACRName $AcrName
                        
                        # Create Storage Account Credential
                        $sac = Get-AzureStorSimpleStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName -ErrorAction:SilentlyContinue 
                        If ($sac -eq $null) {
                            $sac = New-SSStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName -StorageAccountKey $VmAndSvaStorageAccountKey -UseSSL $false -ErrorAction:SilentlyContinue -WaitForComplete
                            if ($sac -eq $null) {
                                throw "  Unable to create a Storage Account Credential ($VmAndSvaStorageAccountName)"
                            }
                        }
                        
                        # Check whether VolumeContainer exists or not
                        Write-Output "  Attempting to create Volume Container ($VolumeContainerName)"
                        $volcon = Get-AzureStorSimpleDeviceVolumeContainer -Name $VolumeContainerName -DeviceName $VirtualDeviceName
                        If ($volcon -eq $null) {
                            $volcon = Get-AzureStorSimpleStorageAccountCredential -StorageAccountName $VmAndSvaStorageAccountName | New-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName -BandWidthRateInMbps 0 -WaitForComplete
                            If ($volcon -eq $null) {
                                throw "  Unable to create a Volume container ($VolumeContainerName) on Virtual device ($VirtualDeviceName)"
                            }
                            Write-Output "   Volume container ($VolumeContainerName) created successfully"
                        }
                        else {
                            Write-Output "   Volume container ($VolumeContainerName) already available"	
						}
                        
                        # Fetch existing volume list
                        $volumelist = Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName | Get-AzureStorSimpleDeviceVolume -DeviceName $VirtualDeviceName
                        
                        Write-Output "  Attempting to create Volumes in Volume Container ($VolumeContainerName)"
                        foreach ($VolumeName in $CurrentInfraData.VolumeList)
                        {
                            If (($volumelist.Count -eq 0) -or (($volumelist | Where-Object {$_.Name -match $VolumeName}) -eq $null)) 
                            {
                                $vol = Get-AzureStorSimpleDeviceVolumeContainer -DeviceName $VirtualDeviceName -VolumeContainerName $VolumeContainerName | New-AzureStorSimpleDeviceVolume -DeviceName $VirtualDeviceName -VolumeName $VolumeName -Size $VolumeSizeInBytes -AccessControlRecords $Acr -VolumeAppType PrimaryVolume -Online $True -EnableDefaultBackup $True -EnableMonitoring $False -WaitForComplete
                                if ($vol -eq $null) {
                                    throw "  Unable to create a Volume ($VolumeName) on Virtual device ($VirtualDeviceName)"
                                }
                                Write-Output "   Volume ($VolumeName) created successfully"
                            }
                            else {
                                Write-Output "   Volume ($VolumeName) already available"	
                            }
                        }
                    }
                }
            }
        }
        
        
        Write-Output "`nCreate the iSCSI target portal and mount the volumes, return the Drive letters of the mounted StorSimple volumes"
        foreach ($data in $ImportInfraList)
        {
            $CurrentInfraData = $data
            $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
            $VMServiceName = $CurrentInfraData.VMServiceName
            $VMName = $data.VMName
            $VMIQN = $CurrentInfraData.IQN
            $VMWinRMUri = $CurrentInfraData.VMWinRMUri
            
            Write-Output "`n Virtual device : $VirtualDeviceName"
            Write-Output " Virtual machine : $VMName"
            
            If ($VMIQN -ne $null)
            {
                # Fetching IQN of the SVA
                $SVAVm = Get-AzureVm -ServiceName $VirtualDeviceName -Name $VirtualDeviceName
                If ($SVAVm -eq $null) {
                    throw "  Unable to get Azure VM ($VMName)"
                }
                
                $SVAIp = $SVAVm.IpAddress
                If ($SVAIp -eq $null) {
                    throw "  Unable to get the IP Address of Azure VM ($VMName)"
                }
                
                $SVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                If ($SVA -eq $null) {
                    throw "  Unable to get the SVA ($VirtualDeviceName)"
                }
                
                $SVAIqn = $SVA.TargetIQN
                If ($SVAIqn -eq $null) {
                    throw "  Unable to fetch IQN of the SVA ($VirtualDeviceName)"
                }

                #create the iSCSI target portal and mount the volumes, return the drive letters of the mounted StorSimple volumes
                Write-Output "  Initating to mount StorSimple volumes on Virtual machine"
                $drives = InlineScript
                {
                    Invoke-Command -ConnectionUri $Using:VMWinRMUri -Credential $Using:VMCredential -ScriptBlock { 
                        param([String]$SVAIp, [String]$SVAIqn, [Int]$SLEEPTIMEOUTSMALL)
                            
                            $newportal = New-IscsiTargetPortal -TargetPortalAddress $SVAIp
                            If ($newportal -eq $null) {
                                throw "  Unable to create a new iSCSI target portal"
                            }
                            
                            $connection = Connect-IscsiTarget -NodeAddress $SVAIqn -IsPersistent $true -ErrorAction:SilentlyContinue
                            $sess = Get-IscsiSession
                            If ($sess -eq $null) {
                                throw "  Unable to connect the iSCSI target"
                            }
                            
                            Update-StorageProviderCache
                            Update-HostStorageCache
                            Start-Sleep -s $SLEEPTIMEOUTSMALL
                            
                            $drivescollection = (Get-Volume | where FileSystemLabel -match "STORSIMPLE*" | Select DriveLetter)
                            If ($drivescollection -eq $null)
                            {
                                Get-Disk  | Where-Object {$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsOffline $false
                                Get-Disk  | Where-Object {$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsReadOnly $false
                                Start-Sleep -s $SLEEPTIMEOUTSMALL
                                
                                # Initialize-Disk partition
                                $RawPartitionDisk = (Get-Disk | Where-Object {$_.Model -match 'STORSIMPLE*'})
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
							
                            # Output of InlineScript
                            ((Get-Volume | where FileSystemLabel -match "STORSIMPLE*" | Select DriveLetter).DriveLetter | Sort)
							
                    } -Argumentlist $Using:SVAIp,$Using:SVAIqn,$Using:SLEEPTIMEOUTSMALL
                }
                
                $DriveList = InlineScript
                {
                    $drives = $Using:drives
                    $list = @()
                    If ($drives.ToString().Contains(",") -eq $True) {
                        $list += $drives.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
                    }
                    else {
                        $list += $drives
                    }
					
                    # Output of InlineScript
                    $list
                }
                
                if ([string]::IsNullOrEmpty($DriveList) -eq $true) {
                    throw "  Unable to fetch StorSimple drives on VM ($VMName)"
                }
                elseIf ($DriveList.Count -ne $CurrentInfraData.VolumeList.Count) {
                    Write-Output "Drive list:"
                    $DriveList
                    Write-Output "Volume list:"
                    $CurrentInfraData.VolumeList
                    throw "Volumes and Drives are mismatched on Virtual device ($VirtualDeviceName)"
                }
                else {
                    InlineScript {
                        $DriveList = $Using:DriveList
                        $CurrentInfraData = $Using:CurrentInfraData
                        $CurrentInfraData.DriveList = $DriveList
                    }
                }
            }
            
            # Drive letters
            $driveletters = ($DriveList -Join ",")
            Write-Output "  Drives: $driveletters"
        }
	
        # Clear variable value
        $AzureCredential = $null
        $VMCredential = $null
	
        # Add checkpoint even If the runbook is suspended by an error, when the job is resumed, 
        # it will resume from the point of the last checkpoint set.
        Checkpoint-Workflow
	
        $AzureCredential = Get-AutomationPSCredential -Name "AzureCredential"
        $AzureAccount = Add-AzureAccount -Credential $AzureCredential
        $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName
        $AzureAccount = Add-AzureRmAccount -Credential $AzureCredential
        $AzureSubscription = Get-AzureRmSubscription –SubscriptionName $SubscriptionName | Select-AzureRmSubscription
        If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
        {
            throw "Unable to connect to Azure"
        }
        
        # Copy the blobs in the respective Drive
        # Do not remove the logging parameter from the AzCopy command as that will be used to get the progress
        # the script uses VM agent to run the AzCopy command, Invoke-Command doesn't work - it'll throw a system out of memory exception for large files
        Write-Output "`nInitiating to trigger AzCopy on all Virtual machines"
        InlineScript
        {
            $SourceBlob = $Using:SourceBlob
            $SourceStorageAccountKey = $Using:SourceStorageAccountKey
            $StorageAccountName = $Using:VmAndSvaStorageAccountName
            $StorageAccountKey = $Using:VmAndSvaStorageAccountKey
            $AutomationAccountName = $Using:AutomationAccountName
            $ResourceGroupName = $Using:ResourceGroupName 
            $ImportDataAzCopyInitiatedSVAsAssetName = $Using:ImportDataAzCopyInitiatedSVAsAssetName
            $ImportInfraList = $Using:ImportInfraList
            $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
            $AssetList = $Using:AssetList
            $ScriptContainer = $Using:ScriptContainer
            
            foreach ($data in $ImportInfraList)
            {
                $CurrentInfraData = $data
                $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
                $VMServiceName = $CurrentInfraData.VMServiceName
                $VMName = $CurrentInfraData.VMName
                $VolumeContainerName = $CurrentInfraData.ContainerName
                $DriveList = $CurrentInfraData.DriveList
                $VolumeList = $CurrentInfraData.VolumeList
                
                Write-Output "`n Virtual machine : $VMName"
                Write-Output "  Triggering AzCopy..."
                
                $AzCopyLoopIndex = 0
                $text = "cd 'C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\'"
                while ($AzCopyLoopIndex -lt $DriveList.Count)
                {
                    $DriveName = $DriveList[$AzcopyLoopIndex]
                    $drive = $DriveName + ":\"
                    $VolumeName = $VolumeList[$AzCopyLoopIndex]
                    If ($DriveList.Count -eq 1) {
                        $VolumeName = $VolumeList
                    }
                    
                    $logpath = "C:\Users\Public\Documents\AzCopy-" + $VolumeName + "-" + $DriveName + ".log"
                    $Journalfile = "C:\Users\Public\Documents\journalfolder-" + $VolumeName + "-" + $DriveName + "\"
                    
                    Write-Output "  Drive: $DriveName"
                    Write-Output "  VolumeName: $VolumeName"
                    Write-Output "  Log filepath: $logpath"
                    
                    $ScriptName = 'script-' + $VMName + "-$(Get-Date -format yyyyMMddhhmm).ps1"
                    
                    If ($SourceBlob.substring($SourceBlob.Length - 1) -eq "/") {
                        $ContainerSourceBlobUrl = $SourceBlob + $VolumeContainerName + '/' + $VolumeName + '/'
                    }
                    else {
                        $ContainerSourceBlobUrl = $SourceBlob + '/' + $VolumeContainerName + '/' + $VolumeName + '/'
                    }
                  
                    $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
                    if ($context -eq $null) {
                        throw "  Unable to create a new storage context"
                    }
                    
                    $container = Get-AzureStorageContainer -Name $ScriptContainer -Context $context -ErrorAction:SilentlyContinue
                    if ($container -eq $null) {
                        $newcontainer = New-AzureStorageContainer -Name $ScriptContainer -Context $context
                        if ($newcontainer -eq $null) {
                            throw "  Unable to create a container to store the script ($ScriptContainer)"
                        }
                    }
                    
                    $text += "`nIf ((Test-Path '$logpath') -eq `$false) `n{`n    .\AzCopy.exe /Source:$ContainerSourceBlobUrl /Dest:$drive /SourceKey:$SourceStorageAccountKey /Z:'$Journalfile' /S /V:'$logpath' `n}"
                    
                    $AzCopyLoopIndex += 1
                }
                    
                $Scriptfilename = "C:\file-" + $VMName + "-$(Get-Date -format yyyyMMddhhmm).ps1"
                $text | Set-Content $Scriptfilename 
                $uri = Set-AzureStorageBlobContent -Blob $ScriptName -Container $ScriptContainer -File $Scriptfilename -context $context -Force
                if ($uri -eq $null) {
                    throw "  Unable to Write script to the container ($Scriptfilename)"
                }
                $sasuri = New-AzureStorageBlobSASToken -Container $ScriptContainer -Blob $ScriptName -Permission r -FullUri -Context $context
                if ($sasuri -eq $null) {
                    throw "  Unable to get the URI for the script ($ScriptContainer)"
                }
                $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName       
                if ($AzureVM -eq $null) {
                    throw "  Unable to access the Azure VM ($VMName)"
                }
                $extension = $AzureVM.ResourceExtensionStatusList | Where-Object {$_.HandlerName -eq "Microsoft.Compute.CustomScriptExtension"}
                if ($extension -ne $null) {
                    Write-Output "  Uninstalling custom script extension" 
                    $result = Set-AzureVMCustomScriptExtension -Uninstall -ReferenceName CustomScriptExtension -VM $AzureVM | Update-AzureVM
                }
                       
                Write-Output "  Installing custom script extension" 
                $result = Set-AzureVMExtension -ExtensionName CustomScriptExtension -VM $AzureVM -Publisher Microsoft.Compute -Version 1.8 | Update-AzureVM    
                                     
                Write-Output "  Running script on the VM"         
                $result = Set-AzureVMCustomScriptExtension -VM $AzureVM -FileUri $sasuri -Run $ScriptName | Update-AzureVM
                
                # Update Import Infra Status
                $CurrentInfraData.IsAzCopyInitiated = $true
        		
                # Fetch DummySVAs asset variable
                $AssetList = (Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName)               
                If ($AssetList -ne $null -and ($AssetList | Where-Object {$_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}) -ne $null) {
                    # Set Import-AzCopyInitiatedSVAs asset data 
                    $AssetVal =  ($AssetList | Where-Object { $_.Name -match $ImportDataAzCopyInitiatedSVAsAssetName}).Value.Replace(",delimiter", "")
                    $AssetVal = $AssetVal + "," + $VirtualDeviceName + ",delimiter"
                    $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataAzCopyInitiatedSVAsAssetName -Encrypted $false -Value $AssetVal
                }
                else {
                    # Create Import-AzCopyInitiatedSVAs asset data 
                    $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataAzCopyInitiatedSVAsAssetName -Value ($VirtualDeviceName + ",delimiter") -Encrypted $false
                }
            }
        }
    }
    
    Write-Output "`n******************************** Result ******************************** "
    $ImportInfraList
}
