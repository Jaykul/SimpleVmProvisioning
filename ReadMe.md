This is an attempt to uncover and document the simplest way to create encrypted VMs in Azure using the new 2.2 version of DiskEncryption which isn't well documented.


You should be able to create a new ResourceGroup containing a KeyVault for Disk Encryption keys, and a single VM, by just running the deployment. Currently, by running the deploy script. Assuming you are already logged in to the account _and Environment_ where you want to deploy, you just need to first define:

- Your VM local administrator `$Credential`
- Your Azure `$SubscriptionId`
- Your preferred Azure `$Location`

```PowerShell
deploy.ps1 -SubscriptionId $SubscriptionId -ResourceGroupName EncryptionSpike -ResourceGroupLocation $Location -DeploymentName comments -VirtualMachineName First -VmAdminCredential $Credential
```