#Requires -Module Az.Resources
#Requires -Module Az.KeyVault
[OutputType("Microsoft.Azure.Commands.KeyVault.Models.PSKeyVault")]
[CmdletBinding()]
param(
    # Identifier of the Azure subscription to be used
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    # Name of the resource group to which the KeyVault belongs to.  A new resource group with this name will be created if one doesn't exist"
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    # Location of the KeyVault. Important note: Make sure the KeyVault and VMs to be encrypted are in the same region / location.
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Location,

    # Name of the KeyVault in which encryption keys are to be placed. A new vault with this name will be created if one doesn't exist
    # [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyVaultName = $($ResourceGroupName + "-dekv"),

    # Name of optional key encryption key in KeyVault. A new key with this name will be created if one doesn't exist
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$KeyEncryptionKeyName = "KeK",

    # Makes a key vaults (and it's keys and secrets) recoverable, enabling a 90 recycle-bin style deletion system
    [switch]$EnableSoftDelete
)

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

########################################################################################################################
# Section1:  Log-in to Azure and select appropriate subscription.
########################################################################################################################
Select-AzSubscription -SubscriptionId $SubscriptionId

########################################################################################################################
# Section2:  Create KeyVault or setup existing keyVault
########################################################################################################################

Try {
    $resGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
} Catch [System.ArgumentException] {
    Write-Host "Couldn't find resource group:  ($ResourceGroupName)"
    $resGroup = $null
}

#Create a new resource group if it doesn't exist
if (-not $resGroup) {
    Write-Host "Creating new resource group:  ($ResourceGroupName)"
    $resGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    Write-Host "Created a new resource group named $ResourceGroupName to place keyVault"
}

try {
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction SilentlyContinue
} catch [System.ArgumentException] {
    Write-Host "Couldn't find Key Vault: $KeyVaultName"
    $keyVault = $null
}

#Create a new vault if vault doesn't exist
if (-not $keyVault) {
    Write-Host "Creating new key vault:  ($KeyVaultName)"
    $keyVault = New-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -Sku Standard -Location $Location
    Write-Host "Created a new KeyVault named $KeyVaultName to store encryption keys"
}

Write-Host "Enabling DiskEncryption on KeyVault $KeyVaultName"
$null = Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -EnabledForDiskEncryption

$resource = Get-AzResource -ResourceId $keyVault.ResourceId

# Soft delete KeyVaults keep deleted secrets for 30 days, but also stick around after being deleted
if ($EnableSoftDelete) {
    Write-Host "Enabling Soft Delete on KeyVault $KeyVaultName"
    $resource.Properties | Add-Member -MemberType "NoteProperty" -Name "enableSoftDelete" -Value "true" -Force
    $null = Set-AzResource -resourceid $resource.ResourceId -Properties $resource.Properties -Force
}

# Enable ARM resource lock on KeyVault to prevent accidental key vault deletion
Write-Host "Adding resource lock on  KeyVault $KeyVaultName"
$lockNotes = "KeyVault may contain AzureDiskEncryption secrets required to boot encrypted VMs"
$null = New-AzResourceLock -LockLevel CanNotDelete -LockName "LockKeyVault" -ResourceName $keyVault.VaultName -ResourceType "Microsoft.KeyVault/vaults" -ResourceGroupName $ResourceGroupName -LockNotes $lockNotes -Force

try {
    $kek = Get-AzKeyVaultKey -VaultName $KeyVaultName -Name $KeyEncryptionKeyName -ErrorAction SilentlyContinue
} catch [Microsoft.Azure.KeyVault.KeyVaultClientException] {
    Write-Host "Couldn't find key encryption key named : $KeyEncryptionKeyName in Key Vault: $KeyVaultName"
    $kek = $null
}

if (-not $kek) {
    Write-Host "Creating new key encryption key named:$KeyEncryptionKeyName in Key Vault: $KeyVaultName"
    $kek = Add-AzKeyVaultKey -VaultName $KeyVaultName -Name $KeyEncryptionKeyName -Destination Software -ErrorAction SilentlyContinue
    Write-Host "Created  key encryption key named:$KeyEncryptionKeyName in Key Vault: $KeyVaultName"
}

########################################################################################################################
# Section3:  Output values that should be used while enabling encryption. Please note these down
########################################################################################################################

$keyVault | Add-Member -NotePropertyName KeyEncryptionKeyUrl -NotePropertyValue $kek.Key.Kid -PassThru

Write-Host "Please note down below details that will be needed to enable encryption on your VMs " -foregroundcolor Green
Write-Host "`t DiskEncryptionKeyVaultUrl: $($keyVault.VaultUri)" -foregroundcolor Green
Write-Host "`t DiskEncryptionKeyVaultId: $($keyVault.ResourceId)" -foregroundcolor Green
Write-Host "`t KeyEncryptionKeyURL: $($kek.Key.Kid)" -foregroundcolor Green
Write-Host "`t KeyEncryptionKeyVaultId: $($keyVault.ResourceId)" -foregroundcolor Green

########################################################################################################################
# To encrypt one VM in given resource group of the logged in subscritpion, assign $vmName and uncomment below section
########################################################################################################################
#$vmName = "Your VM Name"
#$allVMs = Get-AzVm -ResourceGroupName $ResourceGroupName -Name $vmName

########################################################################################################################
# To encrypt all the VMs in the given resource group of the logged in subscription uncomment below section
########################################################################################################################
#$allVMs = Get-AzVm -ResourceGroupName $ResourceGroupName

########################################################################################################################
# To encrypt all the VMs in the all the resource groups of the logged in subscription, uncomment below section
########################################################################################################################
#$allVMs = Get-AzVm

########################################################################################################################
# Loop through the selected list of VMs and enable encryption
########################################################################################################################

foreach ($vm in $allVMs) {
    if ($vm.Location.replace(' ', '').ToLower() -ne $keyVault.Location.replace(' ', '').ToLower()) {
        Write-Error "To enable AzureDiskEncryption, VM and KeyVault must belong to same subscription and same region. vm Location:  $($vm.Location.ToLower()) , keyVault Location: $($keyVault.Location.ToLower())"
        return
    }

    Write-Host "Encrypting VM: $($vm.Name) in ResourceGroup: $($vm.ResourceGroupName) " -foregroundcolor Green
    if (-not $kek) {
        Set-AzVMDiskEncryptionExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -DiskEncryptionKeyVaultUrl $keyVault.VaultUri -DiskEncryptionKeyVaultId $keyVault.ResourceId -VolumeType 'All'
    } else {
        Set-AzVMDiskEncryptionExtension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name -DiskEncryptionKeyVaultUrl $keyVault.VaultUri -DiskEncryptionKeyVaultId $keyVault.ResourceId -KeyEncryptionKeyUrl $kek.Key.Kid -KeyEncryptionKeyVaultId $keyVault.ResourceId -VolumeType 'All'
    }
    # Show encryption status of the VM
    Get-AzVmDiskEncryptionStatus -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name
}
