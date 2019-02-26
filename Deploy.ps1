<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template
#>
[CmdletBinding()]
param(
    # The subscription id where the template will be deployed.
    [Parameter(Mandatory)]
    [string]
    $SubscriptionId,

    # The resource group where the template will be deployed. Can be the name of an existing or a new resource group.
    [Parameter(Mandatory)]
    [string]
    $ResourceGroupName,

    # A location for the resource group (only used if the resource group does not already exist)
    [Parameter()]
    [string]
    $ResourceGroupLocation,

    # The deployment name.
    [Parameter(Mandatory)]
    [string]
    $DeploymentName,

    [Parameter(Mandatory)]
    [string]$VirtualMachineName,

    [Parameter(Mandatory)]
    [PSCredential]$VmAdminCredential,

    # Optional, path to the template file. Defaults to template.json.
    [string]
    $TemplateFilePath = "azuredeploy.jsonc",

    # Optional, path to the parameters file. Defaults to parameters.json. If file is not found, will prompt for parameter values based on template.
    [string]
    $ParametersFilePath = "parameters.jsonc"
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot

# select subscription
Write-Host "Selecting subscription '$SubscriptionId'"
Set-AzContext -SubscriptionId $SubscriptionId -Scope Process

# # You need to Register Resource Providers --once-- on your subscription.
# $ResourceProviders = @("microsoft.network","microsoft.compute","microsoft.storage")
# if($ResourceProviders.length) {
#     Write-Host "Registering resource providers"
#     foreach($ResourceProvider in $ResourceProviders) {
#         Write-Host "Registering resource provider '$ResourceProvider'"
#         Register-AzureRmResourceProvider -ProviderNamespace $ResourceProvider
#     }
# }

#Create or check for existing resource group
$ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$ResourceGroup) {
    Write-Host "Resource group '$ResourceGroupName' does not exist."
    if (!$ResourceGroupLocation) {
        Write-Warning "To create a new resource group, please provide a location."
        $ResourceGroupLocation = Read-Host "resourceGroupLocation"
    }
} else {
    Write-Host "Using existing resource group '$ResourceGroupName'"
}

$Parameters = @{
    Name                = $DeploymentName
    ResourceGroupName   = $ResourceGroupName
    TemplateFile        = Convert-Path $TemplateFilePath
    # parameters to the deployment itself
    AdminUsername       = $VmAdminCredential.UserName
    AdminPassword       = $VmAdminCredential.Password
    VirtualMachineName  = $VirtualMachineName
}

if (Test-Path $parametersFilePath) {
    $parameters.TemplateParameterFile = Convert-Path $parametersFilePath
}

# Start the deployment
Write-Host "Starting deployment..."
New-AzResourceGroupDeployment @Parameters
Pop-Location