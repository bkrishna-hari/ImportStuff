<<<<<<< HEAD
workflow ImportData-InfraSetup
{
    # Asset Names
    $ContainersAssetName = "ImportData-Containers"
    $ExcludeContainersAssetName = "ImportData-ExcludeContainers"
    $ImportDataSVAsAssetName = "ImportData-SVAs"
    $ImportDataConfigCompletedSVAsAssetName = "ImportData-ConfigrationCompletedDevices"
    
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
    Write-Output " "
    Write-Output "Excluded Container list:"
    $ExcludeContainerList
    
    # Final Include Container list
    $ContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $true})    
    $ValidContainerList = (($ContainerList).ContainerName) -Join ","
    
    # Fetch DummySVAs asset variable
    $AssetList = (Get-AzureAutomationVariable -AutomationAccountName $AutomationAccountName)
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
        $ConfigCompletedSVAs = ($AssetList | Where-Object { $_.Name -match $ImportDataConfigCompletedSVAsAssetName}).Value.Replace(",delimiter", "")
    }
    else {
        # Create asset data 
        $asset = New-AzureAutomationVariable -AutomationAccountName $AutomationAccountName -Name $ImportDataConfigCompletedSVAsAssetName -Value $ConfigCompletedSVAs -Encrypted $false
    }

    
    If ($variable -eq $null -and $asset -eq $null) {
        throw "Unable to create $ContainersAssetName asset"
    }
    elseIf ($variable -ne $null -and $asset -eq $null) {
        throw "Unable to set $ContainersAssetName asset"
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
        #$VNetLocation = $Using:VNetLocation
        #$SubnetName = $Using:SubnetName
    
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
            throw "Unable to get the Network Configuration file"
        }
         
        #check whether the network avialble or not
        $networkObj = $workingVnetConfig.GetElementsByTagName("VirtualNetworkSite") | Where-Object {$_.name -eq $VNetName}
        If ($networkObj -eq $null -or $networkObj.Count -eq 0) {
            throw "Virtual Network ($VNetName) not exists"
        }
        elseIf ($networkObj.Location -eq $null -or $networkObj.Location -eq "") {
            throw "Unable to read Virtual Network ($VNetName) Location"
        }
        elseIf ($networkObj.Subnets -eq $null -or $networkObj.Subnets.Subnet -eq $null -or $networkObj.Subnets.Subnet.Name -eq $null -or $networkObj.Subnets.Subnet.Name -eq "") {
            throw "Unable to read Virtual Network ($VNetName) Subnet Name"
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
            throw "Unable to get an image ($VMFamily) for VM"
        }
        
        # Read pending Import Infra Setup list 
        $PendingInfraList = ($ImportInfraList | Where-Object {$_.IsInfraCompleted -eq $false})
        
        $iterationLoopIndex = 0
        Write-Output "Attempting to create a SVAs & VMs"
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
        
        Write-Output "All SVAs & VMs are created successfully"
        Write-Output " "
        Write-Output " ********************************* Result *********************************"
        $ImportInfraList
    }
}
=======
<#
.DESCRIPTION
    This runbook reads Storage container details
    This runbook creates n-Virtual devices & n-Virtual machines.  Here n-value depends on number of storage containers.
	This runbook updates the device configuration of a StorSimple virtual device. 
     
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
    AutomationAccountName: The name of the Automation account name
    
.NOTES:
    Multi Factor Authentication must be disabled to execute this runbook

