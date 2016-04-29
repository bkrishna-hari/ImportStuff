workflow ImportData-InfraSetup
{
    # Asset Names
    $ContainersAssetName = "ImportData-Containers"
    $ExcludeContainersAssetName = "ImportData-ExcludeContainers"
    $ImportDataSVAsAssetName = "ImportData-SVAs"
    $ImportDataConfigCompletedSVAsAssetName = "ImportData-ConfigrationCompletedDevices"
	$NewVirtualDeviceNameAssetName = "ImportData-NewVirtualDeviceName"
	$NewVMNameAssetName = "ImportData-NewVMName"
	$NewVMServiceNameAssetName = "ImportData-NewVMServiceName"
    
    #New Instance Name format 
    $NewVirtualDeviceName = "importsva"
    $NewVMServiceName = "importvmservice"
    $NewVMName = "importvm"
    
    # VM inputs
    $VMFamily = "Windows Server 2012 R2 Datacenter"
    $VMInstanceSize = "Large"
    $VMPassword = "StorSim1"
    $VMUserName = "hcstestuser"
    
    # SVA inputs
    $VDDeviceAdministratorPassword = "StorSimple123"
    $VDSnapShotManagerPassword = "VDSnapshotMan1"
    
    # TImeout inputs 
    $SLEEPTIMEOUT = 60
    $SLEEPTIMEOUTSMALL = 5
    $SLEEPTIMEOUTLARGE = 600
    
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
    
    $VNetName = Get-AutomationVariable –Name "ImportData-VNetName"
    if ($VNetName -eq $null) 
    { 
        throw "The VNetName asset has not been created in the Automation service."  
    }
    
    $VDServiceEncryptionKey = Get-AutomationVariable –Name "ImportData-VDServiceEncryptionKey"
    if ($VDServiceEncryptionKey -eq $null)
    {
        throw "The VDServiceEncryptionKey asset has not been created in the Automation service."
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
    
    # Fetch all assets info
    $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)
		
	# Create an asset for new VirtualDevice Name, VM Name & VMService Name format
	If (($AssetList | Where-Object {$_.Name -match $NewVirtualDeviceNameAssetName}) -ne $null) {
        # Set ImportData-NewVirtualDeviceNameAssetName asset data
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVirtualDeviceNameAssetName -Encrypted $false -Value $NewVirtualDeviceName
    }
    else {
        # Create ImportData-NewVirtualDeviceNameAssetName asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVirtualDeviceNameAssetName -Value $NewVirtualDeviceName -Encrypted $false
    }
	
	If (($AssetList | Where-Object {$_.Name -match $NewVMServiceNameAssetName}) -ne $null) {
        # Set ImportData-NewVMServiceNameAssetName asset data
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVMServiceNameAssetName -Encrypted $false -Value $NewVMServiceName
    }
    else {
        # Create ImportData-NewVMServiceNameAssetName asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVMServiceNameAssetName -Value $NewVMServiceName -Encrypted $false
    }
	
	If (($AssetList | Where-Object {$_.Name -match $NewVMNameAssetName}) -ne $null) {
        # Set ImportData-NewVMNameAssetName asset data
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVMNameAssetName -Encrypted $false -Value $NewVMName
    }
    else {
        # Create ImportData-NewVMNameAssetName asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $NewVMNameAssetName -Value $NewVMName -Encrypted $false
    }

    # Attempting to read Volumes info by container name
    Write-Output "Attempting to fetch Containers in Storage Account ($VmAndSvaStorageAccountName)"
    $ContainerCollection = (Get-AzureStorageContainer | select -ExpandProperty Name) -Join "," 
    If (($ContainerCollection -eq $null) -or ($ContainerCollection.Count -eq 0)) 
    {
        throw "No Container available in Storage Account($VmAndSvaStorageAccountName)"
    }
    else
    {
        $ContainerArrayList = @()
        If ($ContainerCollection.ToString().Contains(',') -eq $True) {
            $ContainerArrayList += $ContainerCollection.Split(",").Trim() 
        }
        else {
            $ContainerArrayList += $ContainerCollection
        }
    }
    
    $ContainerVolumeList = @()
    $ContainerVolumeList = InlineScript
    {
        $ContainerVolumeData = @()
        $ContainerArrayList = $Using:ContainerArrayList
        
        Write-Output "Attempting to read list of blobs"
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
                $CurrentContainerData.HasBlobs = $false
                continue;
                #throw "No blob(s) available in Container ($ContainerName)"
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
        }
        # Output for InlineScript
        $ContainerVolumeData
    }
    
    # Final Exclude Container list
    $ExcludeContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $false}).ContainerName -Join ","
    #Write-Output " "
    Write-Output "`n Excluded Container list:"
    $ExcludeContainerList
    
    # Final Include Container list
    $ContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $true})    
    $ValidContainerList = (($ContainerList).ContainerName) -Join ","
    
    If (($AssetList | Where-Object {$_.Name -match $ExcludeContainersAssetName}) -ne $null) {
        # Set ImportData-ExcludeContainers asset data
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ExcludeContainersAssetName -Encrypted $false -Value $ExcludeContainerList
    }
    else {
        # Create ImportData-ExcludeContainers asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ExcludeContainersAssetName -Value $ExcludeContainerList -Encrypted $false
    }

    If (($AssetList | Where-Object {$_.Name -match $ContainersAssetName}) -ne $null) {
        # Set ImportData-Containers asset data
        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ContainersAssetName -Encrypted $false -Value $ValidContainerList
    }
    else {
        # Create ImportData-Containers asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ContainersAssetName -Value $ValidContainerList -Encrypted $false
    }
    
    $ConfigCompletedSVAs = ""
    If (($AssetList | Where-Object {$_.Name -match $ImportDataConfigCompletedSVAsAssetName}) -ne $null) {
		# Set ImportData-ConfigCompletedSVAs asset data
        $ConfigCompletedSVAs = ($AssetList | Where-Object { $_.Name -match $ImportDataConfigCompletedSVAsAssetName}).Value.Replace(",delimiter", "")
    }
    else {
        # Create ImportData-ConfigCompletedSVAs asset data
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataConfigCompletedSVAsAssetName -Value $ConfigCompletedSVAs -Encrypted $false
    }
    
    Write-Output "Create ImportData-InfraSetup object"
    $InfraLoopIndex = 1
    $ImportInfraList = @()
    foreach ($data in $ContainerList)
    {
        $InfraVirtualDeviceName = ($NewVirtualDeviceName + $InfraLoopIndex)
        $InfraVMServiceName = ($NewVMServiceName + $InfraLoopIndex)
        $InfraVMName = ($NewVMName + $InfraLoopIndex)
        
        $InfraProp=@{ VirtualDeviceName=$InfraVirtualDeviceName; VMName=$InfraVMName; VMServiceName=$InfraVMServiceName; IsSVAOnline=$false; IsVMReady=$false; IsSVAAvailableDefault=$true; IsVMAvailableDefault=$true; SVAJobID=$null; IsSVAJobCompleted=$false; IsSVAConfigrationDone=$false; IsInfraCompleted=$false }
        $NewInfraObj = New-Object PSObject -Property $InfraProp
        $ImportInfraList += $NewInfraObj
        
        $InfraLoopIndex += 1
    }
    
    InlineScript
    {
        $ImportInfraList = $Using:ImportInfraList
        
        $VNetName = $Using:VNetName    
        $VMFamily=$Using:VMFamily
        $VMInstanceSize = $Using:VMInstanceSize
        $VMUserName = $Using:VMUserName 
        $VMPassword = $Using:VMPassword
        $VmAndSvaStorageAccountName = $Using:VmAndSvaStorageAccountName
        $SubscriptionName = $Using:SubscriptionName
        $AutomationAccountName = $Using:AutomationAccountName
        $ImportDataSVAsAssetName = $Using:ImportDataSVAsAssetName
        $ImportDataConfigCompletedSVAsAssetName = $Using:ImportDataConfigCompletedSVAsAssetName
        $AssetList = $Using:AssetList
        $ConfigCompletedSVAs = $Using:ConfigCompletedSVAs
        
        $ResourceName = $Using:ResourceName 
        $StorSimRegKey = $Using:StorSimRegKey 
        $VDServiceEncryptionKey = $Using:VDServiceEncryptionKey  
        $VDDeviceAdministratorPassword = $Using:VDDeviceAdministratorPassword 
        $VDSnapShotManagerPassword = $Using:VDSnapShotManagerPassword 
        
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
        $SLEEPTIMEOUTSMALL = $Using:SLEEPTIMEOUTSMALL  
        $SLEEPTIMEOUTLARGE = $Using:SLEEPTIMEOUTLARGE
        
        # Fetching the virtual network details
        Write-Output "Attempting to check whether Virtual Network ($VNetName) available or not"  
        try {
            $currentVNetConfig = Get-AzureVNetConfig        
            If ($currentVNetConfig -ne $null) {
                [xml]$workingVnetConfig = $currentVNetConfig.XMLConfiguration
            }
        }
        catch {
            throw "Unable to fetch the network configuration file"
        }
         
        #check whether the network avialble or not
        $networkObj = $workingVnetConfig.GetElementsByTagName("VirtualNetworkSite") | Where-Object {$_.name -eq $VNetName}
        If ($networkObj -eq $null -or $networkObj.Count -eq 0) {
            throw "Virtual network ($VNetName) not exists"
        }
        elseIf ($networkObj.Location -eq $null -or $networkObj.Location -eq "" -or -or $networkObj.Location.Length -eq 0) {
            throw "Unable to read virtual network ($VNetName) Location"
        }
        elseIf ($networkObj.Subnets -eq $null -or $networkObj.Subnets.Subnet -eq $null -or $networkObj.Subnets.Subnet.Name -eq $null -or $networkObj.Subnets.Subnet.Name -eq "" -or $networkObj.Subnets.Subnet.Name.Length -eq 0) {
            throw "Unable to read virtual network ($VNetName) Subnet Name"
        }
    
        # Virtual Network data
        $VNetLocation = $networkObj.Location
        $SubnetName = $networkObj.Subnets.Subnet.Name
        Write-Output "VNetLocation: $VNetLocation"
        Write-Output "SubnetName: $SubnetName"
        
        #Fetching Windows Server 2012 R2 Datacenter latest image
        Write-Output "Fetching VM Image"
        $VMImage = Get-AzureVMImage | where { $_.ImageFamily -eq $VMFamily } | sort PublishedDate -Descending | select -ExpandProperty ImageName -First 1
        if ($VMImage -eq $null) {
            throw "Unable to fetch an image ($VMFamily) for VM creation"
        }
        
        # Read pending Import Infra Setup list 
        $PendingInfraList = ($ImportInfraList | Where-Object {$_.IsInfraCompleted -eq $false})
        
        $iterationLoopIndex = 0
        Write-Output "Attempting to create a SVA & VM"
        while ($PendingInfraList -ne $null)
        {
            Write-Output " "
            $iterationLoopIndex += 1
            If ($iterationLoopIndex -eq 1) {
                Write-Output "********************************* Infra-Setup Initiated *********************************"
            } 
            else {
                $CheckIndex = ($iterationLoopIndex - 1)
                Write-Output "********************************* Checking - $CheckIndex *********************************"
            }
			
            foreach ($InfraData in $ImportInfraList)
            {
                Write-Output " "
                $CurrentInfraData = $InfraData
                $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
                $VMServiceName = $CurrentInfraData.VMServiceName
                $VMName = $CurrentInfraData.VMName
                
                # Device Configuration Setting skipped if Virtual Device exists
                If ($ConfigCompletedSVAs -ne $null -and $ConfigCompletedSVAs.Contains($VirtualDeviceName) -and $CurrentInfraData.IsSVAConfigrationDone -eq $false) {
                    #Write-Output "SVA ($VirtualDeviceName) Configuration skipped"
                    $CurrentInfraData.IsSVAConfigrationDone = $true 
                }
                
                try {
                    $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                }
                catch {
                    throw "Failed to check whether VM ($VMName) exists or not"
                }
                
                #Initiating to create a Large (InstanceSize) VM
                If ($AzureVM -eq $null) {
                    Write-Output "Initiating VM ($VMName) creation"                    
                    $AzureVMConfig = New-AzureQuickVM -Windows -ServiceName $VMServiceName -Name $VMName -ImageName $VMImage -Password $VMPassword -AdminUserName $VMUserName -Location $VNetLocation -VNetName $VNetName -SubnetNames $SubnetName -InstanceSize $VMInstanceSize
                    If ($AzureVMConfig -eq $null) {
                        throw "Unable to create VM ($VMName)"
                    }
                    
                    # Waiting for VM Creation to be initiated
                    $loopvariable=$true
                    while ($loopvariable) {
                        $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                        $loopvariable = ($AzureVM -eq $null)
                        Start-Sleep -s $SLEEPTIMEOUTSMALL
                    }
                    
                    Write-Output "Waiting for VM($VMName) creation to be completed"
                    
                    # Set VM detault availablility status
                    $CurrentInfraData.IsVMAvailableDefault = $false
                }
                elseIf ($CurrentInfraData.IsVMAvailableDefault) {
                    Write-Output "VM ($VMName) is already available"
                    $CurrentInfraData.IsVMReady = $true
                }
                
                
                try {
                    $AzureSVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                }
                catch {
                    throw "Failed to check whether SVA ($VirtualDeviceName) exists or not"
                }
                
                # Initiating SVA Creation
                If ($AzureSVA -eq $null -and $CurrentInfraData.SVAJobID -eq $null)
                {
                    Write-Output "Initiating SVA ($VirtualDeviceName) creation"
                    $DeviceJobId = New-AzureStorSimpleVirtualDevice -VirtualDeviceName $VirtualDeviceName -VirtualNetworkName $VNetName -StorageAccountName  $VmAndSvaStorageAccountName -SubNetName $SubnetName 
                    If ($DeviceJobId -eq $null) {
                        throw "Unable to create SVA ($VirtualDeviceName)"
                    }
                
                    # Set DeviceJob value
                    $CurrentInfraData.SVAJobID = $DeviceJobId
                    Write-Output "SVA ($VirtualDeviceName) provisioning is started"
                    
                    # Set VM detault availablility status
                    $CurrentInfraData.IsSVAAvailableDefault = $false
                    
                    # Waitng for SVA provisioning to be initiated
                    Start-Sleep -s $SLEEPTIMEOUT
                }
                elseIf ($CurrentInfraData.IsSVAAvailableDefault) {
                    Write-Output "SVA ($VirtualDeviceName) is already created"
                    $CurrentInfraData.IsSVAOnline = $true
                    $CurrentInfraData.IsSVAJobCompleted = $true
                }
                
                If ($CurrentInfraData.SVAJobID -ne $null -and $CurrentInfraData.IsSVAOnline -eq $false)
                {
                    # Set Device JobID
                    $DeviceJobId = $CurrentInfraData.SVAJobID
                    
                    $loopvariable=$true
                    $DeviceCreationOutput=$null
                    
                    # Fetch job status info
                    $DeviceCreationOutput = Get-AzureStorSimpleJob -InstanceId $DeviceJobId
                    $SVAStatus = $DeviceCreationOutput.Status
                    $progress = $DeviceCreationOutput.Progress
                    If ($SVAStatus -eq "Running") {
                        Write-Output "SVA ($VirtualDeviceName) provisioning ($progress %) is in progress"
                        continue;
                    }
                    
                    if($SVAStatus -ne "Completed") {
                        throw "SVA ($VirtualDeviceName) creation status - $SVAStatus"    
                    }
                    else
                    {
                        Write-Output "Waiting for SVA creation to be initiate"
                        $loopvariable=$true
                        while($loopvariable -eq $true)
                        {
                            Start-Sleep -s $SLEEPTIMEOUTSMALL
                            $VirtualDevice=  Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                            if($VirtualDevice.Status -eq "Online") {
                                $loopVariable=$false
                            }
                        }
                        
                        Write-Output "SVA ($VirtualDeviceName) is online"
                    }
                    
                    #configure the SVA
                    $CurrentInfraData.IsSVAOnline = $true
                    $CurrentInfraData.IsSVAJobCompleted = $true
                }
                elseIf ($CurrentInfraData.IsSVAAvailableDefault -eq $false -and $CurrentInfraData.IsSVAOnline -eq $true) {
                    Write-Output "SVA ($VirtualDeviceName) is created successfully"
                }
                
                If ($CurrentInfraData.IsSVAJobCompleted -eq $true -and $CurrentInfraData.IsSVAConfigrationDone -eq $false)
                {
                    # Check whether Virtual device is in online or not
                    $SVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName                     
                    If ($SVA -ne $null -and $SVA.Status -eq "Online")
                    {
                        #configure the SVA
                        Write-Output "Waiting for SVA Configuration to be completed"
                        $configoutput=Set-AzureStorSimpleVirtualDevice -DeviceName $VirtualDeviceName -SecretKey $VDServiceEncryptionKey -AdministratorPassword $VDDeviceAdministratorPassword -SnapshotManagerPassword $VDSnapShotManagerPassword 
                        if($configoutput.TaskStatus -eq "Completed") {
                           Write-Output "Configuration of SVA ($VirtualDeviceName) successfully completed"
                           $CurrentInfraData.IsSVAConfigrationDone = $true
                           
                           #If (($AssetList | Where-Object {$_.Name -match $ImportDataConfigCompletedSVAsAssetName}) -ne $null) {
                                #$ConfigCompletedSVAs = ($AssetList | Where-Object { $_.Name -match $ImportDataConfigCompletedSVAsAssetName}).Value.Replace(",delimiter", "")
                            
                            $ConfigCompletedSVAs = $ConfigCompletedSVAs.Replace(",delimiter", "")
                            If ($ConfigCompletedSVAs.Count -eq 0){ $ConfigCompletedSVAs += $VirtualDeviceName + ",delimiter" }
                            else { $ConfigCompletedSVAs += "," + $VirtualDeviceName + ",delimiter" }
                            # Set/Update Asset value
                            $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataConfigCompletedSVAsAssetName -Encrypted $false -Value $ConfigCompletedSVAs
                            #}
                        }
                        else {
                            throw "Configuration of SVA ($VirtualDeviceName) failed"
                        }
                    }
                }
                
                # Check whether VM is in ready state or not
                If ($CurrentInfraData.IsVMAvailableDefault -eq $false -and $CurrentInfraData.IsVMReady -eq $false)
                {
                    $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                    if($AzureVM -eq $null) {
                        throw "VM ($VMName) creation failed"
                    }
                    else
                    {
                        Write-Output "VM ($VMName) successfully created and waiting for VM to get ready"                        
                        $vmstatus = $AzureVM.Status
                        if( $AzureVM -ne $null -or $vmstatus -eq "ReadyRole") {
                            Write-Output "VM ($VMName) is in Ready state"
                            $CurrentInfraData.IsVMReady = $true
                        }
                    }
                }
                elseIf ($CurrentInfraData.IsVMAvailableDefault -eq $false -and $CurrentInfraData.IsVMReady -eq $true) {
                    Write-Output "VM ($VMName) is created successfully"
                }
                
                # Set Infra Setup status
                $CurrentInfraData.IsInfraCompleted = ($CurrentInfraData.IsSVAOnline -and $CurrentInfraData.IsVMReady -and $CurrentInfraData.IsSVAConfigrationDone)
            }
            
            # Read pending Import Infra Setup list 
            $PendingInfraList = ($ImportInfraList | Where-Object {$_.IsInfraCompleted -eq $false})
            
            If ($PendingInfraList -ne $null) {
                # Waitng for SVA creation to be initiated
                Write-Output "Waiting for sleep ($SLEEPTIMEOUTLARGE seconds) to be finished"
                Start-Sleep -s $SLEEPTIMEOUTLARGE
            }
            else {
                # Read Completed Infra Systems
                $AvailableSVAList = ($ImportInfraList | Where-Object {$_.IsInfraCompleted -eq $true})
    
                If ($AvailableSVAList -ne $null)
                {
                    # Fetch DummySVAs asset variable
                    $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)
                    
                    $AvailableSVANames = ($AvailableSVAList).VirtualDeviceName -Join ","
                    $AvailableSVANames += -Join ",delimiter"
                    If (($AssetList | Where-Object {$_.Name -match $ImportDataSVAsAssetName}) -ne $null) {
                        # Set ImportData-ExcludeContainers asset data
                        $asset = Set-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataSVAsAssetName -Encrypted $false -Value $AvailableSVANames
                    }
                    else {
                        # Create ImportData-ExcludeContainers asset data 
                        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataSVAsAssetName -Value $AvailableSVANames -Encrypted $false
                    }
                }
            }
        }
        
        Write-Output "`n All SVAs & VMs are created successfully"
        #Write-Output " "
        Write-Output "`n ********************************* Result *********************************"
        $ImportInfraList
    }
}