#>
workflow ImportData-InfraSetup
{
    # Asset Names
    $ContainersAssetName = "Import-Containers"
    $ImportDataSVAsAssetName = "Import-SVAs"
    $ImportDataConfigCompletedSVAsAssetName = "Import-ConfigrationCompletedDevices"
    $NewVirtualDeviceNameAssetName = "Import-NewVirtualDeviceName"
    $NewVMNameAssetName = "Import-NewVMName"
    $NewVMServiceNameAssetName = "Import-NewVMServiceName"
    
    # New Instance Name format
    $NewVirtualDeviceName = "importdatasva"
    $NewVMServiceName = "importdatavmservice"
    $NewVMName = "importdatavm"
    
    # VM inputs
    $VMFamily = "Windows Server 2012 R2 Datacenter"
    $VMInstanceSize = "Large"
    $VMPassword = "StorSim1"
    $VMUserName = "hcstestuser"
    
    # SVA inputs
    $VDDeviceAdministratorPassword = "zPXc&J8@"
    $VDSnapShotManagerPassword = "L*5F%Pkf,</Xq!"
    
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
    
    $VmAndSvaStorageAccountKey = Get-AutomationVariable –Name "StorageAccountKey" 
    if ($VmAndSvaStorageAccountKey -eq $null) 
    { 
        throw "The StorageAccountKey asset has not been created in the Automation service."  
    }
    $SourceStorageAccountKey = $VmAndSvaStorageAccountKey
    
    $AutomationAccountName = Get-AutomationVariable –Name "AutomationAccountName"
    if ($AutomationAccountName -eq $null) 
    { 
        throw "The AutomationAccountName asset has not been created in the Automation service."  
    }
    
    $VNetName = Get-AutomationVariable –Name "VNetName"
    if ($VNetName -eq $null) 
    { 
        throw "The VNetName asset has not been created in the Automation service."  
    }
    
    $VDServiceEncryptionKey = Get-AutomationVariable –Name "VDServiceEncryptionKey"
    if ($VDServiceEncryptionKey -eq $null)
    {
        throw "The VDServiceEncryptionKey asset has not been created in the Automation service."
    }
    
    # Connect to Azure
    Write-Output "Connecting to Azure"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName
    $AzureAccount = Add-AzureRmAccount -Credential $AzureCredential
    $AzureSubscription = Get-AzureRmSubscription -SubscriptionName $SubscriptionName | Set-AzureRmContext
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
    catch {
        throw "Unable to set the storage account for the subscription"
    }
    
    # Read automation account resource group
    Write-Output "Reading automation account's resource group name"
    try {
        $ResourceGroupName = (Get-AzureRmAutomationAccount | where AutomationAccountName -eq $AutomationAccountName).ResourceGroupName
    }
    catch {
        throw "Failed to read automation account's resource group"
    }
    
    # Fetch all asset info
    Write-Output "Fetching all existing assets info"
    try {
        $AssetList = Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName
    }
    catch {
        throw "The Automation account ($AutomationAccountName) is not found."
    }
		
    # Create new assets for Virtual Device Name, VMService Name & VM Name StartsWith
    If (($AssetList | Where-Object {$_.Name -match $NewVirtualDeviceNameAssetName}) -eq $null) {
        # Create NewVirtualDeviceName asset data 
        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $NewVirtualDeviceNameAssetName -Value $NewVirtualDeviceName -Encrypted $false
    }
	
    If (($AssetList | Where-Object {$_.Name -match $NewVMServiceNameAssetName}) -eq $null) {
        # Create NewVMServiceName asset data 
        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $NewVMServiceNameAssetName -Value $NewVMServiceName -Encrypted $false
    }
	
    If (($AssetList | Where-Object {$_.Name -match $NewVMNameAssetName}) -eq $null) {
        # Create NewVMNameAssetName asset data 
        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $NewVMNameAssetName -Value $NewVMName -Encrypted $false
    }
	
    $context = New-AzureStorageContext -StorageAccountName $VmAndSvaStorageAccountName -StorageAccountKey $VmAndSvaStorageAccountKey
    if ($context -eq $null) {
        throw "  Unable to create a new storage context"
    }

    # Attempting to read Volumes info by container name
    Write-Output "Attempting to fetch Container list in Storage account ($VmAndSvaStorageAccountName)"
    $ContainerCollection = (Get-AzureStorageContainer | select -ExpandProperty Name) -Join "," 
    If (($ContainerCollection -eq $null) -or ($ContainerCollection.Count -eq 0)) 
    {
        throw "No Container available in Storage account ($VmAndSvaStorageAccountName)"
    }
    else
    {
        $ContainerArrayList = @()
        If ($ContainerCollection.ToString().Contains(',') -eq $True) {
            $ContainerArrayList += $ContainerCollection.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) 
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
                    $VolumeName = $BlobName.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)[0].Trim()
                    
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
        # Output of InlineScript
        $ContainerVolumeData
    }
	
    if ($ContainerVolumeList -eq $null -or $ContainerVolumeList.Length -eq 0) {
        throw "No Blobs available in Storage account ($VmAndSvaStorageAccountName)"
    }
    
    # Final Exclude Container list
    $ExcludeContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $false}).ContainerName -Join ","
    if ($ExcludeContainerList -ne $null -and $ExcludeContainerList.Length -gt 0) {
        Write-Output "`nExcluded Container list: $($ExcludeContainerList -Join ',')"
    }
    
    # Final Include Container list
    $ContainerList = ($ContainerVolumeList | Where-Object {$_.HasBlobs -eq $true})    
    $ValidContainerList = (($ContainerList).ContainerName) -Join ","

    If (($AssetList | Where-Object {$_.Name -match $ContainersAssetName}) -ne $null) {
        # Set ImportData-Containers asset data
        $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ContainersAssetName -Encrypted $false -Value $ValidContainerList
    }
    else {
        # Create ImportData-Containers asset data 
        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ContainersAssetName -Value $ValidContainerList -Encrypted $false
    }
    
    $ConfigCompletedSVAs = ""
    If (($AssetList | Where-Object {$_.Name -match $ImportDataConfigCompletedSVAsAssetName}) -ne $null) {
		# Set ImportData-ConfigCompletedSVAs asset data
        $ConfigCompletedSVAs = ($AssetList | Where-Object { $_.Name -match $ImportDataConfigCompletedSVAsAssetName}).Value.Replace(",delimiter", "")
    }
    else {
        # Create ImportData-ConfigCompletedSVAs asset data
        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataConfigCompletedSVAsAssetName -Value $ConfigCompletedSVAs -Encrypted $false
    }
	
    # Clear variable value
    $AzureCredential = $null
	
    # Add checkpoint even If the runbook is suspended by an error, when the job is resumed, 
    # it will resume from the point of the last checkpoint set.
    Checkpoint-Workflow
	
    $AzureCredential = Get-AutomationPSCredential -Name "AzureCredential"
    $AzureAccount = Add-AzureAccount -Credential $AzureCredential
    $AzureSubscription = Select-AzureSubscription -SubscriptionName $SubscriptionName
    $AzureAccount = Add-AzureRmAccount -Credential $AzureCredential
    $AzureSubscription = Get-AzureRmSubscription -SubscriptionName $SubscriptionName | Set-AzureRmContext
    If (($AzureSubscription -eq $null) -or ($AzureAccount -eq $null))
    {
        throw "Unable to connect to Azure"
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
        $ResourceGroupName = $Using:ResourceGroupName
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
        Write-Output "Attempting to check whether Virtual network ($VNetName) available or not"  
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
        elseIf ($networkObj.Location -eq $null -or $networkObj.Location -eq "" -or $networkObj.Location.Length -eq 0) {
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
        Write-Output "Fetching latest VM Image"
        $VMImage = Get-AzureVMImage | where { $_.ImageFamily -eq $VMFamily } | sort PublishedDate -Descending | select -ExpandProperty ImageName -First 1
        if ($VMImage -eq $null) {
            throw "Unable to fetch an image ($VMFamily) for VM creation"
        }
        
        # Read pending Import Infra Setup list 
        $PendingInfraList = ($ImportInfraList | Where-Object {$_.IsInfraCompleted -eq $false})
        
        $iterationLoopIndex = 0    # DONOT CHANGE THIS INDEX
        Write-Output "Attempting to create new Virtual device & Virtual machine"
        while ($PendingInfraList -ne $null)
        {
            $iterationLoopIndex += 1
            If ($iterationLoopIndex -eq 1) {
                Write-Output "`n********************************* Infra-Setup initiated *********************************"
            } 
            else {
                $CheckIndex = ($iterationLoopIndex - 1)
                Write-Output "`n********************************* Checking - $CheckIndex *********************************"
            }
			
            foreach ($InfraData in $ImportInfraList)
            {
                Write-Output " "
                $CurrentInfraData = $InfraData
                $VirtualDeviceName = $CurrentInfraData.VirtualDeviceName
                $VMServiceName = $CurrentInfraData.VMServiceName
                $VMName = $CurrentInfraData.VMName
                
                # Check whether Virtual Device Configuration completed or not
                If ($ConfigCompletedSVAs -ne $null -and $ConfigCompletedSVAs.Contains($VirtualDeviceName) -and $CurrentInfraData.IsSVAConfigrationDone -eq $false) {
                    # Set SVA ($VirtualDeviceName) Configuration completed status
                    $CurrentInfraData.IsSVAConfigrationDone = $true
                }
                
                If ($iterationLoopIndex -eq 1) {
                    try {
                        Write-Output "Checking whether Virtual machine ($VMName) exists or not"
                        $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                    }
                    catch {
                        throw "Failed to check whether Virtual machine ($VMName) availability"
                    }
                }
                
                # Initiating to create a Large (InstanceSize) VM
                If ($AzureVM -eq $null) {
                    Write-Output "Initiating to create new Virtual machine ($VMName)"
                    $AzureVMConfig = New-AzureQuickVM -Windows -ServiceName $VMServiceName -Name $VMName -ImageName $VMImage -Password $VMPassword -AdminUserName $VMUserName -Location $VNetLocation -VNetName $VNetName -SubnetNames $SubnetName -InstanceSize $VMInstanceSize
                    If ($AzureVMConfig -eq $null) {
                        throw "Unable to create new Virtual machine ($VMName)"
                    }
                    
                    # Waiting for VM Creation to be initiated
                    $loopvariable=$true
                    while ($loopvariable) {
                        $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                        $loopvariable = ($AzureVM -eq $null)
                        Start-Sleep -s $SLEEPTIMEOUTSMALL
                    }
                    
                    Write-Output "Waiting for Virtual machine ($VMName) creation to be completed"
                    
                    # Set VM detault availablility status
                    $CurrentInfraData.IsVMAvailableDefault = $false
                }
                elseIf ($CurrentInfraData.IsVMAvailableDefault) {
                    Write-Output "Virtual machine ($VMName) is already created"
                    $CurrentInfraData.IsVMReady = $true
                }
                
                
                If ($iterationLoopIndex -eq 1) {
                    try {
                        Write-Output "Checking whether Virtual device ($VirtualDeviceName) exists or not"
                        $AzureSVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                    }
                    catch {
                        throw "Failed to check whether Virtual device ($VirtualDeviceName) availability"
                    }
                }
                
                # Initiating SVA Creation
                If ($AzureSVA -eq $null -and $CurrentInfraData.SVAJobID -eq $null)
                {
                    Write-Output "Initiating to create new Virtual device ($VirtualDeviceName)"
                    $DeviceJobId = New-AzureStorSimpleVirtualDevice -VirtualDeviceName $VirtualDeviceName -VirtualNetworkName $VNetName -StorageAccountName  $VmAndSvaStorageAccountName -SubNetName $SubnetName 
                    If ($DeviceJobId -eq $null) {
                        throw "Unable to create new Virtual device ($VirtualDeviceName)"
                    }
                
                    # Set DeviceJob value
                    $CurrentInfraData.SVAJobID = $DeviceJobId
                    Write-Output "Virtual device ($VirtualDeviceName) provisioning is started"
                    
                    # Set VM detault availablility status
                    $CurrentInfraData.IsSVAAvailableDefault = $false
                    
                    # Waitng for SVA provisioning to be initiated
                    Start-Sleep -s $SLEEPTIMEOUT
                }
                elseIf ($CurrentInfraData.IsSVAAvailableDefault) {
                    Write-Output "Virtual device ($VirtualDeviceName) is already created"
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
                        Write-Output "Virtual device ($VirtualDeviceName) provisioning ($progress %) in progress"
                        continue;
                    }
                    
                    if($SVAStatus -ne "Completed") {
                        throw "Virtual device ($VirtualDeviceName) creation status - $SVAStatus"    
                    }
                    else
                    {
                        Write-Output "Waiting for Virtual device creation to be completed"
                        $loopvariable=$true
                        while($loopvariable -eq $true)
                        {
                            Start-Sleep -s $SLEEPTIMEOUTSMALL
                            $VirtualDevice=  Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName
                            if($VirtualDevice.Status -eq "Online") {
                                $loopVariable=$false
                            }
                        }
                        
                        Write-Output "Virtual device ($VirtualDeviceName) is online"
                    }
                    
                    # Configure the Virtual device
                    $CurrentInfraData.IsSVAOnline = $true
                    $CurrentInfraData.IsSVAJobCompleted = $true
                }
                elseIf ($CurrentInfraData.IsSVAAvailableDefault -eq $false -and $CurrentInfraData.IsSVAOnline -eq $true) {
                    Write-Output "Virtual device ($VirtualDeviceName) is created successfully"
                }
                
                If ($CurrentInfraData.IsSVAJobCompleted -eq $true -and $CurrentInfraData.IsSVAConfigrationDone -eq $false)
                {
                    # Check whether Virtual device is in online or not
                    $SVA = Get-AzureStorSimpleDevice -DeviceName $VirtualDeviceName                     
                    If ($SVA -ne $null -and $SVA.Status -eq "Online")
                    {
                        # Configure the Virtual device
                        Write-Output "Waiting for SVA Configuration to be completed"
                        $configoutput=Set-AzureStorSimpleVirtualDevice -DeviceName $VirtualDeviceName -SecretKey $VDServiceEncryptionKey -AdministratorPassword $VDDeviceAdministratorPassword -SnapshotManagerPassword $VDSnapShotManagerPassword 
                        if($configoutput.TaskStatus -eq "Completed") {
                           Write-Output "Configuration of SVA ($VirtualDeviceName) successfully completed"
                           $CurrentInfraData.IsSVAConfigrationDone = $true
                            
                            $ConfigCompletedSVAs = $ConfigCompletedSVAs.Replace(",delimiter", "")
                            If ($ConfigCompletedSVAs.Count -eq 0){ $ConfigCompletedSVAs += $VirtualDeviceName + ",delimiter" }
                            else { $ConfigCompletedSVAs += "," + $VirtualDeviceName + ",delimiter" }
                            
							# Set/Update Asset value
                            $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataConfigCompletedSVAsAssetName -Encrypted $false -Value $ConfigCompletedSVAs
                        }
                        else {
                            throw "Configuration of SVA ($VirtualDeviceName) failed"
                        }
                    }
                }
                
                # Check whether Virtual machine is in ready state or not
                If ($CurrentInfraData.IsVMAvailableDefault -eq $false -and $CurrentInfraData.IsVMReady -eq $false)
                {
                    $AzureVM = Get-AzureVM -ServiceName $VMServiceName -Name $VMName
                    if($AzureVM -eq $null) {
                        throw "Virtual machine ($VMName) creation failed"
                    }
                    else
                    {
                        Write-Output "Virtual machine ($VMName) successfully created and waiting for Virtual machine to get ready"                        
                        $vmstatus = $AzureVM.Status
                        if( $AzureVM -ne $null -or $vmstatus -eq "ReadyRole") {
                            Write-Output "Virtual machine ($VMName) is in Ready state"
                            $CurrentInfraData.IsVMReady = $true
                        }
                    }
                }
                elseIf ($CurrentInfraData.IsVMAvailableDefault -eq $false -and $CurrentInfraData.IsVMReady -eq $true) {
                    Write-Output "Virtual machine ($VMName) is created successfully"
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
                    $AssetList = Get-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName
                    
                    $AvailableSVANames = ($AvailableSVAList).VirtualDeviceName -Join ","
                    $AvailableSVANames += -Join ",delimiter"
                    If (($AssetList | Where-Object {$_.Name -match $ImportDataSVAsAssetName}) -ne $null) {
                        # Set ImportData-ExcludeContainers asset data
                        $asset = Set-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataSVAsAssetName -Encrypted $false -Value $AvailableSVANames
                    }
                    else {
                        # Create ImportData-ExcludeContainers asset data 
                        $asset = New-AzureRmAutomationVariable -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $ImportDataSVAsAssetName -Value $AvailableSVANames -Encrypted $false
                    }
                }
            }
        }
        
        Write-Output "`nAll Virtual devices & Virtual machines are created successfully"

        Write-Output "`n ********************************* Result *********************************"
        $ImportInfraList
    }
}
>>>>>>> origin/master
